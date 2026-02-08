# bilrost

**Hardened Lima VM for running AI agents** — overlay isolation, network containment, secrets management, and gated sync.

## Install

```bash
# Via pipx (recommended)
pipx install bilrost

# Via uv
uv tool install bilrost

# Via pip
pip install bilrost
```

## Usage

```bash
# Interactive setup
bilrost init

# Provision the VM (~5 min first run)
bilrost up

# Check status
bilrost status

# SSH into the VM
bilrost ssh

# Sync overlay changes to host (with secret scanning)
bilrost sync

# Stop / destroy
bilrost down
bilrost destroy
```

## MCP Server

Agents can manage the sandbox programmatically via FastMCP:

```json
{
  "mcpServers": {
    "sandbox": {
      "command": "bilrost-mcp"
    }
  }
}
```

9 tools: `sandbox_status`, `sandbox_up`, `sandbox_down`, `sandbox_destroy`, `sandbox_exec`, `sandbox_validate`, `sandbox_ssh_info`, `sandbox_gateway_info`, `sandbox_agent_identity`.

## What It Does

- **OverlayFS isolation** — host code mounted read-only, all writes contained in VM overlay
- **Network containment** — UFW firewall with explicit allowlist (HTTPS, DNS, Tailscale, NTP only)
- **Secrets management** — three injection methods, `0600` perms, never in process lists
- **Gated sync** — gitleaks scanning + path allowlist before changes reach your host
- **Docker sandboxing** — per-session containers with configurable network isolation
- **12 Ansible roles** — overlay, secrets, gateway, docker, firewall, sync-gate, gh-cli, buildlog, cadence, qortex, tailscale, and more

## Requirements

- macOS (Apple Silicon or Intel)
- [Homebrew](https://brew.sh/)
- ~10GB disk space

Dependencies (Lima, Ansible, etc.) are installed automatically on first run.

## Documentation

Full docs: [peleke.github.io/openclaw-sandbox](https://peleke.github.io/openclaw-sandbox/)

## License

MIT
