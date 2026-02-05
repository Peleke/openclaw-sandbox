#!/usr/bin/env bash
# Telegram Security Ansible Validation
#
# Validates that Telegram access control is configured securely:
# - dmPolicy is "pairing" (NOT "open")
# - allowFrom does NOT contain "*" wildcard
# - Pre-seeded user ID support works
# - bootstrap.sh documents telegram_user_id
# - README reflects pairing workflow
#
# Usage:
#   ./tests/telegram/test-telegram-ansible.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATEWAY_ROLE="$REPO_ROOT/ansible/roles/gateway"
FIX_VM_PATHS="$GATEWAY_ROLE/tasks/fix-vm-paths.yml"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
PLAYBOOK="$REPO_ROOT/ansible/playbook.yml"
README="$REPO_ROOT/README.md"

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
echo "  Telegram Security Ansible Validation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: fix-vm-paths.yml — dmPolicy Must Be "pairing"
# ============================================================
echo "▸ fix-vm-paths.yml: dmPolicy Security"
echo ""

if [[ -f "$FIX_VM_PATHS" ]]; then
  log_pass "fix-vm-paths.yml exists"
else
  log_fail "fix-vm-paths.yml missing"
  exit 1
fi

# CRITICAL: dmPolicy must NOT be "open"
if ! grep -q "'dmPolicy': 'open'" "$FIX_VM_PATHS" && \
   ! grep -q '"dmPolicy": "open"' "$FIX_VM_PATHS"; then
  log_pass "dmPolicy is NOT set to 'open'"
else
  log_fail "CRITICAL: dmPolicy is still set to 'open' — security vulnerability!"
fi

# dmPolicy must be "pairing"
if grep -q "'dmPolicy': 'pairing'" "$FIX_VM_PATHS" || \
   grep -q '"dmPolicy": "pairing"' "$FIX_VM_PATHS"; then
  log_pass "dmPolicy is set to 'pairing'"
else
  log_fail "dmPolicy should be 'pairing'"
fi

echo ""

# ============================================================
# SECTION 2: fix-vm-paths.yml — No Wildcard allowFrom
# ============================================================
echo "▸ fix-vm-paths.yml: allowFrom Security"
echo ""

# CRITICAL: allowFrom must NOT contain "*" wildcard
if ! grep -q "allowFrom.*\['\*'\]" "$FIX_VM_PATHS" && \
   ! grep -q 'allowFrom.*\["\*"\]' "$FIX_VM_PATHS" && \
   ! grep -q "allowFrom: \['\*'\]" "$FIX_VM_PATHS"; then
  log_pass "allowFrom does NOT contain wildcard '*'"
else
  log_fail "CRITICAL: allowFrom contains '*' wildcard — anyone can message!"
fi

# Should NOT have hardcoded open access
if ! grep -q "'allowFrom': \['\*'\]" "$FIX_VM_PATHS"; then
  log_pass "No hardcoded open access pattern"
else
  log_fail "Hardcoded open access pattern found"
fi

echo ""

# ============================================================
# SECTION 3: fix-vm-paths.yml — Pre-seeded User ID Support
# ============================================================
echo "▸ fix-vm-paths.yml: Pre-seeded User ID"
echo ""

# Check telegram_user_id variable is referenced
if grep -q "telegram_user_id" "$FIX_VM_PATHS"; then
  log_pass "References telegram_user_id variable"
else
  log_fail "Missing telegram_user_id variable support"
fi

# Check conditional: only set allowFrom when telegram_user_id is provided
if grep -q "telegram_user_id is defined" "$FIX_VM_PATHS"; then
  log_pass "Pre-seed is conditional on telegram_user_id being defined"
else
  log_fail "Pre-seed should be conditional on telegram_user_id"
fi

# Check the user ID is added to allowFrom (not wildcard)
if grep -q "telegram_user_id | string" "$FIX_VM_PATHS" || \
   grep -q "telegram_user_id" "$FIX_VM_PATHS"; then
  log_pass "User ID is converted to string for allowFrom"
else
  log_fail "User ID should be converted to string"
fi

# Check that allowFrom uses the variable, not a hardcoded value
if grep -A5 "Pre-seed\|pre-seed\|allowFrom" "$FIX_VM_PATHS" | grep -q "telegram_user_id"; then
  log_pass "allowFrom uses telegram_user_id variable (not hardcoded)"
else
  log_fail "allowFrom should use telegram_user_id variable"
fi

echo ""

# ============================================================
# SECTION 4: fix-vm-paths.yml — Task Structure
# ============================================================
echo "▸ fix-vm-paths.yml: Task Structure"
echo ""

# Separate tasks for dmPolicy and allowFrom
DMPOLICY_TASK_COUNT=$(grep -c "dmPolicy" "$FIX_VM_PATHS" || true)
if [[ "$DMPOLICY_TASK_COUNT" -ge 2 ]]; then
  log_pass "dmPolicy referenced in task name and config ($DMPOLICY_TASK_COUNT occurrences)"
else
  log_fail "Expected dmPolicy in multiple places (task name + config)"
fi

# Check task names are descriptive
if grep -q "pairing" "$FIX_VM_PATHS"; then
  log_pass "Task names reference 'pairing' (secure default)"
else
  log_fail "Task names should mention 'pairing'"
fi

# Check both tasks have 'when' conditions for telegram config existence
TELEGRAM_WHEN_COUNT=$(grep -c "openclaw_config.channels.telegram is defined" "$FIX_VM_PATHS" || true)
if [[ "$TELEGRAM_WHEN_COUNT" -ge 2 ]]; then
  log_pass "Both telegram tasks check config existence ($TELEGRAM_WHEN_COUNT 'when' guards)"
else
  log_fail "Expected at least 2 'when' guards for telegram config existence"
fi

echo ""

# ============================================================
# SECTION 5: fix-vm-paths.yml — Debug Message
# ============================================================
echo "▸ fix-vm-paths.yml: Debug Output"
echo ""

# Debug message should say "pairing" not "open"
if grep -q "pairing" "$FIX_VM_PATHS" | head -1 && \
   ! grep -q 'dmPolicy: open' "$FIX_VM_PATHS"; then
  log_pass "Debug message says 'pairing' (not 'open')"
else
  log_fail "Debug message should reference 'pairing' mode"
fi

# Debug should mention approval workflow
if grep -q "pair approve" "$FIX_VM_PATHS" || grep -q "approve" "$FIX_VM_PATHS"; then
  log_pass "Debug message mentions approval workflow"
else
  log_fail "Debug message should mention how to approve"
fi

echo ""

# ============================================================
# SECTION 6: bootstrap.sh — telegram_user_id Documentation
# ============================================================
echo "▸ bootstrap.sh: Telegram Documentation"
echo ""

# Help text mentions telegram_user_id
if grep -q "telegram_user_id" "$BOOTSTRAP"; then
  log_pass "Help text documents telegram_user_id"
else
  log_fail "Help text should document telegram_user_id"
fi

# Completion message mentions pairing
if grep -q "pairing" "$BOOTSTRAP"; then
  log_pass "Completion message mentions pairing"
else
  log_fail "Completion message should mention pairing"
fi

# Completion message mentions pair approve
if grep -q "pair approve" "$BOOTSTRAP"; then
  log_pass "Completion message shows 'pair approve' command"
else
  log_fail "Completion message should show 'pair approve' command"
fi

# No mention of "open" access in bootstrap
if ! grep -q "dmPolicy.*open" "$BOOTSTRAP" && \
   ! grep -q "open access" "$BOOTSTRAP"; then
  log_pass "No 'open access' language in bootstrap.sh"
else
  log_fail "bootstrap.sh should not mention 'open access'"
fi

echo ""

# ============================================================
# SECTION 7: README — Telegram Section
# ============================================================
echo "▸ README: Telegram Section"
echo ""

# README mentions pairing
if grep -q "pairing" "$README"; then
  log_pass "README mentions pairing"
else
  log_fail "README should mention pairing"
fi

# README mentions telegram_user_id
if grep -q "telegram_user_id" "$README"; then
  log_pass "README documents telegram_user_id variable"
else
  log_fail "README should document telegram_user_id"
fi

# README does NOT say open access / anyone can message
if ! grep -q "anyone can message" "$README"; then
  log_pass "README does NOT say 'anyone can message'"
else
  log_fail "CRITICAL: README still says 'anyone can message'"
fi

# README does NOT mention dmPolicy: open
if ! grep -q 'dmPolicy.*open' "$README" && \
   ! grep -q 'dmPolicy: "open"' "$README"; then
  log_pass "README does NOT mention dmPolicy: open"
else
  log_fail "README should not mention dmPolicy: open"
fi

# README mentions pair approve command
if grep -q "pair approve" "$README"; then
  log_pass "README documents 'pair approve' command"
else
  log_fail "README should document 'pair approve' command"
fi

# README mentions userinfobot (how to get ID)
if grep -q "userinfobot" "$README"; then
  log_pass "README explains how to get Telegram user ID"
else
  log_fail "README should explain how to get Telegram user ID"
fi

echo ""

# ============================================================
# SECTION 8: No Residual Open Access Patterns
# ============================================================
echo "▸ Residual Open Access Check (Full Codebase)"
echo ""

# Scan all Ansible files for dangerous open access patterns
ANSIBLE_DIR="$REPO_ROOT/ansible"

# Check for allowFrom: ["*"] in any ansible file
if ! grep -r "allowFrom.*\[.*\*.*\]" "$ANSIBLE_DIR" --include="*.yml" 2>/dev/null | grep -v "test" | grep -q .; then
  log_pass "No allowFrom wildcard in any Ansible YAML"
else
  log_fail "Found allowFrom wildcard in Ansible files:"
  grep -r "allowFrom.*\[.*\*.*\]" "$ANSIBLE_DIR" --include="*.yml" 2>/dev/null | grep -v "test" || true
fi

# Check for dmPolicy: open in any ansible file
if ! grep -r "'dmPolicy'.*'open'" "$ANSIBLE_DIR" --include="*.yml" 2>/dev/null | grep -q .; then
  log_pass "No dmPolicy: open in any Ansible YAML"
else
  log_fail "Found dmPolicy: open in Ansible files:"
  grep -r "'dmPolicy'.*'open'" "$ANSIBLE_DIR" --include="*.yml" 2>/dev/null || true
fi

echo ""

# ============================================================
# SECTION 9: YAML Validation
# ============================================================
echo "▸ YAML Validation"
echo ""

if [[ -s "$FIX_VM_PATHS" ]] && head -1 "$FIX_VM_PATHS" | grep -q "^---"; then
  log_pass "fix-vm-paths.yml has valid YAML structure"
else
  log_fail "fix-vm-paths.yml YAML structure issue"
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
