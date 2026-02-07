#!/usr/bin/env bash
# Qortex Ansible Role Validation
#
# Validates the Ansible role structure and templates without running them.
# This is a "lint" test that catches issues before deployment.
#
# Usage:
#   ./tests/qortex/test-qortex-ansible.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROLE_DIR="$REPO_ROOT/ansible/roles/qortex"

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
echo "  Qortex Ansible Role Validation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Role Structure
# ============================================================
echo "▸ Role Structure"
echo ""

# Test: Role directory exists
if [[ -d "$ROLE_DIR" ]]; then
  log_pass "Role directory exists: ansible/roles/qortex"
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
for file in defaults/main.yml tasks/main.yml templates/interop.yaml.j2; do
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

TEMPLATE_FILE="$ROLE_DIR/templates/interop.yaml.j2"
if [[ -f "$TEMPLATE_FILE" ]]; then
  log_pass "interop.yaml template exists"

  # Check it references qortex
  if grep -q "qortex" "$TEMPLATE_FILE"; then
    log_pass "Template references qortex"
  else
    log_fail "Template missing qortex reference"
  fi

  # Check it uses Ansible variables (user_home)
  if grep -q "{{ user_home" "$TEMPLATE_FILE"; then
    log_pass "Template uses user_home variable"
  else
    log_fail "Template missing user_home variable"
  fi

  # Check seed directory references
  for dir in pending processed failed; do
    if grep -q "seeds/$dir" "$TEMPLATE_FILE"; then
      log_pass "Template references seeds/$dir"
    else
      log_fail "Template missing seeds/$dir"
    fi
  done

  # Check signal_log reference
  if grep -q "signal_log\|signals/" "$TEMPLATE_FILE"; then
    log_pass "Template references signal log"
  else
    log_fail "Template missing signal log"
  fi
else
  log_fail "interop.yaml template missing"
fi

echo ""

# ============================================================
# SECTION 4: Task Validation
# ============================================================
echo "▸ Task Validation"
echo ""

TASKS_FILE="$ROLE_DIR/tasks/main.yml"

# Test: user_home fact
if grep -q "Get user home directory" "$TASKS_FILE"; then
  log_pass "Tasks get user_home fact"
else
  log_fail "Tasks missing user_home fact"
fi

# Test: Seed directory creation
if grep -q "qortex seed directories" "$TASKS_FILE"; then
  log_pass "Tasks create seed directories"
else
  log_fail "Tasks missing seed directory creation"
fi

# Test: Signals directory
if grep -q "qortex signals directory" "$TASKS_FILE"; then
  log_pass "Tasks create signals directory"
else
  log_fail "Tasks missing signals directory"
fi

# Test: buildlog dir guard (check-before-create pattern to avoid chown on Lima symlinks)
if grep -q "Check if buildlog directory exists" "$TASKS_FILE" && grep -q "Create buildlog directory for interop config" "$TASKS_FILE"; then
  log_pass "Tasks guard buildlog directory existence (check-before-create)"
else
  log_fail "Tasks missing buildlog directory guard"
fi

# Test: interop.yaml deployment
if grep -q "interop.yaml" "$TASKS_FILE"; then
  log_pass "Tasks deploy interop.yaml"
else
  log_fail "Tasks missing interop.yaml deployment"
fi

# Test: uv install guard
if grep -q "Check if uv is installed" "$TASKS_FILE"; then
  log_pass "Tasks check for uv installation"
else
  log_fail "Tasks missing uv install check"
fi

# Test: qortex installation via uv
if grep -q "uv tool install qortex" "$TASKS_FILE"; then
  log_pass "Tasks install qortex via uv tool"
else
  log_fail "Tasks missing qortex installation"
fi

echo ""

# ============================================================
# SECTION 5: Defaults Validation
# ============================================================
echo "▸ Defaults Validation"
echo ""

DEFAULTS_FILE="$ROLE_DIR/defaults/main.yml"

for var in qortex_enabled qortex_install qortex_extras; do
  if grep -q "^$var:" "$DEFAULTS_FILE"; then
    log_pass "Default defined: $var"
  else
    log_fail "Default missing: $var"
  fi
done

echo ""

# ============================================================
# SECTION 6: Playbook Integration
# ============================================================
echo "▸ Playbook Integration"
echo ""

PLAYBOOK_FILE="$REPO_ROOT/ansible/playbook.yml"

if [[ -f "$PLAYBOOK_FILE" ]]; then
  # Test: Qortex role is included
  if grep -q "role: qortex" "$PLAYBOOK_FILE"; then
    log_pass "Qortex role included in playbook"
  else
    log_fail "Qortex role not in playbook"
  fi

  # Test: Has tags
  if grep -A1 "role: qortex" "$PLAYBOOK_FILE" | grep -q "tags:"; then
    log_pass "Qortex role has tags"
  else
    log_info "Qortex role missing tags (optional)"
  fi

  # Test: Has conditional
  if grep -A2 "role: qortex" "$PLAYBOOK_FILE" | grep -q "when:"; then
    log_pass "Qortex role has when condition"
  else
    log_info "Qortex role missing when condition"
  fi

  # Test: Role order (qortex should come after buildlog, before sandbox)
  BUILDLOG_LINE=$(grep -n "role: buildlog" "$PLAYBOOK_FILE" | head -1 | cut -d: -f1 || echo "0")
  QORTEX_LINE=$(grep -n "role: qortex" "$PLAYBOOK_FILE" | head -1 | cut -d: -f1 || echo "0")
  SANDBOX_LINE=$(grep -n "role: sandbox" "$PLAYBOOK_FILE" | head -1 | cut -d: -f1 || echo "0")

  if [[ "$BUILDLOG_LINE" != "0" && "$QORTEX_LINE" != "0" ]]; then
    if [[ "$QORTEX_LINE" -gt "$BUILDLOG_LINE" ]]; then
      log_pass "Role order correct (buildlog before qortex)"
    else
      log_fail "Role order wrong (qortex should come after buildlog)"
    fi
  fi

  if [[ "$SANDBOX_LINE" != "0" && "$QORTEX_LINE" != "0" ]]; then
    if [[ "$QORTEX_LINE" -lt "$SANDBOX_LINE" ]]; then
      log_pass "Role order correct (qortex before sandbox)"
    else
      log_fail "Role order wrong (qortex should come before sandbox)"
    fi
  fi
else
  log_fail "Playbook not found"
fi

echo ""

# ============================================================
# SECTION 7: Bootstrap Integration
# ============================================================
echo "▸ Bootstrap Integration"
echo ""

BOOTSTRAP_FILE="$REPO_ROOT/bootstrap.sh"

if [[ -f "$BOOTSTRAP_FILE" ]]; then
  # Test: --memgraph flag
  if grep -q "\-\-memgraph)" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap has --memgraph flag"
  else
    log_fail "Bootstrap missing --memgraph flag"
  fi

  # Test: --memgraph-port flag
  if grep -q "\-\-memgraph-port)" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap has --memgraph-port flag"
  else
    log_fail "Bootstrap missing --memgraph-port flag"
  fi

  # Test: memgraph_enabled passed to Ansible
  if grep -q "memgraph_enabled" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap passes memgraph_enabled to Ansible"
  else
    log_fail "Bootstrap missing memgraph_enabled Ansible var"
  fi

  # Test: Memgraph port forwards in Lima config
  if grep -q "7687" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap references Memgraph Bolt port 7687"
  else
    log_fail "Bootstrap missing Memgraph port 7687"
  fi

  if grep -q "7444" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap references Memgraph monitoring port 7444"
  else
    log_fail "Bootstrap missing Memgraph port 7444"
  fi
else
  log_fail "bootstrap.sh not found"
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
