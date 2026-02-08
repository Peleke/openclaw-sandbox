"""Tests for Lima YAML configuration generation."""

from pathlib import Path

import pytest
import yaml  # pyyaml dev dep

from sandbox_cli.lima_config import (
    LimaConfigContext,
    MountSpec,
    PortForwardSpec,
    build_context,
    render_config,
    secrets_filename,
    write_config,
)
from sandbox_cli.models import SandboxProfile


# ── fixtures ─────────────────────────────────────────────────────────────


@pytest.fixture
def bootstrap_dir(tmp_path):
    """Fake bootstrap directory."""
    (tmp_path / "bootstrap.sh").touch()
    (tmp_path / "lima").mkdir()
    return tmp_path


@pytest.fixture
def basic_profile(tmp_path):
    """Profile with the minimum required mounts."""
    oc_dir = tmp_path / "openclaw-repo"
    oc_dir.mkdir()
    return SandboxProfile.model_validate(
        {"mounts": {"openclaw": str(oc_dir)}}
    )


@pytest.fixture
def full_profile(tmp_path):
    """Profile with all optional mounts enabled."""
    oc = tmp_path / "openclaw"
    oc.mkdir()
    vault = tmp_path / "vault"
    vault.mkdir()
    config = tmp_path / "config"
    config.mkdir()
    agent = tmp_path / "agents"
    agent.mkdir()
    buildlog = tmp_path / "buildlog"
    buildlog.mkdir()
    secrets = tmp_path / "secrets.env"
    secrets.write_text("ANTHROPIC_API_KEY=sk-test\n")
    return SandboxProfile.model_validate(
        {
            "mounts": {
                "openclaw": str(oc),
                "vault": str(vault),
                "config": str(config),
                "agent_data": str(agent),
                "buildlog_data": str(buildlog),
                "secrets": str(secrets),
            },
            "mode": {"memgraph": True},
            "resources": {"cpus": 8, "memory": "16GiB", "disk": "100GiB"},
        }
    )


# ── build_context ────────────────────────────────────────────────────────


class TestBuildContext:
    def test_basic_profile_has_openclaw_and_provision_mounts(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        mount_points = [m.mount_point for m in ctx.mounts]
        assert "/mnt/openclaw" in mount_points
        assert "/mnt/provision" in mount_points

    def test_provision_is_always_read_only(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        provision = next(m for m in ctx.mounts if m.mount_point == "/mnt/provision")
        assert provision.writable is False

    def test_openclaw_read_only_by_default(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        oc = next(m for m in ctx.mounts if m.mount_point == "/mnt/openclaw")
        assert oc.writable is False

    def test_openclaw_writable_when_yolo_unsafe(self, tmp_path, bootstrap_dir):
        oc = tmp_path / "oc"
        oc.mkdir()
        profile = SandboxProfile.model_validate(
            {"mounts": {"openclaw": str(oc)}, "mode": {"yolo_unsafe": True}}
        )
        ctx = build_context(profile, bootstrap_dir)
        oc_mount = next(m for m in ctx.mounts if m.mount_point == "/mnt/openclaw")
        assert oc_mount.writable is True

    def test_vault_mount_included_when_set(self, full_profile, bootstrap_dir):
        ctx = build_context(full_profile, bootstrap_dir)
        mount_points = [m.mount_point for m in ctx.mounts]
        assert "/mnt/obsidian" in mount_points

    def test_vault_mount_excluded_when_unset(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        mount_points = [m.mount_point for m in ctx.mounts]
        assert "/mnt/obsidian" not in mount_points

    def test_config_mount_included(self, full_profile, bootstrap_dir):
        ctx = build_context(full_profile, bootstrap_dir)
        mount_points = [m.mount_point for m in ctx.mounts]
        assert "/mnt/openclaw-config" in mount_points

    def test_agent_data_always_writable(self, full_profile, bootstrap_dir):
        ctx = build_context(full_profile, bootstrap_dir)
        agent = next(m for m in ctx.mounts if m.mount_point == "/mnt/openclaw-agents")
        assert agent.writable is True

    def test_buildlog_data_always_writable(self, full_profile, bootstrap_dir):
        ctx = build_context(full_profile, bootstrap_dir)
        bl = next(m for m in ctx.mounts if m.mount_point == "/mnt/buildlog-data")
        assert bl.writable is True

    def test_secrets_mounts_parent_directory(self, full_profile, bootstrap_dir):
        ctx = build_context(full_profile, bootstrap_dir)
        sec = next(m for m in ctx.mounts if m.mount_point == "/mnt/secrets")
        # Should be the parent dir, not the file itself
        assert Path(sec.location).is_dir()

    def test_secrets_always_read_only(self, full_profile, bootstrap_dir):
        ctx = build_context(full_profile, bootstrap_dir)
        sec = next(m for m in ctx.mounts if m.mount_point == "/mnt/secrets")
        assert sec.writable is False

    def test_agent_data_dir_created_if_missing(self, tmp_path, bootstrap_dir):
        oc = tmp_path / "oc"
        oc.mkdir()
        agent_dir = tmp_path / "nonexistent-agents"
        profile = SandboxProfile.model_validate(
            {"mounts": {"openclaw": str(oc), "agent_data": str(agent_dir)}}
        )
        build_context(profile, bootstrap_dir)
        assert agent_dir.is_dir()

    def test_buildlog_data_dir_created_if_missing(self, tmp_path, bootstrap_dir):
        oc = tmp_path / "oc"
        oc.mkdir()
        bl_dir = tmp_path / "nonexistent-buildlog"
        profile = SandboxProfile.model_validate(
            {"mounts": {"openclaw": str(oc), "buildlog_data": str(bl_dir)}}
        )
        build_context(profile, bootstrap_dir)
        assert bl_dir.is_dir()

    def test_resources_propagated(self, full_profile, bootstrap_dir):
        ctx = build_context(full_profile, bootstrap_dir)
        assert ctx.vm_cpus == 8
        assert ctx.vm_memory == "16GiB"
        assert ctx.vm_disk == "100GiB"

    def test_default_port_forward_always_present(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        ports = [pf.guest_port for pf in ctx.port_forwards]
        assert 18789 in ports

    def test_memgraph_adds_three_ports(self, full_profile, bootstrap_dir):
        ctx = build_context(full_profile, bootstrap_dir)
        ports = [pf.guest_port for pf in ctx.port_forwards]
        assert 7687 in ports
        assert 3000 in ports
        assert 7444 in ports

    def test_memgraph_ports_individual(self, tmp_path, bootstrap_dir):
        oc = tmp_path / "oc"
        oc.mkdir()
        profile = SandboxProfile.model_validate(
            {
                "mounts": {"openclaw": str(oc)},
                "mode": {"memgraph_ports": [7687, 7444]},
            }
        )
        ctx = build_context(profile, bootstrap_dir)
        ports = [pf.guest_port for pf in ctx.port_forwards]
        assert 7687 in ports
        assert 7444 in ports
        assert 3000 not in ports  # not full memgraph, just individual ports

    def test_memgraph_flag_takes_priority_over_ports(self, tmp_path, bootstrap_dir):
        oc = tmp_path / "oc"
        oc.mkdir()
        profile = SandboxProfile.model_validate(
            {
                "mounts": {"openclaw": str(oc)},
                "mode": {"memgraph": True, "memgraph_ports": [9999]},
            }
        )
        ctx = build_context(profile, bootstrap_dir)
        ports = [pf.guest_port for pf in ctx.port_forwards]
        # memgraph=True wins: gives all three standard ports
        assert 7687 in ports
        assert 3000 in ports
        assert 7444 in ports
        # individual port should NOT be present (elif branch)
        assert 9999 not in ports

    def test_full_mount_order(self, full_profile, bootstrap_dir):
        """Mounts follow the same order as bootstrap.sh."""
        ctx = build_context(full_profile, bootstrap_dir)
        mount_points = [m.mount_point for m in ctx.mounts]
        assert mount_points == [
            "/mnt/openclaw",
            "/mnt/provision",
            "/mnt/obsidian",
            "/mnt/openclaw-config",
            "/mnt/openclaw-agents",
            "/mnt/buildlog-data",
            "/mnt/secrets",
        ]

    def test_yolo_unsafe_makes_vault_and_config_writable(self, tmp_path, bootstrap_dir):
        oc = tmp_path / "oc"
        oc.mkdir()
        vault = tmp_path / "vault"
        vault.mkdir()
        config = tmp_path / "config"
        config.mkdir()
        profile = SandboxProfile.model_validate(
            {
                "mounts": {
                    "openclaw": str(oc),
                    "vault": str(vault),
                    "config": str(config),
                },
                "mode": {"yolo_unsafe": True},
            }
        )
        ctx = build_context(profile, bootstrap_dir)
        vault_mount = next(m for m in ctx.mounts if m.mount_point == "/mnt/obsidian")
        config_mount = next(m for m in ctx.mounts if m.mount_point == "/mnt/openclaw-config")
        assert vault_mount.writable is True
        assert config_mount.writable is True


# ── render_config ────────────────────────────────────────────────────────


class TestRenderConfig:
    def test_renders_valid_yaml(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        text = render_config(ctx)
        parsed = yaml.safe_load(text)
        assert parsed["vmType"] == "vz"

    def test_cpus_memory_disk_in_yaml(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        text = render_config(ctx)
        parsed = yaml.safe_load(text)
        assert parsed["cpus"] == 4
        assert parsed["memory"] == "8GiB"
        assert parsed["disk"] == "50GiB"

    def test_mounts_in_yaml(self, full_profile, bootstrap_dir):
        ctx = build_context(full_profile, bootstrap_dir)
        text = render_config(ctx)
        parsed = yaml.safe_load(text)
        mount_points = [m["mountPoint"] for m in parsed["mounts"]]
        assert "/mnt/openclaw" in mount_points
        assert "/mnt/provision" in mount_points
        assert "/mnt/obsidian" in mount_points

    def test_port_forwards_in_yaml(self, full_profile, bootstrap_dir):
        ctx = build_context(full_profile, bootstrap_dir)
        text = render_config(ctx)
        parsed = yaml.safe_load(text)
        ports = [pf["guestPort"] for pf in parsed["portForwards"]]
        assert 18789 in ports
        assert 7687 in ports

    def test_writable_rendered_as_yaml_bool(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        text = render_config(ctx)
        parsed = yaml.safe_load(text)
        oc = next(m for m in parsed["mounts"] if m["mountPoint"] == "/mnt/openclaw")
        assert oc["writable"] is False  # YAML bool, not string

    def test_provision_scripts_present(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        text = render_config(ctx)
        parsed = yaml.safe_load(text)
        assert len(parsed["provision"]) == 2
        assert parsed["provision"][0]["mode"] == "system"
        assert parsed["provision"][1]["mode"] == "user"

    def test_env_openclaw_sandbox_set(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        text = render_config(ctx)
        parsed = yaml.safe_load(text)
        assert parsed["env"]["OPENCLAW_SANDBOX"] == "true"

    def test_rosetta_enabled(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        text = render_config(ctx)
        parsed = yaml.safe_load(text)
        assert parsed["vmOpts"]["vz"]["rosetta"]["enabled"] is True

    def test_containerd_disabled(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        text = render_config(ctx)
        parsed = yaml.safe_load(text)
        assert parsed["containerd"]["system"] is False
        assert parsed["containerd"]["user"] is False

    def test_ssh_config(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        text = render_config(ctx)
        parsed = yaml.safe_load(text)
        assert parsed["ssh"]["localPort"] == 0
        assert parsed["ssh"]["loadDotSSHPubKeys"] is True

    def test_images_dual_arch(self, basic_profile, bootstrap_dir):
        ctx = build_context(basic_profile, bootstrap_dir)
        text = render_config(ctx)
        parsed = yaml.safe_load(text)
        archs = {img["arch"] for img in parsed["images"]}
        assert archs == {"x86_64", "aarch64"}


# ── write_config ─────────────────────────────────────────────────────────


class TestWriteConfig:
    def test_writes_file_to_lima_subdir(self, basic_profile, bootstrap_dir):
        path = write_config(basic_profile, bootstrap_dir)
        assert path.exists()
        assert path.name == "openclaw-sandbox.generated.yaml"
        assert path.parent.name == "lima"

    def test_written_file_is_valid_yaml(self, basic_profile, bootstrap_dir):
        path = write_config(basic_profile, bootstrap_dir)
        parsed = yaml.safe_load(path.read_text())
        assert parsed["vmType"] == "vz"

    def test_creates_lima_dir_if_missing(self, tmp_path):
        oc = tmp_path / "oc"
        oc.mkdir()
        bdir = tmp_path / "sandbox"
        bdir.mkdir()
        (bdir / "bootstrap.sh").touch()
        # No lima/ subdir exists
        profile = SandboxProfile.model_validate(
            {"mounts": {"openclaw": str(oc)}}
        )
        path = write_config(profile, bdir)
        assert path.exists()


# ── secrets_filename ─────────────────────────────────────────────────────


class TestSecretsFilename:
    def test_returns_basename(self, tmp_path):
        sf = tmp_path / "my-secrets.env"
        sf.touch()
        profile = SandboxProfile.model_validate(
            {"mounts": {"secrets": str(sf)}}
        )
        assert secrets_filename(profile) == "my-secrets.env"

    def test_returns_empty_when_no_secrets(self):
        profile = SandboxProfile()
        assert secrets_filename(profile) == ""
