"""Tests for Ansible inventory builder and playbook invocation."""

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from sandbox_cli.ansible_runner import build_extra_vars, build_inventory, run_playbook
from sandbox_cli.lima_manager import SSHDetails
from sandbox_cli.models import SandboxProfile


# ── fixtures ─────────────────────────────────────────────────────────────


@pytest.fixture
def ssh():
    return SSHDetails(
        host="127.0.0.1",
        port=52345,
        user="testuser",
        key_path="/tmp/id_ed25519",
    )


@pytest.fixture
def bootstrap_dir(tmp_path):
    ansible_dir = tmp_path / "ansible"
    ansible_dir.mkdir()
    (ansible_dir / "playbook.yml").write_text("---\n- hosts: sandbox\n")
    return tmp_path


# ── build_inventory ──────────────────────────────────────────────────────


class TestBuildInventory:
    def test_contains_sandbox_group(self, ssh):
        inv = build_inventory("openclaw-sandbox", ssh)
        assert "[sandbox]" in inv

    def test_contains_vm_name(self, ssh):
        inv = build_inventory("openclaw-sandbox", ssh)
        assert "openclaw-sandbox" in inv

    def test_contains_host_and_port(self, ssh):
        inv = build_inventory("openclaw-sandbox", ssh)
        assert "ansible_host=127.0.0.1" in inv
        assert "ansible_port=52345" in inv

    def test_contains_user_and_key(self, ssh):
        inv = build_inventory("openclaw-sandbox", ssh)
        assert "ansible_user=testuser" in inv
        assert "ansible_ssh_private_key_file=/tmp/id_ed25519" in inv

    def test_disables_host_key_checking(self, ssh):
        inv = build_inventory("openclaw-sandbox", ssh)
        assert "StrictHostKeyChecking=no" in inv
        assert "UserKnownHostsFile=/dev/null" in inv


# ── build_extra_vars ─────────────────────────────────────────────────────


class TestBuildExtraVars:
    def test_default_profile_produces_expected_vars(self):
        profile = SandboxProfile()
        evars = build_extra_vars(profile)
        pairs = dict(zip(evars[::2], evars[1::2]))
        # All values should be -e key=value
        assert all(k == "-e" for k in evars[::2])

    def test_tenant_name_from_current_user(self):
        profile = SandboxProfile()
        evars = build_extra_vars(profile)
        # Should have tenant_name=<something>
        joined = " ".join(evars)
        assert "tenant_name=" in joined

    def test_provision_and_openclaw_paths_hardcoded(self):
        profile = SandboxProfile()
        evars = build_extra_vars(profile)
        values = evars[1::2]  # odd indices are the k=v strings
        assert "provision_path=/mnt/provision" in values
        assert "openclaw_path=/mnt/openclaw" in values
        assert "obsidian_path=/mnt/obsidian" in values

    def test_secrets_filename_included(self, tmp_path):
        sf = tmp_path / "my-secrets.env"
        sf.touch()
        profile = SandboxProfile.model_validate(
            {"mounts": {"secrets": str(sf)}}
        )
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert any("secrets_filename=my-secrets.env" in v for v in values)

    def test_secrets_filename_empty_when_no_secrets(self):
        profile = SandboxProfile()
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert any("secrets_filename=" in v for v in values)
        sec = next(v for v in values if v.startswith("secrets_filename="))
        assert sec == "secrets_filename="

    def test_overlay_yolo_mode_false_by_default(self):
        profile = SandboxProfile()
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "overlay_yolo_mode=false" in values
        assert "overlay_yolo_unsafe=false" in values

    def test_overlay_yolo_mode_true(self):
        profile = SandboxProfile.model_validate({"mode": {"yolo": True}})
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "overlay_yolo_mode=true" in values

    def test_overlay_yolo_unsafe_true(self):
        profile = SandboxProfile.model_validate({"mode": {"yolo_unsafe": True}})
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "overlay_yolo_unsafe=true" in values

    def test_docker_enabled_true_by_default(self):
        profile = SandboxProfile()
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "docker_enabled=true" in values

    def test_docker_enabled_false_when_no_docker(self):
        profile = SandboxProfile.model_validate({"mode": {"no_docker": True}})
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "docker_enabled=false" in values

    def test_agent_data_mount_conditional(self):
        profile = SandboxProfile.model_validate(
            {"mounts": {"agent_data": "/tmp/agents"}}
        )
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "agent_data_mount=/mnt/openclaw-agents" in values

    def test_agent_data_mount_empty_when_unset(self):
        profile = SandboxProfile()
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "agent_data_mount=" in values

    def test_buildlog_data_mount_conditional(self):
        profile = SandboxProfile.model_validate(
            {"mounts": {"buildlog_data": "/tmp/buildlog"}}
        )
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "buildlog_data_mount=/mnt/buildlog-data" in values

    def test_buildlog_data_mount_empty_when_unset(self):
        profile = SandboxProfile()
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "buildlog_data_mount=" in values

    def test_memgraph_enabled_false_by_default(self):
        profile = SandboxProfile()
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "memgraph_enabled=false" in values

    def test_memgraph_enabled_true(self):
        profile = SandboxProfile.model_validate({"mode": {"memgraph": True}})
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "memgraph_enabled=true" in values

    def test_user_extra_vars_appended(self):
        profile = SandboxProfile.model_validate(
            {"extra_vars": {"telegram_user_id": "123456", "custom_key": "val"}}
        )
        evars = build_extra_vars(profile)
        values = evars[1::2]
        assert "telegram_user_id=123456" in values
        assert "custom_key=val" in values

    def test_user_extra_vars_come_after_builtins(self):
        profile = SandboxProfile.model_validate(
            {"extra_vars": {"my_var": "my_val"}}
        )
        evars = build_extra_vars(profile)
        values = evars[1::2]
        # Built-in vars come first, user vars at end
        tenant_idx = next(i for i, v in enumerate(values) if "tenant_name=" in v)
        user_idx = next(i for i, v in enumerate(values) if "my_var=" in v)
        assert user_idx > tenant_idx


# ── run_playbook ─────────────────────────────────────────────────────────


class TestRunPlaybook:
    def test_calls_ansible_playbook(self, ssh, bootstrap_dir):
        profile = SandboxProfile()
        with patch("sandbox_cli.ansible_runner.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            rc = run_playbook(profile, ssh, bootstrap_dir)
        assert rc == 0
        args = mock.call_args[0][0]
        assert args[0] == "ansible-playbook"

    def test_uses_temp_inventory(self, ssh, bootstrap_dir):
        profile = SandboxProfile()
        with patch("sandbox_cli.ansible_runner.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            run_playbook(profile, ssh, bootstrap_dir)
        args = mock.call_args[0][0]
        inv_idx = args.index("-i")
        inv_path = args[inv_idx + 1]
        # Temp file should have been cleaned up after run
        assert not Path(inv_path).exists()

    def test_passes_playbook_path(self, ssh, bootstrap_dir):
        profile = SandboxProfile()
        with patch("sandbox_cli.ansible_runner.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            run_playbook(profile, ssh, bootstrap_dir)
        args = mock.call_args[0][0]
        assert str(bootstrap_dir / "ansible" / "playbook.yml") in args

    def test_sets_ansible_host_key_checking_false(self, ssh, bootstrap_dir):
        profile = SandboxProfile()
        with patch("sandbox_cli.ansible_runner.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            run_playbook(profile, ssh, bootstrap_dir)
        env = mock.call_args[1]["env"]
        assert env["ANSIBLE_HOST_KEY_CHECKING"] == "False"

    def test_returns_nonzero_on_failure(self, ssh, bootstrap_dir):
        profile = SandboxProfile()
        with patch("sandbox_cli.ansible_runner.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=2)
            rc = run_playbook(profile, ssh, bootstrap_dir)
        assert rc == 2

    def test_cleans_up_inventory_on_failure(self, ssh, bootstrap_dir):
        profile = SandboxProfile()
        captured_path = []

        def capture_args(cmd, **kwargs):
            inv_idx = cmd.index("-i")
            captured_path.append(cmd[inv_idx + 1])
            return MagicMock(returncode=1)

        with patch("sandbox_cli.ansible_runner.subprocess.run", side_effect=capture_args):
            run_playbook(profile, ssh, bootstrap_dir)
        assert not Path(captured_path[0]).exists()

    def test_includes_extra_vars(self, ssh, bootstrap_dir):
        profile = SandboxProfile.model_validate(
            {"extra_vars": {"my_key": "my_value"}}
        )
        with patch("sandbox_cli.ansible_runner.subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=0)
            run_playbook(profile, ssh, bootstrap_dir)
        args = mock.call_args[0][0]
        assert "my_key=my_value" in args
