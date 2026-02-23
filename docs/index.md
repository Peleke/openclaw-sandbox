# Bilrost

<p style="font-style: italic; color: #888; margin-bottom: 0.5em;">
  Part of the <strong>qlawbox</strong> stack
  &nbsp;·&nbsp; <a href="https://peleke.github.io/openclaw/">vindler</a>
  &nbsp;·&nbsp; <a href="https://peleke.github.io/qortex/">qortex</a>
  &nbsp;·&nbsp; <a href="https://pypi.org/project/bilrost/">PyPI</a>
</p>

**Defense-in-depth sandbox for agent runtime containment.**

---

## The Problem

Running AI agents directly on your host machine is risky:

- **File access** -- agents can read sensitive files, credentials, SSH keys, and configs.
- **Unrestricted network** -- nothing prevents an agent from phoning home to arbitrary endpoints.
- **No process isolation** -- agent processes share your session, environment, and shell history.
- **Secret leakage** -- API keys end up in environment variables, logs, and `.bash_history`.

You need a boundary between "what the agent can touch" and "everything else on your machine."

## The Solution

Bilrost runs your agents inside a **hardened Linux VM** (Ubuntu 24.04 on Lima) with strict network policies, layered filesystem isolation, and secure secrets handling. Everything provisions from a single command on macOS.

<div style="max-width: 520px; margin: 1.5em auto;">
<svg viewBox="0 0 480 380" style="width: 100%; height: auto;" xmlns="http://www.w3.org/2000/svg" aria-label="Bilrost architecture: macOS host, Lima VM, OverlayFS, Docker sandbox">
  <defs>
    <filter id="roughen" x="-2%" y="-2%" width="104%" height="104%">
      <feTurbulence type="turbulence" baseFrequency="0.03" numOctaves="2" result="noise" seed="7"/>
      <feDisplacementMap in="SourceGraphic" in2="noise" scale="1" xChannelSelector="R" yChannelSelector="G"/>
    </filter>
    <filter id="glow">
      <feGaussianBlur stdDeviation="2.5" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <marker id="arr-p" viewBox="0 0 12 10" refX="10" refY="5" markerWidth="7" markerHeight="5" orient="auto-start-reverse" fill="none" stroke="rgb(168,85,247)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
      <path d="M 1,1 L 10,5 L 1,9"/>
    </marker>
  </defs>
  <rect width="480" height="380" rx="8" fill="#1a1a2e" stroke="rgb(168,85,247)" stroke-width="0.5" opacity="0.4"/>
  <!-- Layer 0: Host -->
  <g transform="rotate(-0.3, 240, 44)">
    <text x="52" y="26" font-family="'Caveat','Comic Sans MS',cursive" font-size="9" fill="#888888" letter-spacing="1">LAYER 0 · HOST</text>
    <path d="M 36,14 C 160,11 320,17 444,13 C 447,30 445,56 447,70 C 320,73 160,69 36,72 C 33,56 35,30 33,14" stroke="#e0e0e0" stroke-width="1.5" fill="rgba(168,85,247,0.04)" stroke-linecap="round" stroke-linejoin="round"/>
    <text x="52" y="52" font-family="'Caveat','Comic Sans MS',cursive" font-size="14" fill="#e0e0e0" font-weight="bold">macOS (Apple Silicon / Intel)</text>
  </g>
  <!-- Arrow -->
  <path d="M 240,76 C 242,86 238,92 240,100" stroke="rgb(168,85,247)" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-dasharray="5 4" opacity="0.6">
    <animate attributeName="stroke-dashoffset" from="0" to="-18" dur="2s" repeatCount="indefinite"/>
  </path>
  <!-- Layer 1: Lima VM -->
  <g transform="rotate(0.4, 240, 130)">
    <text x="52" y="110" font-family="'Caveat','Comic Sans MS',cursive" font-size="9" fill="rgb(168,85,247)" letter-spacing="1">LAYER 1 · LIMA VM</text>
    <path d="M 36,98 C 160,95 320,101 444,97 C 447,118 445,142 447,158 C 320,161 160,157 36,160 C 33,142 35,118 33,98" stroke="rgb(168,85,247)" stroke-width="2" fill="rgba(168,85,247,0.08)" stroke-linecap="round" stroke-linejoin="round"/>
    <text x="52" y="140" font-family="'Caveat','Comic Sans MS',cursive" font-size="13" fill="#e0e0e0">Ubuntu 24.04 · UFW Firewall · Ansible</text>
  </g>
  <!-- Arrow -->
  <path d="M 240,164 C 242,174 238,180 240,188" stroke="rgb(168,85,247)" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-dasharray="5 4" opacity="0.6">
    <animate attributeName="stroke-dashoffset" from="0" to="-18" dur="2s" repeatCount="indefinite"/>
  </path>
  <!-- Layer 2: OverlayFS -->
  <g transform="rotate(-0.5, 240, 218)">
    <text x="52" y="198" font-family="'Caveat','Comic Sans MS',cursive" font-size="9" fill="#888888" letter-spacing="1">LAYER 2 · OVERLAYFS</text>
    <path d="M 36,186 C 160,183 320,189 444,185 C 447,206 445,230 447,246 C 320,249 160,245 36,248 C 33,230 35,206 33,186" stroke="#e0e0e0" stroke-width="1.5" fill="rgba(168,85,247,0.04)" stroke-linecap="round" stroke-linejoin="round"/>
    <text x="52" y="228" font-family="'Caveat','Comic Sans MS',cursive" font-size="13" fill="#e0e0e0">host mounts read-only · writes contained</text>
  </g>
  <!-- Arrow -->
  <path d="M 240,252 C 242,262 238,268 240,276" stroke="rgb(168,85,247)" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-dasharray="5 4" opacity="0.6">
    <animate attributeName="stroke-dashoffset" from="0" to="-18" dur="2s" repeatCount="indefinite"/>
  </path>
  <!-- Layer 3: Docker — air-gapped -->
  <g transform="rotate(0.3, 145, 310)">
    <text x="52" y="286" font-family="'Caveat','Comic Sans MS',cursive" font-size="9" fill="#888888" letter-spacing="1">LAYER 3 · DOCKER</text>
    <path d="M 36,274 C 100,271 170,277 214,273 C 217,294 215,318 217,334 C 170,337 100,333 36,336 C 33,318 35,294 33,274" stroke="#e0e0e0" stroke-width="1.5" fill="rgba(168,85,247,0.04)" stroke-linecap="round" stroke-linejoin="round"/>
    <text x="52" y="302" font-family="'Caveat','Comic Sans MS',cursive" font-size="11" fill="#f87171" font-weight="bold">air-gapped</text>
    <text x="52" y="322" font-family="'Caveat','Comic Sans MS',cursive" font-size="11" fill="#888888">network: none</text>
  </g>
  <!-- Layer 3: Docker — bridge -->
  <g transform="rotate(-0.4, 355, 310)">
    <path d="M 246,274 C 320,271 400,277 444,273 C 447,294 445,318 447,334 C 400,337 320,333 246,336 C 243,318 245,294 243,274" stroke="rgb(168,85,247)" stroke-width="1.8" fill="rgba(168,85,247,0.08)" stroke-linecap="round" stroke-linejoin="round"/>
    <text x="262" y="302" font-family="'Caveat','Comic Sans MS',cursive" font-size="11" fill="#4ade80" font-weight="bold">bridge</text>
    <text x="262" y="322" font-family="'Caveat','Comic Sans MS',cursive" font-size="11" fill="#888888">per-tool routing</text>
  </g>
  <!-- Sync gate return arc -->
  <path d="M 448,304 C 462,304 468,290 468,260 C 468,180 468,100 468,60 C 468,36 462,28 448,28" stroke="rgb(168,85,247)" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-dasharray="6 4" opacity="0.5" filter="url(#glow)" marker-end="url(#arr-p)">
    <animate attributeName="stroke-dashoffset" from="0" to="20" dur="3s" repeatCount="indefinite"/>
  </path>
  <g transform="rotate(90, 474, 170)">
    <text x="474" y="170" text-anchor="middle" font-family="'Caveat','Comic Sans MS',cursive" font-size="9" fill="rgb(168,85,247)" opacity="0.7">sync gate</text>
  </g>
  <!-- Caption -->
  <text x="240" y="368" font-family="'Caveat','Comic Sans MS',cursive" font-size="10" fill="#888888" text-anchor="middle" opacity="0.6">dual-container isolation · gated sync · secrets never in logs</text>
</svg>
</div>

Changes only reach your host through a **validated sync gate** that runs gitleaks scanning, path allowlists, and size checks before anything is copied back.

## Feature Highlights

| Feature | What it does |
|---------|-------------|
| [Python CLI](usage/bootstrap-flags.md) | `bilrost up`, `bilrost status`, `bilrost ssh` — profile-based management |
| [Dual-Container Isolation](configuration/docker-sandbox.md) | Per-tool network routing: air-gapped by default, bridge only for tools that need it |
| [Filesystem Isolation](architecture/overlay-filesystem.md) | OverlayFS makes host mounts read-only; all writes land in an overlay layer |
| [Network Containment](configuration/network-policy.md) | UFW firewall allows only HTTPS, DNS, and Tailscale; everything else is denied and logged |
| [MCP Server](configuration/docker-sandbox.md) | LLM agents manage the sandbox via FastMCP (`bilrost-mcp`) |
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
# Install from PyPI
pip install bilrost
# or: pipx install bilrost / uv tool install bilrost

# Create a profile interactively
bilrost init

# Provision the VM
bilrost up

# Check status
bilrost status

# SSH into the VM
bilrost ssh
```

Or from source:

```bash
git clone https://github.com/Peleke/openclaw-sandbox.git
cd openclaw-sandbox
uv pip install -e cli/
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

## The qlawbox stack

Bilrost is the isolation layer. The full stack:

| Component | Role | Docs |
|-----------|------|------|
| **[vindler](https://peleke.github.io/openclaw/)** | Agent runtime (OpenClaw fork) | [Docs](https://peleke.github.io/openclaw/) |
| **bilrost** | Hardened VM isolation (this project) | [PyPI](https://pypi.org/project/bilrost/) |
| **[qortex](https://peleke.github.io/qortex/)** | Knowledge graph with adaptive learning | [PyPI](https://pypi.org/project/qortex/) |

## License

MIT License. See [LICENSE](https://github.com/Peleke/openclaw-sandbox/blob/main/LICENSE).
