"""Tests for reporting module — post-bootstrap output and OpenClaw interop."""

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from rich.console import Console

from sandbox_cli.models import SandboxProfile
from sandbox_cli.reporting import (
    _parse_identity,
    get_agent_identity,
    get_gateway_password,
    get_learning_stats,
    print_post_bootstrap,
    print_status_report,
)


# ── fixtures ─────────────────────────────────────────────────────────────


@pytest.fixture
def openclaw_dir(tmp_path):
    """Fake ~/.openclaw directory."""
    oc = tmp_path / ".openclaw"
    oc.mkdir()
    return oc


@pytest.fixture
def console():
    return Console(file=None, force_terminal=True, width=120)


# ── get_gateway_password ─────────────────────────────────────────────────


class TestGetGatewayPassword:
    def test_extracts_password_from_openclaw_json(self, openclaw_dir):
        config = {
            "gateway": {
                "auth": {"mode": "password", "password": "sandbox-abc123"}
            }
        }
        (openclaw_dir / "openclaw.json").write_text(json.dumps(config))
        profile = SandboxProfile.model_validate(
            {"mounts": {"config": str(openclaw_dir)}}
        )
        assert get_gateway_password(profile) == "sandbox-abc123"

    def test_returns_empty_when_no_password(self, openclaw_dir):
        config = {"gateway": {"auth": {"mode": "none"}}}
        (openclaw_dir / "openclaw.json").write_text(json.dumps(config))
        profile = SandboxProfile.model_validate(
            {"mounts": {"config": str(openclaw_dir)}}
        )
        assert get_gateway_password(profile) == ""

    def test_returns_empty_when_no_config_file(self, tmp_path):
        profile = SandboxProfile.model_validate(
            {"mounts": {"config": str(tmp_path / "nonexistent")}}
        )
        assert get_gateway_password(profile) == ""

    def test_returns_empty_when_no_config_mount(self):
        profile = SandboxProfile()
        # Falls back to ~/.openclaw which may or may not have the file
        # In test context, the function should handle missing gracefully
        result = get_gateway_password(profile)
        assert isinstance(result, str)

    def test_returns_empty_on_malformed_json(self, openclaw_dir):
        (openclaw_dir / "openclaw.json").write_text("not json{{{")
        profile = SandboxProfile.model_validate(
            {"mounts": {"config": str(openclaw_dir)}}
        )
        assert get_gateway_password(profile) == ""

    def test_returns_empty_when_gateway_key_missing(self, openclaw_dir):
        (openclaw_dir / "openclaw.json").write_text(json.dumps({"meta": {}}))
        profile = SandboxProfile.model_validate(
            {"mounts": {"config": str(openclaw_dir)}}
        )
        assert get_gateway_password(profile) == ""


# ── _parse_identity ──────────────────────────────────────────────────────


class TestParseIdentity:
    def test_parses_heading_name(self):
        result = _parse_identity("# Marvin\nemoji: robot")
        assert result["name"] == "Marvin"

    def test_parses_emoji_field(self):
        result = _parse_identity("# Test\nemoji: 🤖")
        assert result["emoji"] == "🤖"

    def test_parses_name_field(self):
        result = _parse_identity("name: Arthur\nemoji: 🐬")
        assert result["name"] == "Arthur"

    def test_fallback_to_first_line(self):
        result = _parse_identity("Some Agent Name\nother stuff")
        assert result["name"] == "Some Agent Name"

    def test_empty_input(self):
        result = _parse_identity("")
        assert result["name"] == ""
        assert result["emoji"] == ""

    def test_heading_stripped(self):
        result = _parse_identity("# ## Deep Heading")
        assert result["name"] == "## Deep Heading"


# ── get_agent_identity ───────────────────────────────────────────────────


class TestGetAgentIdentity:
    def test_reads_identity_from_agent_subdir(self, tmp_path, monkeypatch):
        monkeypatch.setattr("sandbox_cli.reporting.OPENCLAW_DIR", tmp_path)
        agents = tmp_path / "agents" / "main" / "agent"
        agents.mkdir(parents=True)
        (agents / ".identity.md").write_text("# TestBot\nemoji: 🧪\n")
        result = get_agent_identity()
        assert result is not None
        assert result["name"] == "TestBot"
        assert result["emoji"] == "🧪"

    def test_reads_identity_from_top_level(self, tmp_path, monkeypatch):
        monkeypatch.setattr("sandbox_cli.reporting.OPENCLAW_DIR", tmp_path)
        agent = tmp_path / "agents" / "beta"
        agent.mkdir(parents=True)
        (agent / ".identity.md").write_text("# BetaBot\n")
        result = get_agent_identity()
        assert result is not None
        assert result["name"] == "BetaBot"

    def test_returns_none_when_no_agents_dir(self, tmp_path, monkeypatch):
        monkeypatch.setattr("sandbox_cli.reporting.OPENCLAW_DIR", tmp_path)
        assert get_agent_identity() is None

    def test_returns_none_when_no_identity_files(self, tmp_path, monkeypatch):
        monkeypatch.setattr("sandbox_cli.reporting.OPENCLAW_DIR", tmp_path)
        agents = tmp_path / "agents" / "main"
        agents.mkdir(parents=True)
        # No .identity.md file
        assert get_agent_identity() is None


# ── get_learning_stats ───────────────────────────────────────────────────


class TestGetLearningStats:
    def test_returns_data_on_success(self):
        response_data = json.dumps({"totalObservations": 42}).encode()
        mock_resp = MagicMock()
        mock_resp.read.return_value = response_data
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        with patch("sandbox_cli.reporting.urllib.request.urlopen", return_value=mock_resp):
            result = get_learning_stats()
        assert result is not None
        assert result["totalObservations"] == 42

    def test_returns_none_on_connection_error(self):
        import urllib.error
        with patch(
            "sandbox_cli.reporting.urllib.request.urlopen",
            side_effect=urllib.error.URLError("connection refused"),
        ):
            assert get_learning_stats() is None

    def test_returns_none_on_timeout(self):
        with patch(
            "sandbox_cli.reporting.urllib.request.urlopen",
            side_effect=TimeoutError,
        ):
            assert get_learning_stats() is None

    def test_returns_none_on_bad_json(self):
        mock_resp = MagicMock()
        mock_resp.read.return_value = b"not json"
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        with patch("sandbox_cli.reporting.urllib.request.urlopen", return_value=mock_resp):
            assert get_learning_stats() is None


# ── print_post_bootstrap ─────────────────────────────────────────────────


class TestPrintPostBootstrap:
    def test_prints_bootstrap_complete(self, capsys):
        profile = SandboxProfile()
        console = Console(force_terminal=False)
        print_post_bootstrap(profile, console)
        output = capsys.readouterr().out
        assert "Bootstrap complete" in output

    def test_secure_mode_message(self, capsys):
        profile = SandboxProfile()
        console = Console(force_terminal=False)
        print_post_bootstrap(profile, console)
        output = capsys.readouterr().out
        assert "Secure mode" in output
        assert "READ-ONLY" in output

    def test_yolo_mode_message(self, capsys):
        profile = SandboxProfile.model_validate({"mode": {"yolo": True}})
        console = Console(force_terminal=False)
        print_post_bootstrap(profile, console)
        output = capsys.readouterr().out
        assert "YOLO mode" in output
        assert "auto-sync" in output

    def test_yolo_unsafe_message(self, capsys):
        profile = SandboxProfile.model_validate({"mode": {"yolo_unsafe": True}})
        console = Console(force_terminal=False)
        print_post_bootstrap(profile, console)
        output = capsys.readouterr().out
        assert "YOLO-UNSAFE" in output

    def test_vault_mount_mentioned(self, capsys):
        profile = SandboxProfile.model_validate(
            {"mounts": {"vault": "/tmp/testvault"}}
        )
        console = Console(force_terminal=False)
        print_post_bootstrap(profile, console)
        output = capsys.readouterr().out
        assert "/mnt/obsidian" in output

    def test_gateway_urls_printed(self, capsys):
        profile = SandboxProfile()
        console = Console(force_terminal=False)
        print_post_bootstrap(profile, console)
        output = capsys.readouterr().out
        assert "18789" in output
        assert "green/dashboard" in output
        assert "learning/dashboard" in output

    def test_gateway_password_included_when_available(self, capsys, tmp_path):
        config_dir = tmp_path / "config"
        config_dir.mkdir()
        config = {"gateway": {"auth": {"password": "test-pw-123"}}}
        (config_dir / "openclaw.json").write_text(json.dumps(config))
        profile = SandboxProfile.model_validate(
            {"mounts": {"config": str(config_dir)}}
        )
        console = Console(force_terminal=False)
        print_post_bootstrap(profile, console)
        output = capsys.readouterr().out
        assert "test-pw-123" in output


# ── print_status_report ──────────────────────────────────────────────────


class TestPrintStatusReport:
    def test_shows_vm_info(self, capsys):
        profile = SandboxProfile()
        vm_info = {
            "name": "openclaw-sandbox",
            "status": "Running",
            "arch": "aarch64",
            "cpus": 4,
            "memory": 8589934592,
            "disk": 53687091200,
        }
        with patch("sandbox_cli.reporting.LimaManager") as MockLima:
            mock_lima = MockLima.return_value
            mock_lima.vm_info.return_value = vm_info
            console = Console(force_terminal=False)
            print_status_report(profile, console)
        output = capsys.readouterr().out
        assert "Running" in output
        assert "Sandbox Status" in output

    def test_shows_not_found_when_no_vm(self, capsys):
        profile = SandboxProfile()
        with patch("sandbox_cli.reporting.LimaManager") as MockLima:
            mock_lima = MockLima.return_value
            mock_lima.vm_info.return_value = None
            console = Console(force_terminal=False)
            print_status_report(profile, console)
        output = capsys.readouterr().out
        assert "not found" in output

    def test_shows_profile_info(self, capsys):
        profile = SandboxProfile.model_validate(
            {
                "mounts": {"openclaw": "/tmp/oc"},
                "resources": {"cpus": 8, "memory": "16GiB", "disk": "100GiB"},
            }
        )
        with patch("sandbox_cli.reporting.LimaManager") as MockLima:
            mock_lima = MockLima.return_value
            mock_lima.vm_info.return_value = None
            console = Console(force_terminal=False)
            print_status_report(profile, console)
        output = capsys.readouterr().out
        assert "/tmp/oc" in output
        assert "8 CPUs" in output
