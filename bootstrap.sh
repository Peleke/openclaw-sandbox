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
CONFIG_PATH=""       # Optional: mount host ~/.openclaw for auth/config
AGENT_DATA_PATH=""   # Optional: mount host ~/.openclaw/agents for persistent agent data
SECRETS_PATH=""      # Optional: mount a secrets .env file

# Overlay mode flags
YOLO_MODE=false      # --yolo: overlay + auto-sync timer
YOLO_UNSAFE=false    # --yolo-unsafe: no overlay, rw mounts (legacy)

# Docker sandbox flag
DOCKER_ENABLED=true  # --no-docker: skip Docker installation

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

Required (for new VM):
  --openclaw PATH   Path to your openclaw repository clone

Options:
  --secrets PATH    Mount a secrets .env file into VM (recommended for dev)
                    Example: --secrets ~/.openclaw-secrets.env
  --config PATH     Mount host openclaw config at ~/.openclaw in VM (for auth/creds)
                    Example: --config ~/.openclaw
  --agent-data PATH Mount host agent data dir for persistent green/learning DBs
                    Example: --agent-data ~/.openclaw/agents
  --vault PATH      Mount an Obsidian vault at /mnt/obsidian (read/write)
                    Example: --vault "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/MyVault"
  --no-docker       Skip Docker + sandbox installation (lighter VM)
  --yolo            Enable YOLO mode: overlay ON + auto-sync timer (30s)
                    Writes still go to overlay but auto-sync back to host.
  --yolo-unsafe     Disable overlay entirely: mount host dirs read-write (legacy).
                    *** Requires VM recreate (--delete first) ***
  -e KEY=VALUE      Pass extra variable to Ansible (can be used multiple times)
                    Example: -e "secrets_anthropic_api_key=sk-ant-xxx"
                    Example: -e "secrets_github_token=ghp_xxx"  (GitHub CLI token)
                    Example: -e "telegram_user_id=123456789"  (pre-approve Telegram user)
  --kill            Force stop the VM immediately
  --delete          Delete the VM completely (allows fresh start)
  --shell           Open interactive shell in the VM
  --onboard         Run interactive openclaw onboard in the VM
  --help            Show this help message

Filesystem isolation (default):
  Host mounts are READ-ONLY. All writes go to an OverlayFS upper layer.
  Use scripts/sync-gate.sh to push approved changes back to host.
  --yolo enables auto-sync (convenience), --yolo-unsafe disables overlay.

Environment variables:
  VM_CPUS           Number of CPUs (default: 4)
  VM_MEMORY         Memory allocation (default: 8GiB)
  VM_DISK           Disk size (default: 50GiB)

Examples:
  ./bootstrap.sh --openclaw ~/Projects/openclaw
  ./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
  ./bootstrap.sh --openclaw ~/Projects/openclaw --config ~/.openclaw --agent-data ~/.openclaw/agents
  ./bootstrap.sh --openclaw ~/Projects/openclaw --vault ~/Documents/Vaults/main
  ./bootstrap.sh --openclaw ../openclaw -e "secrets_anthropic_api_key=sk-ant-xxx"
  ./bootstrap.sh --openclaw ../openclaw --yolo          # Auto-sync mode
  ./bootstrap.sh --openclaw ../openclaw --yolo-unsafe   # Legacy rw mounts
  ./bootstrap.sh --shell                    # Open VM shell
  ./bootstrap.sh --onboard                  # Run interactive onboard
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

# Generate Lima config directly (no template substitution issues)
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

    # Validate vault path if specified
    local vault_path=""
    if [[ -n "$VAULT_PATH" ]]; then
        vault_path="$(expand_path "$VAULT_PATH")"
        if [[ ! -d "$vault_path" ]]; then
            log_error "Vault path does not exist: $vault_path"
            exit 1
        fi
    fi

    # Validate config path if specified (for auth/credentials)
    local config_path=""
    if [[ -n "$CONFIG_PATH" ]]; then
        config_path="$(expand_path "$CONFIG_PATH")"
        if [[ ! -d "$config_path" ]]; then
            log_error "Config path does not exist: $config_path"
            log_info "If you don't have an existing config, omit --config and run:"
            log_info "  ./bootstrap.sh --onboard"
            exit 1
        fi
    fi

    # Validate agent-data path if specified
    local agent_data_path=""
    if [[ -n "$AGENT_DATA_PATH" ]]; then
        agent_data_path="$(expand_path "$AGENT_DATA_PATH")"
        if [[ ! -d "$agent_data_path" ]]; then
            log_warn "Agent data path does not exist, creating: $agent_data_path"
            mkdir -p "$agent_data_path"
        fi
    fi

    # Validate secrets path if specified
    local secrets_path=""
    if [[ -n "$SECRETS_PATH" ]]; then
        secrets_path="$(expand_path "$SECRETS_PATH")"
        if [[ ! -f "$secrets_path" ]]; then
            log_error "Secrets file does not exist: $secrets_path"
            log_info "Create a .env file with your secrets, e.g.:"
            log_info "  ANTHROPIC_API_KEY=sk-ant-xxx"
            log_info "  OPENCLAW_GATEWAY_PASSWORD=mypass"
            exit 1
        fi
    fi

    # Determine mount writability based on overlay mode
    local openclaw_writable="false"
    local vault_writable="false"
    local config_writable="false"
    if [[ "$YOLO_UNSAFE" == "true" ]]; then
        openclaw_writable="true"
        vault_writable="true"
        config_writable="true"
        log_warn "YOLO-UNSAFE: All host mounts will be READ-WRITE (no overlay)"
    else
        log_info "Secure mode: host mounts will be READ-ONLY (overlay provides /workspace)"
    fi

    # Generate the config file directly
    cat > "$LIMA_CONFIG" << EOF
# Lima VM configuration for OpenClaw Sandbox
# AUTO-GENERATED by bootstrap.sh - do not edit manually
# https://lima-vm.io/docs/reference/yaml/

vmType: "vz"

images:
  - location: "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    arch: "x86_64"
  - location: "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img"
    arch: "aarch64"

cpus: ${VM_CPUS}
memory: "${VM_MEMORY}"
disk: "${VM_DISK}"

ssh:
  localPort: 0
  loadDotSSHPubKeys: true

# Rosetta for x86_64 emulation on Apple Silicon
vmOpts:
  vz:
    rosetta:
      enabled: true
      binfmt: true

mounts:
  - location: "${openclaw_path}"
    mountPoint: "/mnt/openclaw"
    writable: ${openclaw_writable}
  - location: "${provision_path}"
    mountPoint: "/mnt/provision"
    writable: false
EOF

    # Add vault mount if specified
    if [[ -n "$vault_path" ]]; then
        cat >> "$LIMA_CONFIG" << EOF
  - location: "${vault_path}"
    mountPoint: "/mnt/obsidian"
    writable: ${vault_writable}
EOF
    fi

    # Add config mount if specified (maps to /mnt/openclaw-config in VM)
    # The gateway role will copy config files from this mount into ~/.openclaw/
    if [[ -n "$config_path" ]]; then
        cat >> "$LIMA_CONFIG" << EOF
  - location: "${config_path}"
    mountPoint: "/mnt/openclaw-config"
    writable: ${config_writable}
EOF
    fi

    # Add agent-data mount if specified (maps to /mnt/openclaw-agents in VM)
    # Always writable — contains only SQLite DBs (green.db, learning.db)
    if [[ -n "$agent_data_path" ]]; then
        cat >> "$LIMA_CONFIG" << EOF
  - location: "${agent_data_path}"
    mountPoint: "/mnt/openclaw-agents"
    writable: true
EOF
    fi

    # Add secrets file mount if specified
    # Lima requires directory mounts, so we mount the parent directory
    # and the Ansible role will look for the specific file
    if [[ -n "$secrets_path" ]]; then
        local secrets_dir
        local secrets_filename
        secrets_dir="$(dirname "$secrets_path")"
        secrets_filename="$(basename "$secrets_path")"
        cat >> "$LIMA_CONFIG" << EOF
  - location: "${secrets_dir}"
    mountPoint: "/mnt/secrets"
    writable: false
EOF
    fi

    # Continue with rest of config
    cat >> "$LIMA_CONFIG" << 'EOF'

# Note: Using default user-mode networking (no socket_vmnet required)
# VM can access internet, host can access VM via port forwards

containerd:
  system: false
  user: false

provision:
  - mode: system
    script: |
      #!/bin/bash
      set -eux -o pipefail
      apt-get update
      apt-get install -y \
        curl \
        git \
        jq \
        build-essential \
        python3 \
        python3-pip \
        ca-certificates \
        gnupg
      apt-get clean
      rm -rf /var/lib/apt/lists/*

  - mode: user
    script: |
      #!/bin/bash
      set -eux -o pipefail
      mkdir -p ~/.openclaw
      mkdir -p ~/.local/bin
      echo "OpenClaw sandbox VM provisioned successfully"

portForwards:
  - guestPort: 18789
    hostPort: 18789
    proto: tcp

env:
  OPENCLAW_SANDBOX: "true"

message: |
  OpenClaw Sandbox VM is ready!

  Gateway port 18789 is forwarded to host.

  To stop: limactl stop openclaw-sandbox
  To kill: ./bootstrap.sh --kill
EOF

    log_info "Generated: $LIMA_CONFIG"
    log_info "Mounts:"
    local openclaw_mode="read-only + overlay"
    [[ "$openclaw_writable" == "true" ]] && openclaw_mode="read-write (no overlay)"
    log_info "  /mnt/openclaw  -> $openclaw_path ($openclaw_mode)"
    log_info "  /mnt/provision -> $provision_path (read-only)"
    if [[ -n "$vault_path" ]]; then
        local vault_mode="read-only + overlay"
        [[ "$vault_writable" == "true" ]] && vault_mode="read-write (no overlay)"
        log_info "  /mnt/obsidian  -> $vault_path ($vault_mode)"
    fi
    if [[ -n "$config_path" ]]; then
        local config_mode="read-only"
        [[ "$config_writable" == "true" ]] && config_mode="read-write"
        log_info "  /mnt/openclaw-config -> $config_path ($config_mode)"
    fi
    if [[ -n "$agent_data_path" ]]; then
        log_info "  /mnt/openclaw-agents -> $agent_data_path (read-write, persistent)"
    fi
    if [[ -n "$secrets_path" ]]; then
        log_info "  /mnt/secrets -> $(dirname "$secrets_path") (secrets dir, read-only)"
        log_info "    Secrets file: $(basename "$secrets_path")"
    fi
    if [[ "$YOLO_UNSAFE" != "true" ]]; then
        log_info "  /workspace     -> OverlayFS merge (services run here)"
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
    log_step "Installing dependencies from Brewfile..."
    if [[ -f "${SCRIPT_DIR}/brew/Brewfile" ]]; then
        brew bundle --file="${SCRIPT_DIR}/brew/Brewfile"
        log_info "Dependencies installed."
    else
        log_error "Brewfile not found at ${SCRIPT_DIR}/brew/Brewfile"
        exit 1
    fi

    # Install Ansible collections
    if [[ -f "${SCRIPT_DIR}/ansible/requirements.yml" ]]; then
        log_step "Installing Ansible collections..."
        ansible-galaxy collection install -r "${SCRIPT_DIR}/ansible/requirements.yml" --force-with-deps >/dev/null 2>&1 || true
    fi
}

# Check if VM exists
vm_exists() {
    # Lima outputs single object (not array) when one VM, or array when multiple
    # Use jq slurp to normalize, then search
    limactl list --json 2>/dev/null | jq -e "if type == \"array\" then .[] else . end | select(.name == \"${VM_NAME}\")" > /dev/null 2>&1
}

# Get VM status
vm_status() {
    limactl list --json 2>/dev/null | jq -r "if type == \"array\" then .[] else . end | select(.name == \"${VM_NAME}\") | .status" 2>/dev/null || echo "unknown"
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

    # Parse each field carefully (handle multiple IdentityFile lines)
    SSH_HOST=$(echo "$ssh_config" | grep -E "^\s*Hostname\s+" | head -1 | awk '{print $2}')
    SSH_PORT=$(echo "$ssh_config" | grep -E "^\s*Port\s+" | head -1 | awk '{print $2}')
    SSH_USER=$(echo "$ssh_config" | grep -E "^\s*User\s+" | head -1 | awk '{print $2}')
    # Get the first (Lima-specific) identity file
    SSH_KEY=$(echo "$ssh_config" | grep -E "^\s*IdentityFile\s+" | head -1 | awk '{print $2}' | tr -d '"')

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

    # Determine secrets filename if secrets path is set
    local secrets_filename=""
    if [[ -n "$SECRETS_PATH" ]]; then
        secrets_filename="$(basename "$(expand_path "$SECRETS_PATH")")"
    fi

    # Run the playbook
    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i "$inventory_file" \
        "${SCRIPT_DIR}/ansible/playbook.yml" \
        -e "tenant_name=$(whoami)" \
        -e "provision_path=/mnt/provision" \
        -e "openclaw_path=/mnt/openclaw" \
        -e "obsidian_path=/mnt/obsidian" \
        -e "secrets_filename=${secrets_filename}" \
        -e "overlay_yolo_mode=${YOLO_MODE}" \
        -e "overlay_yolo_unsafe=${YOLO_UNSAFE}" \
        -e "docker_enabled=${DOCKER_ENABLED}" \
        -e "agent_data_mount=${AGENT_DATA_PATH:+/mnt/openclaw-agents}" \
        ${ANSIBLE_EXTRA_VARS[@]+"${ANSIBLE_EXTRA_VARS[@]}"}

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

    if [[ -n "$AGENT_DATA_PATH" ]]; then
        if ! limactl shell "${VM_NAME}" -- test -d /mnt/openclaw-agents; then
            log_warn "Mount /mnt/openclaw-agents not accessible"
            failed=1
        else
            log_info "/mnt/openclaw-agents ✓"
        fi
    fi

    if [[ $failed -ne 0 ]]; then
        log_error "Some mounts are not accessible. Check Lima configuration."
        exit 1
    fi

    log_info "All mounts verified."

    # Note: /workspace overlay mount is created by the Ansible overlay role,
    # not by Lima. It will be verified after Ansible runs.
    if [[ "$YOLO_UNSAFE" != "true" ]]; then
        log_info "Overlay /workspace will be set up by Ansible."
    fi
}

# Open interactive shell in VM
open_shell() {
    if ! vm_exists; then
        log_error "VM does not exist. Run bootstrap first."
        exit 1
    fi
    if [[ "$(vm_status)" != "Running" ]]; then
        log_info "Starting VM..."
        limactl start "${VM_NAME}"
    fi
    log_info "Opening shell in VM..."
    exec limactl shell "${VM_NAME}"
}

# Run interactive onboard in VM
run_onboard() {
    if ! vm_exists; then
        log_error "VM does not exist. Run bootstrap first."
        exit 1
    fi
    if [[ "$(vm_status)" != "Running" ]]; then
        log_info "Starting VM..."
        limactl start "${VM_NAME}"
    fi
    log_info "Running openclaw onboard..."
    log_info "This is interactive - follow the prompts."
    echo ""
    # Run onboard interactively (needs TTY)
    # Use /workspace if overlay is mounted, fall back to /mnt/openclaw
    exec limactl shell "${VM_NAME}" -- bash -c 'cd "$(if mountpoint -q /workspace 2>/dev/null; then echo /workspace; else echo /mnt/openclaw; fi)" && node dist/index.js onboard'
}

# Extra Ansible variables (collected via -e flags)
ANSIBLE_EXTRA_VARS=()

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
            --shell)
                open_shell
                ;;
            --onboard)
                run_onboard
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
            --config)
                if [[ -z "${2:-}" ]]; then
                    log_error "--config requires a path argument"
                    exit 1
                fi
                CONFIG_PATH="$2"
                shift
                ;;
            --agent-data)
                if [[ -z "${2:-}" ]]; then
                    log_error "--agent-data requires a path argument"
                    exit 1
                fi
                AGENT_DATA_PATH="$2"
                shift
                ;;
            --secrets)
                if [[ -z "${2:-}" ]]; then
                    log_error "--secrets requires a path argument"
                    exit 1
                fi
                SECRETS_PATH="$2"
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
            --no-docker)
                DOCKER_ENABLED=false
                ;;
            --yolo)
                YOLO_MODE=true
                ;;
            --yolo-unsafe)
                YOLO_UNSAFE=true
                ;;
            -e)
                if [[ -z "${2:-}" ]]; then
                    log_error "-e requires a KEY=VALUE argument"
                    exit 1
                fi
                ANSIBLE_EXTRA_VARS+=("-e" "$2")
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
        if [[ -n "$OPENCLAW_PATH" ]]; then
            log_warn "Ignoring --openclaw (VM already exists)"
            log_warn "To change paths: ./bootstrap.sh --delete && ./bootstrap.sh --openclaw ..."
        fi
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

    if [[ "$YOLO_UNSAFE" == "true" ]]; then
        echo ""
        log_warn "YOLO-UNSAFE mode: no overlay, host mounts are writable."
        log_warn "Agent writes go DIRECTLY to host filesystem."
    elif [[ "$YOLO_MODE" == "true" ]]; then
        echo ""
        log_info "YOLO mode: overlay active + auto-sync every 30s."
        log_info "Sync to host: scripts/sync-gate.sh (or wait for timer)"
    else
        echo ""
        log_info "Secure mode: overlay active, host mounts are READ-ONLY."
        log_info "Services run from: /workspace"
        log_info "Sync to host: scripts/sync-gate.sh"
    fi

    echo ""
    log_info "Telegram: dmPolicy=pairing (unknown senders get a pairing code)"
    log_info "  Pre-approve your ID: -e \"telegram_user_id=YOUR_ID\""
    log_info "  Approve a code:      limactl shell ${VM_NAME} -- claw pair approve <CODE>"
}

main "$@"
