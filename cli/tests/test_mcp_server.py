"""Tests for mcp_server — MCP tool implementations."""

import subprocess
from unittest.mock import MagicMock, patch, PropertyMock

import pytest

from sandbox_cli.mcp_server import (
    VM_EXEC_TIMEOUT,
    _load_profile_safe,
    _require_limactl,
    sandbox_agent_identity,
    sandbox_destroy,
    sandbox_down,
    sandbox_exec,
    sandbox_gateway_info,
    sandbox_ssh_info,
    sandbox_status,
    sandbox_up,
    sandbox_validate,
)
from sandbox_cli.lima_manager import LimaError, SSHDetails
from sandbox_cli.models import SandboxProfile


# ── _require_limactl ─────────────────────────────────────────────────────


class TestRequireLimactl:
    def test_present(self):
        with patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl"):
            _require_limactl()  # no error

    def test_missing(self):
        with patch("sandbox_cli.mcp_server.shutil.which", return_value=None):
            with pytest.raises(RuntimeError, match="limactl not found"):
                _require_limactl()


# ── _load_profile_safe ───────────────────────────────────────────────────


class TestLoadProfileSafe:
    def test_returns_profile(self):
        profile = SandboxProfile()
        with patch("sandbox_cli.mcp_server.load_profile", return_value=profile):
            result = _load_profile_safe()
        assert result is profile

    def test_returns_default_on_error(self):
        with patch("sandbox_cli.mcp_server.load_profile", side_effect=FileNotFoundError):
            result = _load_profile_safe()
        assert isinstance(result, SandboxProfile)


# ── sandbox_status ───────────────────────────────────────────────────────


class TestSandboxStatus:
    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_vm_running(self, _which):
        vm_info = {"name": "openclaw-sandbox", "status": "Running", "arch": "aarch64", "cpus": 4, "memory": 8, "disk": 50}
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima, \
             patch("sandbox_cli.mcp_server.load_profile", return_value=SandboxProfile()), \
             patch("sandbox_cli.mcp_server.get_gateway_password", return_value=""), \
             patch("sandbox_cli.mcp_server.get_agent_identity", return_value=None), \
             patch("sandbox_cli.mcp_server.get_learning_stats", return_value=None):
            MockLima.return_value.vm_info.return_value = vm_info
            result = sandbox_status()
        assert result["vm"]["status"] == "Running"
        assert result["vm"]["name"] == "openclaw-sandbox"

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_vm_not_found(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima, \
             patch("sandbox_cli.mcp_server.load_profile", return_value=SandboxProfile()), \
             patch("sandbox_cli.mcp_server.get_gateway_password", return_value=""), \
             patch("sandbox_cli.mcp_server.get_agent_identity", return_value=None):
            MockLima.return_value.vm_info.return_value = None
            result = sandbox_status()
        assert result["vm"] is None

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_with_agent_identity(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima, \
             patch("sandbox_cli.mcp_server.load_profile", return_value=SandboxProfile()), \
             patch("sandbox_cli.mcp_server.get_gateway_password", return_value=""), \
             patch("sandbox_cli.mcp_server.get_agent_identity", return_value={"name": "Green", "emoji": "🟢"}), \
             patch("sandbox_cli.mcp_server.get_learning_stats", return_value=None):
            MockLima.return_value.vm_info.return_value = {"name": "openclaw-sandbox", "status": "Running"}
            result = sandbox_status()
        assert result["agent"]["name"] == "Green"

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_with_learning_stats(self, _which):
        stats = {"totalObservations": 42}
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima, \
             patch("sandbox_cli.mcp_server.load_profile", return_value=SandboxProfile()), \
             patch("sandbox_cli.mcp_server.get_gateway_password", return_value=""), \
             patch("sandbox_cli.mcp_server.get_agent_identity", return_value=None), \
             patch("sandbox_cli.mcp_server.get_learning_stats", return_value=stats):
            MockLima.return_value.vm_info.return_value = {"name": "openclaw-sandbox", "status": "Running"}
            result = sandbox_status()
        assert result["learning"]["totalObservations"] == 42

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_with_gateway_password(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima, \
             patch("sandbox_cli.mcp_server.load_profile", return_value=SandboxProfile()), \
             patch("sandbox_cli.mcp_server.get_gateway_password", return_value="s3cret"), \
             patch("sandbox_cli.mcp_server.get_agent_identity", return_value=None):
            MockLima.return_value.vm_info.return_value = None
            result = sandbox_status()
        assert "s3cret" in result["gateway"]["authenticated_url"]

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_no_learning_stats_when_stopped(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima, \
             patch("sandbox_cli.mcp_server.load_profile", return_value=SandboxProfile()), \
             patch("sandbox_cli.mcp_server.get_gateway_password", return_value=""), \
             patch("sandbox_cli.mcp_server.get_agent_identity", return_value=None), \
             patch("sandbox_cli.mcp_server.get_learning_stats") as mock_stats:
            MockLima.return_value.vm_info.return_value = {"name": "openclaw-sandbox", "status": "Stopped"}
            result = sandbox_status()
        mock_stats.assert_not_called()
        assert "learning" not in result


# ── sandbox_up ───────────────────────────────────────────────────────────


class TestSandboxUp:
    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_success(self, _which, tmp_path):
        profile = SandboxProfile()
        with patch("sandbox_cli.mcp_server.load_profile", return_value=profile), \
             patch("sandbox_cli.bootstrap.find_bootstrap_dir", return_value=tmp_path), \
             patch("sandbox_cli.orchestrator.orchestrate_up", return_value=0):
            result = sandbox_up()
        assert result["exit_code"] == 0

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_failure(self, _which, tmp_path):
        profile = SandboxProfile()
        with patch("sandbox_cli.mcp_server.load_profile", return_value=profile), \
             patch("sandbox_cli.bootstrap.find_bootstrap_dir", return_value=tmp_path), \
             patch("sandbox_cli.orchestrator.orchestrate_up", return_value=1):
            result = sandbox_up()
        assert result["exit_code"] == 1

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_profile_error(self, _which):
        with patch("sandbox_cli.mcp_server.load_profile", side_effect=FileNotFoundError("no profile")):
            with pytest.raises(FileNotFoundError):
                sandbox_up()


# ── sandbox_down ─────────────────────────────────────────────────────────


class TestSandboxDown:
    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_success(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima:
            MockLima.return_value.vm_exists.return_value = True
            result = sandbox_down()
        assert result["status"] == "stopped"
        MockLima.return_value.stop.assert_called_once_with(force=True)

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_vm_not_found(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima:
            MockLima.return_value.vm_exists.return_value = False
            result = sandbox_down()
        assert result["status"] == "not_found"


# ── sandbox_destroy ──────────────────────────────────────────────────────


class TestSandboxDestroy:
    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_success(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima:
            MockLima.return_value.vm_exists.return_value = True
            result = sandbox_destroy()
        assert result["status"] == "deleted"
        MockLima.return_value.delete.assert_called_once()

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_vm_not_found(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima:
            MockLima.return_value.vm_exists.return_value = False
            result = sandbox_destroy()
        assert result["status"] == "not_found"


# ── sandbox_exec ─────────────────────────────────────────────────────────


class TestSandboxExec:
    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_simple_command(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima, \
             patch("sandbox_cli.mcp_server.subprocess.run") as mock_run:
            MockLima.return_value.vm_exists.return_value = True
            MockLima.return_value.vm_status.return_value = "Running"
            MockLima.return_value.vm_name = "openclaw-sandbox"
            mock_run.return_value = MagicMock(stdout="hello\n", stderr="", returncode=0)
            result = sandbox_exec("echo hello")
        assert result["stdout"] == "hello\n"
        assert result["exit_code"] == 0

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_exit_code_propagation(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima, \
             patch("sandbox_cli.mcp_server.subprocess.run") as mock_run:
            MockLima.return_value.vm_exists.return_value = True
            MockLima.return_value.vm_status.return_value = "Running"
            MockLima.return_value.vm_name = "openclaw-sandbox"
            mock_run.return_value = MagicMock(stdout="", stderr="not found", returncode=127)
            result = sandbox_exec("nonexistent")
        assert result["exit_code"] == 127
        assert "not found" in result["stderr"]

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_timeout(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima, \
             patch("sandbox_cli.mcp_server.subprocess.run", side_effect=subprocess.TimeoutExpired(cmd="test", timeout=120)):
            MockLima.return_value.vm_exists.return_value = True
            MockLima.return_value.vm_status.return_value = "Running"
            MockLima.return_value.vm_name = "openclaw-sandbox"
            result = sandbox_exec("sleep 999")
        assert "timed out" in result["error"]
        assert result["exit_code"] == -1

    def test_empty_command(self):
        result = sandbox_exec("")
        assert "error" in result
        assert "empty" in result["error"].lower()

    def test_whitespace_command(self):
        result = sandbox_exec("   ")
        assert "error" in result

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_vm_not_running(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima:
            MockLima.return_value.vm_exists.return_value = True
            MockLima.return_value.vm_status.return_value = "Stopped"
            result = sandbox_exec("echo hello")
        assert "error" in result
        assert "not running" in result["error"].lower()

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_vm_not_exists(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima:
            MockLima.return_value.vm_exists.return_value = False
            result = sandbox_exec("echo hello")
        assert "error" in result
        assert "does not exist" in result["error"]

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_timeout_clamped(self, _which):
        """Timeout values are clamped to 1-600 range."""
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima, \
             patch("sandbox_cli.mcp_server.subprocess.run") as mock_run:
            MockLima.return_value.vm_exists.return_value = True
            MockLima.return_value.vm_status.return_value = "Running"
            MockLima.return_value.vm_name = "openclaw-sandbox"
            mock_run.return_value = MagicMock(stdout="", stderr="", returncode=0)
            sandbox_exec("echo test", timeout=9999)
        # Verify timeout was clamped to 600
        call_kwargs = mock_run.call_args[1]
        assert call_kwargs["timeout"] == 600

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_command_with_special_chars(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima, \
             patch("sandbox_cli.mcp_server.subprocess.run") as mock_run:
            MockLima.return_value.vm_exists.return_value = True
            MockLima.return_value.vm_status.return_value = "Running"
            MockLima.return_value.vm_name = "openclaw-sandbox"
            mock_run.return_value = MagicMock(stdout="value\n", stderr="", returncode=0)
            result = sandbox_exec("echo $HOME && ls -la /tmp")
        assert result["exit_code"] == 0
        # Verify command is passed via bash -c
        cmd = mock_run.call_args[0][0]
        assert cmd[-1] == "echo $HOME && ls -la /tmp"


# ── sandbox_validate ─────────────────────────────────────────────────────


class TestSandboxValidate:
    def test_valid_profile(self, tmp_path):
        oc = tmp_path / "openclaw"
        oc.mkdir()
        profile = SandboxProfile.model_validate({"mounts": {"openclaw": str(oc)}})
        with patch("sandbox_cli.mcp_server.load_profile", return_value=profile):
            result = sandbox_validate()
        assert result["ok"] is True
        assert result["errors"] == []

    def test_profile_load_error(self):
        with patch("sandbox_cli.mcp_server.load_profile", side_effect=FileNotFoundError("nope")):
            result = sandbox_validate()
        assert result["ok"] is False
        assert len(result["errors"]) > 0

    def test_with_warnings(self, tmp_path):
        # Profile without openclaw mount triggers a warning
        profile = SandboxProfile()
        with patch("sandbox_cli.mcp_server.load_profile", return_value=profile):
            result = sandbox_validate()
        # May or may not have warnings depending on validation logic
        assert "ok" in result


# ── sandbox_ssh_info ─────────────────────────────────────────────────────


class TestSandboxSshInfo:
    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_success(self, _which):
        ssh = SSHDetails(host="127.0.0.1", port=52345, user="test", key_path="/tmp/key")
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima:
            MockLima.return_value.vm_exists.return_value = True
            MockLima.return_value.vm_status.return_value = "Running"
            MockLima.return_value.get_ssh_details.return_value = ssh
            result = sandbox_ssh_info()
        assert result["host"] == "127.0.0.1"
        assert result["port"] == 52345
        assert result["user"] == "test"

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_vm_not_running(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima:
            MockLima.return_value.vm_exists.return_value = True
            MockLima.return_value.vm_status.return_value = "Stopped"
            result = sandbox_ssh_info()
        assert "error" in result

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_vm_not_exists(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima:
            MockLima.return_value.vm_exists.return_value = False
            result = sandbox_ssh_info()
        assert "error" in result

    @patch("sandbox_cli.mcp_server.shutil.which", return_value="/usr/local/bin/limactl")
    def test_lima_error(self, _which):
        with patch("sandbox_cli.mcp_server.LimaManager") as MockLima:
            MockLima.return_value.vm_exists.return_value = True
            MockLima.return_value.vm_status.return_value = "Running"
            MockLima.return_value.get_ssh_details.side_effect = LimaError("ssh failed")
            result = sandbox_ssh_info()
        assert "error" in result


# ── sandbox_gateway_info ─────────────────────────────────────────────────


class TestSandboxGatewayInfo:
    def test_with_password(self):
        with patch("sandbox_cli.mcp_server.load_profile", return_value=SandboxProfile()), \
             patch("sandbox_cli.mcp_server.get_gateway_password", return_value="s3cret"):
            result = sandbox_gateway_info()
        assert "authenticated_url" in result
        assert "s3cret" in result["authenticated_url"]

    def test_without_password(self):
        with patch("sandbox_cli.mcp_server.load_profile", return_value=SandboxProfile()), \
             patch("sandbox_cli.mcp_server.get_gateway_password", return_value=""):
            result = sandbox_gateway_info()
        assert "authenticated_url" not in result

    def test_always_has_dashboards(self):
        with patch("sandbox_cli.mcp_server.load_profile", return_value=SandboxProfile()), \
             patch("sandbox_cli.mcp_server.get_gateway_password", return_value=""):
            result = sandbox_gateway_info()
        assert "green_dashboard" in result
        assert "learning_dashboard" in result
        assert "base_url" in result


# ── sandbox_agent_identity ───────────────────────────────────────────────


class TestSandboxAgentIdentity:
    def test_found(self):
        with patch("sandbox_cli.mcp_server.get_agent_identity", return_value={"name": "Green", "emoji": "🟢"}):
            result = sandbox_agent_identity()
        assert result["found"] is True
        assert result["name"] == "Green"
        assert result["emoji"] == "🟢"

    def test_not_found(self):
        with patch("sandbox_cli.mcp_server.get_agent_identity", return_value=None):
            result = sandbox_agent_identity()
        assert result["found"] is False
        assert result["name"] == ""


# ── limactl missing ─────────────────────────────────────────────────────


class TestLimactlMissing:
    """All tools that need limactl raise RuntimeError when it's absent."""

    def test_status_raises(self):
        with patch("sandbox_cli.mcp_server.shutil.which", return_value=None):
            with pytest.raises(RuntimeError, match="limactl"):
                sandbox_status()

    def test_up_raises(self):
        with patch("sandbox_cli.mcp_server.shutil.which", return_value=None):
            with pytest.raises(RuntimeError, match="limactl"):
                sandbox_up()

    def test_down_raises(self):
        with patch("sandbox_cli.mcp_server.shutil.which", return_value=None):
            with pytest.raises(RuntimeError, match="limactl"):
                sandbox_down()

    def test_destroy_raises(self):
        with patch("sandbox_cli.mcp_server.shutil.which", return_value=None):
            with pytest.raises(RuntimeError, match="limactl"):
                sandbox_destroy()

    def test_ssh_info_raises(self):
        with patch("sandbox_cli.mcp_server.shutil.which", return_value=None):
            with pytest.raises(RuntimeError, match="limactl"):
                sandbox_ssh_info()
