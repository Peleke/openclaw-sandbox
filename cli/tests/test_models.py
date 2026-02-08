"""Tests for profile models."""

from sandbox_cli.models import Dashboard, Meta, Mode, Mounts, Resources, SandboxProfile


def test_default_profile():
    p = SandboxProfile()
    assert p.meta.bootstrap_dir == ""
    assert p.mounts.openclaw == ""
    assert p.mode.yolo is False
    assert p.resources.cpus == 4
    assert p.resources.memory == "8GiB"
    assert p.resources.disk == "50GiB"
    assert p.dashboard.enabled is False
    assert p.extra_vars == {}


def test_path_expansion():
    m = Mounts(openclaw="~/foo")
    assert "~" not in m.openclaw
    assert m.openclaw.endswith("/foo")


def test_meta_path_expansion():
    m = Meta(bootstrap_dir="~/sandbox")
    assert "~" not in m.bootstrap_dir
    assert m.bootstrap_dir.endswith("/sandbox")


def test_empty_paths_stay_empty():
    m = Mounts()
    assert m.openclaw == ""
    assert m.config == ""


def test_mode_defaults():
    mode = Mode()
    assert mode.yolo is False
    assert mode.yolo_unsafe is False
    assert mode.no_docker is False
    assert mode.memgraph is False
    assert mode.memgraph_ports == []


def test_full_profile_from_dict():
    data = {
        "meta": {"bootstrap_dir": "/tmp/sandbox"},
        "mounts": {
            "openclaw": "/tmp/openclaw",
            "config": "/tmp/config",
            "secrets": "/tmp/secrets.env",
        },
        "mode": {"yolo": True, "memgraph": True, "memgraph_ports": [7687, 7444]},
        "resources": {"cpus": 8, "memory": "16GiB", "disk": "100GiB"},
        "extra_vars": {"telegram_user_id": "123456"},
    }
    p = SandboxProfile.model_validate(data)
    assert p.meta.bootstrap_dir == "/tmp/sandbox"
    assert p.mounts.openclaw == "/tmp/openclaw"
    assert p.mode.yolo is True
    assert p.mode.memgraph_ports == [7687, 7444]
    assert p.resources.cpus == 8
    assert p.extra_vars["telegram_user_id"] == "123456"


# ── Dashboard model ──────────────────────────────────────────────────────


def test_dashboard_defaults():
    d = Dashboard()
    assert d.enabled is False
    assert d.sync_interval == 1
    assert d.vault_path == ""
    assert d.lookback_days == 14
    assert d.repos == []
    assert d.script_path == ""


def test_dashboard_path_expansion():
    d = Dashboard(vault_path="~/Vaults/test", script_path="~/scripts/sync.py")
    assert "~" not in d.vault_path
    assert d.vault_path.endswith("/Vaults/test")
    assert "~" not in d.script_path
    assert d.script_path.endswith("/scripts/sync.py")


def test_dashboard_empty_paths_stay_empty():
    d = Dashboard()
    assert d.vault_path == ""
    assert d.script_path == ""


def test_profile_with_dashboard():
    data = {
        "mounts": {"vault": "/tmp/vault"},
        "dashboard": {
            "enabled": True,
            "sync_interval": 3,
            "lookback_days": 30,
            "repos": ["Peleke/openclaw", "Peleke/cadence"],
        },
    }
    p = SandboxProfile.model_validate(data)
    assert p.dashboard.enabled is True
    assert p.dashboard.sync_interval == 3
    assert p.dashboard.lookback_days == 30
    assert p.dashboard.repos == ["Peleke/openclaw", "Peleke/cadence"]
    assert p.dashboard.vault_path == ""  # falls back to mounts.vault at runtime
