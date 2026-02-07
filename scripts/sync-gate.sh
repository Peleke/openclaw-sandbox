#!/usr/bin/env bash
#
# sync-gate.sh — Gated sync from VM overlay to host
#
# Extracts pending changes from the VM's overlay upper layer,
# validates them (secret scan, path allowlist, size check),
# shows a preview, and applies on approval.
#
# Usage:
#   ./scripts/sync-gate.sh                    # Interactive: validate, preview, apply
#   ./scripts/sync-gate.sh --dry-run          # Just show what would sync
#   ./scripts/sync-gate.sh --auto             # Skip confirmation (CI/automation)
#   ./scripts/sync-gate.sh --reset            # Discard all overlay writes
#   ./scripts/sync-gate.sh --status           # Show overlay status in VM
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VM_NAME="openclaw-sandbox"

# Overlay paths in VM
UPPER="/var/lib/openclaw/overlay/openclaw/upper"
WORKSPACE="/workspace"

# Validation settings
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

log_info()  { echo -e "${GREEN}[SYNC]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

cleanup() {
    if [[ -n "${STAGING_DIR:-}" && -d "${STAGING_DIR:-}" ]]; then
        rm -rf "$STAGING_DIR"
    fi
}
trap cleanup EXIT

# Check VM is running
check_vm() {
    if ! limactl list --json 2>/dev/null | jq -e 'if type == "array" then .[] else . end | select(.name == "'"${VM_NAME}"'") | select(.status == "Running")' > /dev/null 2>&1; then
        log_error "VM '${VM_NAME}' is not running."
        exit 1
    fi
}

# Show overlay status
show_status() {
    check_vm
    limactl shell "${VM_NAME}" -- overlay-status
}

# Reset overlay (discard all writes)
reset_overlay() {
    check_vm
    limactl shell "${VM_NAME}" -- sudo overlay-reset
}

# Extract overlay upper to staging directory
extract_changes() {
    log_step "Extracting pending changes from VM overlay..."

    STAGING_DIR=$(mktemp -d)

    # Copy upper directory contents to host staging area
    # Use rsync over SSH for efficiency
    local ssh_config
    ssh_config=$(limactl show-ssh --format=config "${VM_NAME}" 2>/dev/null)
    local ssh_host ssh_port ssh_user ssh_key
    ssh_host=$(echo "$ssh_config" | grep -E "^\s*Hostname\s+" | head -1 | awk '{print $2}')
    ssh_port=$(echo "$ssh_config" | grep -E "^\s*Port\s+" | head -1 | awk '{print $2}')
    ssh_user=$(echo "$ssh_config" | grep -E "^\s*User\s+" | head -1 | awk '{print $2}')
    ssh_key=$(echo "$ssh_config" | grep -E "^\s*IdentityFile\s+" | head -1 | awk '{print $2}' | tr -d '"')

    # Check if upper has any files
    local file_count
    file_count=$(limactl shell "${VM_NAME}" -- find "${UPPER}" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$file_count" -eq 0 ]]; then
        log_info "No pending changes in overlay."
        exit 0
    fi

    log_info "Found ${file_count} modified files."

    rsync -avz --delete \
        -e "ssh -p ${ssh_port} -i ${ssh_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
        "${ssh_user}@${ssh_host}:${UPPER}/" \
        "${STAGING_DIR}/" \
        2>/dev/null

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
                echo "  - ${f#$STAGING_DIR/}"
            done
            failed=1
        fi
    done

    # 2. Check file sizes
    while IFS= read -r -d '' file; do
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        if [[ "$size" -gt "$MAX_FILE_SIZE" ]]; then
            log_warn "Large file ($(( size / 1024 / 1024 ))MB): ${file#$STAGING_DIR/}"
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
        log_warn "Install with: brew install gitleaks"
    fi

    # 4. Executable / binary detection
    local binary_warnings=0
    while IFS= read -r -d '' file; do
        local filetype
        filetype=$(file -b "$file" 2>/dev/null || echo "unknown")
        case "$filetype" in
            *ELF*|*Mach-O*|*executable*|*"shared object"*)
                log_warn "Binary/executable: ${file#$STAGING_DIR/} ($filetype)"
                binary_warnings=$((binary_warnings + 1))
                ;;
        esac
    done < <(find "$STAGING_DIR" -type f -print0)

    if [[ "$binary_warnings" -gt 0 ]]; then
        log_warn "${binary_warnings} binary/executable file(s) detected — review before applying."
    fi

    # 5. Extension allowlist (informational warnings only)
    local EXPECTED_EXTENSIONS=(.ts .js .json .md .yml .yaml .sh .css .html .svg .txt .map .mjs .cjs .jsx .tsx .lock .toml .cfg .ini .py .rs .go)
    while IFS= read -r -d '' file; do
        local ext=".${file##*.}"
        local basename_file
        basename_file=$(basename "$file")
        # Skip files with no extension (e.g. Makefile, Dockerfile)
        if [[ "$ext" == ".$basename_file" ]]; then
            continue
        fi
        local expected=false
        for e in "${EXPECTED_EXTENSIONS[@]}"; do
            if [[ "$ext" == "$e" ]]; then
                expected=true
                break
            fi
        done
        if [[ "$expected" == "false" ]]; then
            log_warn "Unexpected extension: ${file#$STAGING_DIR/} (${ext})"
        fi
    done < <(find "$STAGING_DIR" -type f -print0)

    if [[ $failed -ne 0 ]]; then
        log_error "Validation FAILED. Fix issues before syncing."
        exit 1
    fi

    log_info "Validation passed."
}

# Preview changes
preview_changes() {
    log_step "Preview of changes to apply:"
    echo ""

    find "$STAGING_DIR" -type f -print0 | sort -z | while IFS= read -r -d '' file; do
        local rel="${file#$STAGING_DIR/}"
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "?")
        echo "  ${rel} (${size} bytes)"
    done

    echo ""

    local total_files total_size
    total_files=$(find "$STAGING_DIR" -type f | wc -l | tr -d ' ')
    total_size=$(du -sh "$STAGING_DIR" 2>/dev/null | cut -f1)
    log_info "Total: ${total_files} files, ${total_size}"
}

# Apply changes to host openclaw directory
apply_changes() {
    # Find the openclaw path from the Lima config
    local openclaw_host_path
    if [[ -f "${PROJECT_DIR}/lima/${VM_NAME}.generated.yaml" ]]; then
        openclaw_host_path=$(grep -A1 'mountPoint: "/mnt/openclaw"' "${PROJECT_DIR}/lima/${VM_NAME}.generated.yaml" | head -1 | sed 's/.*location: "\(.*\)"/\1/' | tr -d '"' | tr -d ' ')
        # Handle the case where location is on the previous line
        if [[ -z "$openclaw_host_path" || "$openclaw_host_path" == *"mountPoint"* ]]; then
            openclaw_host_path=$(grep -B1 'mountPoint: "/mnt/openclaw"' "${PROJECT_DIR}/lima/${VM_NAME}.generated.yaml" | head -1 | sed 's/.*location: "\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' ' | sed 's/^-//')
        fi
    fi

    if [[ -z "${openclaw_host_path:-}" || ! -d "${openclaw_host_path:-}" ]]; then
        log_error "Could not determine host openclaw path from Lima config."
        log_error "Manually copy from: ${STAGING_DIR}"
        exit 1
    fi

    log_step "Applying to: ${openclaw_host_path}"

    rsync -av --ignore-existing "${STAGING_DIR}/" "${openclaw_host_path}/"

    log_info "Changes applied to host."
    log_info "Review with: cd ${openclaw_host_path} && git diff"
}

# Main
DRY_RUN=false
AUTO_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true ;;
        --auto)     AUTO_MODE=true ;;
        --status)   show_status; exit 0 ;;
        --reset)    reset_overlay; exit 0 ;;
        --help|-h)
            echo "Usage: ./scripts/sync-gate.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run   Show what would sync (no changes)"
            echo "  --auto      Skip confirmation prompt"
            echo "  --status    Show overlay status in VM"
            echo "  --reset     Discard all overlay writes"
            echo "  --help      Show this help"
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
log_info "OpenClaw Sync Gate"
log_info "=================="
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
    read -rp "Apply these changes to host? (y/N) " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Aborted."
        exit 0
    fi
fi

apply_changes
