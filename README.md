<div align="center">

# OpenClaw Sandbox

### Secure, isolated VM environment for running OpenClaw agents

[![Release](https://img.shields.io/github/v/release/Peleke/openclaw-sandbox?style=for-the-badge&color=green)](https://github.com/Peleke/openclaw-sandbox/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/Peleke/openclaw-sandbox/ci.yml?style=for-the-badge&label=CI)](https://github.com/Peleke/openclaw-sandbox/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-macOS-blue?style=for-the-badge&logo=apple&logoColor=white)](https://lima-vm.io/)

**Run AI agents with network containment, audit trails, and secrets management.**

<img src="assets/hero-banner.png" alt="OpenClaw Sandbox - Secure VM environment for AI agents" width="800"/>

</div>

---

## The Problem

Running AI agents on your host machine is risky:
- Agents can access sensitive files, credentials, and configs
- Network traffic is unrestricted
- No isolation between agent and host processes
- Secrets end up in environment variables, logs, and shell history

**OpenClaw Sandbox** solves this by running agents inside a hardened Linux VM with strict network policies and secure secrets handling.

## Features

- **Filesystem Isolation** - OverlayFS: host mounts are read-only, all writes contained in overlay
- **Docker Sandbox** - Tool executions run inside Docker containers with network=none
- **Network Containment** - UFW firewall with explicit allowlist (only HTTPS, DNS, Tailscale)
- **Secrets Management** - Multiple injection methods, never in logs or process lists
- **Gated Sync** - Validated pipeline (gitleaks, path allowlist) before changes reach host
- **Tailscale Integration** - Route to your private network via host
- **Zero-Config Deploy** - Single command bootstrap from macOS

## Quick Start

```bash
# Clone and run
git clone https://github.com/Peleke/openclaw-sandbox.git
cd openclaw-sandbox

# Bootstrap with your OpenClaw repo and secrets
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env

# Access the VM
limactl shell openclaw-sandbox
```

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│ macOS Host                                                │
│                                                           │
│  ~/Projects/openclaw ◄──── sync-gate.sh (approved only)  │
│                                                           │
│  ╔════════════════════════════════════════════════════╗   │
│  ║ Lima VM (Ubuntu 24.04)                             ║   │
│  ║                                                     ║   │
│  ║  /mnt/openclaw (read-only virtiofs from host)      ║   │
│  ║       │ lowerdir                                    ║   │
│  ║       ▼                                             ║   │
│  ║  ┌───────────────────────┐                          ║   │
│  ║  │  OverlayFS            │                          ║   │
│  ║  │  upper: /var/lib/     │ ◄── all writes land here ║   │
│  ║  │    openclaw/overlay/  │                          ║   │
│  ║  │  merged: /workspace   │ ◄── services run here    ║   │
│  ║  └───────────────────────┘                          ║   │
│  ║       │                                             ║   │
│  ║       ▼                                             ║   │
│  ║  ┌───────────────────────────────────────────────┐  ║   │
│  ║  │  Gateway (:18789)                              │  ║   │
│  ║  │  WorkingDirectory=/workspace                   │  ║   │
│  ║  │                                                 │  ║   │
│  ║  │  Tool request from agent                       │  ║   │
│  ║  │       │                                         │  ║   │
│  ║  │       ▼                                         │  ║   │
│  ║  │  ┌─────────────────────────────────────────┐   │  ║   │
│  ║  │  │  Docker Container (per-session)          │   │  ║   │
│  ║  │  │  image: openclaw-sandbox:bookworm-slim   │   │  ║   │
│  ║  │  │  network: none (no egress)               │   │  ║   │
│  ║  │  │  /workspace → bind mount                 │   │  ║   │
│  ║  │  └─────────────────────────────────────────┘   │  ║   │
│  ║  └───────────────────────────────────────────────┘  ║   │
│  ║                                                     ║   │
│  ║  ┌──────────────┐  Validation before sync:          ║   │
│  ║  │   Firewall   │    ✓ Secret scan (gitleaks)       ║   │
│  ║  │     UFW      │    ✓ Path allowlist               ║   │
│  ║  └──────────────┘    ✓ Size / filetype check        ║   │
│  ╚════════════════════════════════════════════════════╝   │
└──────────────────────────────────────────────────────────┘
```

## Defense-in-Depth

Two layers of isolation work together:

```
Layer 1 (overlay):   gateway process  → VM + read-only host mounts + OverlayFS
Layer 2 (docker):    tool execution   → Docker container (network=none)
```

Host mounts are **read-only by default**. All writes land in an OverlayFS upper layer inside the VM. Changes only reach the host through a validated sync gate.

Individual tool executions (file reads/writes, shell commands, browser actions) are further sandboxed inside Docker containers with no network access.

## Docker Sandbox

OpenClaw's built-in sandbox containerizes individual tool executions inside the VM:

- **Mode**: `all` - every session gets sandboxed
- **Scope**: `session` - one container per session
- **Workspace**: `rw` - tools can read/write project files
- **Network**: `none` - containers cannot reach the internet
- **Image**: `openclaw-sandbox:bookworm-slim`

```bash
# Check Docker in VM
limactl shell openclaw-sandbox -- docker info

# Check sandbox image
limactl shell openclaw-sandbox -- docker images | grep openclaw-sandbox

# See active containers
limactl shell openclaw-sandbox -- docker ps -a

# Verify network isolation
limactl shell openclaw-sandbox -- docker run --rm --network none alpine ping -c1 8.8.8.8
# ^ Should fail (no network)
```

To disable Docker sandbox (lighter VM):
```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --no-docker
```

## Filesystem Isolation

### Modes

| Mode | Flag | Host Mounts | Overlay | Sync |
|------|------|-------------|---------|------|
| **Secure** (default) | _(none)_ | Read-only | Active | Manual via `sync-gate.sh` |
| **YOLO** | `--yolo` | Read-only | Active | Auto-sync every 30s |
| **YOLO-Unsafe** | `--yolo-unsafe` | Read-write | Disabled | Direct (legacy) |

### Syncing Changes to Host

```bash
# Show pending changes
./scripts/sync-gate.sh --dry-run

# Validate and apply (interactive)
./scripts/sync-gate.sh

# Auto-apply (CI/automation)
./scripts/sync-gate.sh --auto

# Check overlay status in VM
./scripts/sync-gate.sh --status

# Discard all overlay writes
./scripts/sync-gate.sh --reset
```

### VM-side Helpers

```bash
# Check overlay state
limactl shell openclaw-sandbox -- overlay-status

# Reset overlay (discard all writes)
limactl shell openclaw-sandbox -- sudo overlay-reset
```

## Secrets Management

Three ways to provide secrets, in priority order:

### 1. Direct Injection (CI/CD, testing)

```bash
./bootstrap.sh --openclaw ../openclaw \
  -e "secrets_anthropic_api_key=sk-ant-xxx" \
  -e "secrets_gateway_password=mypass"
```

### 2. Secrets File (recommended for dev)

```bash
# Create secrets file
cat > ~/.openclaw-secrets.env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-xxx
OPENAI_API_KEY=sk-xxx
OPENCLAW_GATEWAY_PASSWORD=mypass
EOF

# Bootstrap with secrets
./bootstrap.sh --openclaw ../openclaw --secrets ~/.openclaw-secrets.env
```

### 3. Config Mount (full OpenClaw config)

```bash
./bootstrap.sh --openclaw ../openclaw --config ~/.openclaw
```

### Supported Secrets

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Claude API key |
| `OPENAI_API_KEY` | OpenAI API key |
| `GEMINI_API_KEY` | Google Gemini API key |
| `OPENROUTER_API_KEY` | OpenRouter API key |
| `OPENCLAW_GATEWAY_PASSWORD` | Gateway auth password |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway auth token |
| `SLACK_BOT_TOKEN` | Slack integration |
| `DISCORD_BOT_TOKEN` | Discord integration |
| `TELEGRAM_BOT_TOKEN` | Telegram integration |

## Usage

```bash
# Full bootstrap — secure mode (default: read-only mounts + overlay)
./bootstrap.sh --openclaw ~/Projects/openclaw

# With secrets
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.secrets.env

# With Obsidian vault
./bootstrap.sh --openclaw ~/Projects/openclaw --vault ~/Documents/Vaults/main

# YOLO mode — overlay + auto-sync every 30s
./bootstrap.sh --openclaw ~/Projects/openclaw --yolo

# YOLO-unsafe — no overlay, rw mounts (legacy, requires --delete first)
./bootstrap.sh --openclaw ~/Projects/openclaw --yolo-unsafe

# No Docker — lighter VM (skips Docker + sandbox)
./bootstrap.sh --openclaw ~/Projects/openclaw --no-docker

# Open VM shell
./bootstrap.sh --shell

# Run interactive onboard
./bootstrap.sh --onboard

# Stop VM
./bootstrap.sh --kill

# Delete VM completely (required to change mount modes)
./bootstrap.sh --delete
```

## Telegram Integration

The sandbox supports Telegram bot integration for ambient agent access:

```bash
# Add your bot token to secrets
echo 'TELEGRAM_BOT_TOKEN=your-bot-token' >> ~/.openclaw-secrets.env

# Re-provision to apply
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

The provisioning automatically:
- Sets `dmPolicy: "open"` with `allowFrom: ["*"]` (anyone can message)
- Fixes workspace paths for Linux VM
- Starts the gateway with Telegram long-polling enabled

### Testing Telegram

```bash
# Check gateway status
limactl shell openclaw-sandbox -- systemctl status openclaw-gateway

# View Telegram activity
limactl shell openclaw-sandbox -- tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log | grep telegram

# Check bot connection
limactl shell openclaw-sandbox -- claw status
```

## Cadence Integration

Cadence is the ambient AI pipeline that watches your Obsidian vault and delivers insights to Telegram:

```
┌──────────────┐     ┌─────────────────┐     ┌──────────────┐     ┌──────────────┐
│   Obsidian   │────▶│  Insight        │────▶│  Insight     │────▶│  Telegram    │
│   Watcher    │     │  Extractor      │     │  Digest      │     │  Delivery    │
│              │     │  (LLM)          │     │  (Batching)  │     │              │
└──────────────┘     └─────────────────┘     └──────────────┘     └──────────────┘
```

### Setup

```bash
# Bootstrap with vault mounted
./bootstrap.sh --openclaw ~/Projects/openclaw --vault ~/Documents/Vaults/main --secrets ~/.secrets.env

# Configure cadence
limactl shell openclaw-sandbox -- nano ~/.openclaw/cadence.json
```

Edit `cadence.json`:
```json
{
  "enabled": true,
  "vaultPath": "/mnt/obsidian",
  "delivery": {
    "channel": "telegram",
    "telegramChatId": "YOUR_CHAT_ID"
  },
  "schedule": {
    "enabled": true,
    "nightlyDigest": "21:00",
    "morningStandup": "08:00"
  }
}
```

### Usage

```bash
# Start cadence service
limactl shell openclaw-sandbox -- sudo systemctl start openclaw-cadence

# Check status
limactl shell openclaw-sandbox -- sudo systemctl status openclaw-cadence

# View logs
limactl shell openclaw-sandbox -- sudo journalctl -u openclaw-cadence -f

# Manual digest trigger
limactl shell openclaw-sandbox -- bun /mnt/openclaw/scripts/cadence.ts digest
```

Write journal entries with `::publish` on line 2 (after the title) to mark them for insight extraction.

## buildlog Integration

[buildlog](https://github.com/Peleke/buildlog-template) is installed globally for ambient learning capture:

```
┌──────────────┐     ┌─────────────────┐     ┌──────────────┐     ┌──────────────┐
│   Session    │────▶│    Trajectory   │────▶│   Thompson   │────▶│   Agent      │
│   Activity   │     │    Capture      │     │   Sampling   │     │   Rules      │
└──────────────┘     └─────────────────┘     └──────────────┘     └──────────────┘
```

### What It Does

- Captures structured trajectories from every coding session
- Extracts decision patterns ("seeds") that can be learned
- Uses Thompson Sampling to surface rules that actually reduce mistakes
- Renders learned rules to CLAUDE.md and other agent formats

### Usage

buildlog is pre-configured and the MCP server is registered. Claude Code has access to all 29 tools automatically.

```bash
# Check state
limactl shell openclaw-sandbox -- buildlog overview

# Start a session
limactl shell openclaw-sandbox -- buildlog new my-feature

# Commit (always use this instead of raw git commit)
limactl shell openclaw-sandbox -- buildlog commit -m "feat: add feature"

# Run review gauntlet
limactl shell openclaw-sandbox -- buildlog gauntlet

# Extract and render skills
limactl shell openclaw-sandbox -- buildlog skills
```

### Host CLI Setup

To use `claw` commands from your Mac to the sandboxed gateway:

```bash
# Add to your shell profile (~/.zshrc)
# Detects sandbox and routes to localhost
source ~/.openclaw/dotfiles/env.sh

# Then from host:
claw status  # Shows sandbox gateway status
claw tui     # Opens TUI connected to sandbox
```

## Network Policy

The VM firewall allows only:

| Direction | Port | Protocol | Purpose |
|-----------|------|----------|---------|
| **IN** | 18789 | TCP | Gateway API |
| **IN** | 22 | TCP | SSH/Ansible |
| **OUT** | 443 | TCP | HTTPS (LLM APIs) |
| **OUT** | 80 | TCP | HTTP (apt updates) |
| **OUT** | 53 | UDP/TCP | DNS |
| **OUT** | 100.64.0.0/10 | * | Tailscale |
| **OUT** | 41641 | UDP | Tailscale direct |
| **OUT** | 123 | UDP | NTP |

All other traffic is **denied and logged**.

## Requirements

- macOS with Apple Silicon or Intel
- [Homebrew](https://brew.sh/)
- ~10GB disk space

Dependencies are installed automatically:
- [Lima](https://lima-vm.io/) - Linux VM manager
- [Ansible](https://www.ansible.com/) - Configuration management
- [jq](https://jqlang.github.io/jq/) - JSON processor
- [gitleaks](https://github.com/gitleaks/gitleaks) - Secret scanning (for sync-gate)
- [Tailscale](https://tailscale.com/) - (optional) private networking

## Development Phases

| Phase | Status | Description |
|-------|--------|-------------|
| S1 | Done | Lima VM bootstrap |
| S2 | Done | Gateway deployment |
| S3 | Done | Network containment (UFW) |
| S4 | Done | Tailscale routing |
| S5 | Done | Secrets management |
| S6 | Done | Telegram integration |
| S7 | Done | Cadence (ambient signals) |
| S8 | Done | buildlog (ambient learning) |
| S9 | Done | OverlayFS filesystem isolation |
| **S10** | **Done** | **Docker sandbox inside VM** |
| S11 | Planned | Multi-tenant |

## Security Considerations

1. **Filesystem isolation** - Host mounts read-only, writes contained in OverlayFS
2. **Docker sandbox** - Tool executions in containers with `network: none`
3. **Gated sync** - gitleaks scan + path allowlist before changes reach host
4. **Secrets never logged** - All Ansible tasks use `no_log: true`
5. **File permissions** - `/etc/openclaw/secrets.env` is `0600`
6. **No process exposure** - Using `EnvironmentFile=` not `Environment=`
7. **Network isolation** - Explicit allowlist, all else denied
8. **Audit trail** - inotifywait watcher logs all overlay writes

## Troubleshooting

### Check VM status
```bash
limactl list
```

### View gateway logs
```bash
limactl shell openclaw-sandbox -- sudo journalctl -u openclaw-gateway -f
```

### Check firewall rules
```bash
limactl shell openclaw-sandbox -- sudo ufw status verbose
```

### Verify secrets loaded
```bash
limactl shell openclaw-sandbox -- sudo cat /etc/openclaw/secrets.env
```

### Test Tailscale routing
```bash
limactl shell openclaw-sandbox -- ~/test-tailscale.sh 100.x.x.x
```

## Tests

The project includes comprehensive test suites:

```bash
# Overlay tests (60 checks)
./tests/overlay/run-all.sh              # Full suite (requires VM)
./tests/overlay/run-all.sh --quick      # Ansible validation only
./tests/overlay/test-overlay-ansible.sh # Role structure, templates, integration (60 checks)
./tests/overlay/test-overlay-role.sh    # VM deployment tests (19 checks)

# Docker + Sandbox tests
./tests/sandbox/run-all.sh              # Full suite (requires VM)
./tests/sandbox/run-all.sh --quick      # Ansible validation only
./tests/sandbox/test-sandbox-ansible.sh # Role structure, defaults, integration
./tests/sandbox/test-sandbox-role.sh    # VM deployment tests (Docker, image, config)

# Cadence tests (64 checks)
./tests/cadence/run-all.sh              # Full suite (requires VM)
./tests/cadence/run-all.sh --quick      # Ansible validation only
./tests/cadence/test-cadence-ansible.sh # Ansible role validation (32 checks)
./tests/cadence/test-cadence-role.sh    # VM deployment tests (22 checks)
./tests/cadence/test-cadence-e2e.sh     # Full pipeline E2E (10 checks)
```

### CI/CD

- **CI** runs on every PR: YAML lint, Ansible validation, ShellCheck
- **Release** workflow triggers on `v*` tags and creates GitHub releases

## Contributing

1. Fork the repo
2. Create a feature branch
3. Make changes
4. Run tests: `./tests/overlay/run-all.sh --quick && ./tests/sandbox/run-all.sh --quick && ./tests/cadence/run-all.sh --quick`
5. Open a PR (CI will run automatically)

## Releases

We use [semantic versioning](https://semver.org/) with milestone-based releases.

### Creating a Release

```bash
# Use the release script
./scripts/release.sh 0.4.0

# This will:
# 1. Validate semver format
# 2. Check you're on main with clean working directory
# 3. Verify/prompt for CHANGELOG entry
# 4. Create tag and push
# 5. GitHub Actions creates the release
```

### Version History

See [CHANGELOG.md](./CHANGELOG.md) for detailed release notes.

## License

MIT License. See [LICENSE](./LICENSE).
