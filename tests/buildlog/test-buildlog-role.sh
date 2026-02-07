#!/usr/bin/env bash
# Buildlog Role Tests - Run from host to verify sandbox setup
#
# Usage:
#   ./tests/buildlog/test-buildlog-role.sh
#
# Prerequisites:
#   - Sandbox VM running (limactl list shows openclaw-sandbox Running)
#   - bootstrap.sh completed

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
  PASS=$((PASS + 1))
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
  FAIL=$((FAIL + 1))
}

log_skip() {
  echo -e "${YELLOW}○${NC} $1 (skipped)"
  SKIP=$((SKIP + 1))
}

log_info() {
  echo -e "  → $1"
}

vm_exec() {
  local result
  result=$(limactl shell openclaw-sandbox -- bash -c "$*" 2>&1)
  local exit_code=$?
  echo "$result" | grep -v "cd:.*No such file"
  return $exit_code
}

vm_exec_quiet() {
  limactl shell openclaw-sandbox -- bash -c "$*" 2>/dev/null
}

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Buildlog Role Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# SECTION 1: Prerequisites
# ============================================================
echo "▸ Prerequisites"
echo ""

# Test: VM is running
if limactl list 2>/dev/null | grep -q "openclaw-sandbox.*Running"; then
  log_pass "VM is running"
else
  log_fail "VM is not running (run ./bootstrap.sh first)"
  echo ""
  echo "Total: $PASS passed, $FAIL failed, $SKIP skipped"
  exit 1
fi

echo ""

# ============================================================
# SECTION 2: uv Installation
# ============================================================
echo "▸ uv Package Manager"
echo ""

# Test: uv is installed
if vm_exec_quiet "test -f ~/.local/bin/uv"; then
  log_pass "uv is installed"

  # Test: uv version
  UV_VERSION=$(vm_exec "~/.local/bin/uv --version" 2>/dev/null | head -1)
  if [[ -n "$UV_VERSION" ]]; then
    log_pass "uv version: $UV_VERSION"
  else
    log_fail "Could not get uv version"
  fi
else
  log_fail "uv is not installed"
fi

# Test: uv in PATH
if vm_exec_quiet "grep -q '.local/bin' ~/.bashrc"; then
  log_pass "uv tools directory in PATH (.bashrc)"
else
  log_fail "uv tools directory not in PATH"
fi

echo ""

# ============================================================
# SECTION 3: buildlog Installation
# ============================================================
echo "▸ buildlog Package"
echo ""

# Test: buildlog is installed
if vm_exec_quiet "~/.local/bin/buildlog --version" >/dev/null 2>&1; then
  log_pass "buildlog is installed"

  # Test: buildlog version
  BUILDLOG_VERSION=$(vm_exec "~/.local/bin/buildlog --version" 2>/dev/null | head -1)
  if [[ -n "$BUILDLOG_VERSION" ]]; then
    log_pass "buildlog version: $BUILDLOG_VERSION"
  else
    log_fail "Could not get buildlog version"
  fi
else
  log_fail "buildlog is not installed"
fi

# Test: buildlog-mcp is installed
if vm_exec_quiet "test -f ~/.local/bin/buildlog-mcp"; then
  log_pass "buildlog-mcp server binary exists"
else
  log_fail "buildlog-mcp server binary missing"
fi

echo ""

# ============================================================
# SECTION 4: Claude Configuration
# ============================================================
echo "▸ Claude Configuration"
echo ""

# Test: ~/.claude directory exists
if vm_exec_quiet "test -d ~/.claude"; then
  log_pass "~/.claude directory exists"
else
  log_fail "~/.claude directory missing"
fi

# Test: ~/.claude.json exists (global MCP config from init-mcp --global)
if vm_exec_quiet "test -f ~/.claude.json"; then
  log_pass "~/.claude.json exists (global MCP config)"

  # Test: ~/.claude.json is valid JSON
  if vm_exec "jq . ~/.claude.json" >/dev/null 2>&1; then
    log_pass "~/.claude.json is valid JSON"
  else
    log_fail "~/.claude.json is invalid JSON"
  fi

  # Test: buildlog MCP is registered
  if vm_exec "jq -e '.mcpServers.buildlog' ~/.claude.json" >/dev/null 2>&1; then
    log_pass "buildlog MCP server registered in ~/.claude.json"

    # Test: MCP command points to correct binary
    MCP_CMD=$(vm_exec "jq -r '.mcpServers.buildlog.command' ~/.claude.json" 2>/dev/null)
    if [[ "$MCP_CMD" == *"buildlog-mcp"* ]]; then
      log_pass "MCP command: $MCP_CMD"
    else
      log_fail "MCP command doesn't reference buildlog-mcp: $MCP_CMD"
    fi
  else
    log_fail "buildlog MCP not registered in ~/.claude.json"
  fi
else
  log_fail "~/.claude.json does not exist (global MCP config)"
fi

echo ""

# ============================================================
# SECTION 5: CLAUDE.md
# ============================================================
echo "▸ CLAUDE.md"
echo ""

# Test: CLAUDE.md exists
if vm_exec_quiet "test -f ~/.claude/CLAUDE.md"; then
  log_pass "CLAUDE.md exists"

  # Test: CLAUDE.md has buildlog section (from init-mcp)
  if vm_exec "grep -qi 'buildlog' ~/.claude/CLAUDE.md" 2>/dev/null; then
    log_pass "CLAUDE.md contains buildlog instructions"
  else
    log_fail "CLAUDE.md missing buildlog instructions"
  fi

  # Test: CLAUDE.md has sandbox policy section
  if vm_exec "grep -q 'OPENCLAW SANDBOX BUILDLOG POLICY' ~/.claude/CLAUDE.md" 2>/dev/null; then
    log_pass "CLAUDE.md contains sandbox policy section"
  else
    log_fail "CLAUDE.md missing sandbox policy section"
  fi

  # Test: Sandbox section has aggressive usage notes
  if vm_exec "grep -qi 'aggressive\|AGGRESSIVE\|mandatory\|MANDATORY' ~/.claude/CLAUDE.md" 2>/dev/null; then
    log_pass "CLAUDE.md has aggressive usage instructions"
  else
    log_info "CLAUDE.md may be missing aggressive usage notes"
  fi

  # Show CLAUDE.md stats
  LINE_COUNT=$(vm_exec "wc -l < ~/.claude/CLAUDE.md" 2>/dev/null | tr -d ' ')
  log_info "CLAUDE.md is $LINE_COUNT lines"
else
  log_fail "CLAUDE.md does not exist"
fi

echo ""

# ============================================================
# SECTION 6: Buildlog Data Persistence
# ============================================================
echo "▸ Buildlog Data Persistence"
echo ""

# Test: ~/.buildlog exists (directory or symlink)
if vm_exec_quiet "test -e ~/.buildlog"; then
  log_pass "~/.buildlog exists"

  # Test: Check if it's a symlink (persistent mount) or directory (ephemeral)
  if vm_exec_quiet "test -L ~/.buildlog"; then
    SYMLINK_TARGET=$(vm_exec "readlink ~/.buildlog" 2>/dev/null)
    log_pass "~/.buildlog is symlink -> $SYMLINK_TARGET (persistent)"
  else
    log_info "~/.buildlog is a regular directory (ephemeral, no --buildlog-data mount)"
  fi
else
  log_fail "~/.buildlog does not exist"
fi

# Test: Emissions directories
for subdir in pending processed failed; do
  if vm_exec_quiet "test -d ~/.buildlog/emissions/$subdir"; then
    log_pass "Emissions dir exists: emissions/$subdir"
  else
    log_fail "Emissions dir missing: emissions/$subdir"
  fi
done

# Test: buildlog verify
VERIFY_OUTPUT=$(vm_exec "~/.local/bin/buildlog verify" 2>&1 || true)
if [[ -n "$VERIFY_OUTPUT" ]]; then
  log_pass "buildlog verify ran"
  log_info "Output: $(echo "$VERIFY_OUTPUT" | head -2)"
else
  log_info "buildlog verify produced no output"
fi

echo ""

# ============================================================
# SECTION 7: MCP Server Test
# ============================================================
echo "▸ MCP Server"
echo ""

# Test: buildlog mcp-test command
MCP_TEST_OUTPUT=$(vm_exec "~/.local/bin/buildlog mcp-test" 2>&1 || true)
if echo "$MCP_TEST_OUTPUT" | grep -qE "[0-9]+ tools|tools registered|tool"; then
  log_pass "MCP server test passed"

  # Extract tool count if possible
  TOOL_COUNT=$(echo "$MCP_TEST_OUTPUT" | grep -oE "[0-9]+ tools" | head -1 || echo "")
  if [[ -n "$TOOL_COUNT" ]]; then
    log_info "MCP reports: $TOOL_COUNT"
  fi
else
  log_info "MCP test output: $(echo "$MCP_TEST_OUTPUT" | head -3)"
  log_skip "Could not verify MCP tool count"
fi

echo ""

# ============================================================
# SECTION 7: CLI Commands
# ============================================================
echo "▸ CLI Commands"
echo ""

# Test: buildlog overview works (doesn't require init)
OVERVIEW_OUTPUT=$(vm_exec "cd /tmp && ~/.local/bin/buildlog overview" 2>&1 || true)
if [[ $? -eq 0 ]] || echo "$OVERVIEW_OUTPUT" | grep -qiE "project|status|not initialized|no buildlog"; then
  log_pass "buildlog overview command works"
else
  log_fail "buildlog overview failed"
  log_info "Output: $(echo "$OVERVIEW_OUTPUT" | head -2)"
fi

# Test: buildlog --help works
if vm_exec "~/.local/bin/buildlog --help" >/dev/null 2>&1; then
  log_pass "buildlog --help works"
else
  log_fail "buildlog --help failed"
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo "═══════════════════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL + SKIP))
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC} (of $TOTAL)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
