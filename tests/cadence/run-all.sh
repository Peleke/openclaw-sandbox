#!/usr/bin/env bash
# Cadence Test Suite - Run All Tests
#
# Usage:
#   ./tests/cadence/run-all.sh [--quick]
#
# Options:
#   --quick   Skip E2E tests (faster, no VM interaction)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUICK_MODE=false

if [[ "${1:-}" == "--quick" ]]; then
  QUICK_MODE=true
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              Cadence Test Suite                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

run_test() {
  local name="$1"
  local script="$2"
  local skip="${3:-false}"

  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}Running:${NC} $name"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  if [[ "$skip" == "true" ]]; then
    echo -e "${YELLOW}SKIPPED${NC} (--quick mode)"
    ((TESTS_SKIPPED++))
    echo ""
    return 0
  fi

  if [[ ! -f "$script" ]]; then
    echo -e "${RED}FAILED${NC} - Script not found: $script"
    ((TESTS_FAILED++))
    echo ""
    return 1
  fi

  chmod +x "$script"
  if "$script"; then
    echo -e "${GREEN}PASSED${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}FAILED${NC}"
    ((TESTS_FAILED++))
  fi
  echo ""
}

# ============================================================
# Test 1: Ansible Role Validation (always run)
# ============================================================
run_test "Ansible Role Validation" "$SCRIPT_DIR/test-cadence-ansible.sh"

# ============================================================
# Test 2: Role Deployment Tests (requires VM)
# ============================================================
run_test "Role Deployment Tests" "$SCRIPT_DIR/test-cadence-role.sh" "$QUICK_MODE"

# ============================================================
# Test 3: E2E Pipeline Tests (requires VM + vault mounted + cadence enabled)
# ============================================================
# E2E tests require more setup (vault mounted, cadence enabled)
# Skip if vault isn't available
if limactl shell openclaw-sandbox -- test -d /mnt/obsidian 2>/dev/null; then
  run_test "E2E Pipeline Tests" "$SCRIPT_DIR/test-cadence-e2e.sh" "$QUICK_MODE"
else
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}Running:${NC} E2E Pipeline Tests"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "${YELLOW}SKIPPED${NC} (vault not mounted - run bootstrap.sh --vault ~/path/to/vault)"
  ((TESTS_SKIPPED++))
  echo ""
fi

# ============================================================
# Summary
# ============================================================
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              Test Suite Summary                               ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
printf "║  ${GREEN}Passed:${NC}  %-50s ║\n" "$TESTS_PASSED"
printf "║  ${RED}Failed:${NC}  %-50s ║\n" "$TESTS_FAILED"
printf "║  ${YELLOW}Skipped:${NC} %-50s ║\n" "$TESTS_SKIPPED"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
  echo -e "${RED}Some tests failed!${NC}"
  exit 1
fi

echo -e "${GREEN}All tests passed!${NC}"
exit 0
