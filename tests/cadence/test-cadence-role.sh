#!/usr/bin/env bash
# Cadence Role Tests - Run from host to verify sandbox setup
#
# Usage:
#   ./tests/cadence/test-cadence-role.sh
#
# Prerequisites:
#   - Sandbox VM running (limactl list shows openclaw-sandbox Running)
#   - bootstrap.sh completed with --vault flag

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
  # Run command in VM via bash -c for proper tilde expansion
  # Filter out Lima's cwd warnings while preserving exit code
  local result
  result=$(limactl shell openclaw-sandbox -- bash -c "$*" 2>&1)
  local exit_code=$?
  echo "$result" | grep -v "cd:.*No such file"
  return $exit_code
}

vm_exec_sudo() {
  limactl shell openclaw-sandbox -- sudo "$@" 2>/dev/null
}

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Cadence Role Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Prerequisites
# ============================================================
echo "▸ Prerequisites"
echo ""

# Test: VM is running
if limactl list 2>/dev/null | grep -q "openclaw-sandbox.*Running"; then
  log_pass "VM is running"
else
  log_fail "VM is not running (run ./bootstrap.sh first)"
  echo ""
  echo "Total: $PASS passed, $FAIL failed, $SKIP skipped"
  exit 1
fi

# Test: OpenClaw mounted
if vm_exec test -d /mnt/openclaw; then
  log_pass "OpenClaw repo mounted at /mnt/openclaw"
else
  log_fail "OpenClaw repo not mounted"
fi

# Test: Bun installed
if vm_exec test -f \~/.bun/bin/bun || vm_exec which bun >/dev/null 2>&1; then
  log_pass "Bun installed"
else
  log_skip "Bun not installed (run bootstrap.sh to provision)"
fi

echo ""

# ============================================================
# SECTION 2: Config Files
# ============================================================
echo "▸ Configuration"
echo ""

# Test: cadence.json exists
if vm_exec test -f \~/.openclaw/cadence.json; then
  log_pass "cadence.json exists"

  # Test: cadence.json is valid JSON
  if vm_exec "jq . ~/.openclaw/cadence.json" >/dev/null 2>&1; then
    log_pass "cadence.json is valid JSON"
  else
    log_fail "cadence.json is invalid JSON"
  fi

  # Test: vaultPath is Linux path (not macOS)
  VAULT_PATH=$(vm_exec "jq -r '.vaultPath // empty' ~/.openclaw/cadence.json")
  if [[ -n "$VAULT_PATH" ]]; then
    if [[ "$VAULT_PATH" == /Users/* ]]; then
      log_fail "vaultPath contains macOS path: $VAULT_PATH"
    else
      log_pass "vaultPath is Linux-compatible: $VAULT_PATH"
    fi
  else
    log_skip "vaultPath not set (configure manually)"
  fi

  # Test: delivery channel configured
  DELIVERY_CHANNEL=$(vm_exec "jq -r '.delivery.channel // \"log\"' ~/.openclaw/cadence.json")
  log_info "Delivery channel: $DELIVERY_CHANNEL"

  if [[ "$DELIVERY_CHANNEL" == "telegram" ]]; then
    CHAT_ID=$(vm_exec "jq -r '.delivery.telegramChatId // empty' ~/.openclaw/cadence.json")
    if [[ -n "$CHAT_ID" ]]; then
      log_pass "Telegram chat ID configured"
    else
      log_skip "Telegram chat ID not set (required for delivery)"
    fi
  fi

else
  log_fail "cadence.json does not exist"
fi

echo ""

# ============================================================
# SECTION 3: Systemd Service
# ============================================================
echo "▸ Systemd Service"
echo ""

# Test: Service file exists
if vm_exec_sudo test -f /etc/systemd/system/openclaw-cadence.service; then
  log_pass "Systemd service file exists"

  # Test: Service is enabled
  if vm_exec_sudo systemctl is-enabled openclaw-cadence >/dev/null 2>&1; then
    log_pass "Service is enabled"
  else
    log_fail "Service is not enabled"
  fi

  # Test: Service references correct script
  if vm_exec_sudo grep -q "scripts/cadence.ts start" /etc/systemd/system/openclaw-cadence.service; then
    log_pass "Service runs cadence.ts start"
  else
    log_fail "Service does not reference cadence.ts"
  fi

  # Test: Service has EnvironmentFile for secrets
  if vm_exec_sudo grep -q "EnvironmentFile" /etc/systemd/system/openclaw-cadence.service; then
    log_pass "Service loads secrets from EnvironmentFile"
  else
    log_fail "Service missing EnvironmentFile directive"
  fi

  # Test: Service depends on gateway
  if vm_exec_sudo grep -q "openclaw-gateway" /etc/systemd/system/openclaw-cadence.service; then
    log_pass "Service depends on gateway"
  else
    log_skip "Service does not depend on gateway (optional)"
  fi

else
  log_fail "Systemd service file does not exist"
fi

echo ""

# ============================================================
# SECTION 4: Runtime Verification
# ============================================================
echo "▸ Runtime"
echo ""

# Check if cadence is enabled before checking service status
CADENCE_ENABLED=$(vm_exec "jq -r '.enabled // false' ~/.openclaw/cadence.json" 2>/dev/null)

if [[ "$CADENCE_ENABLED" == "true" ]]; then
  # Test: Service is active (only if enabled)
  SERVICE_STATUS=$(vm_exec_sudo systemctl is-active openclaw-cadence 2>/dev/null || echo "inactive")
  if [[ "$SERVICE_STATUS" == "active" ]]; then
    log_pass "Cadence service is running"
  else
    log_fail "Cadence service is not running (status: $SERVICE_STATUS)"
    log_info "Check logs: limactl shell openclaw-sandbox -- sudo journalctl -u openclaw-cadence -n 20"
  fi
else
  log_skip "Cadence not enabled in config (service not started)"
  log_info "Enable by setting \"enabled\": true in cadence.json"
fi

# Test: Gateway service is running (prerequisite for cadence)
GATEWAY_STATUS=$(vm_exec_sudo systemctl is-active openclaw-gateway 2>/dev/null || echo "inactive")
if [[ "$GATEWAY_STATUS" == "active" ]]; then
  log_pass "Gateway service is running"
else
  log_fail "Gateway service is not running (cadence needs gateway)"
fi

# Test: Secrets file exists (needed for LLM API)
if vm_exec_sudo test -f /etc/openclaw/secrets.env; then
  log_pass "Secrets file exists"

  # Test: Has Anthropic API key (needed for insight extraction)
  if vm_exec_sudo grep -q "ANTHROPIC_API_KEY" /etc/openclaw/secrets.env; then
    log_pass "Anthropic API key configured"
  else
    log_skip "Anthropic API key not set (required for LLM extraction)"
  fi
else
  log_fail "Secrets file does not exist"
fi

echo ""

# ============================================================
# SECTION 5: Vault Mount
# ============================================================
echo "▸ Obsidian Vault"
echo ""

# Test: Vault mount point exists
if vm_exec test -d /mnt/obsidian; then
  log_pass "Vault mount point exists"

  # Test: Vault has content
  FILE_COUNT=$(vm_exec find /mnt/obsidian -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$FILE_COUNT" -gt 0 ]]; then
    log_pass "Vault contains $FILE_COUNT markdown files"
  else
    log_skip "Vault is empty or not mounted"
  fi
else
  log_skip "Vault not mounted at /mnt/obsidian"
  log_info "Mount with: ./bootstrap.sh --vault ~/path/to/vault"
fi

echo ""

# ============================================================
# SECTION 6: CLI Commands
# ============================================================
echo "▸ CLI Commands"
echo ""

# Test: cadence.ts script exists
if vm_exec test -f /mnt/openclaw/scripts/cadence.ts; then
  log_pass "cadence.ts script exists"

  # Test: Can run cadence status
  if vm_exec "cd /mnt/openclaw && ~/.bun/bin/bun scripts/cadence.ts status" >/dev/null 2>&1; then
    log_pass "cadence.ts status runs successfully"
  else
    log_fail "cadence.ts status failed"
  fi
else
  log_fail "cadence.ts script not found"
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
