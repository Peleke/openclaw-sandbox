"""Tests for subprocess delegation: run_bootstrap, exec_bootstrap, run_script."""

from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

from sandbox_cli.bootstrap import run_bootstrap, run_script
from sandbox_cli.models import SandboxProfile


@pytest.fixture()
def sandbox_dir(tmp_path, monkeypatch):
    """Create a fake sandbox directory with bootstrap.sh and scripts/."""
    (tmp_path / "bootstrap.sh").touch(mode=0o755)
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    (scripts / "sync-gate.sh").touch(mode=0o755)
    (scripts / "dashboard.sh").touch(mode=0o755)
    monkeypatch.chdir(tmp_path)
    return tmp_path


def _profile_with_mounts() -> SandboxProfile:
    return SandboxProfile.model_validate(
        {
            "mounts": {
                "openclaw": "/tmp/openclaw",
                "secrets": "/tmp/secrets.env",
            },
            "mode": {"yolo": True},
            "resources": {"cpus": 6, "memory": "12GiB", "disk": "80GiB"},
        }
    )


class TestRunBootstrap:
    def test_builds_correct_argv_and_env(self, sandbox_dir):
        profile = _profile_with_mounts()
        with patch("sandbox_cli.bootstrap.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            rc = run_bootstrap(profile)

        assert rc == 0
        call_args = mock_run.call_args
        argv = call_args[0][0]
        env = call_args[1]["env"]

        assert argv[0] == str(sandbox_dir / "bootstrap.sh")
        assert "--openclaw" in argv
        assert "/tmp/openclaw" in argv
        assert "--secrets" in argv
        assert "--yolo" in argv
        assert env["VM_CPUS"] == "6"
        assert env["VM_MEMORY"] == "12GiB"
        assert env["VM_DISK"] == "80GiB"

    def test_extra_flags_appended(self, sandbox_dir):
        profile = SandboxProfile()
        with patch("sandbox_cli.bootstrap.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            run_bootstrap(profile, extra_flags=["--delete"])

        argv = mock_run.call_args[0][0]
        assert argv[-1] == "--delete"

    def test_returns_nonzero_on_failure(self, sandbox_dir):
        profile = SandboxProfile()
        with patch("sandbox_cli.bootstrap.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=1)
            rc = run_bootstrap(profile)
        assert rc == 1


class TestRunScript:
    def test_runs_existing_script(self, sandbox_dir):
        profile = SandboxProfile()
        with patch("sandbox_cli.bootstrap.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            rc = run_script(profile, "sync-gate.sh", extra_flags=["--dry-run"])

        assert rc == 0
        argv = mock_run.call_args[0][0]
        assert "sync-gate.sh" in argv[0]
        assert "--dry-run" in argv

    def test_returns_1_for_missing_script(self, sandbox_dir):
        profile = SandboxProfile()
        rc = run_script(profile, "nonexistent.sh")
        assert rc == 1

    def test_rejects_path_traversal(self, sandbox_dir):
        profile = SandboxProfile()
        rc = run_script(profile, "../../etc/passwd")
        assert rc == 1
