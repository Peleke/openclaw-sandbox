#!/usr/bin/env bash
# sync-skills.sh - Sync custom skills from host into VM
#
# Usage: ./scripts/sync-skills.sh

set -euo pipefail

VM_NAME="openclaw-sandbox"
SKILLS_SRC="/Users/peleke/Documents/Projects/skills/skills/custom"
TARGET_DIR="$(limactl shell "$VM_NAME" -- bash -c 'echo $HOME' 2>/dev/null | tr -d '\r')/.openclaw/skills-extra"

# Verify source exists
if [[ ! -d "$SKILLS_SRC" ]]; then
    echo "ERROR: Skills source does not exist: $SKILLS_SRC"
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

# Ensure target directory exists
ssh -p "${SSH_PORT}" -i "${SSH_KEY}" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q \
    "${SSH_USER}@${SSH_HOST}" "mkdir -p ${TARGET_DIR}"

echo "[$(date -Iseconds)] Syncing skills: $SKILLS_SRC -> $VM_NAME:$TARGET_DIR"

rsync -a --delete \
    -e "ssh -p ${SSH_PORT} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q" \
    "${SKILLS_SRC}/" \
    "${SSH_USER}@${SSH_HOST}:${TARGET_DIR}/"

echo "[$(date -Iseconds)] Skills sync complete."
