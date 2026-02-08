# OpenClaw Sandbox

**Secure, isolated VM environment for running OpenClaw agents.**

---

## The Problem

Running AI agents directly on your host machine is risky:

- **File access** -- agents can read sensitive files, credentials, SSH keys, and configs.
- **Unrestricted network** -- nothing prevents an agent from phoning home to arbitrary endpoints.
- **No process isolation** -- agent processes share your session, environment, and shell history.
- **Secret leakage** -- API keys end up in environment variables, logs, and `.bash_history`.

You need a boundary between "what the agent can touch" and "everything else on your machine."

## The Solution

OpenClaw Sandbox runs your agents inside a **hardened Linux VM** (Ubuntu 24.04 on Lima) with strict network policies, layered filesystem isolation, and secure secrets handling. Everything provisions from a single command on macOS.

```
macOS Host
  └── Lima VM (Ubuntu 24.04)
        ├── OverlayFS (host mounts read-only, writes contained)
        ├── UFW Firewall (explicit allowlist only)
        ├── Docker Sandbox (tool execution in containers)
        └── Secrets Pipeline (never in logs or process lists)
```

Changes only reach your host through a **validated sync gate** that runs gitleaks scanning, path allowlists, and size checks before anything is copied back.

## Feature Highlights

| Feature | What it does |
|---------|-------------|
| [Python CLI](usage/bootstrap-flags.md) | `sandbox up`, `sandbox status`, `sandbox ssh` — profile-based management |
| [Dual-Container Isolation](configuration/docker-sandbox.md) | Per-tool network routing: air-gapped by default, bridge only for tools that need it |
| [Filesystem Isolation](architecture/overlay-filesystem.md) | OverlayFS makes host mounts read-only; all writes land in an overlay layer |
| [Network Containment](configuration/network-policy.md) | UFW firewall allows only HTTPS, DNS, and Tailscale; everything else is denied and logged |
| [MCP Server](configuration/docker-sandbox.md) | LLM agents manage the sandbox via FastMCP (`sandbox-mcp`) |
| [Secrets Management](configuration/secrets.md) | Multiple injection methods, file permissions at `0600`, never exposed in logs |
| [Config/Data Isolation](configuration/obsidian-vault.md) | Config files copied (patchable), agent data symlinked to persistent mounts |
| [Gated Sync](usage/sync-gate.md) | gitleaks scan + path allowlist before any changes reach the host |
| [GitHub CLI](configuration/github-cli.md) | `gh` installed in VM and sandbox containers with `GH_TOKEN` passthrough |
| [Obsidian Vault](configuration/obsidian-vault.md) | Vault bind-mounted with overlay protection; iCloud rsync sync |
| [Qortex Interop](configuration/qortex.md) | Seed exchange directories and buildlog interop for multi-agent coordination |
| [Telegram Integration](configuration/telegram.md) | Bot integration with pairing-based access control |
| [Cadence Pipeline](configuration/cadence.md) | Ambient AI: vault watch → insight extraction → Telegram delivery |
| [Tailscale Routing](configuration/network-policy.md) | Route to your private network via the host |

## Quick Start

```bash
# Clone the repository
git clone https://github.com/Peleke/openclaw-sandbox.git
cd openclaw-sandbox

# Install the CLI
pip install -e cli/

# Create a profile interactively
sandbox init

# Provision the VM
sandbox up

# Check status
sandbox status

# SSH into the VM
sandbox ssh
```

Or use `bootstrap.sh` directly:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

!!! tip
    Dependencies (Lima, Ansible, jq, gitleaks) are installed automatically via Homebrew. You just need macOS and Homebrew.

## Requirements

- macOS (Apple Silicon or Intel)
- [Homebrew](https://brew.sh/)
- ~10GB disk space

## Documentation

| Section | What's inside |
|---------|--------------|
| [Getting Started](getting-started/prerequisites.md) | Prerequisites, installation, and your first session |
| [Usage](usage/bootstrap-flags.md) | Bootstrap flags, filesystem modes, sync gate, and VM management |
| [Configuration](configuration/overview.md) | Secrets, Docker sandbox, network policy, Telegram, GitHub CLI, Obsidian, Cadence, and buildlog |
| [Architecture](architecture/overview.md) | System design, defense-in-depth layers, secrets pipeline, and overlay filesystem |
| [Security](security/threat-model.md) | Threat model and STRIDE analysis |
| [Development](development/testing.md) | Test suites, contributing guide, and release process |
| [Troubleshooting](troubleshooting.md) | Common issues, diagnostic commands, and recovery steps |

## Defense-in-Depth

Two layers of isolation work together:

```
Layer 1 (overlay):   gateway process  --> VM + read-only host mounts + OverlayFS
Layer 2 (docker):    tool execution   --> Isolated container (air-gapped)
                     network tools    --> Network container (bridge, per-tool routing)
```

Host mounts are **read-only by default**. All writes land in an OverlayFS upper layer inside the VM. Individual tool executions are further sandboxed inside Docker containers with **dual-container network isolation**: most tools run air-gapped, while only `web_fetch`, `web_search`, and `gh` commands get bridge networking.

## Security at a Glance

1. **Filesystem isolation** -- host mounts read-only, writes contained in OverlayFS
2. **Docker sandbox** -- tool executions in containers with bridge networking
3. **Gated sync** -- gitleaks scan + path allowlist before changes reach host
4. **Secrets never logged** -- all Ansible tasks use `no_log: true`
5. **File permissions** -- `/etc/openclaw/secrets.env` is `0600`
6. **No process exposure** -- `EnvironmentFile=` instead of `Environment=`
7. **Network isolation** -- explicit allowlist, all else denied and logged
8. **Audit trail** -- inotifywait watcher logs all overlay writes

## License

MIT License. See [LICENSE](https://github.com/Peleke/openclaw-sandbox/blob/main/LICENSE).
