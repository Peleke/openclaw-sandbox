"""Tests for argv builder and script discovery."""

from pathlib import Path

import pytest

from sandbox_cli.bootstrap import build_argv, find_bootstrap_dir
from sandbox_cli.models import SandboxProfile


def test_empty_profile_produces_no_args():
    p = SandboxProfile()
    assert build_argv(p) == []


def test_mount_flags():
    p = SandboxProfile.model_validate(
        {
            "mounts": {
                "openclaw": "/tmp/openclaw",
                "config": "/tmp/config",
                "secrets": "/tmp/secrets.env",
            }
        }
    )
    argv = build_argv(p)
    assert "--openclaw" in argv
    assert "/tmp/openclaw" in argv
    assert "--config" in argv
    assert "/tmp/config" in argv
    assert "--secrets" in argv
    assert "/tmp/secrets.env" in argv
    # Not set, should not appear
    assert "--vault" not in argv
    assert "--agent-data" not in argv
    assert "--buildlog-data" not in argv


def test_mode_flags():
    p = SandboxProfile.model_validate(
        {
            "mode": {
                "yolo": True,
                "no_docker": True,
                "memgraph": True,
                "memgraph_ports": [7687, 7444],
            }
        }
    )
    argv = build_argv(p)
    assert "--yolo" in argv
    assert "--no-docker" in argv
    assert "--memgraph" in argv
    assert argv.count("--memgraph-port") == 2
    assert "7687" in argv
    assert "7444" in argv
    assert "--yolo-unsafe" not in argv


def test_extra_vars():
    p = SandboxProfile.model_validate(
        {"extra_vars": {"telegram_user_id": "123", "foo": "bar"}}
    )
    argv = build_argv(p)
    assert "-e" in argv
    assert "telegram_user_id=123" in argv
    assert "foo=bar" in argv


def test_full_argv_ordering():
    """Mount flags come first, then mode, then extra_vars."""
    p = SandboxProfile.model_validate(
        {
            "mounts": {"openclaw": "/oc", "vault": "/v"},
            "mode": {"yolo": True},
            "extra_vars": {"k": "v"},
        }
    )
    argv = build_argv(p)
    oc_idx = argv.index("--openclaw")
    yolo_idx = argv.index("--yolo")
    e_idx = argv.index("-e")
    assert oc_idx < yolo_idx < e_idx


def test_find_bootstrap_dir_cwd(tmp_path, monkeypatch):
    (tmp_path / "bootstrap.sh").touch()
    monkeypatch.chdir(tmp_path)
    p = SandboxProfile()
    assert find_bootstrap_dir(p) == tmp_path


def test_find_bootstrap_dir_env(tmp_path, monkeypatch):
    (tmp_path / "bootstrap.sh").touch()
    monkeypatch.setenv("OPENCLAW_SANDBOX_DIR", str(tmp_path))
    monkeypatch.chdir("/tmp")
    p = SandboxProfile()
    assert find_bootstrap_dir(p) == tmp_path


def test_find_bootstrap_dir_profile(tmp_path, monkeypatch):
    (tmp_path / "bootstrap.sh").touch()
    monkeypatch.chdir("/tmp")
    monkeypatch.delenv("OPENCLAW_SANDBOX_DIR", raising=False)
    p = SandboxProfile.model_validate(
        {"meta": {"bootstrap_dir": str(tmp_path)}}
    )
    assert find_bootstrap_dir(p) == tmp_path


def test_find_bootstrap_dir_not_found(monkeypatch):
    monkeypatch.chdir("/tmp")
    monkeypatch.delenv("OPENCLAW_SANDBOX_DIR", raising=False)
    p = SandboxProfile()
    with pytest.raises(FileNotFoundError):
        find_bootstrap_dir(p)
