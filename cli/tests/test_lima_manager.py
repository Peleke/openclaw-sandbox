"""Tests for LimaManager — VM lifecycle via limactl."""

import json
from pathlib import Path
from unittest.mock import MagicMock, call, patch

import pytest

from sandbox_cli.lima_manager import LimaManager, LimaError, SSHDetails, _parse_ssh_field


# ── helpers ──────────────────────────────────────────────────────────────


def _limactl_list_output(vms: list[dict]) -> str:
    """Lima outputs one JSON object per line, not an array."""
    return "\n".join(json.dumps(vm) for vm in vms)


RUNNING_VM = {"name": "openclaw-sandbox", "status": "Running", "arch": "aarch64", "cpus": 4, "memory": 8589934592, "disk": 53687091200}
STOPPED_VM = {"name": "openclaw-sandbox", "status": "Stopped", "arch": "aarch64", "cpus": 4}
OTHER_VM = {"name": "other-vm", "status": "Running", "arch": "x86_64"}

SSH_CONFIG = """\
Host openclaw-sandbox
  Hostname 127.0.0.1
  Port 52345
  User peleke
  IdentityFile "/Users/peleke/.lima/_config/user"
  IdentityFile "/Users/peleke/.ssh/id_ed25519"
  StrictHostKeyChecking no
"""


@pytest.fixture
def lima():
    return LimaManager()


# ── vm_exists ────────────────────────────────────────────────────────────


class TestVmExists:
    def test_true_when_vm_present(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(
                returncode=0,
                stdout=_limactl_list_output([RUNNING_VM]),
            )
            assert lima.vm_exists() is True

    def test_false_when_vm_absent(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(
                returncode=0,
                stdout=_limactl_list_output([OTHER_VM]),
            )
            assert lima.vm_exists() is False

    def test_false_when_no_vms(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0, stdout="")
            assert lima.vm_exists() is False

    def test_false_when_limactl_fails(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=1, stdout="")
            assert lima.vm_exists() is False

    def test_handles_multiple_vms(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(
                returncode=0,
                stdout=_limactl_list_output([OTHER_VM, RUNNING_VM]),
            )
            assert lima.vm_exists() is True

    def test_handles_malformed_json_line(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(
                returncode=0,
                stdout="not json\n" + json.dumps(RUNNING_VM),
            )
            assert lima.vm_exists() is True


# ── vm_status ────────────────────────────────────────────────────────────


class TestVmStatus:
    def test_running(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(
                returncode=0,
                stdout=_limactl_list_output([RUNNING_VM]),
            )
            assert lima.vm_status() == "Running"

    def test_stopped(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(
                returncode=0,
                stdout=_limactl_list_output([STOPPED_VM]),
            )
            assert lima.vm_status() == "Stopped"

    def test_unknown_when_not_found(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(
                returncode=0,
                stdout=_limactl_list_output([OTHER_VM]),
            )
            assert lima.vm_status() == "unknown"

    def test_unknown_when_limactl_fails(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=1, stdout="")
            assert lima.vm_status() == "unknown"


# ── vm_info ──────────────────────────────────────────────────────────────


class TestVmInfo:
    def test_returns_dict_when_found(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(
                returncode=0,
                stdout=_limactl_list_output([RUNNING_VM]),
            )
            info = lima.vm_info()
            assert info is not None
            assert info["name"] == "openclaw-sandbox"
            assert info["cpus"] == 4

    def test_returns_none_when_not_found(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(
                returncode=0,
                stdout=_limactl_list_output([OTHER_VM]),
            )
            assert lima.vm_info() is None


# ── create / start / stop / delete ───────────────────────────────────────


class TestLifecycle:
    def test_create_calls_limactl_create(self, lima, tmp_path):
        config = tmp_path / "test.yaml"
        config.touch()
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            lima.create(config)
        args = mock.call_args[0][0]
        assert args[0] == "limactl"
        assert args[1] == "create"
        assert "--name=openclaw-sandbox" in args
        assert str(config) in args

    def test_create_raises_on_failure(self, lima, tmp_path):
        config = tmp_path / "test.yaml"
        config.touch()
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=1)
            with pytest.raises(LimaError, match="create failed"):
                lima.create(config)

    def test_start_calls_limactl_start(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            lima.start()
        args = mock.call_args[0][0]
        assert args == ["limactl", "start", "openclaw-sandbox"]

    def test_start_raises_on_failure(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=1)
            with pytest.raises(LimaError, match="start failed"):
                lima.start()

    def test_stop_calls_limactl_stop(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            lima.stop()
        args = mock.call_args[0][0]
        assert args == ["limactl", "stop", "openclaw-sandbox"]

    def test_stop_force_adds_flag(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            lima.stop(force=True)
        args = mock.call_args[0][0]
        assert "--force" in args

    def test_delete_stops_then_deletes(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            lima.delete()
        calls = mock.call_args_list
        assert len(calls) == 2
        # First call: stop --force
        stop_args = calls[0][0][0]
        assert stop_args[0] == "limactl"
        assert "stop" in stop_args
        assert "--force" in stop_args
        # Second call: delete --force
        del_args = calls[1][0][0]
        assert "delete" in del_args
        assert "--force" in del_args

    def test_delete_without_force(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            lima.delete(force=False)
        del_args = mock.call_args_list[1][0][0]
        assert "--force" not in del_args


# ── ensure_running ───────────────────────────────────────────────────────


class TestEnsureRunning:
    def test_creates_and_starts_when_no_vm(self, lima, tmp_path):
        config = tmp_path / "test.yaml"
        config.touch()
        with patch.object(lima, "vm_exists", return_value=False), \
             patch.object(lima, "create") as mock_create, \
             patch.object(lima, "vm_status", return_value="Stopped"), \
             patch.object(lima, "start") as mock_start:
            created = lima.ensure_running(config)
        assert created is True
        mock_create.assert_called_once_with(config)
        mock_start.assert_called_once()

    def test_starts_when_stopped(self, lima, tmp_path):
        config = tmp_path / "test.yaml"
        config.touch()
        with patch.object(lima, "vm_exists", return_value=True), \
             patch.object(lima, "vm_status", return_value="Stopped"), \
             patch.object(lima, "start") as mock_start:
            created = lima.ensure_running(config)
        assert created is False
        mock_start.assert_called_once()

    def test_noop_when_already_running(self, lima, tmp_path):
        config = tmp_path / "test.yaml"
        config.touch()
        with patch.object(lima, "vm_exists", return_value=True), \
             patch.object(lima, "vm_status", return_value="Running"), \
             patch.object(lima, "start") as mock_start:
            created = lima.ensure_running(config)
        assert created is False
        mock_start.assert_not_called()


# ── get_ssh_details ──────────────────────────────────────────────────────


class TestGetSSHDetails:
    def test_parses_ssh_config(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0, stdout=SSH_CONFIG)
            details = lima.get_ssh_details()
        assert details.host == "127.0.0.1"
        assert details.port == 52345
        assert details.user == "peleke"
        assert details.key_path == "/Users/peleke/.lima/_config/user"

    def test_strips_quotes_from_identity_file(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0, stdout=SSH_CONFIG)
            details = lima.get_ssh_details()
        assert '"' not in details.key_path

    def test_raises_when_limactl_fails(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=1, stdout="")
            with pytest.raises(LimaError, match="show-ssh failed"):
                lima.get_ssh_details()

    def test_raises_when_no_identity_file(self, lima):
        ssh_no_key = "Host test\n  Hostname 127.0.0.1\n  Port 22\n  User test\n"
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0, stdout=ssh_no_key)
            with pytest.raises(LimaError, match="SSH key"):
                lima.get_ssh_details()


# ── shell ────────────────────────────────────────────────────────────────


class TestShell:
    def test_shell_execvp(self, lima):
        with patch("sandbox_cli.lima_manager.os.execvp") as mock:
            lima.shell()
        mock.assert_called_once_with(
            "limactl", ["limactl", "shell", "openclaw-sandbox"]
        )

    def test_shell_exec_with_command(self, lima):
        with patch("sandbox_cli.lima_manager.os.execvp") as mock:
            lima.shell_exec("node dist/index.js onboard")
        args = mock.call_args[0][1]
        assert args[-1] == "node dist/index.js onboard"
        assert "bash" in args
        assert "-c" in args


# ── verify_mount ─────────────────────────────────────────────────────────


class TestVerifyMount:
    def test_returns_true_when_dir_exists(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            assert lima.verify_mount("/mnt/openclaw") is True

    def test_returns_false_when_dir_missing(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=1)
            assert lima.verify_mount("/mnt/missing") is False

    def test_calls_limactl_shell_with_test(self, lima):
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            lima.verify_mount("/mnt/openclaw")
        args = mock.call_args[0][0]
        assert args[:2] == ["limactl", "shell"]
        assert "test" in args
        assert "-d" in args
        assert "/mnt/openclaw" in args


# ── _parse_ssh_field ─────────────────────────────────────────────────────


class TestParseSSHField:
    def test_extracts_hostname(self):
        assert _parse_ssh_field(SSH_CONFIG, "Hostname") == "127.0.0.1"

    def test_extracts_port(self):
        assert _parse_ssh_field(SSH_CONFIG, "Port") == "52345"

    def test_extracts_user(self):
        assert _parse_ssh_field(SSH_CONFIG, "User") == "peleke"

    def test_returns_first_identity_file(self):
        result = _parse_ssh_field(SSH_CONFIG, "IdentityFile")
        assert result is not None
        assert "_config/user" in result

    def test_returns_none_for_missing_field(self):
        assert _parse_ssh_field(SSH_CONFIG, "ProxyJump") is None

    def test_handles_leading_whitespace(self):
        config = "  Hostname   10.0.0.1\n"
        assert _parse_ssh_field(config, "Hostname") == "10.0.0.1"


# ── custom vm_name ───────────────────────────────────────────────────────


class TestCustomVmName:
    def test_custom_name_used_in_commands(self):
        lima = LimaManager(vm_name="my-custom-vm")
        with patch("sandbox_cli.lima_manager.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            lima.start()
        args = mock.call_args[0][0]
        assert "my-custom-vm" in args
