# Dashboard Sync (GitHub to Obsidian)

The dashboard sync pulls GitHub issues across your repositories into Obsidian as kanban boards, individual issue notes, and a Dataview dashboard. It runs on the **host** (not inside the VM) and writes directly to your Obsidian vault.

## What It Creates

After a sync, your vault will contain:

```
<vault>/
  Engineering/
    Master Kanban.md          # All issues across all repos, grouped by state
    <owner>-<repo> Kanban.md  # Per-repo board (one per repo with issues)
    Issues/
      <owner>-<repo>/
        <number>-<slug>.md    # Individual issue note with YAML frontmatter
    Dashboard.md              # Dataview-powered summary table
```

Each issue note includes frontmatter with `repo`, `number`, `state`, `labels`, `assignees`, `created`, and `updated` fields. The kanban boards use Obsidian's native kanban plugin format.

## Prerequisites

- An Obsidian vault on the host filesystem
- The sync script at `<vault>/_scripts/gh-obsidian-sync.py` (or a custom path)
- `gh` CLI authenticated (the script calls `gh issue list` and `gh api`)
- Python 3.11+ on the host

## Configuration

Add a `[dashboard]` section to your sandbox profile (`~/.openclaw/sandbox-profile.toml`):

```toml
[dashboard]
enabled = true
sync_interval = 1
vault_path = "~/Documents/Vaults/MyVault"
lookback_days = 14
repos = []
script_path = ""
```

| Field | Default | Description |
|-------|---------|-------------|
| `enabled` | `false` | Enable dashboard sync |
| `sync_interval` | `1` | Sync every Nth heartbeat tick (reserved for future cadence integration) |
| `vault_path` | `""` | Path to Obsidian vault on host. Falls back to `mounts.vault` if empty |
| `lookback_days` | `14` | Only sync issues updated within this many days |
| `repos` | `[]` | Explicit repo list (`["owner/repo", ...]`). Empty = all repos visible to `gh` |
| `script_path` | `""` | Path to sync script. Empty = auto-discover at `<vault>/_scripts/gh-obsidian-sync.py` |

!!! tip "Vault path fallback"
    If `vault_path` is empty, the CLI falls back to `mounts.vault` from the `[mounts]` section. Set `vault_path` explicitly if your host vault is at a different location than the VM mount source (e.g., iCloud path vs local symlink).

## Usage

### CLI Command

```bash
# Run the sync
bilrost dashboard sync

# Preview without writing files
bilrost dashboard sync --dry-run
```

The `bilrost dashboard` command (without `sync`) still opens the gateway dashboard in your browser, same as before. Use `--page` to jump to a specific page:

```bash
bilrost dashboard              # open gateway dashboard
bilrost dashboard --page green # open Green dashboard
bilrost dashboard sync         # run GitHub-to-Obsidian sync
```

### MCP Tool

The `sandbox_dashboard_sync` MCP tool lets agents trigger the sync programmatically:

```json
{
  "tool": "sandbox_dashboard_sync",
  "arguments": {
    "dry_run": false
  }
}
```

Returns `{ "stdout": "...", "stderr": "...", "exit_code": 0 }`.

### Host-Side Wrapper Script

`scripts/dashboard-sync.sh` is a standalone bash script that reads config from the sandbox profile and runs the sync. It is useful for cron/launchd automation or running outside the CLI:

```bash
# Manual run
./scripts/dashboard-sync.sh

# Dry run
./scripts/dashboard-sync.sh --dry-run
```

## Automated Scheduling (launchd)

A launchd plist is provided at `scripts/com.openclaw.dashboard-sync.plist` for periodic sync on macOS. **This is a manual host-side step** — bootstrap and Ansible do not install host launchd agents.

### Installation

```bash
# Copy the plist to your LaunchAgents directory
cp scripts/com.openclaw.dashboard-sync.plist ~/Library/LaunchAgents/

# Load it (starts immediately and runs every 10 minutes)
launchctl load ~/Library/LaunchAgents/com.openclaw.dashboard-sync.plist
```

### Verify it is running

```bash
launchctl list | grep com.openclaw.dashboard-sync
```

### Check logs

```bash
cat /tmp/dashboard-sync.log
```

### Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.openclaw.dashboard-sync.plist
rm ~/Library/LaunchAgents/com.openclaw.dashboard-sync.plist
```

!!! warning "Full Disk Access required"
    launchd agents cannot access `~/Documents/` (or `~/Library/Mobile Documents/`) without Full Disk Access (FDA). Grant FDA to `/bin/bash` in **System Settings > Privacy & Security > Full Disk Access**. Running the script manually from Terminal works without this step because Terminal typically has FDA.

    This is the same requirement as the vault-sync and cadence host plists. See [Cadence > Host-Side Scheduling](cadence.md#host-side-scheduling-launchd) for more detail.

!!! note "Not handled by bootstrap"
    All host-side launchd plists (vault-sync, cadence, dashboard-sync) are manual installs. Bootstrap provisions the **VM** via Ansible — it does not modify your macOS LaunchAgents. This is by design: host-side scheduling is a user choice, not a provisioning step.

## Troubleshooting

### "Operation not permitted" in logs

The launchd agent is hitting the FDA restriction. Grant Full Disk Access to `/bin/bash` (see warning above).

### "Sync script not found"

The sync script is auto-discovered at `<vault>/_scripts/gh-obsidian-sync.py`. If your script is elsewhere, set `script_path` explicitly in the `[dashboard]` section of your profile.

### "No vault path configured"

Set either `dashboard.vault_path` or `mounts.vault` in `~/.openclaw/sandbox-profile.toml`.

### Sync runs but creates no files

- Check that `gh` is authenticated: `gh auth status`
- Check `--days` window: issues older than `lookback_days` are skipped
- Run with `--dry-run` to see what would be created without writing
