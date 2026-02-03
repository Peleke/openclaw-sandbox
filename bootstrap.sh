#!/usr/bin/env bash
#
# bootstrap.sh - One-shot provisioning for OpenClaw sandbox VM
#
# Usage:
#   ./bootstrap.sh --openclaw /path/to/openclaw   # Required: specify openclaw repo
#   ./bootstrap.sh --openclaw ~/Projects/openclaw --vault ~/path/to/vault
#   ./bootstrap.sh --kill                          # Force stop the VM
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="openclaw-sandbox"
LIMA_TEMPLATE="${SCRIPT_DIR}/lima/${VM_NAME}.yaml.tpl"
LIMA_CONFIG="${SCRIPT_DIR}/lima/${VM_NAME}.generated.yaml"

# User-configurable paths (set via flags)
OPENCLAW_PATH=""
VAULT_PATH=""

# VM resource defaults
VM_CPUS="${VM_CPUS:-4}"
VM_MEMORY="${VM_MEMORY:-8GiB}"
VM_DISK="${VM_DISK:-50GiB}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Show usage
usage() {
    cat <<EOF
Usage: ./bootstrap.sh --openclaw PATH [OPTIONS]

Required:
  --openclaw PATH   Path to your openclaw repository clone

Options:
  --vault PATH      Mount an Obsidian vault at /mnt/obsidian (read/write)
                    Example: --vault "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/MyVault"
  --kill            Force stop the VM immediately
  --delete          Delete the VM completely (allows fresh start)
  --help            Show this help message

Environment variables:
  VM_CPUS           Number of CPUs (default: 4)
  VM_MEMORY         Memory allocation (default: 8GiB)
  VM_DISK           Disk size (default: 50GiB)

Examples:
  ./bootstrap.sh --openclaw ~/Projects/openclaw
  ./bootstrap.sh --openclaw ~/Projects/openclaw --vault ~/Documents/Vaults/main
  ./bootstrap.sh --kill
  ./bootstrap.sh --delete
EOF
    exit 0
}

# Expand path (resolve ~ and make absolute)
expand_path() {
    local path="$1"
    # Expand ~
    path="${path/#\~/$HOME}"
    # Make absolute if relative
    if [[ "$path" != /* ]]; then
        path="$(cd "$path" 2>/dev/null && pwd)" || path="$path"
    fi
    echo "$path"
}

# Kill switch - immediately stop the VM
kill_vm() {
    log_warn "Kill switch activated - stopping VM forcefully..."
    if limactl list --json 2>/dev/null | jq -e ".[] | select(.name == \"${VM_NAME}\")" > /dev/null 2>&1; then
        limactl stop --force "${VM_NAME}" 2>/dev/null || true
        log_info "VM '${VM_NAME}' stopped."
    else
        log_info "VM '${VM_NAME}' does not exist."
    fi
    exit 0
}

# Delete the VM completely
delete_vm() {
    log_warn "Deleting VM '${VM_NAME}'..."
    if limactl list --json 2>/dev/null | jq -e ".[] | select(.name == \"${VM_NAME}\")" > /dev/null 2>&1; then
        limactl stop --force "${VM_NAME}" 2>/dev/null || true
        limactl delete "${VM_NAME}" 2>/dev/null || true
        log_info "VM '${VM_NAME}' deleted."
    else
        log_info "VM '${VM_NAME}' does not exist."
    fi
    # Also clean up generated config
    rm -f "$LIMA_CONFIG"
    exit 0
}

# Generate Lima config from template
generate_lima_config() {
    log_step "Generating Lima configuration..."

    local provision_path
    provision_path="$(expand_path "$SCRIPT_DIR")"

    local openclaw_path
    openclaw_path="$(expand_path "$OPENCLAW_PATH")"

    # Validate paths exist
    if [[ ! -d "$openclaw_path" ]]; then
        log_error "OpenClaw path does not exist: $openclaw_path"
        exit 1
    fi

    if [[ ! -d "$provision_path" ]]; then
        log_error "Provision path does not exist: $provision_path"
        exit 1
    fi

    # Build mounts section
    local mounts=""
    local mount_message=""

    # Always mount openclaw repo
    mounts+="  - location: \"${openclaw_path}\""$'\n'
    mounts+="    mountPoint: \"/mnt/openclaw\""$'\n'
    mounts+="    writable: true"$'\n'
    mount_message+="    /mnt/openclaw  -> ${openclaw_path}"$'\n'

    # Always mount provision repo (read-only)
    mounts+="  - location: \"${provision_path}\""$'\n'
    mounts+="    mountPoint: \"/mnt/provision\""$'\n'
    mounts+="    writable: false"$'\n'
    mount_message+="    /mnt/provision -> ${provision_path} (read-only)"$'\n'

    # Optionally mount vault
    if [[ -n "$VAULT_PATH" ]]; then
        local vault_path
        vault_path="$(expand_path "$VAULT_PATH")"

        if [[ ! -d "$vault_path" ]]; then
            log_error "Vault path does not exist: $vault_path"
            exit 1
        fi

        mounts+="  - location: \"${vault_path}\""$'\n'
        mounts+="    mountPoint: \"/mnt/obsidian\""$'\n'
        mounts+="    writable: true"$'\n'
        mount_message+="    /mnt/obsidian  -> ${vault_path}"$'\n'
    fi

    # Generate config from template
    if [[ ! -f "$LIMA_TEMPLATE" ]]; then
        log_error "Template not found: $LIMA_TEMPLATE"
        exit 1
    fi

    # Use sed to replace placeholders
    sed -e "s|{{CPUS}}|${VM_CPUS}|g" \
        -e "s|{{MEMORY}}|${VM_MEMORY}|g" \
        -e "s|{{DISK}}|${VM_DISK}|g" \
        "$LIMA_TEMPLATE" > "$LIMA_CONFIG"

    # Replace mounts section (multi-line, so use awk)
    awk -v mounts="$mounts" '{gsub(/{{MOUNTS}}/, mounts)}1' "$LIMA_CONFIG" > "${LIMA_CONFIG}.tmp"
    mv "${LIMA_CONFIG}.tmp" "$LIMA_CONFIG"

    awk -v msg="$mount_message" '{gsub(/{{MOUNT_MESSAGE}}/, msg)}1' "$LIMA_CONFIG" > "${LIMA_CONFIG}.tmp"
    mv "${LIMA_CONFIG}.tmp" "$LIMA_CONFIG"

    log_info "Generated: $LIMA_CONFIG"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure Homebrew is installed
ensure_homebrew() {
    if ! command_exists brew; then
        log_error "Homebrew is not installed."
        log_info "Install it from https://brew.sh or run:"
        echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi
    log_info "Homebrew found."
}

# Install dependencies from Brewfile
install_deps() {
    log_step "Installing dependencies from Brewfile..."
    if [[ -f "${SCRIPT_DIR}/brew/Brewfile" ]]; then
        brew bundle --file="${SCRIPT_DIR}/brew/Brewfile" --no-lock
        log_info "Dependencies installed."
    else
        log_error "Brewfile not found at ${SCRIPT_DIR}/brew/Brewfile"
        exit 1
    fi
}

# Check if VM exists
vm_exists() {
    limactl list --json 2>/dev/null | jq -e ".[] | select(.name == \"${VM_NAME}\")" > /dev/null 2>&1
}

# Get VM status
vm_status() {
    limactl list --json 2>/dev/null | jq -r ".[] | select(.name == \"${VM_NAME}\") | .status" 2>/dev/null || echo "unknown"
}

# Create or start the Lima VM
ensure_vm() {
    log_step "Ensuring VM is running..."

    if ! vm_exists; then
        log_info "Creating Lima VM '${VM_NAME}'..."
        limactl create --name="${VM_NAME}" "$LIMA_CONFIG"
    else
        log_info "VM '${VM_NAME}' already exists."
        # Check if config changed - warn user
        if [[ -n "$OPENCLAW_PATH" ]] || [[ -n "$VAULT_PATH" ]]; then
            log_warn "VM already exists. Path options only apply to new VMs."
            log_warn "To apply new paths: ./bootstrap.sh --delete && ./bootstrap.sh --openclaw ..."
        fi
    fi

    local status
    status=$(vm_status)

    if [[ "$status" != "Running" ]]; then
        log_info "Starting Lima VM '${VM_NAME}'..."
        limactl start "${VM_NAME}"
    else
        log_info "VM '${VM_NAME}' is already running."
    fi
}

# Get SSH connection details from Lima (robust parsing)
get_ssh_details() {
    # Use limactl show-ssh with config format and parse it
    local ssh_config
    ssh_config=$(limactl show-ssh --format=config "${VM_NAME}" 2>/dev/null)

    SSH_HOST=$(echo "$ssh_config" | grep -E "^\s*HostName" | awk '{print $2}')
    SSH_PORT=$(echo "$ssh_config" | grep -E "^\s*Port" | awk '{print $2}')
    SSH_USER=$(echo "$ssh_config" | grep -E "^\s*User" | awk '{print $2}')
    SSH_KEY=$(echo "$ssh_config" | grep -E "^\s*IdentityFile" | awk '{print $2}' | tr -d '"')

    # Defaults if parsing fails
    SSH_HOST="${SSH_HOST:-127.0.0.1}"
    SSH_PORT="${SSH_PORT:-22}"
    SSH_USER="${SSH_USER:-$(whoami)}"

    if [[ -z "$SSH_KEY" ]]; then
        log_error "Could not determine SSH key from Lima"
        exit 1
    fi
}

# Run Ansible playbook
run_ansible() {
    log_step "Running Ansible playbook..."

    # Get SSH details
    get_ssh_details

    log_info "SSH: ${SSH_USER}@${SSH_HOST}:${SSH_PORT}"

    # Create temporary inventory
    local inventory_file
    inventory_file=$(mktemp)

    cat > "$inventory_file" << EOF
[sandbox]
${VM_NAME} ansible_host=${SSH_HOST} ansible_port=${SSH_PORT} ansible_user=${SSH_USER} ansible_ssh_private_key_file=${SSH_KEY} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

    log_info "Inventory: $inventory_file"

    # Run the playbook
    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i "$inventory_file" \
        "${SCRIPT_DIR}/ansible/playbook.yml" \
        -e "tenant_name=$(whoami)" \
        -e "provision_path=/mnt/provision" \
        -e "openclaw_path=/mnt/openclaw" \
        -e "obsidian_path=/mnt/obsidian"

    local ansible_exit=$?
    rm -f "$inventory_file"

    if [[ $ansible_exit -eq 0 ]]; then
        log_info "Ansible playbook completed successfully."
    else
        log_error "Ansible playbook failed with exit code $ansible_exit"
        exit $ansible_exit
    fi
}

# Verify mounts are accessible
verify_mounts() {
    log_step "Verifying host mounts..."

    local failed=0

    if ! limactl shell "${VM_NAME}" -- test -d /mnt/openclaw; then
        log_warn "Mount /mnt/openclaw not accessible"
        failed=1
    else
        log_info "/mnt/openclaw ✓"
    fi

    if ! limactl shell "${VM_NAME}" -- test -d /mnt/provision; then
        log_warn "Mount /mnt/provision not accessible"
        failed=1
    else
        log_info "/mnt/provision ✓"
    fi

    if [[ -n "$VAULT_PATH" ]]; then
        if ! limactl shell "${VM_NAME}" -- test -d /mnt/obsidian; then
            log_warn "Mount /mnt/obsidian not accessible"
            failed=1
        else
            log_info "/mnt/obsidian ✓"
        fi
    fi

    if [[ $failed -ne 0 ]]; then
        log_error "Some mounts are not accessible. Check Lima configuration."
        exit 1
    fi

    log_info "All mounts verified."
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kill)
                kill_vm
                ;;
            --delete)
                delete_vm
                ;;
            --help|-h)
                usage
                ;;
            --openclaw)
                if [[ -z "${2:-}" ]]; then
                    log_error "--openclaw requires a path argument"
                    exit 1
                fi
                OPENCLAW_PATH="$2"
                shift
                ;;
            --vault)
                if [[ -z "${2:-}" ]]; then
                    log_error "--vault requires a path argument"
                    exit 1
                fi
                VAULT_PATH="$2"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
        shift
    done
}

# Main
main() {
    parse_args "$@"

    echo ""
    log_info "OpenClaw Sandbox Bootstrap"
    log_info "=========================="
    echo ""

    # Check if VM already exists - if so, we don't need --openclaw
    if vm_exists; then
        log_info "VM '${VM_NAME}' already exists, using existing configuration."
    else
        # Require --openclaw for new VM creation
        if [[ -z "$OPENCLAW_PATH" ]]; then
            log_error "--openclaw PATH is required to create a new VM"
            echo ""
            usage
        fi
        generate_lima_config
    fi

    ensure_homebrew
    install_deps
    ensure_vm
    verify_mounts
    run_ansible

    echo ""
    log_info "=========================="
    log_info "Bootstrap complete!"
    echo ""
    log_info "VM '${VM_NAME}' is running."
    log_info "Access via:  limactl shell ${VM_NAME}"
    log_info "Stop with:   ./bootstrap.sh --kill"
    log_info "Delete with: ./bootstrap.sh --delete"

    if [[ -n "$VAULT_PATH" ]]; then
        echo ""
        log_info "Vault mounted at: /mnt/obsidian"
    fi
}

main "$@"
