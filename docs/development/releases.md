# Releases

Bilrost uses [semantic versioning](https://semver.org/) with milestone-based releases.

## Versioning Policy

Versions follow `MAJOR.MINOR.PATCH`:

| Component | When to bump |
|-----------|-------------|
| **MAJOR** | Breaking changes to bootstrap flags, config format, or VM structure |
| **MINOR** | New features (new role, new capability, new integration) |
| **PATCH** | Bug fixes, documentation updates, test improvements |

Each minor release corresponds to a development phase (S1 through S11).

## Creating a Release

Use the release script to create a new release:

```bash
./scripts/release.sh 0.4.0
```

### What the Release Script Does

The script performs the following steps:

1. **Validates version format** -- ensures the version matches `MAJOR.MINOR.PATCH` (e.g., `0.4.0`).
2. **Checks branch** -- warns if you are not on `main` (prompts for confirmation to continue).
3. **Checks working directory** -- fails if there are uncommitted changes.
4. **Verifies CHANGELOG entry** -- checks that `CHANGELOG.md` has a `## [0.4.0]` section. If missing, opens your `$EDITOR` so you can add one.
5. **Updates CHANGELOG links** -- updates the `[Unreleased]` comparison link and adds a version comparison link.
6. **Commits CHANGELOG** -- if the CHANGELOG was modified, commits it as `docs: update CHANGELOG for v0.4.0`.
7. **Creates an annotated tag** -- `git tag -a v0.4.0 -m "Release v0.4.0"`.
8. **Pushes to origin** -- pushes both the `main` branch and the new tag.

!!! note
    The script will prompt you to confirm before tagging and pushing. You can abort at the confirmation step.

### Example Session

```
$ ./scripts/release.sh 0.5.0

==========================================
  openclaw-sandbox release script
==========================================

CHANGELOG.md has entry for [0.5.0]

CHANGELOG.md updated:
(diff output shown here)

Ready to release v0.5.0
Tag and push? [y/N] y

Pushing to origin...

==========================================
  Release v0.5.0 initiated!
==========================================

GitHub Actions will create the release.
Monitor: https://github.com/Peleke/openclaw-sandbox/actions
```

## GitHub Actions Release Workflow

When a tag matching `v*` is pushed, the release workflow (`.github/workflows/release.yml`) runs:

1. **Validate** -- checks that `CHANGELOG.md` has an entry for the tagged version.
2. **Create GitHub Release** -- extracts the release notes from `CHANGELOG.md` for that version and creates a GitHub Release with those notes.

The workflow uses `gh release create` with the extracted changelog section as the release body.

## CHANGELOG Format

The CHANGELOG follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format:

```markdown
# Changelog

All notable changes to openclaw-sandbox are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-02-04

### Added
- Feature description

### Fixed
- Bug fix description

### Changed
- Change description

## [0.3.0] - 2026-02-03

### Added
...

[Unreleased]: https://github.com/Peleke/openclaw-sandbox/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/Peleke/openclaw-sandbox/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Peleke/openclaw-sandbox/compare/v0.2.0...v0.3.0
```

### Sections

Use these section headers within each version block:

| Section | Use for |
|---------|---------|
| `### Added` | New features |
| `### Fixed` | Bug fixes |
| `### Changed` | Changes to existing functionality |
| `### Deprecated` | Features that will be removed |
| `### Removed` | Features that were removed |
| `### Security` | Security-related changes |

### Comparison Links

The bottom of `CHANGELOG.md` contains comparison links for each version. The release script updates these automatically:

- `[Unreleased]` always compares the latest tag to `HEAD`.
- Each version compares its tag to the previous version's tag.
- The first version links to its release tag.

## Version History

| Version | Date | Milestone |
|---------|------|-----------|
| *Unreleased* | -- | PRs #36–#70: GitHub CLI, dual-container isolation, Python CLI, MCP server, config/data isolation, qortex interop, cadence wiring |
| 0.3.0 | 2026-02-03 | S1-S7: Bootstrap through Cadence |
| 0.2.0 | 2026-02-02 | S4-S6: Tailscale, Secrets, Telegram |
| 0.1.0 | 2026-02-01 | S1: Initial bootstrap infrastructure |

See [CHANGELOG.md](https://github.com/Peleke/openclaw-sandbox/blob/main/CHANGELOG.md) for the full release history.
