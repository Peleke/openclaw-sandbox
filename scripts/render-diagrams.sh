#!/usr/bin/env bash
#
# render-diagrams.sh — Render Mermaid .mmd files to SVG
#
# Usage:
#   ./scripts/render-diagrams.sh
#
# Requires: npx @mermaid-js/mermaid-cli (mmdc)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="${PROJECT_DIR}/docs/diagrams/src"
OUT_DIR="${PROJECT_DIR}/docs/diagrams"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[RENDER]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if ! command -v npx >/dev/null 2>&1; then
    log_error "npx not found. Install Node.js first."
    exit 1
fi

if [[ ! -d "$SRC_DIR" ]]; then
    log_error "Source directory not found: ${SRC_DIR}"
    exit 1
fi

RENDERED=0
FAILED=0

for mmd_file in "${SRC_DIR}"/*.mmd; do
    [[ -f "$mmd_file" ]] || continue

    basename="$(basename "$mmd_file" .mmd)"
    svg_file="${OUT_DIR}/${basename}.svg"

    log_info "Rendering ${basename}.mmd → ${basename}.svg"

    if npx -y @mermaid-js/mermaid-cli -i "$mmd_file" -o "$svg_file" -b transparent 2>/dev/null; then
        ((RENDERED++))
    else
        log_error "Failed to render: ${basename}.mmd"
        ((FAILED++))
    fi
done

echo ""
log_info "Done: ${RENDERED} rendered, ${FAILED} failed"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
