# Obsidian Vault Access

The sandbox can mount an Obsidian vault from your host, giving agents read-only access to your notes and knowledge base. The vault is available both in the VM and inside sandbox containers.

## Setup

Pass the `--vault` flag when bootstrapping:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --vault ~/Documents/Vaults/main
```

This mounts your vault directory into the Lima VM at `/mnt/obsidian` via virtiofs (read-only by default from the host side).

!!! warning "Mount modes are baked at VM creation"
    The `--vault` flag creates a Lima mount. If you initially bootstrapped without `--vault` and want to add a vault later, you need to delete and recreate the VM:
    ```bash
    ./bootstrap.sh --delete
    ./bootstrap.sh --openclaw ~/Projects/openclaw --vault ~/Documents/Vaults/main
    ```

## How It Works

### OverlayFS Layer

Like the main OpenClaw source, the vault gets an OverlayFS overlay:

| Path | Purpose |
|------|---------|
| `/mnt/obsidian` | Host mount (read-only lower dir) |
| `/var/lib/openclaw/overlay/obsidian/upper` | Overlay upper dir (writes land here) |
| `/workspace-obsidian` | Merged mount point (agents see this) |

The systemd mount unit is `workspace\x2dobsidian.mount` (the `\x2d` is the systemd escape for the `-` character in mount paths).

### Gateway Environment Variable

When the vault mount is detected, the gateway systemd service exports:

```ini
Environment=OBSIDIAN_VAULT_PATH=/workspace-obsidian
```

This tells agents where to find vault files without hardcoding the path.

### Container Bind Mount

The sandbox role automatically adds a read-only bind mount into Docker containers:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "docker": {
          "binds": ["/workspace-obsidian:/workspace-obsidian:ro"]
        }
      }
    }
  }
}
```

!!! note "Read-only by default"
    The vault is mounted as `ro` (read-only) in containers. This is controlled by the `sandbox_vault_access` variable, which defaults to `ro`. Change it with:
    ```bash
    -e "sandbox_vault_access=rw"
    ```

## Stale Mount Cleanup

If you previously bootstrapped with `--vault` but later re-provision without it, the overlay role automatically cleans up the stale obsidian mount unit:

1. Checks if `/mnt/obsidian` exists (the Lima mount)
2. If it does not exist, checks for a stale `workspace\x2dobsidian.mount` unit
3. Stops the mount, disables it, and removes the unit file

This prevents systemd failures from mount units pointing to nonexistent lower directories.

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `overlay_lower_obsidian` | `/mnt/obsidian` | Host vault mount point |
| `overlay_obsidian_path` | `/workspace-obsidian` | Merged overlay mount point |
| `sandbox_vault_path` | `/workspace-obsidian` | Source path for container bind mount |
| `sandbox_vault_access` | `ro` | Container access: `ro` or `rw` |

## Verification Commands

```bash
# Check vault mount exists in VM
limactl shell openclaw-sandbox -- mountpoint /workspace-obsidian

# List vault contents
limactl shell openclaw-sandbox -- ls /workspace-obsidian

# Check systemd mount unit
limactl shell openclaw-sandbox -- systemctl status workspace\\x2dobsidian.mount

# Verify OBSIDIAN_VAULT_PATH in gateway env
limactl shell openclaw-sandbox -- systemctl show openclaw-gateway --property=Environment | grep OBSIDIAN

# Check vault is visible inside containers
limactl shell openclaw-sandbox -- docker run --rm \
  -v /workspace-obsidian:/workspace-obsidian:ro alpine ls /workspace-obsidian

# Check sandbox config for vault bind
limactl shell openclaw-sandbox -- jq '.agents.defaults.sandbox.docker.binds' ~/.openclaw/openclaw.json
# Expected: ["/workspace-obsidian:/workspace-obsidian:ro"]
```

## Troubleshooting

### Vault directory is empty

1. Check the Lima mount exists: `ls /mnt/obsidian`
2. If empty, the vault path might be wrong. Delete and re-create the VM with the correct `--vault` path
3. Check Lima mount status: `limactl list --json | jq '.[] | .mounts'`

### Mount unit failed

```bash
# Check the unit status
limactl shell openclaw-sandbox -- systemctl status workspace\\x2dobsidian.mount

# Check journalctl for errors
limactl shell openclaw-sandbox -- sudo journalctl -u workspace\\x2dobsidian.mount
```

Common causes:

- The lower directory `/mnt/obsidian` does not exist (VM created without `--vault`)
- The upper or work directories are missing (run `./bootstrap.sh` again to recreate)

### Vault not visible in containers

1. Check the bind mount is in `openclaw.json`: `jq '.agents.defaults.sandbox.docker.binds' ~/.openclaw/openclaw.json`
2. Check `/workspace-obsidian` exists and is mounted on the VM
3. Restart the gateway after config changes: `sudo systemctl restart openclaw-gateway`
