#!/usr/bin/env bash
# Buildlog Ansible Role Validation
#
# Validates the Ansible role structure and templates without running them.
# This is a "lint" test that catches issues before deployment.
#
# Usage:
#   ./tests/buildlog/test-buildlog-ansible.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROLE_DIR="$REPO_ROOT/ansible/roles/buildlog"

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
  PASS=$((PASS + 1))
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
  FAIL=$((FAIL + 1))
}

log_info() {
  echo -e "  → $1"
}

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Buildlog Ansible Role Validation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Role Structure
# ============================================================
echo "▸ Role Structure"
echo ""

# Test: Role directory exists
if [[ -d "$ROLE_DIR" ]]; then
  log_pass "Role directory exists: ansible/roles/buildlog"
else
  log_fail "Role directory missing"
  exit 1
fi

# Test: Required subdirectories
for subdir in defaults tasks templates; do
  if [[ -d "$ROLE_DIR/$subdir" ]]; then
    log_pass "Directory exists: $subdir/"
  else
    log_fail "Missing directory: $subdir/"
  fi
done

# Test: Required files
for file in defaults/main.yml tasks/main.yml templates/CLAUDE.md.default.j2; do
  if [[ -f "$ROLE_DIR/$file" ]]; then
    log_pass "File exists: $file"
  else
    log_fail "Missing file: $file"
  fi
done

echo ""

# ============================================================
# SECTION 2: YAML Validation
# ============================================================
echo "▸ YAML Syntax"
echo ""

# Check if yamllint is available
if command -v yamllint &>/dev/null; then
  for yaml_file in defaults/main.yml tasks/main.yml; do
    if yamllint -d relaxed "$ROLE_DIR/$yaml_file" >/dev/null 2>&1; then
      log_pass "Valid YAML: $yaml_file"
    else
      log_fail "Invalid YAML: $yaml_file"
      yamllint -d relaxed "$ROLE_DIR/$yaml_file" 2>&1 | head -5
    fi
  done
elif command -v ansible-playbook &>/dev/null; then
  for yaml_file in defaults/main.yml tasks/main.yml; do
    if head -1 "$ROLE_DIR/$yaml_file" | grep -qE '^---' || head -1 "$ROLE_DIR/$yaml_file" | grep -qE '^#'; then
      log_pass "Valid YAML: $yaml_file"
    else
      log_fail "Invalid YAML: $yaml_file (missing --- header)"
    fi
  done
else
  log_info "yamllint/ansible not available, skipping YAML validation"
fi

echo ""

# ============================================================
# SECTION 3: Template Validation
# ============================================================
echo "▸ Template Validation"
echo ""

# Test: Default CLAUDE.md template
TEMPLATE_FILE="$ROLE_DIR/templates/CLAUDE.md.default.j2"
if [[ -f "$TEMPLATE_FILE" ]]; then
  log_pass "Default CLAUDE.md template exists"

  # Check it mentions sandbox
  if grep -q "sandbox\|Sandbox\|SANDBOX" "$TEMPLATE_FILE"; then
    log_pass "Template mentions sandbox context"
  else
    log_fail "Template missing sandbox context"
  fi

  # Check it uses ansible variables
  if grep -q "{{ ansible_user" "$TEMPLATE_FILE"; then
    log_pass "Template uses Ansible variables"
  else
    log_info "Template doesn't use Ansible variables (may be static)"
  fi
else
  log_fail "Default CLAUDE.md template missing"
fi

echo ""

# ============================================================
# SECTION 4: Task Validation
# ============================================================
echo "▸ Task Validation"
echo ""

TASKS_FILE="$ROLE_DIR/tasks/main.yml"

# Test: uv installation
if grep -q "Install uv" "$TASKS_FILE"; then
  log_pass "Tasks install uv"
else
  log_fail "Tasks missing uv installation"
fi

# Test: buildlog installation via uv tool
if grep -q "uv tool install buildlog" "$TASKS_FILE"; then
  log_pass "Tasks install buildlog via uv tool"
else
  log_fail "Tasks missing buildlog installation"
fi

# Test: init-mcp command
if grep -q "buildlog init-mcp" "$TASKS_FILE"; then
  log_pass "Tasks run buildlog init-mcp"
else
  log_fail "Tasks missing init-mcp step"
fi

# Test: CLAUDE.md setup (3-step process)
if grep -q "Step 1.*Step 2.*Step 3\|CLAUDE.md Setup" "$TASKS_FILE"; then
  log_pass "Tasks implement 3-step CLAUDE.md setup"
else
  log_info "Could not verify 3-step CLAUDE.md process"
fi

# Test: blockinfile for sandbox notes
if grep -q "blockinfile" "$TASKS_FILE"; then
  log_pass "Tasks use blockinfile for idempotent appends"
else
  log_fail "Tasks missing blockinfile (sandbox notes may duplicate)"
fi

# Test: PATH setup
if grep -q "\.local/bin.*PATH\|PATH.*\.local/bin" "$TASKS_FILE"; then
  log_pass "Tasks add uv tools to PATH"
else
  log_fail "Tasks missing PATH configuration"
fi

# Test: MCP test
if grep -q "buildlog mcp-test" "$TASKS_FILE"; then
  log_pass "Tasks verify MCP server"
else
  log_info "Tasks don't verify MCP (optional)"
fi

echo ""

# ============================================================
# SECTION 5: Defaults Validation
# ============================================================
echo "▸ Defaults Validation"
echo ""

DEFAULTS_FILE="$ROLE_DIR/defaults/main.yml"

# Test: Required default variables
for var in buildlog_version buildlog_extras buildlog_host_claude_md_path; do
  if grep -q "^$var:" "$DEFAULTS_FILE"; then
    log_pass "Default defined: $var"
  else
    log_fail "Default missing: $var"
  fi
done

# Test: buildlog_version defaults to empty (latest)
if grep -q 'buildlog_version: ""' "$DEFAULTS_FILE"; then
  log_pass "buildlog_version defaults to latest"
else
  log_info "buildlog_version has specific version set"
fi

# Test: buildlog_extras includes anthropic
if grep -q 'buildlog_extras:.*anthropic' "$DEFAULTS_FILE"; then
  log_pass "Extras include anthropic for LLM extraction"
else
  log_info "Extras don't include anthropic (optional)"
fi

# Test: Host CLAUDE.md path is provision mount
CLAUDE_PATH=$(grep "buildlog_host_claude_md_path:" "$DEFAULTS_FILE" | sed 's/.*: *//' | tr -d '"')
if [[ "$CLAUDE_PATH" == /mnt/provision/* ]]; then
  log_pass "Host CLAUDE.md path uses provision mount: $CLAUDE_PATH"
else
  log_info "Host CLAUDE.md path: $CLAUDE_PATH"
fi

echo ""

# ============================================================
# SECTION 6: Playbook Integration
# ============================================================
echo "▸ Playbook Integration"
echo ""

PLAYBOOK_FILE="$REPO_ROOT/ansible/playbook.yml"

if [[ -f "$PLAYBOOK_FILE" ]]; then
  # Test: Buildlog role is included
  if grep -q "role: buildlog" "$PLAYBOOK_FILE"; then
    log_pass "Buildlog role included in playbook"
  else
    log_fail "Buildlog role not in playbook"
  fi

  # Test: Buildlog role has tag
  if grep -A1 "role: buildlog" "$PLAYBOOK_FILE" | grep -q "tags:"; then
    log_pass "Buildlog role has tags"
  else
    log_info "Buildlog role missing tags (optional)"
  fi

  # Test: Role order (buildlog should come after cadence/gateway)
  CADENCE_LINE=$(grep -n "role: cadence" "$PLAYBOOK_FILE" | head -1 | cut -d: -f1 || echo "0")
  BUILDLOG_LINE=$(grep -n "role: buildlog" "$PLAYBOOK_FILE" | head -1 | cut -d: -f1 || echo "0")
  if [[ -n "$CADENCE_LINE" && -n "$BUILDLOG_LINE" && "$CADENCE_LINE" != "0" ]]; then
    if [[ "$BUILDLOG_LINE" -gt "$CADENCE_LINE" ]]; then
      log_pass "Role order correct (cadence before buildlog)"
    else
      log_fail "Role order wrong (buildlog should come after cadence)"
    fi
  fi
else
  log_fail "Playbook not found"
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo "═══════════════════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}Validation PASSED${NC} ($PASS/$TOTAL checks)"
else
  echo -e "  ${RED}Validation FAILED${NC} ($PASS passed, $FAIL failed)"
fi
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
