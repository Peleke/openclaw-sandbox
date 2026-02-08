"""Pre-flight validation: path checks, secrets audit, coherence."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from .models import SandboxProfile

# Keys the secrets template expects (from secrets.env.j2).
KNOWN_SECRET_KEYS: set[str] = {
    "ANTHROPIC_API_KEY",
    "OPENAI_API_KEY",
    "GEMINI_API_KEY",
    "OPENROUTER_API_KEY",
    "OPENCLAW_GATEWAY_PASSWORD",
    "OPENCLAW_GATEWAY_TOKEN",
    "GH_TOKEN",
    "SLACK_BOT_TOKEN",
    "DISCORD_BOT_TOKEN",
    "TELEGRAM_BOT_TOKEN",
}

# Minimum keys that should be present for a working sandbox.
REQUIRED_SECRET_KEYS: set[str] = {
    "ANTHROPIC_API_KEY",
    "GH_TOKEN",
}


@dataclass
class ValidationResult:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return len(self.errors) == 0


def validate_profile(profile: SandboxProfile) -> ValidationResult:
    """Run all checks and return a combined result."""
    result = ValidationResult()
    _check_paths(profile, result)
    _check_secrets(profile, result)
    _check_coherence(profile, result)
    return result


def _check_paths(profile: SandboxProfile, result: ValidationResult) -> None:
    """Verify that every non-empty mount path resolves to a real file/dir."""
    mount_fields = {
        "openclaw": profile.mounts.openclaw,
        "config": profile.mounts.config,
        "agent_data": profile.mounts.agent_data,
        "buildlog_data": profile.mounts.buildlog_data,
        "secrets": profile.mounts.secrets,
        "vault": profile.mounts.vault,
    }
    for name, raw in mount_fields.items():
        if not raw:
            continue
        p = Path(raw).expanduser()
        if not p.exists():
            result.errors.append(f"mount.{name}: path does not exist: {p}")


def _check_secrets(profile: SandboxProfile, result: ValidationResult) -> None:
    """Parse .env file and check for known keys."""
    raw = profile.mounts.secrets
    if not raw:
        result.warnings.append("No secrets file configured — VM will have no API keys")
        return
    p = Path(raw).expanduser()
    if not p.exists():
        # Already caught by path check; don't duplicate.
        return
    try:
        text = p.read_text()
    except OSError as exc:
        result.errors.append(f"Cannot read secrets file: {exc}")
        return

    present: set[str] = set()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # Strip optional 'export ' prefix common in .env files
        if line.startswith("export "):
            line = line[len("export "):]
        key, _, _ = line.partition("=")
        present.add(key.strip())

    missing_required = REQUIRED_SECRET_KEYS - present
    if missing_required:
        result.errors.append(
            f"Secrets file is missing required keys: {', '.join(sorted(missing_required))}"
        )

    missing_optional = (KNOWN_SECRET_KEYS - REQUIRED_SECRET_KEYS) - present
    if missing_optional:
        result.warnings.append(
            f"Secrets file is missing optional keys: {', '.join(sorted(missing_optional))}"
        )


def _check_coherence(profile: SandboxProfile, result: ValidationResult) -> None:
    """Logical consistency checks."""
    if profile.mode.yolo and profile.mode.yolo_unsafe:
        result.errors.append("yolo and yolo_unsafe are mutually exclusive")

    if not profile.mounts.openclaw:
        result.warnings.append(
            "No openclaw mount — required for new VMs (ignored for existing ones)"
        )
