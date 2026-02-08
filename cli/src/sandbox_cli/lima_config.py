"""Lima YAML configuration generation via Jinja2.

Replaces the 300-line ``generate_lima_config()`` bash function with
structured dataclasses fed into a thin Jinja2 template.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from jinja2 import Environment, PackageLoader

from .models import SandboxProfile

VM_NAME = "openclaw-sandbox"

# ── dataclasses ──────────────────────────────────────────────────────────


@dataclass
class MountSpec:
    """A single Lima host→VM mount."""

    location: str
    mount_point: str
    writable: bool


@dataclass
class PortForwardSpec:
    """A single Lima port-forward rule."""

    guest_port: int
    host_port: int
    proto: str = "tcp"


@dataclass
class LimaConfigContext:
    """Everything the Jinja2 template needs to render."""

    vm_cpus: int
    vm_memory: str
    vm_disk: str
    mounts: list[MountSpec] = field(default_factory=list)
    port_forwards: list[PortForwardSpec] = field(default_factory=list)


# ── builders ─────────────────────────────────────────────────────────────


def _expand(raw: str) -> str:
    """Expand ~ and make absolute."""
    p = Path(raw).expanduser()
    return str(p.resolve())


def build_context(profile: SandboxProfile, bootstrap_dir: Path) -> LimaConfigContext:
    """Translate a *SandboxProfile* into a *LimaConfigContext*.

    All conditional mount / port-forward logic lives here so the template
    is a dumb iterator.
    """
    writable = profile.mode.yolo_unsafe
    mounts: list[MountSpec] = []

    # Required: openclaw repo
    if profile.mounts.openclaw:
        mounts.append(
            MountSpec(
                location=_expand(profile.mounts.openclaw),
                mount_point="/mnt/openclaw",
                writable=writable,
            )
        )

    # Always: provision (= bootstrap dir), read-only
    mounts.append(
        MountSpec(
            location=str(bootstrap_dir.resolve()),
            mount_point="/mnt/provision",
            writable=False,
        )
    )

    # Optional: vault → /mnt/obsidian
    if profile.mounts.vault:
        mounts.append(
            MountSpec(
                location=_expand(profile.mounts.vault),
                mount_point="/mnt/obsidian",
                writable=writable,
            )
        )

    # Optional: config → /mnt/openclaw-config
    if profile.mounts.config:
        mounts.append(
            MountSpec(
                location=_expand(profile.mounts.config),
                mount_point="/mnt/openclaw-config",
                writable=writable,
            )
        )

    # Optional: agent_data → /mnt/openclaw-agents (always writable)
    if profile.mounts.agent_data:
        path = Path(profile.mounts.agent_data).expanduser()
        path.mkdir(parents=True, exist_ok=True)
        mounts.append(
            MountSpec(
                location=str(path.resolve()),
                mount_point="/mnt/openclaw-agents",
                writable=True,
            )
        )

    # Optional: buildlog_data → /mnt/buildlog-data (always writable)
    if profile.mounts.buildlog_data:
        path = Path(profile.mounts.buildlog_data).expanduser()
        path.mkdir(parents=True, exist_ok=True)
        mounts.append(
            MountSpec(
                location=str(path.resolve()),
                mount_point="/mnt/buildlog-data",
                writable=True,
            )
        )

    # Optional: secrets → /mnt/secrets (parent dir, always read-only)
    if profile.mounts.secrets:
        secrets_path = Path(profile.mounts.secrets).expanduser().resolve()
        mounts.append(
            MountSpec(
                location=str(secrets_path.parent),
                mount_point="/mnt/secrets",
                writable=False,
            )
        )

    # ── port forwards ────────────────────────────────────────────────────
    port_forwards: list[PortForwardSpec] = [
        PortForwardSpec(guest_port=18789, host_port=18789),
    ]

    if profile.mode.memgraph:
        port_forwards.extend([
            PortForwardSpec(guest_port=7687, host_port=7687),
            PortForwardSpec(guest_port=3000, host_port=3000),
            PortForwardSpec(guest_port=7444, host_port=7444),
        ])
    elif profile.mode.memgraph_ports:
        for port in profile.mode.memgraph_ports:
            port_forwards.append(PortForwardSpec(guest_port=port, host_port=port))

    return LimaConfigContext(
        vm_cpus=profile.resources.cpus,
        vm_memory=profile.resources.memory,
        vm_disk=profile.resources.disk,
        mounts=mounts,
        port_forwards=port_forwards,
    )


# ── rendering ────────────────────────────────────────────────────────────

_env = Environment(
    loader=PackageLoader("sandbox_cli", "templates"),
    keep_trailing_newline=True,
    trim_blocks=True,
    lstrip_blocks=True,
)


def render_config(context: LimaConfigContext) -> str:
    """Render the Lima YAML from a *LimaConfigContext*."""
    template = _env.get_template("lima-vm.yaml.j2")
    return template.render(ctx=context)


def write_config(profile: SandboxProfile, bootstrap_dir: Path) -> Path:
    """Build context, render YAML, write to ``lima/<VM_NAME>.generated.yaml``.

    Returns the path of the written file.
    """
    context = build_context(profile, bootstrap_dir)
    yaml_text = render_config(context)
    out_dir = bootstrap_dir / "lima"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{VM_NAME}.generated.yaml"
    out_path.write_text(yaml_text)
    return out_path


def secrets_filename(profile: SandboxProfile) -> str:
    """Return the basename of the secrets file, or empty string."""
    if profile.mounts.secrets:
        return Path(profile.mounts.secrets).expanduser().resolve().name
    return ""
