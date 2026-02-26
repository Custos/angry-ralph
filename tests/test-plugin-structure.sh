#!/usr/bin/env bash
# tests/test-plugin-structure.sh — Validate the complete plugin structure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
PASS=0
FAIL=0

assert_exists() {
  local desc="$1" path="$2"
  if [ -e "$PLUGIN_DIR/$path" ]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc ($path missing)"
    ((FAIL++)) || true
  fi
}

assert_contains() {
  local desc="$1" file="$2" pattern="$3"
  if grep -q "$pattern" "$PLUGIN_DIR/$file" 2>/dev/null; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc ('$pattern' not found in $file)"
    ((FAIL++)) || true
  fi
}

echo "Validating angry-ralph plugin structure..."
echo ""

# Manifest
assert_exists "plugin.json exists" ".claude-plugin/plugin.json"
assert_contains "manifest has name" ".claude-plugin/plugin.json" '"name": "angry-ralph"'

# Commands
assert_exists "angry-ralph command" "commands/angry-ralph.md"
assert_exists "cancel-ralph command" "commands/cancel-ralph.md"
assert_exists "help command" "commands/help.md"
assert_contains "angry-ralph has frontmatter" "commands/angry-ralph.md" "name: angry-ralph"
assert_contains "cancel-ralph has frontmatter" "commands/cancel-ralph.md" "name: cancel-ralph"
assert_contains "help has frontmatter" "commands/help.md" "name: angry-ralph-help"
assert_exists "angry-review-code command" "commands/angry-review-code.md"
assert_exists "angry-review-plan command" "commands/angry-review-plan.md"
assert_exists "angry-review-section command" "commands/angry-review-section.md"
assert_contains "angry-review-code has frontmatter" "commands/angry-review-code.md" "name: angry-review-code"
assert_contains "angry-review-plan has frontmatter" "commands/angry-review-plan.md" "name: angry-review-plan"
assert_contains "angry-review-section has frontmatter" "commands/angry-review-section.md" "name: angry-review-section"
assert_exists "angry-status command" "commands/angry-status.md"
assert_contains "angry-status has frontmatter" "commands/angry-status.md" "name: angry-status"
assert_exists "angry-skip-to command" "commands/angry-skip-to.md"
assert_contains "angry-skip-to has frontmatter" "commands/angry-skip-to.md" "name: angry-skip-to"
assert_exists "angry-rerun command" "commands/angry-rerun.md"
assert_contains "angry-rerun has frontmatter" "commands/angry-rerun.md" "name: angry-rerun"
assert_exists "angry-split command" "commands/angry-split.md"
assert_contains "angry-split has frontmatter" "commands/angry-split.md" "name: angry-split"

# Agent
assert_exists "external-reviewer agent" "agents/external-reviewer.md"
assert_contains "agent has name" "agents/external-reviewer.md" "name: external-reviewer"
assert_contains "agent has model" "agents/external-reviewer.md" "model: inherit"
assert_contains "agent has color" "agents/external-reviewer.md" "color: red"
assert_contains "agent has restricted tools" "agents/external-reviewer.md" 'tools: \["Bash", "Read"\]'
assert_contains "agent has examples" "agents/external-reviewer.md" "<example>"

# Skill
assert_exists "SKILL.md exists" "skills/angry-ralph/SKILL.md"
assert_contains "skill has name" "skills/angry-ralph/SKILL.md" "name: angry-ralph"
assert_contains "skill has description" "skills/angry-ralph/SKILL.md" "description:"

# Reference protocols
assert_exists "planning protocol" "skills/angry-ralph/references/planning-protocol.md"
assert_exists "review protocol" "skills/angry-ralph/references/review-protocol.md"
assert_exists "tdd protocol" "skills/angry-ralph/references/tdd-protocol.md"
assert_exists "loop protocol" "skills/angry-ralph/references/loop-protocol.md"
assert_exists "final review protocol" "skills/angry-ralph/references/final-review-protocol.md"
assert_exists "section review protocol" "skills/angry-ralph/references/section-review-protocol.md"

# Hooks
assert_exists "hooks.json" "hooks/hooks.json"
assert_exists "stop-hook.sh" "hooks/stop-hook.sh"
assert_contains "hooks.json references stop hook" "hooks/hooks.json" "stop-hook.sh"
assert_contains "hooks.json uses CLAUDE_PLUGIN_ROOT" "hooks/hooks.json" "CLAUDE_PLUGIN_ROOT"
assert_contains "hooks.json has Stop event" "hooks/hooks.json" '"Stop"'
assert_contains "hooks.json has SubagentStop event" "hooks/hooks.json" '"SubagentStop"'

# Scripts
assert_exists "validate-env.sh" "scripts/checks/validate-env.sh"
assert_exists "state.sh" "scripts/lib/state.sh"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
