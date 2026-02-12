#!/usr/bin/env bash
# Firewall Ansible Role Validation
#
# Validates the Ansible role structure, defaults, and rules without running them.
#
# Usage:
#   ./tests/firewall/test-firewall-ansible.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROLE_DIR="$REPO_ROOT/ansible/roles/firewall"

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
echo "  Firewall Ansible Role Validation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Role Structure
# ============================================================
echo "▸ Role Structure"
echo ""

if [[ -d "$ROLE_DIR" ]]; then
  log_pass "Role directory exists: ansible/roles/firewall"
else
  log_fail "Role directory missing"
  exit 1
fi

for subdir in defaults tasks; do
  if [[ -d "$ROLE_DIR/$subdir" ]]; then
    log_pass "Directory exists: $subdir/"
  else
    log_fail "Missing directory: $subdir/"
  fi
done

for file in defaults/main.yml tasks/main.yml; do
  if [[ -f "$ROLE_DIR/$file" ]]; then
    log_pass "File exists: $file"
  else
    log_fail "Missing file: $file"
  fi
done

echo ""

# ============================================================
# SECTION 2: Default Variables
# ============================================================
echo "▸ Default Variables"
echo ""

DEFAULTS_FILE="$ROLE_DIR/defaults/main.yml"

for var in firewall_reset_on_run firewall_gateway_port firewall_allowed_domains firewall_tailscale_cidr firewall_tailscale_port firewall_enable_logging firewall_log_limit firewall_otel_host_ip firewall_otel_ports; do
  if grep -q "^$var:" "$DEFAULTS_FILE"; then
    log_pass "Default defined: $var"
  else
    log_fail "Default missing: $var"
  fi
done

# Verify OTEL host IP is Lima host address
if grep -q '192.168.5.2' "$DEFAULTS_FILE"; then
  log_pass "OTEL host IP is Lima host address (192.168.5.2)"
else
  log_fail "OTEL host IP should be 192.168.5.2 (Lima host.lima.internal)"
fi

# Verify OTEL port includes 4318
if grep -q '4318' "$DEFAULTS_FILE"; then
  log_pass "OTEL ports include 4318 (OTLP HTTP)"
else
  log_fail "OTEL ports missing 4318"
fi

echo ""

# ============================================================
# SECTION 3: Core Firewall Rules
# ============================================================
echo "▸ Core Firewall Rules"
echo ""

TASKS_FILE="$ROLE_DIR/tasks/main.yml"

# Default deny policies
if grep -q "Set default incoming policy to deny" "$TASKS_FILE"; then
  log_pass "Default incoming: deny"
else
  log_fail "Missing default incoming deny"
fi

if grep -q "Set default outgoing policy to deny" "$TASKS_FILE"; then
  log_pass "Default outgoing: deny"
else
  log_fail "Missing default outgoing deny"
fi

# Loopback
if grep -q "Allow loopback interface" "$TASKS_FILE"; then
  log_pass "Loopback rule present"
else
  log_fail "Missing loopback rule"
fi

# Gateway port
if grep -q "Allow incoming gateway connections" "$TASKS_FILE"; then
  log_pass "Gateway incoming rule present"
else
  log_fail "Missing gateway incoming rule"
fi

# SSH
if grep -q "Allow incoming SSH" "$TASKS_FILE"; then
  log_pass "SSH rule present"
else
  log_fail "Missing SSH rule"
fi

# DNS
if grep -q "Allow outbound DNS" "$TASKS_FILE"; then
  log_pass "DNS rule present"
else
  log_fail "Missing DNS rule"
fi

# HTTPS
if grep -q "Allow outbound HTTPS" "$TASKS_FILE"; then
  log_pass "HTTPS rule present"
else
  log_fail "Missing HTTPS rule"
fi

# NTP
if grep -q "Allow outbound NTP" "$TASKS_FILE"; then
  log_pass "NTP rule present"
else
  log_fail "Missing NTP rule"
fi

echo ""

# ============================================================
# SECTION 4: OTEL Firewall Rules
# ============================================================
echo "▸ OTEL Firewall Rules"
echo ""

# OTEL UFW rule exists
if grep -q "Allow outbound OTEL to host" "$TASKS_FILE"; then
  log_pass "OTEL outbound rule present"
else
  log_fail "Missing OTEL outbound rule"
fi

# OTEL rule uses to_ip
if grep -A8 "Allow outbound OTEL" "$TASKS_FILE" | grep -q "to_ip:"; then
  log_pass "OTEL rule uses to_ip (scoped to host only)"
else
  log_fail "OTEL rule missing to_ip — must be scoped to host collector"
fi

# OTEL rule uses firewall_otel_host_ip variable
if grep -A8 "Allow outbound OTEL" "$TASKS_FILE" | grep -q "firewall_otel_host_ip"; then
  log_pass "OTEL rule uses firewall_otel_host_ip variable"
else
  log_fail "OTEL rule should use firewall_otel_host_ip variable"
fi

# OTEL rule loops over firewall_otel_ports
if grep -A10 "Allow outbound OTEL" "$TASKS_FILE" | grep -q "firewall_otel_ports"; then
  log_pass "OTEL rule loops over firewall_otel_ports"
else
  log_fail "OTEL rule should loop over firewall_otel_ports"
fi

# OTEL rule gated on qortex_otel_enabled
if grep -A12 "Allow outbound OTEL" "$TASKS_FILE" | grep -q "qortex_otel_enabled"; then
  log_pass "OTEL rule gated on qortex_otel_enabled"
else
  log_fail "OTEL rule must be gated on qortex_otel_enabled"
fi

# OTEL rule uses TCP protocol
if grep -A8 "Allow outbound OTEL" "$TASKS_FILE" | grep -q "proto: tcp"; then
  log_pass "OTEL rule uses TCP protocol"
else
  log_fail "OTEL rule should use TCP protocol"
fi

# OTEL rule is outbound
if grep -A8 "Allow outbound OTEL" "$TASKS_FILE" | grep -q "direction: out"; then
  log_pass "OTEL rule direction is outbound"
else
  log_fail "OTEL rule should be outbound"
fi

echo ""

# ============================================================
# SECTION 5: Completion Message
# ============================================================
echo "▸ Completion Message"
echo ""

# Completion message mentions OTEL
if grep -q "OTEL" "$TASKS_FILE" && grep -q "firewall_otel_ports" "$TASKS_FILE"; then
  log_pass "Completion message includes OTEL info"
else
  log_fail "Completion message should mention OTEL when enabled"
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
