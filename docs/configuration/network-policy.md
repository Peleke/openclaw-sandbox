# Network Policy

The VM runs a UFW (Uncomplicated Firewall) with a default-deny policy in both directions. Only explicitly allowlisted traffic is permitted. All denied connections are logged for audit.

## Firewall Rules

| Direction | Port | Protocol | Purpose |
|-----------|------|----------|---------|
| **IN** | 18789 | TCP | Gateway API (agents connect here) |
| **IN** | 22 | TCP | SSH (Ansible provisioning, `limactl shell`) |
| **OUT** | 443 | TCP | HTTPS (LLM APIs, GitHub, npm registries) |
| **OUT** | 80 | TCP | HTTP (APT package updates) |
| **OUT** | 53 | UDP | DNS (name resolution) |
| **OUT** | 53 | TCP | DNS (large responses, zone transfers) |
| **OUT** | 100.64.0.0/10 | * | Tailscale CGNAT range |
| **OUT** | 41641 | UDP | Tailscale direct connections |
| **OUT** | 123 | UDP | NTP (time synchronization) |
| **OUT** | 4318 | TCP | OTEL export to host collector (when `qortex_otel_enabled`, to `192.168.5.2`) |
| **IN/OUT** | lo | * | Loopback (required for local services) |

**Everything else is denied and logged.**

## What Each Rule Allows

### Inbound

**Gateway (TCP 18789):** The OpenClaw gateway listens on this port. Agents, the TUI, and the host `claw` CLI connect here. This is the only way to interact with the gateway from outside the VM.

**SSH (TCP 22):** Required for Lima VM management. Ansible uses SSH to provision the VM, and `limactl shell` uses SSH to open interactive sessions. Without this rule, you cannot manage the VM.

### Outbound

**HTTPS (TCP 443):** Required for LLM API calls (Anthropic, OpenAI, Google AI, OpenRouter), GitHub API (`gh` commands), npm/PyPI package downloads, and messaging API calls (Slack, Discord, Telegram).

**HTTP (TCP 80):** Required for APT package repository updates. Ubuntu mirrors serve package metadata over HTTP.

**DNS (UDP/TCP 53):** Required for name resolution. Without DNS, no outbound HTTPS connections can be established.

**Tailscale (100.64.0.0/10 + UDP 41641):** Allows routing traffic to your Tailscale network through the host. The CGNAT range covers all Tailscale node IPs. Port 41641 enables direct peer-to-peer connections.

**NTP (UDP 123):** Required for time synchronization. TLS certificate validation fails with incorrect system time, which would break all HTTPS connections.

**OTEL (TCP 4318):** When `qortex_otel_enabled` is true (default), allows the VM to send OpenTelemetry traces and metrics to the host collector at `192.168.5.2:4318` (Lima's host gateway IP). This is scoped to a single IP, not a broad outbound rule. The qortex learning pipeline uses this to export bandit selection events, observation rewards, and Prometheus metrics to host-side Grafana.

## Default Policies

The firewall starts with:

```
Default incoming: DENY
Default outgoing: DENY
```

This is a strict allowlist model. If a port or destination is not explicitly in the table above, it is blocked and logged.

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `firewall_reset_on_run` | `true` | Reset UFW to clean state on each provision |
| `firewall_gateway_port` | `18789` | Inbound port to allow for the gateway |
| `firewall_tailscale_cidr` | `100.64.0.0/10` | Tailscale IP range |
| `firewall_tailscale_port` | `41641` | Tailscale direct connection port |
| `firewall_enable_logging` | `true` | Log denied packets |
| `firewall_log_limit` | `3/min` | Rate limit for log entries |
| `firewall_otel_host_ip` | `192.168.5.2` | Host IP for OTEL export (Lima gateway) |
| `firewall_otel_ports` | `["4318"]` | Ports to allow for OTEL export |

!!! warning "firewall_reset_on_run"
    By default, UFW is reset to a clean state on every provision run. This ensures the firewall matches the expected configuration. If you add custom rules manually, set `firewall_reset_on_run=false` to preserve them:
    ```bash
    ./bootstrap.sh --openclaw ~/Projects/openclaw -e "firewall_reset_on_run=false"
    ```

## Customizing Rules

### Adding an outbound rule

SSH into the VM and add the rule:

```bash
# Allow outbound to a specific service
limactl shell openclaw-sandbox -- sudo ufw allow out to any port 8080 proto tcp

# Allow outbound to a specific IP
limactl shell openclaw-sandbox -- sudo ufw allow out to 10.0.0.5
```

!!! note "Custom rules are lost on re-provision"
    Unless `firewall_reset_on_run=false`, all custom rules are wiped on the next `./bootstrap.sh` run. For permanent additions, modify `ansible/roles/firewall/tasks/main.yml`.

### Allowed domains reference

The `firewall_allowed_domains` list in the firewall defaults documents which domains the HTTPS rule is intended to cover:

```yaml
firewall_allowed_domains:
  - api.openai.com
  - api.anthropic.com
  - generativelanguage.googleapis.com
  - bedrock-runtime.us-east-1.amazonaws.com
  - slack.com
  - api.slack.com
  - discord.com
  - discordapp.com
```

!!! tip "The HTTPS rule is port-based, not domain-based"
    The current firewall allows **all** outbound TCP 443 traffic, not just the domains listed above. The domain list is documentary -- it describes which services the sandbox is designed to reach. Any HTTPS endpoint is reachable from the VM. Domain-based filtering would require a transparent proxy or DNS-level blocking, which is not currently implemented.

## Verification Commands

```bash
# Check firewall status
limactl shell openclaw-sandbox -- sudo ufw status verbose

# Check firewall is active
limactl shell openclaw-sandbox -- sudo ufw status | head -1

# View denied connections in logs
limactl shell openclaw-sandbox -- sudo journalctl -k | grep UFW

# Test outbound HTTPS
limactl shell openclaw-sandbox -- curl -s -o /dev/null -w '%{http_code}' https://api.anthropic.com

# Test that non-allowed ports are blocked
limactl shell openclaw-sandbox -- curl -s --connect-timeout 5 telnet://example.com:25
# Should timeout/fail

# Check specific rules
limactl shell openclaw-sandbox -- sudo ufw status numbered
```

## Audit Trail

With `firewall_enable_logging=true` (the default), denied packets are logged to the kernel log:

```bash
# View firewall denials
limactl shell openclaw-sandbox -- sudo dmesg | grep UFW

# Follow live
limactl shell openclaw-sandbox -- sudo journalctl -kf | grep UFW
```

Log entries include source/destination IP, port, protocol, and interface -- giving you visibility into what the VM (or containers) attempted to reach and was denied.
