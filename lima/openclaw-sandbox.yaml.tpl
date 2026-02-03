# Lima VM configuration for OpenClaw Sandbox
# NOTE: This is a TEMPLATE. bootstrap.sh generates the actual config.
# https://lima-vm.io/docs/reference/yaml/

# VM identification
vmType: "vz"  # Virtualization.framework (faster on Apple Silicon)

# Base image - Ubuntu 24.04 LTS (Noble Numbat)
images:
  - location: "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    arch: "x86_64"
  - location: "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img"
    arch: "aarch64"

# Resource limits
cpus: {{CPUS}}
memory: "{{MEMORY}}"
disk: "{{DISK}}"

# Rosetta for x86_64 emulation on Apple Silicon
rosetta:
  enabled: true
  binfmt: true

# SSH configuration
ssh:
  localPort: 0  # Auto-assign port
  loadDotSSHPubKeys: true

# Host mounts - paths are expanded by bootstrap.sh
mounts:
{{MOUNTS}}

# Network configuration
networks:
  - lima: shared

# Containerd (not needed for now)
containerd:
  system: false
  user: false

# Provisioning scripts run on first boot
provision:
  - mode: system
    script: |
      #!/bin/bash
      set -eux -o pipefail

      # Update package lists
      apt-get update

      # Install essential packages
      apt-get install -y \
        curl \
        git \
        jq \
        build-essential \
        python3 \
        python3-pip \
        ca-certificates \
        gnupg

      # Clean up
      apt-get clean
      rm -rf /var/lib/apt/lists/*

  - mode: user
    script: |
      #!/bin/bash
      set -eux -o pipefail

      # Create standard directories
      mkdir -p ~/.openclaw
      mkdir -p ~/.local/bin

      echo "OpenClaw sandbox VM provisioned successfully"

# Port forwarding (gateway default port)
portForwards:
  - guestPort: 18789
    hostPort: 18789
    proto: tcp

# Environment variables available in the VM
env:
  OPENCLAW_SANDBOX: "true"

# Message shown after VM starts
message: |
  OpenClaw Sandbox VM is ready!

  Mounts:
{{MOUNT_MESSAGE}}

  Gateway port 18789 is forwarded to host.

  To stop: limactl stop openclaw-sandbox
  To kill: ./bootstrap.sh --kill
