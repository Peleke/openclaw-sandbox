#!/usr/bin/env bash
#
# dashboard.sh - Open or print OpenClaw gateway dashboard URLs
#
# Reads the gateway password from ~/.openclaw/openclaw.json and opens
# the dashboard in your browser (or prints the URL with --dry).
#
# Usage:
#   ./scripts/dashboard.sh              # Open control panel (default)
#   ./scripts/dashboard.sh green        # Open green dashboard
#   ./scripts/dashboard.sh learning     # Open learning dashboard
#   ./scripts/dashboard.sh --dry        # Print URL instead of opening
#   ./scripts/dashboard.sh --dry green  # Print green dashboard URL

set -euo pipefail

GATEWAY_HOST="${OPENCLAW_GATEWAY_HOST:-127.0.0.1}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
CONFIG_PATH="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"

DRY_RUN=false
PAGE="control"

# Parse args
for arg in "$@"; do
    case "$arg" in
        --dry)       DRY_RUN=true ;;
        green)       PAGE="green" ;;
        learning)    PAGE="learning" ;;
        control)     PAGE="control" ;;
        --help|-h)
            echo "Usage: dashboard.sh [--dry] [green|learning|control]"
            echo ""
            echo "Pages:"
            echo "  control    Gateway control panel (default)"
            echo "  green      Carbon emissions dashboard"
            echo "  learning   Learning/bandit dashboard"
            echo ""
            echo "Options:"
            echo "  --dry      Print URL instead of opening browser"
            echo ""
            echo "Environment:"
            echo "  OPENCLAW_GATEWAY_HOST  Gateway host (default: 127.0.0.1)"
            echo "  OPENCLAW_GATEWAY_PORT  Gateway port (default: 18789)"
            echo "  OPENCLAW_CONFIG        Config file path (default: ~/.openclaw/openclaw.json)"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: dashboard.sh [--dry] [green|learning|control]" >&2
            exit 1
            ;;
    esac
done

BASE="http://${GATEWAY_HOST}:${GATEWAY_PORT}"

# Get gateway password: env var first, then config file
GW_PASSWORD="${OPENCLAW_GATEWAY_PASSWORD:-}"
if [[ -z "$GW_PASSWORD" ]] && [[ -f "$CONFIG_PATH" ]] && command -v jq &>/dev/null; then
    GW_PASSWORD=$(jq -r '.gateway.auth.password // empty' "$CONFIG_PATH" 2>/dev/null || true)
fi

# Build URL
case "$PAGE" in
    green)    URL="${BASE}/__openclaw__/api/green/dashboard" ;;
    learning) URL="${BASE}/__openclaw__/api/learning/dashboard" ;;
    control)
        if [[ -n "$GW_PASSWORD" ]]; then
            URL="${BASE}/?password=${GW_PASSWORD}"
        else
            URL="${BASE}/"
        fi
        ;;
esac

if [[ "$DRY_RUN" == "true" ]]; then
    echo "$URL"
else
    # Open in browser
    if command -v open &>/dev/null; then
        open "$URL"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$URL"
    else
        echo "$URL"
    fi
fi
