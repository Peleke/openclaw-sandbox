"""Integration tests for Typer subcommands via CliRunner."""

from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest
from typer.testing import CliRunner

from sandbox_cli.app import app
from sandbox_cli.models import SandboxProfile

runner = CliRunner()


@pytest.fixture(autouse=True)
def _fake_sandbox_dir(tmp_path, monkeypatch):
    """Every command test gets a fake sandbox dir so find_bootstrap_dir succeeds."""
    (tmp_path / "bootstrap.sh").touch(mode=0o755)
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    (scripts / "sync-gate.sh").touch(mode=0o755)
    (scripts / "dashboard.sh").touch(mode=0o755)
    monkeypatch.chdir(tmp_path)
    # Also patch load_profile to return a valid-enough profile
    monkeypatch.setattr(
        "sandbox_cli.app.load_profile",
        lambda: SandboxProfile(),
    )


class TestUpCommand:
    def test_up_calls_bootstrap(self):
        with patch("sandbox_cli.app.run_bootstrap", return_value=0) as mock:
            result = runner.invoke(app, ["up"])
        assert result.exit_code == 0
        mock.assert_called_once()
        # Should NOT have --delete in extra_flags
        _, kwargs = mock.call_args
        assert kwargs.get("extra_flags") is None

    def test_up_fresh_deletes_first(self):
        with patch("sandbox_cli.app.run_bootstrap", return_value=0) as mock:
            result = runner.invoke(app, ["up", "--fresh"])
        assert mock.call_count == 2
        # First call is delete
        first_call_kwargs = mock.call_args_list[0][1]
        assert first_call_kwargs["extra_flags"] == ["--delete"]

    def test_up_fresh_aborts_on_delete_failure(self):
        with patch("sandbox_cli.app.run_bootstrap", side_effect=[1]) as mock:
            result = runner.invoke(app, ["up", "--fresh"])
        assert result.exit_code == 1
        assert mock.call_count == 1  # Only the delete call, not the provision


class TestDownCommand:
    def test_down_calls_kill(self):
        with patch("sandbox_cli.app.run_bootstrap", return_value=0) as mock:
            result = runner.invoke(app, ["down"])
        assert result.exit_code == 0
        _, kwargs = mock.call_args
        assert kwargs["extra_flags"] == ["--kill"]


class TestDestroyCommand:
    def test_destroy_prompts_and_calls_delete(self):
        with patch("sandbox_cli.app.run_bootstrap", return_value=0) as mock:
            result = runner.invoke(app, ["destroy"], input="y\n")
        assert result.exit_code == 0
        _, kwargs = mock.call_args
        assert kwargs["extra_flags"] == ["--delete"]

    def test_destroy_aborts_on_no(self):
        with patch("sandbox_cli.app.run_bootstrap") as mock:
            result = runner.invoke(app, ["destroy"], input="n\n")
        mock.assert_not_called()

    def test_destroy_force_skips_prompt(self):
        with patch("sandbox_cli.app.run_bootstrap", return_value=0) as mock:
            result = runner.invoke(app, ["destroy", "-f"])
        assert result.exit_code == 0
        mock.assert_called_once()


class TestStatusCommand:
    def test_status_shows_profile_info(self):
        with patch("sandbox_cli.app.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=1, stdout="", stderr="")
            result = runner.invoke(app, ["status"])
        assert result.exit_code == 0
        assert "Sandbox Status" in result.output

    def test_status_handles_missing_limactl(self):
        with patch(
            "sandbox_cli.app.subprocess.run", side_effect=FileNotFoundError
        ):
            result = runner.invoke(app, ["status"])
        assert result.exit_code == 0
        assert "limactl not installed" in result.output


class TestSyncCommand:
    def test_sync_calls_script(self):
        with patch("sandbox_cli.app.run_script", return_value=0) as mock:
            result = runner.invoke(app, ["sync"])
        assert result.exit_code == 0
        mock.assert_called_once()
        args, kwargs = mock.call_args
        assert args[1] == "sync-gate.sh"
        assert kwargs["extra_flags"] == []

    def test_sync_dry_run(self):
        with patch("sandbox_cli.app.run_script", return_value=0) as mock:
            result = runner.invoke(app, ["sync", "--dry-run"])
        _, kwargs = mock.call_args
        assert kwargs["extra_flags"] == ["--dry-run"]


class TestDashboardCommand:
    def test_dashboard_default_page(self):
        with patch("sandbox_cli.app.run_script", return_value=0) as mock:
            result = runner.invoke(app, ["dashboard"])
        assert result.exit_code == 0
        _, kwargs = mock.call_args
        assert kwargs["extra_flags"] == []

    def test_dashboard_with_page(self):
        with patch("sandbox_cli.app.run_script", return_value=0) as mock:
            result = runner.invoke(app, ["dashboard", "green"])
        _, kwargs = mock.call_args
        assert kwargs["extra_flags"] == ["green"]


class TestHelpOutput:
    def test_help_shows_all_commands(self):
        result = runner.invoke(app, ["--help"])
        assert result.exit_code == 0
        for cmd in ["init", "up", "down", "destroy", "status", "ssh", "onboard", "sync", "dashboard"]:
            assert cmd in result.output
