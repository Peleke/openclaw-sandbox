"""Tests for pre-flight validation."""

from sandbox_cli.models import SandboxProfile
from sandbox_cli.validation import validate_profile


def test_empty_profile_warns():
    p = SandboxProfile()
    r = validate_profile(p)
    assert r.ok  # no errors, only warnings
    assert any("No secrets file" in w for w in r.warnings)
    assert any("No openclaw mount" in w for w in r.warnings)


def test_missing_path_is_error(tmp_path):
    p = SandboxProfile.model_validate(
        {"mounts": {"openclaw": str(tmp_path / "nonexistent")}}
    )
    r = validate_profile(p)
    assert not r.ok
    assert any("does not exist" in e for e in r.errors)


def test_existing_paths_pass(tmp_path):
    oc = tmp_path / "openclaw"
    oc.mkdir()
    secrets = tmp_path / "secrets.env"
    secrets.write_text("ANTHROPIC_API_KEY=sk-test\nGH_TOKEN=ghp_test\n")
    p = SandboxProfile.model_validate(
        {"mounts": {"openclaw": str(oc), "secrets": str(secrets)}}
    )
    r = validate_profile(p)
    assert r.ok


def test_missing_required_secrets(tmp_path):
    secrets = tmp_path / "secrets.env"
    secrets.write_text("OPENAI_API_KEY=sk-test\n")
    p = SandboxProfile.model_validate({"mounts": {"secrets": str(secrets)}})
    r = validate_profile(p)
    assert not r.ok
    assert any("ANTHROPIC_API_KEY" in e for e in r.errors)
    assert any("GH_TOKEN" in e for e in r.errors)


def test_missing_optional_secrets_warns(tmp_path):
    secrets = tmp_path / "secrets.env"
    secrets.write_text("ANTHROPIC_API_KEY=sk-test\nGH_TOKEN=ghp_test\n")
    p = SandboxProfile.model_validate({"mounts": {"secrets": str(secrets)}})
    r = validate_profile(p)
    assert r.ok
    assert any("optional keys" in w for w in r.warnings)


def test_yolo_mutual_exclusion():
    p = SandboxProfile.model_validate(
        {"mode": {"yolo": True, "yolo_unsafe": True}}
    )
    r = validate_profile(p)
    assert not r.ok
    assert any("mutually exclusive" in e for e in r.errors)


def test_yolo_alone_is_fine():
    p = SandboxProfile.model_validate({"mode": {"yolo": True}})
    r = validate_profile(p)
    # May have warnings (no openclaw, no secrets) but no errors from coherence
    assert not any("mutually exclusive" in e for e in r.errors)


def test_export_prefix_in_secrets(tmp_path):
    """Secrets parser handles 'export KEY=value' .env syntax."""
    secrets = tmp_path / "secrets.env"
    secrets.write_text("export ANTHROPIC_API_KEY=sk-test\nexport GH_TOKEN=ghp_test\n")
    p = SandboxProfile.model_validate({"mounts": {"secrets": str(secrets)}})
    r = validate_profile(p)
    assert r.ok
    assert not any("ANTHROPIC_API_KEY" in e for e in r.errors)


def test_mixed_env_formats(tmp_path):
    """Secrets parser handles mix of plain, export, comments, and blank lines."""
    secrets = tmp_path / "secrets.env"
    secrets.write_text(
        "# API keys\n"
        "ANTHROPIC_API_KEY=sk-test\n"
        "\n"
        "export GH_TOKEN=ghp_test\n"
        "  OPENAI_API_KEY = sk-openai  \n"
    )
    p = SandboxProfile.model_validate({"mounts": {"secrets": str(secrets)}})
    r = validate_profile(p)
    assert r.ok
