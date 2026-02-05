#!/usr/bin/env bash
# Overlay VM Deployment Tests
#
# Tests that the overlay role deploys correctly in the VM.
# Requires a running VM with the overlay role applied.
#
# Usage:
#   ./tests/overlay/test-overlay-role.sh

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
echo "  Overlay VM Deployment Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check VM is running
if ! limactl list --json 2>/dev/null | jq -e 'if type == "array" then .[] else . end | select(.name == "'"${VM_NAME}"'") | select(.status == "Running")' > /dev/null 2>&1; then
  echo -e "${YELLOW}VM '${VM_NAME}' is not running. Skipping deployment tests.${NC}"
  echo ""
  exit 0
fi

# ============================================================
# SECTION 1: Overlay Mount
# ============================================================
echo "▸ Overlay Mount"
echo ""

if vm_exec mountpoint -q /workspace 2>/dev/null; then
  log_pass "/workspace is a mounted filesystem"
else
  log_fail "/workspace is NOT mounted"
fi

if vm_exec test -d /workspace 2>/dev/null; then
  log_pass "/workspace directory exists"
else
  log_fail "/workspace directory missing"
fi

# Check mount type is overlay
if vm_exec mount 2>/dev/null | grep -q "on /workspace type overlay"; then
  log_pass "/workspace is an overlay mount"
else
  log_fail "/workspace is not an overlay mount"
fi

echo ""

# ============================================================
# SECTION 2: Read-Only Lower
# ============================================================
echo "▸ Read-Only Lower Mount"
echo ""

if vm_exec test -d /mnt/openclaw 2>/dev/null; then
  log_pass "/mnt/openclaw exists"
else
  log_fail "/mnt/openclaw missing"
fi

# Try to write to lower (should fail if read-only)
if ! vm_exec touch /mnt/openclaw/.overlay-test-$(date +%s) 2>/dev/null; then
  log_pass "/mnt/openclaw is read-only (write rejected)"
else
  log_fail "/mnt/openclaw is writable (should be read-only!)"
  # Clean up test file
  vm_exec rm -f /mnt/openclaw/.overlay-test-* 2>/dev/null || true
fi

echo ""

# ============================================================
# SECTION 3: Overlay Write
# ============================================================
echo "▸ Overlay Write (upper layer)"
echo ""

TEST_FILE="/workspace/.overlay-test-$$"
if vm_exec touch "$TEST_FILE" 2>/dev/null; then
  log_pass "Can write to /workspace"

  # Verify write went to upper, not lower
  if vm_exec test -f /var/lib/openclaw/overlay/openclaw/upper/.overlay-test-$$ 2>/dev/null; then
    log_pass "Write landed in overlay upper (not on host)"
  else
    log_fail "Write did not land in overlay upper"
  fi

  # Clean up
  vm_exec rm -f "$TEST_FILE" 2>/dev/null || true
else
  log_fail "Cannot write to /workspace"
fi

echo ""

# ============================================================
# SECTION 4: Overlay Directories
# ============================================================
echo "▸ Overlay Directory Structure"
echo ""

for dir in /var/lib/openclaw/overlay/openclaw/upper /var/lib/openclaw/overlay-work/openclaw; do
  if vm_exec test -d "$dir" 2>/dev/null; then
    log_pass "Directory exists: $dir"
  else
    log_fail "Directory missing: $dir"
  fi
done

echo ""

# ============================================================
# SECTION 5: Systemd Services
# ============================================================
echo "▸ Systemd Services"
echo ""

# workspace.mount
if vm_exec systemctl is-enabled workspace.mount 2>/dev/null | grep -q "enabled"; then
  log_pass "workspace.mount is enabled"
else
  log_fail "workspace.mount is not enabled"
fi

if vm_exec systemctl is-active workspace.mount 2>/dev/null | grep -q "active"; then
  log_pass "workspace.mount is active"
else
  log_fail "workspace.mount is not active"
fi

# overlay-watcher
if vm_exec systemctl is-enabled overlay-watcher 2>/dev/null | grep -q "enabled"; then
  log_pass "overlay-watcher is enabled"
else
  log_fail "overlay-watcher is not enabled"
fi

if vm_exec systemctl is-active overlay-watcher 2>/dev/null | grep -q "active"; then
  log_pass "overlay-watcher is active"
else
  log_fail "overlay-watcher is not active"
fi

echo ""

# ============================================================
# SECTION 6: Gateway Integration
# ============================================================
echo "▸ Gateway Integration"
echo ""

# Check gateway WorkingDirectory
if vm_exec cat /etc/systemd/system/openclaw-gateway.service 2>/dev/null | grep -q "WorkingDirectory=/workspace"; then
  log_pass "Gateway WorkingDirectory is /workspace"
else
  log_fail "Gateway WorkingDirectory is not /workspace"
fi

# Check gateway depends on workspace.mount
if vm_exec cat /etc/systemd/system/openclaw-gateway.service 2>/dev/null | grep -q "workspace.mount"; then
  log_pass "Gateway depends on workspace.mount"
else
  log_fail "Gateway missing workspace.mount dependency"
fi

echo ""

# ============================================================
# SECTION 7: Helper Scripts
# ============================================================
echo "▸ Helper Scripts"
echo ""

if vm_exec test -x /usr/local/bin/overlay-status 2>/dev/null; then
  log_pass "overlay-status script deployed and executable"
else
  log_fail "overlay-status script missing or not executable"
fi

if vm_exec test -x /usr/local/bin/overlay-reset 2>/dev/null; then
  log_pass "overlay-reset script deployed and executable"
else
  log_fail "overlay-reset script missing or not executable"
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
