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
# SECTION 4: OTEL Observability Environment
# ============================================================
echo "▸ OTEL Observability Environment"
echo ""

# Test: profile.d script deployed
if vm_exec_quiet "test -f /etc/profile.d/qortex-otel.sh"; then
  log_pass "/etc/profile.d/qortex-otel.sh exists"

  # Test: Contains QORTEX_OTEL_ENABLED
  if vm_exec "grep -q 'QORTEX_OTEL_ENABLED' /etc/profile.d/qortex-otel.sh" 2>/dev/null; then
    log_pass "OTEL script exports QORTEX_OTEL_ENABLED"
  else
    log_fail "OTEL script missing QORTEX_OTEL_ENABLED"
  fi

  # Test: Contains OTEL_EXPORTER_OTLP_ENDPOINT
  if vm_exec "grep -q 'OTEL_EXPORTER_OTLP_ENDPOINT' /etc/profile.d/qortex-otel.sh" 2>/dev/null; then
    log_pass "OTEL script exports OTEL_EXPORTER_OTLP_ENDPOINT"
  else
    log_fail "OTEL script missing OTEL_EXPORTER_OTLP_ENDPOINT"
  fi

  # Test: Contains OTEL_EXPORTER_OTLP_PROTOCOL
  if vm_exec "grep -q 'OTEL_EXPORTER_OTLP_PROTOCOL' /etc/profile.d/qortex-otel.sh" 2>/dev/null; then
    log_pass "OTEL script exports OTEL_EXPORTER_OTLP_PROTOCOL"
  else
    log_fail "OTEL script missing OTEL_EXPORTER_OTLP_PROTOCOL"
  fi

  # Test: Endpoint points to host
  if vm_exec "grep -q 'host.lima.internal' /etc/profile.d/qortex-otel.sh" 2>/dev/null; then
    log_pass "OTEL endpoint targets host.lima.internal"
  else
    log_fail "OTEL endpoint not targeting host.lima.internal"
  fi
else
  log_skip "/etc/profile.d/qortex-otel.sh not deployed (OTEL may be disabled)"
fi

# Test: bash.bashrc hook
if vm_exec "grep -q 'qortex-otel.sh' /etc/bash.bashrc" 2>/dev/null; then
  log_pass "bash.bashrc hooks qortex-otel.sh"
else
  log_skip "bash.bashrc missing qortex-otel.sh hook"
fi

# Test: env vars available in shell
OTEL_ENABLED=$(vm_exec "bash -l -c 'echo \$QORTEX_OTEL_ENABLED'" 2>/dev/null || echo "")
if [[ "$OTEL_ENABLED" == "true" ]]; then
  log_pass "QORTEX_OTEL_ENABLED=true in login shell"
else
  log_skip "QORTEX_OTEL_ENABLED not set (got: '$OTEL_ENABLED')"
fi

OTEL_ENDPOINT=$(vm_exec "bash -l -c 'echo \$OTEL_EXPORTER_OTLP_ENDPOINT'" 2>/dev/null || echo "")
if [[ -n "$OTEL_ENDPOINT" && "$OTEL_ENDPOINT" == *"host.lima.internal"* ]]; then
  log_pass "OTEL_EXPORTER_OTLP_ENDPOINT set to $OTEL_ENDPOINT"
else
  log_skip "OTEL_EXPORTER_OTLP_ENDPOINT not set"
fi

OTEL_PROTOCOL=$(vm_exec "bash -l -c 'echo \$OTEL_EXPORTER_OTLP_PROTOCOL'" 2>/dev/null || echo "")
if [[ "$OTEL_PROTOCOL" == "http/protobuf" ]]; then
  log_pass "OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf (bypasses gRPC)"
else
  log_skip "OTEL_EXPORTER_OTLP_PROTOCOL not set (got: '$OTEL_PROTOCOL')"
fi

echo ""

# ============================================================
# SECTION 5: Docker Container
# ============================================================
echo "▸ Docker Container"
echo ""

# Test: qortex container is running
CONTAINER_STATUS=$(vm_exec "docker inspect -f '{{.State.Status}}' qortex" 2>/dev/null || echo "not found")
if [[ "$CONTAINER_STATUS" == "running" ]]; then
  log_pass "qortex Docker container is running"
else
  log_fail "qortex Docker container not running (status: $CONTAINER_STATUS)"
fi

# Test: container uses host network
CONTAINER_NETWORK=$(vm_exec "docker inspect -f '{{.HostConfig.NetworkMode}}' qortex" 2>/dev/null || echo "unknown")
if [[ "$CONTAINER_NETWORK" == "host" ]]; then
  log_pass "Container uses host network"
else
  log_fail "Container not using host network (got: $CONTAINER_NETWORK)"
fi

# Test: container has data volume mounted
CONTAINER_MOUNTS=$(vm_exec "docker inspect -f '{{range .Mounts}}{{.Destination}} {{end}}' qortex" 2>/dev/null || echo "")
if echo "$CONTAINER_MOUNTS" | grep -q "/data"; then
  log_pass "Data volume mounted at /data"
else
  log_fail "Data volume not mounted (mounts: $CONTAINER_MOUNTS)"
fi

# Test: container has env file loaded
CONTAINER_ENV=$(vm_exec "docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' qortex" 2>/dev/null || echo "")
if echo "$CONTAINER_ENV" | grep -q "QORTEX_EXTRACTION=spacy"; then
  log_pass "Container has QORTEX_EXTRACTION=spacy"
else
  log_fail "Container missing QORTEX_EXTRACTION env var"
fi

if echo "$CONTAINER_ENV" | grep -q "QORTEX_OTEL_ENABLED=true"; then
  log_pass "Container has QORTEX_OTEL_ENABLED=true"
else
  log_skip "Container OTEL may be disabled"
fi

if echo "$CONTAINER_ENV" | grep -q "HF_HUB_OFFLINE=1"; then
  log_pass "Container has HF_HUB_OFFLINE=1 (no runtime downloads)"
else
  log_fail "Container missing HF_HUB_OFFLINE=1"
fi

# Test: old systemd services are gone
OLD_SYSTEMD=$(vm_exec "systemctl is-active qortex.service" 2>/dev/null || echo "inactive")
if [[ "$OLD_SYSTEMD" == "inactive" || "$OLD_SYSTEMD" == *"could not be found"* ]]; then
  log_pass "Old systemd qortex.service is gone"
else
  log_fail "Old systemd qortex.service still active: $OLD_SYSTEMD"
fi

echo ""

# ============================================================
# SECTION 6: Health Check & REST API
# ============================================================
echo "▸ Health Check & REST API"
echo ""

# Test: health endpoint responds
HEALTH_RESPONSE=$(vm_exec "curl -sf http://localhost:8400/v1/health" 2>/dev/null || echo "")
if echo "$HEALTH_RESPONSE" | grep -q '"status"'; then
  log_pass "GET /v1/health responds OK"
else
  log_fail "GET /v1/health failed (got: '$HEALTH_RESPONSE')"
fi

# Test: status endpoint responds (with auth)
API_KEY=$(vm_exec "cat /etc/openclaw/qortex-api-key" 2>/dev/null || echo "")
if [[ -n "$API_KEY" ]]; then
  log_pass "API key exists at /etc/openclaw/qortex-api-key"

  STATUS_RESPONSE=$(vm_exec "curl -sf -H 'Authorization: Bearer $API_KEY' http://localhost:8400/v1/status" 2>/dev/null || echo "")
  if echo "$STATUS_RESPONSE" | grep -q "status\|health"; then
    log_pass "GET /v1/status responds with auth"
  else
    log_skip "GET /v1/status did not respond (got: '$STATUS_RESPONSE')"
  fi
else
  log_skip "No API key found"
fi

echo ""

# ============================================================
# SECTION 7: Gateway Config
# ============================================================
echo "▸ Gateway Config (qortex transport)"
echo ""

# Test: openclaw.json has HTTP transport config
CONFIG_FILE=$(vm_exec "cat ~/.openclaw/openclaw.json" 2>/dev/null || echo "{}")
if echo "$CONFIG_FILE" | grep -q '"transport".*"http"'; then
  log_pass "openclaw.json has transport: http"
else
  log_fail "openclaw.json missing transport: http"
fi

if echo "$CONFIG_FILE" | grep -q '"baseUrl".*"http://localhost:8400"'; then
  log_pass "openclaw.json has baseUrl: http://localhost:8400"
else
  log_fail "openclaw.json missing baseUrl: http://localhost:8400"
fi

# Test: no stale MCP references
if echo "$CONFIG_FILE" | grep -q '8401/mcp'; then
  log_fail "openclaw.json still has stale 8401/mcp reference"
else
  log_pass "No stale 8401/mcp references in config"
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
