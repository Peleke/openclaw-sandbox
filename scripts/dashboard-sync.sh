#!/usr/bin/env bash
# dashboard-sync.sh — Sync GitHub issues to Obsidian kanban boards
#
# Usage: ./scripts/dashboard-sync.sh [--dry-run]
#
# Reads dashboard config from the sandbox profile (~/.openclaw/sandbox-profile.toml).
# Falls back to mounts.vault when dashboard.vault_path is not set.
# The sync script is auto-discovered at <vault>/_scripts/gh-obsidian-sync.py.
#
# To set up periodic sync (every 10 minutes):
#   cp scripts/com.openclaw.dashboard-sync.plist ~/Library/LaunchAgents/
#   launchctl load ~/Library/LaunchAgents/com.openclaw.dashboard-sync.plist

set -euo pipefail

DRY_RUN=""
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN="--dry-run"

# ── Resolve vault and script paths from profile ─────────────────────────

read_profile() {
    python3 -c "
import tomllib, pathlib, os, json

p = pathlib.Path(os.path.expanduser('~/.openclaw/sandbox-profile.toml'))
if not p.exists():
    print(json.dumps({'error': 'Profile not found'}))
    raise SystemExit(1)

d = tomllib.loads(p.read_text())
dash = d.get('dashboard', {})
mounts = d.get('mounts', {})

vault = dash.get('vault_path', '') or mounts.get('vault', '')
if vault:
    vault = os.path.expanduser(vault)

script = dash.get('script_path', '')
if script:
    script = os.path.expanduser(script)
else:
    script = os.path.join(vault, '_scripts', 'gh-obsidian-sync.py') if vault else ''

days = dash.get('lookback_days', 14)
repos = dash.get('repos', [])

print(json.dumps({
    'vault': vault,
    'script': script,
    'days': days,
    'repos': repos,
}))
" 2>/dev/null
}

PROFILE_JSON=$(read_profile)
if echo "$PROFILE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'error' not in d else 1)" 2>/dev/null; then
    VAULT=$(echo "$PROFILE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['vault'])")
    SCRIPT=$(echo "$PROFILE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['script'])")
    DAYS=$(echo "$PROFILE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['days'])")
    REPOS=$(echo "$PROFILE_JSON" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin)['repos']))")
else
    echo "ERROR: Could not read sandbox profile."
    exit 1
fi

if [[ -z "$VAULT" ]]; then
    echo "ERROR: No vault path. Set dashboard.vault_path or mounts.vault in sandbox profile."
    exit 1
fi

if [[ ! -d "$VAULT" ]]; then
    echo "ERROR: Vault directory does not exist: $VAULT"
    exit 1
fi

if [[ ! -f "$SCRIPT" ]]; then
    echo "ERROR: Sync script not found: $SCRIPT"
    exit 1
fi

# ── Run the sync ────────────────────────────────────────────────────────

CMD=(python3 "$SCRIPT" --vault "$VAULT" --days "$DAYS")
if [[ -n "$REPOS" ]]; then
    # shellcheck disable=SC2206
    CMD+=(--repos $REPOS)
fi
if [[ -n "$DRY_RUN" ]]; then
    CMD+=(--dry-run)
fi

echo "[$(date -Iseconds)] Dashboard sync: ${CMD[*]}"
"${CMD[@]}"
echo "[$(date -Iseconds)] Dashboard sync complete."
