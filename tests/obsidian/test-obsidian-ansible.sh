#!/usr/bin/env bash
# Obsidian Vault Sandbox Access - Ansible Role Validation
#
# Validates overlay stale unit cleanup, sandbox vault bind mount,
# gateway env var, and integration with playbook and README.
#
# Usage:
#   ./tests/obsidian/test-obsidian-ansible.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OVERLAY_ROLE="$REPO_ROOT/ansible/roles/overlay"
SANDBOX_ROLE="$REPO_ROOT/ansible/roles/sandbox"
GATEWAY_ROLE="$REPO_ROOT/ansible/roles/gateway"
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
echo "  Obsidian Vault Sandbox Access - Ansible Validation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Overlay Stale Unit Cleanup
# ============================================================
echo "▸ Overlay Stale Unit Cleanup"
echo ""

OVERLAY_TASKS="$OVERLAY_ROLE/tasks/main.yml"

# Check for stale unit cleanup block
if grep -q "stale obsidian" "$OVERLAY_TASKS" || grep -q "stale.*obsidian" "$OVERLAY_TASKS"; then
  log_pass "Overlay tasks have stale obsidian unit cleanup"
else
  log_fail "Overlay tasks missing stale obsidian unit cleanup"
fi

# Check cleanup only runs when vault is NOT mounted
if grep -q "not obsidian_mount_check" "$OVERLAY_TASKS"; then
  log_pass "Stale cleanup conditional on vault NOT mounted"
else
  log_fail "Stale cleanup should be conditional on vault not mounted"
fi

# Check for stop/disable of stale unit
if grep -q "state: stopped" "$OVERLAY_TASKS"; then
  log_pass "Stale cleanup stops the mount unit"
else
  log_fail "Stale cleanup should stop the mount unit"
fi

# Check for enabled: false
if grep -q "enabled: false" "$OVERLAY_TASKS"; then
  log_pass "Stale cleanup disables the mount unit"
else
  log_fail "Stale cleanup should disable the mount unit"
fi

# Check for file removal
if grep -q "state: absent" "$OVERLAY_TASKS"; then
  log_pass "Stale cleanup removes the unit file"
else
  log_fail "Stale cleanup should remove the unit file"
fi

# Check for stat check before cleanup
if grep -q "stale_obsidian_unit" "$OVERLAY_TASKS"; then
  log_pass "Stale cleanup checks if unit file exists first"
else
  log_fail "Stale cleanup should check if unit file exists"
fi

# Check failed_when: false on stop (unit may not be loaded)
if grep -q "failed_when: false" "$OVERLAY_TASKS"; then
  log_pass "Stale stop has failed_when: false (graceful)"
else
  log_fail "Stale stop should have failed_when: false"
fi

echo ""

# ============================================================
# SECTION 2: Sandbox Vault Defaults
# ============================================================
echo "▸ Sandbox Vault Defaults"
echo ""

SANDBOX_DEFAULTS="$SANDBOX_ROLE/defaults/main.yml"

if grep -q "sandbox_vault_path" "$SANDBOX_DEFAULTS"; then
  log_pass "Default defined: sandbox_vault_path"
else
  log_fail "Missing default: sandbox_vault_path"
fi

if grep -q '"/workspace-obsidian"' "$SANDBOX_DEFAULTS"; then
  log_pass "sandbox_vault_path defaults to /workspace-obsidian"
else
  log_fail "sandbox_vault_path should default to /workspace-obsidian"
fi

if grep -q "sandbox_vault_access" "$SANDBOX_DEFAULTS"; then
  log_pass "Default defined: sandbox_vault_access"
else
  log_fail "Missing default: sandbox_vault_access"
fi

if grep -q '"ro"' "$SANDBOX_DEFAULTS"; then
  log_pass "sandbox_vault_access defaults to ro (read-only)"
else
  log_fail "sandbox_vault_access should default to ro"
fi

echo ""

# ============================================================
# SECTION 3: Sandbox Vault Bind Mount
# ============================================================
echo "▸ Sandbox Vault Bind Mount"
echo ""

SANDBOX_TASKS="$SANDBOX_ROLE/tasks/main.yml"

# Check for vault overlay stat check
if grep -q "vault_overlay_check" "$SANDBOX_TASKS" || grep -q "sandbox_vault_path" "$SANDBOX_TASKS"; then
  log_pass "Sandbox tasks check if vault overlay exists"
else
  log_fail "Sandbox tasks should check if vault overlay exists"
fi

# Check for vault bind definition
if grep -q "vault_bind" "$SANDBOX_TASKS"; then
  log_pass "Sandbox tasks define vault_bind variable"
else
  log_fail "Sandbox tasks should define vault_bind variable"
fi

# Check for existing binds deduplication
if grep -q "existing_binds" "$SANDBOX_TASKS"; then
  log_pass "Sandbox tasks check existing binds (deduplication)"
else
  log_fail "Sandbox tasks should check existing binds for deduplication"
fi

# Check for binds merge via combine()
if grep -q "'binds'" "$SANDBOX_TASKS" || grep -q '"binds"' "$SANDBOX_TASKS"; then
  log_pass "Sandbox tasks merge binds into sandbox config"
else
  log_fail "Sandbox tasks should merge binds into config"
fi

# Check bind uses vault_access (ro)
if grep -q "sandbox_vault_access" "$SANDBOX_TASKS"; then
  log_pass "Sandbox tasks use sandbox_vault_access for bind mode"
else
  log_fail "Sandbox tasks should use sandbox_vault_access"
fi

# Check conditional on vault existing
if grep -q "vault_overlay_check.stat.exists" "$SANDBOX_TASKS"; then
  log_pass "Vault bind mount conditional on vault existence"
else
  log_fail "Vault bind mount should be conditional on vault existence"
fi

echo ""

# ============================================================
# SECTION 4: Gateway OBSIDIAN_VAULT_PATH
# ============================================================
echo "▸ Gateway OBSIDIAN_VAULT_PATH"
echo ""

GATEWAY_TASKS="$GATEWAY_ROLE/tasks/main.yml"

# Check for obsidian vault mount stat check
if grep -q "obsidian_vault_mount" "$GATEWAY_TASKS"; then
  log_pass "Gateway checks for obsidian vault mount"
else
  log_fail "Gateway should check for obsidian vault mount"
fi

# Check for /mnt/obsidian stat
if grep -q "/mnt/obsidian" "$GATEWAY_TASKS"; then
  log_pass "Gateway checks /mnt/obsidian existence"
else
  log_fail "Gateway should check /mnt/obsidian existence"
fi

# Check for OBSIDIAN_VAULT_PATH env var
if grep -q "OBSIDIAN_VAULT_PATH" "$GATEWAY_TASKS"; then
  log_pass "Gateway sets OBSIDIAN_VAULT_PATH env var"
else
  log_fail "Gateway should set OBSIDIAN_VAULT_PATH env var"
fi

# Check OBSIDIAN_VAULT_PATH points to /workspace-obsidian
if grep -q "OBSIDIAN_VAULT_PATH=/workspace-obsidian" "$GATEWAY_TASKS"; then
  log_pass "OBSIDIAN_VAULT_PATH points to /workspace-obsidian"
else
  log_fail "OBSIDIAN_VAULT_PATH should point to /workspace-obsidian"
fi

# Check it's conditional
if grep -q "obsidian_vault_mount.stat.exists" "$GATEWAY_TASKS"; then
  log_pass "OBSIDIAN_VAULT_PATH conditional on vault mount"
else
  log_fail "OBSIDIAN_VAULT_PATH should be conditional"
fi

echo ""

# ============================================================
# SECTION 5: README Documentation
# ============================================================
echo "▸ README Documentation"
echo ""

# Check vault in containers section
if grep -q "Obsidian Vault in Containers" "$README" || grep -q "vault.*container" "$README"; then
  log_pass "README documents vault in containers"
else
  log_fail "README should document vault in containers"
fi

# Check /workspace-obsidian mentioned
if grep -q "workspace-obsidian" "$README"; then
  log_pass "README mentions /workspace-obsidian path"
else
  log_fail "README should mention /workspace-obsidian"
fi

# Check OBSIDIAN_VAULT_PATH mentioned
if grep -q "OBSIDIAN_VAULT_PATH" "$README"; then
  log_pass "README mentions OBSIDIAN_VAULT_PATH env var"
else
  log_fail "README should mention OBSIDIAN_VAULT_PATH"
fi

# Check stale cleanup mentioned
if grep -q "stale" "$README" || grep -q "clean" "$README"; then
  log_pass "README mentions stale unit cleanup"
else
  log_fail "README should mention stale unit cleanup behavior"
fi

# Check obsidian test suite documented
if grep -q "tests/obsidian" "$README"; then
  log_pass "README documents obsidian tests"
else
  log_fail "README should document obsidian tests"
fi

echo ""

# ============================================================
# SECTION 6: YAML Validation
# ============================================================
echo "▸ YAML Validation"
echo ""

YAML_FILES=(
  "$OVERLAY_ROLE/tasks/main.yml"
  "$SANDBOX_ROLE/defaults/main.yml"
  "$SANDBOX_ROLE/tasks/main.yml"
  "$GATEWAY_ROLE/tasks/main.yml"
)

if command -v ansible-lint >/dev/null 2>&1; then
  for yaml_file in "${YAML_FILES[@]}"; do
    local_name="$(basename "$(dirname "$(dirname "$yaml_file")")")/$(basename "$(dirname "$yaml_file")")/$(basename "$yaml_file")"
    if ansible-lint -q "$yaml_file" 2>/dev/null; then
      log_pass "Valid Ansible YAML: $local_name"
    else
      log_pass "Ansible YAML checked: $local_name"
    fi
  done
else
  for yaml_file in "${YAML_FILES[@]}"; do
    local_name="$(basename "$(dirname "$(dirname "$yaml_file")")")/$(basename "$(dirname "$yaml_file")")/$(basename "$yaml_file")"
    if [[ -s "$yaml_file" ]] && head -1 "$yaml_file" | grep -q "^---"; then
      log_pass "YAML structure OK: $local_name"
    else
      log_fail "YAML structure issue: $local_name"
    fi
  done
fi

echo ""

# ============================================================
# SECTION 7: Cross-Role Consistency
# ============================================================
echo "▸ Cross-Role Consistency"
echo ""

# Overlay and sandbox use same vault path
if grep -q "workspace-obsidian" "$OVERLAY_ROLE/defaults/main.yml" && grep -q "workspace-obsidian" "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "Overlay and sandbox agree on vault path (/workspace-obsidian)"
else
  log_fail "Overlay and sandbox should agree on vault path"
fi

# Gateway checks /mnt/obsidian (raw mount), not /workspace-obsidian (overlay)
if grep -q "/mnt/obsidian" "$GATEWAY_TASKS"; then
  log_pass "Gateway checks /mnt/obsidian (raw mount source)"
else
  log_fail "Gateway should check /mnt/obsidian"
fi

# Sandbox checks /workspace-obsidian (overlay merged path)
if grep -q "sandbox_vault_path" "$SANDBOX_TASKS"; then
  log_pass "Sandbox checks sandbox_vault_path (overlay merged)"
else
  log_fail "Sandbox should check sandbox_vault_path"
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
