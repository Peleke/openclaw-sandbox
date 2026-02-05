# VM Management

The sandbox runs inside a Lima VM named `openclaw-sandbox`. This page covers how to interact with the VM throughout its lifecycle -- opening shells, stopping, starting, deleting, and re-provisioning.

## Opening a Shell

There are two ways to get a shell inside the VM:

### Via bootstrap.sh

```bash
./bootstrap.sh --shell
```

This checks if the VM exists (errors if not), starts it if it's stopped, then opens an interactive shell. Under the hood it runs `limactl shell openclaw-sandbox`.

### Via limactl directly

```bash
limactl shell openclaw-sandbox
```

Same result, but won't auto-start a stopped VM -- you'd get an error if the VM isn't running.

### Running a single command

You don't need a full shell to run one-off commands. Pass them after `--`:

```bash
# Check gateway status
limactl shell openclaw-sandbox -- systemctl status openclaw-gateway

# View overlay state
limactl shell openclaw-sandbox -- overlay-status

# Check Docker
limactl shell openclaw-sandbox -- docker ps
```

## Stopping the VM

### `--kill` (force stop)

```bash
./bootstrap.sh --kill
```

This immediately force-stops the VM using `limactl stop --force openclaw-sandbox`. It's the equivalent of pulling the power cord. Use this when:

- The VM is unresponsive
- You want to free resources quickly
- You're done for the day

The VM's disk state is preserved. You can start it again later.

!!! note
    Force-stopping doesn't give services inside the VM a chance to shut down gracefully. If the agent was in the middle of writing files, the overlay upper layer might have partial writes. This is generally fine -- the overlay is inside the VM, not on your host.

### Graceful stop via limactl

```bash
limactl stop openclaw-sandbox
```

This sends a shutdown signal and waits for the VM to stop cleanly. Services get a chance to shut down gracefully. Prefer this over `--kill` when you're not in a hurry.

## Starting the VM

If the VM was stopped (via `--kill` or `limactl stop`), you have a few options to start it again:

### Just start it

```bash
limactl start openclaw-sandbox
```

This boots the VM but doesn't run Ansible. Services that were enabled (gateway, overlay, watcher) will start automatically via systemd.

### Re-provision (recommended)

```bash
./bootstrap.sh
```

Running bootstrap on an existing VM skips creation and just re-runs the Ansible playbook. This is the safest way to restart because it ensures everything is configured correctly. You don't need to pass `--openclaw` again -- the mount paths are already baked into the Lima config.

```bash
# Re-provision with updated secrets
./bootstrap.sh --secrets ~/.openclaw-secrets.env

# Re-provision with new variables
./bootstrap.sh -e "telegram_user_id=123456789"

# Re-provision with YOLO mode enabled
./bootstrap.sh --yolo
```

## Deleting the VM

```bash
./bootstrap.sh --delete
```

This completely removes the VM:

1. Force-stops the VM if it's running
2. Deletes the VM and all its disk data via `limactl delete`
3. Removes the generated Lima config file (`lima/openclaw-sandbox.generated.yaml`)

### When you need to delete

You must delete and recreate the VM when:

- **Changing mount paths** -- The `--openclaw`, `--vault`, or `--config` paths are baked into the Lima config at creation time
- **Switching to/from YOLO-Unsafe** -- Mount writability (read-only vs. read-write) is set at creation time
- **Changing VM resources** -- CPU, memory, and disk are set at creation time
- **Starting completely fresh** -- If something is broken beyond repair

```bash
# Delete and recreate with different paths
./bootstrap.sh --delete
./bootstrap.sh --openclaw /new/path/to/openclaw --vault ~/new-vault

# Delete and recreate with different resources
./bootstrap.sh --delete
VM_CPUS=8 VM_MEMORY=16GiB ./bootstrap.sh --openclaw ~/Projects/openclaw
```

!!! warning
    Deleting the VM destroys all data inside it, including:

    - The overlay upper layer (all pending unsynced changes)
    - Any files the agent created outside the overlay
    - Docker images and containers
    - Installed packages not managed by Ansible

    Make sure to sync any work you want to keep before deleting:

    ```bash
    ./scripts/sync-gate.sh    # sync overlay changes to host
    ./bootstrap.sh --delete   # then delete
    ```

## Running Onboard

```bash
./bootstrap.sh --onboard
```

This runs the interactive `openclaw onboard` wizard inside the VM. It's useful for initial setup when you don't have an existing `~/.openclaw` config directory to mount with `--config`.

The onboard command detects whether the overlay is active and runs from the right directory:

- If `/workspace` is mounted (overlay active): runs from `/workspace`
- Otherwise: runs from `/mnt/openclaw`

!!! tip
    If you already have a working `~/.openclaw` config on your Mac, skip onboard and use `--config ~/.openclaw` instead. It's faster and you don't have to re-enter everything.

## Re-provisioning

Running `bootstrap.sh` against an existing VM is idempotent. It:

1. Detects the VM already exists (skips creation)
2. Ensures Homebrew and dependencies are installed on your Mac
3. Starts the VM if it's stopped
4. Verifies host mounts are accessible
5. Runs the full Ansible playbook

This means you can safely re-run bootstrap whenever you:

- Pull new changes to the sandbox repo
- Update your secrets file
- Want to add a `-e` variable
- Switch between secure and YOLO mode (but not YOLO-Unsafe -- that needs a delete)

```bash
# These all work on an existing VM:
./bootstrap.sh
./bootstrap.sh --secrets ~/.openclaw-secrets.env
./bootstrap.sh --yolo
./bootstrap.sh -e "secrets_github_token=ghp_new_token"
```

!!! note
    When re-provisioning, you'll see a warning if you pass `--openclaw`:

    ```
    [WARN] Ignoring --openclaw (VM already exists)
    [WARN] To change paths: ./bootstrap.sh --delete && ./bootstrap.sh --openclaw ...
    ```

    This is expected. The path is baked into the Lima config and can't be changed without recreating.

## Useful limactl Commands

Beyond what `bootstrap.sh` wraps, here are `limactl` commands you might find handy:

### List VMs

```bash
limactl list
```

Shows all Lima VMs, their status, CPU/memory allocation, and disk usage.

### Check VM info

```bash
limactl list --json | jq '.[] | select(.name == "openclaw-sandbox")'
```

### SSH config

```bash
limactl show-ssh --format=config openclaw-sandbox
```

Shows the SSH connection details. Useful if you want to connect with a standard SSH client or configure your editor's remote development features.

### Copy files

```bash
# Host to VM
limactl copy local-file.txt openclaw-sandbox:/tmp/

# VM to host
limactl copy openclaw-sandbox:/workspace/output.txt ./
```

!!! tip
    For bulk file transfers from the overlay, use `sync-gate.sh` instead of `limactl copy`. It includes validation.

## Lifecycle Summary

| Action | Command | Notes |
|--------|---------|-------|
| Create + provision | `./bootstrap.sh --openclaw PATH` | First run |
| Re-provision | `./bootstrap.sh` | Existing VM |
| Open shell | `./bootstrap.sh --shell` | or `limactl shell openclaw-sandbox` |
| Graceful stop | `limactl stop openclaw-sandbox` | Clean shutdown |
| Force stop | `./bootstrap.sh --kill` | Immediate |
| Start | `limactl start openclaw-sandbox` | Without re-provisioning |
| Delete | `./bootstrap.sh --delete` | Destroys everything |
| Onboard | `./bootstrap.sh --onboard` | Interactive setup wizard |
