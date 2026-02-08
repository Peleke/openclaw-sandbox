# Testing

OpenClaw Sandbox has comprehensive test suites for every Ansible role. Tests are split into fast offline validation and full VM deployment checks.

## Test Structure

Each role follows a consistent three-file pattern:

```
tests/<role>/
  ├── run-all.sh                  # Runner: orchestrates both suites
  ├── test-<role>-ansible.sh      # Lint: role structure, defaults, templates, integration
  └── test-<role>-role.sh         # VM: deployment tests against a running VM
```

- **`run-all.sh`** -- Entrypoint that runs both suites sequentially. Accepts `--quick` to skip VM tests.
- **`test-*-ansible.sh`** -- Pure offline validation. Checks role file structure, defaults values, task definitions, template syntax, and integration with the playbook and bootstrap script. No VM required.
- **`test-*-role.sh`** -- Runs commands inside a live VM via `limactl shell`. Verifies that services are running, files exist with correct permissions, firewall rules are applied, and end-to-end behavior works.

### Pass/Fail Counter Pattern

Every test script uses a shared pattern: a `PASS` and `FAIL` counter, colored output, and a summary at the end:

```bash
PASS=0
FAIL=0

# Each assertion increments one counter
if [[ condition ]]; then
  echo -e "${GREEN}PASS${NC} description"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${NC} description"
  FAIL=$((FAIL + 1))
fi

# Summary
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
```

## Running Tests

### Quick Mode (No VM Required)

Quick mode runs only the Ansible validation tests. This is fast (seconds) and useful during development:

```bash
# Single role
./tests/overlay/run-all.sh --quick

# All roles
./tests/overlay/run-all.sh --quick && \
./tests/sandbox/run-all.sh --quick && \
./tests/gh-cli/run-all.sh --quick && \
./tests/obsidian/run-all.sh --quick && \
./tests/cadence/run-all.sh --quick && \
./tests/gateway/run-all.sh --quick && \
./tests/buildlog/run-all.sh --quick && \
./tests/qortex/run-all.sh --quick && \
./tests/telegram/run-all.sh --quick
```

!!! tip
    Use `--quick` for fast iteration while developing. Run full mode before opening a PR.

### Full Mode (Requires Running VM)

Full mode runs both Ansible validation and VM deployment tests. The VM must be running:

```bash
# Ensure VM is up
sandbox status   # or: limactl list

# Run full suite for a single role
./tests/overlay/run-all.sh

# Run all suites
./tests/overlay/run-all.sh && \
./tests/sandbox/run-all.sh && \
./tests/gh-cli/run-all.sh && \
./tests/obsidian/run-all.sh && \
./tests/cadence/run-all.sh && \
./tests/gateway/run-all.sh && \
./tests/buildlog/run-all.sh && \
./tests/qortex/run-all.sh && \
./tests/telegram/run-all.sh
```

!!! warning
    VM tests execute real commands inside the sandbox VM. Make sure you have a running, provisioned VM before running full mode.

## Test Suites

### Overlay Tests

| File | Type | Checks |
|------|------|--------|
| `test-overlay-ansible.sh` | Ansible validation | 60 |
| `test-overlay-role.sh` | VM deployment | 19 |

Covers: role structure, defaults, tasks, handlers, 5 templates, OverlayFS mount, overlay-status helper, overlay-reset, audit watcher, inotifywait integration.

### Docker + Sandbox Tests

| File | Type | Description |
|------|------|-------------|
| `test-sandbox-ansible.sh` | Ansible validation | Role structure, defaults, integration |
| `test-sandbox-role.sh` | VM deployment | Docker CE, sandbox image, config injection |

Covers: Docker CE installation, `openclaw-sandbox:bookworm-slim` image, `openclaw.json` sandbox config, bridge networking, `gh` augmentation in image.

### GitHub CLI Tests

| File | Type | Description |
|------|------|-------------|
| `test-gh-cli-ansible.sh` | Ansible validation | Role structure, secrets pipeline, integration |
| `test-gh-cli-role.sh` | VM deployment | `gh` installation, APT repo, token flow |

Covers: GitHub APT repository, `gh` binary, `GH_TOKEN` in secrets pipeline, sandbox env passthrough.

### Obsidian Vault Tests

| File | Type | Description |
|------|------|-------------|
| `test-obsidian-ansible.sh` | Ansible validation | Overlay stale cleanup, bind mount config |
| `test-obsidian-role.sh` | VM deployment | Mount verification, container access |

Covers: vault overlay mount, stale unit cleanup, sandbox bind mount config, `OBSIDIAN_VAULT_PATH` env var.

### Cadence Tests

| File | Type | Checks |
|------|------|--------|
| `test-cadence-ansible.sh` | Ansible validation | 32 |
| `test-cadence-role.sh` | VM deployment | 22 |
| `test-cadence-e2e.sh` | End-to-end pipeline | 10 |

Covers: systemd service, `auth-profiles.json`, file watcher, LLM extraction, Telegram delivery pipeline.

### Buildlog Tests

| File | Type | Description |
|------|------|-------------|
| `test-buildlog-ansible.sh` | Ansible validation | Role structure, CLAUDE.md pipeline, MCP config |
| `test-buildlog-role.sh` | VM deployment | `uv` installation, `buildlog` binary, MCP server |

Covers: `uv tool install buildlog`, CLAUDE.md 3-step pipeline (copy base, init-mcp, append sandbox policy).

### Telegram Tests

| File | Type | Description |
|------|------|-------------|
| `test-telegram-ansible.sh` | Ansible validation | Pairing config, DM policy, user ID seeding |
| `test-telegram-role.sh` | VM deployment | Bot connection, pairing flow |

Covers: `dmPolicy: "pairing"`, `TELEGRAM_BOT_TOKEN` secrets flow, pre-approved user ID.

### Gateway Tests

| File | Type | Description |
|------|------|-------------|
| `test-gateway-ansible.sh` | Ansible validation | Role structure, systemd unit, config injection |
| `test-gateway-role.sh` | VM deployment | Gateway service running, port forwarding, Docker access |

Covers: systemd service, `SupplementaryGroups=docker`, port 18789 forwarding, `openclaw.json` config.

### Qortex Tests

| File | Type | Description |
|------|------|-------------|
| `test-qortex-ansible.sh` | Ansible validation | Role structure, defaults, directory setup, interop config |
| `test-qortex-role.sh` | VM deployment | Seed directories, signals directory, qortex CLI, interop.yaml |

Covers: `~/.qortex/seeds/{pending,processed,failed}`, `~/.qortex/signals/`, `~/.buildlog/interop.yaml`, `uv tool install qortex`.

### Python CLI Tests (pytest)

The Python CLI has its own test suite (273 tests) run via pytest:

```bash
cd cli && pytest
```

Covers: profile management, VM orchestration, MCP server tools, Lima manager, config validation.

## Test Counts Summary

| Suite | Static (Ansible) | VM/E2E | Total |
|-------|:-:|:-:|:-:|
| Sandbox | 117 | 49 | 166 |
| GitHub CLI | 110 | -- | 110 |
| Cadence | 32 | 32 | 64 |
| Overlay | 58 | 19 | 77 |
| Obsidian | 66 | -- | 66 |
| Qortex | 58 | -- | 58 |
| Telegram | 56 | -- | 56 |
| Gateway | 55 | -- | 55 |
| Buildlog | 51 | -- | 51 |
| Python CLI | -- | -- | 273 (pytest) |

## CI/CD

CI runs automatically on every push to `main` and on every pull request.

### GitHub Actions Workflow

The CI pipeline (`.github/workflows/ci.yml`) runs three jobs:

| Job | What it does |
|-----|-------------|
| **Validate Ansible** | Runs `yamllint -d relaxed ansible/` and validates all YAML files with Python's `yaml.safe_load()` |
| **Quick Tests** | Runs Ansible validation test suites (the `--quick` equivalent) |
| **ShellCheck** | Lints all scripts in `scripts/`, `bootstrap.sh`, and test files |

```yaml
# The CI checks
- yamllint -d relaxed ansible/           # YAML syntax
- python yaml.safe_load() on all .yml    # Ansible YAML validation
- ShellCheck on scripts/ and tests/      # Shell script linting
```

!!! note
    CI does **not** run VM deployment tests (no Lima VM in GitHub Actions). VM tests are run locally before merging.

### Docs Deployment

A separate workflow (`.github/workflows/docs.yml`) builds and deploys the documentation site on pushes to `main` that touch `docs/`, `mkdocs.yml`, or `scripts/render-diagrams.sh`. It uses MkDocs with GitHub Pages.

## Adding Tests for a New Role

When you add a new Ansible role, follow this pattern:

### 1. Create the Test Directory

```bash
mkdir tests/<role-name>
```

### 2. Create the Ansible Validation Script

`tests/<role-name>/test-<role-name>-ansible.sh`:

```bash
#!/usr/bin/env bash
# <Role Name> Ansible Role Validation
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

check() {
  local desc="$1"
  local result="$2"
  if [[ "$result" == "true" ]]; then
    echo -e "  ${GREEN}PASS${NC} $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $desc"
    FAIL=$((FAIL + 1))
  fi
}

# Check role files exist
check "defaults/main.yml exists" \
  "$(test -f "$REPO_ROOT/ansible/roles/<role-name>/defaults/main.yml" && echo true || echo false)"

# Check integration with playbook
check "playbook includes role" \
  "$(grep -q '<role-name>' "$REPO_ROOT/ansible/playbook.yml" && echo true || echo false)"

# ... more checks ...

# Summary
TOTAL=$((PASS + FAIL))
if [[ $FAIL -gt 0 ]]; then
  echo -e "  ${RED}FAILED${NC} ($PASS/$TOTAL checks)"
  exit 1
else
  echo -e "  ${GREEN}PASSED${NC} ($PASS/$TOTAL checks)"
fi
```

### 3. Create the VM Deployment Script

`tests/<role-name>/test-<role-name>-role.sh`:

```bash
#!/usr/bin/env bash
# <Role Name> VM Deployment Tests
set -euo pipefail

VM_NAME="openclaw-sandbox"

vm_exec() {
  limactl shell "$VM_NAME" -- "$@"
}

# Check service is running
vm_exec systemctl is-active <service-name>

# Check file exists
vm_exec test -f /path/to/expected/file

# ... more checks ...
```

### 4. Create the Runner

`tests/<role-name>/run-all.sh`:

```bash
#!/usr/bin/env bash
# <Role Name> Test Suite - Run All Tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUICK_MODE=false
[[ "${1:-}" == "--quick" ]] && QUICK_MODE=true

# Always run Ansible validation
bash "$SCRIPT_DIR/test-<role-name>-ansible.sh"

# Skip VM tests in quick mode
if [[ "$QUICK_MODE" == "false" ]]; then
  bash "$SCRIPT_DIR/test-<role-name>-role.sh"
fi
```

### 5. Update CI

Add the new test to `.github/workflows/ci.yml` if it should run in CI, and make sure ShellCheck covers the new test scripts.

!!! tip
    Keep Ansible validation tests thorough -- they are the primary safety net in CI since VM tests cannot run in GitHub Actions.
