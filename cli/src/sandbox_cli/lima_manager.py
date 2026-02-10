"""VM lifecycle management via ``limactl`` subprocess calls."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

VM_NAME = "openclaw-sandbox"


@dataclass(frozen=True)
class SSHDetails:
    """Parsed SSH connection info from ``limactl show-ssh``."""

    host: str
    port: int
    user: str
    key_path: str


class LimaError(RuntimeError):
    """Raised when a limactl command fails unexpectedly."""


class LimaManager:
    """Thin wrapper around ``limactl`` for VM lifecycle operations."""

    def __init__(self, vm_name: str = VM_NAME) -> None:
        self.vm_name = vm_name

    # ── queries ──────────────────────────────────────────────────────────

    def vm_exists(self) -> bool:
        """Return *True* if a VM with this name exists in Lima."""
        proc = subprocess.run(
            ["limactl", "list", "--json"],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            return False
        # Lima outputs one JSON object per line (not an array)
        for line in proc.stdout.strip().splitlines():
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("name") == self.vm_name:
                return True
        return False

    def vm_status(self) -> str:
        """Return the VM status string (``Running``, ``Stopped``, …) or ``unknown``."""
        proc = subprocess.run(
            ["limactl", "list", "--json"],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            return "unknown"
        for line in proc.stdout.strip().splitlines():
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("name") == self.vm_name:
                return entry.get("status", "unknown")
        return "unknown"

    def vm_info(self) -> dict | None:
        """Return the full JSON dict for this VM, or *None*."""
        proc = subprocess.run(
            ["limactl", "list", "--json"],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            return None
        for line in proc.stdout.strip().splitlines():
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("name") == self.vm_name:
                return entry
        return None

    # ── lifecycle ────────────────────────────────────────────────────────

    def create(self, config_path: Path) -> None:
        """Create the VM from a Lima YAML config."""
        proc = subprocess.run(
            ["limactl", "create", f"--name={self.vm_name}", str(config_path)],
        )
        if proc.returncode != 0:
            raise LimaError(f"limactl create failed (exit {proc.returncode})")

    def start(self) -> None:
        """Start an existing (stopped) VM."""
        proc = subprocess.run(["limactl", "start", self.vm_name])
        if proc.returncode != 0:
            raise LimaError(f"limactl start failed (exit {proc.returncode})")

    def stop(self, *, force: bool = False) -> None:
        """Stop the VM. With *force*, uses ``--force``."""
        cmd = ["limactl", "stop"]
        if force:
            cmd.append("--force")
        cmd.append(self.vm_name)
        subprocess.run(cmd)

    def delete(self, *, force: bool = True) -> None:
        """Stop (force) then delete the VM."""
        subprocess.run(
            ["limactl", "stop", "--force", self.vm_name],
            capture_output=True,
        )
        cmd = ["limactl", "delete"]
        if force:
            cmd.append("--force")
        cmd.append(self.vm_name)
        subprocess.run(cmd)

    def ensure_running(self, config_path: Path) -> bool:
        """Create if missing, start if stopped. Return *True* if VM was created."""
        created = False
        if not self.vm_exists():
            self.create(config_path)
            created = True

        status = self.vm_status()
        if status != "Running":
            self.start()

        return created

    # ── SSH ──────────────────────────────────────────────────────────────

    def get_ssh_details(self) -> SSHDetails:
        """Parse ``limactl show-ssh --format=config`` and return *SSHDetails*."""
        proc = subprocess.run(
            ["limactl", "show-ssh", "--format=config", self.vm_name],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            raise LimaError("limactl show-ssh failed")

        ssh_config = proc.stdout
        host = _parse_ssh_field(ssh_config, "Hostname") or "127.0.0.1"
        port_str = _parse_ssh_field(ssh_config, "Port") or "22"
        user = _parse_ssh_field(ssh_config, "User") or os.getlogin()
        key = _parse_ssh_field(ssh_config, "IdentityFile")
        if key:
            key = key.strip('"')

        if not key:
            raise LimaError("Could not determine SSH key from Lima")

        return SSHDetails(host=host, port=int(port_str), user=user, key_path=key)

    # ── shell ────────────────────────────────────────────────────────────

    def shell(self) -> None:
        """Replace the current process with an interactive VM shell (TTY)."""
        os.execvp("limactl", ["limactl", "shell", self.vm_name])

    def shell_exec(self, command: str) -> None:
        """Replace the current process, running *command* inside the VM."""
        os.execvp(
            "limactl",
            [
                "limactl",
                "shell",
                self.vm_name,
                "--",
                "bash",
                "-c",
                command,
            ],
        )

    def shell_run(self, command: str) -> subprocess.CompletedProcess:
        """Run *command* inside the VM and return the result (no process replacement)."""
        return subprocess.run(
            ["limactl", "shell", self.vm_name, "--", "bash", "-c", command],
            capture_output=True,
            text=True,
        )

    # ── mount verification ───────────────────────────────────────────────

    def verify_mount(self, mount_point: str) -> bool:
        """Return *True* if *mount_point* is an accessible directory inside the VM."""
        proc = subprocess.run(
            ["limactl", "shell", self.vm_name, "--", "test", "-d", mount_point],
            capture_output=True,
        )
        return proc.returncode == 0


# ── helpers ──────────────────────────────────────────────────────────────


def _parse_ssh_field(ssh_config: str, field_name: str) -> str | None:
    """Extract the first value for *field_name* from SSH config text."""
    pattern = rf"^\s*{re.escape(field_name)}\s+(.+)$"
    match = re.search(pattern, ssh_config, re.MULTILINE)
    return match.group(1).strip() if match else None
