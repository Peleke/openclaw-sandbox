"""Dependency checks: Homebrew, brew bundle, ansible-galaxy."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


class DependencyError(RuntimeError):
    """Raised when a required host tool is missing."""


def check_brew() -> None:
    """Verify Homebrew is installed, raise *DependencyError* if not."""
    if shutil.which("brew") is None:
        raise DependencyError(
            "Homebrew is not installed.\n"
            "Install it from https://brew.sh or run:\n"
            '  /bin/bash -c "$(curl -fsSL '
            'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        )


def install_brew_deps(bootstrap_dir: Path) -> int:
    """Run ``brew bundle`` against the repo Brewfile.

    Returns the subprocess exit code.
    """
    brewfile = bootstrap_dir / "brew" / "Brewfile"
    if not brewfile.is_file():
        print(f"Brewfile not found at {brewfile}", file=sys.stderr)
        return 1
    result = subprocess.run(
        ["brew", "bundle", f"--file={brewfile}"],
    )
    return result.returncode


def install_ansible_collections(bootstrap_dir: Path) -> int:
    """Run ``ansible-galaxy collection install`` from requirements.yml.

    Returns 0 on success or if the requirements file is absent (nothing to do).
    """
    requirements = bootstrap_dir / "ansible" / "requirements.yml"
    if not requirements.is_file():
        return 0
    result = subprocess.run(
        [
            "ansible-galaxy",
            "collection",
            "install",
            "-r",
            str(requirements),
            "--force-with-deps",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode
