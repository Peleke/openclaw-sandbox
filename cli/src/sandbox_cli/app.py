"""OpenClaw Sandbox CLI — Typer app and subcommand definitions."""

from __future__ import annotations

import json
import subprocess
import sys
from typing import Annotated, Optional

import typer
from rich.console import Console
from rich.table import Table

from .bootstrap import exec_bootstrap, find_bootstrap_dir, run_bootstrap, run_script
from .models import SandboxProfile
from .profile import init_wizard, load_profile
from .validation import validate_profile

app = typer.Typer(
    name="sandbox",
    help="OpenClaw Sandbox — provision once, run forever.",
    no_args_is_help=True,
)
console = Console()


# ── helpers ──────────────────────────────────────────────────────────────


def _load_and_validate(*, strict: bool = True) -> SandboxProfile:
    """Load the profile and run validation. Exit on errors if strict."""
    profile = load_profile()
    result = validate_profile(profile)
    for w in result.warnings:
        console.print(f"[yellow]warning:[/yellow] {w}")
    if not result.ok:
        for e in result.errors:
            console.print(f"[red]error:[/red] {e}")
        if strict:
            raise typer.Exit(1)
    return profile


# ── subcommands ──────────────────────────────────────────────────────────


@app.command()
def init() -> None:
    """Interactive wizard to create or update your sandbox profile."""
    init_wizard()


@app.command()
def up(
    fresh: Annotated[
        bool,
        typer.Option("--fresh", help="Destroy existing VM first, then reprovision."),
    ] = False,
) -> None:
    """Provision (or reprovision) the sandbox VM."""
    profile = _load_and_validate()
    if fresh:
        console.print("[bold]Destroying existing VM before reprovisioning...[/bold]")
        rc = run_bootstrap(profile, extra_flags=["--delete"])
        if rc != 0:
            console.print("[red]VM deletion failed.[/red]")
            raise typer.Exit(rc)
    rc = run_bootstrap(profile)
    raise typer.Exit(rc)


@app.command()
def down() -> None:
    """Stop the sandbox VM (force kill)."""
    profile = _load_and_validate(strict=False)
    rc = run_bootstrap(profile, extra_flags=["--kill"])
    raise typer.Exit(rc)


@app.command()
def destroy(
    force: Annotated[
        bool,
        typer.Option("-f", "--force", help="Skip confirmation prompt."),
    ] = False,
) -> None:
    """Delete the sandbox VM entirely."""
    if not force:
        confirm = typer.confirm("This will permanently delete the VM. Continue?")
        if not confirm:
            raise typer.Abort()
    profile = _load_and_validate(strict=False)
    rc = run_bootstrap(profile, extra_flags=["--delete"])
    raise typer.Exit(rc)


@app.command()
def status() -> None:
    """Show VM state and profile summary."""
    profile = _load_and_validate(strict=False)

    # VM state from limactl
    table = Table(title="Sandbox Status")
    table.add_column("Field", style="cyan")
    table.add_column("Value")

    vm_status = "unknown"
    try:
        proc = subprocess.run(
            ["limactl", "list", "--json"],
            capture_output=True,
            text=True,
        )
        if proc.returncode == 0:
            for line in proc.stdout.strip().splitlines():
                entry = json.loads(line)
                if entry.get("name") == "openclaw-sandbox":
                    vm_status = entry.get("status", "unknown")
                    table.add_row("VM", entry.get("name", ""))
                    table.add_row("Status", vm_status)
                    table.add_row("Arch", entry.get("arch", ""))
                    table.add_row("CPUs", str(entry.get("cpus", "")))
                    table.add_row("Memory", str(entry.get("memory", "")))
                    table.add_row("Disk", str(entry.get("disk", "")))
                    break
            else:
                table.add_row("VM", "not found")
    except FileNotFoundError:
        table.add_row("VM", "limactl not installed")

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

    console.print(table)


@app.command()
def ssh() -> None:
    """SSH into the sandbox VM (replaces process for TTY)."""
    profile = _load_and_validate(strict=False)
    exec_bootstrap(profile, extra_flags=["--shell"])


@app.command()
def onboard() -> None:
    """Run the onboarding wizard inside the VM (replaces process for TTY)."""
    profile = _load_and_validate(strict=False)
    exec_bootstrap(profile, extra_flags=["--onboard"])


@app.command()
def sync(
    dry_run: Annotated[
        bool,
        typer.Option("--dry-run", help="Preview changes without applying."),
    ] = False,
) -> None:
    """Sync overlay changes from VM to host."""
    profile = _load_and_validate(strict=False)
    flags = []
    if dry_run:
        flags.append("--dry-run")
    rc = run_script(profile, "sync-gate.sh", extra_flags=flags)
    raise typer.Exit(rc)


@app.command()
def dashboard(
    page: Annotated[
        Optional[str],
        typer.Argument(help="Dashboard page: control, green, learning"),
    ] = None,
) -> None:
    """Open the OpenClaw gateway dashboard."""
    profile = _load_and_validate(strict=False)
    flags = []
    if page:
        flags.append(page)
    rc = run_script(profile, "dashboard.sh", extra_flags=flags)
    raise typer.Exit(rc)
