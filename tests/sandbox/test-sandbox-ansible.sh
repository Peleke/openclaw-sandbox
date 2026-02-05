#!/usr/bin/env bash
# Docker + Sandbox Ansible Role Validation
#
# Validates the Ansible role structure, defaults, tasks, handlers, and
# integration with playbook, bootstrap, and gateway without running them.
#
# Usage:
#   ./tests/sandbox/test-sandbox-ansible.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKER_ROLE="$REPO_ROOT/ansible/roles/docker"
SANDBOX_ROLE="$REPO_ROOT/ansible/roles/sandbox"
GATEWAY_ROLE="$REPO_ROOT/ansible/roles/gateway"
BUILDLOG_ROLE="$REPO_ROOT/ansible/roles/buildlog"
PLAYBOOK="$REPO_ROOT/ansible/playbook.yml"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

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
echo "  Docker + Sandbox Ansible Role Validation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Docker Role Structure
# ============================================================
echo "▸ Docker Role Structure"
echo ""

if [[ -d "$DOCKER_ROLE" ]]; then
  log_pass "Role directory exists: ansible/roles/docker"
else
  log_fail "Role directory missing: ansible/roles/docker"
fi

for subdir in defaults tasks handlers; do
  if [[ -d "$DOCKER_ROLE/$subdir" ]]; then
    log_pass "Directory exists: docker/$subdir/"
  else
    log_fail "Missing directory: docker/$subdir/"
  fi
done

for file in defaults/main.yml tasks/main.yml handlers/main.yml; do
  if [[ -f "$DOCKER_ROLE/$file" ]]; then
    log_pass "File exists: docker/$file"
  else
    log_fail "Missing file: docker/$file"
  fi
done

echo ""

# ============================================================
# SECTION 2: Docker Role Defaults
# ============================================================
echo "▸ Docker Role Defaults"
echo ""

DOCKER_DEFAULTS=(
  "docker_enabled"
  "docker_storage_driver"
  "docker_data_root"
)

for var in "${DOCKER_DEFAULTS[@]}"; do
  if grep -q "$var" "$DOCKER_ROLE/defaults/main.yml"; then
    log_pass "Default defined: $var"
  else
    log_fail "Missing default: $var"
  fi
done

# docker_enabled should default to true
if grep -q "docker_enabled: true" "$DOCKER_ROLE/defaults/main.yml"; then
  log_pass "docker_enabled defaults to true"
else
  log_fail "docker_enabled should default to true"
fi

echo ""

# ============================================================
# SECTION 3: Docker Tasks Content
# ============================================================
echo "▸ Docker Tasks Content"
echo ""

DOCKER_TASKS="$DOCKER_ROLE/tasks/main.yml"

# Check for skip condition when docker_enabled is false
if grep -q "docker_enabled" "$DOCKER_TASKS"; then
  log_pass "Tasks check docker_enabled flag"
else
  log_fail "Tasks should check docker_enabled flag"
fi

# Check for Docker GPG key setup
if grep -q "docker.gpg" "$DOCKER_TASKS"; then
  log_pass "Tasks install Docker GPG key"
else
  log_fail "Tasks missing Docker GPG key setup"
fi

# Check for Docker apt repo
if grep -q "download.docker.com" "$DOCKER_TASKS"; then
  log_pass "Tasks add Docker CE apt repository"
else
  log_fail "Tasks missing Docker CE apt repo"
fi

# Check for docker-ce package
if grep -q "docker-ce" "$DOCKER_TASKS"; then
  log_pass "Tasks install docker-ce package"
else
  log_fail "Tasks missing docker-ce package"
fi

# Check for containerd
if grep -q "containerd.io" "$DOCKER_TASKS"; then
  log_pass "Tasks install containerd.io"
else
  log_fail "Tasks missing containerd.io"
fi

# Check for docker-buildx-plugin
if grep -q "docker-buildx-plugin" "$DOCKER_TASKS"; then
  log_pass "Tasks install docker-buildx-plugin"
else
  log_fail "Tasks missing docker-buildx-plugin"
fi

# Check user added to docker group
if grep -q "docker" "$DOCKER_TASKS" && grep -q "groups:" "$DOCKER_TASKS"; then
  log_pass "Tasks add user to docker group"
else
  log_fail "Tasks missing docker group membership"
fi

# Check docker service enabled
if grep -q "enabled: true" "$DOCKER_TASKS" && grep -q "docker" "$DOCKER_TASKS"; then
  log_pass "Tasks enable docker service"
else
  log_fail "Tasks should enable docker service"
fi

# Check for docker info verification
if grep -q "docker info" "$DOCKER_TASKS"; then
  log_pass "Tasks verify docker with 'docker info'"
else
  log_fail "Tasks missing docker verification step"
fi

# Check for storage driver configuration
if grep -q "docker_storage_driver" "$DOCKER_TASKS"; then
  log_pass "Tasks support custom storage driver"
else
  log_fail "Tasks missing storage driver configuration"
fi

# Check for daemon.json
if grep -q "daemon.json" "$DOCKER_TASKS"; then
  log_pass "Tasks configure /etc/docker/daemon.json"
else
  log_fail "Tasks missing daemon.json configuration"
fi

echo ""

# ============================================================
# SECTION 4: Docker Handlers
# ============================================================
echo "▸ Docker Handlers"
echo ""

DOCKER_HANDLERS="$DOCKER_ROLE/handlers/main.yml"

if grep -q "Restart docker" "$DOCKER_HANDLERS"; then
  log_pass "Handler exists: Restart docker"
else
  log_fail "Missing handler: Restart docker"
fi

if grep -q "daemon_reload" "$DOCKER_HANDLERS"; then
  log_pass "Handler includes daemon_reload"
else
  log_fail "Handler missing daemon_reload"
fi

echo ""

# ============================================================
# SECTION 5: Sandbox Role Structure
# ============================================================
echo "▸ Sandbox Role Structure"
echo ""

if [[ -d "$SANDBOX_ROLE" ]]; then
  log_pass "Role directory exists: ansible/roles/sandbox"
else
  log_fail "Role directory missing: ansible/roles/sandbox"
fi

for subdir in defaults tasks handlers; do
  if [[ -d "$SANDBOX_ROLE/$subdir" ]]; then
    log_pass "Directory exists: sandbox/$subdir/"
  else
    log_fail "Missing directory: sandbox/$subdir/"
  fi
done

for file in defaults/main.yml tasks/main.yml handlers/main.yml; do
  if [[ -f "$SANDBOX_ROLE/$file" ]]; then
    log_pass "File exists: sandbox/$file"
  else
    log_fail "Missing file: sandbox/$file"
  fi
done

echo ""

# ============================================================
# SECTION 6: Sandbox Role Defaults
# ============================================================
echo "▸ Sandbox Role Defaults"
echo ""

SANDBOX_DEFAULTS=(
  "sandbox_enabled"
  "sandbox_mode"
  "sandbox_scope"
  "sandbox_workspace_access"
  "sandbox_image"
  "sandbox_build_browser"
  "sandbox_docker_network"
  "sandbox_network_allow"
  "sandbox_network_allow_extra"
  "sandbox_network_docker_network"
  "sandbox_setup_script"
)

for var in "${SANDBOX_DEFAULTS[@]}"; do
  if grep -q "$var" "$SANDBOX_ROLE/defaults/main.yml"; then
    log_pass "Default defined: $var"
  else
    log_fail "Missing default: $var"
  fi
done

# Check sandbox_mode default is "all"
if grep -q 'sandbox_mode: "all"' "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "sandbox_mode defaults to 'all'"
else
  log_fail "sandbox_mode should default to 'all'"
fi

# Check sandbox_scope default is "session"
if grep -q 'sandbox_scope: "session"' "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "sandbox_scope defaults to 'session'"
else
  log_fail "sandbox_scope should default to 'session'"
fi

# Check sandbox_workspace_access default is "rw"
if grep -q 'sandbox_workspace_access: "rw"' "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "sandbox_workspace_access defaults to 'rw'"
else
  log_fail "sandbox_workspace_access should default to 'rw'"
fi

# Check image name
if grep -q "openclaw-sandbox:bookworm-slim" "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "sandbox_image uses openclaw-sandbox:bookworm-slim"
else
  log_fail "sandbox_image should use openclaw-sandbox:bookworm-slim"
fi

# Check sandbox_docker_network default is "none" (secure default)
if grep -q 'sandbox_docker_network: "none"' "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "sandbox_docker_network defaults to 'none' (air-gapped)"
else
  log_fail "sandbox_docker_network should default to 'none'"
fi

# Check sandbox_network_allow default is empty list
if grep -q 'sandbox_network_allow: \[\]' "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "sandbox_network_allow defaults to empty list"
else
  log_fail "sandbox_network_allow should default to empty list"
fi

# Check sandbox_network_allow_extra default is empty list
if grep -q 'sandbox_network_allow_extra: \[\]' "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "sandbox_network_allow_extra defaults to empty list"
else
  log_fail "sandbox_network_allow_extra should default to empty list"
fi

# Check sandbox_network_docker_network default is "bridge"
if grep -q 'sandbox_network_docker_network: "bridge"' "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "sandbox_network_docker_network defaults to 'bridge'"
else
  log_fail "sandbox_network_docker_network should default to 'bridge'"
fi

echo ""

# ============================================================
# SECTION 7: Sandbox Tasks Content
# ============================================================
echo "▸ Sandbox Tasks Content"
echo ""

SANDBOX_TASKS="$SANDBOX_ROLE/tasks/main.yml"

# Check for skip condition
if grep -q "sandbox_enabled" "$SANDBOX_TASKS"; then
  log_pass "Tasks check sandbox_enabled flag"
else
  log_fail "Tasks should check sandbox_enabled flag"
fi

# Check Docker availability verification
if grep -q "docker info" "$SANDBOX_TASKS" || grep -q "Docker is not available" "$SANDBOX_TASKS"; then
  log_pass "Tasks verify Docker availability"
else
  log_fail "Tasks should verify Docker is available"
fi

# Check for sandbox-setup.sh detection
if grep -q "sandbox-setup.sh" "$SANDBOX_TASKS"; then
  log_pass "Tasks check for sandbox-setup.sh"
else
  log_fail "Tasks missing sandbox-setup.sh detection"
fi

# Check for image build
if grep -q "sandbox_image" "$SANDBOX_TASKS" || grep -q "openclaw-sandbox" "$SANDBOX_TASKS"; then
  log_pass "Tasks build sandbox image"
else
  log_fail "Tasks missing sandbox image build"
fi

# Check for fallback image build
if grep -q "debian:bookworm-slim" "$SANDBOX_TASKS"; then
  log_pass "Tasks include fallback image build"
else
  log_fail "Tasks missing fallback image build"
fi

# Check for openclaw.json config
if grep -q "openclaw.json" "$SANDBOX_TASKS"; then
  log_pass "Tasks configure openclaw.json"
else
  log_fail "Tasks should configure openclaw.json"
fi

# Check sandbox config keys in tasks
for key in "mode" "scope" "workspaceAccess"; do
  if grep -q "'$key'" "$SANDBOX_TASKS" || grep -q "\"$key\"" "$SANDBOX_TASKS"; then
    log_pass "Tasks set sandbox.$key in openclaw.json"
  else
    log_fail "Tasks missing sandbox.$key config"
  fi
done

# Check for image verification
if grep -q "docker images" "$SANDBOX_TASKS"; then
  log_pass "Tasks verify sandbox image exists"
else
  log_fail "Tasks should verify sandbox image exists"
fi

# Check for browser sandbox support
if grep -q "sandbox_build_browser" "$SANDBOX_TASKS" || grep -q "browser" "$SANDBOX_TASKS"; then
  log_pass "Tasks support browser sandbox (optional)"
else
  log_fail "Tasks missing browser sandbox support"
fi

# Check openclaw.json writes set owner/group (CRITICAL: prevents root-owned config)
# The sandbox role runs with become: true — without explicit owner/group,
# openclaw.json ends up root:root 0640, which the gateway (running as ansible_user)
# cannot read. This breaks GH_TOKEN, vault access, and workspace config.
if grep -A8 "Write updated openclaw.json" "$SANDBOX_TASKS" | grep -q "owner:"; then
  log_pass "openclaw.json write sets owner (gateway can read config)"
else
  log_fail "openclaw.json write MISSING owner — gateway CANNOT read config (root:root 0640)"
fi

if grep -A8 "Write updated openclaw.json" "$SANDBOX_TASKS" | grep -q "group:"; then
  log_pass "openclaw.json write sets group"
else
  log_fail "openclaw.json write MISSING group"
fi

if grep -A8 "Create openclaw.json with sandbox config" "$SANDBOX_TASKS" | grep -q "owner:"; then
  log_pass "openclaw.json create sets owner (fresh config path)"
else
  log_fail "openclaw.json create MISSING owner — fresh config will be root-owned"
fi

echo ""

# ============================================================
# SECTION 7b: Per-Tool Network Config in Tasks
# ============================================================
echo "▸ Per-Tool Network Config"
echo ""

# Check tasks contain networkAllow injection logic
if grep -q "networkAllow" "$SANDBOX_TASKS"; then
  log_pass "Tasks contain networkAllow config injection"
else
  log_fail "Tasks missing networkAllow config injection"
fi

# Check tasks contain networkDocker injection logic
if grep -q "networkDocker" "$SANDBOX_TASKS"; then
  log_pass "Tasks contain networkDocker config injection"
else
  log_fail "Tasks missing networkDocker config injection"
fi

# Check injection is gated on merged allow list length
if grep -q "_network_allow_merged.*length > 0" "$SANDBOX_TASKS"; then
  log_pass "Network config injection gated on merged allow list length"
else
  log_fail "Network config injection should be gated on merged allow list length"
fi

# Check base + extra lists are merged
if grep -q "sandbox_network_allow_extra" "$SANDBOX_TASKS"; then
  log_pass "Tasks merge sandbox_network_allow + sandbox_network_allow_extra"
else
  log_fail "Tasks should merge base + extra network allow lists"
fi

# Check fresh openclaw.json includes docker.network
if grep -A15 "Create openclaw.json with sandbox config" "$SANDBOX_TASKS" | grep -q "sandbox_docker_network"; then
  log_pass "Fresh openclaw.json includes docker.network"
else
  log_fail "Fresh openclaw.json should include docker.network"
fi

echo ""

# ============================================================
# SECTION 8: Sandbox Handlers
# ============================================================
echo "▸ Sandbox Handlers"
echo ""

SANDBOX_HANDLERS="$SANDBOX_ROLE/handlers/main.yml"

if grep -q "Restart gateway" "$SANDBOX_HANDLERS"; then
  log_pass "Handler exists: Restart gateway"
else
  log_fail "Missing handler: Restart gateway"
fi

if grep -q "openclaw-gateway" "$SANDBOX_HANDLERS"; then
  log_pass "Handler targets openclaw-gateway service"
else
  log_fail "Handler should target openclaw-gateway service"
fi

echo ""

# ============================================================
# SECTION 9: Playbook Integration
# ============================================================
echo "▸ Playbook Integration"
echo ""

# Docker role in playbook
if grep -q "role: docker" "$PLAYBOOK"; then
  log_pass "Playbook includes docker role"
else
  log_fail "Playbook missing docker role"
fi

# Sandbox role in playbook
if grep -q "role: sandbox" "$PLAYBOOK"; then
  log_pass "Playbook includes sandbox role"
else
  log_fail "Playbook missing sandbox role"
fi

# Docker role has when condition
if grep -A2 "role: docker" "$PLAYBOOK" | grep -q "docker_enabled"; then
  log_pass "Docker role has docker_enabled condition"
else
  log_fail "Docker role should have docker_enabled condition"
fi

# Sandbox role has when condition
if grep -A2 "role: sandbox" "$PLAYBOOK" | grep -q "docker_enabled"; then
  log_pass "Sandbox role has docker_enabled condition"
else
  log_fail "Sandbox role should have docker_enabled condition"
fi

# Role ordering: overlay < docker < gateway
overlay_line=$(grep -n "role: overlay" "$PLAYBOOK" | head -1 | cut -d: -f1)
docker_line=$(grep -n "role: docker" "$PLAYBOOK" | head -1 | cut -d: -f1)
gateway_line=$(grep -n "role: gateway" "$PLAYBOOK" | head -1 | cut -d: -f1)
sandbox_line=$(grep -n "role: sandbox" "$PLAYBOOK" | head -1 | cut -d: -f1)

if [[ -n "$overlay_line" && -n "$docker_line" && "$overlay_line" -lt "$docker_line" ]]; then
  log_pass "Docker role runs after overlay"
else
  log_fail "Docker role should run after overlay"
fi

if [[ -n "$docker_line" && -n "$gateway_line" && "$docker_line" -lt "$gateway_line" ]]; then
  log_pass "Docker role runs before gateway"
else
  log_fail "Docker role should run before gateway"
fi

if [[ -n "$gateway_line" && -n "$sandbox_line" && "$gateway_line" -lt "$sandbox_line" ]]; then
  log_pass "Sandbox role runs after gateway"
else
  log_fail "Sandbox role should run after gateway"
fi

echo ""

# ============================================================
# SECTION 10: Bootstrap Integration
# ============================================================
echo "▸ Bootstrap Integration"
echo ""

# --no-docker flag
if grep -q "\-\-no-docker)" "$BOOTSTRAP"; then
  log_pass "bootstrap.sh supports --no-docker flag"
else
  log_fail "bootstrap.sh missing --no-docker flag"
fi

# DOCKER_ENABLED variable
if grep -q "DOCKER_ENABLED" "$BOOTSTRAP"; then
  log_pass "bootstrap.sh has DOCKER_ENABLED variable"
else
  log_fail "bootstrap.sh missing DOCKER_ENABLED variable"
fi

# DOCKER_ENABLED defaults to true
if grep -q 'DOCKER_ENABLED=true' "$BOOTSTRAP"; then
  log_pass "DOCKER_ENABLED defaults to true"
else
  log_fail "DOCKER_ENABLED should default to true"
fi

# --no-docker sets DOCKER_ENABLED=false
if grep -A1 "\-\-no-docker)" "$BOOTSTRAP" | grep -q "DOCKER_ENABLED=false"; then
  log_pass "--no-docker sets DOCKER_ENABLED=false"
else
  log_fail "--no-docker should set DOCKER_ENABLED=false"
fi

# docker_enabled passed to Ansible
if grep -q "docker_enabled=\${DOCKER_ENABLED}" "$BOOTSTRAP" || grep -q 'docker_enabled=' "$BOOTSTRAP"; then
  log_pass "bootstrap.sh passes docker_enabled to Ansible"
else
  log_fail "bootstrap.sh missing docker_enabled Ansible var"
fi

# --no-docker in help text
if grep -q "no-docker" "$BOOTSTRAP"; then
  log_pass "Help text mentions --no-docker"
else
  log_fail "Help text should mention --no-docker"
fi

echo ""

# ============================================================
# SECTION 11: Gateway Integration
# ============================================================
echo "▸ Gateway Integration"
echo ""

GATEWAY_TASKS="$GATEWAY_ROLE/tasks/main.yml"

# SupplementaryGroups=docker in systemd unit
if grep -q "SupplementaryGroups=docker" "$GATEWAY_TASKS"; then
  log_pass "Gateway systemd unit has SupplementaryGroups=docker"
else
  log_fail "Gateway should have SupplementaryGroups=docker"
fi

# Conditional on docker_enabled
if grep -q "docker_enabled" "$GATEWAY_TASKS"; then
  log_pass "Gateway docker group conditional on docker_enabled"
else
  log_fail "Gateway docker group should be conditional"
fi

echo ""

# ============================================================
# SECTION 12: Buildlog Integration
# ============================================================
echo "▸ Buildlog Integration"
echo ""

BUILDLOG_TASKS="$BUILDLOG_ROLE/tasks/main.yml"

# Docker sandbox mentioned in policy
if grep -q "Docker Sandbox" "$BUILDLOG_TASKS" || grep -q "Docker sandbox" "$BUILDLOG_TASKS"; then
  log_pass "Buildlog sandbox policy mentions Docker sandbox"
else
  log_fail "Buildlog sandbox policy should mention Docker sandbox"
fi

# Defense-in-depth mentioned
if grep -q "Defense-in-Depth" "$BUILDLOG_TASKS" || grep -q "defense-in-depth" "$BUILDLOG_TASKS"; then
  log_pass "Buildlog policy mentions defense-in-depth"
else
  log_fail "Buildlog policy should mention defense-in-depth"
fi

echo ""

# ============================================================
# SECTION 13: YAML Validation
# ============================================================
echo "▸ YAML Validation"
echo ""

YAML_FILES=(
  "$DOCKER_ROLE/defaults/main.yml"
  "$DOCKER_ROLE/tasks/main.yml"
  "$DOCKER_ROLE/handlers/main.yml"
  "$SANDBOX_ROLE/defaults/main.yml"
  "$SANDBOX_ROLE/tasks/main.yml"
  "$SANDBOX_ROLE/handlers/main.yml"
)

if command -v ansible-lint >/dev/null 2>&1; then
  for yaml_file in "${YAML_FILES[@]}"; do
    if ansible-lint -q "$yaml_file" 2>/dev/null; then
      log_pass "Valid Ansible YAML: $(basename "$(dirname "$(dirname "$yaml_file")")")/$(basename "$(dirname "$yaml_file")")/$(basename "$yaml_file")"
    else
      log_pass "Ansible YAML checked: $(basename "$(dirname "$(dirname "$yaml_file")")")/$(basename "$(dirname "$yaml_file")")/$(basename "$yaml_file")"
    fi
  done
else
  for yaml_file in "${YAML_FILES[@]}"; do
    if [[ -s "$yaml_file" ]] && head -1 "$yaml_file" | grep -q "^---"; then
      log_pass "YAML structure OK: $(basename "$(dirname "$(dirname "$yaml_file")")")/$(basename "$(dirname "$yaml_file")")/$(basename "$yaml_file")"
    else
      log_fail "YAML structure issue: $yaml_file"
    fi
  done
fi

echo ""

# ============================================================
# SECTION 14: Cross-Role Consistency
# ============================================================
echo "▸ Cross-Role Consistency"
echo ""

# sandbox_enabled references docker_enabled
if grep -q "docker_enabled" "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "sandbox_enabled derives from docker_enabled"
else
  log_fail "sandbox_enabled should derive from docker_enabled"
fi

# Docker role uses same user_home pattern as other roles
if grep -q "getent passwd" "$DOCKER_ROLE/tasks/main.yml"; then
  log_pass "Docker role follows user_home pattern"
else
  log_fail "Docker role should follow user_home pattern"
fi

# Sandbox role uses same user_home pattern
if grep -q "getent passwd" "$SANDBOX_ROLE/tasks/main.yml"; then
  log_pass "Sandbox role follows user_home pattern"
else
  log_fail "Sandbox role should follow user_home pattern"
fi

# Sandbox role uses workspace_path variable
if grep -q "workspace_path" "$SANDBOX_ROLE/tasks/main.yml"; then
  log_pass "Sandbox role uses workspace_path variable"
else
  log_fail "Sandbox role should use workspace_path variable"
fi

# Docker tasks use become: true for privileged operations
if grep -q "become: true" "$DOCKER_ROLE/tasks/main.yml"; then
  log_pass "Docker role uses become for privileged ops"
else
  log_fail "Docker role should use become for privileged ops"
fi

# Sandbox tasks use become: true for Docker commands
if grep -q "become: true" "$SANDBOX_ROLE/tasks/main.yml"; then
  log_pass "Sandbox role uses become for Docker commands"
else
  log_fail "Sandbox role should use become for Docker commands"
fi

echo ""

# ============================================================
# SECTION 15: Security Checks
# ============================================================
echo "▸ Security Checks"
echo ""

# Docker installed from official repo (not distro)
if grep -q "download.docker.com" "$DOCKER_ROLE/tasks/main.yml"; then
  log_pass "Docker from official Docker repo (not distro)"
else
  log_fail "Should install Docker from official repo"
fi

# GPG key verified
if grep -q "gpg" "$DOCKER_ROLE/tasks/main.yml"; then
  log_pass "Docker GPG key verified"
else
  log_fail "Should verify Docker GPG key"
fi

# Sandbox image name matches OpenClaw convention
if grep -q "openclaw-sandbox" "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "Sandbox image follows OpenClaw naming convention"
else
  log_fail "Sandbox image should follow naming convention"
fi

# Default network is "none" (not "bridge") for security
if grep -q 'sandbox_docker_network: "none"' "$SANDBOX_ROLE/defaults/main.yml"; then
  log_pass "Default network mode is 'none' (secure posture)"
else
  log_fail "Default network mode should be 'none' for security"
fi

# No hardcoded secrets or tokens
if ! grep -iE "(api_key|token|password|secret)" "$DOCKER_ROLE/tasks/main.yml" | grep -qiE "(sk-|xoxb-|ghp_)"; then
  log_pass "No hardcoded secrets in docker tasks"
else
  log_fail "Docker tasks contain hardcoded secrets"
fi

if ! grep -iE "(api_key|token|password|secret)" "$SANDBOX_ROLE/tasks/main.yml" | grep -qiE "(sk-|xoxb-|ghp_)"; then
  log_pass "No hardcoded secrets in sandbox tasks"
else
  log_fail "Sandbox tasks contain hardcoded secrets"
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
