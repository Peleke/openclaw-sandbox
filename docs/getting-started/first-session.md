# First Session

Your VM is running and the bootstrap completed. Now what? This page covers how to connect, verify that everything is healthy, and start using the sandbox for real work.

## Connect to the VM

From your Mac terminal:

```bash
limactl shell openclaw-sandbox
```

You are now inside the Ubuntu 24.04 VM. Your username matches your macOS account. The first thing you will want to do is navigate to the workspace:

```bash
cd /workspace
```

This is where the action happens. `/workspace` is an OverlayFS merge of your read-only host mount (`/mnt/openclaw`) and a writable upper layer. You can read all your project files and write freely -- nothing touches your host filesystem until you explicitly sync.

!!! tip
    You can also run one-off commands from the host without opening a full shell:

    ```bash
    limactl shell openclaw-sandbox -- ls /workspace
    ```

## Health Checks

Run through these to confirm the sandbox is in good shape.

### Gateway

The OpenClaw gateway is a systemd service that listens on port 18789:

```bash
systemctl status openclaw-gateway
```

You should see `active (running)`. If it shows `failed`, check the logs:

```bash
sudo journalctl -u openclaw-gateway --no-pager -n 50
```

### Overlay Filesystem

Verify the overlay is mounted:

```bash
mountpoint -q /workspace && echo "Overlay is mounted" || echo "Overlay is NOT mounted"
```

For more detail:

```bash
overlay-status
```

This is a helper script installed by the sandbox. It shows the overlay upper layer usage and mount state.

### Docker

If your bootstrap included Docker (the default), verify it is running:

```bash
docker info
```

Check the sandbox image:

```bash
docker images | grep openclaw-sandbox
```

Expected output:

```
openclaw-sandbox   bookworm-slim   abc123def456   2 hours ago   ~300MB
```

And check for any containers from previous sessions:

```bash
docker ps -a
```

### Firewall

The VM has a UFW firewall with an explicit allowlist. To see the rules:

```bash
sudo ufw status verbose
```

### Secrets

If you bootstrapped with `--secrets`, verify they landed:

```bash
sudo cat /etc/openclaw/secrets.env
```

!!! warning
    This file is `0600` (root-only read). The gateway reads it via `EnvironmentFile=` in its systemd unit, so secrets never appear in process listings or logs.

## Run the Onboard Flow

If this is a fresh OpenClaw setup and you need to configure the agent interactively, run the onboard from the host:

```bash
./bootstrap.sh --onboard
```

Or from inside the VM:

```bash
cd /workspace
node dist/index.js onboard
```

This walks you through the OpenClaw first-run setup (provider selection, model config, etc.).

## Working in the Sandbox

### File Edits Stay in the Overlay

Any file you create or modify under `/workspace` is written to the OverlayFS upper layer, not to your host filesystem. This means:

- You can experiment freely without risk
- Your host repo stays clean
- You decide when (and what) to sync back

To see what has changed in the overlay:

```bash
overlay-status
```

Or from the host:

```bash
./scripts/sync-gate.sh --dry-run
```

### Syncing Changes to Host

When you are ready to push approved changes back to your host:

```bash
# From the host (not inside the VM)
./scripts/sync-gate.sh
```

This runs validation (gitleaks secret scan, path allowlist, size checks) and then applies the changes interactively. For more on the sync workflow, see [Sync Gate](../usage/sync-gate.md).

### Using GitHub CLI

If you provided a `GH_TOKEN` in your secrets, `gh` is ready to go:

```bash
# Inside the VM
source /etc/openclaw/secrets.env
gh auth status
```

The `gh` CLI is also available inside Docker sandbox containers automatically.

### Checking Logs

Gateway logs (where agent activity shows up):

```bash
sudo journalctl -u openclaw-gateway -f
```

Application-level logs:

```bash
tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log
```

## Stopping and Starting

### Stop the VM

From the host:

```bash
./bootstrap.sh --kill
```

Or equivalently:

```bash
limactl stop --force openclaw-sandbox
```

### Start it Again

```bash
limactl start openclaw-sandbox
```

The VM retains all state (overlay writes, Docker images, systemd configuration) across stops and starts. You do not need to re-run the bootstrap unless you want to re-provision.

### Delete and Start Fresh

If you want a clean slate:

```bash
./bootstrap.sh --delete
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

!!! warning
    Deleting the VM destroys all overlay writes, Docker images, and any state inside the VM. Make sure to sync anything you want to keep before deleting.

## Quick Reference

| Task | Command |
|---|---|
| Open VM shell | `limactl shell openclaw-sandbox` |
| Check gateway | `limactl shell openclaw-sandbox -- systemctl status openclaw-gateway` |
| Check overlay | `limactl shell openclaw-sandbox -- mountpoint -q /workspace && echo OK` |
| View gateway logs | `limactl shell openclaw-sandbox -- sudo journalctl -u openclaw-gateway -f` |
| See overlay changes | `./scripts/sync-gate.sh --dry-run` |
| Sync to host | `./scripts/sync-gate.sh` |
| Reset overlay | `limactl shell openclaw-sandbox -- sudo overlay-reset` |
| Stop VM | `./bootstrap.sh --kill` |
| Delete VM | `./bootstrap.sh --delete` |
| Re-provision | `./bootstrap.sh --openclaw ~/Projects/openclaw` |
| Run onboard | `./bootstrap.sh --onboard` |
| Dashboard sync | `sandbox dashboard sync` |
| Dashboard sync (dry run) | `sandbox dashboard sync --dry-run` |

## Next Steps

- **[Filesystem Modes](../usage/filesystem-modes.md)** -- Learn about secure, YOLO, and YOLO-unsafe modes
- **[Secrets](../configuration/secrets.md)** -- Configure API keys and credentials
- **[Docker Sandbox](../configuration/docker-sandbox.md)** -- Understand how tool executions are containerized
- **[Sync Gate](../usage/sync-gate.md)** -- Manage the host sync pipeline
