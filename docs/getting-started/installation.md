# Installation

This page walks you through cloning the sandbox repo, running the bootstrap, and verifying that everything came up correctly. The whole process takes about 5-10 minutes on a decent connection (most of that is the Ubuntu image download on first run).

## Clone the Repository

```bash
git clone https://github.com/Peleke/openclaw-sandbox.git
cd openclaw-sandbox
```

## Run the Bootstrap

The `bootstrap.sh` script does everything: installs host dependencies via Homebrew, creates and starts a Lima VM, and runs Ansible to provision the full sandbox environment inside it.

### Minimal Bootstrap

At minimum, you need to point it at your local OpenClaw clone:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw
```

This gives you the **secure mode** defaults:

- Host mounts are **read-only**
- OverlayFS provides a writable `/workspace` inside the VM
- Docker sandbox is enabled
- Firewall is configured with an explicit allowlist

### Bootstrap with Secrets

To inject API keys and credentials:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

The secrets file is a standard `.env` format. See [Prerequisites](prerequisites.md#optional-a-secrets-file) for an example.

!!! tip
    You can also pass individual secrets directly with `-e`:

    ```bash
    ./bootstrap.sh --openclaw ~/Projects/openclaw \
      -e "secrets_anthropic_api_key=sk-ant-xxx" \
      -e "secrets_github_token=ghp_xxx"
    ```

### Bootstrap with an Obsidian Vault

If you want the agent to have read-only access to an Obsidian vault:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --vault ~/Documents/Vaults/main
```

### What Happens During Bootstrap

Here is roughly what you will see:

```
[INFO] OpenClaw Sandbox Bootstrap
[INFO] ==========================

[STEP] Generating Lima configuration...
[INFO] Secure mode: host mounts will be READ-ONLY (overlay provides /workspace)
[INFO] Generated: ./lima/openclaw-sandbox.generated.yaml
[INFO] Mounts:
[INFO]   /mnt/openclaw  -> /Users/you/Projects/openclaw (read-only + overlay)
[INFO]   /mnt/provision -> /Users/you/Projects/openclaw-sandbox (read-only)
[INFO]   /workspace     -> OverlayFS merge (services run here)

[INFO] Homebrew found.
[STEP] Installing dependencies from Brewfile...
[INFO] Dependencies installed.
[STEP] Installing Ansible collections...

[INFO] Creating Lima VM 'openclaw-sandbox'...
[STEP] Ensuring VM is running...
[INFO] Starting Lima VM 'openclaw-sandbox'...
[STEP] Verifying host mounts...
[INFO] /mnt/openclaw ✓
[INFO] /mnt/provision ✓

[STEP] Running Ansible playbook...
... (Ansible output: firewall, overlay, Docker, gateway, etc.) ...

[INFO] ==========================
[INFO] Bootstrap complete!

[INFO] VM 'openclaw-sandbox' is running.
[INFO] Access via:  limactl shell openclaw-sandbox
[INFO] Stop with:   ./bootstrap.sh --kill
[INFO] Delete with: ./bootstrap.sh --delete

[INFO] Secure mode: overlay active, host mounts are READ-ONLY.
[INFO] Services run from: /workspace
[INFO] Sync to host: scripts/sync-gate.sh
```

!!! note
    The first run downloads the Ubuntu 24.04 cloud image (~600 MB). Subsequent bootstraps reuse the cached image and are much faster.

## Verify the Installation

### Check the VM is Running

From your Mac terminal:

```bash
limactl list
```

You should see output like:

```
NAME               STATUS    SSH            CPUS    MEMORY    DISK      DIR
openclaw-sandbox   Running   127.0.0.1:N    4       8GiB      50GiB     ~/.lima/openclaw-sandbox
```

### Shell Into the VM

```bash
limactl shell openclaw-sandbox
```

This drops you into a bash shell inside the Ubuntu VM. You will land in your home directory as your current macOS username.

!!! note "Lima cd warnings"
    You may see a warning like `bash: line 1: cd: /Users/you/Projects/openclaw-sandbox: No such file or directory`. This is harmless -- Lima tries to match your host working directory inside the VM, but that path does not exist there. You are still in the VM; just `cd /workspace` to get to the project.

### Check Key Services

From inside the VM (or prefix commands with `limactl shell openclaw-sandbox --`):

```bash
# Gateway should be active
systemctl status openclaw-gateway

# Overlay should be mounted
mountpoint -q /workspace && echo "Overlay mounted" || echo "No overlay"

# Docker should be running (if not bootstrapped with --no-docker)
docker info
```

### Check the Sandbox Image

```bash
docker images | grep openclaw-sandbox
```

Expected:

```
openclaw-sandbox   bookworm-slim   abc123def456   ...   ~300MB
```

## Re-Running the Bootstrap

The bootstrap is **idempotent**. Running it again on an existing VM will re-run the Ansible provisioning without recreating the VM:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

!!! warning "Changing mount paths requires a VM recreate"
    Lima mounts are baked at VM creation time. If you need to change the `--openclaw`, `--vault`, or `--config` paths, you must delete and recreate the VM:

    ```bash
    ./bootstrap.sh --delete
    ./bootstrap.sh --openclaw ~/new/path --secrets ~/.openclaw-secrets.env
    ```

## Host-Side Scheduling (Optional)

The sandbox ships launchd plists for automated host-side tasks. **These are not installed by bootstrap** — they are manual, opt-in steps because they run on your Mac, not inside the VM.

| Plist | Script | Interval | Purpose |
|-------|--------|----------|---------|
| `com.openclaw.vault-sync.plist` | `sync-vault.sh` | 5 min | Keep VM vault current with iCloud |
| `com.openclaw.cadence.plist` | cadence host process | -- | Ambient AI signal coordinator |
| `com.openclaw.dashboard-sync.plist` | `dashboard-sync.sh` | 10 min | Sync GitHub issues to Obsidian kanban boards |

To install any of them:

```bash
cp scripts/<plist-name> ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/<plist-name>
```

!!! warning "Full Disk Access required"
    launchd agents that access `~/Documents/` or `~/Library/Mobile Documents/` need Full Disk Access (FDA) for `/bin/bash`. Grant it in **System Settings > Privacy & Security > Full Disk Access**.

For details, see [Cadence > Host-Side Scheduling](../configuration/cadence.md#host-side-scheduling-launchd) and [Dashboard Sync](../configuration/dashboard-sync.md#automated-scheduling-launchd).

## Common First-Run Issues

### "Homebrew is not installed"

The bootstrap requires Homebrew. Install it from [brew.sh](https://brew.sh/):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### "OpenClaw path does not exist"

Double-check the path you passed to `--openclaw`. It must point to an existing directory (your local OpenClaw repo clone).

### VM Creation Hangs or Fails

If `limactl create` hangs, it may be a network issue downloading the Ubuntu image. Check your internet connection and try again. You can also check Lima logs:

```bash
limactl list
ls ~/.lima/openclaw-sandbox/
```

### "VM already exists. Path options only apply to new VMs."

This warning means you are passing `--openclaw` to an already-created VM. The path is ignored because Lima mounts are fixed at creation time. If you need different mounts, delete and recreate:

```bash
./bootstrap.sh --delete
./bootstrap.sh --openclaw ~/Projects/openclaw
```

### Ansible Fails Mid-Run

The playbook is idempotent, so you can safely re-run `bootstrap.sh` after fixing the issue. Ansible will skip tasks that already completed successfully.

## Next Steps

Once the bootstrap completes successfully, head to [First Session](first-session.md) to learn how to work inside the sandbox.
