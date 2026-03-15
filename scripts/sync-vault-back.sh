#!/usr/bin/env bash
#
# sync-vault-back.sh — Gated reverse sync: VM vault overlay → host Obsidian vault
#
# Extracts files written by Cadence (GitHub synthesis, buildlog entries) from the
# VM's obsidian overlay upper layer, validates them, and syncs to the host vault.
#
# By default, scoped to the Buildlog/ subdirectory only (cadence-generated files).
# Use --scope to change or --all to sync everything in the overlay upper.
#
# Usage:
#   ./scripts/sync-vault-back.sh                    # Interactive: validate, preview, apply
#   ./scripts/sync-vault-back.sh --dry-run          # Just show what would sync
#   ./scripts/sync-vault-back.sh --auto             # Skip confirmation (CI/automation)
#   ./scripts/sync-vault-back.sh --scope Buildlog   # Limit to subdirectory (default)
#   ./scripts/sync-vault-back.sh --all              # Sync everything in overlay upper
#   ./scripts/sync-vault-back.sh --status           # Show vault overlay status
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VM_NAME="openclaw-sandbox"

# Overlay paths in VM (obsidian vault upper layer)
UPPER="/var/lib/openclaw/overlay/obsidian/upper"

# Default scope: only sync Buildlog/ subdirectory
SCOPE="Buildlog"

# Validation settings (same as sync-gate.sh)
MAX_FILE_SIZE=$((10 * 1024 * 1024))  # 10MB per file
BLOCKED_EXTENSIONS=(.env .pem .key .p12 .pfx .jks .keystore .secret .credentials)

# Staging area on host
STAGING_DIR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[VAULT]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

cleanup() {
    if [[ -n "${STAGING_DIR:-}" && -d "${STAGING_DIR:-}" ]]; then
        rm -rf "$STAGING_DIR"
    fi
}
trap cleanup EXIT

# Resolve host vault path from sandbox-profile.toml
resolve_vault_path() {
    local vault_path=""
    if command -v python3 &>/dev/null; then
        vault_path=$(python3 -c "
import tomllib, pathlib, os
p = pathlib.Path(os.path.expanduser('~/.openclaw/sandbox-profile.toml'))
if p.exists():
    d = tomllib.loads(p.read_text())
    v = d.get('mounts', {}).get('vault', '')
    if v:
        print(os.path.expanduser(v))
" 2>/dev/null || true)
    fi

    if [[ -z "$vault_path" ]]; then
        log_error "Could not resolve vault path from ~/.openclaw/sandbox-profile.toml"
        log_error "Ensure mounts.vault is set in the profile."
        exit 1
    fi

    if [[ ! -d "$vault_path" ]]; then
        log_error "Host vault path does not exist: $vault_path"
        exit 1
    fi

    echo "$vault_path"
}

# Check VM is running
check_vm() {
    if ! limactl list --json 2>/dev/null | jq -e 'if type == "array" then .[] else . end | select(.name == "'"${VM_NAME}"'") | select(.status == "Running")' > /dev/null 2>&1; then
        log_error "VM '${VM_NAME}' is not running."
        exit 1
    fi
}

# Show vault overlay status
show_status() {
    check_vm
    echo ""
    log_info "Vault Overlay Status"
    log_info "===================="
    echo ""

    local file_count
    file_count=$(limactl shell "${VM_NAME}" -- find "${UPPER}" -type f 2>/dev/null | wc -l | tr -d ' ')
    log_info "Files in vault overlay upper: ${file_count}"

    if [[ "$file_count" -gt 0 ]]; then
        echo ""
        limactl shell "${VM_NAME}" -- find "${UPPER}" -type f -printf '%T@ %P\n' 2>/dev/null | sort -rn | head -20 | while read -r _ts path; do
            echo "  ${path}"
        done
    fi
}

# Extract vault overlay upper to staging directory
extract_changes() {
    log_step "Extracting vault overlay changes from VM..."

    STAGING_DIR=$(mktemp -d)

    # Get SSH details
    local ssh_config ssh_host ssh_port ssh_user ssh_key
    ssh_config=$(limactl show-ssh --format=config "${VM_NAME}" 2>/dev/null)
    ssh_host=$(echo "$ssh_config" | grep -E "^\s*Hostname\s+" | head -1 | awk '{print $2}')
    ssh_port=$(echo "$ssh_config" | grep -E "^\s*Port\s+" | head -1 | awk '{print $2}')
    ssh_user=$(echo "$ssh_config" | grep -E "^\s*User\s+" | head -1 | awk '{print $2}')
    ssh_key=$(echo "$ssh_config" | grep -E "^\s*IdentityFile\s+" | head -1 | awk '{print $2}' | tr -d '"')

    # Build source path (with scope if set)
    local source_path="${UPPER}"
    if [[ -n "$SCOPE" ]]; then
        source_path="${UPPER}/${SCOPE}"
    fi

    # Check if source has any files
    local file_count
    file_count=$(limactl shell "${VM_NAME}" -- find "${source_path}" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$file_count" -eq 0 ]]; then
        log_info "No pending vault changes${SCOPE:+ in ${SCOPE}/}."
        exit 0
    fi

    log_info "Found ${file_count} file(s)${SCOPE:+ in ${SCOPE}/}."

    # Create scope subdirectory in staging to preserve path structure
    if [[ -n "$SCOPE" ]]; then
        mkdir -p "${STAGING_DIR}/${SCOPE}"
        rsync -avz --delete \
            -e "ssh -p ${ssh_port} -i ${ssh_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
            "${ssh_user}@${ssh_host}:${source_path}/" \
            "${STAGING_DIR}/${SCOPE}/" \
            2>/dev/null
    else
        rsync -avz --delete \
            -e "ssh -p ${ssh_port} -i ${ssh_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
            "${ssh_user}@${ssh_host}:${source_path}/" \
            "${STAGING_DIR}/" \
            2>/dev/null
    fi

    log_info "Extracted to staging: ${STAGING_DIR}"
}

# Validate: check for secrets, blocked files, size limits
validate_changes() {
    log_step "Validating changes..."
    local failed=0

    # 1. Check for blocked file extensions
    for ext in "${BLOCKED_EXTENSIONS[@]}"; do
        local matches
        matches=$(find "$STAGING_DIR" -name "*${ext}" -type f 2>/dev/null || true)
        if [[ -n "$matches" ]]; then
            log_error "Blocked file extension found: ${ext}"
            echo "$matches" | while read -r f; do
                echo "  - ${f#"$STAGING_DIR"/}"
            done
            failed=1
        fi
    done

    # 2. Check file sizes
    while IFS= read -r -d '' file; do
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        if [[ "$size" -gt "$MAX_FILE_SIZE" ]]; then
            log_warn "Large file ($(( size / 1024 / 1024 ))MB): ${file#"$STAGING_DIR"/}"
        fi
    done < <(find "$STAGING_DIR" -type f -print0)

    # 3. Run gitleaks if available
    if command -v gitleaks >/dev/null 2>&1; then
        log_step "Running gitleaks secret scan..."
        if ! gitleaks detect --source="$STAGING_DIR" --no-git --no-banner 2>/dev/null; then
            log_error "gitleaks found potential secrets! Review and remove before syncing."
            failed=1
        else
            log_info "gitleaks: no secrets detected."
        fi
    else
        log_warn "gitleaks not installed — skipping secret scan."
    fi

    if [[ $failed -ne 0 ]]; then
        log_error "Validation FAILED. Fix issues before syncing."
        exit 1
    fi

    log_info "Validation passed."
}

# Preview changes
preview_changes() {
    log_step "Preview of vault changes to apply:"
    echo ""

    find "$STAGING_DIR" -type f -print0 | sort -z | while IFS= read -r -d '' file; do
        local rel="${file#"$STAGING_DIR"/}"
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "?")
        echo "  ${rel} (${size} bytes)"
    done

    echo ""

    local total_files total_size
    total_files=$(find "$STAGING_DIR" -type f | wc -l | tr -d ' ')
    total_size=$(du -sh "$STAGING_DIR" 2>/dev/null | cut -f1)
    log_info "Total: ${total_files} file(s), ${total_size}"
}

# Apply changes to host vault
apply_changes() {
    local vault_path
    vault_path=$(resolve_vault_path)

    log_step "Applying to: ${vault_path}"

    # Use rsync to sync staging → host vault (preserving directory structure)
    # --ignore-existing prevents overwriting files the user edited on the host
    rsync -av --ignore-existing --exclude='.obsidian/' \
        "${STAGING_DIR}/" \
        "${vault_path}/"

    log_info "Vault changes applied to host."
    log_info "Files should appear in Obsidian shortly (iCloud sync)."
}

# Main
DRY_RUN=false
AUTO_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true ;;
        --auto)     AUTO_MODE=true ;;
        --scope)    SCOPE="${2:-Buildlog}"; shift ;;
        --all)      SCOPE="" ;;
        --status)   show_status; exit 0 ;;
        --help|-h)
            echo "Usage: ./scripts/sync-vault-back.sh [OPTIONS]"
            echo ""
            echo "Syncs cadence-generated files from VM vault overlay back to host."
            echo ""
            echo "Options:"
            echo "  --dry-run         Show what would sync (no changes)"
            echo "  --auto            Skip confirmation prompt"
            echo "  --scope DIR       Limit to subdirectory (default: Buildlog)"
            echo "  --all             Sync everything in overlay upper"
            echo "  --status          Show vault overlay status in VM"
            echo "  --help            Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

echo ""
log_info "Vault Writeback"
log_info "==============="
if [[ -n "$SCOPE" ]]; then
    log_info "Scope: ${SCOPE}/"
else
    log_info "Scope: all files"
fi
echo ""

check_vm
extract_changes
validate_changes
preview_changes

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    log_info "Dry run complete. No changes applied."
    exit 0
fi

if [[ "$AUTO_MODE" != "true" ]]; then
    echo ""
    read -rp "Apply these changes to host vault? (y/N) " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Aborted."
        exit 0
    fi
fi

apply_changes
