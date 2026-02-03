# Changelog

All notable changes to openclaw-sandbox are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
