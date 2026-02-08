"""Profile load / save / init wizard."""

from __future__ import annotations

import sys
from pathlib import Path

import tomli_w

from .models import SandboxProfile

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib  # type: ignore[no-redef]

PROFILE_DIR = Path.home() / ".openclaw"
PROFILE_PATH = PROFILE_DIR / "sandbox-profile.toml"


def load_profile() -> SandboxProfile:
    """Load profile from disk, or return defaults."""
    if not PROFILE_PATH.exists():
        return SandboxProfile()
    data = tomllib.loads(PROFILE_PATH.read_text())
    return SandboxProfile.model_validate(data)


def save_profile(profile: SandboxProfile) -> Path:
    """Write profile to disk and return the path."""
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    data = profile.model_dump(mode="json")
    PROFILE_PATH.write_text(tomli_w.dumps(data))
    return PROFILE_PATH


def _prompt(label: str, default: str = "") -> str:
    """Prompt for a value with an optional default."""
    suffix = f" [{default}]" if default else ""
    raw = input(f"  {label}{suffix}: ").strip()
    return raw or default


def _tilde(p: str) -> str:
    """Collapse $HOME back to ~ for storage."""
    home = str(Path.home())
    if p.startswith(home):
        return "~" + p[len(home):]
    return p


def init_wizard() -> SandboxProfile:
    """Interactive wizard that builds a profile from user input."""
    print("OpenClaw Sandbox — profile setup\n")

    # --- meta ---
    bootstrap_dir = _prompt(
        "Bootstrap repo directory",
        default=_tilde(str(Path.cwd())),
    )

    # --- mounts ---
    print("\nMount paths (leave blank to skip):")
    openclaw = _prompt("openclaw repo", default="~/Documents/Projects/openclaw")
    config = _prompt("config dir (~/.openclaw)", default="~/.openclaw")
    agent_data = _prompt("agent data dir", default="~/.openclaw/agents")
    buildlog_data = _prompt("buildlog data dir", default="~/.buildlog")
    secrets = _prompt("secrets .env file", default="~/.openclaw-secrets.env")
    vault = _prompt("vault (Obsidian) path")

    # --- mode ---
    print("\nMode flags:")
    yolo = input("  Enable yolo overlay mode? [y/N]: ").strip().lower() == "y"
    no_docker = input("  Skip Docker install? [y/N]: ").strip().lower() == "y"
    memgraph = input("  Enable Memgraph? [y/N]: ").strip().lower() == "y"

    # --- resources ---
    print("\nVM resources:")
    cpus = int(_prompt("CPUs", default="4"))
    memory = _prompt("Memory", default="8GiB")
    disk = _prompt("Disk", default="50GiB")

    profile = SandboxProfile.model_validate(
        {
            "meta": {"bootstrap_dir": bootstrap_dir},
            "mounts": {
                "openclaw": openclaw,
                "config": config,
                "agent_data": agent_data,
                "buildlog_data": buildlog_data,
                "secrets": secrets,
                "vault": vault,
            },
            "mode": {
                "yolo": yolo,
                "yolo_unsafe": False,
                "no_docker": no_docker,
                "memgraph": memgraph,
                "memgraph_ports": [],
            },
            "resources": {
                "cpus": cpus,
                "memory": memory,
                "disk": disk,
            },
            "extra_vars": {},
        }
    )

    path = save_profile(profile)
    print(f"\nProfile saved to {path}")
    return profile
