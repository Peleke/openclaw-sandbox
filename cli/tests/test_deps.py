"""Tests for dependency checks (brew, ansible-galaxy)."""

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from sandbox_cli.deps import (
    DependencyError,
    check_brew,
    install_ansible_collections,
    install_brew_deps,
)


class TestCheckBrew:
    def test_passes_when_brew_on_path(self):
        with patch("sandbox_cli.deps.shutil.which", return_value="/opt/homebrew/bin/brew"):
            check_brew()  # should not raise

    def test_raises_when_brew_missing(self):
        with patch("sandbox_cli.deps.shutil.which", return_value=None):
            with pytest.raises(DependencyError, match="Homebrew is not installed"):
                check_brew()

    def test_error_message_includes_install_url(self):
        with patch("sandbox_cli.deps.shutil.which", return_value=None):
            with pytest.raises(DependencyError, match="brew.sh"):
                check_brew()


class TestInstallBrewDeps:
    def test_runs_brew_bundle_with_correct_brewfile(self, tmp_path):
        brewdir = tmp_path / "brew"
        brewdir.mkdir()
        (brewdir / "Brewfile").write_text('brew "lima"\n')
        with patch("sandbox_cli.deps.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            rc = install_brew_deps(tmp_path)
        assert rc == 0
        args = mock_run.call_args[0][0]
        assert args[0] == "brew"
        assert args[1] == "bundle"
        assert f"--file={brewdir / 'Brewfile'}" in args[2]

    def test_returns_nonzero_on_failure(self, tmp_path):
        brewdir = tmp_path / "brew"
        brewdir.mkdir()
        (brewdir / "Brewfile").write_text("")
        with patch("sandbox_cli.deps.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=1)
            rc = install_brew_deps(tmp_path)
        assert rc == 1

    def test_returns_1_when_brewfile_missing(self, tmp_path):
        rc = install_brew_deps(tmp_path)
        assert rc == 1

    def test_does_not_call_subprocess_when_brewfile_missing(self, tmp_path):
        with patch("sandbox_cli.deps.subprocess.run") as mock_run:
            install_brew_deps(tmp_path)
        mock_run.assert_not_called()


class TestInstallAnsibleCollections:
    def test_runs_galaxy_install(self, tmp_path):
        ansible_dir = tmp_path / "ansible"
        ansible_dir.mkdir()
        (ansible_dir / "requirements.yml").write_text("collections:\n  - community.general\n")
        with patch("sandbox_cli.deps.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            rc = install_ansible_collections(tmp_path)
        assert rc == 0
        args = mock_run.call_args[0][0]
        assert args[0] == "ansible-galaxy"
        assert "collection" in args
        assert "install" in args
        assert "--force-with-deps" in args

    def test_returns_0_when_no_requirements_file(self, tmp_path):
        rc = install_ansible_collections(tmp_path)
        assert rc == 0

    def test_returns_nonzero_on_galaxy_failure(self, tmp_path):
        ansible_dir = tmp_path / "ansible"
        ansible_dir.mkdir()
        (ansible_dir / "requirements.yml").write_text("")
        with patch("sandbox_cli.deps.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=1)
            rc = install_ansible_collections(tmp_path)
        assert rc == 1

    def test_suppresses_stdout_and_stderr(self, tmp_path):
        ansible_dir = tmp_path / "ansible"
        ansible_dir.mkdir()
        (ansible_dir / "requirements.yml").write_text("")
        with patch("sandbox_cli.deps.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            install_ansible_collections(tmp_path)
        kwargs = mock_run.call_args[1]
        assert kwargs["stdout"] is not None  # subprocess.DEVNULL
        assert kwargs["stderr"] is not None
