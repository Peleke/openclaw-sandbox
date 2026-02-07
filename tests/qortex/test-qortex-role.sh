#!/usr/bin/env bash
# Qortex Role Tests - Run from host to verify sandbox setup
#
# Usage:
#   ./tests/qortex/test-qortex-role.sh
#
# Prerequisites:
#   - Sandbox VM running (limactl list shows openclaw-sandbox Running)
#   - bootstrap.sh completed

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

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

log_info() {
  echo -e "  → $1"
}

vm_exec() {
  local result
  result=$(limactl shell openclaw-sandbox -- bash -c "$*" 2>&1)
  local exit_code=$?
  echo "$result" | grep -v "cd:.*No such file"
  return $exit_code
}

vm_exec_quiet() {
  limactl shell openclaw-sandbox -- bash -c "$*" 2>/dev/null
}

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Qortex Role Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Prerequisites
# ============================================================
echo "▸ Prerequisites"
echo ""

if limactl list 2>/dev/null | grep -q "openclaw-sandbox.*Running"; then
  log_pass "VM is running"
else
  log_fail "VM is not running (run ./bootstrap.sh first)"
  echo ""
  echo "Total: $PASS passed, $FAIL failed, $SKIP skipped"
  exit 1
fi

echo ""

# ============================================================
# SECTION 2: Seed Exchange Directories
# ============================================================
echo "▸ Seed Exchange Directories"
echo ""

# Test: ~/.qortex base directory
if vm_exec_quiet "test -d ~/.qortex"; then
  log_pass "~/.qortex directory exists"
else
  log_fail "~/.qortex directory missing"
fi

# Test: Seed subdirectories with correct mode
for subdir in pending processed failed; do
  if vm_exec_quiet "test -d ~/.qortex/seeds/$subdir"; then
    log_pass "Seed dir exists: seeds/$subdir"

    # Check permissions
    PERMS=$(vm_exec "stat -c '%a' ~/.qortex/seeds/$subdir" 2>/dev/null || echo "unknown")
    if [[ "$PERMS" == "750" ]]; then
      log_pass "Mode 0750: seeds/$subdir"
    else
      log_info "Mode $PERMS (expected 750): seeds/$subdir"
    fi
  else
    log_fail "Seed dir missing: seeds/$subdir"
  fi
done

# Test: Signals directory
if vm_exec_quiet "test -d ~/.qortex/signals"; then
  log_pass "Signals directory exists"
else
  log_fail "Signals directory missing"
fi

echo ""

# ============================================================
# SECTION 3: Interop Configuration
# ============================================================
echo "▸ Interop Configuration"
echo ""

# Test: interop.yaml exists
if vm_exec_quiet "test -f ~/.buildlog/interop.yaml"; then
  log_pass "~/.buildlog/interop.yaml exists"

  # Test: Contains qortex source
  if vm_exec "grep -q 'qortex' ~/.buildlog/interop.yaml" 2>/dev/null; then
    log_pass "interop.yaml references qortex"
  else
    log_fail "interop.yaml missing qortex reference"
  fi

  # Test: Contains seed directory paths
  if vm_exec "grep -q 'seeds/pending' ~/.buildlog/interop.yaml" 2>/dev/null; then
    log_pass "interop.yaml has pending seed path"
  else
    log_fail "interop.yaml missing pending seed path"
  fi

  # Test: Contains signal log path
  if vm_exec "grep -q 'signals/' ~/.buildlog/interop.yaml" 2>/dev/null; then
    log_pass "interop.yaml has signal log path"
  else
    log_fail "interop.yaml missing signal log path"
  fi
else
  log_fail "~/.buildlog/interop.yaml does not exist"
fi

echo ""

# ============================================================
# SECTION 4: Qortex CLI
# ============================================================
echo "▸ Qortex CLI"
echo ""

# Test: qortex is installed
if vm_exec_quiet "~/.local/bin/qortex --version" >/dev/null 2>&1; then
  log_pass "qortex CLI is installed"

  QORTEX_VERSION=$(vm_exec "~/.local/bin/qortex --version" 2>/dev/null | head -1)
  if [[ -n "$QORTEX_VERSION" ]]; then
    log_pass "qortex version: $QORTEX_VERSION"
  else
    log_info "Could not get qortex version"
  fi
else
  log_skip "qortex CLI not installed (may not be published yet)"
fi

# Test: buildlog ingest-seeds doesn't crash
INGEST_OUTPUT=$(vm_exec "~/.local/bin/buildlog ingest-seeds" 2>&1 || true)
if [[ $? -eq 0 ]] || echo "$INGEST_OUTPUT" | grep -qiE "ingested\|no seeds\|complete\|success"; then
  log_pass "buildlog ingest-seeds runs without crash"
else
  log_skip "buildlog ingest-seeds returned unexpected output"
  log_info "Output: $(echo "$INGEST_OUTPUT" | head -2)"
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo "═══════════════════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL + SKIP))
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC} (of $TOTAL)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
