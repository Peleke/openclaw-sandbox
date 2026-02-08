<div align="center">

# OpenClaw Sandbox

### Secure, Isolated VM for Running AI Agents

[![Release](https://img.shields.io/github/v/release/Peleke/openclaw-sandbox?style=for-the-badge&color=green)](https://github.com/Peleke/openclaw-sandbox/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/Peleke/openclaw-sandbox/ci.yml?style=for-the-badge&label=CI)](https://github.com/Peleke/openclaw-sandbox/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-macOS-blue?style=for-the-badge&logo=apple&logoColor=white)](https://lima-vm.io/)
[![Tests](https://img.shields.io/badge/Tests-208_passed-brightgreen?style=for-the-badge)](cli/tests/)

**Run AI agents with network containment, audit trails, and secrets management.**

[Quick Start](#-quick-start) · [Features](#-features) · [Architecture](#-architecture) · [CLI Reference](#-cli-reference) · [Contributing](#-contributing)

---

</div>

## The Problem

Running AI agents on your host machine is a liability:
- Agents can read your credentials, SSH keys, and browser cookies
- Network traffic is unrestricted — they can exfiltrate data anywhere
- No isolation between agent and host processes
- Secrets end up in environment variables, logs, and shell history

You need the agent to do real work — access your code, call APIs, run tools — but without handing it the keys to your entire machine.

## The Solution

**OpenClaw Sandbox** runs agents inside a hardened Lima VM with strict network policies, OverlayFS filesystem isolation, and Docker-containerized tool execution. Your code is mounted read-only. All writes are contained in an overlay. Changes only reach your host through a validated sync gate with secret scanning.

One command to provision. One command to tear down. Everything in between is contained.

```
You: sandbox up
     → Lima VM created (Ubuntu 24.04, Apple VZ)
     → Ansible provisions 10 roles (overlay, Docker, firewall, secrets, gateway...)
     → Gateway starts on :18789
     → Agent is running. You are safe.

You: sandbox status
     → VM: Running | Mode: secure | Overlay: active
     → Agent: Claw (🦞) | Observations: 847

You: sandbox ssh
     → You're inside the VM. Do whatever you want.
```

**10 Ansible roles. 208 CLI tests. Zero manual config.**

---

## Features

### 🛡️ Defense-in-Depth Isolation
Two layers working together. **Layer 1**: OverlayFS makes host mounts read-only — all writes land in an upper layer inside the VM. **Layer 2**: Individual tool executions (shell commands, file ops, browser actions) run inside Docker containers with bridge networking. Your code never leaves the sandbox.

### 🔒 Network Containment
UFW firewall with explicit allowlist — only HTTPS, DNS, Tailscale, and NTP are permitted. All other traffic is denied and logged. The agent can call LLM APIs and pull packages, but can't phone home to anywhere unexpected.

### 🔑 Secrets Management
Three injection methods (direct, secrets file, config mount). Secrets land in `/etc/openclaw/secrets.env` with `0600` permissions, loaded via `EnvironmentFile=` — never in process lists, never in logs. All Ansible tasks use `no_log: true`.

### 📂 Gated Sync
Changes only reach your host through `sandbox sync`, which runs gitleaks secret scanning, path allowlisting, and size/filetype checks. In secure mode, you approve every change. In YOLO mode, it auto-syncs every 30 seconds.

### 🐳 Docker Sandbox
OpenClaw's built-in sandbox containerizes tool executions inside the VM. Every session gets its own container with bridge networking (configurable to `none` for full air-gap). The sandbox image is auto-augmented with `gh` if missing.

### 🔗 GitHub CLI
`gh` installed from the official APT repository. `GH_TOKEN` passthrough from secrets — no `gh auth login` needed. Available both in the VM and inside sandbox containers.

### 📓 Obsidian Vault Access
Mount your vault read-only into the VM and sandbox containers. The agent can read your notes but can't modify them. `OBSIDIAN_VAULT_PATH` is exported so agents know where to find vault files.

### 📡 Telegram Integration
Pairing-based access control. Pre-seed your Telegram user ID or use the built-in pairing flow. No open access by default.

### 📊 buildlog Integration
[buildlog](https://github.com/Peleke/buildlog-template) is pre-installed for ambient learning capture — structured trajectories, Thompson Sampling for rule surfacing, automatic CLAUDE.md rendering. MCP server registered with 29 tools.

### ⚡ Zero-Config Deploy
Single `sandbox up` from macOS. Homebrew, Lima, Ansible — all dependencies installed automatically. Apple Silicon with Rosetta, or Intel. ~10GB disk.

---

## 🆚 Why a VM?

| | Docker-only | Sandbox VM |
|---|:---:|:---:|
| **Filesystem isolation** | Bind mounts (writable) | OverlayFS (read-only lower) |
| **Network policy** | iptables in container | UFW at VM level |
| **Secrets exposure** | Env vars in container | `EnvironmentFile=` (not in process list) |
| **Tool sandboxing** | Single container | Nested: VM → Docker per session |
| **Kernel isolation** | Shared host kernel | Separate VM kernel |
| **Sync validation** | None | gitleaks + path allowlist |

---

## 🚀 Quick Start

```bash
# Install the CLI
pip install openclaw-sandbox
# or: uv pip install openclaw-sandbox

# Interactive setup — creates ~/.openclaw/sandbox-profile.toml
sandbox init

# Provision the VM (first run takes ~5 minutes)
sandbox up

# Check status
sandbox status

# SSH into the VM
sandbox ssh

# Sync overlay changes to host (with secret scanning)
sandbox sync

# Stop the VM
sandbox down

# Delete the VM entirely
sandbox destroy
```

### From Source

```bash
git clone https://github.com/Peleke/openclaw-sandbox.git
cd openclaw-sandbox

# Install CLI in dev mode
uv pip install -e cli/

# Provision
sandbox up
```

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────┐
│ macOS Host                                                │
│                                                           │
│  ~/Projects/openclaw ◄──── sandbox sync (approved only)  │
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
│  ║  │  │  network: bridge                          │   │  ║   │
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

### Isolation Layers

```
Layer 1 (overlay):   gateway process  → VM + read-only host mounts + OverlayFS
Layer 2 (docker):    tool execution   → Docker container (bridge network)
```

---

## 💻 CLI Reference

| Command | Description |
|---------|-------------|
| `sandbox init` | Interactive wizard — creates `~/.openclaw/sandbox-profile.toml` |
| `sandbox up` | Provision (or reprovision) the VM |
| `sandbox up --fresh` | Destroy + reprovision from scratch |
| `sandbox down` | Stop the VM (force kill) |
| `sandbox destroy` | Delete the VM entirely (with confirmation) |
| `sandbox destroy -f` | Delete without confirmation |
| `sandbox status` | Show VM state, profile summary, agent identity |
| `sandbox ssh` | SSH into the VM (replaces process for TTY) |
| `sandbox onboard` | Run the onboarding wizard inside the VM |
| `sandbox sync` | Sync overlay changes to host (with validation) |
| `sandbox sync --dry-run` | Preview sync without applying |
| `sandbox dashboard` | Open the gateway dashboard |
| `sandbox dashboard green` | Open a specific dashboard page |

### Profile Configuration

`sandbox init` creates `~/.openclaw/sandbox-profile.toml`:

```toml
[mounts]
openclaw = "~/Projects/openclaw"
config = "~/.openclaw"
agent_data = "~/.openclaw/agents"
buildlog_data = "~/.buildlog"
secrets = "~/.openclaw-secrets.env"
vault = "~/Documents/Vaults/ClawTheCurious"

[mode]
yolo = false
yolo_unsafe = false
no_docker = false

[resources]
cpus = 4
memory = "8GiB"
disk = "50GiB"
```

### Filesystem Modes

| Mode | Flag | Host Mounts | Overlay | Sync |
|------|------|-------------|---------|------|
| **Secure** (default) | _(none)_ | Read-only | Active | Manual via `sandbox sync` |
| **YOLO** | `--yolo` | Read-only | Active | Auto-sync every 30s |
| **YOLO-Unsafe** | `--yolo-unsafe` | Read-write | Disabled | Direct (legacy) |

---

<div align="center">

# Part II: Technical Documentation

*For engineers, contributors, and the curious*

</div>

---

## 🔑 Secrets Management

Three ways to provide secrets, in priority order:

### 1. Direct Injection (CI/CD, testing)

```bash
# Via profile extra_vars or bootstrap.sh fallback
sandbox up  # with extra_vars in profile
```

### 2. Secrets File (recommended for dev)

```bash
cat > ~/.openclaw-secrets.env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-xxx
OPENAI_API_KEY=sk-xxx
OPENCLAW_GATEWAY_PASSWORD=mypass
GH_TOKEN=ghp_xxx
EOF

# Point your profile at it
sandbox init  # → secrets = "~/.openclaw-secrets.env"
```

### 3. Config Mount (full OpenClaw config)

```bash
# Point your profile at ~/.openclaw
sandbox init  # → config = "~/.openclaw"
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
| `GH_TOKEN` | GitHub CLI token |
| `SLACK_BOT_TOKEN` | Slack integration |
| `DISCORD_BOT_TOKEN` | Discord integration |
| `TELEGRAM_BOT_TOKEN` | Telegram integration |

### Token Flow

```
Host secrets file → Ansible regex extraction → /etc/openclaw/secrets.env (0600)
  → gateway EnvironmentFile= → container env passthrough (sandbox.docker.env.GH_TOKEN)
```

## 🔥 Network Policy

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

## 📡 Telegram Setup

```bash
# Add bot token to secrets
echo 'TELEGRAM_BOT_TOKEN=your-bot-token' >> ~/.openclaw-secrets.env

# Pre-seed your Telegram user ID
# Get it from @userinfobot on Telegram
# Add to profile extra_vars: telegram_user_id = "YOUR_ID"
sandbox up
```

Access control uses OpenClaw's pairing system (`dmPolicy: "pairing"`):

| Scenario | What happens |
|----------|-------------|
| **Your ID pre-seeded** | You can message immediately |
| **Unknown sender** | Bot shows a pairing code |
| **Owner approves code** | Sender gets added to allow list |

## 📊 buildlog Setup

buildlog is pre-configured and the MCP server is registered. Claude Code has access to all 29 tools automatically.

```bash
# Check state
sandbox ssh
buildlog overview

# Commit with logging
buildlog commit -m "feat: add feature"

# Run review gauntlet
buildlog gauntlet

# Extract and render skills
buildlog skills
```

## 📁 Project Structure

```
openclaw-sandbox/
├── cli/                          # Python CLI (Typer + Rich)
│   ├── src/sandbox_cli/
│   │   ├── app.py                # Typer subcommand definitions
│   │   ├── models.py             # Pydantic profile models
│   │   ├── lima_config.py        # Jinja2 Lima YAML generation
│   │   ├── lima_manager.py       # limactl subprocess wrapper
│   │   ├── ansible_runner.py     # Inventory builder + playbook invocation
│   │   ├── orchestrator.py       # Sequences: deps → config → VM → ansible
│   │   ├── reporting.py          # Status output + OpenClaw interop
│   │   ├── deps.py               # Homebrew/Ansible dependency checks
│   │   ├── profile.py            # Profile loading + init wizard
│   │   ├── validation.py         # Profile validation
│   │   ├── bootstrap.py          # Legacy bash delegation (deprecated)
│   │   └── templates/
│   │       └── lima-vm.yaml.j2   # Lima VM config template
│   └── tests/                    # 208 pytest tests
├── ansible/
│   ├── playbook.yml              # Main playbook
│   └── roles/
│       ├── overlay/              # OverlayFS isolation
│       ├── sandbox/              # Docker sandbox config
│       ├── docker/               # Docker CE installation
│       ├── secrets/              # Secrets extraction + injection
│       ├── gh-cli/               # GitHub CLI
│       ├── obsidian/             # Vault mount + container bind
│       ├── gateway/              # OpenClaw gateway systemd service
│       ├── firewall/             # UFW network policy
│       ├── buildlog/             # buildlog + MCP registration
│       └── qortex/               # Qortex interop + Memgraph
├── scripts/
│   ├── sync-gate.sh              # Host-side sync with gitleaks
│   ├── dashboard.sh              # Gateway dashboard opener
│   └── release.sh                # Semver release automation
├── tests/                        # Ansible role test suites
│   ├── overlay/                  # 60 Ansible + 19 VM checks
│   ├── sandbox/                  # 89 Ansible + 32 VM checks
│   ├── gh-cli/                   # 59 Ansible + 15 VM checks
│   ├── obsidian/                 # 34 Ansible + 12 VM checks
│   └── cadence/                  # 64 checks total
├── bootstrap.sh                  # Legacy entrypoint (still works)
└── Brewfile                      # macOS dependencies
```

## 🧪 Tests

### CLI Tests (208 tests)

```bash
uv run --directory cli pytest tests/ -v
```

### Ansible Role Tests

```bash
# Quick mode — Ansible lint + structure validation
./tests/overlay/run-all.sh --quick
./tests/sandbox/run-all.sh --quick
./tests/gh-cli/run-all.sh --quick
./tests/obsidian/run-all.sh --quick

# Full mode — deploys to running VM
./tests/overlay/run-all.sh
./tests/sandbox/run-all.sh
```

### CI/CD

- **CI** runs on every PR: YAML lint, Ansible validation, ShellCheck
- **Release** workflow triggers on `v*` tags and creates GitHub releases

## 🔧 Troubleshooting

```bash
# Check VM status
sandbox status

# View gateway logs
sandbox ssh
sudo journalctl -u openclaw-gateway -f

# Check firewall rules
sandbox ssh
sudo ufw status verbose

# Verify secrets loaded
sandbox ssh
sudo cat /etc/openclaw/secrets.env

# Check overlay state
sandbox ssh
overlay-status

# Reset overlay (discard all writes)
sandbox ssh
sudo overlay-reset
```

## 🚢 Releases

```bash
# Use the release script
./scripts/release.sh 0.7.0

# This will:
# 1. Validate semver format
# 2. Check you're on main with clean working directory
# 3. Verify/prompt for CHANGELOG entry
# 4. Create tag and push
# 5. GitHub Actions creates the release
```

See [CHANGELOG.md](./CHANGELOG.md) for detailed release notes.

## 🤝 Contributing

1. Fork the repo
2. Create a feature branch
3. Make changes
4. Run tests: `uv run --directory cli pytest tests/ -v`
5. Open a PR (CI will run automatically)

## 📋 Requirements

- macOS with Apple Silicon or Intel
- [Homebrew](https://brew.sh/)
- ~10GB disk space

Dependencies are installed automatically: [Lima](https://lima-vm.io/), [Ansible](https://www.ansible.com/), [jq](https://jqlang.github.io/jq/), [gitleaks](https://github.com/gitleaks/gitleaks), [Tailscale](https://tailscale.com/) (optional).

## License

MIT License. See [LICENSE](./LICENSE).

---

<div align="center">

**Provision once. Run forever.**

</div>
