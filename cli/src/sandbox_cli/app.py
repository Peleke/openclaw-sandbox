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
    memgraph: Annotated[
        bool,
        typer.Option("--memgraph", help="Enable Memgraph (overrides profile setting)."),
    ] = False,
) -> None:
    """Provision (or reprovision) the sandbox VM."""
    profile = _load_and_validate()
    if memgraph:
        profile.mode.memgraph = True
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
def upgrade(
    qortex_dir: Annotated[
        Optional[str],
        typer.Option(
            "--qortex-dir", "-q",
            help="Path to local qortex source directory. Builds wheels from source.",
        ),
    ] = None,
    wheel_dir: Annotated[
        Optional[str],
        typer.Option(
            "--wheel-dir", "-w",
            help="Path to pre-built wheels directory (skips build step).",
        ),
    ] = None,
    skip_restart: Annotated[
        bool,
        typer.Option("--skip-restart", help="Install without restarting the gateway."),
    ] = False,
) -> None:
    """Build, deploy, and install qortex wheels into the sandbox.

    Dev workflow: build wheels from local source, SCP to VM, install, restart.
    Replaces the ad-hoc wheel juggling dance forever.

    \b
    Examples:
        bilrost upgrade -q ~/Projects/qortex          # build + deploy + restart
        bilrost upgrade -w ~/Projects/qortex/dist      # deploy pre-built wheels
        bilrost upgrade -q ~/Projects/qortex --skip-restart
    """
    import shutil
    import subprocess
    from pathlib import Path

    _load_and_validate(strict=False)
    lima = LimaManager()
    if lima.vm_status() != "Running":
        console.print("[yellow]VM is not running.[/yellow] Run [bold]bilrost up[/bold] first.")
        raise typer.Exit(1)

    if not qortex_dir and not wheel_dir:
        console.print("[red]error:[/red] Provide --qortex-dir (build from source) or --wheel-dir (pre-built).")
        raise typer.Exit(1)

    # ── Step 1: Build wheels ────────────────────────────────────────────
    if qortex_dir:
        src = Path(qortex_dir).expanduser().resolve()
        if not (src / "pyproject.toml").exists():
            console.print(f"[red]error:[/red] No pyproject.toml in {src}")
            raise typer.Exit(1)

        dist = src / "dist"
        if dist.exists():
            shutil.rmtree(dist)
        dist.mkdir()

        console.print(f"[blue]Building wheels from {src}...[/blue]")
        builds = [
            (src, dist),
            (src / "packages" / "qortex-online", dist),
            (src / "packages" / "qortex-observe", dist),
            (src / "packages" / "qortex-ingest", dist),
        ]
        for pkg_dir, out_dir in builds:
            if not (pkg_dir / "pyproject.toml").exists():
                console.print(f"  [dim]skip[/dim] {pkg_dir.name} (no pyproject.toml)")
                continue
            console.print(f"  [dim]build[/dim] {pkg_dir.name}")
            proc = subprocess.run(
                ["uv", "build", "--wheel", "--out-dir", str(out_dir)],
                cwd=str(pkg_dir),
                capture_output=True, text=True,
            )
            if proc.returncode != 0:
                console.print(f"[red]Build failed for {pkg_dir.name}:[/red]")
                console.print(proc.stderr)
                raise typer.Exit(1)
        whl_dir = dist
    else:
        whl_dir = Path(wheel_dir).expanduser().resolve()  # type: ignore[arg-type]

    wheels = list(whl_dir.glob("*.whl"))
    if not wheels:
        console.print(f"[red]error:[/red] No .whl files found in {whl_dir}")
        raise typer.Exit(1)
    console.print(f"  [green]{len(wheels)} wheel(s) ready[/green]")

    # ── Step 2: SCP wheels to VM ────────────────────────────────────────
    console.print("[blue]Copying wheels to VM...[/blue]")
    ssh = lima.get_ssh_details()
    for whl in wheels:
        proc = subprocess.run(
            [
                "scp", "-P", str(ssh.port),
                "-i", ssh.key_path,
                "-o", "StrictHostKeyChecking=no",
                str(whl),
                f"{ssh.user}@{ssh.host}:/tmp/",
            ],
            capture_output=True, text=True,
        )
        if proc.returncode != 0:
            console.print(f"[red]SCP failed for {whl.name}:[/red] {proc.stderr}")
            raise typer.Exit(1)
        console.print(f"  [dim]copied[/dim] {whl.name}")

    # ── Step 3: Install wheels ──────────────────────────────────────────
    # Use qortex[all] to pull every optional extra (vec, memgraph, nlp, mcp,
    # observability, llm, causal, pdf, source-postgres, dev).
    # Namespace packages (online, observe, ingest) are separate wheels that
    # must be --with'd explicitly with their own [all] extras.
    console.print("[blue]Installing wheels in VM...[/blue]")
    uv = "~/.local/bin/uv"
    tool_python = "~/.local/share/uv/tools/qortex/bin/python3"

    # Resolve exact filenames locally to avoid shell glob + bracket quoting issues.
    # Main wheel gets [all] (pulls vec, memgraph, nlp, mcp, observability, llm, etc).
    # Namespace wheels get [all] too (pulls their otel, nlp, anthropic extras).
    main_wheels = [w for w in wheels if w.name.startswith("qortex-") and not w.name.startswith("qortex_")]
    if not main_wheels:
        console.print("[red]error:[/red] No main qortex wheel found (expected qortex-*.whl)")
        raise typer.Exit(1)
    main_whl = main_wheels[0].name

    ns_patterns = ["qortex_online-*.whl", "qortex_observe-*.whl", "qortex_ingest-*.whl"]
    with_clauses = []
    for pattern in ns_patterns:
        for match in whl_dir.glob(pattern):
            # Quote the path[extra] to prevent shell bracket expansion
            with_clauses.append(f"--with '/tmp/{match.name}[all]'")

    # Pin sqlite-vec prerelease in the install itself — 0.1.6 ships a
    # 32-bit ELF on aarch64 that segfaults. If we fix it post-install,
    # any re-resolve pulls 0.1.6 back. Bake the pin into the command.
    install_cmd = (
        f"{uv} tool install --force --reinstall --prerelease=allow "
        f"'/tmp/{main_whl}[all]' "
        + " ".join(with_clauses)
        + " --with 'sqlite-vec>=0.1.7a2'"
    )
    result = lima.shell_run(install_cmd)
    if result.returncode != 0:
        console.print(f"[red]Install failed:[/red]\n{result.stderr}")
        raise typer.Exit(1)
    console.print(f"  [green]installed[/green]")

    # ── Step 4: spaCy model ─────────────────────────────────────────────
    console.print("[blue]Ensuring spaCy model...[/blue]")
    spacy_url = (
        "https://github.com/explosion/spacy-models/releases/download/"
        "en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"
    )
    spacy_cmd = f"{uv} pip install --python {tool_python} en_core_web_sm@{spacy_url}"
    result = lima.shell_run(spacy_cmd)
    if result.returncode != 0:
        console.print(f"[yellow]warning:[/yellow] spaCy model install failed: {result.stderr}")
    else:
        console.print(f"  [green]en_core_web_sm ready[/green]")

    # ── Step 6: Restart gateway ─────────────────────────────────────────
    if not skip_restart:
        console.print("[blue]Restarting gateway...[/blue]")
        result = lima.shell_run("sudo systemctl restart openclaw-gateway")
        if result.returncode != 0:
            console.print(f"[red]Gateway restart failed:[/red] {result.stderr}")
            raise typer.Exit(1)
        console.print("[green]Gateway restarted.[/green]")

    # ── Step 7: Cleanup ─────────────────────────────────────────────────
    lima.shell_run("rm -f /tmp/qortex*.whl")

    console.print("\n[bold green]Upgrade complete.[/bold green]")


@app.command()
def restart() -> None:
    """Restart the OpenClaw gateway service in the VM."""
    _load_and_validate(strict=False)
    lima = LimaManager()
    if lima.vm_status() != "Running":
        console.print("[yellow]VM is not running.[/yellow] Run [bold]bilrost up[/bold] first.")
        raise typer.Exit(1)
    console.print("Restarting gateway...")
    result = lima.shell_run("sudo systemctl restart openclaw-gateway")
    if result.returncode != 0:
        if result.stderr:
            console.print(f"[red]{result.stderr.rstrip()}[/red]")
        console.print("[red]Gateway restart failed.[/red]")
        raise typer.Exit(result.returncode)
    console.print("[green]Gateway restarted.[/green]")


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
