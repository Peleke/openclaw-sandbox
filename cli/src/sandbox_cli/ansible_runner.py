"""Ansible inventory builder and playbook invocation."""

from __future__ import annotations

import getpass
import os
import subprocess
import tempfile
from pathlib import Path

from .lima_config import secrets_filename
from .lima_manager import SSHDetails
from .models import SandboxProfile


def build_inventory(vm_name: str, ssh: SSHDetails) -> str:
    """Return an INI-format Ansible inventory string."""
    return (
        "[sandbox]\n"
        f"{vm_name} "
        f"ansible_host={ssh.host} "
        f"ansible_port={ssh.port} "
        f"ansible_user={ssh.user} "
        f"ansible_ssh_private_key_file={ssh.key_path} "
        "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'\n"
    )


def build_extra_vars(profile: SandboxProfile) -> list[str]:
    """Build the ``-e key=value`` argument list for ``ansible-playbook``.

    Matches the exact set of variables that ``bootstrap.sh`` passes.
    """
    sec_fname = secrets_filename(profile)
    tenant = getpass.getuser()

    # Conditional mount paths — empty string when not configured
    agent_mount = "/mnt/openclaw-agents" if profile.mounts.agent_data else ""
    buildlog_mount = "/mnt/buildlog-data" if profile.mounts.buildlog_data else ""

    pairs: list[tuple[str, str]] = [
        ("tenant_name", tenant),
        ("provision_path", "/mnt/provision"),
        ("openclaw_path", "/mnt/openclaw"),
        ("obsidian_path", "/mnt/obsidian"),
        ("secrets_filename", sec_fname),
        ("overlay_yolo_mode", str(profile.mode.yolo).lower()),
        ("overlay_yolo_unsafe", str(profile.mode.yolo_unsafe).lower()),
        ("docker_enabled", str(not profile.mode.no_docker).lower()),
        ("agent_data_mount", agent_mount),
        ("buildlog_data_mount", buildlog_mount),
        ("memgraph_enabled", str(profile.mode.memgraph).lower()),
    ]

    argv: list[str] = []
    for key, value in pairs:
        argv.extend(["-e", f"{key}={value}"])

    # User-supplied extra vars
    for key, value in profile.extra_vars.items():
        argv.extend(["-e", f"{key}={value}"])

    return argv


def run_playbook(
    profile: SandboxProfile,
    ssh: SSHDetails,
    bootstrap_dir: Path,
    *,
    vm_name: str = "openclaw-sandbox",
) -> int:
    """Write a temp inventory, run ``ansible-playbook``, clean up.

    Returns the ansible-playbook exit code.
    """
    inventory_text = build_inventory(vm_name, ssh)
    playbook = bootstrap_dir / "ansible" / "playbook.yml"

    fd, inv_path = tempfile.mkstemp(prefix="sandbox-inv-", suffix=".ini")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(inventory_text)

        cmd = [
            "ansible-playbook",
            "-i",
            inv_path,
            str(playbook),
        ] + build_extra_vars(profile)

        env = {**os.environ, "ANSIBLE_HOST_KEY_CHECKING": "False"}
        result = subprocess.run(cmd, env=env)
        return result.returncode
    finally:
        Path(inv_path).unlink(missing_ok=True)
