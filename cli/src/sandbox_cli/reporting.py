"""Post-bootstrap reporting and OpenClaw interop (v1).

Covers:
- Mode-specific completion messages (secure / yolo / yolo-unsafe)
- Gateway password extraction from ``~/.openclaw/openclaw.json``
- Dashboard URLs with optional auth
- Agent identity from ``~/.openclaw/agents/<id>/.identity.md``
- Learning stats from gateway API (best-effort, 2s timeout)
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from pathlib import Path

from rich.console import Console
from rich.table import Table

from .lima_manager import LimaManager
from .models import SandboxProfile

GATEWAY_PORT = 18789
GATEWAY_BASE = f"http://127.0.0.1:{GATEWAY_PORT}"
OPENCLAW_DIR = Path.home() / ".openclaw"


# ── gateway password ─────────────────────────────────────────────────────


def get_gateway_password(profile: SandboxProfile) -> str:
    """Try to read ``.gateway.auth.password`` from ``openclaw.json``.

    Returns the password string, or empty string on failure.
    """
    config_dir = profile.mounts.config
    if not config_dir:
        config_dir = str(OPENCLAW_DIR)
    config_json = Path(config_dir).expanduser() / "openclaw.json"
    if not config_json.is_file():
        return ""
    try:
        data = json.loads(config_json.read_text())
        return data.get("gateway", {}).get("auth", {}).get("password", "")
    except (json.JSONDecodeError, OSError):
        return ""


# ── agent identity ───────────────────────────────────────────────────────


def get_agent_identity() -> dict[str, str] | None:
    """Read the first agent's ``.identity.md`` and return ``{name, emoji}``.

    Looks in ``~/.openclaw/agents/*/agent/.identity.md`` (or similar).
    Returns *None* if no identity found.
    """
    agents_dir = OPENCLAW_DIR / "agents"
    if not agents_dir.is_dir():
        return None
    # Walk agent directories looking for .identity.md
    for agent_dir in sorted(agents_dir.iterdir()):
        if not agent_dir.is_dir():
            continue
        identity_file = agent_dir / "agent" / ".identity.md"
        if not identity_file.is_file():
            identity_file = agent_dir / ".identity.md"
        if not identity_file.is_file():
            continue
        try:
            text = identity_file.read_text().strip()
            return _parse_identity(text)
        except OSError:
            continue
    return None


def _parse_identity(text: str) -> dict[str, str]:
    """Extract name and emoji from identity markdown.

    Expects lines like ``# Name`` or ``emoji: X`` or ``name: X``.
    Falls back to first line as name.
    """
    result: dict[str, str] = {"name": "", "emoji": ""}
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("# "):
            result["name"] = stripped[2:].strip()
        elif stripped.lower().startswith("emoji:"):
            result["emoji"] = stripped.split(":", 1)[1].strip()
        elif stripped.lower().startswith("name:"):
            result["name"] = stripped.split(":", 1)[1].strip()
    if not result["name"] and text:
        result["name"] = text.splitlines()[0].strip().lstrip("#").strip()
    return result


# ── learning stats ───────────────────────────────────────────────────────


def get_learning_stats() -> dict | None:
    """Best-effort HTTP GET to the learning API (2s timeout).

    Returns the JSON response dict, or *None* on any failure.
    """
    url = f"{GATEWAY_BASE}/__openclaw__/api/learning/summary"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.URLError, OSError, json.JSONDecodeError, ValueError):
        return None


# ── post-bootstrap output ────────────────────────────────────────────────


def print_post_bootstrap(
    profile: SandboxProfile,
    console: Console | None = None,
) -> None:
    """Print the completion report after a successful provision."""
    if console is None:
        console = Console()

    console.print()
    console.print("[bold green]Bootstrap complete![/bold green]")
    console.print()
    console.print("VM 'openclaw-sandbox' is running.")
    console.print("Access via:  [cyan]sandbox ssh[/cyan]")
    console.print("Stop with:   [cyan]sandbox down[/cyan]")
    console.print("Delete with: [cyan]sandbox destroy[/cyan]")

    # Vault
    if profile.mounts.vault:
        console.print()
        console.print(f"Vault mounted at: /mnt/obsidian")

    # Mode-specific messages
    console.print()
    if profile.mode.yolo_unsafe:
        console.print(
            "[bold yellow]YOLO-UNSAFE mode:[/bold yellow] "
            "no overlay, host mounts are writable."
        )
        console.print(
            "[yellow]Agent writes go DIRECTLY to host filesystem.[/yellow]"
        )
    elif profile.mode.yolo:
        console.print("YOLO mode: overlay active + auto-sync every 30s.")
        console.print("Sync to host: [cyan]sandbox sync[/cyan] (or wait for timer)")
    else:
        console.print("Secure mode: overlay active, host mounts are READ-ONLY.")
        console.print("Services run from: /workspace")
        console.print("Sync to host: [cyan]sandbox sync[/cyan]")

    # Gateway dashboard URLs
    gw_password = get_gateway_password(profile)
    console.print()
    console.print(f"Gateway dashboard: [link]{GATEWAY_BASE}[/link]")
    if gw_password:
        console.print(f"  With auth:  {GATEWAY_BASE}/?password={gw_password}")
    console.print(f"  Green:      {GATEWAY_BASE}/__openclaw__/api/green/dashboard")
    console.print(f"  Learning:   {GATEWAY_BASE}/__openclaw__/api/learning/dashboard")

    # Telegram
    console.print()
    console.print("Telegram: dmPolicy=pairing (unknown senders get a pairing code)")
    console.print('  Pre-approve your ID: extra_vars → telegram_user_id=YOUR_ID')
    console.print(
        "  Approve a code:      [cyan]sandbox ssh[/cyan] → "
        "claw pair approve <CODE>"
    )


def print_status_report(
    profile: SandboxProfile,
    console: Console | None = None,
) -> None:
    """Print an enriched status report with interop data."""
    if console is None:
        console = Console()

    lima = LimaManager()

    table = Table(title="Sandbox Status")
    table.add_column("Field", style="cyan")
    table.add_column("Value")

    # VM info
    info = lima.vm_info()
    if info:
        table.add_row("VM", info.get("name", ""))
        table.add_row("Status", info.get("status", "unknown"))
        table.add_row("Arch", info.get("arch", ""))
        table.add_row("CPUs", str(info.get("cpus", "")))
        table.add_row("Memory", str(info.get("memory", "")))
        table.add_row("Disk", str(info.get("disk", "")))
    else:
        table.add_row("VM", "not found")

    # Profile info
    table.add_section()
    table.add_row("Bootstrap dir", profile.meta.bootstrap_dir or "(not set)")
    table.add_row("OpenClaw mount", profile.mounts.openclaw or "(not set)")
    table.add_row("Secrets", profile.mounts.secrets or "(not set)")
    table.add_row("Vault", profile.mounts.vault or "(not set)")
    table.add_row("YOLO", str(profile.mode.yolo))
    table.add_row("Docker", str(not profile.mode.no_docker))
    table.add_row("Memgraph", str(profile.mode.memgraph))
    table.add_row(
        "Resources",
        f"{profile.resources.cpus} CPUs / {profile.resources.memory} / {profile.resources.disk}",
    )

    # Agent identity (interop v1)
    identity = get_agent_identity()
    if identity:
        table.add_section()
        name = identity.get("name", "")
        emoji = identity.get("emoji", "")
        label = f"{emoji} {name}".strip() if emoji else name
        table.add_row("Agent", label or "(unnamed)")

    # Learning stats (interop v1, best-effort)
    if info and info.get("status") == "Running":
        stats = get_learning_stats()
        if stats:
            table.add_section()
            obs = stats.get("totalObservations", stats.get("total_observations", ""))
            if obs:
                table.add_row("Observations", str(obs))

    console.print(table)
