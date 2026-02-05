#!/usr/bin/env bash
# Telegram Security VM Deployment Tests
#
# Verifies that the deployed VM has secure Telegram access control:
# - dmPolicy is "pairing" in openclaw.json
# - allowFrom does NOT contain "*"
# - Pre-seeded user ID appears if configured
#
# Usage:
#   ./tests/telegram/test-telegram-role.sh

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
echo "  Telegram Security VM Deployment Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check VM is running
if ! limactl list --json 2>/dev/null | jq -e 'if type == "array" then .[] else . end | select(.name == "'"${VM_NAME}"'") | select(.status == "Running")' > /dev/null 2>&1; then
  echo -e "${YELLOW}VM '${VM_NAME}' is not running. Skipping deployment tests.${NC}"
  echo ""
  exit 0
fi

# Get user home
USER_HOME=$(vm_exec bash -c 'echo $HOME' 2>/dev/null || echo "")

# ============================================================
# SECTION 1: openclaw.json Exists
# ============================================================
echo "▸ Config File"
echo ""

CONFIG_EXISTS=false
if vm_exec test -f "$USER_HOME/.openclaw/openclaw.json" 2>/dev/null; then
  log_pass "openclaw.json exists"
  CONFIG_EXISTS=true
else
  log_skip "openclaw.json does not exist (gateway not configured)"
fi

echo ""

if [[ "$CONFIG_EXISTS" == "false" ]]; then
  echo "═══════════════════════════════════════════════════════════════"
  TOTAL=$((PASS + FAIL + SKIP))
  echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC} / ${TOTAL} total"
  echo "═══════════════════════════════════════════════════════════════"
  exit 0
fi

# Read the config once
CONFIG_JSON=$(vm_exec bash -c "cat $USER_HOME/.openclaw/openclaw.json" 2>/dev/null || echo "{}")

# Check if telegram config exists
HAS_TELEGRAM=false
if echo "$CONFIG_JSON" | jq -e '.channels.telegram' >/dev/null 2>&1; then
  HAS_TELEGRAM=true
fi

# ============================================================
# SECTION 2: dmPolicy Must Be "pairing"
# ============================================================
echo "▸ dmPolicy Security"
echo ""

if [[ "$HAS_TELEGRAM" == "true" ]]; then
  DM_POLICY=$(echo "$CONFIG_JSON" | jq -r '.channels.telegram.dmPolicy // "not-set"' 2>/dev/null)

  # CRITICAL: must NOT be "open"
  if [[ "$DM_POLICY" != "open" ]]; then
    log_pass "dmPolicy is NOT 'open' (value: $DM_POLICY)"
  else
    log_fail "CRITICAL: dmPolicy is 'open' — security vulnerability!"
  fi

  # Should be "pairing"
  if [[ "$DM_POLICY" == "pairing" ]]; then
    log_pass "dmPolicy is 'pairing' (secure default)"
  elif [[ "$DM_POLICY" == "not-set" ]]; then
    log_pass "dmPolicy not explicitly set (OpenClaw defaults to 'pairing')"
  elif [[ "$DM_POLICY" == "allowlist" ]]; then
    log_pass "dmPolicy is 'allowlist' (also secure)"
  else
    log_fail "dmPolicy should be 'pairing' or 'allowlist', got: $DM_POLICY"
  fi
else
  log_skip "No telegram config in openclaw.json"
fi

echo ""

# ============================================================
# SECTION 3: allowFrom Must NOT Have Wildcard
# ============================================================
echo "▸ allowFrom Security"
echo ""

if [[ "$HAS_TELEGRAM" == "true" ]]; then
  ALLOW_FROM=$(echo "$CONFIG_JSON" | jq -r '.channels.telegram.allowFrom // []' 2>/dev/null)

  # CRITICAL: must NOT contain "*"
  if echo "$ALLOW_FROM" | jq -e 'map(select(. == "*")) | length == 0' >/dev/null 2>&1; then
    log_pass "allowFrom does NOT contain '*' wildcard"
  else
    log_fail "CRITICAL: allowFrom contains '*' — anyone can message!"
  fi

  # Check if allowFrom has entries (pre-seeded IDs)
  ALLOW_COUNT=$(echo "$ALLOW_FROM" | jq 'length' 2>/dev/null || echo "0")
  if [[ "$ALLOW_COUNT" -gt 0 ]]; then
    ENTRIES=$(echo "$ALLOW_FROM" | jq -r 'join(", ")' 2>/dev/null)
    log_pass "allowFrom has $ALLOW_COUNT pre-seeded entry/entries: [$ENTRIES]"
  else
    log_pass "allowFrom is empty (all senders must pair)"
  fi

  # Verify entries are numeric IDs (not wildcards or garbage)
  if [[ "$ALLOW_COUNT" -gt 0 ]]; then
    INVALID=$(echo "$ALLOW_FROM" | jq -r '.[] | select(test("^[0-9]+$") | not)' 2>/dev/null || echo "")
    if [[ -z "$INVALID" ]]; then
      log_pass "All allowFrom entries are numeric IDs"
    else
      log_fail "allowFrom contains non-numeric entries: $INVALID"
    fi
  fi
else
  log_skip "No telegram config in openclaw.json"
fi

echo ""

# ============================================================
# SECTION 4: Gateway Service Config
# ============================================================
echo "▸ Gateway Service"
echo ""

# Check gateway service file exists
if vm_exec test -f /etc/systemd/system/openclaw-gateway.service 2>/dev/null; then
  log_pass "Gateway service file exists"
else
  log_skip "Gateway service not installed"
fi

# Gateway should NOT have any open access env vars
if vm_exec test -f /etc/systemd/system/openclaw-gateway.service 2>/dev/null; then
  if ! vm_exec bash -c 'grep -i "OPEN_ACCESS\|DM_POLICY=open\|ALLOW_ALL" /etc/systemd/system/openclaw-gateway.service 2>/dev/null' 2>/dev/null | grep -q .; then
    log_pass "Gateway service has no open access environment variables"
  else
    log_fail "Gateway service contains open access environment variables"
  fi
fi

echo ""

# ============================================================
# SECTION 5: Pairing Store Directory
# ============================================================
echo "▸ Pairing Infrastructure"
echo ""

# Check if .openclaw directory exists (pairing store lives here)
if vm_exec test -d "$USER_HOME/.openclaw" 2>/dev/null; then
  log_pass "~/.openclaw directory exists (pairing store location)"
else
  log_skip "~/.openclaw directory missing"
fi

# Check permissions on openclaw.json (should not be world-readable)
if vm_exec test -f "$USER_HOME/.openclaw/openclaw.json" 2>/dev/null; then
  PERMS=$(vm_exec bash -c "stat -c '%a' $USER_HOME/.openclaw/openclaw.json" 2>/dev/null || echo "unknown")
  if [[ "$PERMS" == "640" || "$PERMS" == "600" ]]; then
    log_pass "openclaw.json permissions: $PERMS (restricted)"
  elif [[ "$PERMS" == "unknown" ]]; then
    log_skip "Could not check openclaw.json permissions"
  else
    log_fail "openclaw.json permissions: $PERMS (should be 640 or 600)"
  fi
fi

echo ""

# ============================================================
# SECTION 6: Full Config Dump (Informational)
# ============================================================
echo "▸ Telegram Config Summary"
echo ""

if [[ "$HAS_TELEGRAM" == "true" ]]; then
  TG_SUMMARY=$(echo "$CONFIG_JSON" | jq '{
    dmPolicy: .channels.telegram.dmPolicy,
    allowFrom: .channels.telegram.allowFrom,
    groupPolicy: .channels.telegram.groupPolicy,
    hasBotToken: (.channels.telegram.botToken != null)
  }' 2>/dev/null || echo "{}")
  echo "  $TG_SUMMARY"
  log_pass "Telegram config readable"
else
  log_skip "No telegram config to summarize"
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
