"""Dashboard sync — run gh-obsidian-sync.py to update Obsidian kanban boards."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from .models import Dashboard, SandboxProfile

SYNC_SCRIPT_NAME = "gh-obsidian-sync.py"
SYNC_TIMEOUT = 120  # seconds


def resolve_config(profile: SandboxProfile) -> tuple[Path, Path]:
    """Return (vault_path, script_path) resolved from profile.

    Falls back to mounts.vault when dashboard.vault_path is empty.
    Auto-discovers the sync script under vault/_scripts/ when
    dashboard.script_path is empty.

    Raises FileNotFoundError if either path cannot be resolved.
    """
    dash = profile.dashboard

    vault = dash.vault_path or profile.mounts.vault
    if not vault:
        raise FileNotFoundError(
            "No vault path configured. Set dashboard.vault_path or mounts.vault "
            "in your sandbox profile."
        )
    vault_path = Path(vault).expanduser().resolve()

    if dash.script_path:
        script_path = Path(dash.script_path).expanduser().resolve()
    else:
        script_path = vault_path / "_scripts" / SYNC_SCRIPT_NAME

    return vault_path, script_path


def run_dashboard_sync(
    profile: SandboxProfile,
    *,
    dry_run: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Execute gh-obsidian-sync.py with config from the profile.

    Returns the CompletedProcess so callers can inspect stdout/stderr/returncode.
    Raises FileNotFoundError if vault or script is missing.
    """
    vault_path, script_path = resolve_config(profile)

    if not vault_path.is_dir():
        raise FileNotFoundError(f"Vault directory does not exist: {vault_path}")
    if not script_path.is_file():
        raise FileNotFoundError(f"Sync script not found: {script_path}")

    dash = profile.dashboard
    cmd: list[str] = [
        sys.executable, str(script_path),
        "--vault", str(vault_path),
        "--days", str(dash.lookback_days),
    ]
    if dash.repos:
        cmd.extend(["--repos"] + dash.repos)
    if dry_run:
        cmd.append("--dry-run")

    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=SYNC_TIMEOUT,
    )
