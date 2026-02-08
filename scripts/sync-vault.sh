#!/usr/bin/env bash
# sync-vault.sh - Sync Obsidian vault from host into VM overlay
#
# Usage: ./scripts/sync-vault.sh [VAULT_PATH]
#
# Bypasses virtiofs iCloud file coordination locks by using rsync over SSH.
# The overlay upper directory receives the copies, so /workspace-obsidian/
# serves host-readable files instead of hitting the locked virtiofs mount.
#
# To set up periodic sync (every 5 minutes):
#   crontab -e
#   */5 * * * * /path/to/openclaw-sandbox/scripts/sync-vault.sh >> /tmp/vault-sync.log 2>&1

set -euo pipefail

VM_NAME="openclaw-sandbox"
# Write to the merged overlay mount so inotify fires and chokidar picks it up.
# Writing to the raw upper dir (/var/lib/openclaw/overlay/obsidian/upper)
# bypasses inotify on the merged mount — cadence would never see the change.
TARGET_DIR="/workspace-obsidian"

# Resolve vault path: argument > profile > default
if [[ -n "${1:-}" ]]; then
    VAULT_PATH="$1"
elif command -v python3 &>/dev/null; then
    # Try reading from sandbox profile
    VAULT_PATH=$(python3 -c "
import tomllib, pathlib, os
p = pathlib.Path(os.path.expanduser('~/.openclaw/sandbox-profile.toml'))
if p.exists():
    d = tomllib.loads(p.read_text())
    v = d.get('mounts', {}).get('vault', '')
    if v:
        print(os.path.expanduser(v))
" 2>/dev/null || true)
fi

if [[ -z "${VAULT_PATH:-}" ]]; then
    echo "ERROR: No vault path. Pass as argument or set mounts.vault in sandbox profile."
    exit 1
fi

# Verify vault exists
if [[ ! -d "$VAULT_PATH" ]]; then
    echo "ERROR: Vault path does not exist: $VAULT_PATH"
    exit 1
fi

# Verify VM is running
if ! limactl list --json 2>/dev/null | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    obj = json.loads(line)
    if obj.get('name') == '${VM_NAME}' and obj.get('status') == 'Running':
        sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    echo "ERROR: VM '${VM_NAME}' is not running"
    exit 1
fi

# Get SSH details
SSH_CONFIG=$(limactl show-ssh --format=config "$VM_NAME" 2>/dev/null)
SSH_HOST=$(echo "$SSH_CONFIG" | grep -m1 'Hostname ' | awk '{print $2}')
SSH_PORT=$(echo "$SSH_CONFIG" | grep -m1 'Port ' | awk '{print $2}')
SSH_USER=$(echo "$SSH_CONFIG" | grep -m1 'User ' | awk '{print $2}')
SSH_KEY=$(echo "$SSH_CONFIG" | grep -m1 'IdentityFile ' | awk '{print $2}' | tr -d '"')

echo "[$(date -Iseconds)] Syncing vault: $VAULT_PATH -> $VM_NAME:$TARGET_DIR"

rsync -a --delete --exclude='.obsidian/' \
    -e "ssh -p ${SSH_PORT} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q" \
    "${VAULT_PATH}/" \
    "${SSH_USER}@${SSH_HOST}:${TARGET_DIR}/"

echo "[$(date -Iseconds)] Vault sync complete."
