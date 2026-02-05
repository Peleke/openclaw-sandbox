#!/usr/bin/env bash
#
# test-docs-build.sh — Build validation for docs site
#
# Requires: Python (mkdocs), Node.js (mermaid-cli)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0

pass() {
  echo -e "  ${GREEN}✓${NC} $1"
  PASS=$((PASS + 1))
}

fail() {
  echo -e "  ${RED}✗${NC} $1"
  FAIL=$((FAIL + 1))
}

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Docs Build Tests                                    ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================
echo -e "${CYAN}── Prerequisites ──${NC}"
# ============================================================

if command -v mkdocs >/dev/null 2>&1; then
  pass "mkdocs is installed ($(mkdocs --version 2>&1 | head -1))"
else
  fail "mkdocs is not installed (pip install mkdocs)"
  echo -e "${RED}Cannot continue without mkdocs${NC}"
  exit 1
fi

if command -v npx >/dev/null 2>&1; then
  pass "npx is available"
else
  fail "npx is not available (install Node.js)"
fi

# ============================================================
echo -e "${CYAN}── Mermaid rendering ──${NC}"
# ============================================================

if command -v npx >/dev/null 2>&1; then
  if bash "${PROJECT_DIR}/scripts/render-diagrams.sh" 2>&1; then
    pass "render-diagrams.sh completed"
  else
    fail "render-diagrams.sh failed"
  fi

  # Check each SVG was produced
  for mmd in "${PROJECT_DIR}/docs/diagrams/src/"*.mmd; do
    [[ -f "$mmd" ]] || continue
    basename="$(basename "$mmd" .mmd)"
    svg="${PROJECT_DIR}/docs/diagrams/${basename}.svg"
    if [[ -f "$svg" ]]; then
      pass "${basename}.svg rendered"
      # Check it's valid XML
      if head -5 "$svg" | grep -q '<svg\|<?xml'; then
        pass "${basename}.svg is valid SVG"
      else
        fail "${basename}.svg does not appear to be valid SVG"
      fi
    else
      fail "${basename}.svg not produced"
    fi
  done
else
  echo -e "  ${YELLOW}SKIP${NC} Mermaid rendering (npx not available)"
fi

# ============================================================
echo -e "${CYAN}── MkDocs build ──${NC}"
# ============================================================

cd "$PROJECT_DIR"

if mkdocs build --strict 2>&1; then
  pass "mkdocs build --strict succeeded"
else
  fail "mkdocs build --strict failed"
fi

# Check site directory was created
if [[ -d "${PROJECT_DIR}/site" ]]; then
  pass "site/ directory created"
else
  fail "site/ directory not created"
fi

# Check key pages exist in built site
for page in index.html getting-started/prerequisites/index.html configuration/secrets/index.html architecture/overview/index.html; do
  if [[ -f "${PROJECT_DIR}/site/${page}" ]]; then
    pass "built: ${page}"
  else
    fail "missing in build: ${page}"
  fi
done

# ============================================================
echo -e "${CYAN}── Serve smoke test ──${NC}"
# ============================================================

# Start mkdocs serve in background, check it responds, kill it
SERVE_PORT=8765
mkdocs serve -a "127.0.0.1:${SERVE_PORT}" &>/dev/null &
SERVE_PID=$!
sleep 3

if curl -sf "http://127.0.0.1:${SERVE_PORT}/" >/dev/null 2>&1; then
  pass "mkdocs serve responds on port ${SERVE_PORT}"
else
  fail "mkdocs serve not responding on port ${SERVE_PORT}"
fi

kill "$SERVE_PID" 2>/dev/null || true
wait "$SERVE_PID" 2>/dev/null || true

# ============================================================
# Summary
# ============================================================
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Build Test Summary                                  ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
TOTAL=$((PASS + FAIL))
echo -e "  Passed: ${GREEN}${PASS}${NC}"
echo -e "  Failed: ${RED}${FAIL}${NC}"
echo -e "  Total:  ${TOTAL}"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}SOME CHECKS FAILED${NC}"
  exit 1
else
  echo -e "${GREEN}ALL CHECKS PASSED${NC}"
fi
