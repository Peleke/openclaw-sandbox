"""Top-level orchestration: deps → config → VM → mounts → ansible → report."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from rich.console import Console

from .deps import DependencyError, check_brew, install_ansible_collections, install_brew_deps
from .lima_config import build_context, write_config
from .lima_manager import LimaError, LimaManager, SSHDetails
from .ansible_runner import run_playbook
from .models import SandboxProfile
from .reporting import print_post_bootstrap

console = Console()


def orchestrate_up(
    profile: SandboxProfile,
    bootstrap_dir: Path,
    *,
    lima: LimaManager | None = None,
) -> int:
    """Full provision flow. Returns 0 on success, non-zero on failure."""
    if lima is None:
        lima = LimaManager()

    # ── 1. dependency checks ─────────────────────────────────────────────
    console.print("[blue]Checking dependencies...[/blue]")
    try:
        check_brew()
    except DependencyError as exc:
        console.print(f"[red]{exc}[/red]")
        return 1

    rc = install_brew_deps(bootstrap_dir)
    if rc != 0:
        console.print("[red]brew bundle failed.[/red]")
        return rc

    rc = install_ansible_collections(bootstrap_dir)
    if rc != 0:
        console.print("[yellow]ansible-galaxy install had warnings (continuing).[/yellow]")
        # Non-fatal: collections may already be installed

    # ── 2. Lima config generation ────────────────────────────────────────
    if not lima.vm_exists():
        if not profile.mounts.openclaw:
            console.print(
                "[red]--openclaw mount is required to create a new VM.[/red]\n"
                "Set mounts.openclaw in your profile or run [cyan]sandbox init[/cyan]."
            )
            return 1
        console.print("[blue]Generating Lima configuration...[/blue]")
        config_path = write_config(profile, bootstrap_dir)
        _print_mounts(profile, bootstrap_dir)
    else:
        console.print("VM 'openclaw-sandbox' already exists, using existing configuration.")
        if profile.mounts.openclaw:
            console.print(
                "[yellow]Path options only apply to new VMs. "
                "To change paths: sandbox destroy -f && sandbox up[/yellow]"
            )
        config_path = bootstrap_dir / "lima" / "openclaw-sandbox.generated.yaml"

    # ── 3. ensure VM is running ──────────────────────────────────────────
    console.print("[blue]Ensuring VM is running...[/blue]")
    try:
        created = lima.ensure_running(config_path)
        if created:
            console.print("Created and started VM.")
        else:
            console.print("VM is running.")
    except LimaError as exc:
        console.print(f"[red]Lima error: {exc}[/red]")
        return 1

    # ── 4. verify mounts ────────────────────────────────────────────────
    console.print("[blue]Verifying host mounts...[/blue]")
    ctx = build_context(profile, bootstrap_dir)
    failed = False
    for mount in ctx.mounts:
        ok = lima.verify_mount(mount.mount_point)
        if ok:
            console.print(f"  {mount.mount_point} [green]OK[/green]")
        else:
            console.print(f"  {mount.mount_point} [red]MISSING[/red]")
            failed = True
    if failed:
        console.print("[red]Some mounts are not accessible. Check Lima configuration.[/red]")
        return 1
    console.print("[green]All mounts verified.[/green]")

    if not profile.mode.yolo_unsafe:
        console.print("Overlay /workspace will be set up by Ansible.")

    # ── 5. ansible ──────────────────────────────────────────────────────
    console.print("[blue]Running Ansible playbook...[/blue]")
    try:
        ssh = lima.get_ssh_details()
    except LimaError as exc:
        console.print(f"[red]{exc}[/red]")
        return 1

    console.print(f"SSH: {ssh.user}@{ssh.host}:{ssh.port}")
    rc = run_playbook(profile, ssh, bootstrap_dir)
    if rc != 0:
        console.print(f"[red]Ansible playbook failed (exit {rc}).[/red]")
        return rc

    # ── 6. vault sync ─────────────────────────────────────────────────────
    if profile.mounts.vault and not profile.mode.yolo_unsafe:
        _sync_vault(profile, ssh, console)

    # ── 7. report ────────────────────────────────────────────────────────
    print_post_bootstrap(profile, console)
    return 0


def _sync_vault(
    profile: SandboxProfile,
    ssh: SSHDetails,
    console: Console,
) -> None:
    """Rsync vault from host into the VM overlay upper directory.

    iCloud's ``filecoordinationd`` locks files in ``~/Library/Mobile Documents/``
    which makes them unreadable through Lima's virtiofs.  Rsync over SSH bypasses
    this because the host process can read the files normally, then pushes them
    into the overlay upper dir so ``/workspace-obsidian/`` serves the copies.
    """
    vault_path = Path(profile.mounts.vault).expanduser().resolve()
    if not vault_path.is_dir():
        console.print(f"[yellow]Vault path does not exist: {vault_path}[/yellow]")
        return

    target = "/var/lib/openclaw/overlay/obsidian/upper/"
    console.print("[blue]Syncing Obsidian vault into VM overlay...[/blue]")
    console.print(f"  Source: {vault_path} (host)")
    console.print(f"  Target: {target} (VM)")

    ssh_cmd = (
        f"ssh -p {ssh.port} -i {ssh.key_path} "
        "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    )
    result = subprocess.run(
        [
            "rsync", "-a", "--delete",
            "-e", ssh_cmd,
            f"{vault_path}/",
            f"{ssh.user}@{ssh.host}:{target}",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        console.print("[green]Vault synced. Readable at /workspace-obsidian/[/green]")
    else:
        console.print(
            f"[yellow]Vault sync failed (exit {result.returncode}).[/yellow]\n"
            f"  {result.stderr.strip()}\n"
            "  Files may not be readable due to iCloud locks.\n"
            f"  Manual: rsync -a '{vault_path}/' openclaw-sandbox:{target}"
        )


def _print_mounts(profile: SandboxProfile, bootstrap_dir: Path) -> None:
    """Log the resolved mount table after config generation."""
    ctx = build_context(profile, bootstrap_dir)
    console.print("[blue]Mounts:[/blue]")
    for m in ctx.mounts:
        mode = "read-write" if m.writable else "read-only"
        if not profile.mode.yolo_unsafe and m.mount_point == "/mnt/openclaw":
            mode += " + overlay"
        console.print(f"  {m.mount_point:25s} -> {m.location} ({mode})")
