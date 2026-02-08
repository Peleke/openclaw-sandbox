"""MCP server exposing sandbox management tools to LLM agents.

Runs over stdio transport.  Entry point: ``sandbox-mcp`` (console script).

Implementation functions are plain callables for testability.  They are
registered with FastMCP via ``mcp.tool()`` at the bottom of the file.
"""

from __future__ import annotations

import shutil
import subprocess

from ._capture import CapturedExec, _truncate, make_capture_console, suppress_stdout
from .dashboard import run_dashboard_sync
from .lima_manager import LimaError, LimaManager
from .models import SandboxProfile
from .profile import load_profile
from .reporting import (
    GATEWAY_BASE,
    GATEWAY_PORT,
    get_agent_identity,
    get_gateway_password,
    get_learning_stats,
)
from .validation import validate_profile

VM_EXEC_TIMEOUT = 120


# ── helpers ──────────────────────────────────────────────────────────────


def _require_limactl() -> None:
    """Raise if ``limactl`` is not on PATH."""
    if shutil.which("limactl") is None:
        raise RuntimeError(
            "limactl not found. Install Lima: brew install lima"
        )


def _load_profile_safe() -> SandboxProfile:
    """Load the profile, returning a default on failure."""
    try:
        return load_profile()
    except Exception:
        return SandboxProfile()


# ── tool implementations ────────────────────────────────────────────────


def sandbox_status() -> dict:
    """Return sandbox VM status, profile summary, and interop data.

    Read-only. Returns VM state, profile info, agent identity,
    learning stats, and gateway URLs.
    """
    _require_limactl()
    lima = LimaManager()
    profile = _load_profile_safe()

    result: dict = {"vm": None, "profile": {}, "gateway": {}}

    # VM info
    info = lima.vm_info()
    if info:
        result["vm"] = {
            "name": info.get("name", ""),
            "status": info.get("status", "unknown"),
            "arch": info.get("arch", ""),
            "cpus": info.get("cpus"),
            "memory": info.get("memory"),
            "disk": info.get("disk"),
        }

    # Profile summary
    result["profile"] = {
        "openclaw_mount": profile.mounts.openclaw or None,
        "vault": profile.mounts.vault or None,
        "secrets": profile.mounts.secrets or None,
        "yolo": profile.mode.yolo,
        "yolo_unsafe": profile.mode.yolo_unsafe,
        "docker": not profile.mode.no_docker,
        "memgraph": profile.mode.memgraph,
        "resources": f"{profile.resources.cpus} CPUs / {profile.resources.memory} / {profile.resources.disk}",
    }

    # Gateway
    gw_password = get_gateway_password(profile)
    result["gateway"] = {
        "base_url": GATEWAY_BASE,
        "port": GATEWAY_PORT,
        "dashboard": GATEWAY_BASE,
        "authenticated_url": f"{GATEWAY_BASE}/?password={gw_password}" if gw_password else None,
        "green_dashboard": f"{GATEWAY_BASE}/__openclaw__/api/green/dashboard",
        "learning_dashboard": f"{GATEWAY_BASE}/__openclaw__/api/learning/dashboard",
    }

    # Agent identity
    identity = get_agent_identity()
    if identity:
        result["agent"] = identity

    # Learning stats (only if VM is running)
    if info and info.get("status") == "Running":
        stats = get_learning_stats()
        if stats:
            result["learning"] = stats

    return result


def sandbox_up() -> dict:
    """Provision or reprovision the sandbox VM.

    Long-running (1-5 minutes). Creates the VM if it doesn't exist,
    starts it if stopped, and runs the Ansible playbook.
    Returns captured console output and exit code.
    """
    _require_limactl()

    from .bootstrap import find_bootstrap_dir
    from .orchestrator import orchestrate_up

    profile = load_profile()
    bootstrap_dir = find_bootstrap_dir(profile)

    cap = make_capture_console()

    # Temporarily replace the orchestrator's module-level console
    import sandbox_cli.orchestrator as orch_mod

    original_console = orch_mod.console
    orch_mod.console = cap
    try:
        with suppress_stdout():
            rc = orchestrate_up(profile, bootstrap_dir)
    finally:
        orch_mod.console = original_console

    output = cap.file.getvalue()
    return {
        "exit_code": rc,
        "output": _truncate(output),
    }


def sandbox_down() -> dict:
    """Stop the sandbox VM (force kill).

    Fast operation. Returns success or error.
    """
    _require_limactl()
    lima = LimaManager()

    if not lima.vm_exists():
        return {"status": "not_found", "message": "VM does not exist."}

    lima.stop(force=True)
    return {"status": "stopped", "message": "VM stopped."}


def sandbox_destroy() -> dict:
    """Delete the sandbox VM entirely.

    Destructive. Force-stops and deletes the VM.
    """
    _require_limactl()
    lima = LimaManager()

    if not lima.vm_exists():
        return {"status": "not_found", "message": "VM does not exist."}

    lima.delete()
    return {"status": "deleted", "message": "VM deleted."}


def sandbox_exec(command: str, timeout: int = VM_EXEC_TIMEOUT) -> dict:
    """Execute a command inside the sandbox VM.

    Returns stdout, stderr, and exit_code. Timeout defaults to 120s.
    This is the primary tool for agents to interact with the VM.
    """
    if not command or not command.strip():
        return {"error": "Command must not be empty."}

    _require_limactl()
    lima = LimaManager()

    if not lima.vm_exists():
        return {"error": "VM does not exist. Run sandbox_up first."}

    status = lima.vm_status()
    if status != "Running":
        return {"error": f"VM is not running (status: {status}). Run sandbox_up first."}

    timeout = max(1, min(timeout, 600))

    try:
        proc = subprocess.run(
            ["limactl", "shell", lima.vm_name, "--", "bash", "-c", command],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        result = CapturedExec(
            stdout=proc.stdout,
            stderr=proc.stderr,
            exit_code=proc.returncode,
        )
    except subprocess.TimeoutExpired:
        return {
            "error": f"Command timed out after {timeout}s.",
            "stdout": "",
            "stderr": "",
            "exit_code": -1,
        }

    return {
        "stdout": _truncate(result.stdout),
        "stderr": _truncate(result.stderr),
        "exit_code": result.exit_code,
    }


def sandbox_validate() -> dict:
    """Validate the current sandbox profile.

    Returns validation result with ok status, errors, and warnings.
    """
    try:
        profile = load_profile()
    except Exception as exc:
        return {"ok": False, "errors": [str(exc)], "warnings": []}

    result = validate_profile(profile)
    return {
        "ok": result.ok,
        "errors": list(result.errors),
        "warnings": list(result.warnings),
    }


def sandbox_ssh_info() -> dict:
    """Return SSH connection details for the sandbox VM.

    Returns host, port, user, and key_path. Useful for agents that
    need to establish their own SSH connections.
    """
    _require_limactl()
    lima = LimaManager()

    if not lima.vm_exists():
        return {"error": "VM does not exist."}

    status = lima.vm_status()
    if status != "Running":
        return {"error": f"VM is not running (status: {status})."}

    try:
        ssh = lima.get_ssh_details()
    except LimaError as exc:
        return {"error": str(exc)}

    return {
        "host": ssh.host,
        "port": ssh.port,
        "user": ssh.user,
        "key_path": ssh.key_path,
    }


def sandbox_gateway_info() -> dict:
    """Return gateway dashboard URLs with optional authentication.

    Provides base URL, authenticated URL (if password configured),
    and direct links to green and learning dashboards.
    """
    profile = _load_profile_safe()
    gw_password = get_gateway_password(profile)

    result: dict = {
        "base_url": GATEWAY_BASE,
        "port": GATEWAY_PORT,
        "dashboard": GATEWAY_BASE,
        "green_dashboard": f"{GATEWAY_BASE}/__openclaw__/api/green/dashboard",
        "learning_dashboard": f"{GATEWAY_BASE}/__openclaw__/api/learning/dashboard",
    }
    if gw_password:
        result["authenticated_url"] = f"{GATEWAY_BASE}/?password={gw_password}"

    return result


def sandbox_agent_identity() -> dict:
    """Return the agent's identity (name and emoji) if configured.

    Reads from ~/.openclaw/agents/<id>/.identity.md.
    """
    identity = get_agent_identity()
    if identity:
        return {"found": True, **identity}
    return {"found": False, "name": "", "emoji": ""}


def sandbox_dashboard_sync(dry_run: bool = False) -> dict:
    """Sync GitHub issues to Obsidian kanban boards.

    Runs gh-obsidian-sync.py using the dashboard config from the sandbox
    profile. Generates Master Kanban, per-repo boards, individual issue
    notes, and a Dataview dashboard.

    Set dry_run=True to preview without writing files.
    """
    profile = _load_profile_safe()

    try:
        result = run_dashboard_sync(profile, dry_run=dry_run)
    except FileNotFoundError as exc:
        return {"error": str(exc), "exit_code": -1}
    except subprocess.TimeoutExpired:
        return {"error": "Dashboard sync timed out.", "exit_code": -1}

    return {
        "stdout": _truncate(result.stdout),
        "stderr": _truncate(result.stderr),
        "exit_code": result.returncode,
    }


# ── MCP registration ────────────────────────────────────────────────────

def _build_server() -> None:
    """Register all tool functions with the FastMCP server."""
    from fastmcp import FastMCP as _FastMCP

    global mcp
    mcp = _FastMCP("OpenClaw Sandbox")
    mcp.tool(sandbox_status)
    mcp.tool(sandbox_up)
    mcp.tool(sandbox_down)
    mcp.tool(sandbox_destroy)
    mcp.tool(sandbox_exec)
    mcp.tool(sandbox_validate)
    mcp.tool(sandbox_ssh_info)
    mcp.tool(sandbox_gateway_info)
    mcp.tool(sandbox_agent_identity)
    mcp.tool(sandbox_dashboard_sync)


mcp = None  # type: ignore[assignment]
_build_server()


# ── entry point ──────────────────────────────────────────────────────────


def main() -> None:
    """Run the MCP server (stdio transport)."""
    mcp.run()


if __name__ == "__main__":
    main()
