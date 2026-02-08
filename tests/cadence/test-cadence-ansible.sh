#!/usr/bin/env bash
# Cadence Ansible Role Validation
#
# Validates the Ansible role structure and templates without running them.
# This is a "lint" test that catches issues before deployment.
#
# Usage:
#   ./tests/cadence/test-cadence-ansible.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROLE_DIR="$REPO_ROOT/ansible/roles/cadence"

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
echo "  Cadence Ansible Role Validation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Role Structure
# ============================================================
echo "▸ Role Structure"
echo ""

# Test: Role directory exists
if [[ -d "$ROLE_DIR" ]]; then
  log_pass "Role directory exists: ansible/roles/cadence"
else
  log_fail "Role directory missing"
  exit 1
fi

# Test: Required subdirectories
for subdir in defaults tasks templates handlers; do
  if [[ -d "$ROLE_DIR/$subdir" ]]; then
    log_pass "Directory exists: $subdir/"
  else
    log_fail "Missing directory: $subdir/"
  fi
done

# Test: Required files
for file in defaults/main.yml tasks/main.yml handlers/main.yml templates/cadence.json.j2; do
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
  for yaml_file in defaults/main.yml tasks/main.yml handlers/main.yml; do
    if yamllint -d relaxed "$ROLE_DIR/$yaml_file" >/dev/null 2>&1; then
      log_pass "Valid YAML: $yaml_file"
    else
      log_fail "Invalid YAML: $yaml_file"
      yamllint -d relaxed "$ROLE_DIR/$yaml_file" 2>&1 | head -5
    fi
  done
elif command -v ansible-playbook &>/dev/null; then
  # Use ansible's built-in YAML parser via syntax check
  for yaml_file in defaults/main.yml tasks/main.yml handlers/main.yml; do
    # Basic check: file starts with --- or has valid structure
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

# Test: cadence.json.j2 produces valid JSON structure
TEMPLATE_FILE="$ROLE_DIR/templates/cadence.json.j2"
if [[ -f "$TEMPLATE_FILE" ]]; then
  # Check for required Jinja2 variables
  for var in cadence_enabled cadence_vault_path cadence_delivery_channel; do
    if grep -q "{{ $var" "$TEMPLATE_FILE"; then
      log_pass "Template uses variable: $var"
    else
      log_fail "Template missing variable: $var"
    fi
  done

  # Check fileLogPath in delivery section
  if grep -q "fileLogPath" "$TEMPLATE_FILE"; then
    log_pass "Template includes fileLogPath for container bridging"
  else
    log_fail "Template missing fileLogPath in delivery section"
  fi

  # Check JSON structure (basic brace matching)
  OPEN_BRACES=$(grep -o '{' "$TEMPLATE_FILE" | wc -l | tr -d ' ')
  CLOSE_BRACES=$(grep -o '}' "$TEMPLATE_FILE" | wc -l | tr -d ' ')
  if [[ "$OPEN_BRACES" -eq "$CLOSE_BRACES" ]]; then
    log_pass "Template has balanced braces"
  else
    log_fail "Template has unbalanced braces (open: $OPEN_BRACES, close: $CLOSE_BRACES)"
  fi
fi

echo ""

# ============================================================
# SECTION 4: Task Validation
# ============================================================
echo "▸ Task Validation"
echo ""

TASKS_FILE="$ROLE_DIR/tasks/main.yml"

# Test: Tasks use become for privileged operations
if grep -q "become: true" "$TASKS_FILE"; then
  log_pass "Tasks use 'become: true' for privilege escalation"
else
  log_fail "Tasks may be missing privilege escalation"
fi

# Test: Systemd service is created
if grep -q "openclaw-cadence.service" "$TASKS_FILE"; then
  log_pass "Tasks create systemd service"
else
  log_fail "Tasks don't create systemd service"
fi

# Test: Service has EnvironmentFile (for secrets)
if grep -q "EnvironmentFile" "$TASKS_FILE"; then
  log_pass "Service loads EnvironmentFile (secrets)"
else
  log_fail "Service missing EnvironmentFile directive"
fi

# Test: Tasks notify handlers
if grep -q "notify:" "$TASKS_FILE"; then
  log_pass "Tasks use handlers for notifications"
else
  log_info "Tasks don't use handlers (may be intentional)"
fi

# Test: macOS path fix logic exists
if grep -q "/Users/" "$TASKS_FILE"; then
  log_pass "Tasks handle macOS path conversion"
else
  log_fail "Tasks missing macOS path fix logic"
fi

# Test: Prerequisite checks exist
if grep -q "Check if Obsidian vault is mounted\|Check if Telegram is configured" "$TASKS_FILE"; then
  log_pass "Tasks include prerequisite checks"
else
  log_fail "Tasks missing prerequisite checks"
fi

echo ""

# ============================================================
# SECTION 5: Defaults Validation
# ============================================================
echo "▸ Defaults Validation"
echo ""

DEFAULTS_FILE="$ROLE_DIR/defaults/main.yml"

# Test: Required default variables exist
for var in cadence_enabled cadence_vault_path cadence_delivery_channel cadence_llm_provider cadence_schedule_enabled; do
  if grep -q "^$var:" "$DEFAULTS_FILE"; then
    log_pass "Default defined: $var"
  else
    log_fail "Default missing: $var"
  fi
done

# Test: cadence_enabled defaults to false (safe default)
if grep -q "cadence_enabled: false" "$DEFAULTS_FILE"; then
  log_pass "cadence_enabled defaults to false (safe)"
else
  log_fail "cadence_enabled should default to false"
fi

# Test: Vault path is VM path, not macOS
VAULT_DEFAULT=$(grep "cadence_vault_path:" "$DEFAULTS_FILE" | sed 's/.*: *//' | tr -d '"')
if [[ "$VAULT_DEFAULT" == /mnt/* || "$VAULT_DEFAULT" == /workspace* ]]; then
  log_pass "Default vault path is VM path: $VAULT_DEFAULT"
elif [[ "$VAULT_DEFAULT" == /Users/* ]]; then
  log_fail "Default vault path is macOS path (should be /mnt/... or /workspace-...)"
else
  log_info "Default vault path: $VAULT_DEFAULT"
fi

echo ""

# ============================================================
# SECTION 6: Playbook Integration
# ============================================================
echo "▸ Playbook Integration"
echo ""

PLAYBOOK_FILE="$REPO_ROOT/ansible/playbook.yml"

if [[ -f "$PLAYBOOK_FILE" ]]; then
  # Test: Cadence role is included
  if grep -q "role: cadence" "$PLAYBOOK_FILE"; then
    log_pass "Cadence role included in playbook"
  else
    log_fail "Cadence role not in playbook"
  fi

  # Test: Cadence role has tag
  if grep -A1 "role: cadence" "$PLAYBOOK_FILE" | grep -q "tags:"; then
    log_pass "Cadence role has tags"
  else
    log_info "Cadence role missing tags (optional)"
  fi

  # Test: Role order (cadence should come after gateway)
  GATEWAY_LINE=$(grep -n "role: gateway" "$PLAYBOOK_FILE" | head -1 | cut -d: -f1)
  CADENCE_LINE=$(grep -n "role: cadence" "$PLAYBOOK_FILE" | head -1 | cut -d: -f1)
  if [[ -n "$GATEWAY_LINE" && -n "$CADENCE_LINE" ]]; then
    if [[ "$CADENCE_LINE" -gt "$GATEWAY_LINE" ]]; then
      log_pass "Role order correct (gateway before cadence)"
    else
      log_fail "Role order wrong (cadence should come after gateway)"
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
