# Qortex Interop

[Qortex](https://github.com/Peleke/qortex) is a knowledge-graph-backed coordination layer for multi-agent workflows. The sandbox's qortex role sets up **seed exchange directories** and **buildlog interop** so agents running in the sandbox can emit and consume structured signals.

## What It Does

The qortex role creates directory structure for signal exchange and optionally installs the qortex CLI:

1. **Seed exchange directories** — `~/.qortex/seeds/{pending,processed,failed}` for structured data handoff
2. **Signals directory** — `~/.qortex/signals/` for projection output (JSONL logs)
3. **Buildlog interop config** — `~/.buildlog/interop.yaml` linking buildlog to qortex's seed pipeline
4. **CLI installation** — `qortex` command via `uv tool install`

## Setup

Qortex is enabled by default when the sandbox is provisioned. No extra flags are needed:

```bash
# Using the Bilrost CLI (recommended)
bilrost up

# Using bootstrap.sh directly
./bootstrap.sh --openclaw ~/Projects/openclaw
```

### With Memgraph (Graph Database)

To enable Memgraph port forwarding for graph queries:

```bash
# Forward all Memgraph ports (7687, 3000, 7444)
./bootstrap.sh --openclaw ~/Projects/openclaw --memgraph

# Forward specific ports
./bootstrap.sh --openclaw ~/Projects/openclaw \
  --memgraph-port 7687 \
  --memgraph-port 3000
```

| Port | Service |
|------|---------|
| 7687 | Bolt protocol (Cypher queries) |
| 3000 | Memgraph Lab (web UI) |
| 7444 | Monitoring |

## Directory Structure

After provisioning, the VM has:

```
~/.qortex/
├── seeds/
│   ├── pending/       # New seeds waiting for processing
│   ├── processed/     # Successfully consumed seeds
│   └── failed/        # Seeds that failed processing
└── signals/
    └── projections.jsonl   # Signal projection output

~/.buildlog/
└── interop.yaml       # Buildlog ↔ Qortex exchange config
```

All directories are created with mode `0750`.

### Interop Configuration

The `interop.yaml` file tells buildlog where to find qortex's seed pipeline:

```yaml
---
sources:
  - name: qortex
    pending_dir: ~/.qortex/seeds/pending
    processed_dir: ~/.qortex/seeds/processed
    failed_dir: ~/.qortex/seeds/failed
    signal_log: ~/.qortex/signals/projections.jsonl
```

This enables buildlog to:

- Drop seeds into `pending/` for qortex to pick up
- Read signal projections from `signals/projections.jsonl`
- Track processing status via the `processed/` and `failed/` directories

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `qortex_enabled` | `true` | Enable qortex directory setup and interop config |
| `qortex_install` | `true` | Install qortex CLI via `uv tool install` |
| `qortex_extras` | `""` | Pip extras for qortex (e.g. `"anthropic"` for LLM features) |

Override with `-e`:

```bash
# Disable qortex entirely
./bootstrap.sh --openclaw ~/Projects/openclaw -e "qortex_enabled=false"

# Install with LLM extras
./bootstrap.sh --openclaw ~/Projects/openclaw -e 'qortex_extras=anthropic'
```

## Standalone Use

The qortex role guards `~/.buildlog` directory creation — if the buildlog role has already created it (e.g., as a Lima mount symlink), qortex skips that step. This means qortex works both:

- **With buildlog** — interop.yaml is deployed into the existing `~/.buildlog/`
- **Without buildlog** — qortex creates `~/.buildlog/` as a real directory and deploys interop.yaml

## Verification Commands

```bash
# Check seed directories exist
limactl shell openclaw-sandbox -- ls -la ~/.qortex/seeds/

# Check signals directory
limactl shell openclaw-sandbox -- ls -la ~/.qortex/signals/

# Check interop config
limactl shell openclaw-sandbox -- cat ~/.buildlog/interop.yaml

# Verify qortex CLI is installed
limactl shell openclaw-sandbox -- qortex --version

# Check uv tool list
limactl shell openclaw-sandbox -- ~/.local/bin/uv tool list | grep qortex
```

## Troubleshooting

### qortex CLI not found

1. Check uv is installed: `limactl shell openclaw-sandbox -- ~/.local/bin/uv --version`
2. Check tool list: `limactl shell openclaw-sandbox -- ~/.local/bin/uv tool list`
3. Re-provision: `bilrost up` or `./bootstrap.sh --openclaw ~/Projects/openclaw`

### interop.yaml missing

The interop config is only deployed if it doesn't already exist (to preserve manual edits). To force re-creation:

```bash
limactl shell openclaw-sandbox -- rm ~/.buildlog/interop.yaml
bilrost up  # or ./bootstrap.sh to re-provision
```

### Memgraph ports not forwarding

1. Verify `--memgraph` or `--memgraph-port` was passed at VM creation time
2. Lima port forwards are baked at creation — to change, delete and recreate:

```bash
bilrost destroy -f
./bootstrap.sh --openclaw ~/Projects/openclaw --memgraph
```
