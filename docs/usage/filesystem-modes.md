# Filesystem Modes

Bilrost provides three filesystem modes that control how the agent interacts with your host files. The default is the most restrictive -- you opt into less isolation as needed.

## How It Works

When you run `bootstrap.sh`, your OpenClaw repo is mounted into the VM via Lima's virtiofs. What happens next depends on which mode you chose:

- **Secure mode** wraps that mount in an OverlayFS layer so the agent never writes to your host
- **YOLO mode** does the same overlay, but periodically syncs changes back automatically
- **YOLO-Unsafe mode** skips the overlay entirely and mounts your host directory read-write

## Mode Comparison

| | Secure (default) | YOLO | YOLO-Unsafe |
|---|---|---|---|
| **Flag** | _(none)_ | `--yolo` | `--yolo-unsafe` |
| **Host mounts** | Read-only | Read-only | Read-write |
| **OverlayFS** | Active | Active | Disabled |
| **Writes land in** | Overlay upper layer | Overlay upper layer | Host filesystem directly |
| **Sync to host** | Manual via `sync-gate.sh` | Auto every 30s | Immediate (no sync needed) |
| **Validation** | gitleaks + blocked extensions + size check | None (bypassed) | N/A |
| **Audit trail** | inotifywait watcher logs all writes | inotifywait watcher logs all writes | None |
| **VM recreate needed** | No | No | Yes |

## Secure Mode (Default)

This is the default. You don't pass any extra flags.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw
```

### What happens

1. Your OpenClaw repo mounts read-only at `/mnt/openclaw`
2. An OverlayFS layer merges it with a writable upper directory
3. The merged view appears at `/workspace` -- this is where services run
4. All writes land in `/var/lib/openclaw/overlay/openclaw/upper` inside the VM
5. An `inotifywait` watcher logs every write to `/var/log/openclaw/overlay-watcher.log`
6. Nothing reaches your host until you explicitly run `sync-gate.sh`

### Key paths inside the VM

| Path | Purpose |
|------|---------|
| `/mnt/openclaw` | Read-only host mount (OverlayFS lower) |
| `/var/lib/openclaw/overlay/openclaw/upper` | Writable upper layer (writes land here) |
| `/workspace` | Merged OverlayFS mount (services run here) |
| `/var/log/openclaw/overlay-watcher.log` | Audit log of all filesystem writes |

### When to use it

- You want full control over what changes reach your host
- You're running an agent you haven't tested yet
- You want an audit trail of every file the agent touches
- You're doing security-sensitive work

### Syncing changes back

When you're ready to apply the agent's work to your host:

```bash
# Preview what would sync
./scripts/sync-gate.sh --dry-run

# Validate and apply (interactive confirmation)
./scripts/sync-gate.sh

# Or auto-apply for CI
./scripts/sync-gate.sh --auto
```

See [Sync Gate](sync-gate.md) for full details on the validation pipeline.

## YOLO Mode

Overlay is still active, but changes auto-sync back to the host on a timer.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --yolo
```

### What happens

1. Everything from secure mode still applies -- read-only mounts, OverlayFS, audit watcher
2. Additionally, a systemd timer (`yolo-sync.timer`) fires every 30 seconds
3. The timer triggers `yolo-sync.service`, which rsyncs the overlay upper layer directly back to the host mount at `/mnt/openclaw`

### The timer

The sync interval defaults to 30 seconds. It starts 60 seconds after boot to let the system settle:

```ini
[Timer]
OnBootSec=60s
OnUnitActiveSec=30s
AccuracySec=5s
```

### When to use it

- You trust what the agent is doing and want to iterate fast
- You're actively watching the agent and want changes reflected on host in near-real-time
- You want the overlay's audit trail but don't want to manually sync

!!! warning
    YOLO mode bypasses the sync-gate validation pipeline. There's no gitleaks scan, no blocked extension check, and no size limit enforcement on auto-synced files. The rsync runs with `--delete`, so files removed in the overlay are also removed on the host.

### Switching to YOLO mode

You can switch between secure and YOLO mode without recreating the VM -- just re-provision:

```bash
./bootstrap.sh --yolo
```

To go back to secure mode, re-provision without the flag:

```bash
./bootstrap.sh
```

## YOLO-Unsafe Mode

No overlay at all. Your host directories are mounted read-write. The agent writes directly to your filesystem.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --yolo-unsafe
```

### What happens

1. Your OpenClaw repo mounts **read-write** at `/mnt/openclaw`
2. No OverlayFS is created -- `/workspace` is not used
3. Services run directly from `/mnt/openclaw`
4. There is no audit watcher, no sync gate, no validation
5. Agent writes go straight to your host filesystem

### When to use it

- You're comfortable with the agent having full write access
- You're doing quick local development and want zero overhead
- You understand the risks and just want it to work like a normal mount

!!! warning
    This is called "unsafe" for a reason. A misbehaving agent can delete files, overwrite configs, or write secrets to disk -- all directly on your host.

### Requires VM recreate

Lima mount writability is set at VM creation time. You can't switch to or from YOLO-Unsafe without deleting and recreating the VM:

```bash
# Switch TO yolo-unsafe
./bootstrap.sh --delete
./bootstrap.sh --openclaw ~/Projects/openclaw --yolo-unsafe

# Switch BACK to secure mode
./bootstrap.sh --delete
./bootstrap.sh --openclaw ~/Projects/openclaw
```

!!! note
    This is a Lima limitation, not a Bilrost one. Virtiofs mount options are baked into the VM definition at creation time.

## Obsidian Vault Overlay

When you mount a vault with `--vault`, it gets the same overlay treatment as the OpenClaw repo:

| Mode | Vault mount | Vault overlay |
|------|-------------|---------------|
| Secure / YOLO | `/mnt/obsidian` (read-only) | `/workspace-obsidian` (merged) |
| YOLO-Unsafe | `/mnt/obsidian` (read-write) | None |

The vault overlay uses its own upper directory at `/var/lib/openclaw/overlay/obsidian/upper`, separate from the openclaw overlay. The systemd mount unit is `workspace\x2dobsidian.mount` (the `\x2d` is the systemd escape for `-`).

## Ansible Variables

These are the overlay role defaults that control behavior. You normally don't need to change them -- they're set automatically by `bootstrap.sh` flags.

| Variable | Default | Description |
|----------|---------|-------------|
| `overlay_enabled` | `true` | Master switch for the overlay |
| `overlay_yolo_mode` | `false` | Enable auto-sync timer |
| `overlay_yolo_unsafe` | `false` | Disable overlay, use rw mounts |
| `overlay_lower_openclaw` | `/mnt/openclaw` | Read-only host mount path |
| `overlay_lower_obsidian` | `/mnt/obsidian` | Read-only vault mount path |
| `overlay_upper_base` | `/var/lib/openclaw/overlay` | Base path for upper directories |
| `overlay_work_base` | `/var/lib/openclaw/overlay-work` | Base path for work directories |
| `overlay_workspace_path` | `/workspace` | Merged mount point for openclaw |
| `overlay_obsidian_path` | `/workspace-obsidian` | Merged mount point for vault |
| `overlay_yolo_sync_interval` | `30s` | Auto-sync timer interval |
| `overlay_watcher_log` | `/var/log/openclaw/overlay-watcher.log` | Audit watcher log path |

## Decision Flowchart

Not sure which mode to pick? Here's a quick guide:

1. **Are you running an untested agent or doing security-sensitive work?** Use **secure mode** (default).
2. **Do you trust the agent but want fast feedback?** Use **YOLO mode** (`--yolo`).
3. **Are you doing quick local dev and don't care about isolation?** Use **YOLO-Unsafe** (`--yolo-unsafe`).

When in doubt, start with secure mode. You can always run `sync-gate.sh` to push changes to host, and you can switch to YOLO mode later without recreating the VM.
