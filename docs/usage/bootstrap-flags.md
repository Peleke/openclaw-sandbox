# Bootstrap Flags

!!! note "Python CLI is the recommended interface"
    The primary way to manage your sandbox is now the **Python CLI** (`sandbox` command). The CLI wraps `bootstrap.sh` with a profile-based configuration system and interactive setup:

    ```bash
    # Create a profile interactively
    sandbox init

    # Provision or re-provision
    sandbox up

    # Check status
    sandbox status

    # SSH into the VM
    sandbox ssh

    # Sync overlay changes to host
    sandbox sync

    # Stop the VM
    sandbox down

    # Delete the VM
    sandbox destroy
    ```

    See [Getting Started](../getting-started/first-session.md) for a walkthrough. The flags documented below still work with `bootstrap.sh` directly and are useful for understanding what the CLI does under the hood.

`bootstrap.sh` is the underlying entry point for creating, configuring, and managing your sandbox VM. This page documents every flag, environment variable, and usage pattern.

## Required Flags

### `--openclaw PATH`

Path to your local OpenClaw repository clone. This is **required when creating a new VM** -- the directory gets mounted into the VM at `/mnt/openclaw` (read-only by default).

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw
./bootstrap.sh --openclaw ../openclaw
```

!!! note
    Once a VM exists, `--openclaw` is ignored on subsequent runs. Lima mounts are baked at VM creation time. To change the path, you need to delete and recreate:

    ```bash
    ./bootstrap.sh --delete
    ./bootstrap.sh --openclaw /new/path/to/openclaw
    ```

## Optional Flags

### `--secrets PATH`

Mount a `.env` file containing secrets into the VM. The file is mounted read-only at `/mnt/secrets/` and Ansible extracts individual values into `/etc/openclaw/secrets.env` (mode `0600`).

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

The secrets file is a standard `.env` format:

```env
ANTHROPIC_API_KEY=sk-ant-xxx
OPENAI_API_KEY=sk-xxx
OPENCLAW_GATEWAY_PASSWORD=mypass
GH_TOKEN=ghp_xxx
TELEGRAM_BOT_TOKEN=your-bot-token
```

!!! tip
    This is the recommended approach for development. Create the file once and pass it on every bootstrap.

### `--config PATH`

Mount your host OpenClaw config directory into the VM at `/mnt/openclaw-config`. The gateway role symlinks this to `~/.openclaw` inside the VM, giving the agent access to existing auth credentials and configuration.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --config ~/.openclaw
```

!!! note
    If you don't have an existing config directory, skip this flag and run `./bootstrap.sh --onboard` after bootstrap to set up config interactively inside the VM.

### `--vault PATH`

Mount an Obsidian vault into the VM at `/mnt/obsidian`. In secure mode, an OverlayFS layer is created at `/workspace-obsidian` so the vault is read-only from the host's perspective.

```bash
# Standard path
./bootstrap.sh --openclaw ~/Projects/openclaw --vault ~/Documents/Vaults/main

# iCloud-synced vault (note the quotes for spaces)
./bootstrap.sh --openclaw ~/Projects/openclaw \
  --vault "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/MyVault"
```

When a vault is mounted, sandbox containers automatically get a read-only bind mount at `/workspace-obsidian`, and the gateway exports `OBSIDIAN_VAULT_PATH=/workspace-obsidian`.

### `--no-docker`

Skip Docker CE installation and sandbox container setup entirely. This gives you a lighter VM if you don't need containerized tool execution.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --no-docker
```

### `--yolo`

Enable YOLO mode: the overlay is still active (host mounts remain read-only), but a systemd timer automatically syncs changes from the overlay upper layer back to the host every 30 seconds.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --yolo
```

!!! warning
    YOLO mode bypasses the sync-gate validation pipeline (no gitleaks scan, no blocked extension checks). Use it when you trust what the agent is doing and want faster iteration.

### `--yolo-unsafe`

Disable the overlay entirely. Host directories are mounted **read-write** -- the agent writes directly to your host filesystem with no isolation layer.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --yolo-unsafe
```

!!! warning
    This requires a VM recreate because Lima mount writability is baked at VM creation time:

    ```bash
    ./bootstrap.sh --delete
    ./bootstrap.sh --openclaw ~/Projects/openclaw --yolo-unsafe
    ```

### `--agent-data PATH`

Mount a directory for persistent agent data (green.db, learning.db) at `/mnt/openclaw-agents` inside the VM. Agent data files are symlinked from `~/.openclaw/` to this mount so they persist across VM recreations.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --agent-data ~/.openclaw/agents
```

### `--buildlog-data PATH`

Mount a directory for persistent buildlog data at `/mnt/buildlog-data` inside the VM.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --buildlog-data ~/.buildlog
```

### `--skills PATH`

Mount a custom skills directory at `/mnt/skills-custom` (read-only) inside the VM. Used by cadence for loading custom skill definitions.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --skills ~/Projects/skills/skills/custom
```

### `--memgraph`

Forward all Memgraph ports (7687, 3000, 7444) from the VM to the host for graph database access.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --memgraph
```

### `--memgraph-port PORT`

Forward a specific Memgraph port. Can be specified multiple times.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw \
  --memgraph-port 7687 \
  --memgraph-port 3000
```

### `-e KEY=VALUE`

Pass extra variables directly to the Ansible playbook. Can be used multiple times. This is the primary way to inject secrets without a file, or to set Ansible variables like the Telegram user ID.

**Injecting API keys:**

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "secrets_anthropic_api_key=sk-ant-xxx"
```

**Injecting a GitHub token:**

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "secrets_github_token=ghp_xxx"
```

**Pre-approving a Telegram user:**

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "telegram_user_id=123456789"
```

**Multiple variables at once:**

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "secrets_anthropic_api_key=sk-ant-xxx" \
  -e "secrets_github_token=ghp_xxx" \
  -e "telegram_user_id=123456789"
```

## Action Flags

These flags perform a specific action and exit immediately. They don't run the full bootstrap flow.

### `--kill`

Force-stop the VM immediately. Equivalent to pulling the power cord.

```bash
./bootstrap.sh --kill
```

This runs `limactl stop --force openclaw-sandbox`. The VM's disk state is preserved -- you can start it again by running bootstrap or `limactl start openclaw-sandbox`.

### `--delete`

Delete the VM completely, including its disk. Also removes the generated Lima config file.

```bash
./bootstrap.sh --delete
```

You need this when:

- Switching between secure mode and `--yolo-unsafe` (mount writability changes)
- Changing the `--openclaw` path
- Changing the `--vault` path
- Starting completely fresh

### `--shell`

Open an interactive shell inside the VM. If the VM is stopped, it starts it first.

```bash
./bootstrap.sh --shell
```

This is a convenience wrapper around `limactl shell openclaw-sandbox`.

### `--onboard`

Run the interactive `openclaw onboard` wizard inside the VM. Useful for initial setup when you don't have an existing `~/.openclaw` config to mount.

```bash
./bootstrap.sh --onboard
```

The onboard command runs inside whichever workspace is available -- `/workspace` if overlay is mounted, otherwise `/mnt/openclaw`.

### `--help`

Show the full usage message and exit.

```bash
./bootstrap.sh --help
```

## Environment Variables

These control VM resource allocation. Set them before running bootstrap.

| Variable | Default | Description |
|----------|---------|-------------|
| `VM_CPUS` | `4` | Number of virtual CPUs |
| `VM_MEMORY` | `8GiB` | Memory allocation |
| `VM_DISK` | `50GiB` | Disk size |

**Examples:**

```bash
# Beefy VM for heavy workloads
VM_CPUS=8 VM_MEMORY=16GiB VM_DISK=100GiB \
  ./bootstrap.sh --openclaw ~/Projects/openclaw

# Lightweight VM for testing
VM_CPUS=2 VM_MEMORY=4GiB VM_DISK=20GiB \
  ./bootstrap.sh --openclaw ~/Projects/openclaw
```

!!! note
    These only take effect when creating a new VM. To change resources on an existing VM, delete and recreate:

    ```bash
    ./bootstrap.sh --delete
    VM_CPUS=8 VM_MEMORY=16GiB ./bootstrap.sh --openclaw ~/Projects/openclaw
    ```

## Re-provisioning

Running `bootstrap.sh` again on an existing VM skips creation and just re-runs the Ansible playbook. This is useful for:

- Updating configuration after changing your secrets file
- Re-deploying after pulling new ansible role changes
- Adding `-e` variables you forgot the first time

```bash
# VM already exists -- this just re-provisions
./bootstrap.sh --secrets ~/.openclaw-secrets.env -e "telegram_user_id=123456789"
```

!!! tip
    You don't need to pass `--openclaw` when re-provisioning an existing VM. The mount paths are already baked into the Lima config.

## Full Examples

### Using the Python CLI (recommended)

```bash
# Interactive profile setup — walks you through all options
sandbox init

# Provision the VM with your saved profile
sandbox up

# Re-provision after config changes
sandbox up

# Check what's running
sandbox status

# SSH into the VM
sandbox ssh

# Sync overlay changes back to host
sandbox sync
```

### Using bootstrap.sh directly

```bash
# Minimal: just the openclaw repo
./bootstrap.sh --openclaw ~/Projects/openclaw

# Kitchen sink: secrets, config, vault, agent data, skills
./bootstrap.sh --openclaw ~/Projects/openclaw \
  --secrets ~/.openclaw-secrets.env \
  --config ~/.openclaw \
  --vault ~/Documents/Vaults/main \
  --agent-data ~/.openclaw/agents \
  --buildlog-data ~/.buildlog \
  --skills ~/Projects/skills/skills/custom \
  -e "telegram_user_id=123456789"

# YOLO mode for fast iteration
./bootstrap.sh --openclaw ~/Projects/openclaw --yolo

# Lightweight VM without Docker
./bootstrap.sh --openclaw ~/Projects/openclaw --no-docker

# With Memgraph graph database
./bootstrap.sh --openclaw ~/Projects/openclaw --memgraph

# CI/testing: direct secret injection, no interactive prompts
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "secrets_anthropic_api_key=sk-ant-xxx" \
  -e "secrets_gateway_password=mypass"
```
