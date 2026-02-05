# Overlay Filesystem

The overlay role sets up Linux OverlayFS to give the agent a writable workspace while keeping your host files read-only. This page explains how OverlayFS works, how the sandbox configures it, and what happens to writes.

![Overlay Filesystem](../diagrams/overlay-filesystem.svg)

## OverlayFS in 30 Seconds

OverlayFS is a union filesystem built into the Linux kernel. It layers directories on top of each other:

- **lowerdir**: the read-only base (your project files from the host)
- **upperdir**: where all writes go (inside the VM, never touches the host)
- **workdir**: internal bookkeeping directory used by the kernel
- **merged**: the combined view that processes actually see

When a process reads a file, OverlayFS checks the upper layer first, then falls through to the lower layer. When a process writes a file, the write always goes to the upper layer. Deletes are recorded as "whiteout" files in the upper layer -- the original file in the lower layer is untouched.

## Directory Layout

The overlay role creates this structure inside the VM:

| Path | Role | Description |
|------|------|-------------|
| `/mnt/openclaw` | lowerdir | Read-only virtiofs mount of your project |
| `/var/lib/openclaw/overlay/openclaw/upper` | upperdir | All agent writes land here |
| `/var/lib/openclaw/overlay-work/openclaw` | workdir | Kernel bookkeeping |
| `/workspace` | merged | Unified view -- gateway and services run here |

For Obsidian vaults (when `--vault` is used):

| Path | Role | Description |
|------|------|-------------|
| `/mnt/obsidian` | lowerdir | Read-only virtiofs mount of your vault |
| `/var/lib/openclaw/overlay/obsidian/upper` | upperdir | Vault writes |
| `/var/lib/openclaw/overlay-work/obsidian` | workdir | Kernel bookkeeping |
| `/workspace-obsidian` | merged | Unified vault view |

## systemd Mount Units

The overlay is managed by systemd mount units, not fstab entries. The overlay role deploys them from Jinja2 templates.

### workspace.mount

Template: `ansible/roles/overlay/templates/workspace.mount.j2`

```ini
[Unit]
Description=OverlayFS workspace mount
After=local-fs.target
DefaultDependencies=no

[Mount]
What=overlay
Where=/workspace
Type=overlay
Options=lowerdir=/mnt/openclaw,upperdir=/var/lib/openclaw/overlay/openclaw/upper,workdir=/var/lib/openclaw/overlay-work/openclaw

[Install]
WantedBy=local-fs.target
```

The gateway service depends on this unit (`Requires=workspace.mount`, `After=workspace.mount`), so systemd ensures the overlay is mounted before the gateway starts.

### workspace-obsidian.mount

The Obsidian overlay follows the same pattern. The unit file is named `workspace\x2dobsidian.mount` because systemd requires mount unit filenames to match the mount path with special characters escaped.

!!! note "systemd mount unit naming"
    A mount at `/workspace-obsidian` requires a unit file named `workspace\x2dobsidian.mount`. The `\x2d` is the systemd escape for the `-` character. You can verify with: `systemd-escape --path /workspace-obsidian`.

If the vault is not mounted (no `--vault` flag), the role automatically cleans up stale obsidian mount units from previous provisioning runs -- stops the unit, disables it, and removes the file.

## The Audit Watcher

The overlay role deploys an `overlay-watcher.service` that uses `inotifywait` to monitor the upper directory:

```ini
[Service]
Type=simple
ExecStart=/usr/bin/inotifywait -m -r \
  --timefmt '%Y-%m-%dT%H:%M:%S' \
  --format '%T %w%f %e' \
  -e create -e modify -e delete -e move \
  /var/lib/openclaw/overlay/openclaw/upper
StandardOutput=append:/var/log/openclaw/overlay-watcher.log
```

This gives you a timestamped audit log of every filesystem change the agent makes:

```
2024-03-15T14:22:01 /var/lib/openclaw/overlay/openclaw/upper/src/index.ts MODIFY
2024-03-15T14:22:03 /var/lib/openclaw/overlay/openclaw/upper/src/new-file.ts CREATE
```

The watcher depends on `workspace.mount` and restarts on failure.

## Filesystem Modes

The overlay role supports three modes, controlled by `bootstrap.sh` flags:

### Secure Mode (default)

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw
```

- Host mounts: read-only
- Overlay: active
- Sync: manual via `sync-gate.sh`
- Variables: `overlay_enabled: true`, `overlay_yolo_unsafe: false`, `overlay_yolo_mode: false`

### YOLO Mode

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --yolo
```

- Host mounts: read-only
- Overlay: active
- Sync: automatic every 30 seconds
- Variables: `overlay_enabled: true`, `overlay_yolo_unsafe: false`, `overlay_yolo_mode: true`

In YOLO mode, the role deploys two additional systemd units:

**yolo-sync.service** (oneshot):
```ini
ExecStart=/usr/bin/rsync -av --delete \
  /var/lib/openclaw/overlay/openclaw/upper/ /mnt/openclaw/
```

**yolo-sync.timer**:
```ini
[Timer]
OnBootSec=60s
OnUnitActiveSec=30s
AccuracySec=5s
```

The timer fires 60 seconds after boot, then every 30 seconds (`overlay_yolo_sync_interval`). This bypasses sync-gate validation entirely.

### YOLO-Unsafe Mode

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --yolo-unsafe
```

- Host mounts: **read-write**
- Overlay: disabled
- Sync: not needed (writes go directly to host)
- Variables: `overlay_yolo_unsafe: true`

!!! warning
    YOLO-unsafe mode disables all filesystem isolation. Agent writes go directly to your host files. This requires deleting and recreating the VM (`--delete` first) because Lima mount writability is baked at creation time.

## How workspace_path Is Computed

The playbook (`ansible/playbook.yml`) sets `workspace_path` based on overlay state:

```yaml
workspace_path: >-
  {{ overlay_workspace_path | default('/workspace')
     if (overlay_enabled | default(true) | bool
         and not (overlay_yolo_unsafe | default(false) | bool))
     else openclaw_path }}
```

| Condition | workspace_path |
|-----------|---------------|
| Overlay enabled, not yolo-unsafe | `/workspace` (merged mount) |
| Overlay disabled or yolo-unsafe | `/mnt/openclaw` (direct host mount) |

Every role that needs to know where the project lives uses `{{ workspace_path }}` -- the gateway's `WorkingDirectory`, the sandbox's build commands, the buildlog's working directory, and so on.

## Role Defaults

All overlay configuration has sensible defaults in `ansible/roles/overlay/defaults/main.yml`:

```yaml
overlay_enabled: true
overlay_yolo_mode: false
overlay_yolo_unsafe: false

overlay_lower_openclaw: /mnt/openclaw
overlay_lower_obsidian: /mnt/obsidian
overlay_upper_base: /var/lib/openclaw/overlay
overlay_work_base: /var/lib/openclaw/overlay-work

overlay_workspace_path: /workspace
overlay_obsidian_path: /workspace-obsidian

overlay_yolo_sync_interval: "30s"
overlay_watcher_log: /var/log/openclaw/overlay-watcher.log
```

## Inspecting Overlay State

From the host:

```bash
# Check overlay mount status
limactl shell openclaw-sandbox -- mountpoint -q /workspace && echo "mounted" || echo "not mounted"

# See what's in the upper layer (agent writes)
limactl shell openclaw-sandbox -- ls /var/lib/openclaw/overlay/openclaw/upper/

# Check audit log
limactl shell openclaw-sandbox -- tail -20 /var/log/openclaw/overlay-watcher.log

# View overlay mount details
limactl shell openclaw-sandbox -- mount | grep overlay

# Check overlay helper scripts
limactl shell openclaw-sandbox -- overlay-status
```

To reset the overlay (discard all agent writes):

```bash
limactl shell openclaw-sandbox -- sudo overlay-reset
```

Or from the host using the sync-gate:

```bash
./scripts/sync-gate.sh --reset
```
