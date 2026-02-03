# Security Remediation Roadmap

> Generated from security audit on 2026-02-03

## Overview

The sandbox has **strong foundational security** (default-deny firewall, no_log secrets, proper permissions) but has **access control gaps** that need addressing before production use.

---

## 🔴 CRITICAL: Telegram Open Access

### Current State
```yaml
# fix-vm-paths.yml unconditionally sets:
dmPolicy: "open"
allowFrom: ["*"]
```

**Risk**: Anyone who discovers the bot can send messages, trigger agent responses, and potentially:
- Exhaust API credits
- Inject malicious prompts
- Abuse compute resources

### Remediation Plan

**Phase 1: Explicit Opt-In (S7)**
```yaml
# Add to ansible/roles/gateway/defaults/main.yml
telegram_dm_policy: "restricted"  # Default to restricted
telegram_allowed_users: []        # Empty by default

# In fix-vm-paths.yml, only set if explicitly configured:
- name: Configure Telegram access (if enabled)
  when: telegram_allowed_users | length > 0
  ansible.builtin.set_fact:
    openclaw_config: "{{ openclaw_config | combine({...}) }}"
```

**Phase 2: Pairing Flow (S8)**
- Restore `dmPolicy: "pairing"` as default
- Fix the silent message drop bug (add logging)
- Document pairing code workflow in README

**Phase 3: Rate Limiting (S9)**
- Add rate limiting config to gateway
- Per-user message limits
- Cooldown periods for new users

### Files to Modify
- `ansible/roles/gateway/defaults/main.yml` - Add telegram config vars
- `ansible/roles/gateway/tasks/fix-vm-paths.yml` - Conditional Telegram setup
- `README.md` - Document secure Telegram setup

### Acceptance Criteria
- [ ] Default config does NOT allow open Telegram access
- [ ] User must explicitly list allowed Telegram user IDs
- [ ] Pairing flow works and logs properly
- [ ] Rate limiting prevents abuse

---

## 🟠 HIGH: HTTPS Firewall Not Enforced to Allowlist

### Current State
```yaml
# firewall/tasks/main.yml allows ANY HTTPS:
- name: Allow outbound HTTPS
  community.general.ufw:
    rule: allow
    port: "443"
    proto: tcp
    direction: out
```

**Risk**: Agent can exfiltrate data to any HTTPS endpoint, not just LLM APIs.

### Remediation Plan

**Phase 1: Document the Limitation (Now)**
- Add warning to README that HTTPS is not domain-restricted
- UFW cannot filter by domain (only IP)

**Phase 2: DNS-Based Allowlist (S8)**
```bash
# Create script to resolve allowed domains and create IP rules
# Run on boot/provision

ALLOWED_DOMAINS=(
  "api.anthropic.com"
  "api.openai.com"
  "generativelanguage.googleapis.com"
)

for domain in "${ALLOWED_DOMAINS[@]}"; do
  for ip in $(dig +short "$domain"); do
    ufw allow out to "$ip" port 443 proto tcp
  done
done

# Then deny all other 443
ufw deny out port 443 proto tcp
```

**Phase 3: Transparent Proxy (S10)**
- Deploy mitmproxy or squid in VM
- Force all HTTPS through proxy
- Allowlist domains at proxy level
- Log all requests for audit

### Files to Modify
- `ansible/roles/firewall/tasks/main.yml` - Add domain resolution
- `ansible/roles/firewall/templates/resolve-domains.sh.j2` - New script
- `ansible/roles/firewall/defaults/main.yml` - Domain allowlist

### Acceptance Criteria
- [ ] HTTPS only allowed to known LLM API IPs
- [ ] DNS resolution runs on each provision
- [ ] Fallback if DNS fails (deny all vs allow all - configurable)
- [ ] Audit log of HTTPS destinations

---

## 🟠 HIGH: Vault Mount Writable

### Current State
```yaml
# bootstrap.sh creates writable mount:
- location: "$vault_path"
  mountPoint: "/mnt/obsidian"
  writable: true  # DANGEROUS
```

**Risk**: Rogue agent can modify/delete user's Obsidian vault (irreversible data loss).

### Remediation Plan

**Phase 1: Default Read-Only (S7)**
```bash
# bootstrap.sh change:
writable: ${VAULT_WRITABLE:-false}  # Default to read-only

# User must explicitly opt-in:
./bootstrap.sh --vault ~/Vaults/main --vault-writable
```

**Phase 2: Copy-on-Write (S9)**
- Mount vault read-only at `/mnt/obsidian-ro`
- Create writable overlay at `/mnt/obsidian`
- Agent writes go to overlay, not original vault
- User can review/merge changes

**Phase 3: Git-Based Vault (S10)**
- If vault is git repo, use git worktree
- Agent commits changes to sandbox branch
- User reviews PR before merging to main

### Files to Modify
- `bootstrap.sh` - Add `--vault-writable` flag, default false
- `lima/openclaw-sandbox.template.yaml` - Template for mount config
- `README.md` - Document vault security options

### Acceptance Criteria
- [ ] Vault is read-only by default
- [ ] Explicit flag required for write access
- [ ] Warning displayed when writable enabled
- [ ] Optional overlay/CoW mode for safe writes

---

## 🟡 MEDIUM: Secrets Regex Bug

### Current State
```yaml
# Greedy regex can match beyond intended scope:
regex_search('ANTHROPIC_API_KEY=(.+)', '\\1')
```

**Risk**: If secrets file has unusual formatting, regex could capture unintended content.

### Remediation Plan

**Phase 1: Fix Regex (S7)**
```yaml
# Change from:
regex_search('ANTHROPIC_API_KEY=(.+)', '\\1')

# To:
regex_search('ANTHROPIC_API_KEY=([^\n\r]+)', '\\1')
```

### Files to Modify
- `ansible/roles/secrets/tasks/main.yml` - Fix all regex patterns

### Acceptance Criteria
- [ ] All secret extraction regex uses `[^\n\r]+` not `.+`
- [ ] Test with multi-line secrets file
- [ ] Test with trailing whitespace

---

## 🟡 MEDIUM: /tmp Mount Exposure

### Current State
```yaml
# Fallback mounts entire /tmp:
- location: "/tmp"
  mountPoint: "/mnt/secrets"
```

**Risk**: Exposes temporary files from other processes.

### Remediation Plan

**Phase 1: Dedicated Secrets Directory (S7)**
```bash
# bootstrap.sh change:
SECRETS_STAGING="/tmp/openclaw-secrets-$$"
mkdir -p "$SECRETS_STAGING"
cp "$secrets_path" "$SECRETS_STAGING/secrets.env"

# Mount only the staging dir, not all of /tmp
- location: "$SECRETS_STAGING"
  mountPoint: "/mnt/secrets"
```

### Files to Modify
- `bootstrap.sh` - Create isolated staging directory

### Acceptance Criteria
- [ ] Only secrets file is mounted, not entire /tmp
- [ ] Staging directory cleaned up on VM stop

---

## Implementation Priority

| Issue | Severity | Effort | Phase |
|-------|----------|--------|-------|
| Telegram open access | 🔴 CRITICAL | Medium | S7 |
| Vault writable | 🟠 HIGH | Low | S7 |
| Secrets regex | 🟡 MEDIUM | Low | S7 |
| /tmp mount | 🟡 MEDIUM | Low | S7 |
| HTTPS allowlist | 🟠 HIGH | High | S8 |
| Rate limiting | 🟡 MEDIUM | Medium | S9 |
| Transparent proxy | 🟡 MEDIUM | High | S10 |

---

## What's Already Good ✅

These don't need changes:

- **Default-deny firewall** - Correct architecture
- **no_log on secrets** - Comprehensive coverage
- **File permissions (0600)** - Proper secrets protection
- **EnvironmentFile=** - Secrets hidden from process list
- **SSH key auth** - No default passwords
- **Service user** - Gateway doesn't run as root
- **Read-only mounts** - Most mounts are read-only
- **Role ordering** - Secrets → Gateway → Firewall
