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
    (tmp_path / "lima").mkdir()
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
    def test_up_calls_orchestrate(self):
        with patch("sandbox_cli.app.orchestrate_up", return_value=0) as mock:
            result = runner.invoke(app, ["up"])
        assert result.exit_code == 0
        mock.assert_called_once()

    def test_up_fresh_deletes_then_orchestrates(self):
        with patch("sandbox_cli.app.LimaManager") as MockLima, \
             patch("sandbox_cli.app.orchestrate_up", return_value=0) as mock_orch:
            result = runner.invoke(app, ["up", "--fresh"])
        MockLima.return_value.delete.assert_called_once()
        mock_orch.assert_called_once()

    def test_up_returns_orchestrate_exit_code(self):
        with patch("sandbox_cli.app.orchestrate_up", return_value=3):
            result = runner.invoke(app, ["up"])
        assert result.exit_code == 3


class TestDownCommand:
    def test_down_calls_lima_stop(self):
        with patch("sandbox_cli.app.LimaManager") as MockLima:
            result = runner.invoke(app, ["down"])
        assert result.exit_code == 0
        MockLima.return_value.stop.assert_called_once_with(force=True)


class TestDestroyCommand:
    def test_destroy_prompts_and_calls_delete(self):
        with patch("sandbox_cli.app.LimaManager") as MockLima:
            result = runner.invoke(app, ["destroy"], input="y\n")
        assert result.exit_code == 0
        MockLima.return_value.delete.assert_called_once()

    def test_destroy_aborts_on_no(self):
        with patch("sandbox_cli.app.LimaManager") as MockLima:
            result = runner.invoke(app, ["destroy"], input="n\n")
        MockLima.return_value.delete.assert_not_called()

    def test_destroy_force_skips_prompt(self):
        with patch("sandbox_cli.app.LimaManager") as MockLima:
            result = runner.invoke(app, ["destroy", "-f"])
        assert result.exit_code == 0
        MockLima.return_value.delete.assert_called_once()


class TestStatusCommand:
    def test_status_calls_print_status_report(self):
        with patch("sandbox_cli.app.print_status_report") as mock:
            result = runner.invoke(app, ["status"])
        assert result.exit_code == 0
        mock.assert_called_once()


class TestSshCommand:
    def test_ssh_calls_lima_shell(self):
        with patch("sandbox_cli.app.LimaManager") as MockLima:
            result = runner.invoke(app, ["ssh"])
        MockLima.return_value.shell.assert_called_once()


class TestOnboardCommand:
    def test_onboard_calls_lima_shell_exec(self):
        with patch("sandbox_cli.app.LimaManager") as MockLima:
            result = runner.invoke(app, ["onboard"])
        MockLima.return_value.shell_exec.assert_called_once()
        cmd = MockLima.return_value.shell_exec.call_args[0][0]
        assert "onboard" in cmd


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
