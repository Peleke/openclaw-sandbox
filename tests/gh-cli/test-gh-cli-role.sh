#!/usr/bin/env bash
# GitHub CLI VM Deployment Tests
#
# Tests that the gh-cli role deploys correctly in the VM.
# Requires a running VM with the role applied.
#
# Usage:
#   ./tests/gh-cli/test-gh-cli-role.sh

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
echo "  GitHub CLI VM Deployment Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check VM is running
if ! limactl list --json 2>/dev/null | jq -e 'if type == "array" then .[] else . end | select(.name == "'"${VM_NAME}"'") | select(.status == "Running")' > /dev/null 2>&1; then
  echo -e "${YELLOW}VM '${VM_NAME}' is not running. Skipping deployment tests.${NC}"
  echo ""
  exit 0
fi

# ============================================================
# SECTION 1: gh Binary
# ============================================================
echo "▸ gh Binary"
echo ""

# Check gh is installed
if vm_exec which gh >/dev/null 2>&1; then
  log_pass "gh binary found"
else
  log_fail "gh binary not found"
fi

# Check gh version
GH_VERSION=$(vm_exec gh --version 2>/dev/null | head -1 || echo "")
if [[ -n "$GH_VERSION" ]]; then
  log_pass "gh version: $GH_VERSION"
else
  log_fail "Could not get gh version"
fi

echo ""

# ============================================================
# SECTION 2: APT Repository
# ============================================================
echo "▸ APT Repository"
echo ""

# Check apt source file
if vm_exec test -f /etc/apt/sources.list.d/github-cli.list 2>/dev/null; then
  log_pass "GitHub CLI apt source configured"
else
  log_fail "GitHub CLI apt source missing"
fi

# Check apt source content
if vm_exec grep -q "cli.github.com/packages" /etc/apt/sources.list.d/github-cli.list 2>/dev/null; then
  log_pass "Apt source points to cli.github.com"
else
  log_fail "Apt source should point to cli.github.com"
fi

# Check GPG key
if vm_exec test -f /etc/apt/keyrings/githubcli-archive-keyring.gpg 2>/dev/null; then
  log_pass "GitHub CLI GPG key installed"
else
  log_fail "GitHub CLI GPG key missing"
fi

echo ""

# ============================================================
# SECTION 3: gh Package
# ============================================================
echo "▸ gh Package"
echo ""

# Check gh package is installed via dpkg
if vm_exec dpkg -l gh 2>/dev/null | grep -q "^ii"; then
  log_pass "gh package installed (dpkg)"
else
  log_fail "gh package not installed"
fi

echo ""

# ============================================================
# SECTION 4: GH_TOKEN in Secrets
# ============================================================
echo "▸ GH_TOKEN Secrets Integration"
echo ""

# Check secrets.env file exists
if vm_exec sudo test -f /etc/openclaw/secrets.env 2>/dev/null; then
  log_pass "secrets.env file exists"

  # Check if GH_TOKEN line is present (if token was provided)
  if vm_exec sudo grep -q "^GH_TOKEN=" /etc/openclaw/secrets.env 2>/dev/null; then
    log_pass "GH_TOKEN present in secrets.env"

    # Check gh auth status (non-destructive, just verifies token)
    if vm_exec bash -c 'export $(sudo grep "^GH_TOKEN=" /etc/openclaw/secrets.env); gh auth status' 2>/dev/null; then
      log_pass "gh auth status succeeds (token is valid)"
    else
      log_skip "gh auth status failed (token may be expired or invalid)"
    fi
  else
    log_skip "GH_TOKEN not in secrets.env (no token provided — expected if no --secrets or -e)"
  fi
else
  log_skip "secrets.env not found"
fi

echo ""

# ============================================================
# SECTION 5: Sandbox Container gh
# ============================================================
echo "▸ Sandbox Container gh"
echo ""

# Check if sandbox image exists
if vm_exec sudo docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "openclaw-sandbox:bookworm-slim"; then
  # Check gh is in the sandbox image
  if vm_exec sudo docker run --rm openclaw-sandbox:bookworm-slim which gh 2>/dev/null; then
    log_pass "gh available in sandbox container"
  else
    log_fail "gh not found in sandbox container"
  fi
else
  log_skip "Sandbox image not found (cannot check container gh)"
fi

echo ""

# ============================================================
# SECTION 6: Sandbox Config (GH_TOKEN passthrough)
# ============================================================
echo "▸ Sandbox Config (openclaw.json)"
echo ""

USER_HOME=$(vm_exec bash -c 'echo $HOME' 2>/dev/null || echo "/home/$(vm_exec whoami 2>/dev/null)")

if vm_exec test -f "$USER_HOME/.openclaw/openclaw.json" 2>/dev/null; then
  SANDBOX_CONFIG=$(vm_exec cat "$USER_HOME/.openclaw/openclaw.json" 2>/dev/null || echo "{}")

  # Check if sandbox.env.GH_TOKEN exists (only if GH_TOKEN was provided)
  if vm_exec sudo grep -q "^GH_TOKEN=" /etc/openclaw/secrets.env 2>/dev/null; then
    if echo "$SANDBOX_CONFIG" | jq -e '.agents.defaults.sandbox.env.GH_TOKEN' >/dev/null 2>&1; then
      log_pass "openclaw.json has sandbox.env.GH_TOKEN passthrough"
    else
      log_fail "openclaw.json missing sandbox.env.GH_TOKEN passthrough"
    fi
  else
    log_skip "GH_TOKEN not in secrets (passthrough not expected)"
  fi
else
  log_skip "openclaw.json not found"
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
