"""OpenClaw Sandbox CLI — Typer app and subcommand definitions."""

from __future__ import annotations

from typing import Annotated, Optional

import typer
from rich.console import Console

from .bootstrap import find_bootstrap_dir, run_script
from .dashboard import run_dashboard_sync
from .lima_manager import LimaManager
from .models import SandboxProfile
from .orchestrator import orchestrate_up
from .profile import init_wizard, load_profile
from .reporting import print_status_report
from .validation import validate_profile

app = typer.Typer(
    name="sandbox",
    help="OpenClaw Sandbox — provision once, run forever.",
    no_args_is_help=True,
)
console = Console()

_ONBOARD_CMD = (
    'cd "$(if mountpoint -q /workspace 2>/dev/null; '
    "then echo /workspace; else echo /mnt/openclaw; fi)\" "
    "&& node dist/index.js onboard"
)


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
    bootstrap_dir = find_bootstrap_dir(profile)
    lima = LimaManager()
    if fresh:
        console.print("[bold]Destroying existing VM before reprovisioning...[/bold]")
        lima.delete()
    rc = orchestrate_up(profile, bootstrap_dir, lima=lima)
    raise typer.Exit(rc)


@app.command()
def down() -> None:
    """Stop the sandbox VM (force kill)."""
    _load_and_validate(strict=False)
    lima = LimaManager()
    lima.stop(force=True)
    console.print("VM stopped.")


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
    _load_and_validate(strict=False)
    lima = LimaManager()
    lima.delete()
    console.print("VM deleted.")


@app.command()
def status() -> None:
    """Show VM state and profile summary."""
    profile = _load_and_validate(strict=False)
    print_status_report(profile, console)


@app.command()
def ssh() -> None:
    """SSH into the sandbox VM (replaces process for TTY)."""
    _load_and_validate(strict=False)
    lima = LimaManager()
    lima.shell()


@app.command()
def onboard() -> None:
    """Run the onboarding wizard inside the VM (replaces process for TTY)."""
    _load_and_validate(strict=False)
    lima = LimaManager()
    lima.shell_exec(_ONBOARD_CMD)


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


# ── dashboard sub-app ────────────────────────────────────────────────────

dashboard_app = typer.Typer(
    name="dashboard",
    help="Gateway dashboard and GitHub-to-Obsidian sync.",
    invoke_without_command=True,
)
app.add_typer(dashboard_app)


@dashboard_app.callback(invoke_without_command=True)
def dashboard_open(
    ctx: typer.Context,
    page: Annotated[
        Optional[str],
        typer.Option("--page", "-p", help="Dashboard page: control, green, learning"),
    ] = None,
) -> None:
    """Open the OpenClaw gateway dashboard."""
    if ctx.invoked_subcommand is not None:
        return
    profile = _load_and_validate(strict=False)
    flags = []
    if page:
        flags.append(page)
    rc = run_script(profile, "dashboard.sh", extra_flags=flags)
    raise typer.Exit(rc)


@dashboard_app.command("sync")
def dashboard_sync(
    dry_run: Annotated[
        bool,
        typer.Option("--dry-run", help="Preview without writing files."),
    ] = False,
) -> None:
    """Sync GitHub issues to Obsidian kanban boards."""
    profile = _load_and_validate(strict=False)
    try:
        result = run_dashboard_sync(profile, dry_run=dry_run)
    except FileNotFoundError as exc:
        console.print(f"[red]error:[/red] {exc}")
        raise typer.Exit(1) from None

    if result.stdout:
        console.print(result.stdout.rstrip())
    if result.returncode != 0:
        if result.stderr:
            console.print(f"[yellow]{result.stderr.rstrip()}[/yellow]")
        console.print(f"[red]Sync failed (exit {result.returncode}).[/red]")
        raise typer.Exit(result.returncode)
    console.print("[green]Dashboard sync complete.[/green]")
