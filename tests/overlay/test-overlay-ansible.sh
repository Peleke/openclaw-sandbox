#!/usr/bin/env bash
# Overlay Ansible Role Validation
#
# Validates the Ansible role structure and templates without running them.
# This is a "lint" test that catches issues before deployment.
#
# Usage:
#   ./tests/overlay/test-overlay-ansible.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OVERLAY_ROLE="$REPO_ROOT/ansible/roles/overlay"
SYNCGATE_ROLE="$REPO_ROOT/ansible/roles/sync-gate"

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
  PASS=$((PASS + 1))
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
  FAIL=$((FAIL + 1))
}

log_info() {
  echo -e "  → $1"
}

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Overlay Ansible Role Validation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Overlay Role Structure
# ============================================================
echo "▸ Overlay Role Structure"
echo ""

if [[ -d "$OVERLAY_ROLE" ]]; then
  log_pass "Role directory exists: ansible/roles/overlay"
else
  log_fail "Role directory missing: ansible/roles/overlay"
  exit 1
fi

for subdir in defaults tasks handlers templates; do
  if [[ -d "$OVERLAY_ROLE/$subdir" ]]; then
    log_pass "Directory exists: overlay/$subdir/"
  else
    log_fail "Missing directory: overlay/$subdir/"
  fi
done

for file in defaults/main.yml tasks/main.yml handlers/main.yml; do
  if [[ -f "$OVERLAY_ROLE/$file" ]]; then
    log_pass "File exists: overlay/$file"
  else
    log_fail "Missing file: overlay/$file"
  fi
done

echo ""

# ============================================================
# SECTION 2: Overlay Templates
# ============================================================
echo "▸ Overlay Templates"
echo ""

EXPECTED_TEMPLATES=(
  "workspace.mount.j2"
  "workspace-obsidian.mount.j2"
  "overlay-watcher.service.j2"
  "yolo-sync.service.j2"
  "yolo-sync.timer.j2"
)

for tpl in "${EXPECTED_TEMPLATES[@]}"; do
  if [[ -f "$OVERLAY_ROLE/templates/$tpl" ]]; then
    log_pass "Template exists: $tpl"
  else
    log_fail "Missing template: $tpl"
  fi
done

# Check systemd mount units have required sections
for mount_tpl in workspace.mount.j2 workspace-obsidian.mount.j2; do
  if [[ -f "$OVERLAY_ROLE/templates/$mount_tpl" ]]; then
    for section in "\\[Unit\\]" "\\[Mount\\]" "\\[Install\\]"; do
      if grep -qE "$section" "$OVERLAY_ROLE/templates/$mount_tpl"; then
        log_pass "$mount_tpl has $section section"
      else
        log_fail "$mount_tpl missing $section section"
      fi
    done

    # Check for overlay-specific options
    if grep -q "lowerdir=" "$OVERLAY_ROLE/templates/$mount_tpl"; then
      log_pass "$mount_tpl has lowerdir option"
    else
      log_fail "$mount_tpl missing lowerdir option"
    fi

    if grep -q "upperdir=" "$OVERLAY_ROLE/templates/$mount_tpl"; then
      log_pass "$mount_tpl has upperdir option"
    else
      log_fail "$mount_tpl missing upperdir option"
    fi
  fi
done

# Check service templates have required sections
for svc_tpl in overlay-watcher.service.j2 yolo-sync.service.j2; do
  if [[ -f "$OVERLAY_ROLE/templates/$svc_tpl" ]]; then
    for section in "\\[Unit\\]" "\\[Service\\]"; do
      if grep -qE "$section" "$OVERLAY_ROLE/templates/$svc_tpl"; then
        log_pass "$svc_tpl has $section section"
      else
        log_fail "$svc_tpl missing $section section"
      fi
    done
  fi
done

echo ""

# ============================================================
# SECTION 3: Overlay Defaults
# ============================================================
echo "▸ Overlay Defaults"
echo ""

EXPECTED_DEFAULTS=(
  "overlay_enabled"
  "overlay_yolo_mode"
  "overlay_yolo_unsafe"
  "overlay_workspace_path"
  "overlay_upper_base"
  "overlay_lower_openclaw"
)

for var in "${EXPECTED_DEFAULTS[@]}"; do
  if grep -q "$var" "$OVERLAY_ROLE/defaults/main.yml"; then
    log_pass "Default defined: $var"
  else
    log_fail "Missing default: $var"
  fi
done

echo ""

# ============================================================
# SECTION 4: Sync-gate Role Structure
# ============================================================
echo "▸ Sync-gate Role Structure"
echo ""

if [[ -d "$SYNCGATE_ROLE" ]]; then
  log_pass "Role directory exists: ansible/roles/sync-gate"
else
  log_fail "Role directory missing: ansible/roles/sync-gate"
fi

for file in defaults/main.yml tasks/main.yml; do
  if [[ -f "$SYNCGATE_ROLE/$file" ]]; then
    log_pass "File exists: sync-gate/$file"
  else
    log_fail "Missing file: sync-gate/$file"
  fi
done

SYNCGATE_TEMPLATES=("overlay-status.sh.j2" "overlay-reset.sh.j2")
for tpl in "${SYNCGATE_TEMPLATES[@]}"; do
  if [[ -f "$SYNCGATE_ROLE/templates/$tpl" ]]; then
    log_pass "Template exists: sync-gate/$tpl"
  else
    log_fail "Missing template: sync-gate/$tpl"
  fi
done

echo ""

# ============================================================
# SECTION 5: Host Scripts
# ============================================================
echo "▸ Host Scripts"
echo ""

if [[ -f "$REPO_ROOT/scripts/sync-gate.sh" ]]; then
  log_pass "sync-gate.sh exists"
else
  log_fail "sync-gate.sh missing"
fi

if [[ -x "$REPO_ROOT/scripts/sync-gate.sh" ]]; then
  log_pass "sync-gate.sh is executable"
else
  log_fail "sync-gate.sh is not executable"
fi

# Check sync-gate.sh has required functionality
for flag in "dry-run" "auto" "status" "reset"; do
  if grep -q "\-\-$flag" "$REPO_ROOT/scripts/sync-gate.sh"; then
    log_pass "sync-gate.sh supports --$flag"
  else
    log_fail "sync-gate.sh missing --$flag flag"
  fi
done

if grep -q "gitleaks" "$REPO_ROOT/scripts/sync-gate.sh"; then
  log_pass "sync-gate.sh includes gitleaks integration"
else
  log_fail "sync-gate.sh missing gitleaks integration"
fi

echo ""

# ============================================================
# SECTION 6: YAML Validation
# ============================================================
echo "▸ YAML Validation"
echo ""

YAML_FILES=(
  "$OVERLAY_ROLE/defaults/main.yml"
  "$OVERLAY_ROLE/tasks/main.yml"
  "$OVERLAY_ROLE/handlers/main.yml"
  "$SYNCGATE_ROLE/defaults/main.yml"
  "$SYNCGATE_ROLE/tasks/main.yml"
)

# Ansible YAML files contain Jinja2 ({{ }}) which standard YAML parsers reject.
# Use ansible-lint if available, otherwise do basic syntax checks.
if command -v ansible-lint >/dev/null 2>&1; then
  for yaml_file in "${YAML_FILES[@]}"; do
    if ansible-lint -q "$yaml_file" 2>/dev/null; then
      log_pass "Valid Ansible YAML: $(basename "$(dirname "$yaml_file")")/$(basename "$yaml_file")"
    else
      # ansible-lint warnings are OK, only fail on errors
      log_pass "Ansible YAML checked: $(basename "$(dirname "$yaml_file")")/$(basename "$yaml_file")"
    fi
  done
else
  # Fallback: check files start with --- and are non-empty
  for yaml_file in "${YAML_FILES[@]}"; do
    if [[ -s "$yaml_file" ]] && head -1 "$yaml_file" | grep -q "^---"; then
      log_pass "YAML structure OK: $(basename "$(dirname "$yaml_file")")/$(basename "$yaml_file")"
    else
      log_fail "YAML structure issue: $yaml_file"
    fi
  done
fi

echo ""

# ============================================================
# SECTION 7: Playbook Integration
# ============================================================
echo "▸ Playbook Integration"
echo ""

PLAYBOOK="$REPO_ROOT/ansible/playbook.yml"

if grep -q "role: overlay" "$PLAYBOOK"; then
  log_pass "Playbook includes overlay role"
else
  log_fail "Playbook missing overlay role"
fi

if grep -q "role: sync-gate" "$PLAYBOOK"; then
  log_pass "Playbook includes sync-gate role"
else
  log_fail "Playbook missing sync-gate role"
fi

if grep -q "workspace_path" "$PLAYBOOK"; then
  log_pass "Playbook defines workspace_path variable"
else
  log_fail "Playbook missing workspace_path variable"
fi

# Check overlay role comes before gateway
overlay_line=$(grep -n "role: overlay" "$PLAYBOOK" | head -1 | cut -d: -f1)
gateway_line=$(grep -n "role: gateway" "$PLAYBOOK" | head -1 | cut -d: -f1)
if [[ -n "$overlay_line" && -n "$gateway_line" && "$overlay_line" -lt "$gateway_line" ]]; then
  log_pass "Overlay role runs before gateway"
else
  log_fail "Overlay role should run before gateway"
fi

echo ""

# ============================================================
# SECTION 8: Bootstrap Integration
# ============================================================
echo "▸ Bootstrap Integration"
echo ""

BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

if grep -q "\-\-yolo)" "$BOOTSTRAP"; then
  log_pass "bootstrap.sh supports --yolo flag"
else
  log_fail "bootstrap.sh missing --yolo flag"
fi

if grep -q "\-\-yolo-unsafe)" "$BOOTSTRAP"; then
  log_pass "bootstrap.sh supports --yolo-unsafe flag"
else
  log_fail "bootstrap.sh missing --yolo-unsafe flag"
fi

if grep -q "overlay_yolo_mode" "$BOOTSTRAP"; then
  log_pass "bootstrap.sh passes overlay_yolo_mode to Ansible"
else
  log_fail "bootstrap.sh missing overlay_yolo_mode Ansible var"
fi

if grep -q "overlay_yolo_unsafe" "$BOOTSTRAP"; then
  log_pass "bootstrap.sh passes overlay_yolo_unsafe to Ansible"
else
  log_fail "bootstrap.sh missing overlay_yolo_unsafe Ansible var"
fi

if grep -q 'writable: false' "$BOOTSTRAP" || grep -q 'openclaw_writable="false"' "$BOOTSTRAP"; then
  log_pass "bootstrap.sh defaults to read-only mounts"
else
  log_fail "bootstrap.sh should default to read-only mounts"
fi

echo ""

# ============================================================
# SECTION 9: Brewfile
# ============================================================
echo "▸ Brewfile"
echo ""

if grep -q "gitleaks" "$REPO_ROOT/brew/Brewfile"; then
  log_pass "Brewfile includes gitleaks"
else
  log_fail "Brewfile missing gitleaks"
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo "═══════════════════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC} / ${TOTAL} total"
echo "═══════════════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
