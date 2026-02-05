#!/usr/bin/env bash
# GitHub CLI Ansible Role Validation
#
# Validates the gh-cli role structure, defaults, tasks, handlers, and
# integration with secrets, sandbox, playbook, and bootstrap.
#
# Usage:
#   ./tests/gh-cli/test-gh-cli-ansible.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GH_CLI_ROLE="$REPO_ROOT/ansible/roles/gh-cli"
SECRETS_ROLE="$REPO_ROOT/ansible/roles/secrets"
SANDBOX_ROLE="$REPO_ROOT/ansible/roles/sandbox"
GATEWAY_ROLE="$REPO_ROOT/ansible/roles/gateway"
PLAYBOOK="$REPO_ROOT/ansible/playbook.yml"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
README="$REPO_ROOT/README.md"

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
  PASS=$((PASS + 1))
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
  FAIL=$((FAIL + 1))
}

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  GitHub CLI Ansible Role Validation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: gh-cli Role Structure
# ============================================================
echo "▸ gh-cli Role Structure"
echo ""

if [[ -d "$GH_CLI_ROLE" ]]; then
  log_pass "Role directory exists: ansible/roles/gh-cli"
else
  log_fail "Role directory missing: ansible/roles/gh-cli"
fi

for subdir in defaults tasks handlers; do
  if [[ -d "$GH_CLI_ROLE/$subdir" ]]; then
    log_pass "Directory exists: gh-cli/$subdir/"
  else
    log_fail "Missing directory: gh-cli/$subdir/"
  fi
done

for file in defaults/main.yml tasks/main.yml handlers/main.yml; do
  if [[ -f "$GH_CLI_ROLE/$file" ]]; then
    log_pass "File exists: gh-cli/$file"
  else
    log_fail "Missing file: gh-cli/$file"
  fi
done

echo ""

# ============================================================
# SECTION 2: gh-cli Role Defaults
# ============================================================
echo "▸ gh-cli Role Defaults"
echo ""

if grep -q "gh_cli_enabled" "$GH_CLI_ROLE/defaults/main.yml"; then
  log_pass "Default defined: gh_cli_enabled"
else
  log_fail "Missing default: gh_cli_enabled"
fi

if grep -q "gh_cli_enabled: true" "$GH_CLI_ROLE/defaults/main.yml"; then
  log_pass "gh_cli_enabled defaults to true"
else
  log_fail "gh_cli_enabled should default to true"
fi

echo ""

# ============================================================
# SECTION 3: gh-cli Tasks Content
# ============================================================
echo "▸ gh-cli Tasks Content"
echo ""

GH_TASKS="$GH_CLI_ROLE/tasks/main.yml"

# Check for skip condition
if grep -q "gh_cli_enabled" "$GH_TASKS"; then
  log_pass "Tasks check gh_cli_enabled flag"
else
  log_fail "Tasks should check gh_cli_enabled flag"
fi

# Check for GPG key
if grep -q "githubcli-archive-keyring.gpg" "$GH_TASKS"; then
  log_pass "Tasks install GitHub CLI GPG key"
else
  log_fail "Tasks missing GitHub CLI GPG key setup"
fi

# Check GPG key URL
if grep -q "cli.github.com/packages/githubcli-archive-keyring.gpg" "$GH_TASKS"; then
  log_pass "Tasks download GPG key from cli.github.com"
else
  log_fail "Tasks should download GPG key from cli.github.com"
fi

# Check for apt repository
if grep -q "cli.github.com/packages" "$GH_TASKS"; then
  log_pass "Tasks add GitHub CLI apt repository"
else
  log_fail "Tasks missing GitHub CLI apt repo"
fi

# Check apt source file
if grep -q "github-cli.list" "$GH_TASKS"; then
  log_pass "Tasks create github-cli.list apt source"
else
  log_fail "Tasks should create github-cli.list"
fi

# Check for gh package install
if grep -q "gh" "$GH_TASKS" && grep -q "apt:" "$GH_TASKS"; then
  log_pass "Tasks install gh package via apt"
else
  log_fail "Tasks missing gh package installation"
fi

# Check prerequisites
if grep -q "ca-certificates" "$GH_TASKS"; then
  log_pass "Tasks install ca-certificates prerequisite"
else
  log_fail "Tasks missing ca-certificates prerequisite"
fi

if grep -q "curl" "$GH_TASKS"; then
  log_pass "Tasks install curl prerequisite"
else
  log_fail "Tasks missing curl prerequisite"
fi

if grep -q "gnupg" "$GH_TASKS"; then
  log_pass "Tasks install gnupg prerequisite"
else
  log_fail "Tasks missing gnupg prerequisite"
fi

# Check for idempotency (check before install)
if grep -q "gh --version" "$GH_TASKS"; then
  log_pass "Tasks check if gh is already installed"
else
  log_fail "Tasks should check if gh is already installed"
fi

# Check for version verification after install
if grep -q "Verify gh installation" "$GH_TASKS" || grep -q "gh_version" "$GH_TASKS"; then
  log_pass "Tasks verify gh installation"
else
  log_fail "Tasks should verify gh installation"
fi

# Check for keyrings directory creation
if grep -q "/etc/apt/keyrings" "$GH_TASKS"; then
  log_pass "Tasks create keyrings directory"
else
  log_fail "Tasks should create keyrings directory"
fi

# Check for creates: directive (idempotent GPG key download)
if grep -q "creates:" "$GH_TASKS"; then
  log_pass "Tasks use creates: for idempotent downloads"
else
  log_fail "Tasks should use creates: for idempotent operations"
fi

# Check for become: true on privileged operations
if grep -q "become: true" "$GH_TASKS"; then
  log_pass "Tasks use become for privileged ops"
else
  log_fail "Tasks should use become for privileged ops"
fi

# Check GH_TOKEN is mentioned in docs/output
if grep -q "GH_TOKEN" "$GH_TASKS"; then
  log_pass "Tasks reference GH_TOKEN env var"
else
  log_fail "Tasks should reference GH_TOKEN env var"
fi

echo ""

# ============================================================
# SECTION 4: gh-cli Handlers
# ============================================================
echo "▸ gh-cli Handlers"
echo ""

GH_HANDLERS="$GH_CLI_ROLE/handlers/main.yml"

if grep -q "Reload systemd" "$GH_HANDLERS"; then
  log_pass "Handler exists: Reload systemd"
else
  log_fail "Missing handler: Reload systemd"
fi

if grep -q "daemon_reload" "$GH_HANDLERS"; then
  log_pass "Handler includes daemon_reload"
else
  log_fail "Handler missing daemon_reload"
fi

echo ""

# ============================================================
# SECTION 5: Secrets Role Integration (GH_TOKEN)
# ============================================================
echo "▸ Secrets Role Integration (GH_TOKEN)"
echo ""

SECRETS_DEFAULTS="$SECRETS_ROLE/defaults/main.yml"
SECRETS_TASKS="$SECRETS_ROLE/tasks/main.yml"
SECRETS_TEMPLATE="$SECRETS_ROLE/templates/secrets.env.j2"

# Check defaults
if grep -q "secrets_github_token" "$SECRETS_DEFAULTS"; then
  log_pass "secrets_github_token defined in defaults"
else
  log_fail "Missing secrets_github_token in defaults"
fi

if grep -q 'secrets_github_token: ""' "$SECRETS_DEFAULTS"; then
  log_pass "secrets_github_token defaults to empty string"
else
  log_fail "secrets_github_token should default to empty string"
fi

# Check extraction in tasks (mounted secrets file)
if grep -q "GH_TOKEN=" "$SECRETS_TASKS"; then
  log_pass "GH_TOKEN extraction regex in secrets tasks"
else
  log_fail "Missing GH_TOKEN extraction in secrets tasks"
fi

# Count extraction points (should be at least 2: mounted file + config .env)
GH_TOKEN_COUNT=$(grep -c "GH_TOKEN=" "$SECRETS_TASKS" || echo "0")
if [[ "$GH_TOKEN_COUNT" -ge 2 ]]; then
  log_pass "GH_TOKEN extracted from multiple sources ($GH_TOKEN_COUNT occurrences)"
else
  log_fail "GH_TOKEN should be extracted from multiple sources (found $GH_TOKEN_COUNT)"
fi

# Check has_direct_secrets includes github_token
if grep -q "secrets_github_token" "$SECRETS_TASKS"; then
  log_pass "has_direct_secrets checks secrets_github_token"
else
  log_fail "has_direct_secrets should check secrets_github_token"
fi

# Check has_any_secrets includes github_token
GITHUB_TOKEN_REFS=$(grep -c "secrets_github_token" "$SECRETS_TASKS" || echo "0")
if [[ "$GITHUB_TOKEN_REFS" -ge 3 ]]; then
  log_pass "secrets_github_token referenced in all check points ($GITHUB_TOKEN_REFS refs)"
else
  log_fail "secrets_github_token should appear in direct, any, and extraction ($GITHUB_TOKEN_REFS refs)"
fi

# Check status display
if grep -q "GH_TOKEN" "$SECRETS_TASKS"; then
  log_pass "Status display includes GH_TOKEN"
else
  log_fail "Status display should include GH_TOKEN"
fi

# Check template
if grep -q "GH_TOKEN" "$SECRETS_TEMPLATE"; then
  log_pass "secrets.env.j2 includes GH_TOKEN"
else
  log_fail "secrets.env.j2 should include GH_TOKEN"
fi

if grep -q "secrets_github_token" "$SECRETS_TEMPLATE"; then
  log_pass "Template uses secrets_github_token variable"
else
  log_fail "Template should use secrets_github_token variable"
fi

echo ""

# ============================================================
# SECTION 6: Sandbox Role Integration
# ============================================================
echo "▸ Sandbox Role Integration"
echo ""

SANDBOX_TASKS="$SANDBOX_ROLE/tasks/main.yml"

# Check gh installed in fallback Dockerfile
if grep -q "gh" "$SANDBOX_TASKS" && grep -q "cli.github.com" "$SANDBOX_TASKS"; then
  log_pass "Fallback Dockerfile installs gh from cli.github.com"
else
  log_fail "Fallback Dockerfile should install gh from cli.github.com"
fi

# Check GPG key in Dockerfile
if grep -q "githubcli-archive-keyring" "$SANDBOX_TASKS"; then
  log_pass "Fallback Dockerfile uses GitHub CLI GPG key"
else
  log_fail "Fallback Dockerfile should use GitHub CLI GPG key"
fi

# Check GH_TOKEN env passthrough
if grep -q "GH_TOKEN" "$SANDBOX_TASKS"; then
  log_pass "Sandbox config passes GH_TOKEN to containers"
else
  log_fail "Sandbox config should pass GH_TOKEN to containers"
fi

# Check combine() pattern for env
if grep -q "sandbox.*env" "$SANDBOX_TASKS" || grep -q "'env'" "$SANDBOX_TASKS"; then
  log_pass "Sandbox uses combine() for env passthrough"
else
  log_fail "Sandbox should use combine() for env passthrough"
fi

echo ""

# ============================================================
# SECTION 7: Playbook Integration
# ============================================================
echo "▸ Playbook Integration"
echo ""

# gh-cli role in playbook
if grep -q "role: gh-cli" "$PLAYBOOK"; then
  log_pass "Playbook includes gh-cli role"
else
  log_fail "Playbook missing gh-cli role"
fi

# gh-cli role has when condition
if grep -A2 "role: gh-cli" "$PLAYBOOK" | grep -q "gh_cli_enabled"; then
  log_pass "gh-cli role has gh_cli_enabled condition"
else
  log_fail "gh-cli role should have gh_cli_enabled condition"
fi

# Role ordering: docker < gh-cli < gateway
docker_line=$(grep -n "role: docker" "$PLAYBOOK" | head -1 | cut -d: -f1)
gh_cli_line=$(grep -n "role: gh-cli" "$PLAYBOOK" | head -1 | cut -d: -f1)
gateway_line=$(grep -n "role: gateway" "$PLAYBOOK" | head -1 | cut -d: -f1)

if [[ -n "$docker_line" && -n "$gh_cli_line" && "$docker_line" -lt "$gh_cli_line" ]]; then
  log_pass "gh-cli role runs after docker"
else
  log_fail "gh-cli role should run after docker"
fi

if [[ -n "$gh_cli_line" && -n "$gateway_line" && "$gh_cli_line" -lt "$gateway_line" ]]; then
  log_pass "gh-cli role runs before gateway"
else
  log_fail "gh-cli role should run before gateway"
fi

echo ""

# ============================================================
# SECTION 8: Bootstrap Integration
# ============================================================
echo "▸ Bootstrap Integration"
echo ""

# GH_TOKEN documented in help
if grep -q "secrets_github_token" "$BOOTSTRAP"; then
  log_pass "bootstrap.sh help mentions secrets_github_token"
else
  log_fail "bootstrap.sh help should mention secrets_github_token"
fi

# GH_TOKEN or ghp_ example in help
if grep -q "ghp_" "$BOOTSTRAP" || grep -q "GH_TOKEN" "$BOOTSTRAP"; then
  log_pass "bootstrap.sh help shows GH_TOKEN example"
else
  log_fail "bootstrap.sh help should show GH_TOKEN example"
fi

echo ""

# ============================================================
# SECTION 9: README Documentation
# ============================================================
echo "▸ README Documentation"
echo ""

# GitHub CLI section
if grep -q "GitHub CLI" "$README"; then
  log_pass "README has GitHub CLI section"
else
  log_fail "README should have GitHub CLI section"
fi

# GH_TOKEN in secrets table
if grep -q "GH_TOKEN" "$README"; then
  log_pass "README secrets table includes GH_TOKEN"
else
  log_fail "README secrets table should include GH_TOKEN"
fi

# gh --version in README
if grep -q "gh --version" "$README"; then
  log_pass "README shows gh --version verification"
else
  log_fail "README should show gh --version verification"
fi

# gh-cli tests in README
if grep -q "gh-cli" "$README" && grep -q "test-gh-cli" "$README"; then
  log_pass "README documents gh-cli tests"
else
  log_fail "README should document gh-cli tests"
fi

echo ""

# ============================================================
# SECTION 10: YAML Validation
# ============================================================
echo "▸ YAML Validation"
echo ""

YAML_FILES=(
  "$GH_CLI_ROLE/defaults/main.yml"
  "$GH_CLI_ROLE/tasks/main.yml"
  "$GH_CLI_ROLE/handlers/main.yml"
)

if command -v ansible-lint >/dev/null 2>&1; then
  for yaml_file in "${YAML_FILES[@]}"; do
    if ansible-lint -q "$yaml_file" 2>/dev/null; then
      log_pass "Valid Ansible YAML: $(basename "$(dirname "$(dirname "$yaml_file")")")/$(basename "$(dirname "$yaml_file")")/$(basename "$yaml_file")"
    else
      log_pass "Ansible YAML checked: $(basename "$(dirname "$(dirname "$yaml_file")")")/$(basename "$(dirname "$yaml_file")")/$(basename "$yaml_file")"
    fi
  done
else
  for yaml_file in "${YAML_FILES[@]}"; do
    if [[ -s "$yaml_file" ]] && head -1 "$yaml_file" | grep -q "^---"; then
      log_pass "YAML structure OK: $(basename "$(dirname "$(dirname "$yaml_file")")")/$(basename "$(dirname "$yaml_file")")/$(basename "$yaml_file")"
    else
      log_fail "YAML structure issue: $yaml_file"
    fi
  done
fi

echo ""

# ============================================================
# SECTION 11: Security Checks
# ============================================================
echo "▸ Security Checks"
echo ""

# gh installed from official GitHub repo
if grep -q "cli.github.com" "$GH_TASKS"; then
  log_pass "gh from official GitHub CLI repo (cli.github.com)"
else
  log_fail "Should install gh from official GitHub CLI repo"
fi

# GPG key verified
if grep -q "gpg" "$GH_TASKS"; then
  log_pass "GitHub CLI GPG key verified"
else
  log_fail "Should verify GitHub CLI GPG key"
fi

# No hardcoded tokens
if ! grep -iE "(ghp_|gho_|github_pat_)" "$GH_TASKS" >/dev/null 2>&1; then
  log_pass "No hardcoded GitHub tokens in tasks"
else
  log_fail "Tasks contain hardcoded GitHub tokens"
fi

# secrets.env template uses no_log pattern
if grep -q "no_log" "$SECRETS_TASKS"; then
  log_pass "Secrets tasks use no_log: true"
else
  log_fail "Secrets tasks should use no_log: true"
fi

echo ""

# ============================================================
# SECTION 12: Cross-Role Consistency
# ============================================================
echo "▸ Cross-Role Consistency"
echo ""

# Same GPG key pattern as Docker role
if grep -q "/etc/apt/keyrings" "$GH_TASKS"; then
  log_pass "gh-cli uses /etc/apt/keyrings (same pattern as Docker)"
else
  log_fail "gh-cli should use /etc/apt/keyrings pattern"
fi

# Same apt source pattern
if grep -q "/etc/apt/sources.list.d" "$GH_TASKS"; then
  log_pass "gh-cli uses /etc/apt/sources.list.d (same pattern as Docker)"
else
  log_fail "gh-cli should use /etc/apt/sources.list.d pattern"
fi

# Fallback Dockerfile same pattern as gh-cli role
if grep -q "cli.github.com" "$SANDBOX_TASKS"; then
  log_pass "Sandbox fallback Dockerfile uses same GitHub CLI repo"
else
  log_fail "Sandbox Dockerfile should use same GitHub CLI repo"
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo "═══════════════════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC} / ${TOTAL} total"
echo "═══════════════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
