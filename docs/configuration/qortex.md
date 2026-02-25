# Qortex Interop

[Qortex](https://github.com/Peleke/qortex) provides vector search, knowledge graph retrieval, and a Thompson Sampling bandit for the learning pipeline. The sandbox's qortex role installs the CLI, deploys environment config, and wires the gateway to use qortex as its memory and learning backend.

## What It Does

The qortex role handles nine things:

1. **CLI installation** via `uv tool install qortex[mcp,vec-sqlite,observability,nlp]` (includes spaCy for concept extraction). When `qortex_serve_enabled` is true, the `server` extra is appended automatically. When pgvector is the vector backend, the `vec-pgvector` extra is also included.
2. **Concept extraction setup**: downloads the spaCy `en_core_web_sm` model when `qortex_extraction` is `spacy` (default)
3. **Seed exchange directories** for structured data handoff (`~/.qortex/seeds/{pending,processed,failed}`)
4. **Signals directory** for projection output (`~/.qortex/signals/`)
5. **Buildlog interop config** (`~/.buildlog/interop.yaml`) linking buildlog to qortex's seed pipeline
6. **OTEL environment** (`/etc/openclaw/qortex-otel.env` + `/etc/profile.d/qortex-otel.sh`) so qortex exports traces and metrics to the host collector
7. **Gateway config injection** (via `fix-vm-paths.yml`): injects `memorySearch` with `provider: "qortex"` and `learning` config into `openclaw.json` so the gateway uses qortex for both memory tools and bandit-based tool selection
8. **HTTP service** (`qortex serve`): when `qortex_serve_enabled` is true, deploys a persistent REST API server as a systemd service with API key + HMAC-SHA256 authentication
9. **MCP HTTP service** (`qortex mcp-serve`): when `qortex_mcp_enabled` is true, deploys a second systemd service running the MCP server over Streamable HTTP transport, replacing the stdio subprocess model for gateway connections
10. **PgVector integration**: when `qortex_vec_backend` is `pgvector`, the qortex HTTP service connects to the pgvector PostgreSQL container for vector search instead of the default SQLite backend

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

### With PgVector (Vector Search Backend)

To use PostgreSQL + pgvector instead of the default SQLite vector backend:

```bash
# Using the Bilrost CLI
bilrost up --pgvector --qortex-serve

# Using bootstrap.sh directly
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "pgvector_enabled=true" \
  -e "qortex_serve_enabled=true" \
  -e "qortex_vec_backend=pgvector"
```

This deploys a persistent PostgreSQL container with the pgvector extension (`pgvector/pgvector:pg16`) and configures the qortex HTTP service to use it as the vector store. The pgvector role:

1. Creates a Docker Compose project at `/opt/pgvector`
2. Starts a PostgreSQL container (`qortex-pgvector`) with host networking
3. Initializes the `vector` extension via `CREATE EXTENSION IF NOT EXISTS vector`
4. Stores data in a named Docker volume (`pgvector_data`) for persistence across restarts
5. Health-checks via `pg_isready` with retries

| Setting | Default |
|---------|---------|
| Image | `pgvector/pgvector:pg16` |
| Port | `5432` |
| User | `qortex` |
| Password | `qortex` |
| Database | `qortex` |
| DSN | `postgresql://qortex:qortex@localhost:5432/qortex` |

!!! note "PgVector requires Docker"
    The pgvector role depends on Docker CE being installed (`docker_enabled: true`, which is the default). If you used `--no-docker`, pgvector cannot be enabled.

## Qortex HTTP Service

When `qortex_serve_enabled` is true, the role deploys a persistent REST API server as a systemd service (`qortex.service`). This provides HTTP endpoints for vector search, knowledge graph queries, and learning pipeline operations.

### Enabling the HTTP Service

```bash
# Using the Bilrost CLI
bilrost up --qortex-serve

# Using bootstrap.sh
./bootstrap.sh --openclaw ~/Projects/openclaw -e "qortex_serve_enabled=true"

# With pgvector backend
bilrost up --pgvector --qortex-serve
```

### API Authentication

The qortex HTTP service supports two authentication methods:

**API Key Authentication**

On first provision, a 256-bit random API key is generated via `openssl rand -hex 32` and stored at `/etc/openclaw/qortex-api-key` (mode `0640`). The key is idempotent -- it is only generated if the file does not already exist, so reprovisioning preserves the original key. Clients include the key in the `Authorization` header:

```
Authorization: Bearer <api-key>
```

**HMAC-SHA256 Authentication**

For request signing, set `qortex_hmac_secret` to a shared secret. Clients sign the request body with HMAC-SHA256 and include the signature in the `X-Signature` header.

### Systemd Service

The `qortex.service` unit runs as the Ansible provisioning user with hardened settings:

```ini
[Unit]
Description=Qortex Knowledge Graph Service
After=network-online.target docker.service  # docker.service only when pgvector_enabled

[Service]
Type=simple
EnvironmentFile=/etc/openclaw/qortex.env
EnvironmentFile=/etc/openclaw/qortex-otel.env  # only when qortex_otel_enabled
ExecStart=~/.local/bin/qortex serve --host 0.0.0.0 --port 8400
NoNewPrivileges=true
ProtectSystem=strict
```

The environment file (`/etc/openclaw/qortex.env`) contains:

| Variable | Value | Condition |
|----------|-------|-----------|
| `QORTEX_VEC` | `sqlite` or `pgvector` | Always |
| `PGVECTOR_DSN` | `postgresql://qortex:qortex@localhost:5432/qortex` | When `qortex_vec_backend=pgvector` |
| `QORTEX_API_KEYS` | Auto-generated 256-bit key | When API key file exists |
| `QORTEX_HMAC_SECRET` | User-provided secret | When `qortex_hmac_secret` is set |
| `QORTEX_EXTRACTION` | `spacy`, `llm`, or `none` | Always |
| `MEMGRAPH_HOST`, `_PORT`, `_USER`, `_PASSWORD` | Memgraph connection details | When `memgraph_enabled` |
| OTEL variables | OTEL endpoint and protocol | When `qortex_otel_enabled` |
| `QORTEX_PROMETHEUS_PORT` | `9090` | When `qortex_prometheus_enabled` |

### HTTP Service Verification

```bash
# Check qortex HTTP service is running
limactl shell openclaw-sandbox -- systemctl status qortex

# Check the API key
limactl shell openclaw-sandbox -- sudo cat /etc/openclaw/qortex-api-key

# Test the endpoint (from inside the VM)
limactl shell openclaw-sandbox -- bash -c \
  'curl -s -H "Authorization: Bearer $(sudo cat /etc/openclaw/qortex-api-key)" \
   http://localhost:8400/health'
```

## Qortex MCP HTTP Service

When `qortex_mcp_enabled` is true (automatically tracks `qortex_serve_enabled`), the role deploys a second systemd service (`qortex-mcp.service`) that runs the qortex MCP server over Streamable HTTP transport. The gateway connects here for memory search and learning pipeline operations instead of spawning stdio subprocesses.

### Why Two Services?

The REST API (`qortex.service`, port 8400) serves framework adapters (Agno, AutoGen, LangChain) that speak standard HTTP with API key auth. The MCP service (`qortex-mcp.service`, port 8401) speaks the MCP Streamable HTTP protocol that the gateway's `StreamableHTTPClientTransport` expects. Separating them keeps auth and protocol concerns clean.

### Enabling the MCP Service

The MCP service is automatically enabled when the HTTP service is enabled:

```bash
# Using the Bilrost CLI
bilrost up --qortex-serve

# Using bootstrap.sh
./bootstrap.sh --openclaw ~/Projects/openclaw -e "qortex_serve_enabled=true"
```

To enable MCP independently (uncommon):

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw -e "qortex_mcp_enabled=true"
```

### Systemd Service

The `qortex-mcp.service` unit:

```ini
[Unit]
Description=Qortex MCP Server (Streamable HTTP)
After=network-online.target qortex.service

[Service]
Type=simple
Environment=FASTMCP_HOST=0.0.0.0
Environment=FASTMCP_PORT=8401
EnvironmentFile=-/etc/openclaw/qortex.env
EnvironmentFile=-/etc/openclaw/qortex-otel.env
ExecStart=~/.local/bin/qortex mcp-serve --transport streamable-http
```

FastMCP reads `FASTMCP_HOST` and `FASTMCP_PORT` via pydantic `BaseSettings` (env prefix `FASTMCP_`). The Streamable HTTP endpoint is served at `/mcp` (e.g., `http://localhost:8401/mcp`).

### Gateway Config Injection

When the MCP HTTP service is enabled, the gateway role's `fix-vm-paths.yml` switches `memorySearch` and `learning` config from stdio transport to HTTP transport:

```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "qortex": {
          "transport": "http",
          "http": { "baseUrl": "http://localhost:8401/mcp" }
        }
      }
    }
  },
  "learning": {
    "qortex": {
      "transport": "http",
      "http": { "baseUrl": "http://localhost:8401/mcp" }
    }
  }
}
```

No authentication is needed on the MCP endpoint — it is an internal service within the VM.

### MCP Service Verification

```bash
# Check qortex MCP service is running
limactl shell openclaw-sandbox -- systemctl status qortex-mcp

# Check the MCP endpoint responds
limactl shell openclaw-sandbox -- curl -s http://localhost:8401/mcp

# Check both services are running
limactl shell openclaw-sandbox -- systemctl status qortex qortex-mcp

# Check the gateway sees HTTP transport
limactl shell openclaw-sandbox -- bash -c \
  'jq ".agents.defaults.memorySearch.qortex" ~/.openclaw/openclaw.json'
```

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
| `qortex_extras` | `mcp,vec-sqlite,observability,nlp` | Pip extras for qortex (MCP server, vector search, OTEL, spaCy NLP) |
| `qortex_extraction` | `spacy` | Concept extraction strategy: `spacy`, `llm`, or `none` |
| `qortex_otel_enabled` | `true` | Export OpenTelemetry traces and Prometheus metrics |
| `qortex_otel_endpoint` | `http://host.lima.internal:4318` | OTEL collector endpoint on the host |
| `qortex_otel_protocol` | `http/protobuf` | OTEL exporter wire protocol |
| `qortex_prometheus_enabled` | `true` | Expose a Prometheus metrics endpoint for Grafana |
| `qortex_prometheus_port` | `9090` | Port for Prometheus scraping |
| `qortex_serve_enabled` | `false` | Enable the qortex HTTP service (REST API server) |
| `qortex_serve_port` | `8400` | HTTP service listen port |
| `qortex_serve_host` | `0.0.0.0` | HTTP service bind address |
| `qortex_vec_backend` | `sqlite` | Vector search backend: `sqlite` or `pgvector` |
| `qortex_pgvector_dsn` | `postgresql://qortex:qortex@localhost:5432/qortex` | PostgreSQL connection string for pgvector backend |
| `qortex_api_keys` | `""` (auto-generated on first provision) | Comma-separated API keys for HTTP service auth |
| `qortex_hmac_secret` | `""` | Shared secret for HMAC-SHA256 request signing |
| `qortex_mcp_enabled` | `false` | Enable qortex MCP HTTP service (Streamable HTTP transport for gateway) |
| `qortex_mcp_port` | `8401` | MCP HTTP service listen port |
| `qortex_mcp_host` | `0.0.0.0` | MCP HTTP service bind address |
| `qortex_wheel_dir` | `""` | Path to pre-built wheels directory (empty = install from PyPI) |

Override with `-e`:

```bash
# Disable qortex entirely
./bootstrap.sh --openclaw ~/Projects/openclaw -e "qortex_enabled=false"

# Disable OTEL export (keeps qortex but no metrics)
./bootstrap.sh --openclaw ~/Projects/openclaw -e "qortex_otel_enabled=false"

# Use LLM extraction instead of spaCy (requires API key)
./bootstrap.sh --openclaw ~/Projects/openclaw -e "qortex_extraction=llm"

# Disable extraction entirely
./bootstrap.sh --openclaw ~/Projects/openclaw -e "qortex_extraction=none"

# Enable HTTP service with pgvector backend
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "qortex_serve_enabled=true" \
  -e "qortex_vec_backend=pgvector" \
  -e "pgvector_enabled=true"
```

## Observability (OTEL + Prometheus)

When `qortex_otel_enabled` is true (default), the role deploys two environment files:

- `/etc/openclaw/qortex-otel.env` (systemd EnvironmentFile, loaded by `openclaw-gateway.service`)
- `/etc/profile.d/qortex-otel.sh` (shell env, sourced by login and non-login shells)

Both set the same variables:

| Variable | Value | Purpose |
|----------|-------|---------|
| `QORTEX_OTEL_ENABLED` | `true` | Master switch for OpenTelemetry export |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://host.lima.internal:4318` | Host-side OTEL collector |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` | Wire format |
| `QORTEX_PROMETHEUS_ENABLED` | `true` | Expose metrics endpoint |
| `QORTEX_PROMETHEUS_PORT` | `9090` | Prometheus scrape port |
| `QORTEX_EXTRACTION` | `spacy` | Concept extraction strategy (`spacy`, `llm`, `none`) |
| `HF_HUB_OFFLINE` | `1` | Prevent HuggingFace model downloads at runtime (models pre-cached during provisioning) |

The firewall role allows TCP 4318 outbound to the Lima host gateway IP (`192.168.5.2`) when OTEL is enabled. Loopback traffic for Prometheus (port 9090) is already allowed.

To view traces and metrics on the host, run an OTEL collector (e.g. Grafana Alloy) listening on port 4318, and point Grafana at Prometheus on `localhost:9090` (forwarded through Lima).

## Learning Pipeline

The gateway uses qortex's Thompson Sampling bandit to decide which tools, skills, and context files to include in each agent run. This is configured automatically on provision.

The `fix-vm-paths.yml` task injects two blocks into `openclaw.json` when `qortex_enabled` is true:

**Memory search** (vector retrieval via qortex MCP):
```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "enabled": true,
        "provider": "qortex",
        "qortex": { "command": "qortex mcp-serve", "feedback": true }
      }
    }
  }
}
```

**Learning** (bandit selection + observation):
```json
{
  "learning": {
    "enabled": true,
    "phase": "active",
    "tokenBudget": 8000,
    "baselineRate": 0.10,
    "minPulls": 20,
    "qortex": { "command": "qortex mcp-serve" },
    "learnerName": "openclaw"
  }
}
```

The gateway also gets `tools.alsoAllow: ["group:memory"]` so memory tools are available regardless of the tool profile.

These injections only happen when the config is missing the relevant keys. Existing user config is preserved and patched, not overwritten.

## Standalone Use

The qortex role guards `~/.buildlog` directory creation. If the buildlog role has already created it (e.g., as a Lima mount symlink), qortex skips that step. This means qortex works both ways:

- **With buildlog**: interop.yaml is deployed into the existing `~/.buildlog/`
- **Without buildlog**: qortex creates `~/.buildlog/` as a real directory and deploys interop.yaml

## Upgrading qortex

Use `bilrost upgrade` to build, deploy, and install qortex wheels from local source into the sandbox. This replaces ad-hoc wheel copying and `uv tool install` commands.

### From local source (build + deploy)

```bash
bilrost upgrade -q ~/Projects/qortex
```

This:

1. Builds wheels for `qortex`, `qortex-online`, `qortex-observe`, `qortex-ingest`, and `qortex-learning`
2. SCPs them to the VM
3. Installs with `uv tool install qortex[all]` plus all namespace packages
4. Ensures the spaCy `en_core_web_sm` model is installed
5. Restarts the gateway

### From pre-built wheels

```bash
bilrost upgrade -w ~/Projects/qortex/dist
```

Skips the build step. Useful when you've already built wheels or received them from CI.

### From Test PyPI (development builds)

```bash
bilrost upgrade --dev
```

Installs the latest pre-release build from Test PyPI. Useful for testing CI-published packages without building locally. Mutually exclusive with `--qortex-dir` and `--wheel-dir`.

### Options

| Flag | Description |
|------|-------------|
| `-q`, `--qortex-dir` | Path to local qortex source directory |
| `-w`, `--wheel-dir` | Path to pre-built wheels directory |
| `--dev` | Install latest dev build from Test PyPI |
| `--skip-restart` | Install without restarting the gateway |

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

# Check qortex HTTP service (when qortex_serve_enabled)
limactl shell openclaw-sandbox -- systemctl status qortex

# Check pgvector container (when pgvector_enabled)
limactl shell openclaw-sandbox -- docker ps | grep qortex-pgvector
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
2. Lima port forwards are baked at creation. To change them, delete and recreate:

```bash
bilrost destroy -f
./bootstrap.sh --openclaw ~/Projects/openclaw --memgraph
```

### Qortex HTTP service not starting

1. Check the service status: `limactl shell openclaw-sandbox -- systemctl status qortex`
2. Check the journal: `limactl shell openclaw-sandbox -- journalctl -u qortex --no-pager -n 50`
3. Verify the environment file: `limactl shell openclaw-sandbox -- sudo cat /etc/openclaw/qortex.env`
4. Verify the API key file exists: `limactl shell openclaw-sandbox -- sudo ls -la /etc/openclaw/qortex-api-key`
5. Ensure the `server` extra was installed: `limactl shell openclaw-sandbox -- qortex serve --help`

### Qortex MCP service not starting

1. Check the service status: `limactl shell openclaw-sandbox -- systemctl status qortex-mcp`
2. Check the journal: `limactl shell openclaw-sandbox -- journalctl -u qortex-mcp --no-pager -n 50`
3. Verify FastMCP is installed: `limactl shell openclaw-sandbox -- qortex mcp-serve --help`
4. Test the endpoint manually: `limactl shell openclaw-sandbox -- curl -s http://localhost:8401/mcp`
5. Verify the gateway config has HTTP transport: `limactl shell openclaw-sandbox -- bash -c 'jq ".agents.defaults.memorySearch.qortex.transport" ~/.openclaw/openclaw.json'`

### PgVector container not running

1. Check container status: `limactl shell openclaw-sandbox -- docker ps -a | grep pgvector`
2. Check container logs: `limactl shell openclaw-sandbox -- docker logs qortex-pgvector`
3. Verify the compose file: `limactl shell openclaw-sandbox -- cat /opt/pgvector/docker-compose.yml`
4. Restart the container: `limactl shell openclaw-sandbox -- sudo docker compose -f /opt/pgvector/docker-compose.yml restart`

## OpenClaw memory backend (qortex)

When the OpenClaw gateway runs in the sandbox, the agent can use **memory tools** (`memory_search`, `memory_get`, and optionally `memory_feedback`) backed by qortex instead of the default SQLite + embeddings pipeline. That lets the agent query the knowledge graph via the qortex MCP server.

### How it works

- OpenClaw’s **memory-core** plugin registers the memory tools. They are only created when **memory search is enabled** and the plugin receives the runtime config.
- The backend is selected by `agents.defaults.memorySearch.provider`. Set it to `"qortex"` to use the qortex MCP server; otherwise OpenClaw uses the SQLite/embedding path (openai/gemini/local).
- With `provider: "qortex"`, the gateway spawns the qortex MCP subprocess (e.g. `qortex mcp-serve` or `uvx qortex mcp-serve`) and forwards `memory_search` / `memory_get` / `memory_feedback` to it.

### Intended flow when memory tools are available

When the agent **has** `memory_search` and `memory_get` in its tool list, OpenClaw’s system prompt tells it: *before answering anything about prior work, decisions, dates, people, preferences, or todos, run memory_search on MEMORY.md + memory/*.md, then use memory_get to pull only the needed lines.* So the intended flow is **memory_search → memory_get**, not manual `read` of the files.

If an agent says something like “I don’t use memory_search, I just read MEMORY.md manually”, that session almost certainly **does not have** the memory tools. For example: Cursor/Claude in the IDE, or a client that isn’t using the OpenClaw gateway’s tool list. In that case the model falls back to describing “I read the memory files with read”. To get the real flow, use a session that goes through the gateway (e.g. Telegram, the Mac app, or whatever invokes the gateway with the same config) so the agent receives the memory tools.

### Config required for the agent to see memory tools

1. **Memory search enabled**  
   `agents.defaults.memorySearch.enabled` must be `true` (or omitted; it defaults to true).

2. **Provider set to qortex**  
   `agents.defaults.memorySearch.provider: "qortex"` so the gateway uses the qortex backend.

3. **Memory slot**  
   The default memory plugin is **memory-core** (`plugins.slots.memory: "memory-core"`). Do not set the slot to another plugin if you want the built-in memory tools.

4. **Tool policy**  
   The agent’s tool policy must allow the memory tools (e.g. `group:memory` or `memory_search`, `memory_get`, `memory_feedback`). The **coding** profile includes `group:memory`; the **messaging** profile does not. So if your session uses `tools.profile: "messaging"` (common for Telegram/TUI), the memory tools can be filtered out, and visibility may change run-to-run if the effective profile or agent varies. To make memory tools consistently visible, set `tools.profile` to `"coding"` (or `"full"`), or add `tools.alsoAllow: ["group:memory"]` so memory is allowed even when the profile is messaging.

**Example (always allow memory on all sessions):** in `openclaw.json`:

```json
{
  "tools": {
    "profile": "coding"
  }
}
```

Or keep your current profile and add memory only:

```json
{
  "tools": {
    "alsoAllow": ["group:memory"]
  }
}
```

5. **Config present where the gateway runs**  
   The gateway loads config from `~/.openclaw/openclaw.json` (or your mounted config). That file must contain the above. If you use the sandbox’s config mount, ensure your host `~/.openclaw/openclaw.json` (or the dir you pass to `--config`) includes `agents.defaults.memorySearch`.

### Example config (VM / sandbox)

Minimal snippet so the agent sees memory tools and uses qortex in the sandbox:

```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "enabled": true,
        "provider": "qortex",
        "qortex": {
          "command": "qortex mcp-serve",
          "feedback": true
        }
      }
    }
  }
}
```

In the VM, `qortex` is installed via the qortex Ansible role at `~/.local/bin/qortex`, and the gateway’s PATH includes `~/.local/bin`, so `qortex mcp-serve` works. On the host you might use `"uvx qortex mcp-serve"` if that’s how you run qortex.

### If the agent does not see memory tools

- **Check config key**: it must be `agents.defaults.memorySearch` (not `memory`). If you use the wrong key, OpenClaw never sees your provider setting; `provider` defaults to `"auto"` and the SQLite/embedding path runs (often OpenAI). So “we had qortex but it wasn’t being used” usually means the key was wrong or the merged config didn’t have `memorySearch`. See OpenClaw’s Zod schema or `dist/config/zod-schema.agent-runtime.js` for the exact shape.
- **Check config is loaded**: the gateway must receive this config when building the tool list (e.g. from `~/.openclaw/openclaw.json` in the VM).
- **Check plugin**: memory-core must be loaded and the memory slot must be `memory-core` (default). If you set `plugins.slots.memory` to another plugin, the core memory tools are not registered.
- **Check tool policy**: ensure the agent's effective tool policy allows `memory_search` / `memory_get` (e.g. via `group:memory` or an explicit allow list).
- **Check bundled plugins dir**: the gateway resolves extensions from `OPENCLAW_BUNDLED_PLUGINS_DIR` or by walking up from `dist/`. If the env var is missing and the walk-up fails (e.g. overlay mounts), memory-core is never discovered and the tools are never registered.

**Fix:** The gateway only picks up environment variables when it starts. The systemd unit sets `OPENCLAW_BUNDLED_PLUGINS_DIR`, but if the gateway was started before that was added (or before you re-provisioned), it won't have it. Re-provision: `bilrost up`. After any config change, restart the gateway: `bilrost restart`.

**Quick manual fix (no reprovision):** If you already have `memorySearch` with `provider: "qortex"` but the agent still doesn't see the tools, patch the config in the VM and restart:

```bash
limactl shell openclaw-sandbox -- bash -c 'jq "
  .agents.defaults.memorySearch.enabled = true |
  .agents.defaults.memorySearch.qortex = ((.agents.defaults.memorySearch.qortex // {}) | .command = (.command // \"qortex mcp-serve\")) |
  .tools.alsoAllow = ((.tools.alsoAllow // []) + [\"group:memory\"] | unique)
" ~/.openclaw/openclaw.json > /tmp/out.json && mv /tmp/out.json ~/.openclaw/openclaw.json'
bilrost restart
```

### Verification (in the VM)

Run these from the host. Use `bash -c '...'` so `~` expands inside the VM to the VM user’s home, not the host’s:

```bash
# Config has memorySearch and provider qortex
limactl shell openclaw-sandbox -- bash -c 'jq ".agents.defaults.memorySearch" ~/.openclaw/openclaw.json'

# qortex CLI available (used by OpenClaw to spawn MCP server)
limactl shell openclaw-sandbox -- qortex --version
```

### Auto-injection on provision

When the sandbox is provisioned with qortex enabled (`qortex_enabled: true`, which is the default), the **gateway** role’s VM path-fix step will:

- **If `memorySearch` is missing**: inject the full `agents.defaults.memorySearch` block with `enabled`, `provider`, `qortex.command`, and `qortex.feedback`.
- **If `memorySearch` exists**: patch it to add `enabled: true` and `qortex.command: "qortex mcp-serve"` (or keep your existing `command` if set).
- Add `group:memory` to `tools.alsoAllow` so the memory tools are allowed even when `tools.profile` is messaging (option 2).

Provision/re-provision uses `bilrost up` (or `bilrost up --fresh` to destroy and recreate). There is no `bilrost provision` command.

### Updating config inside the VM

Config in the VM lives at **`~/.openclaw/openclaw.json`** (VM user’s home). Ways to change it:

1. **Edit in the VM** (survives until next provision overwrite if config is copied from mount):
   ```bash
   limactl shell openclaw-sandbox -- bash -c 'nano ~/.openclaw/openclaw.json'
   ```
   Or use `jq` to patch and write back. After editing, restart the gateway so it reloads config: `bilrost restart`.

2. **Edit on the host and re-copy** (if you use `--config` and the gateway copies from a mount): change the file in your host config dir (e.g. `~/.openclaw/openclaw.json`), then run `bilrost up` so the gateway role copies and re-applies fix-vm-paths, or copy the file into the VM manually and run `bilrost restart`.

3. **Re-provision**: run `bilrost up` (or `bilrost up --fresh` to destroy and recreate) so the playbook copies config from the mount and runs fix-vm-paths (injecting memorySearch and alsoAllow when qortex is enabled).
