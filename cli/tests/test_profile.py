"""Tests for profile load/save round-trip."""

from pathlib import Path

from sandbox_cli.models import SandboxProfile
from sandbox_cli.profile import load_profile, save_profile, PROFILE_PATH


def test_round_trip(tmp_path, monkeypatch):
    """Profile survives a save/load cycle."""
    fake_profile_path = tmp_path / "sandbox-profile.toml"
    monkeypatch.setattr("sandbox_cli.profile.PROFILE_PATH", fake_profile_path)
    monkeypatch.setattr("sandbox_cli.profile.PROFILE_DIR", tmp_path)

    original = SandboxProfile.model_validate(
        {
            "meta": {"bootstrap_dir": "/tmp/sandbox"},
            "mounts": {
                "openclaw": "/tmp/openclaw",
                "config": "/tmp/config",
                "agent_data": "/tmp/agents",
                "buildlog_data": "/tmp/buildlog",
                "secrets": "/tmp/secrets.env",
                "vault": "/tmp/vault",
            },
            "mode": {
                "yolo": True,
                "memgraph": True,
                "memgraph_ports": [7687],
            },
            "resources": {"cpus": 8, "memory": "16GiB", "disk": "100GiB"},
            "extra_vars": {"foo": "bar"},
        }
    )

    save_profile(original)
    assert fake_profile_path.exists()

    loaded = load_profile()
    assert loaded.meta.bootstrap_dir == original.meta.bootstrap_dir
    assert loaded.mounts.openclaw == original.mounts.openclaw
    assert loaded.mounts.vault == original.mounts.vault
    assert loaded.mode.yolo == original.mode.yolo
    assert loaded.mode.memgraph_ports == original.mode.memgraph_ports
    assert loaded.resources.cpus == original.resources.cpus
    assert loaded.resources.memory == original.resources.memory
    assert loaded.extra_vars == original.extra_vars


def test_load_missing_file(tmp_path, monkeypatch):
    """Loading a nonexistent profile returns defaults."""
    monkeypatch.setattr(
        "sandbox_cli.profile.PROFILE_PATH", tmp_path / "nope.toml"
    )
    p = load_profile()
    assert p.meta.bootstrap_dir == ""
    assert p.resources.cpus == 4
