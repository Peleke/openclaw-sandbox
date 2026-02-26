# Qortex Interop

[Qortex](https://github.com/Peleke/qortex) provides vector search, knowledge graph retrieval, and a Thompson Sampling bandit for the learning pipeline. The sandbox's qortex role deploys qortex as a Docker container, sets up seed exchange directories, and wires the gateway to use qortex as its memory and learning backend via HTTP REST.

## What It Does

The qortex role handles eight things:

1. **Docker container deployment**: pulls `ghcr.io/peleke/qortex:latest` and runs it with host networking. The image ships with the embedding model (all-MiniLM-L6-v2), spaCy (`en_core_web_sm`), and the full extraction pipeline baked in -- no runtime downloads needed.
2. **Data volume**: creates a named Docker volume (`qortex_data`) mounted at `/root/.qortex` inside the container for persisting the SQLite database, vector index, and learning state across restarts.
3. **Seed exchange directories** for structured data handoff (`~/.qortex/seeds/{pending,processed,failed}`)
4. **Signals directory** for projection output (`~/.qortex/signals/`)
5. **Buildlog interop config** (`~/.buildlog/interop.yaml`) linking buildlog to qortex's seed pipeline
6. **OTEL environment** (`/etc/openclaw/qortex-otel.env` + `/etc/profile.d/qortex-otel.sh`) so qortex exports traces and metrics to the host collector
7. **Gateway config injection** (via `fix-vm-paths.yml`): injects `memorySearch` with `provider: "qortex"` and `learning` config into `openclaw.json`, using HTTP REST transport (`transport: "http"`) to connect to the Docker container instead of spawning an MCP subprocess
8. **Old systemd cleanup**: stops, disables, and removes legacy `qortex.service` and `qortex-mcp.service` units from previous provisioning (systemd + uv deployment is fully replaced by Docker)

## Setup

Qortex is enabled by default when the sandbox is provisioned. No extra flags are needed:

```bash
# Using the Bilrost CLI (recommended)
bilrost up

# Using bootstrap.sh directly
./bootstrap.sh --openclaw ~/Projects/openclaw
```

The Docker image is pulled automatically on first provision. On subsequent provisions, the pull is **skipped if the image is already loaded locally**. This supports offline and air-gapped VMs where registry access may not be available.

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
bilrost up --pgvector

# Using bootstrap.sh directly
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "pgvector_enabled=true" \
  -e "qortex_vec_backend=pgvector"
```

This deploys a persistent PostgreSQL container with the pgvector extension (`pgvector/pgvector:pg16`) and configures the qortex Docker container to use it as the vector store. The pgvector role:

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

## Docker Container Deployment

Qortex runs as a Docker container with host networking. The container serves a REST API that the gateway connects to via HTTP transport.

### Container Configuration

| Setting | Value |
|---------|-------|
| Image | `ghcr.io/peleke/qortex:latest` |
| Container name | `qortex` |
| Network | `host` (binds to `localhost:8400`) |
| Restart policy | `unless-stopped` |
| Data volume | `qortex_data` mounted at `/root/.qortex` |
| Environment | `/etc/openclaw/qortex.env` |

### Baked-In Dependencies

The Docker image includes everything needed to run qortex without runtime downloads:

- **Embedding model**: `all-MiniLM-L6-v2` (sentence-transformers)
- **NLP model**: spaCy `en_core_web_sm` for concept extraction
- **Extraction pipeline**: full spaCy-based extraction ready out of the box

`HF_HUB_OFFLINE=1` is set in the environment to prevent HuggingFace model downloads at runtime.

### API Authentication

The qortex HTTP service supports two authentication methods:

**API Key Authentication**

On first provision, a 256-bit random API key is generated via `openssl rand -hex 32` and stored at `/etc/openclaw/qortex-api-key` (mode `0640`). The key is idempotent -- it is only generated if the file does not already exist, so reprovisioning preserves the original key. Clients include the key in the `Authorization` header:

```
Authorization: Bearer <api-key>
```

The gateway automatically reads this key and includes it in all HTTP requests to the qortex container.

**HMAC-SHA256 Authentication**

For request signing, set `qortex_hmac_secret` to a shared secret. Clients sign the request body with HMAC-SHA256 and include the signature in the `X-Signature` header.

### Environment File

The environment file (`/etc/openclaw/qortex.env`) is passed to the Docker container via `--env-file` and contains:

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

### Health Check

After starting the container, the role waits for the `/v1/health` endpoint to return HTTP 200, with up to 30 retries at 5-second intervals.

### Container Verification

```bash
# Check qortex container is running
limactl shell openclaw-sandbox -- docker ps | grep qortex

# Check container logs
limactl shell openclaw-sandbox -- docker logs qortex

# Check the API key
limactl shell openclaw-sandbox -- sudo cat /etc/openclaw/qortex-api-key

# Test the health endpoint (from inside the VM)
limactl shell openclaw-sandbox -- bash -c \
  'curl -s -H "Authorization: Bearer $(sudo cat /etc/openclaw/qortex-api-key)" \
   http://localhost:8400/v1/health'

# Check the data volume
limactl shell openclaw-sandbox -- docker volume inspect qortex_data
```

## Gateway HTTP Transport

The gateway connects to qortex via HTTP REST instead of spawning an MCP subprocess. This is configured automatically during provisioning.

### How It Works

When `qortex_serve_enabled` is true and `qortex_http_transport` is true (both default), the `fix-vm-paths.yml` task:

1. Injects `memorySearch` with `provider: "qortex"` and `transport: "http"` pointing at `http://localhost:8400`
2. Injects `learning` config with `transport: "http"` pointing at the same endpoint
3. Includes the API key in the `Authorization: Bearer` header for both
4. **Strips the `command` key** from both `memorySearch.qortex` and `learning.qortex` so the gateway does not try to spawn a subprocess alongside the HTTP connection

The `command` stripping is important: without it, the gateway would attempt to launch `qortex mcp-serve` as a subprocess (the old MCP stdio transport), which would conflict with the Docker container's REST endpoint.

### Resulting Config

After provisioning, `openclaw.json` contains:

**Memory search** (vector retrieval via HTTP REST):
```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "enabled": true,
        "provider": "qortex",
        "qortex": {
          "transport": "http",
          "http": {
            "baseUrl": "http://localhost:8400",
            "headers": {
              "Authorization": "Bearer <auto-generated-key>"
            }
          },
          "feedback": true
        }
      }
    }
  }
}
```

**Learning** (bandit selection + observation via HTTP REST):
```json
{
  "learning": {
    "enabled": true,
    "phase": "active",
    "tokenBudget": 8000,
    "baselineRate": 0.10,
    "minPulls": 5,
    "qortex": {
      "transport": "http",
      "http": {
        "baseUrl": "http://localhost:8400",
        "headers": {
          "Authorization": "Bearer <auto-generated-key>"
        }
      }
    },
    "learnerName": "openclaw"
  }
}
```

The gateway also gets `tools.alsoAllow: ["group:memory"]` so memory tools are available regardless of the tool profile.

These injections only happen when the config is missing the relevant keys. Existing user config is preserved and patched, not overwritten.

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
└── interop.yaml       # Buildlog <-> Qortex exchange config
```

All directories are created with mode `0750`.

### Docker Resources

```
Docker container: qortex (host networking, port 8400)
Docker volume:    qortex_data -> /root/.qortex (inside container)
Docker image:     ghcr.io/peleke/qortex:latest
```

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
| `qortex_docker_image` | `ghcr.io/peleke/qortex:latest` | Docker image for the qortex container |
| `qortex_docker_container` | `qortex` | Docker container name |
| `qortex_docker_volume` | `qortex_data` | Named Docker volume for persistent data |
| `qortex_serve_enabled` | `true` | Deploy the qortex Docker container |
| `qortex_serve_port` | `8400` | HTTP service listen port |
| `qortex_serve_host` | `0.0.0.0` | HTTP service bind address |
| `qortex_http_transport` | `true` | Gateway connects via HTTP REST (not MCP subprocess) |
| `qortex_extraction` | `spacy` | Concept extraction strategy: `spacy`, `llm`, or `none` |
| `qortex_vec_backend` | `sqlite` | Vector search backend: `sqlite` or `pgvector` |
| `qortex_pgvector_dsn` | `postgresql://qortex:qortex@localhost:5432/qortex` | PostgreSQL connection string for pgvector backend |
| `qortex_api_keys` | `""` (auto-generated on first provision) | Comma-separated API keys for HTTP service auth |
| `qortex_hmac_secret` | `""` | Shared secret for HMAC-SHA256 request signing |
| `qortex_otel_enabled` | `true` | Export OpenTelemetry traces and Prometheus metrics |
| `qortex_otel_endpoint` | `http://host.lima.internal:4318` | OTEL collector endpoint on the host |
| `qortex_otel_protocol` | `http/protobuf` | OTEL exporter wire protocol |
| `qortex_prometheus_enabled` | `true` | Expose a Prometheus metrics endpoint for Grafana |
| `qortex_prometheus_port` | `9090` | Port for Prometheus scraping |
| `qortex_install_cli` | `false` | Install lightweight qortex CLI via `uv` (for ad-hoc commands, not required for Docker service) |

### Deprecated Variables

These variables are retained for backward compatibility but are no longer used by the Docker deployment:

| Variable | Default | Notes |
|----------|---------|-------|
| `qortex_install` | `false` | Replaced by Docker container; use `qortex_install_cli` for ad-hoc CLI |
| `qortex_extras` | `""` | No longer needed; Docker image has all dependencies baked in |
| `qortex_wheel_dir` | `""` | No longer needed; Docker image replaces wheel-based installs |
| `qortex_mcp_enabled` | `false` | MCP HTTP service replaced by REST on `qortex_serve_port` |
| `qortex_mcp_port` | `8401` | Unused; REST runs on `qortex_serve_port` |

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

# Use pgvector backend
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "qortex_vec_backend=pgvector" \
  -e "pgvector_enabled=true"

# Use a custom Docker image
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "qortex_docker_image=ghcr.io/peleke/qortex:v2.0.0"
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
| `HF_HUB_OFFLINE` | `1` | Prevent HuggingFace model downloads at runtime (models baked into Docker image) |

The firewall role allows TCP 4318 outbound to the Lima host gateway IP (`192.168.5.2`) when OTEL is enabled. Loopback traffic for Prometheus (port 9090) is already allowed.

The Docker container also receives OTEL variables via `/etc/openclaw/qortex.env` (passed as `--env-file` to `docker run`), so traces and metrics are exported from inside the container.

To view traces and metrics on the host, run an OTEL collector (e.g. Grafana Alloy) listening on port 4318, and point Grafana at Prometheus on `localhost:9090` (forwarded through Lima).

## Learning Pipeline

The gateway uses qortex's Thompson Sampling bandit to decide which tools, skills, and context files to include in each agent run. This is configured automatically on provision.

The `fix-vm-paths.yml` task injects two blocks into `openclaw.json` when `qortex_enabled` is true. Both use HTTP REST transport to communicate with the Docker container:

**Memory search** (vector retrieval via HTTP REST):
```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "enabled": true,
        "provider": "qortex",
        "qortex": {
          "transport": "http",
          "http": {
            "baseUrl": "http://localhost:8400",
            "headers": { "Authorization": "Bearer <key>" }
          },
          "feedback": true
        }
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
    "minPulls": 5,
    "qortex": {
      "transport": "http",
      "http": {
        "baseUrl": "http://localhost:8400",
        "headers": { "Authorization": "Bearer <key>" }
      }
    },
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

Since qortex now runs as a Docker container, upgrading is a matter of pulling a new image and restarting the container:

```bash
# Pull the latest image and reprovision
bilrost up
```

This will pull the newest `ghcr.io/peleke/qortex:latest` image (if a newer version is available) and recreate the container. The data volume (`qortex_data`) persists across container recreations.

### Using a specific image tag

```bash
bilrost up -e "qortex_docker_image=ghcr.io/peleke/qortex:v2.0.0"
```

### Optional CLI for ad-hoc commands

If you need the `qortex` CLI for ad-hoc commands (e.g., `qortex status`, `qortex ingest`) without going through the Docker container, enable the lightweight CLI install:

```bash
bilrost up -e "qortex_install_cli=true"
```

This installs the CLI via `uv tool install` but is not required for the Docker service.

## Verification Commands

```bash
# Check qortex Docker container is running
limactl shell openclaw-sandbox -- docker ps | grep qortex

# Check container logs
limactl shell openclaw-sandbox -- docker logs qortex --tail 50

# Check data volume
limactl shell openclaw-sandbox -- docker volume inspect qortex_data

# Check seed directories exist
limactl shell openclaw-sandbox -- ls -la ~/.qortex/seeds/

# Check signals directory
limactl shell openclaw-sandbox -- ls -la ~/.qortex/signals/

# Check interop config
limactl shell openclaw-sandbox -- cat ~/.buildlog/interop.yaml

# Test health endpoint
limactl shell openclaw-sandbox -- bash -c \
  'curl -s -H "Authorization: Bearer $(sudo cat /etc/openclaw/qortex-api-key)" \
   http://localhost:8400/v1/health'

# Check pgvector container (when pgvector_enabled)
limactl shell openclaw-sandbox -- docker ps | grep qortex-pgvector
```

## Troubleshooting

### Qortex container not running

1. Check container status: `limactl shell openclaw-sandbox -- docker ps -a | grep qortex`
2. Check container logs: `limactl shell openclaw-sandbox -- docker logs qortex`
3. Check the environment file: `limactl shell openclaw-sandbox -- sudo cat /etc/openclaw/qortex.env`
4. Check the image exists: `limactl shell openclaw-sandbox -- docker images | grep qortex`
5. If the image is missing, reprovision: `bilrost up`

### Qortex container starts but health check fails

1. Check the container is listening: `limactl shell openclaw-sandbox -- curl -s http://localhost:8400/v1/health`
2. Check container logs for startup errors: `limactl shell openclaw-sandbox -- docker logs qortex --tail 100`
3. Verify the port is not in use by another process: `limactl shell openclaw-sandbox -- ss -tlnp | grep 8400`

### Old systemd services still running

The qortex role automatically stops and removes `qortex.service` and `qortex-mcp.service` on provision. If they persist:

1. Check: `limactl shell openclaw-sandbox -- systemctl status qortex qortex-mcp`
2. Manually stop: `limactl shell openclaw-sandbox -- sudo systemctl stop qortex qortex-mcp`
3. Remove unit files: `limactl shell openclaw-sandbox -- sudo rm /etc/systemd/system/qortex.service /etc/systemd/system/qortex-mcp.service && sudo systemctl daemon-reload`

### Image pull fails (air-gapped VM)

If the VM cannot reach `ghcr.io`, pre-load the image:

```bash
# On the host: save the image to a tar file
docker pull ghcr.io/peleke/qortex:latest
docker save ghcr.io/peleke/qortex:latest -o qortex.tar

# Copy into the VM and load
limactl copy qortex.tar openclaw-sandbox:~/qortex.tar
limactl shell openclaw-sandbox -- docker load -i ~/qortex.tar

# Reprovision (will skip the pull since the image is now loaded)
bilrost up
```

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

### PgVector container not running

1. Check container status: `limactl shell openclaw-sandbox -- docker ps -a | grep pgvector`
2. Check container logs: `limactl shell openclaw-sandbox -- docker logs qortex-pgvector`
3. Verify the compose file: `limactl shell openclaw-sandbox -- cat /opt/pgvector/docker-compose.yml`
4. Restart the container: `limactl shell openclaw-sandbox -- sudo docker compose -f /opt/pgvector/docker-compose.yml restart`

## OpenClaw memory backend (qortex)

When the OpenClaw gateway runs in the sandbox, the agent can use **memory tools** (`memory_search`, `memory_get`, and optionally `memory_feedback`) backed by qortex instead of the default SQLite + embeddings pipeline. That lets the agent query the knowledge graph via qortex's HTTP REST API.

### How it works

- OpenClaw's **memory-core** plugin registers the memory tools. They are only created when **memory search is enabled** and the plugin receives the runtime config.
- The backend is selected by `agents.defaults.memorySearch.provider`. Set it to `"qortex"` to use the qortex backend; otherwise OpenClaw uses the SQLite/embedding path (openai/gemini/local).
- With `provider: "qortex"` and `transport: "http"`, the gateway sends HTTP requests to the qortex Docker container at `http://localhost:8400` for `memory_search` / `memory_get` / `memory_feedback`.

### Intended flow when memory tools are available

When the agent **has** `memory_search` and `memory_get` in its tool list, OpenClaw's system prompt tells it: *before answering anything about prior work, decisions, dates, people, preferences, or todos, run memory_search on MEMORY.md + memory/*.md, then use memory_get to pull only the needed lines.* So the intended flow is **memory_search -> memory_get**, not manual `read` of the files.

If an agent says something like "I don't use memory_search, I just read MEMORY.md manually", that session almost certainly **does not have** the memory tools. For example: Cursor/Claude in the IDE, or a client that isn't using the OpenClaw gateway's tool list. In that case the model falls back to describing "I read the memory files with read". To get the real flow, use a session that goes through the gateway (e.g. Telegram, the Mac app, or whatever invokes the gateway with the same config) so the agent receives the memory tools.

### Config required for the agent to see memory tools

1. **Memory search enabled**
   `agents.defaults.memorySearch.enabled` must be `true` (or omitted; it defaults to true).

2. **Provider set to qortex**
   `agents.defaults.memorySearch.provider: "qortex"` so the gateway uses the qortex backend.

3. **Memory slot**
   The default memory plugin is **memory-core** (`plugins.slots.memory: "memory-core"`). Do not set the slot to another plugin if you want the built-in memory tools.

4. **Tool policy**
   The agent's tool policy must allow the memory tools (e.g. `group:memory` or `memory_search`, `memory_get`, `memory_feedback`). The **coding** profile includes `group:memory`; the **messaging** profile does not. So if your session uses `tools.profile: "messaging"` (common for Telegram/TUI), the memory tools can be filtered out, and visibility may change run-to-run if the effective profile or agent varies. To make memory tools consistently visible, set `tools.profile` to `"coding"` (or `"full"`), or add `tools.alsoAllow: ["group:memory"]` so memory is allowed even when the profile is messaging.

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
   The gateway loads config from `~/.openclaw/openclaw.json` (or your mounted config). That file must contain the above. If you use the sandbox's config mount, ensure your host `~/.openclaw/openclaw.json` (or the dir you pass to `--config`) includes `agents.defaults.memorySearch`.

### Example config (VM / sandbox)

Minimal snippet so the agent sees memory tools and uses qortex in the sandbox (this is injected automatically by provisioning):

```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "enabled": true,
        "provider": "qortex",
        "qortex": {
          "transport": "http",
          "http": {
            "baseUrl": "http://localhost:8400",
            "headers": {
              "Authorization": "Bearer <auto-generated-key>"
            }
          },
          "feedback": true
        }
      }
    }
  }
}
```

In the VM, the qortex Docker container listens on `localhost:8400` with host networking. The gateway sends HTTP requests to this endpoint. No subprocess spawning is needed.

### If the agent does not see memory tools

- **Check config key**: it must be `agents.defaults.memorySearch` (not `memory`). If you use the wrong key, OpenClaw never sees your provider setting; `provider` defaults to `"auto"` and the SQLite/embedding path runs (often OpenAI). So "we had qortex but it wasn't being used" usually means the key was wrong or the merged config didn't have `memorySearch`. See OpenClaw's Zod schema or `dist/config/zod-schema.agent-runtime.js` for the exact shape.
- **Check config is loaded**: the gateway must receive this config when building the tool list (e.g. from `~/.openclaw/openclaw.json` in the VM).
- **Check plugin**: memory-core must be loaded and the memory slot must be `memory-core` (default). If you set `plugins.slots.memory` to another plugin, the core memory tools are not registered.
- **Check tool policy**: ensure the agent's effective tool policy allows `memory_search` / `memory_get` (e.g. via `group:memory` or an explicit allow list).
- **Check bundled plugins dir**: the gateway resolves extensions from `OPENCLAW_BUNDLED_PLUGINS_DIR` or by walking up from `dist/`. If the env var is missing and the walk-up fails (e.g. overlay mounts), memory-core is never discovered and the tools are never registered.

**Fix:** The gateway only picks up environment variables when it starts. The systemd unit sets `OPENCLAW_BUNDLED_PLUGINS_DIR`, but if the gateway was started before that was added (or before you re-provisioned), it won't have it. Re-provision: `bilrost up`. After any config change, restart the gateway: `bilrost restart`.

**Quick manual fix (no reprovision):** If you already have `memorySearch` with `provider: "qortex"` but the agent still doesn't see the tools, patch the config in the VM and restart:

```bash
limactl shell openclaw-sandbox -- bash -c 'jq "
  .agents.defaults.memorySearch.enabled = true |
  .agents.defaults.memorySearch.qortex.transport = \"http\" |
  .agents.defaults.memorySearch.qortex.http.baseUrl = \"http://localhost:8400\" |
  .tools.alsoAllow = ((.tools.alsoAllow // []) + [\"group:memory\"] | unique)
" ~/.openclaw/openclaw.json > /tmp/out.json && mv /tmp/out.json ~/.openclaw/openclaw.json'
bilrost restart
```

### Verification (in the VM)

Run these from the host. Use `bash -c '...'` so `~` expands inside the VM to the VM user's home, not the host's:

```bash
# Config has memorySearch with HTTP transport
limactl shell openclaw-sandbox -- bash -c 'jq ".agents.defaults.memorySearch" ~/.openclaw/openclaw.json'

# qortex container is running
limactl shell openclaw-sandbox -- docker ps | grep qortex

# Health check passes
limactl shell openclaw-sandbox -- bash -c \
  'curl -s -H "Authorization: Bearer $(sudo cat /etc/openclaw/qortex-api-key)" \
   http://localhost:8400/v1/health'
```

### Auto-injection on provision

When the sandbox is provisioned with qortex enabled (`qortex_enabled: true`, which is the default), the **gateway** role's VM path-fix step will:

- **If `memorySearch` is missing**: inject the full `agents.defaults.memorySearch` block with `enabled`, `provider`, and `qortex` containing `transport: "http"` and `http.baseUrl`.
- **If `memorySearch` exists**: patch it to add `enabled: true` and HTTP transport config.
- **Strip `command`** from both `memorySearch.qortex` and `learning.qortex` when HTTP transport is active (prevents subprocess conflicts).
- Add `group:memory` to `tools.alsoAllow` so the memory tools are allowed even when `tools.profile` is messaging.

Provision/re-provision uses `bilrost up` (or `bilrost up --fresh` to destroy and recreate). There is no `bilrost provision` command.

### Updating config inside the VM

Config in the VM lives at **`~/.openclaw/openclaw.json`** (VM user's home). Ways to change it:

1. **Edit in the VM** (survives until next provision overwrite if config is copied from mount):
   ```bash
   limactl shell openclaw-sandbox -- bash -c 'nano ~/.openclaw/openclaw.json'
   ```
   Or use `jq` to patch and write back. After editing, restart the gateway so it reloads config: `bilrost restart`.

2. **Edit on the host and re-copy** (if you use `--config` and the gateway copies from a mount): change the file in your host config dir (e.g. `~/.openclaw/openclaw.json`), then run `bilrost up` so the gateway role copies and re-applies fix-vm-paths, or copy the file into the VM manually and run `bilrost restart`.

3. **Re-provision**: run `bilrost up` (or `bilrost up --fresh` to destroy and recreate) so the playbook copies config from the mount and runs fix-vm-paths (injecting memorySearch and alsoAllow when qortex is enabled).
