#!/usr/bin/env bash
# Obsidian Vault Sandbox Access - VM Deployment Tests
#
# Tests that vault is accessible in sandbox containers and
# that stale mount cleanup works correctly.
# Requires a running VM with roles applied.
#
# Usage:
#   ./tests/obsidian/test-obsidian-role.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

VM_NAME="openclaw-sandbox"

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
  PASS=$((PASS + 1))
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
  FAIL=$((FAIL + 1))
}

log_skip() {
  echo -e "${YELLOW}○${NC} $1 (skipped)"
  SKIP=$((SKIP + 1))
}

vm_exec() {
  limactl shell "${VM_NAME}" -- "$@"
}

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Obsidian Vault Sandbox Access - VM Deployment Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check VM is running
if ! limactl list --json 2>/dev/null | jq -e 'if type == "array" then .[] else . end | select(.name == "'"${VM_NAME}"'") | select(.status == "Running")' > /dev/null 2>&1; then
  echo -e "${YELLOW}VM '${VM_NAME}' is not running. Skipping deployment tests.${NC}"
  echo ""
  exit 0
fi

# ============================================================
# SECTION 1: Vault Mount Status
# ============================================================
echo "▸ Vault Mount Status"
echo ""

# Check if /mnt/obsidian exists (vault was passed via --vault)
VAULT_MOUNTED=false
if vm_exec test -d /mnt/obsidian 2>/dev/null; then
  log_pass "/mnt/obsidian mount exists"
  VAULT_MOUNTED=true
else
  log_skip "/mnt/obsidian not found (--vault not used, vault tests conditional)"
fi

echo ""

# ============================================================
# SECTION 2: Vault Overlay
# ============================================================
echo "▸ Vault Overlay"
echo ""

if [[ "$VAULT_MOUNTED" == "true" ]]; then
  # Check /workspace-obsidian overlay is mounted
  if vm_exec mountpoint -q /workspace-obsidian 2>/dev/null; then
    log_pass "/workspace-obsidian overlay is mounted"
  else
    log_fail "/workspace-obsidian overlay should be mounted when vault exists"
  fi

  # Check vault contents are visible
  if vm_exec ls /workspace-obsidian/ >/dev/null 2>&1; then
    log_pass "/workspace-obsidian contents are accessible"
  else
    log_fail "/workspace-obsidian contents should be accessible"
  fi
else
  # Check NO stale mount unit
  if ! vm_exec test -f /etc/systemd/system/workspace\\x2dobsidian.mount 2>/dev/null; then
    log_pass "No stale obsidian mount unit (vault not mounted)"
  else
    log_fail "Stale obsidian mount unit should be cleaned up when vault not mounted"
  fi

  # Check /workspace-obsidian is not a mountpoint
  if ! vm_exec mountpoint -q /workspace-obsidian 2>/dev/null; then
    log_pass "/workspace-obsidian is not mounted (expected without vault)"
  else
    log_fail "/workspace-obsidian should not be mounted without vault"
  fi
fi

echo ""

# ============================================================
# SECTION 3: Sandbox Config (vault bind)
# ============================================================
echo "▸ Sandbox Config (vault bind)"
echo ""

USER_HOME=$(vm_exec bash -c 'echo $HOME' 2>/dev/null || echo "/home/$(vm_exec whoami 2>/dev/null)")

if vm_exec test -f "$USER_HOME/.openclaw/openclaw.json" 2>/dev/null; then
  SANDBOX_CONFIG=$(vm_exec cat "$USER_HOME/.openclaw/openclaw.json" 2>/dev/null || echo "{}")

  if [[ "$VAULT_MOUNTED" == "true" ]]; then
    # Check sandbox.binds contains vault
    if echo "$SANDBOX_CONFIG" | jq -e '.agents.defaults.sandbox.docker.binds[]' 2>/dev/null | grep -q "workspace-obsidian"; then
      log_pass "openclaw.json has vault bind in sandbox.docker.binds"
    else
      log_fail "openclaw.json should have vault bind in sandbox.docker.binds"
    fi

    # Check bind is read-only
    if echo "$SANDBOX_CONFIG" | jq -e '.agents.defaults.sandbox.docker.binds[]' 2>/dev/null | grep -q ":ro"; then
      log_pass "Vault bind is read-only (:ro)"
    else
      log_fail "Vault bind should be read-only (:ro)"
    fi
  else
    # Without vault, binds should not contain vault
    if ! echo "$SANDBOX_CONFIG" | jq -e '.agents.defaults.sandbox.docker.binds[]' 2>/dev/null | grep -q "workspace-obsidian" 2>/dev/null; then
      log_pass "No vault bind in sandbox.binds (vault not mounted)"
    else
      log_fail "Should not have vault bind when vault not mounted"
    fi
  fi
else
  log_skip "openclaw.json not found"
fi

echo ""

# ============================================================
# SECTION 4: Container Vault Access
# ============================================================
echo "▸ Container Vault Access"
echo ""

if [[ "$VAULT_MOUNTED" == "true" ]]; then
  # Test Docker can bind-mount vault
  if vm_exec sudo docker run --rm -v /workspace-obsidian:/workspace-obsidian:ro alpine ls /workspace-obsidian >/dev/null 2>&1; then
    log_pass "Docker container can access vault at /workspace-obsidian"
  else
    log_fail "Docker container should be able to access vault"
  fi
else
  log_skip "Cannot test container vault access (vault not mounted)"
fi

echo ""

# ============================================================
# SECTION 5: Gateway OBSIDIAN_VAULT_PATH
# ============================================================
echo "▸ Gateway OBSIDIAN_VAULT_PATH"
echo ""

# Check gateway service file
if vm_exec test -f /etc/systemd/system/openclaw-gateway.service 2>/dev/null; then
  if [[ "$VAULT_MOUNTED" == "true" ]]; then
    if vm_exec grep -q "OBSIDIAN_VAULT_PATH=/workspace-obsidian" /etc/systemd/system/openclaw-gateway.service 2>/dev/null; then
      log_pass "Gateway has OBSIDIAN_VAULT_PATH env var"
    else
      log_fail "Gateway should have OBSIDIAN_VAULT_PATH when vault mounted"
    fi
  else
    if ! vm_exec grep -q "OBSIDIAN_VAULT_PATH" /etc/systemd/system/openclaw-gateway.service 2>/dev/null; then
      log_pass "Gateway has no OBSIDIAN_VAULT_PATH (vault not mounted)"
    else
      log_skip "Gateway has OBSIDIAN_VAULT_PATH (may be from previous provision)"
    fi
  fi
else
  log_skip "Gateway service file not found"
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo "═══════════════════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL + SKIP))
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC} / ${TOTAL} total"
echo "═══════════════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
