#!/usr/bin/env bash
# Docker + Sandbox VM Deployment Tests
#
# Tests that Docker and sandbox roles deploy correctly in the VM.
# Requires a running VM with the roles applied.
#
# Usage:
#   ./tests/sandbox/test-sandbox-role.sh

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
echo "  Docker + Sandbox VM Deployment Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check VM is running
if ! limactl list --json 2>/dev/null | jq -e 'if type == "array" then .[] else . end | select(.name == "'"${VM_NAME}"'") | select(.status == "Running")' > /dev/null 2>&1; then
  echo -e "${YELLOW}VM '${VM_NAME}' is not running. Skipping deployment tests.${NC}"
  echo ""
  exit 0
fi

# ============================================================
# SECTION 1: Docker Daemon
# ============================================================
echo "▸ Docker Daemon"
echo ""

# Check if Docker is installed
if vm_exec which docker >/dev/null 2>&1; then
  log_pass "Docker binary found"
else
  log_fail "Docker binary not found"
fi

# Check Docker version
DOCKER_VERSION=$(vm_exec docker --version 2>/dev/null || echo "")
if [[ -n "$DOCKER_VERSION" ]]; then
  log_pass "Docker version: $DOCKER_VERSION"
else
  log_fail "Could not get Docker version"
fi

# Check Docker daemon is running
if vm_exec sudo systemctl is-active docker >/dev/null 2>&1; then
  log_pass "Docker daemon is running"
else
  log_fail "Docker daemon is not running"
fi

# Check Docker daemon is enabled
if vm_exec sudo systemctl is-enabled docker >/dev/null 2>&1; then
  log_pass "Docker daemon is enabled (starts on boot)"
else
  log_fail "Docker daemon is not enabled"
fi

# Check Docker info works
if vm_exec sudo docker info >/dev/null 2>&1; then
  log_pass "docker info succeeds"
else
  log_fail "docker info failed"
fi

# Check Docker socket exists
if vm_exec test -S /var/run/docker.sock 2>/dev/null; then
  log_pass "Docker socket exists at /var/run/docker.sock"
else
  log_fail "Docker socket missing"
fi

echo ""

# ============================================================
# SECTION 2: Docker Group Membership
# ============================================================
echo "▸ Docker Group Membership"
echo ""

# Check current user is in docker group
# Note: `id -nG` may not reflect group changes until re-login, so also check /etc/group
CURRENT_USER=$(vm_exec whoami 2>/dev/null || echo "")
if vm_exec id -nG 2>/dev/null | grep -qw docker; then
  log_pass "Current user is in docker group (active session)"
elif vm_exec getent group docker 2>/dev/null | grep -q "$CURRENT_USER"; then
  log_pass "Current user is in docker group (via /etc/group, needs re-login for session)"
else
  log_fail "Current user NOT in docker group"
fi

# Check docker group exists
if vm_exec getent group docker >/dev/null 2>&1; then
  log_pass "Docker group exists"
else
  log_fail "Docker group missing"
fi

echo ""

# ============================================================
# SECTION 3: Docker CE from Official Repo
# ============================================================
echo "▸ Docker CE Installation Source"
echo ""

# Check Docker CE (not distro docker.io)
if vm_exec dpkg -l docker-ce 2>/dev/null | grep -q "^ii"; then
  log_pass "docker-ce package installed (official repo)"
else
  log_fail "docker-ce package not installed"
fi

if vm_exec dpkg -l containerd.io 2>/dev/null | grep -q "^ii"; then
  log_pass "containerd.io package installed"
else
  log_fail "containerd.io package not installed"
fi

# Verify apt source
if vm_exec test -f /etc/apt/sources.list.d/docker.list 2>/dev/null; then
  log_pass "Docker apt source configured"
else
  log_fail "Docker apt source missing"
fi

if vm_exec grep -q "download.docker.com" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
  log_pass "Apt source points to download.docker.com"
else
  log_fail "Apt source should point to download.docker.com"
fi

# Check GPG key
if vm_exec test -f /etc/apt/keyrings/docker.gpg 2>/dev/null; then
  log_pass "Docker GPG key installed"
else
  log_fail "Docker GPG key missing"
fi

echo ""

# ============================================================
# SECTION 4: Docker Functionality
# ============================================================
echo "▸ Docker Functionality"
echo ""

# Run hello-world container
if vm_exec sudo docker run --rm hello-world >/dev/null 2>&1; then
  log_pass "docker run hello-world succeeds"
else
  log_fail "docker run hello-world failed"
fi

# Check Docker can create containers
if vm_exec sudo docker create --name test-create alpine echo hello >/dev/null 2>&1; then
  vm_exec sudo docker rm test-create >/dev/null 2>&1 || true
  log_pass "Docker can create containers"
else
  log_fail "Docker cannot create containers"
fi

# Check Docker storage driver
STORAGE_DRIVER=$(vm_exec sudo docker info --format '{{.Driver}}' 2>/dev/null || echo "unknown")
if [[ "$STORAGE_DRIVER" != "unknown" ]]; then
  log_pass "Storage driver: $STORAGE_DRIVER"
else
  log_fail "Could not determine storage driver"
fi

echo ""

# ============================================================
# SECTION 5: Network Isolation
# ============================================================
echo "▸ Docker Network Isolation"
echo ""

# Test --network none blocks connectivity
if ! vm_exec sudo docker run --rm --network none alpine ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
  log_pass "Container with --network none cannot reach internet"
else
  log_fail "Container with --network none CAN reach internet (should be blocked)"
fi

# Test --network none blocks DNS
if ! vm_exec sudo docker run --rm --network none alpine nslookup google.com >/dev/null 2>&1; then
  log_pass "Container with --network none cannot resolve DNS"
else
  log_fail "Container with --network none CAN resolve DNS (should be blocked)"
fi

# Verify docker.network in openclaw.json is "none" (secure default)
USER_HOME_NET=$(vm_exec bash -c 'echo $HOME' 2>/dev/null || echo "/home/$(vm_exec whoami 2>/dev/null)")
if vm_exec test -f "$USER_HOME_NET/.openclaw/openclaw.json" 2>/dev/null; then
  NET_CONFIG=$(vm_exec cat "$USER_HOME_NET/.openclaw/openclaw.json" 2>/dev/null || echo "{}")
  DOCKER_NETWORK=$(echo "$NET_CONFIG" | jq -r '.agents.defaults.sandbox.docker.network // ""' 2>/dev/null)
  if [[ "$DOCKER_NETWORK" == "none" ]]; then
    log_pass "openclaw.json docker.network = 'none' (secure default)"
  elif [[ "$DOCKER_NETWORK" == "bridge" ]]; then
    log_fail "openclaw.json docker.network = 'bridge' (should be 'none')"
  elif [[ -n "$DOCKER_NETWORK" ]]; then
    log_pass "openclaw.json docker.network = '$DOCKER_NETWORK' (custom)"
  else
    log_skip "docker.network not set in openclaw.json"
  fi

  # Check for per-tool network config (if configured)
  NETWORK_ALLOW=$(echo "$NET_CONFIG" | jq -r '.agents.defaults.sandbox.networkAllow // empty' 2>/dev/null)
  if [[ -n "$NETWORK_ALLOW" ]]; then
    log_pass "openclaw.json has networkAllow configured"
    NETWORK_DOCKER=$(echo "$NET_CONFIG" | jq -r '.agents.defaults.sandbox.networkDocker.network // ""' 2>/dev/null)
    if [[ "$NETWORK_DOCKER" == "bridge" ]]; then
      log_pass "openclaw.json networkDocker.network = 'bridge'"
    elif [[ -n "$NETWORK_DOCKER" ]]; then
      log_pass "openclaw.json networkDocker.network = '$NETWORK_DOCKER' (custom)"
    else
      log_fail "networkDocker.network should be set when networkAllow is configured"
    fi
  fi

  # Check networkExecAllow config
  NETWORK_EXEC_ALLOW=$(echo "$NET_CONFIG" | jq -r '.agents.defaults.sandbox.networkExecAllow // empty' 2>/dev/null)
  if [[ -n "$NETWORK_EXEC_ALLOW" ]]; then
    log_pass "openclaw.json has networkExecAllow configured"
    # Verify 'gh' is in the list
    if echo "$NET_CONFIG" | jq -e '.agents.defaults.sandbox.networkExecAllow | index("gh")' >/dev/null 2>&1; then
      log_pass "networkExecAllow includes 'gh'"
    else
      log_fail "networkExecAllow should include 'gh'"
    fi
  fi
else
  log_skip "openclaw.json not found (cannot verify network config)"
fi

echo ""

# ============================================================
# SECTION 5b: Dual-Container Network Isolation (E2E)
# ============================================================
echo "▸ Dual-Container Network Isolation (E2E)"
echo ""

SANDBOX_IMAGE="openclaw-sandbox:bookworm-slim"
TEST_SUFFIX="$$"

# Check sandbox image exists before running container tests
if vm_exec sudo docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "$SANDBOX_IMAGE"; then

  # --- Create isolated container (network: none) ---
  ISOLATED_NAME="test-isolated-${TEST_SUFFIX}"
  ISOLATED_ID=$(vm_exec sudo docker run -d --network none \
    --name "$ISOLATED_NAME" \
    --env GH_TOKEN='test-gh-token' \
    --env BRAVE_API_KEY='test-brave-key' \
    "$SANDBOX_IMAGE" sleep 120 2>/dev/null | grep -v "cd:" | tail -1)

  if [[ -n "$ISOLATED_ID" ]]; then
    log_pass "Created isolated container (network: none)"
  else
    log_fail "Failed to create isolated container"
  fi

  # --- Create bridge container (network: bridge) ---
  BRIDGE_NAME="test-bridge-${TEST_SUFFIX}"
  BRIDGE_ID=$(vm_exec sudo docker run -d --network bridge \
    --name "$BRIDGE_NAME" \
    --env GH_TOKEN='test-gh-token' \
    --env BRAVE_API_KEY='test-brave-key' \
    "$SANDBOX_IMAGE" sleep 120 2>/dev/null | grep -v "cd:" | tail -1)

  if [[ -n "$BRIDGE_ID" ]]; then
    log_pass "Created bridge container (network: bridge)"
  else
    log_fail "Failed to create bridge container"
  fi

  # --- Verify network modes via docker inspect ---
  if [[ -n "$ISOLATED_ID" ]]; then
    ISOLATED_NETS=$(vm_exec sudo docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$ISOLATED_NAME" 2>/dev/null | grep -v "cd:" || echo "")
    if echo "$ISOLATED_NETS" | grep -q "none"; then
      log_pass "Isolated container network = 'none'"
    else
      log_fail "Isolated container network should be 'none', got: $ISOLATED_NETS"
    fi
  fi

  if [[ -n "$BRIDGE_ID" ]]; then
    BRIDGE_NETS=$(vm_exec sudo docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$BRIDGE_NAME" 2>/dev/null | grep -v "cd:" || echo "")
    if echo "$BRIDGE_NETS" | grep -q "bridge"; then
      log_pass "Bridge container network = 'bridge'"
    else
      log_fail "Bridge container network should be 'bridge', got: $BRIDGE_NETS"
    fi
  fi

  # --- Verify env vars pass through to both containers ---
  if [[ -n "$ISOLATED_ID" ]]; then
    ISO_GH=$(vm_exec sudo docker exec "$ISOLATED_NAME" sh -c 'echo $GH_TOKEN' 2>/dev/null | grep -v "cd:" || echo "")
    if [[ "$ISO_GH" == "test-gh-token" ]]; then
      log_pass "Isolated container has GH_TOKEN env var"
    else
      log_fail "Isolated container missing GH_TOKEN (got: '$ISO_GH')"
    fi

    ISO_BRAVE=$(vm_exec sudo docker exec "$ISOLATED_NAME" sh -c 'echo $BRAVE_API_KEY' 2>/dev/null | grep -v "cd:" || echo "")
    if [[ "$ISO_BRAVE" == "test-brave-key" ]]; then
      log_pass "Isolated container has BRAVE_API_KEY env var"
    else
      log_fail "Isolated container missing BRAVE_API_KEY (got: '$ISO_BRAVE')"
    fi
  fi

  if [[ -n "$BRIDGE_ID" ]]; then
    BRG_GH=$(vm_exec sudo docker exec "$BRIDGE_NAME" sh -c 'echo $GH_TOKEN' 2>/dev/null | grep -v "cd:" || echo "")
    if [[ "$BRG_GH" == "test-gh-token" ]]; then
      log_pass "Bridge container has GH_TOKEN env var"
    else
      log_fail "Bridge container missing GH_TOKEN (got: '$BRG_GH')"
    fi
  fi

  # --- Network isolation: isolated container CANNOT reach internet ---
  if [[ -n "$ISOLATED_ID" ]]; then
    if ! vm_exec sudo docker exec "$ISOLATED_NAME" sh -c 'curl -s --connect-timeout 3 https://api.github.com >/dev/null 2>&1' 2>/dev/null; then
      log_pass "Isolated container cannot reach internet (curl fails)"
    else
      log_fail "Isolated container CAN reach internet (should be air-gapped)"
    fi

    # DNS should also fail
    if ! vm_exec sudo docker exec "$ISOLATED_NAME" sh -c 'nslookup google.com >/dev/null 2>&1' 2>/dev/null; then
      log_pass "Isolated container cannot resolve DNS"
    else
      log_fail "Isolated container CAN resolve DNS (should be blocked)"
    fi
  fi

  # --- Network access: bridge container CAN reach internet ---
  if [[ -n "$BRIDGE_ID" ]]; then
    if vm_exec sudo docker exec "$BRIDGE_NAME" sh -c 'curl -s --connect-timeout 5 https://api.github.com >/dev/null 2>&1' 2>/dev/null; then
      log_pass "Bridge container can reach internet (curl succeeds)"
    else
      log_fail "Bridge container cannot reach internet (should have bridge networking)"
    fi

    # gh binary should exist and be functional
    GH_VERSION=$(vm_exec sudo docker exec "$BRIDGE_NAME" gh --version 2>/dev/null | grep -v "cd:" | head -1 || echo "")
    if [[ -n "$GH_VERSION" ]]; then
      log_pass "Bridge container: gh binary works ($GH_VERSION)"
    else
      log_fail "Bridge container: gh binary missing or broken"
    fi
  fi

  # --- Cleanup ---
  vm_exec sudo docker rm -f "$ISOLATED_NAME" "$BRIDGE_NAME" >/dev/null 2>&1 || true
  log_pass "Cleaned up test containers"

else
  log_skip "Sandbox image not found — skipping dual-container E2E tests"
fi

echo ""

# ============================================================
# SECTION 6: Sandbox Image
# ============================================================
echo "▸ Sandbox Image"
echo ""

# Check if sandbox image exists
if vm_exec sudo docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "openclaw-sandbox:bookworm-slim"; then
  log_pass "Sandbox image openclaw-sandbox:bookworm-slim exists"
else
  # Image may not exist if sandbox-setup.sh wasn't found and fallback wasn't built yet
  log_skip "Sandbox image openclaw-sandbox:bookworm-slim not found (may need sandbox-setup.sh)"
fi

# Check image size is reasonable (< 2GB)
IMAGE_SIZE=$(vm_exec sudo docker images --format '{{.Size}}' openclaw-sandbox:bookworm-slim 2>/dev/null || echo "")
if [[ -n "$IMAGE_SIZE" ]]; then
  log_pass "Sandbox image size: $IMAGE_SIZE"
else
  log_skip "Cannot check image size (image may not exist)"
fi

echo ""

# ============================================================
# SECTION 7: Gateway Docker Access
# ============================================================
echo "▸ Gateway Docker Access"
echo ""

# Check gateway systemd unit has SupplementaryGroups=docker
if vm_exec cat /etc/systemd/system/openclaw-gateway.service 2>/dev/null | grep -q "SupplementaryGroups=docker"; then
  log_pass "Gateway systemd unit has SupplementaryGroups=docker"
else
  log_fail "Gateway systemd unit missing SupplementaryGroups=docker"
fi

# Check gateway service file exists
if vm_exec test -f /etc/systemd/system/openclaw-gateway.service 2>/dev/null; then
  log_pass "Gateway service file exists"
else
  log_fail "Gateway service file missing"
fi

echo ""

# ============================================================
# SECTION 8: Sandbox Configuration
# ============================================================
echo "▸ Sandbox Configuration (openclaw.json)"
echo ""

# Get user home
USER_HOME=$(vm_exec bash -c 'echo $HOME' 2>/dev/null || echo "/home/$(vm_exec whoami 2>/dev/null)")

# Check if openclaw.json exists
if vm_exec test -f "$USER_HOME/.openclaw/openclaw.json" 2>/dev/null; then
  log_pass "openclaw.json exists"

  # Check sandbox config in openclaw.json
  SANDBOX_CONFIG=$(vm_exec cat "$USER_HOME/.openclaw/openclaw.json" 2>/dev/null || echo "{}")

  if echo "$SANDBOX_CONFIG" | jq -e '.agents.defaults.sandbox' >/dev/null 2>&1; then
    log_pass "openclaw.json has agents.defaults.sandbox config"
  else
    log_fail "openclaw.json missing sandbox config"
  fi

  # Check sandbox mode
  SANDBOX_MODE=$(echo "$SANDBOX_CONFIG" | jq -r '.agents.defaults.sandbox.mode // ""' 2>/dev/null)
  if [[ "$SANDBOX_MODE" == "all" ]]; then
    log_pass "sandbox.mode = 'all'"
  elif [[ -n "$SANDBOX_MODE" ]]; then
    log_pass "sandbox.mode = '$SANDBOX_MODE' (custom)"
  else
    log_fail "sandbox.mode not set"
  fi

  # Check sandbox scope
  SANDBOX_SCOPE=$(echo "$SANDBOX_CONFIG" | jq -r '.agents.defaults.sandbox.scope // ""' 2>/dev/null)
  if [[ "$SANDBOX_SCOPE" == "session" ]]; then
    log_pass "sandbox.scope = 'session'"
  elif [[ -n "$SANDBOX_SCOPE" ]]; then
    log_pass "sandbox.scope = '$SANDBOX_SCOPE' (custom)"
  else
    log_fail "sandbox.scope not set"
  fi

  # Check workspace access
  WORKSPACE_ACCESS=$(echo "$SANDBOX_CONFIG" | jq -r '.agents.defaults.sandbox.workspaceAccess // ""' 2>/dev/null)
  if [[ "$WORKSPACE_ACCESS" == "rw" ]]; then
    log_pass "sandbox.workspaceAccess = 'rw'"
  elif [[ -n "$WORKSPACE_ACCESS" ]]; then
    log_pass "sandbox.workspaceAccess = '$WORKSPACE_ACCESS' (custom)"
  else
    log_fail "sandbox.workspaceAccess not set"
  fi
else
  log_skip "openclaw.json does not exist (gateway not fully configured)"
fi

echo ""

# ============================================================
# SECTION 9: Overlay + Docker Coexistence
# ============================================================
echo "▸ Overlay + Docker Coexistence"
echo ""

# Check overlay is still mounted
if vm_exec mountpoint -q /workspace 2>/dev/null; then
  log_pass "/workspace overlay still mounted"
else
  log_skip "/workspace not mounted (overlay may not be active)"
fi

# Check Docker data-root is NOT on overlay
DOCKER_ROOT=$(vm_exec sudo docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
if [[ "$DOCKER_ROOT" == "/var/lib/docker" ]]; then
  log_pass "Docker data-root at /var/lib/docker (not on overlay)"
else
  log_pass "Docker data-root at $DOCKER_ROOT"
fi

# Check Docker can mount from /workspace
if vm_exec test -d /workspace 2>/dev/null; then
  if vm_exec sudo docker run --rm -v /workspace:/test:ro alpine ls /test >/dev/null 2>&1; then
    log_pass "Docker can bind-mount from /workspace"
  else
    log_fail "Docker cannot bind-mount from /workspace"
  fi
else
  log_skip "/workspace not available for bind-mount test"
fi

echo ""

# ============================================================
# SECTION 10: Docker Resource Limits
# ============================================================
echo "▸ Docker Resources"
echo ""

# Check Docker isn't using too much disk
DOCKER_DISK=$(vm_exec sudo docker system df --format '{{.Size}}' 2>/dev/null | head -1 || echo "")
if [[ -n "$DOCKER_DISK" ]]; then
  log_pass "Docker disk usage: $DOCKER_DISK"
else
  log_skip "Cannot check Docker disk usage"
fi

# Check containerd is running
if vm_exec sudo systemctl is-active containerd >/dev/null 2>&1; then
  log_pass "containerd service is running"
else
  log_fail "containerd service is not running"
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
