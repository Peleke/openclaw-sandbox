# Telegram Security Plan

**Issue**: #9 - CRITICAL: Telegram Open Access
**Branch**: `fix/telegram-security`
**Status**: Planning

---

## Problem Statement

The sandbox currently sets `dmPolicy: "open"` with `allowFrom: ["*"]` which allows **anyone** who discovers the bot to:
- Send messages and trigger agent responses
- Exhaust API credits
- Inject malicious prompts
- Abuse compute resources

We tried `dmPolicy: "pairing"` but it wasn't working during bootstrap.

---

## Root Cause Analysis

Investigation of the OpenClaw Telegram channel code revealed **5 bugs** that cause pairing to fail silently:

### Bug 1: Empty Pairing Code at Limit
**File**: `src/pairing/pairing-store.ts:393-400`

When max pending pairing requests (default: 50) is reached:
```typescript
return { code: "", created: false };  // Returns empty code!
```
User receives message: "Pairing code: " (empty)

### Bug 2: Silent Failure on Message Send
**File**: `src/telegram/bot-message-context.ts:269-285`

```typescript
await withTelegramApiErrorLogging({...}).catch(() => {});  // Error ignored!
```
If bot can't send DM (user has DMs disabled, network error), pairing request is created but user never sees code.

### Bug 3: No Pre-flight Validation
No check that bot can send DMs before entering pairing mode. Invalid config silently drops all messages.

### Bug 4: Store AllowFrom Not Normalized
Entries with `telegram:` prefix in store won't match during access check due to normalization mismatch.

### Bug 5: No Approval Notification Error Handling
**File**: `extensions/telegram/src/channel.ts:68-74`

If approval notification fails, user is added to allowlist but never notified. They don't know their next message will work.

---

## Security Requirements

| Requirement | Priority | Status |
|-------------|----------|--------|
| Default to restricted access (not open) | P0 | ❌ |
| Pairing flow works reliably | P0 | ❌ |
| Rate limiting per user | P1 | ❌ |
| Explicit opt-in for open mode | P1 | ❌ |
| Audit logging of access attempts | P2 | ❌ |

---

## Solution Design

### Phase 1: Fix Default Configuration (Sandbox)

**Goal**: Sandbox defaults to secure config, requires explicit opt-in for open access.

#### 1.1 New Ansible Variables

```yaml
# ansible/roles/gateway/defaults/main.yml
telegram_enabled: false                    # Must explicitly enable
telegram_dm_policy: "pairing"             # Default to pairing, not open
telegram_allow_from: []                   # Empty by default
telegram_require_explicit_open: true      # Fail if "open" without confirmation
```

#### 1.2 Update fix-vm-paths.yml

```yaml
# Only configure Telegram if explicitly enabled
- name: Configure Telegram (if enabled)
  when: telegram_enabled | bool
  block:
    - name: Validate open mode requires confirmation
      when: telegram_dm_policy == "open"
      ansible.builtin.assert:
        that:
          - telegram_allow_open_confirmed | default(false) | bool
        fail_msg: |
          ⚠️  SECURITY WARNING: telegram_dm_policy is "open"
          This allows ANYONE to message your bot.

          To confirm this is intentional, set:
            telegram_allow_open_confirmed: true

          Recommended: Use "pairing" instead.

    - name: Set Telegram config
      ansible.builtin.set_fact:
        telegram_config:
          dmPolicy: "{{ telegram_dm_policy }}"
          allowFrom: "{{ telegram_allow_from }}"
```

#### 1.3 Bootstrap Validation

Add to `bootstrap.sh`:
```bash
# Warn if enabling open Telegram access
if [[ "$TELEGRAM_DM_POLICY" == "open" ]]; then
  echo "⚠️  WARNING: Telegram open access enabled!"
  echo "   Anyone can message your bot."
  read -p "Continue? [y/N] " -n 1 -r
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi
```

### Phase 2: Self-Service Pairing (Sandbox)

**Goal**: Users can self-enroll with a pairing secret, no manual approval needed.

#### 2.1 Pairing Secret

```yaml
# In secrets.env
TELEGRAM_PAIRING_SECRET=your-random-secret-here
```

#### 2.2 Flow

```
User → Bot: /start mysecretkey
Bot → (validates secret)
Bot → (adds user to allowlist)
Bot → User: "Welcome! You're now authorized."
```

**Implementation**: This requires OpenClaw changes (not just sandbox). Create upstream issue.

### Phase 3: Fallback - Manual Allowlist (Sandbox)

**Goal**: If pairing doesn't work, provide manual allowlist bootstrap.

#### 3.1 Pre-populate Allowlist

```yaml
# bootstrap.sh flag
./bootstrap.sh --telegram-allow 123456789,987654321

# Or in secrets
TELEGRAM_ALLOWED_USERS=123456789,987654321
```

#### 3.2 Ansible Implementation

```yaml
- name: Parse allowed users from env
  when: secrets_telegram_allowed_users is defined
  ansible.builtin.set_fact:
    telegram_allow_from: "{{ secrets_telegram_allowed_users.split(',') }}"
```

### Phase 4: Rate Limiting (Future)

**Goal**: Prevent abuse even from authorized users.

```yaml
# Gateway config
telegram:
  rateLimit:
    perMinute: 10
    perHour: 60
    perDay: 200
    maxMessageLength: 4000
```

**Implementation**: Requires OpenClaw gateway changes. Create upstream issue.

---

## Implementation Checklist

### Sandbox Changes (This PR)

- [ ] Add `telegram_enabled` default (false)
- [ ] Add `telegram_dm_policy` default ("pairing")
- [ ] Add `telegram_allow_from` default ([])
- [ ] Add `telegram_require_explicit_open` guard
- [ ] Update `fix-vm-paths.yml` with validation
- [ ] Add `--telegram-allow` flag to bootstrap.sh
- [ ] Parse `TELEGRAM_ALLOWED_USERS` from secrets
- [ ] Update README with security documentation
- [ ] Add tests for Telegram config validation

### Upstream Issues (OpenClaw)

- [ ] Issue: Fix empty pairing code at limit (Bug 1)
- [ ] Issue: Handle pairing message send failure (Bug 2)
- [ ] Issue: Add pre-flight bot validation (Bug 3)
- [ ] Issue: Normalize store allowFrom entries (Bug 4)
- [ ] Issue: Handle approval notification failure (Bug 5)
- [ ] Issue: Add self-service pairing with secret
- [ ] Issue: Add rate limiting config

---

## Test Plan

### Unit Tests (Ansible)

```bash
# Test that open mode requires confirmation
ansible-playbook playbook.yml -e "telegram_dm_policy=open"
# Should fail with security warning

# Test that open mode works with confirmation
ansible-playbook playbook.yml -e "telegram_dm_policy=open telegram_allow_open_confirmed=true"
# Should succeed
```

### E2E Tests

```bash
# Test pairing mode (manual)
1. Bootstrap with pairing mode
2. Message bot from unknown user
3. Verify pairing code is sent
4. Approve via CLI
5. Verify user can now message

# Test allowlist mode
1. Bootstrap with --telegram-allow <your-id>
2. Message bot
3. Verify response received
4. Message from different user
5. Verify message blocked
```

### Security Tests (Adversarial)

```bash
# Test rate limiting (when implemented)
# Send 100 messages in 1 minute
# Verify rate limit kicks in

# Test max message length
# Send very long message
# Verify truncation/rejection

# Test pairing spam
# Generate 100 pairing requests
# Verify limit enforced
```

---

## Rollout Plan

1. **Phase 1**: Merge this PR with default guards
2. **Phase 2**: Create upstream issues for OpenClaw fixes
3. **Phase 3**: Once upstream fixes merged, enable pairing by default
4. **Phase 4**: Add rate limiting (future release)

---

## Security Considerations

1. **Pairing secrets should be strong** - Minimum 16 chars, random
2. **User IDs are immutable** - Can be trusted for allowlist
3. **Bot tokens must be rotated** - Every 6 months or on compromise
4. **Audit logging** - Phase S8 will add access attempt logging
5. **Defense in depth** - Network isolation + auth + rate limiting

---

## References

- [Telegram Bot API - setWebhook](https://core.telegram.org/bots/api#setwebhook)
- [OpenClaw Security Documentation](https://docs.openclaw.ai/gateway/security)
- [grammY Ratelimiter Plugin](https://grammy.dev/plugins/ratelimiter)
- OpenClaw source: `src/telegram/bot-message-context.ts`, `src/pairing/pairing-store.ts`
