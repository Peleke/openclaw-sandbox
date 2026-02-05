#!/usr/bin/env bash
#
# Docs Test Suite - Run All Tests
#
# Usage:
#   ./tests/docs/run-all.sh [--quick]
#
# Options:
#   --quick   Skip build tests (no Python/Node required)
#
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
echo "║              Docs Test Suite                                  ║"
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
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo ""
    return 0
  fi

  if bash "$script"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  echo ""
}

# Test 1: Structure validation (always runs)
run_test "Structure Validation" "$SCRIPT_DIR/test-docs-structure.sh"

# Test 2: Build tests (skip in quick mode)
run_test "Build Tests" "$SCRIPT_DIR/test-docs-build.sh" "$QUICK_MODE"

# ============================================================
# Summary
# ============================================================
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              Test Suite Summary                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
TOTAL=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
echo -e "  Suites passed:  ${GREEN}${TESTS_PASSED}${NC}"
echo -e "  Suites failed:  ${RED}${TESTS_FAILED}${NC}"
echo -e "  Suites skipped: ${YELLOW}${TESTS_SKIPPED}${NC}"
echo -e "  Total:          ${TOTAL}"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
  echo -e "${RED}SOME TESTS FAILED${NC}"
  exit 1
else
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
fi
