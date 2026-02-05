#!/usr/bin/env bash
#
# test-docs-structure.sh — Static structure checks for docs site
#
# Validates that all expected files exist, nav entries are correct,
# and Mermaid sources are present. No build tools required.
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

check_file() {
  local path="$1"
  local label="${2:-$path}"
  if [[ -f "${PROJECT_DIR}/${path}" ]]; then
    pass "$label exists"
  else
    fail "$label missing: ${path}"
  fi
}

check_dir() {
  local path="$1"
  local label="${2:-$path}"
  if [[ -d "${PROJECT_DIR}/${path}" ]]; then
    pass "$label exists"
  else
    fail "$label missing: ${path}"
  fi
}

check_executable() {
  local path="$1"
  local label="${2:-$path}"
  if [[ -x "${PROJECT_DIR}/${path}" ]]; then
    pass "$label is executable"
  else
    fail "$label is not executable: ${path}"
  fi
}

check_nonempty() {
  local path="$1"
  local label="${2:-$path}"
  if [[ -s "${PROJECT_DIR}/${path}" ]]; then
    pass "$label has content"
  else
    fail "$label is empty: ${path}"
  fi
}

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Docs Structure Tests                                ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================
echo -e "${CYAN}── Config files ──${NC}"
# ============================================================
check_file "mkdocs.yml" "mkdocs.yml"
check_nonempty "mkdocs.yml" "mkdocs.yml"
check_file ".github/workflows/docs.yml" "docs CI workflow"
check_file "scripts/render-diagrams.sh" "render-diagrams.sh"
check_executable "scripts/render-diagrams.sh" "render-diagrams.sh"
check_file "docs/diagrams/.gitignore" "diagrams .gitignore"

# ============================================================
echo -e "${CYAN}── mkdocs.yml validation ──${NC}"
# ============================================================

# Check theme is readthedocs
if grep -q 'name: readthedocs' "${PROJECT_DIR}/mkdocs.yml"; then
  pass "theme is readthedocs"
else
  fail "theme is not readthedocs"
fi

# Check site_name
if grep -q 'site_name:' "${PROJECT_DIR}/mkdocs.yml"; then
  pass "site_name is set"
else
  fail "site_name is missing"
fi

# ============================================================
echo -e "${CYAN}── Nav entry files exist ──${NC}"
# ============================================================

# Extract all .md file paths from nav entries in mkdocs.yml
nav_files=$(grep -oE '[a-zA-Z0-9/_-]+\.md' "${PROJECT_DIR}/mkdocs.yml" | sort -u)

for md_file in $nav_files; do
  check_file "docs/${md_file}" "nav: ${md_file}"
done

# ============================================================
echo -e "${CYAN}── Mermaid source files ──${NC}"
# ============================================================
check_dir "docs/diagrams/src" "diagrams/src directory"
check_nonempty "docs/diagrams/src/architecture.mmd" "architecture.mmd"
check_nonempty "docs/diagrams/src/defense-in-depth.mmd" "defense-in-depth.mmd"
check_nonempty "docs/diagrams/src/secrets-pipeline.mmd" "secrets-pipeline.mmd"
check_nonempty "docs/diagrams/src/overlay-filesystem.mmd" "overlay-filesystem.mmd"

# ============================================================
echo -e "${CYAN}── Moved files in correct locations ──${NC}"
# ============================================================
check_file "docs/security/threat-model.md" "threat-model.md (moved)"
check_file "docs/security/stride/spoofing.md" "stride/spoofing.md (moved)"
check_file "docs/security/stride/tampering.md" "stride/tampering.md (moved)"
check_file "docs/security/stride/repudiation.md" "stride/repudiation.md (moved)"
check_file "docs/security/stride/information-disclosure.md" "stride/information-disclosure.md (moved)"
check_file "docs/security/stride/denial-of-service.md" "stride/denial-of-service.md (moved)"
check_file "docs/security/stride/elevation-of-privilege.md" "stride/elevation-of-privilege.md (moved)"
check_file "docs/security/stride/supply-chain.md" "stride/supply-chain.md (moved)"
check_file "docs/publication-series-outline.md" "publication-series-outline.md (kept)"

# ============================================================
echo -e "${CYAN}── Old locations cleaned up ──${NC}"
# ============================================================
if [[ ! -f "${PROJECT_DIR}/docs/threat-modeling-methodology.md" ]]; then
  pass "old threat-modeling-methodology.md removed"
else
  fail "old threat-modeling-methodology.md still exists"
fi

if [[ ! -f "${PROJECT_DIR}/docs/plans/stride-s-spoofing.md" ]]; then
  pass "old plans/stride-s-spoofing.md removed"
else
  fail "old plans/stride-s-spoofing.md still exists"
fi

# ============================================================
echo -e "${CYAN}── Doc pages have real content (not just stubs) ──${NC}"
# ============================================================
for md_file in $nav_files; do
  full_path="${PROJECT_DIR}/docs/${md_file}"
  if [[ -f "$full_path" ]]; then
    line_count=$(wc -l < "$full_path" | tr -d ' ')
    if [[ "$line_count" -gt 5 ]]; then
      pass "${md_file} has content (${line_count} lines)"
    else
      fail "${md_file} appears to be a stub (${line_count} lines)"
    fi
  fi
done

# ============================================================
# Summary
# ============================================================
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Structure Test Summary                              ║"
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
