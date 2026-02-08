"""Tests for profile models."""

from sandbox_cli.models import Meta, Mode, Mounts, Resources, SandboxProfile


def test_default_profile():
    p = SandboxProfile()
    assert p.meta.bootstrap_dir == ""
    assert p.mounts.openclaw == ""
    assert p.mode.yolo is False
    assert p.resources.cpus == 4
    assert p.resources.memory == "8GiB"
    assert p.resources.disk == "50GiB"
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
