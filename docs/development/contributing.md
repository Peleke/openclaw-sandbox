# Contributing

Contributions to OpenClaw Sandbox are welcome. This guide covers the development workflow from fork to merged PR.

## Development Setup

### Prerequisites

You need macOS with Homebrew installed. The bootstrap script installs all other dependencies automatically, but for development you should also have:

```bash
# Core dependencies (installed by bootstrap.sh if missing)
brew install lima ansible jq gitleaks

# Development tools
brew install shellcheck yamllint
pip install yamllint   # Also available via pip
```

### Clone and Bootstrap

```bash
# Fork the repo on GitHub, then clone your fork
git clone https://github.com/<your-username>/openclaw-sandbox.git
cd openclaw-sandbox

# Bootstrap a VM for testing
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

## Workflow

### 1. Fork the Repository

Fork [Peleke/openclaw-sandbox](https://github.com/Peleke/openclaw-sandbox) on GitHub and clone your fork.

### 2. Create a Feature Branch

```bash
git checkout -b feat/my-feature main
```

Use conventional branch naming:

| Prefix | Purpose |
|--------|---------|
| `feat/` | New features |
| `fix/` | Bug fixes |
| `docs/` | Documentation changes |
| `test/` | Test additions or changes |
| `refactor/` | Code refactoring |

### 3. Make Changes

See the [Code Style](#code-style) section below for conventions.

### 4. Run Tests

Run quick tests for fast iteration (no VM required):

```bash
# All quick tests
./tests/overlay/run-all.sh --quick && \
./tests/sandbox/run-all.sh --quick && \
./tests/gh-cli/run-all.sh --quick && \
./tests/obsidian/run-all.sh --quick && \
./tests/cadence/run-all.sh --quick
```

!!! tip
    If your change only affects one role, run just that role's tests during development. Run the full suite before opening a PR.

Before submitting, run ShellCheck locally:

```bash
shellcheck scripts/*.sh bootstrap.sh tests/**/*.sh
```

And lint the YAML:

```bash
yamllint -d relaxed ansible/
```

### 5. Open a Pull Request

Push your branch and open a PR against `main`:

```bash
git push origin feat/my-feature
```

CI will run automatically on your PR:

- **YAML lint** -- `yamllint -d relaxed` on all Ansible files
- **Ansible validation** -- `yaml.safe_load()` on all `.yml` files
- **ShellCheck** -- lints `scripts/`, `bootstrap.sh`, and test files

!!! note
    CI does not run VM deployment tests. Run those locally before submitting: `./tests/<role>/run-all.sh` (full mode, requires a running VM).

## Code Style

### Ansible YAML

- Use 2-space indentation.
- Always provide `defaults/main.yml` for role variables.
- Use `no_log: true` on any task that handles secrets.
- Use `creates:` or `when:` conditions for idempotent tasks.
- Put Jinja2 expressions in double quotes: `"{{ variable }}"`.

!!! warning "Ansible YAML Gotcha"
    Standard YAML parsers (Python's `yaml.safe_load()`) will fail on Ansible files containing Jinja2 `{{ }}` expressions outside of quoted strings. CI uses `yaml.safe_load()`, so always quote your Jinja2 expressions.

### Shell Scripts

- All scripts must pass ShellCheck.
- Use `set -euo pipefail` at the top of every script.
- Use `#!/usr/bin/env bash` as the shebang.
- Quote all variable expansions: `"$variable"`, not `$variable`.
- Use `[[ ]]` for conditionals, not `[ ]`.
- Include a usage comment block at the top of each script.

### File Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Ansible role | `ansible/roles/<name>/` | `ansible/roles/overlay/` |
| Role defaults | `defaults/main.yml` | |
| Role tasks | `tasks/main.yml` | |
| Role handlers | `handlers/main.yml` | |
| Role templates | `templates/<name>.j2` | `templates/workspace.mount.j2` |
| Test runner | `tests/<role>/run-all.sh` | |
| Ansible test | `tests/<role>/test-<role>-ansible.sh` | |
| VM test | `tests/<role>/test-<role>-role.sh` | |
| Scripts | `scripts/<name>.sh` | `scripts/sync-gate.sh` |

### Commit Messages

Use conventional commit format:

```
<type>(<scope>): <description>

[optional body]
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`.

Examples:

```
feat(overlay): add audit watcher for overlay writes
fix(telegram): replace open access with pairing-based security
docs: update README for v0.4.0
test(gh-cli): add APT repo verification checks
```

## Adding a New Ansible Role

When adding a new role:

1. Create the role directory structure under `ansible/roles/<name>/`.
2. Add the role to `ansible/playbook.yml`.
3. Wire any new flags into `bootstrap.sh`.
4. Create the test suite (see [Testing > Adding Tests](testing.md#adding-tests-for-a-new-role)).
5. Update the README with the new feature.

### Secrets Pipeline

If your role requires a new secret, there are 5 insertion points in the secrets handling:

1. `ansible/roles/secrets/defaults/main.yml` -- default variable
2. Regex extraction block #1 in secrets tasks (extract from file)
3. Regex extraction block #2 in secrets tasks (extract from file)
4. `has_direct` condition (check for direct injection via `-e`)
5. `has_any` condition + status output

Plus the template that writes `/etc/openclaw/secrets.env`.

### APT Repository Pattern

If your role installs software from an APT repository:

1. Download the GPG key to `/etc/apt/keyrings/<name>.gpg` (use `creates:` for idempotency).
2. Add the source to `/etc/apt/sources.list.d/<name>.list`.
3. Run `apt-get update` then `apt-get install`.

This follows the same pattern used by the Docker and GitHub CLI roles.

## Questions?

Open an issue on [GitHub](https://github.com/Peleke/openclaw-sandbox/issues) if you have questions about contributing.
