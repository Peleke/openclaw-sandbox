# Architecture Overview

OpenClaw Sandbox runs AI agents inside a hardened Linux VM with strict filesystem isolation, network containment, and secure secrets handling. The architecture uses three nested layers -- macOS host, Lima VM, and Docker containers -- each adding a boundary between the agent and your data.

![Architecture](../diagrams/architecture.svg)

## The Three-Layer Model

### Layer 1: macOS Host

The host machine runs the **Python CLI** (`sandbox` command) or `bootstrap.sh`, which orchestrates everything:

1. **Installs dependencies** from the Brewfile (Lima, Ansible, jq, gitleaks)
2. **Generates a Lima YAML config** programmatically (no template file -- the config is built directly in bash with `cat` heredocs)
3. **Creates and starts the Lima VM** with `limactl create` / `limactl start`
4. **Verifies host mounts** are accessible inside the VM
5. **Runs the Ansible playbook** over SSH to provision all services

The Python CLI (`sandbox up`, `sandbox status`, `sandbox ssh`, etc.) is the recommended interface. It wraps `bootstrap.sh` with profile-based configuration and an interactive setup wizard (`sandbox init`). An **MCP server** (`sandbox-mcp`) is also available for LLM agents to manage the sandbox programmatically via FastMCP over stdio.

The host also provides the sync-gate exit path (`scripts/sync-gate.sh`) for getting approved changes back from the VM overlay.

### Layer 2: Lima VM (Ubuntu 24.04)

A [Lima](https://lima-vm.io/) virtual machine running Ubuntu 24.04 with Apple's Virtualization.framework (`vmType: "vz"`). The VM provides:

- **virtiofs mounts** from the host (read-only by default)
- **OverlayFS** so services see a writable `/workspace` while the host mount stays untouched
- **UFW firewall** with an explicit allowlist (HTTPS, DNS, Tailscale, NTP -- everything else denied)
- **Gateway process** running on port 18789, forwarded to the host
- **Secrets management** via `/etc/openclaw/secrets.env` (mode `0600`)

### Layer 3: Docker Containers

Individual tool executions (file reads/writes, shell commands, browser actions) are sandboxed inside Docker containers using **dual-container network isolation**:

- **Isolated container** (`network: none`): most tool executions — air-gapped, no internet
- **Network container** (`network: bridge`): tools matching `networkAllow` (e.g., `web_fetch`, `web_search`) or `networkExecAllow` (e.g., `gh` commands)
- **Image**: `openclaw-sandbox:bookworm-slim` (auto-augmented with `gh` if missing)
- **Scope**: one container pair per session
- **Workspace**: `/workspace` bind-mounted read-write into both containers

## Component Breakdown

### Lima VM Configuration

`bootstrap.sh` generates the Lima config at `lima/openclaw-sandbox.generated.yaml`. Key settings:

| Setting | Value |
|---------|-------|
| `vmType` | `vz` (Apple Virtualization.framework) |
| CPUs | 4 (configurable via `VM_CPUS`) |
| Memory | 8GiB (configurable via `VM_MEMORY`) |
| Disk | 50GiB (configurable via `VM_DISK`) |
| Rosetta | Enabled (x86_64 emulation on Apple Silicon) |
| containerd | Disabled (Docker CE installed separately) |

### virtiofs Mounts

Host directories are mounted into the VM using virtiofs:

| Host Path | VM Mount Point | Writable |
|-----------|---------------|----------|
| `~/Projects/openclaw` | `/mnt/openclaw` | Read-only (default) |
| Sandbox repo directory | `/mnt/provision` | Read-only (always) |
| Obsidian vault (optional) | `/mnt/obsidian` | Read-only (default) |
| `~/.openclaw` (optional) | `/mnt/openclaw-config` | Read-only (default) |
| Agent data (optional) | `/mnt/openclaw-agents` | Read-write (always) |
| Buildlog data (optional) | `/mnt/buildlog-data` | Read-write (always) |
| Custom skills (optional) | `/mnt/skills-custom` | Read-only (always) |
| Secrets parent dir (optional) | `/mnt/secrets` | Read-only (always) |

!!! important
    Lima mounts are baked at VM creation time. Changing mount writability requires `--delete` + recreate.

### OverlayFS

The overlay merges the read-only host mount with a writable upper layer:

- **Lower (read-only)**: `/mnt/openclaw`
- **Upper (writes)**: `/var/lib/openclaw/overlay/openclaw/upper`
- **Merged**: `/workspace` -- where the gateway and all services run

An optional Obsidian overlay does the same for vaults: `/mnt/obsidian` merges into `/workspace-obsidian`.

### Gateway

The gateway is a Node.js process managed by systemd (`openclaw-gateway.service`):

- Binds to `0.0.0.0:18789`
- `WorkingDirectory=/workspace`
- Loads secrets via `EnvironmentFile=-/etc/openclaw/secrets.env`
- Gets Docker access via `SupplementaryGroups=docker` (no re-login needed)
- Depends on `workspace.mount` when overlay is active

### Docker Sandbox

When Docker is enabled, the sandbox role:

1. Builds the sandbox image using OpenClaw's `scripts/sandbox-setup.sh` (or a fallback Dockerfile)
2. Layers `gh` CLI on top if missing (inspects the base image user and restores it after augmentation)
3. Configures `openclaw.json` with sandbox settings via the `combine()` pattern
4. Sets up **dual-container network isolation**: `networkAllow` and `networkExecAllow` route specific tools to a bridge-networked container while the default container is air-gapped

### UFW Firewall

The VM firewall uses an explicit allowlist:

| Direction | Port/Range | Purpose |
|-----------|-----------|---------|
| IN | 18789/tcp | Gateway API |
| IN | 22/tcp | SSH (Ansible) |
| OUT | 443/tcp | HTTPS (LLM APIs) |
| OUT | 80/tcp | HTTP (apt updates) |
| OUT | 53/udp,tcp | DNS |
| OUT | 100.64.0.0/10 | Tailscale |
| OUT | 41641/udp | Tailscale direct |
| OUT | 123/udp | NTP |

All other traffic is denied and logged.

## Role Execution Order

The Ansible playbook (`ansible/playbook.yml`) executes roles in this order:

| # | Role | Phase | Purpose |
|---|------|-------|---------|
| 1 | `secrets` | S5 | Extract and write `/etc/openclaw/secrets.env` |
| 2 | `overlay` | S9 | Set up OverlayFS, create `/workspace` |
| 3 | `docker` | S10 | Install Docker CE from official repo |
| 4 | `gh-cli` | -- | Install GitHub CLI from official APT repo |
| 5 | `gateway` | S2 | Install Node.js, build OpenClaw, deploy systemd service |
| 6 | `firewall` | S3 | Configure UFW allowlist |
| 7 | `tailscale` | S4 | Set up Tailscale routing |
| 8 | `cadence` | S7 | Deploy ambient insight pipeline |
| 9 | `buildlog` | S8 | Install buildlog for ambient learning |
| 10 | `qortex` | -- | Set up seed exchange directories and interop config |
| 11 | `sandbox` | S10 | Build sandbox image, configure `openclaw.json` (dual-container) |
| 12 | `sync-gate` | S9 | Deploy sync helper scripts |

The ordering is intentional: secrets must be available before anything else, overlay must exist before the gateway starts (it depends on `workspace.mount`), Docker must be ready before the gateway gets `SupplementaryGroups=docker`, and the sandbox role needs the workspace built.

!!! note
    Roles with `when:` conditions: `docker` and `sandbox` require `docker_enabled` (default: true), `sync-gate` requires overlay to be active (not yolo-unsafe).

## Port Forwarding

Lima forwards a single port from the VM to the host:

```yaml
portForwards:
  - guestPort: 18789
    hostPort: 18789
    proto: tcp
```

This makes the gateway accessible at `localhost:18789` on the host. The `claw` CLI and host-side tools connect through this port.

## How Provisioning Works

The Python CLI (`sandbox up`) is the recommended entry point. It loads a saved profile and calls `bootstrap.sh` under the hood. LLM agents can also use the MCP server (`sandbox-mcp`) which exposes `sandbox_up`, `sandbox_down`, `sandbox_status`, and other tools via FastMCP over stdio.

The main flow in `bootstrap.sh`:

```
parse_args()
  |
  v
generate_lima_config()    # Build Lima YAML programmatically
  |
  v
ensure_homebrew()         # Check brew is installed
  |
  v
install_deps()            # brew bundle + ansible-galaxy
  |
  v
ensure_vm()               # limactl create/start
  |
  v
verify_mounts()           # Confirm /mnt/* paths are accessible
  |
  v
run_ansible()             # Provision all 12 roles
  |
  v
Done.
```

The script also handles operational commands (`--kill`, `--delete`, `--shell`, `--onboard`) that bypass the provisioning flow entirely.

### Workspace Path Resolution

The playbook computes `workspace_path` dynamically:

```yaml
workspace_path: >-
  {{ overlay_workspace_path | default('/workspace')
     if (overlay_enabled | default(true) | bool
         and not (overlay_yolo_unsafe | default(false) | bool))
     else openclaw_path }}
```

Translation: if overlay is enabled and not in yolo-unsafe mode, workspace is `/workspace` (the OverlayFS merged mount). Otherwise, it falls back to `/mnt/openclaw` (direct host mount).
