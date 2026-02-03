#!/usr/bin/env bash
#
# bootstrap.sh - One-shot provisioning for OpenClaw sandbox VM
#
# Usage:
#   ./bootstrap.sh                      # Create/start VM and run Ansible
#   ./bootstrap.sh --vault /path/to/vault  # Mount an Obsidian vault
#   ./bootstrap.sh --kill               # Force stop the VM immediately
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="openclaw-sandbox"
LIMA_TEMPLATE="${SCRIPT_DIR}/lima/${VM_NAME}.yaml"
LIMA_OVERRIDE="${SCRIPT_DIR}/lima/${VM_NAME}.override.yaml"
VAULT_PATH=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Show usage
usage() {
    cat <<EOF
Usage: ./bootstrap.sh [OPTIONS]

Options:
  --vault PATH    Mount an Obsidian vault at /mnt/obsidian (read/write)
                  Example: --vault "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/MyVault"
  --kill          Force stop the VM immediately
  --help          Show this help message

Examples:
  ./bootstrap.sh                           # Start VM without vault mount
  ./bootstrap.sh --vault ~/Documents/vault # Start VM with local vault
  ./bootstrap.sh --kill                    # Stop the VM
EOF
    exit 0
}

# Kill switch - immediately stop the VM
kill_vm() {
    log_warn "Kill switch activated - stopping VM forcefully..."
    if limactl list --json 2>/dev/null | grep -q "\"name\":\"${VM_NAME}\""; then
        limactl stop --force "${VM_NAME}" 2>/dev/null || true
        log_info "VM '${VM_NAME}' stopped."
    else
        log_info "VM '${VM_NAME}' does not exist or is already stopped."
    fi
    exit 0
}

# Generate Lima override file for vault mount
generate_vault_override() {
    local vault_path="$1"

    # Expand ~ to actual home directory
    vault_path="${vault_path/#\~/$HOME}"

    if [[ ! -d "$vault_path" ]]; then
        log_error "Vault path does not exist: $vault_path"
        exit 1
    fi

    log_info "Generating vault mount override for: $vault_path"

    cat > "$LIMA_OVERRIDE" <<EOF
# Auto-generated vault mount override
# Created by bootstrap.sh --vault
mounts:
  - location: "${vault_path}"
    mountPoint: "/mnt/obsidian"
    writable: true
EOF

    log_info "Override file created: $LIMA_OVERRIDE"
}

# Clean up override file
cleanup_override() {
    if [[ -f "$LIMA_OVERRIDE" ]]; then
        rm -f "$LIMA_OVERRIDE"
    fi
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
    log_info "Installing dependencies from Brewfile..."
    if [[ -f "${SCRIPT_DIR}/brew/Brewfile" ]]; then
        brew bundle --file="${SCRIPT_DIR}/brew/Brewfile" --no-lock
        log_info "Dependencies installed."
    else
        log_error "Brewfile not found at ${SCRIPT_DIR}/brew/Brewfile"
        exit 1
    fi
}

# Create or start the Lima VM
ensure_vm() {
    if ! limactl list --json 2>/dev/null | grep -q "\"name\":\"${VM_NAME}\""; then
        log_info "Creating Lima VM '${VM_NAME}'..."

        # Use override file if it exists (for vault mount)
        if [[ -f "$LIMA_OVERRIDE" ]]; then
            log_info "Applying vault mount override..."
            limactl create --name="${VM_NAME}" "${LIMA_TEMPLATE}" "${LIMA_OVERRIDE}"
        else
            limactl create --name="${VM_NAME}" "${LIMA_TEMPLATE}"
        fi
    else
        # VM already exists - warn if trying to add vault to existing VM
        if [[ -n "$VAULT_PATH" ]]; then
            log_warn "VM already exists. To change mounts, delete and recreate:"
            log_warn "  limactl delete ${VM_NAME}"
            log_warn "  ./bootstrap.sh --vault '${VAULT_PATH}'"
        fi
    fi

    local status
    status=$(limactl list --json 2>/dev/null | grep -A5 "\"name\":\"${VM_NAME}\"" | grep '"status"' | cut -d'"' -f4 || echo "unknown")

    if [[ "$status" != "Running" ]]; then
        log_info "Starting Lima VM '${VM_NAME}'..."
        limactl start "${VM_NAME}"
    else
        log_info "VM '${VM_NAME}' is already running."
    fi
}

# Get the VM's SSH config for Ansible
get_vm_ssh_config() {
    limactl show-ssh --format=config "${VM_NAME}"
}

# Run Ansible playbook
run_ansible() {
    log_info "Running Ansible playbook..."

    # Create temporary inventory with Lima SSH config
    local inventory_file
    inventory_file=$(mktemp)

    # Get SSH details from Lima
    local ssh_host ssh_port ssh_user ssh_key
    ssh_host="127.0.0.1"
    ssh_port=$(limactl show-ssh --format=args "${VM_NAME}" 2>/dev/null | grep -oE '\-p [0-9]+' | awk '{print $2}')
    ssh_user=$(limactl show-ssh --format=args "${VM_NAME}" 2>/dev/null | grep -oE '[a-z]+@' | tr -d '@')
    ssh_key=$(limactl show-ssh --format=args "${VM_NAME}" 2>/dev/null | grep -oE '\-i [^ ]+' | awk '{print $2}')

    cat > "$inventory_file" << EOF
[sandbox]
${VM_NAME} ansible_host=${ssh_host} ansible_port=${ssh_port} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

    # Run the playbook
    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i "$inventory_file" \
        "${SCRIPT_DIR}/ansible/playbook.yml" \
        -e "tenant_name=peleke" \
        -e "provision_path=/mnt/provision" \
        -e "openclaw_path=/mnt/openclaw" \
        -e "obsidian_path=/mnt/obsidian"

    rm -f "$inventory_file"
    log_info "Ansible playbook completed."
}

# Verify mounts are accessible
verify_mounts() {
    log_info "Verifying host mounts..."

    local failed=0

    # Only check obsidian mount if vault was specified
    if [[ -n "$VAULT_PATH" ]]; then
        if ! limactl shell "${VM_NAME}" -- test -d /mnt/obsidian; then
            log_warn "Mount /mnt/obsidian not accessible"
            failed=1
        fi
    fi

    if ! limactl shell "${VM_NAME}" -- test -d /mnt/openclaw; then
        log_warn "Mount /mnt/openclaw not accessible"
        failed=1
    fi

    if ! limactl shell "${VM_NAME}" -- test -d /mnt/provision; then
        log_warn "Mount /mnt/provision not accessible"
        failed=1
    fi

    if [[ $failed -eq 0 ]]; then
        log_info "All mounts verified."
    else
        log_warn "Some mounts may not be accessible. Check Lima configuration."
    fi
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kill)
                kill_vm
                ;;
            --help|-h)
                usage
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

    log_info "OpenClaw Sandbox Bootstrap"
    log_info "=========================="

    # Generate vault override if specified
    if [[ -n "$VAULT_PATH" ]]; then
        generate_vault_override "$VAULT_PATH"
    fi

    ensure_homebrew
    install_deps
    ensure_vm
    verify_mounts
    run_ansible

    # Clean up override file after VM creation
    cleanup_override

    log_info "=========================="
    log_info "Bootstrap complete!"
    log_info ""
    log_info "VM '${VM_NAME}' is running."
    log_info "Access via: limactl shell ${VM_NAME}"
    log_info "Stop with:  ./bootstrap.sh --kill"

    if [[ -n "$VAULT_PATH" ]]; then
        log_info "Vault mounted at: /mnt/obsidian"
    else
        log_info ""
        log_info "No vault mounted. To add one, recreate the VM:"
        log_info "  limactl delete ${VM_NAME}"
        log_info "  ./bootstrap.sh --vault /path/to/your/vault"
    fi
}

main "$@"
