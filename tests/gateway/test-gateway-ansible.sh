#!/usr/bin/env bash
# Gateway Ansible Role Validation (config/data isolation focus)
#
# Validates the config-copy + agent-data-symlink pattern.
#
# Usage:
#   ./tests/gateway/test-gateway-ansible.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROLE_DIR="$REPO_ROOT/ansible/roles/gateway"

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
echo "  Gateway Ansible Role Validation (config/data isolation)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Role Structure
# ============================================================
echo "▸ Role Structure"
echo ""

if [[ -d "$ROLE_DIR" ]]; then
  log_pass "Role directory exists: ansible/roles/gateway"
else
  log_fail "Role directory missing"
  exit 1
fi

for file in tasks/main.yml tasks/fix-vm-paths.yml; do
  if [[ -f "$ROLE_DIR/$file" ]]; then
    log_pass "File exists: $file"
  else
    log_fail "Missing file: $file"
  fi
done

echo ""

# ============================================================
# SECTION 2: Config/Data Isolation Pattern
# ============================================================
echo "▸ Config/Data Isolation"
echo ""

TASKS_FILE="$ROLE_DIR/tasks/main.yml"

# Test: No longer symlinks whole ~/.openclaw directory
if grep -q "src: /mnt/openclaw-config" "$TASKS_FILE" && grep -q "dest.*\.openclaw\"$" "$TASKS_FILE"; then
  log_fail "Still symlinks whole ~/.openclaw to mount (old pattern)"
else
  log_pass "No whole-directory symlink to config mount"
fi

# Test: Ensures ~/.openclaw is a real directory
if grep -q "Ensure ~/.openclaw directory exists" "$TASKS_FILE"; then
  log_pass "Creates ~/.openclaw as real directory"
else
  log_fail "Missing ~/.openclaw directory creation"
fi

# Test: Legacy symlink removal
if grep -q "Check if ~/.openclaw is a symlink (legacy)" "$TASKS_FILE"; then
  log_pass "Handles legacy symlink removal"
else
  log_fail "Missing legacy symlink handling"
fi

# Test: Symlink check comes BEFORE directory ensure
SYMLINK_CHECK_LINE=$(grep -n "Check if ~/.openclaw is a symlink" "$TASKS_FILE" | head -1 | cut -d: -f1 || echo "999")
DIR_ENSURE_LINE=$(grep -n "Ensure ~/.openclaw directory exists" "$TASKS_FILE" | head -1 | cut -d: -f1 || echo "0")
if [[ "$SYMLINK_CHECK_LINE" -lt "$DIR_ENSURE_LINE" ]]; then
  log_pass "Symlink check comes before directory ensure (correct order)"
else
  log_fail "Symlink check should come before directory ensure"
fi

# Test: Config files copied via Ansible find+copy (not shell glob)
if grep -q "ansible.builtin.find" "$TASKS_FILE" && grep -q "Find config files on mount" "$TASKS_FILE"; then
  log_pass "Uses Ansible find+copy for config files (not shell glob)"
else
  log_fail "Should use Ansible find+copy instead of shell for config files"
fi

# Test: No shell-based config copy (security issue)
if grep -q "for f in /mnt/openclaw-config" "$TASKS_FILE"; then
  log_fail "Still uses shell glob for config copy (security concern)"
else
  log_pass "No shell glob for config copy"
fi

# Test: Directory has owner/group set
if grep -A6 "Ensure ~/.openclaw directory exists" "$TASKS_FILE" | grep -q "owner:"; then
  log_pass "~/.openclaw directory sets owner"
else
  log_fail "~/.openclaw directory missing owner (files will be root-owned)"
fi

# Test: Copied config files have owner/group set
if grep -A8 "Copy config files from mount" "$TASKS_FILE" | grep -q "owner:"; then
  log_pass "Copied config files set owner (gateway can read them)"
else
  log_fail "Copied config files missing owner (gateway EACCES crash)"
fi

# Test: Identity directories copied from config mount
if grep -q "Copy identity directories from config mount" "$TASKS_FILE"; then
  log_pass "Copies identity directories from config mount"
else
  log_fail "Missing identity directory copy (device auth, telegram pairing lost on recreate)"
fi

# Test: Identity copy sets owner
if grep -A8 "Copy identity directories from config mount" "$TASKS_FILE" | grep -q "owner:"; then
  log_pass "Identity directory copy sets owner"
else
  log_fail "Identity directory copy missing owner"
fi

# Test: Identity dirs defined in defaults
DEFAULTS_FILE="$ROLE_DIR/defaults/main.yml"
if [[ -f "$DEFAULTS_FILE" ]]; then
  for dir in identity credentials dotfiles; do
    if grep -q "$dir" "$DEFAULTS_FILE"; then
      log_pass "Identity defaults include '$dir' directory"
    else
      log_fail "Identity defaults missing '$dir' directory"
    fi
  done
else
  log_fail "Gateway defaults/main.yml not found (identity dirs not configurable)"
fi

echo ""

# ============================================================
# SECTION 3: Agent Data Mount
# ============================================================
echo "▸ Agent Data Mount"
echo ""

# Test: Agent data mount check
if grep -q "Check if agent data mount exists" "$TASKS_FILE"; then
  log_pass "Checks for agent data mount"
else
  log_fail "Missing agent data mount check"
fi

# Test: Agent data symlink
if grep -q "Symlink agents directory to persistent mount" "$TASKS_FILE"; then
  log_pass "Symlinks agents to persistent mount"
else
  log_fail "Missing agents symlink task"
fi

# Test: Uses agent_data_mount variable with default
if grep -q "agent_data_mount | default" "$TASKS_FILE"; then
  log_pass "agent_data_mount has default guard"
else
  log_fail "agent_data_mount missing default guard"
fi

# Test: Handles existing agents directory
if grep -q "Remove existing agents directory if mount available" "$TASKS_FILE"; then
  log_pass "Handles existing agents directory before symlinking"
else
  log_fail "Missing existing agents directory handling"
fi

# Test: Force symlink
if grep -q "force: true" "$TASKS_FILE"; then
  log_pass "Symlink uses force: true for idempotency"
else
  log_info "Symlink may not be idempotent without force: true"
fi

echo ""

# ============================================================
# SECTION 4: Bootstrap Integration
# ============================================================
echo "▸ Bootstrap Integration"
echo ""

BOOTSTRAP_FILE="$REPO_ROOT/bootstrap.sh"

if [[ -f "$BOOTSTRAP_FILE" ]]; then
  if grep -q "\-\-agent-data)" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap has --agent-data flag"
  else
    log_fail "Bootstrap missing --agent-data flag"
  fi

  if grep -q "agent_data_mount=" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap passes agent_data_mount to Ansible"
  else
    log_fail "Bootstrap missing agent_data_mount Ansible var"
  fi

  if grep -q "/mnt/openclaw-agents" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap references /mnt/openclaw-agents mount point"
  else
    log_fail "Bootstrap missing /mnt/openclaw-agents mount"
  fi

  # Test: Agent data mount is always writable
  if grep -A2 "mountPoint.*openclaw-agents" "$BOOTSTRAP_FILE" | grep -q "writable: true"; then
    log_pass "Agent data mount is writable: true"
  else
    log_fail "Agent data mount should be writable: true"
  fi
else
  log_fail "bootstrap.sh not found"
fi

echo ""

# ============================================================
# SECTION 5: fix-vm-paths.yml Compatibility
# ============================================================
echo "▸ fix-vm-paths.yml Compatibility"
echo ""

FIX_PATHS_FILE="$ROLE_DIR/tasks/fix-vm-paths.yml"

if [[ -f "$FIX_PATHS_FILE" ]]; then
  # Test: Writes to ~/.openclaw/openclaw.json (local copy)
  if grep -q "user_home.*\.openclaw/openclaw.json" "$FIX_PATHS_FILE"; then
    log_pass "fix-vm-paths writes to local ~/.openclaw/openclaw.json"
  else
    log_info "Could not verify fix-vm-paths write target"
  fi

  # Test: Does not depend on symlink
  if grep -q "/mnt/openclaw-config" "$FIX_PATHS_FILE"; then
    log_fail "fix-vm-paths references mount directly (should use local copy)"
  else
    log_pass "fix-vm-paths does not reference mount path directly"
  fi

  # Test: Workspace directory is world-readable (Docker sandbox containers need this)
  if grep -A6 "Create workspace directory" "$FIX_PATHS_FILE" | grep -q '0755'; then
    log_pass "Workspace directory mode 0755 (Docker sandbox can read it)"
  else
    log_fail "Workspace directory too restrictive — Docker sandbox agents can't read it"
  fi

  # Test: Workspace directory sets owner/group
  if grep -A6 "Create workspace directory" "$FIX_PATHS_FILE" | grep -q "owner:"; then
    log_pass "Workspace directory sets owner"
  else
    log_fail "Workspace directory missing owner"
  fi
else
  log_fail "fix-vm-paths.yml not found"
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
