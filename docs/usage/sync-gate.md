# Sync Gate

`sync-gate.sh` is the host-side script that moves changes from the VM's overlay layer back to your host filesystem. It extracts, validates, previews, and applies -- in that order.

This only applies to **secure mode** (the default). In YOLO mode, changes auto-sync on a timer. In YOLO-Unsafe mode, there's no overlay to sync.

## What It Does

The sync gate runs a four-step pipeline:

1. **Extract** -- Copies files from the overlay upper layer (`/var/lib/openclaw/overlay/openclaw/upper`) to a temporary staging directory on your Mac via rsync over SSH
2. **Validate** -- Runs gitleaks, checks for blocked file extensions, and flags oversized files
3. **Preview** -- Lists every file that would be synced, with sizes
4. **Apply** -- Rsyncs the validated staging directory into your host OpenClaw repo

If any validation step fails, the sync aborts and nothing reaches your host.

## Commands

### Interactive Sync (default)

The standard flow: extract, validate, preview, then ask for confirmation before applying.

```bash
./scripts/sync-gate.sh
```

Expected output:

```
[SYNC] OpenClaw Sync Gate
[SYNC] ==================

[STEP] Extracting pending changes from VM overlay...
[SYNC] Found 3 modified files.
[SYNC] Extracted to staging: /var/folders/.../tmp.xxxxx

[STEP] Validating changes...
[STEP] Running gitleaks secret scan...
[SYNC] gitleaks: no secrets detected.
[SYNC] Validation passed.

[STEP] Preview of changes to apply:

  src/index.ts (4521 bytes)
  src/utils/helper.ts (892 bytes)
  package.json (1205 bytes)

[SYNC] Total: 3 files, 6.2K

Apply these changes to host? (y/N) y

[STEP] Applying to: /Users/you/Projects/openclaw
[SYNC] Changes applied to host.
[SYNC] Review with: cd /Users/you/Projects/openclaw && git diff
```

### `--dry-run`

Run the full extract and validate pipeline, show the preview, but don't apply anything.

```bash
./scripts/sync-gate.sh --dry-run
```

This is useful for checking what the agent has done before committing to a sync.

### `--auto`

Skip the interactive confirmation prompt and apply immediately after validation passes. Intended for CI/automation pipelines.

```bash
./scripts/sync-gate.sh --auto
```

!!! warning
    `--auto` still runs the full validation pipeline (gitleaks, blocked extensions, size check). It only skips the "Apply these changes? (y/N)" prompt. If validation fails, the sync still aborts.

### `--status`

Show the overlay status inside the VM. This delegates to the `overlay-status` helper script deployed by the sync-gate Ansible role.

```bash
./scripts/sync-gate.sh --status
```

Expected output:

```
=== OverlayFS Status ===

Workspace overlay: MOUNTED at /workspace

=== Pending Changes (overlay upper) ===

Files modified/created: 3
Directories: 5
Total size: 6.2K

--- File listing ---
  src/index.ts (4521 bytes)
  src/utils/helper.ts (892 bytes)
  package.json (1205 bytes)

=== Watcher Log (last 10 entries) ===
2025-05-01T14:32:01 /var/lib/openclaw/overlay/openclaw/upper/src/index.ts MODIFY
2025-05-01T14:32:03 /var/lib/openclaw/overlay/openclaw/upper/src/utils/helper.ts CREATE
```

### `--reset`

Discard all overlay writes. This delegates to the `overlay-reset` helper script inside the VM, which requires root.

```bash
./scripts/sync-gate.sh --reset
```

!!! warning
    This is destructive. All pending changes in the overlay upper layer are permanently deleted. The reset script:

    1. Stops services that use the overlay (gateway, cadence, watcher)
    2. Unmounts the overlay
    3. Clears the upper and work directories
    4. Remounts the overlay
    5. Restarts all services

    You'll get a confirmation prompt before anything is deleted.

## The Validation Pipeline

Every sync (except `--status` and `--reset`) runs through three validation checks.

### 1. Blocked File Extensions

The script refuses to sync files with extensions that commonly contain secrets or credentials:

| Extension | Type |
|-----------|------|
| `.env` | Environment variables |
| `.pem` | TLS/SSH certificates |
| `.key` | Private keys |
| `.p12` | PKCS#12 keystores |
| `.pfx` | PKCS#12 keystores (Windows) |
| `.jks` | Java keystores |
| `.keystore` | Generic keystores |
| `.secret` | Generic secrets |
| `.credentials` | Generic credentials |

If any file in the overlay matches these extensions, the sync fails immediately.

### 2. File Size Check

Files larger than **10 MB** are flagged with a warning. This doesn't block the sync, but it alerts you to unexpectedly large files (like binaries or data dumps that shouldn't be in a source repo).

### 3. Gitleaks Secret Scan

If [gitleaks](https://github.com/gitleaks/gitleaks) is installed on your Mac (it's included in the Brewfile), the script runs a full secret scan on the staged files:

```bash
gitleaks detect --source="$STAGING_DIR" --no-git --no-banner
```

This catches secrets that might be embedded in source code -- API keys, tokens, passwords -- even if they don't have a telltale file extension. If gitleaks finds anything, the sync fails.

!!! tip
    gitleaks is installed automatically by the Brewfile. If it's missing for some reason:

    ```bash
    brew install gitleaks
    ```

## VM-Side Helpers

The sync-gate Ansible role deploys two helper scripts inside the VM at `/usr/local/bin/`. You can run them directly or through `limactl shell`.

### `overlay-status`

Reports the overlay state: whether it's mounted, how many files are pending, their sizes, and the last 10 audit watcher log entries.

```bash
# From the host
limactl shell openclaw-sandbox -- overlay-status

# From inside the VM
overlay-status
```

The output includes:

- Mount status of `/workspace`
- Count of modified/created files in the upper layer
- Total size of pending changes
- File listing (most recent 50 files)
- Last 10 entries from the watcher log

### `overlay-reset`

Clears all pending overlay writes and remounts. **Must be run as root.**

```bash
# From the host
limactl shell openclaw-sandbox -- sudo overlay-reset

# From inside the VM
sudo overlay-reset
```

The reset process:

1. Prompts for confirmation (shows file count)
2. Stops `openclaw-gateway`, `openclaw-cadence`, and `overlay-watcher` services
3. Unmounts `/workspace`
4. Deletes everything in the upper directory (`/var/lib/openclaw/overlay/openclaw/upper/`)
5. Deletes everything in the work directory (`/var/lib/openclaw/overlay-work/openclaw/`)
6. Remounts the workspace overlay (`workspace.mount`)
7. Restarts all stopped services

After reset, `/workspace` is a clean view of the read-only host mount with no pending changes.

## How Apply Works

When you confirm the sync, `sync-gate.sh` determines your host OpenClaw path by reading the generated Lima config (`lima/openclaw-sandbox.generated.yaml`) and finding the location associated with the `/mnt/openclaw` mount point.

It then rsyncs the staging directory into that host path:

```bash
rsync -av --ignore-existing "$STAGING_DIR/" "$OPENCLAW_HOST_PATH/"
```

!!! note
    The apply uses `--ignore-existing`, which means it won't overwrite files that already exist on the host. This is a safety measure -- if a file was modified both on host and in the overlay, the host version is preserved and you'll need to resolve that manually.

After applying, the script suggests reviewing with `git diff`:

```bash
cd /path/to/your/openclaw && git diff
```

## Typical Workflow

Here's how a typical secure-mode development session looks:

```bash
# 1. Bootstrap the VM
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env

# 2. Agent does work inside the VM (writes go to overlay)
# ... time passes ...

# 3. Check what the agent changed
./scripts/sync-gate.sh --dry-run

# 4. Looks good -- sync it
./scripts/sync-gate.sh

# 5. Review on host
cd ~/Projects/openclaw && git diff

# 6. Commit if happy
git add -p && git commit

# 7. Clear the overlay for the next round
./scripts/sync-gate.sh --reset
```
