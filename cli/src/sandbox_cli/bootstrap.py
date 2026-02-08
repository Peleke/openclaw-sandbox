"""Argv builder and subprocess delegation to bootstrap.sh / helper scripts.

The ``run_bootstrap`` and ``exec_bootstrap`` functions are **deprecated** as
of v0.7.  Use the new Python modules (``orchestrator``, ``lima_manager``, etc.)
instead.  These wrappers are kept for backward compatibility and will be
removed in a future release.
"""

from __future__ import annotations

import os
import subprocess
import sys
import warnings
from pathlib import Path

from .models import SandboxProfile


def find_bootstrap_dir(profile: SandboxProfile) -> Path:
    """Locate the sandbox repo via CWD > $OPENCLAW_SANDBOX_DIR > profile.

    Returns the directory containing bootstrap.sh.
    """
    candidates = [
        Path.cwd(),
        Path(os.environ.get("OPENCLAW_SANDBOX_DIR", "")),
        Path(profile.meta.bootstrap_dir) if profile.meta.bootstrap_dir else None,
    ]
    for c in candidates:
        if c and (c / "bootstrap.sh").is_file():
            return c
    raise FileNotFoundError(
        "Cannot find bootstrap.sh — run from the sandbox repo, "
        "set $OPENCLAW_SANDBOX_DIR, or configure meta.bootstrap_dir in your profile."
    )


def build_argv(profile: SandboxProfile) -> list[str]:
    """Build the argv list for bootstrap.sh from the profile."""
    argv: list[str] = []

    # Mounts
    mount_flags = [
        ("--openclaw", profile.mounts.openclaw),
        ("--config", profile.mounts.config),
        ("--agent-data", profile.mounts.agent_data),
        ("--buildlog-data", profile.mounts.buildlog_data),
        ("--secrets", profile.mounts.secrets),
        ("--vault", profile.mounts.vault),
    ]
    for flag, value in mount_flags:
        if value:
            argv.extend([flag, value])

    # Mode flags
    if profile.mode.yolo:
        argv.append("--yolo")
    if profile.mode.yolo_unsafe:
        argv.append("--yolo-unsafe")
    if profile.mode.no_docker:
        argv.append("--no-docker")
    if profile.mode.memgraph:
        argv.append("--memgraph")
    for port in profile.mode.memgraph_ports:
        argv.extend(["--memgraph-port", str(port)])

    # Extra Ansible vars
    for key, value in profile.extra_vars.items():
        argv.extend(["-e", f"{key}={value}"])

    return argv


def run_bootstrap(
    profile: SandboxProfile,
    *,
    extra_flags: list[str] | None = None,
) -> int:
    """Run bootstrap.sh with the profile's flags and return the exit code.

    .. deprecated:: 0.7
        Use :func:`sandbox_cli.orchestrator.orchestrate_up` instead.
    """
    warnings.warn(
        "run_bootstrap() is deprecated — use orchestrate_up() instead",
        DeprecationWarning,
        stacklevel=2,
    )
    bdir = find_bootstrap_dir(profile)
    script = str(bdir / "bootstrap.sh")
    argv = [script] + build_argv(profile) + (extra_flags or [])
    env = {
        **os.environ,
        "VM_CPUS": str(profile.resources.cpus),
        "VM_MEMORY": profile.resources.memory,
        "VM_DISK": profile.resources.disk,
    }
    result = subprocess.run(argv, env=env)
    return result.returncode


def exec_bootstrap(
    profile: SandboxProfile,
    *,
    extra_flags: list[str],
) -> None:
    """Replace the current process with bootstrap.sh (for TTY commands).

    .. deprecated:: 0.7
        Use :meth:`sandbox_cli.lima_manager.LimaManager.shell` or
        :meth:`~LimaManager.shell_exec` instead.
    """
    warnings.warn(
        "exec_bootstrap() is deprecated — use LimaManager.shell() instead",
        DeprecationWarning,
        stacklevel=2,
    )
    bdir = find_bootstrap_dir(profile)
    script = str(bdir / "bootstrap.sh")
    argv = [script] + extra_flags
    env = {
        **os.environ,
        "VM_CPUS": str(profile.resources.cpus),
        "VM_MEMORY": profile.resources.memory,
        "VM_DISK": profile.resources.disk,
    }
    os.execve(script, argv, env)


def run_script(
    profile: SandboxProfile,
    script_name: str,
    *,
    extra_flags: list[str] | None = None,
) -> int:
    """Run a helper script under scripts/ and return the exit code."""
    bdir = find_bootstrap_dir(profile)
    scripts_dir = (bdir / "scripts").resolve()
    script = (scripts_dir / script_name).resolve()
    if not script.is_relative_to(scripts_dir):
        print(f"Script path escapes scripts directory: {script_name}", file=sys.stderr)
        return 1
    if not script.is_file():
        print(f"Script not found: {script}", file=sys.stderr)
        return 1
    argv = [str(script)] + (extra_flags or [])
    result = subprocess.run(argv)
    return result.returncode
