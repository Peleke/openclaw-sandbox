# Changelog

All notable changes to openclaw-sandbox are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

**Cadence Wiring (PR #70)**
- End-to-end vault sync pipeline: Obsidian note → rsync → chokidar → signal bus → Telegram
- `--skills PATH` flag mounts custom skills directory at `/mnt/skills-custom` (read-only)
- `fileLogPath` in cadence.json enables container signal bridging via JSONL
- launchd plists for host-side scheduling (`com.openclaw.vault-sync.plist`, `com.openclaw.cadence.plist`)
- `--exclude=.obsidian/` in rsync avoids ESTALE on virtiofs lower-layer config files

**MCP Server (PR #65)**
- Agent-driven sandbox management via FastMCP (`sandbox-mcp` console script)
- Tools: `sandbox_up`, `sandbox_down`, `sandbox_status`, `sandbox_ssh`, `sandbox_sync`
- Runs over stdio transport for seamless integration with LLM agents
- Plain-function implementations for testability; registered via `mcp.tool(fn)`

**Secrets Auto-Export + Vault Rsync (PR #63)**
- iCloud lock bypass: rsync-based vault sync for files locked by iCloud Drive
- Host-side `sync-vault.sh` script for manual or cron-based vault sync

**Python CLI (PRs #60, #62)**
- Typer-based CLI replacing bash bootstrap as the primary interface
- Commands: `sandbox up`, `sandbox down`, `sandbox destroy`, `sandbox status`, `sandbox ssh`, `sandbox sync`, `sandbox dashboard`
- Profile-based configuration via `~/.openclaw-sandbox/profiles/`
- Interactive `sandbox init` wizard for profile creation

**File Ownership Fix (PR #58)**
- Agent identity persistence across VM restarts

**Dogfood-Ready Sandbox (PR #57)**
- Config/data isolation: `~/.openclaw/` config files copied (patchable), agent data symlinked to writable mount
- `--agent-data PATH` mounts persistent agent data at `/mnt/openclaw-agents`
- `--buildlog-data PATH` mounts persistent buildlog data at `/mnt/buildlog-data`
- Qortex interop role: seed exchange directories, buildlog interop config, qortex CLI
- `--memgraph` and `--memgraph-port` flags for Memgraph port forwarding

**Dual-Container Network Isolation (PR #55)**
- Per-tool network routing: two containers per scope (isolated + network)
- `networkAllow`: tool-level routing (`web_fetch`, `web_search` → bridge container)
- `networkExecAllow`: command-prefix routing (`gh` → bridge, others → air-gapped)
- `networkDocker`: bridge container config (network mode, DNS)
- Operator extension variables: `sandbox_network_allow_extra`, `sandbox_network_exec_allow_extra`
- BRAVE_API_KEY added to full secrets pipeline

**MkDocs Documentation (PR #41)**
- Full documentation site with MkDocs Material theme
- Architecture, configuration, security (STRIDE), development, and troubleshooting docs

**Obsidian Vault Access (PR #37)**
- Vault mounting with OverlayFS overlay at `/workspace-obsidian`
- Stale mount unit cleanup when vault is removed

**GitHub CLI Integration (PR #36)**
- gh-cli Ansible role with APT repo installation
- GH_TOKEN secrets pipeline integration and sandbox env passthrough

### Fixed

- Vault write access default changed from `ro` to `rw` (PR #67)
- Vault sync writes to merged overlay mount (`/workspace-obsidian/`) instead of upper dir, fixing inotify visibility (PR #70)
- Jinja2 operator precedence bug in networkExecAllow injection (PR #55)
- Obsidian overlay mount bad unit file error: double backslash → single in YAML plain scalar (PR #36)
- Obsidian mount failure when no vault mounted: stale unit cleanup (PR #37)

## [0.3.0] - 2026-02-03

### Added

**Phase S7: Cadence Ambient AI Pipeline**
- Ansible role `cadence` for ambient AI journal→insight→Telegram pipeline
- Systemd service `openclaw-cadence` for persistent execution
- Auto-creates `auth-profiles.json` for OpenClaw LLM access
- Comprehensive test suite (64 checks across 3 test files)
- E2E pipeline verification: file watcher → LLM extraction → Telegram delivery

**Phase S6: Telegram Delivery**
- Telegram bot integration for insight delivery
- Chat ID configuration in `cadence.json`

**Phase S5: Secrets Management**
- `/etc/openclaw/secrets.env` for API keys
- Mounted from host via Lima
- Systemd `EnvironmentFile` integration

**Phase S4: Tailscale Routing**
- VPN connectivity through host's Tailscale
- Route configuration for secure egress

**Phase S3: UFW Network Containment**
- Firewall rules for network isolation
- Allowlist-based egress control

**Phase S2: Gateway Service**
- OpenClaw gateway as systemd service
- Node.js and Bun installation
- Automatic dependency management

**Phase S1: Bootstrap Infrastructure**
- Lima VM configuration for Ubuntu Noble
- Mount points for OpenClaw repo, config, secrets, vault
- Ansible provisioning framework

### Fixed
- HOME path resolution with Ansible `become: true`
- Bun installing to /root instead of user home
- Test vm_exec preserving exit codes with Lima

## [0.2.0] - 2026-02-02

### Added
- Phases S4-S6: Tailscale, Secrets, Telegram integration
- Security roadmap issues (#9, #10, #11)

## [0.1.0] - 2026-02-01

### Added
- Initial bootstrap infrastructure
- Lima VM with Ubuntu Noble
- Basic Ansible playbook structure
- Gateway role for OpenClaw installation

[Unreleased]: https://github.com/Peleke/openclaw-sandbox/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Peleke/openclaw-sandbox/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Peleke/openclaw-sandbox/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Peleke/openclaw-sandbox/releases/tag/v0.1.0
