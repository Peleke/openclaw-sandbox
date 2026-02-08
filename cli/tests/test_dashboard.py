"""Tests for dashboard sync module."""

import subprocess
from pathlib import Path
from unittest.mock import patch

import pytest

from sandbox_cli.dashboard import resolve_config, run_dashboard_sync
from sandbox_cli.models import Dashboard, SandboxProfile


# ── resolve_config ───────────────────────────────────────────────────────


class TestResolveConfig:
    def test_uses_dashboard_vault_path(self, tmp_path):
        vault = tmp_path / "vault"
        vault.mkdir()
        profile = SandboxProfile(dashboard=Dashboard(vault_path=str(vault)))
        vault_path, script_path = resolve_config(profile)
        assert vault_path == vault
        assert script_path == vault / "_scripts" / "gh-obsidian-sync.py"

    def test_falls_back_to_mounts_vault(self, tmp_path):
        vault = tmp_path / "vault"
        vault.mkdir()
        profile = SandboxProfile(
            mounts={"vault": str(vault)},
            dashboard=Dashboard(),
        )
        vault_path, _ = resolve_config(profile)
        assert vault_path == vault

    def test_raises_when_no_vault(self):
        profile = SandboxProfile()
        with pytest.raises(FileNotFoundError, match="No vault path"):
            resolve_config(profile)

    def test_uses_explicit_script_path(self, tmp_path):
        vault = tmp_path / "vault"
        vault.mkdir()
        script = tmp_path / "custom-sync.py"
        profile = SandboxProfile(
            dashboard=Dashboard(
                vault_path=str(vault),
                script_path=str(script),
            ),
        )
        _, script_path = resolve_config(profile)
        assert script_path == script


# ── run_dashboard_sync ───────────────────────────────────────────────────


class TestRunDashboardSync:
    @pytest.fixture()
    def sync_env(self, tmp_path):
        """Set up a vault dir with a sync script."""
        vault = tmp_path / "vault"
        vault.mkdir()
        scripts_dir = vault / "_scripts"
        scripts_dir.mkdir()
        script = scripts_dir / "gh-obsidian-sync.py"
        script.write_text("#!/usr/bin/env python3\nprint('synced')\n")
        return vault, script

    def test_raises_when_vault_missing(self, tmp_path):
        profile = SandboxProfile(
            dashboard=Dashboard(vault_path=str(tmp_path / "nonexistent")),
        )
        with pytest.raises(FileNotFoundError, match="Vault directory"):
            run_dashboard_sync(profile)

    def test_raises_when_script_missing(self, tmp_path):
        vault = tmp_path / "vault"
        vault.mkdir()
        profile = SandboxProfile(
            dashboard=Dashboard(vault_path=str(vault)),
        )
        with pytest.raises(FileNotFoundError, match="Sync script not found"):
            run_dashboard_sync(profile)

    def test_builds_correct_command(self, sync_env):
        vault, script = sync_env
        profile = SandboxProfile(
            dashboard=Dashboard(
                vault_path=str(vault),
                lookback_days=30,
            ),
        )
        with patch("sandbox_cli.dashboard.subprocess.run") as mock_run:
            mock_run.return_value = subprocess.CompletedProcess([], 0, "", "")
            run_dashboard_sync(profile)

        cmd = mock_run.call_args[0][0]
        assert str(script) in cmd
        assert "--vault" in cmd
        assert str(vault) in cmd
        assert "--days" in cmd
        assert "30" in cmd

    def test_dry_run_flag(self, sync_env):
        vault, _ = sync_env
        profile = SandboxProfile(
            dashboard=Dashboard(vault_path=str(vault)),
        )
        with patch("sandbox_cli.dashboard.subprocess.run") as mock_run:
            mock_run.return_value = subprocess.CompletedProcess([], 0, "", "")
            run_dashboard_sync(profile, dry_run=True)

        cmd = mock_run.call_args[0][0]
        assert "--dry-run" in cmd

    def test_repos_flag(self, sync_env):
        vault, _ = sync_env
        profile = SandboxProfile(
            dashboard=Dashboard(
                vault_path=str(vault),
                repos=["Peleke/openclaw", "Peleke/cadence"],
            ),
        )
        with patch("sandbox_cli.dashboard.subprocess.run") as mock_run:
            mock_run.return_value = subprocess.CompletedProcess([], 0, "", "")
            run_dashboard_sync(profile)

        cmd = mock_run.call_args[0][0]
        assert "--repos" in cmd
        assert "Peleke/openclaw" in cmd
        assert "Peleke/cadence" in cmd

    def test_returns_completed_process(self, sync_env):
        vault, _ = sync_env
        profile = SandboxProfile(
            dashboard=Dashboard(vault_path=str(vault)),
        )
        expected = subprocess.CompletedProcess([], 0, "ok", "")
        with patch("sandbox_cli.dashboard.subprocess.run", return_value=expected):
            result = run_dashboard_sync(profile)
        assert result is expected
