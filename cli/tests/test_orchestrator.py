"""Tests for orchestrator — the top-level up flow."""

import subprocess
from pathlib import Path
from unittest.mock import MagicMock, patch, call

import pytest

from sandbox_cli.lima_config import LimaConfigContext
from sandbox_cli.lima_manager import LimaError, LimaManager, SSHDetails
from sandbox_cli.models import SandboxProfile
from sandbox_cli.orchestrator import orchestrate_up, _sync_vault


# ── fixtures ─────────────────────────────────────────────────────────────


@pytest.fixture
def bootstrap_dir(tmp_path):
    """Fake bootstrap dir with all expected subdirs."""
    (tmp_path / "bootstrap.sh").touch()
    (tmp_path / "lima").mkdir()
    (tmp_path / "brew").mkdir()
    (tmp_path / "brew" / "Brewfile").write_text('brew "lima"\n')
    ansible = tmp_path / "ansible"
    ansible.mkdir()
    (ansible / "playbook.yml").write_text("---\n- hosts: sandbox\n")
    (ansible / "requirements.yml").write_text("collections:\n  - community.general\n")
    return tmp_path


@pytest.fixture
def profile(tmp_path):
    oc = tmp_path / "openclaw"
    oc.mkdir()
    return SandboxProfile.model_validate(
        {"mounts": {"openclaw": str(oc)}}
    )


@pytest.fixture
def ssh():
    return SSHDetails(
        host="127.0.0.1", port=52345, user="test", key_path="/tmp/key"
    )


@pytest.fixture
def mock_lima(ssh):
    """A fully mocked LimaManager for happy-path tests."""
    lima = MagicMock(spec=LimaManager)
    lima.vm_exists.return_value = False
    lima.ensure_running.return_value = True
    lima.verify_mount.return_value = True
    lima.get_ssh_details.return_value = ssh
    lima.vm_name = "openclaw-sandbox"
    return lima


# ── happy path ───────────────────────────────────────────────────────────


class TestOrchestrateUpHappyPath:
    def test_returns_0_on_success(self, profile, bootstrap_dir, mock_lima):
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0), \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=0), \
             patch("sandbox_cli.orchestrator.print_post_bootstrap"):
            rc = orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        assert rc == 0

    def test_writes_config_when_vm_absent(self, profile, bootstrap_dir, mock_lima):
        mock_lima.vm_exists.return_value = False
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0), \
             patch("sandbox_cli.orchestrator.write_config") as mock_write, \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=0), \
             patch("sandbox_cli.orchestrator.print_post_bootstrap"):
            mock_write.return_value = bootstrap_dir / "lima" / "openclaw-sandbox.generated.yaml"
            orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        mock_write.assert_called_once()

    def test_skips_config_when_vm_exists(self, profile, bootstrap_dir, mock_lima):
        mock_lima.vm_exists.return_value = True
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0), \
             patch("sandbox_cli.orchestrator.write_config") as mock_write, \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=0), \
             patch("sandbox_cli.orchestrator.print_post_bootstrap"):
            orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        mock_write.assert_not_called()

    def test_calls_ensure_running(self, profile, bootstrap_dir, mock_lima):
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0), \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=0), \
             patch("sandbox_cli.orchestrator.print_post_bootstrap"):
            orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        mock_lima.ensure_running.assert_called_once()

    def test_verifies_mounts(self, profile, bootstrap_dir, mock_lima):
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0), \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=0), \
             patch("sandbox_cli.orchestrator.print_post_bootstrap"):
            orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        assert mock_lima.verify_mount.call_count >= 2  # at least openclaw + provision

    def test_runs_ansible(self, profile, bootstrap_dir, mock_lima, ssh):
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0), \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=0) as mock_pb, \
             patch("sandbox_cli.orchestrator.print_post_bootstrap"):
            orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        mock_pb.assert_called_once_with(profile, ssh, bootstrap_dir)

    def test_prints_report(self, profile, bootstrap_dir, mock_lima):
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0), \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=0), \
             patch("sandbox_cli.orchestrator.print_post_bootstrap") as mock_report:
            orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        mock_report.assert_called_once()


# ── failure paths ────────────────────────────────────────────────────────


class TestOrchestrateUpFailures:
    def test_fails_when_brew_missing(self, profile, bootstrap_dir, mock_lima):
        from sandbox_cli.deps import DependencyError
        with patch("sandbox_cli.orchestrator.check_brew", side_effect=DependencyError("no brew")):
            rc = orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        assert rc == 1

    def test_fails_when_brew_bundle_fails(self, profile, bootstrap_dir, mock_lima):
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=1):
            rc = orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        assert rc == 1

    def test_fails_when_no_openclaw_mount_for_new_vm(self, bootstrap_dir, mock_lima):
        profile = SandboxProfile()  # no openclaw mount
        mock_lima.vm_exists.return_value = False
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0):
            rc = orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        assert rc == 1

    def test_fails_when_lima_ensure_running_fails(self, profile, bootstrap_dir, mock_lima):
        mock_lima.ensure_running.side_effect = LimaError("boom")
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0):
            rc = orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        assert rc == 1

    def test_fails_when_mount_missing(self, profile, bootstrap_dir, mock_lima):
        mock_lima.verify_mount.return_value = False
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0):
            rc = orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        assert rc == 1

    def test_fails_when_ssh_details_fail(self, profile, bootstrap_dir, mock_lima):
        mock_lima.get_ssh_details.side_effect = LimaError("no ssh")
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0):
            rc = orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        assert rc == 1

    def test_fails_when_ansible_fails(self, profile, bootstrap_dir, mock_lima):
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0), \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=2):
            rc = orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        assert rc == 2

    def test_ansible_galaxy_failure_is_nonfatal(self, profile, bootstrap_dir, mock_lima):
        """ansible-galaxy install failing should not stop the whole flow."""
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=1), \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=0), \
             patch("sandbox_cli.orchestrator.print_post_bootstrap"):
            rc = orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        assert rc == 0


# ── vault sync ──────────────────────────────────────────────────────────


class TestSyncVault:
    @pytest.fixture
    def vault_dir(self, tmp_path):
        vault = tmp_path / "vault"
        vault.mkdir()
        (vault / "daily.md").write_text("# daily")
        return vault

    @pytest.fixture
    def vault_profile(self, tmp_path, vault_dir):
        oc = tmp_path / "openclaw"
        oc.mkdir()
        return SandboxProfile.model_validate(
            {"mounts": {"openclaw": str(oc), "vault": str(vault_dir)}}
        )

    @pytest.fixture
    def ssh(self):
        return SSHDetails(
            host="127.0.0.1", port=52345, user="test", key_path="/tmp/key"
        )

    def test_sync_calls_rsync(self, vault_profile, vault_dir, ssh):
        with patch("sandbox_cli.orchestrator.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            from rich.console import Console
            from io import StringIO
            _sync_vault(vault_profile, ssh, Console(file=StringIO()))
        mock_run.assert_called_once()
        args = mock_run.call_args[0][0]
        assert args[0] == "rsync"
        assert "-a" in args
        assert "--delete" in args
        assert f"{vault_dir}/" in args
        assert "test@127.0.0.1:/workspace-obsidian/" in args
        assert "--exclude=.obsidian/" in args

    def test_sync_uses_ssh_details(self, vault_profile, vault_dir, ssh):
        with patch("sandbox_cli.orchestrator.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            from rich.console import Console
            from io import StringIO
            _sync_vault(vault_profile, ssh, Console(file=StringIO()))
        args = mock_run.call_args[0][0]
        ssh_arg = args[args.index("-e") + 1]
        assert "-p 52345" in ssh_arg
        assert "-i /tmp/key" in ssh_arg

    def test_sync_skips_when_vault_dir_missing(self, tmp_path, ssh):
        profile = SandboxProfile.model_validate(
            {"mounts": {"openclaw": str(tmp_path), "vault": "/nonexistent/path"}}
        )
        with patch("sandbox_cli.orchestrator.subprocess.run") as mock_run:
            from rich.console import Console
            from io import StringIO
            _sync_vault(profile, ssh, Console(file=StringIO()))
        mock_run.assert_not_called()

    def test_sync_handles_rsync_failure(self, vault_profile, vault_dir, ssh):
        with patch("sandbox_cli.orchestrator.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=1, stderr="rsync error")
            from rich.console import Console
            from io import StringIO
            buf = StringIO()
            _sync_vault(vault_profile, ssh, Console(file=buf))
        # Should not raise — failure is non-fatal
        output = buf.getvalue()
        assert "failed" in output.lower()

    def test_orchestrate_up_calls_vault_sync(self, vault_profile, bootstrap_dir, mock_lima):
        """Vault sync runs after ansible when vault is configured."""
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0), \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=0), \
             patch("sandbox_cli.orchestrator.print_post_bootstrap"), \
             patch("sandbox_cli.orchestrator._sync_vault") as mock_sync:
            orchestrate_up(vault_profile, bootstrap_dir, lima=mock_lima)
        mock_sync.assert_called_once()

    def test_orchestrate_up_skips_vault_sync_without_vault(self, profile, bootstrap_dir, mock_lima):
        """No vault in profile → no vault sync."""
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0), \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=0), \
             patch("sandbox_cli.orchestrator.print_post_bootstrap"), \
             patch("sandbox_cli.orchestrator._sync_vault") as mock_sync:
            orchestrate_up(profile, bootstrap_dir, lima=mock_lima)
        mock_sync.assert_not_called()

    def test_orchestrate_up_skips_vault_sync_in_yolo_unsafe(self, vault_profile, bootstrap_dir, mock_lima):
        """yolo_unsafe → no overlay → no vault sync needed."""
        vault_profile.mode.yolo_unsafe = True
        with patch("sandbox_cli.orchestrator.check_brew"), \
             patch("sandbox_cli.orchestrator.install_brew_deps", return_value=0), \
             patch("sandbox_cli.orchestrator.install_ansible_collections", return_value=0), \
             patch("sandbox_cli.orchestrator.run_playbook", return_value=0), \
             patch("sandbox_cli.orchestrator.print_post_bootstrap"), \
             patch("sandbox_cli.orchestrator._sync_vault") as mock_sync:
            orchestrate_up(vault_profile, bootstrap_dir, lima=mock_lima)
        mock_sync.assert_not_called()
