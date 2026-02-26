#!/usr/bin/env bash
# Qortex Ansible Role Validation
#
# Validates the Ansible role structure and templates without running them.
# This is a "lint" test that catches issues before deployment.
#
# Usage:
#   ./tests/qortex/test-qortex-ansible.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROLE_DIR="$REPO_ROOT/ansible/roles/qortex"

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
echo "  Qortex Ansible Role Validation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Role Structure
# ============================================================
echo "▸ Role Structure"
echo ""

# Test: Role directory exists
if [[ -d "$ROLE_DIR" ]]; then
  log_pass "Role directory exists: ansible/roles/qortex"
else
  log_fail "Role directory missing"
  exit 1
fi

# Test: Required subdirectories
for subdir in defaults tasks templates handlers; do
  if [[ -d "$ROLE_DIR/$subdir" ]]; then
    log_pass "Directory exists: $subdir/"
  else
    log_fail "Missing directory: $subdir/"
  fi
done

# Test: Required files
for file in defaults/main.yml tasks/main.yml handlers/main.yml templates/interop.yaml.j2 templates/qortex-otel.sh.j2 templates/qortex.env.j2; do
  if [[ -f "$ROLE_DIR/$file" ]]; then
    log_pass "File exists: $file"
  else
    log_fail "Missing file: $file"
  fi
done

# Test: Old systemd templates are removed
for file in templates/qortex.service.j2 templates/qortex-mcp.service.j2; do
  if [[ ! -f "$ROLE_DIR/$file" ]]; then
    log_pass "Removed legacy file: $file"
  else
    log_fail "Legacy file still present: $file (should be removed)"
  fi
done

echo ""

# ============================================================
# SECTION 2: YAML Validation
# ============================================================
echo "▸ YAML Syntax"
echo ""

if command -v yamllint &>/dev/null; then
  for yaml_file in defaults/main.yml tasks/main.yml handlers/main.yml; do
    if yamllint -d relaxed "$ROLE_DIR/$yaml_file" >/dev/null 2>&1; then
      log_pass "Valid YAML: $yaml_file"
    else
      log_fail "Invalid YAML: $yaml_file"
      yamllint -d relaxed "$ROLE_DIR/$yaml_file" 2>&1 | head -5
    fi
  done
elif command -v ansible-playbook &>/dev/null; then
  for yaml_file in defaults/main.yml tasks/main.yml handlers/main.yml; do
    if head -1 "$ROLE_DIR/$yaml_file" | grep -qE '^---' || head -1 "$ROLE_DIR/$yaml_file" | grep -qE '^#'; then
      log_pass "Valid YAML: $yaml_file"
    else
      log_fail "Invalid YAML: $yaml_file (missing --- header)"
    fi
  done
else
  log_info "yamllint/ansible not available, skipping YAML validation"
fi

echo ""

# ============================================================
# SECTION 3: Template Validation
# ============================================================
echo "▸ Template Validation"
echo ""

# --- interop.yaml template ---
TEMPLATE_FILE="$ROLE_DIR/templates/interop.yaml.j2"
if [[ -f "$TEMPLATE_FILE" ]]; then
  log_pass "interop.yaml template exists"

  # Check it references qortex
  if grep -q "qortex" "$TEMPLATE_FILE"; then
    log_pass "Template references qortex"
  else
    log_fail "Template missing qortex reference"
  fi

  # Check it uses Ansible variables (user_home)
  if grep -q "{{ user_home" "$TEMPLATE_FILE"; then
    log_pass "Template uses user_home variable"
  else
    log_fail "Template missing user_home variable"
  fi

  # Check seed directory references
  for dir in pending processed failed; do
    if grep -q "seeds/$dir" "$TEMPLATE_FILE"; then
      log_pass "Template references seeds/$dir"
    else
      log_fail "Template missing seeds/$dir"
    fi
  done

  # Check signal_log reference
  if grep -q "signal_log\|signals/" "$TEMPLATE_FILE"; then
    log_pass "Template references signal log"
  else
    log_fail "Template missing signal log"
  fi
else
  log_fail "interop.yaml template missing"
fi

echo ""

# --- qortex-otel.sh template ---
OTEL_TEMPLATE="$ROLE_DIR/templates/qortex-otel.sh.j2"
if [[ -f "$OTEL_TEMPLATE" ]]; then
  log_pass "qortex-otel.sh template exists"

  # Check OTEL env vars
  if grep -q "QORTEX_OTEL_ENABLED" "$OTEL_TEMPLATE"; then
    log_pass "OTEL template exports QORTEX_OTEL_ENABLED"
  else
    log_fail "OTEL template missing QORTEX_OTEL_ENABLED"
  fi

  if grep -q "OTEL_EXPORTER_OTLP_ENDPOINT" "$OTEL_TEMPLATE"; then
    log_pass "OTEL template exports OTEL_EXPORTER_OTLP_ENDPOINT"
  else
    log_fail "OTEL template missing OTEL_EXPORTER_OTLP_ENDPOINT"
  fi

  if grep -q "OTEL_EXPORTER_OTLP_PROTOCOL" "$OTEL_TEMPLATE"; then
    log_pass "OTEL template exports OTEL_EXPORTER_OTLP_PROTOCOL"
  else
    log_fail "OTEL template missing OTEL_EXPORTER_OTLP_PROTOCOL"
  fi

  # Check it uses Ansible variables
  if grep -q "qortex_otel_enabled\|qortex_otel_endpoint\|qortex_otel_protocol" "$OTEL_TEMPLATE"; then
    log_pass "OTEL template uses Ansible variables"
  else
    log_fail "OTEL template missing Ansible variable references"
  fi
else
  log_fail "qortex-otel.sh template missing"
fi

# --- qortex-otel.env template (systemd format) ---
OTEL_ENV_TEMPLATE="$ROLE_DIR/templates/qortex-otel.env.j2"
if [[ -f "$OTEL_ENV_TEMPLATE" ]]; then
  log_pass "qortex-otel.env template exists"

  # Must NOT contain 'export' (systemd EnvironmentFile format)
  if grep -q "^export " "$OTEL_ENV_TEMPLATE"; then
    log_fail "OTEL env template contains 'export' (invalid for systemd EnvironmentFile)"
  else
    log_pass "OTEL env template has no 'export' (correct systemd format)"
  fi

  # Check all 5 required vars
  for var in QORTEX_OTEL_ENABLED OTEL_EXPORTER_OTLP_ENDPOINT OTEL_EXPORTER_OTLP_PROTOCOL QORTEX_PROMETHEUS_ENABLED QORTEX_PROMETHEUS_PORT; do
    if grep -q "^$var=" "$OTEL_ENV_TEMPLATE"; then
      log_pass "OTEL env template has $var"
    else
      log_fail "OTEL env template missing $var"
    fi
  done
else
  log_fail "qortex-otel.env template missing"
fi

# --- qortex.env template (Docker env-file format) ---
DOCKER_ENV_TEMPLATE="$ROLE_DIR/templates/qortex.env.j2"
if [[ -f "$DOCKER_ENV_TEMPLATE" ]]; then
  log_pass "qortex.env Docker template exists"

  # Must NOT contain 'export' (Docker --env-file format)
  if grep -q "^export " "$DOCKER_ENV_TEMPLATE"; then
    log_fail "Docker env template contains 'export' (invalid for --env-file)"
  else
    log_pass "Docker env template has no 'export' (correct format)"
  fi

  # Check required env vars for Docker container
  for var in QORTEX_STORE QORTEX_VEC HF_HUB_OFFLINE QORTEX_EXTRACTION QORTEX_GRAPH; do
    if grep -q "^$var=" "$DOCKER_ENV_TEMPLATE"; then
      log_pass "Docker env template has $var"
    else
      log_fail "Docker env template missing $var"
    fi
  done

  # Check OTEL vars are present (conditional)
  if grep -q "QORTEX_OTEL_ENABLED" "$DOCKER_ENV_TEMPLATE"; then
    log_pass "Docker env template has OTEL config"
  else
    log_fail "Docker env template missing OTEL config"
  fi
else
  log_fail "qortex.env Docker template missing"
fi

echo ""

# ============================================================
# SECTION 4: Task Validation
# ============================================================
echo "▸ Task Validation"
echo ""

TASKS_FILE="$ROLE_DIR/tasks/main.yml"

# Test: user_home fact
if grep -q "Get user home directory" "$TASKS_FILE"; then
  log_pass "Tasks get user_home fact"
else
  log_fail "Tasks missing user_home fact"
fi

# Test: Seed directory creation
if grep -q "qortex seed directories" "$TASKS_FILE"; then
  log_pass "Tasks create seed directories"
else
  log_fail "Tasks missing seed directory creation"
fi

# Test: Signals directory
if grep -q "qortex signals directory" "$TASKS_FILE"; then
  log_pass "Tasks create signals directory"
else
  log_fail "Tasks missing signals directory"
fi

# Test: buildlog dir guard (check-before-create pattern to avoid chown on Lima symlinks)
if grep -q "Check if buildlog directory exists" "$TASKS_FILE" && grep -q "Create buildlog directory for interop config" "$TASKS_FILE"; then
  log_pass "Tasks guard buildlog directory existence (check-before-create)"
else
  log_fail "Tasks missing buildlog directory guard"
fi

# Test: interop.yaml deployment
if grep -q "interop.yaml" "$TASKS_FILE"; then
  log_pass "Tasks deploy interop.yaml"
else
  log_fail "Tasks missing interop.yaml deployment"
fi

# Test: Docker deployment (replaces uv + systemd)
if grep -q "docker pull" "$TASKS_FILE"; then
  log_pass "Tasks pull Docker image"
else
  log_fail "Tasks missing Docker image pull"
fi

if grep -q "docker run" "$TASKS_FILE"; then
  log_pass "Tasks run Docker container"
else
  log_fail "Tasks missing Docker container run"
fi

if grep -q "docker volume create" "$TASKS_FILE"; then
  log_pass "Tasks create Docker data volume"
else
  log_fail "Tasks missing Docker data volume creation"
fi

if grep -q "network host" "$TASKS_FILE"; then
  log_pass "Tasks use host network (for localhost access)"
else
  log_fail "Tasks missing host network mode"
fi

if grep -q "env-file" "$TASKS_FILE"; then
  log_pass "Tasks pass env file to Docker container"
else
  log_fail "Tasks missing env-file flag"
fi

# Test: Health check wait
if grep -q "v1/health" "$TASKS_FILE"; then
  log_pass "Tasks wait for health check endpoint"
else
  log_fail "Tasks missing health check wait"
fi

# Test: Old systemd cleanup
if grep -q "Stop and disable old qortex systemd" "$TASKS_FILE"; then
  log_pass "Tasks clean up old systemd services"
else
  log_fail "Tasks missing systemd cleanup"
fi

# Test: OTEL profile.d deployment
if grep -q "profile.d/qortex-otel.sh" "$TASKS_FILE"; then
  log_pass "Tasks deploy OTEL profile.d script"
else
  log_fail "Tasks missing OTEL profile.d deployment"
fi

# Test: bash.bashrc OTEL hook
if grep -q "qortex-otel.sh" "$TASKS_FILE" && grep -q "bash.bashrc" "$TASKS_FILE"; then
  log_pass "Tasks hook OTEL into bash.bashrc"
else
  log_fail "Tasks missing bash.bashrc OTEL hook"
fi

# Test: systemd OTEL env file deployment
if grep -q "Deploy qortex OTEL env for systemd services" "$TASKS_FILE"; then
  log_pass "Tasks deploy systemd OTEL env file"
else
  log_fail "Tasks missing systemd OTEL env file deployment"
fi

# Test: systemd env deployed to /etc/openclaw/qortex-otel.env
if grep -q "/etc/openclaw/qortex-otel.env" "$TASKS_FILE"; then
  log_pass "OTEL env deployed to /etc/openclaw/qortex-otel.env"
else
  log_fail "OTEL env not deployed to expected path"
fi

echo ""

# ============================================================
# SECTION 5: Defaults Validation
# ============================================================
echo "▸ Defaults Validation"
echo ""

DEFAULTS_FILE="$ROLE_DIR/defaults/main.yml"

for var in qortex_enabled qortex_docker_image qortex_docker_container qortex_docker_volume qortex_serve_enabled qortex_serve_port qortex_http_transport qortex_otel_enabled qortex_otel_endpoint qortex_otel_protocol qortex_prometheus_enabled qortex_prometheus_port; do
  if grep -q "^$var:" "$DEFAULTS_FILE"; then
    log_pass "Default defined: $var"
  else
    log_fail "Default missing: $var"
  fi
done

echo ""

# ============================================================
# SECTION 6: Playbook Integration
# ============================================================
echo "▸ Playbook Integration"
echo ""

PLAYBOOK_FILE="$REPO_ROOT/ansible/playbook.yml"

if [[ -f "$PLAYBOOK_FILE" ]]; then
  # Test: Qortex role is included
  if grep -q "role: qortex" "$PLAYBOOK_FILE"; then
    log_pass "Qortex role included in playbook"
  else
    log_fail "Qortex role not in playbook"
  fi

  # Test: Has tags
  if grep -A1 "role: qortex" "$PLAYBOOK_FILE" | grep -q "tags:"; then
    log_pass "Qortex role has tags"
  else
    log_info "Qortex role missing tags (optional)"
  fi

  # Test: Has conditional
  if grep -A2 "role: qortex" "$PLAYBOOK_FILE" | grep -q "when:"; then
    log_pass "Qortex role has when condition"
  else
    log_info "Qortex role missing when condition"
  fi

  # Test: Role order (qortex should come after docker, before sandbox)
  DOCKER_LINE=$(grep -n "role: docker" "$PLAYBOOK_FILE" | head -1 | cut -d: -f1 || echo "0")
  QORTEX_LINE=$(grep -n "role: qortex" "$PLAYBOOK_FILE" | head -1 | cut -d: -f1 || echo "0")
  SANDBOX_LINE=$(grep -n "role: sandbox" "$PLAYBOOK_FILE" | head -1 | cut -d: -f1 || echo "0")

  if [[ "$DOCKER_LINE" != "0" && "$QORTEX_LINE" != "0" ]]; then
    if [[ "$QORTEX_LINE" -gt "$DOCKER_LINE" ]]; then
      log_pass "Role order correct (docker before qortex)"
    else
      log_fail "Role order wrong (qortex should come after docker)"
    fi
  fi

  if [[ "$SANDBOX_LINE" != "0" && "$QORTEX_LINE" != "0" ]]; then
    if [[ "$QORTEX_LINE" -lt "$SANDBOX_LINE" ]]; then
      log_pass "Role order correct (qortex before sandbox)"
    else
      log_fail "Role order wrong (qortex should come before sandbox)"
    fi
  fi
else
  log_fail "Playbook not found"
fi

echo ""

# ============================================================
# SECTION 7: Bootstrap Integration
# ============================================================
echo "▸ Bootstrap Integration"
echo ""

BOOTSTRAP_FILE="$REPO_ROOT/bootstrap.sh"

if [[ -f "$BOOTSTRAP_FILE" ]]; then
  # Test: --memgraph flag
  if grep -q "\-\-memgraph)" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap has --memgraph flag"
  else
    log_fail "Bootstrap missing --memgraph flag"
  fi

  # Test: --memgraph-port flag
  if grep -q "\-\-memgraph-port)" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap has --memgraph-port flag"
  else
    log_fail "Bootstrap missing --memgraph-port flag"
  fi

  # Test: memgraph_enabled passed to Ansible
  if grep -q "memgraph_enabled" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap passes memgraph_enabled to Ansible"
  else
    log_fail "Bootstrap missing memgraph_enabled Ansible var"
  fi

  # Test: Memgraph port forwards in Lima config
  if grep -q "7687" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap references Memgraph Bolt port 7687"
  else
    log_fail "Bootstrap missing Memgraph port 7687"
  fi

  if grep -q "7444" "$BOOTSTRAP_FILE"; then
    log_pass "Bootstrap references Memgraph monitoring port 7444"
  else
    log_fail "Bootstrap missing Memgraph port 7444"
  fi
else
  log_fail "bootstrap.sh not found"
fi

echo ""

# ============================================================
# SECTION 8: Handler Validation
# ============================================================
echo "▸ Handler Validation"
echo ""

HANDLERS_FILE="$ROLE_DIR/handlers/main.yml"

if [[ -f "$HANDLERS_FILE" ]]; then
  if grep -q "Restart qortex container" "$HANDLERS_FILE"; then
    log_pass "Handler: Restart qortex container"
  else
    log_fail "Handler missing: Restart qortex container"
  fi

  if grep -q "docker restart" "$HANDLERS_FILE"; then
    log_pass "Handler uses docker restart (not systemctl)"
  else
    log_fail "Handler not using docker restart"
  fi
else
  log_fail "Handlers file missing"
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo "═══════════════════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}Validation PASSED${NC} ($PASS/$TOTAL checks)"
else
  echo -e "  ${RED}Validation FAILED${NC} ($PASS passed, $FAIL failed)"
fi
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
