# Configuration Overview

Every configurable aspect of the Bilrost maps to an Ansible variable, a file on the VM, and a way to change it. This page is the single source of truth for what you can configure and how.

![Architecture](../diagrams/architecture.svg)

## How Configuration Works

Configuration flows through three layers:

1. **Bootstrap flags** -- command-line arguments to `./bootstrap.sh` that set Lima VM properties (mounts, network) and Ansible variables
2. **Ansible variables** -- role defaults that control provisioning behavior, overridable with `-e "var=value"`
3. **VM files** -- the generated configuration files, systemd units, and environment files inside the Lima VM

!!! note "Lima mounts are baked at VM creation"
    Changing mount modes (e.g., switching from secure to `--yolo-unsafe`) requires `./bootstrap.sh --delete` followed by a fresh bootstrap. Ansible variables can be changed on re-provision without deleting.

## Complete Variable Reference

### Secrets Role (`ansible/roles/secrets/defaults/main.yml`)

| Variable | Default | VM File | Description | How to Set |
|----------|---------|---------|-------------|------------|
| `secrets_anthropic_api_key` | `""` | `/etc/openclaw/secrets.env` | Claude API key | `-e` or secrets file |
| `secrets_openai_api_key` | `""` | `/etc/openclaw/secrets.env` | OpenAI API key | `-e` or secrets file |
| `secrets_gemini_api_key` | `""` | `/etc/openclaw/secrets.env` | Google Gemini API key | `-e` or secrets file |
| `secrets_openrouter_api_key` | `""` | `/etc/openclaw/secrets.env` | OpenRouter API key | `-e` or secrets file |
| `secrets_gateway_password` | `""` | `/etc/openclaw/secrets.env` | Gateway auth password | `-e` or secrets file |
| `secrets_gateway_token` | `""` | `/etc/openclaw/secrets.env` | Gateway auth token | `-e` or secrets file |
| `secrets_github_token` | `""` | `/etc/openclaw/secrets.env` | GitHub CLI token (`GH_TOKEN`) | `-e` or secrets file |
| `secrets_slack_bot_token` | `""` | `/etc/openclaw/secrets.env` | Slack bot integration | `-e` or secrets file |
| `secrets_discord_bot_token` | `""` | `/etc/openclaw/secrets.env` | Discord bot integration | `-e` or secrets file |
| `secrets_telegram_bot_token` | `""` | `/etc/openclaw/secrets.env` | Telegram bot integration | `-e` or secrets file |
| `secrets_env_file` | `/etc/openclaw/secrets.env` | -- | Output file path | `-e` |
| `secrets_env_file_mode` | `0600` | -- | File permissions | `-e` |
| `secrets_env_dir` | `/etc/openclaw` | -- | Secrets directory path | `-e` |
| `secrets_env_dir_mode` | `0755` | -- | Secrets directory permissions | `-e` |
| `secrets_mount_dir` | `/mnt/secrets` | -- | Where secrets file is mounted | `--secrets` flag |
| `secrets_filename` | `""` | -- | Mounted secrets filename (set by bootstrap) | `--secrets` flag |
| `secrets_skip` | `false` | -- | Skip secrets provisioning | `-e "secrets_skip=true"` |

### Overlay Role (`ansible/roles/overlay/defaults/main.yml`)

| Variable | Default | VM File | Description | How to Set |
|----------|---------|---------|-------------|------------|
| `overlay_enabled` | `true` | systemd mount units | Master switch for overlay | `--yolo-unsafe` disables |
| `overlay_yolo_mode` | `false` | `yolo-sync.timer` | Auto-sync every 30s | `--yolo` flag |
| `overlay_yolo_unsafe` | `false` | -- | Skip overlay, rw mounts | `--yolo-unsafe` flag |
| `overlay_lower_openclaw` | `/mnt/openclaw` | `workspace.mount` | Read-only host mount | Set by Lima config |
| `overlay_lower_obsidian` | `/mnt/obsidian` | `workspace\x2dobsidian.mount` | Obsidian vault lower dir | `--vault` flag |
| `overlay_upper_base` | `/var/lib/openclaw/overlay` | `workspace.mount` | Where writes land | `-e` |
| `overlay_work_base` | `/var/lib/openclaw/overlay-work` | `workspace.mount` | OverlayFS work dir | `-e` |
| `overlay_workspace_path` | `/workspace` | `workspace.mount` | Merged mount point | `-e` |
| `overlay_obsidian_path` | `/workspace-obsidian` | `workspace\x2dobsidian.mount` | Obsidian merged mount | `-e` |
| `overlay_yolo_sync_interval` | `30s` | `yolo-sync.timer` | YOLO auto-sync interval | `-e` |
| `overlay_watcher_log` | `/var/log/openclaw/overlay-watcher.log` | `overlay-watcher.service` | Audit log path | `-e` |

### Sandbox Role (`ansible/roles/sandbox/defaults/main.yml`)

| Variable | Default | VM File | Description | How to Set |
|----------|---------|---------|-------------|------------|
| `sandbox_enabled` | `{{ docker_enabled }}` | -- | Master switch | Follows `docker_enabled` |
| `sandbox_mode` | `all` | `openclaw.json` | Sandbox mode: `off`, `non-main`, `all` | `-e` |
| `sandbox_scope` | `session` | `openclaw.json` | Scope: `session`, `agent`, `shared` | `-e` |
| `sandbox_workspace_access` | `rw` | `openclaw.json` | Workspace access: `none`, `ro`, `rw` | `-e` |
| `sandbox_image` | `openclaw-sandbox:bookworm-slim` | Docker image | Container image name | `-e` |
| `sandbox_build_browser` | `false` | Docker image | Build browser sandbox image | `-e` |
| `sandbox_docker_network` | `bridge` | `openclaw.json` | Network: `bridge`, `host`, `none` | `-e` |
| `sandbox_setup_script` | `scripts/sandbox-setup.sh` | -- | Build script location | `-e` |
| `sandbox_vault_path` | `/workspace-obsidian` | `openclaw.json` | Vault bind mount source | `-e` |
| `sandbox_vault_access` | `rw` | `openclaw.json` | Vault access: `ro`, `rw` | `-e` |

### Docker Role (`ansible/roles/docker/defaults/main.yml`)

| Variable | Default | VM File | Description | How to Set |
|----------|---------|---------|-------------|------------|
| `docker_enabled` | `true` | -- | Master switch for Docker CE | `--no-docker` flag |
| `docker_storage_driver` | `""` (auto) | `/etc/docker/daemon.json` | Storage driver override | `-e` |
| `docker_data_root` | `/var/lib/docker` | `/etc/docker/daemon.json` | Docker data directory | `-e` |

### Firewall Role (`ansible/roles/firewall/defaults/main.yml`)

| Variable | Default | VM File | Description | How to Set |
|----------|---------|---------|-------------|------------|
| `firewall_reset_on_run` | `true` | UFW rules | Reset to clean state each run | `-e "firewall_reset_on_run=false"` |
| `firewall_gateway_port` | `18789` | UFW rules | Inbound port for gateway | `-e` |
| `firewall_tailscale_cidr` | `100.64.0.0/10` | UFW rules | Tailscale CGNAT range | `-e` |
| `firewall_tailscale_port` | `41641` | UFW rules | Tailscale direct UDP port | `-e` |
| `firewall_enable_logging` | `true` | UFW config | Log denied connections | `-e` |
| `firewall_log_limit` | `3/min` | UFW config | Rate limit for log entries | `-e` |

### GitHub CLI Role (`ansible/roles/gh-cli/defaults/main.yml`)

| Variable | Default | VM File | Description | How to Set |
|----------|---------|---------|-------------|------------|
| `gh_cli_enabled` | `true` | -- | Install `gh` from official repo | `-e "gh_cli_enabled=false"` |

### Cadence Role (`ansible/roles/cadence/defaults/main.yml`)

| Variable | Default | VM File | Description | How to Set |
|----------|---------|---------|-------------|------------|
| `cadence_enabled` | `false` | `~/.openclaw/cadence.json` | Enable cadence pipeline | `-e "cadence_enabled=true"` |
| `cadence_vault_path` | `/mnt/obsidian` | `cadence.json` | Vault path inside VM | `-e` |
| `cadence_delivery_channel` | `telegram` | `cadence.json` | Delivery: `telegram`, `discord`, `log` | `-e` |
| `cadence_telegram_chat_id` | `""` | `cadence.json` | Telegram chat ID for delivery | `-e` |
| `cadence_llm_provider` | `anthropic` | `cadence.json` | LLM provider | `-e` |
| `cadence_llm_model` | `claude-3-5-haiku-latest` | `cadence.json` | LLM model | `-e` |
| `cadence_schedule_enabled` | `true` | `cadence.json` | Enable scheduled digests | `-e` |
| `cadence_nightly_digest` | `21:00` | `cadence.json` | Nightly digest time | `-e` |
| `cadence_morning_standup` | `08:00` | `cadence.json` | Morning standup time | `-e` |
| `cadence_timezone` | `America/New_York` | `cadence.json` | Schedule timezone | `-e` |

### Buildlog Role (`ansible/roles/buildlog/defaults/main.yml`)

| Variable | Default | VM File | Description | How to Set |
|----------|---------|---------|-------------|------------|
| `buildlog_version` | `""` (latest) | -- | Pin to a specific version | `-e "buildlog_version=0.5.0"` |
| `buildlog_extras` | `anthropic` | -- | Python extras for LLM support | `-e` |
| `buildlog_host_claude_md_path` | `/mnt/provision/CLAUDE.md` | `~/.claude/CLAUDE.md` | Host CLAUDE.md to copy into VM | `--claude-md` flag |

### Tailscale Role (`ansible/roles/tailscale/defaults/main.yml`)

| Variable | Default | VM File | Description | How to Set |
|----------|---------|---------|-------------|------------|
| `tailscale_cidr` | `100.64.0.0/10` | -- | Tailscale CGNAT range | `-e` |
| `tailscale_test_ips` | `[]` | -- | IPs to test connectivity | `-e` |
| `tailscale_verify_routing` | `true` | -- | Verify routing works | `-e` |
| `tailscale_fail_on_unreachable` | `false` | -- | Fail if Tailscale unreachable | `-e` |

### Playbook-Level Variables (`ansible/playbook.yml`)

| Variable | Default | Description | How to Set |
|----------|---------|-------------|------------|
| `tenant_name` | `$USER` | Tenant identifier | `-e` |
| `provision_path` | `/mnt/provision` | Provision mount point | Set by bootstrap |
| `openclaw_path` | `/mnt/openclaw` | OpenClaw source mount | `--openclaw` flag |
| `obsidian_path` | `/mnt/obsidian` | Obsidian vault mount | `--vault` flag |
| `openclaw_user` | `openclaw` | Service user | `-e` |
| `gateway_port` | `18789` | Gateway listen port | `-e` |
| `gateway_bind` | `0.0.0.0` | Gateway bind address | `-e` |
| `workspace_path` | `/workspace` (computed) | Where services run | Determined by overlay state |

## Provisioning Order

The playbook executes roles in this order:

1. **secrets** -- load and write secrets first so they are available to later roles
2. **overlay** -- set up OverlayFS so `/workspace` is ready
3. **docker** -- install Docker CE runtime
4. **gh-cli** -- install GitHub CLI from official APT repo
5. **gateway** -- deploy and configure the OpenClaw gateway service
6. **firewall** -- apply UFW network containment rules
7. **tailscale** -- configure Tailscale routing through host
8. **cadence** -- deploy ambient AI pipeline
9. **buildlog** -- install buildlog for ambient learning capture
10. **sandbox** -- build Docker sandbox image, configure `openclaw.json`
11. **sync-gate** -- deploy sync-gate helper scripts

!!! tip "Re-running provisioning"
    You can re-run `./bootstrap.sh` at any time to apply configuration changes. Only Lima mount changes (affecting the VM itself) require `--delete` first. All Ansible variables can be changed with `-e` on re-provision.

## Key Files on the VM

| File | Purpose | Managed By |
|------|---------|------------|
| `/etc/openclaw/secrets.env` | All secrets (mode 0600) | secrets role |
| `/etc/systemd/system/openclaw-gateway.service` | Gateway systemd unit | gateway role |
| `/etc/systemd/system/openclaw-cadence.service` | Cadence systemd unit | cadence role |
| `/etc/systemd/system/workspace.mount` | OverlayFS mount for `/workspace` | overlay role |
| `/etc/systemd/system/workspace\x2dobsidian.mount` | OverlayFS mount for `/workspace-obsidian` | overlay role |
| `/etc/systemd/system/overlay-watcher.service` | Audit watcher for overlay writes | overlay role |
| `~/.openclaw/openclaw.json` | OpenClaw gateway + sandbox config | gateway + sandbox roles |
| `~/.openclaw/cadence.json` | Cadence pipeline config | cadence role |
| `~/.claude/CLAUDE.md` | Agent instructions (buildlog + sandbox policy) | buildlog role |
