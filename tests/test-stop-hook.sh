#!/usr/bin/env bash
# tests/test-stop-hook.sh — Tests for stop-hook.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/stop-hook.sh"
STATE_LIB="$SCRIPT_DIR/../scripts/lib/state.sh"
TEST_DIR=$(mktemp -d)
STATE_FILE="$TEST_DIR/.claude/angry-ralph.local.md"
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

source "$STATE_LIB"

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc"
    echo "  expected: '$expected'"
    echo "  actual:   '$actual'"
    ((FAIL++)) || true
  fi
}

assert_contains() {
  local desc="$1" expected_substr="$2" actual="$3"
  if echo "$actual" | grep -q "$expected_substr"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc"
    echo "  expected to contain: '$expected_substr'"
    echo "  actual: '$actual'"
    ((FAIL++)) || true
  fi
}

assert_empty() {
  local desc="$1" actual="$2"
  if [ -z "$actual" ]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc"
    echo "  expected empty stdout, got: '$actual'"
    ((FAIL++)) || true
  fi
}

# Helper: run the hook, capture stdout (the decision payload)
run_hook_stdout() {
  local input="$1"
  echo "$input" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null || true
}

# ---- Test 1: No state file → allow exit (empty stdout) ----
rm -f "$STATE_FILE"
OUTPUT=$(run_hook_stdout '{"session_id":"test","transcript_path":"","cwd":"'"$TEST_DIR"'"}')
assert_empty "no state file → empty stdout (allow)" "$OUTPUT"

# ---- Test 2: State file with phase=execute, no promise → blocks (JSON stdout) ----
mkdir -p "$TEST_DIR/.claude"
create_state_file "$STATE_FILE" "execute" "1" "3" "section-01-auth" "SECTION_COMPLETE" "/tmp/spec.md" "/tmp/planning/" "Build the auth module"

TRANSCRIPT="$TEST_DIR/transcript.jsonl"
echo '{"role":"assistant","content":"I am working on it"}' > "$TRANSCRIPT"

OUTPUT=$(run_hook_stdout '{"session_id":"test","transcript_path":"'"$TRANSCRIPT"'","cwd":"'"$TEST_DIR"'"}')
assert_contains "block outputs decision=block" '"decision"' "$OUTPUT"
assert_contains "block outputs block value" '"block"' "$OUTPUT"
assert_contains "block has reason" '"reason"' "$OUTPUT"
assert_contains "block has systemMessage" '"systemMessage"' "$OUTPUT"
assert_contains "block mentions iteration" "iteration" "$OUTPUT"

# Verify blocking output is valid JSON
VALID_JSON=$(echo "$OUTPUT" | python3 -c "import sys,json; json.loads(sys.stdin.read()); print('true')" 2>/dev/null || echo "false")
assert_eq "blocking output is valid JSON" "true" "$VALID_JSON"

# Verify iteration was incremented in state file
ITER=$(read_state_field "$STATE_FILE" "iteration")
assert_eq "iteration incremented to 2" "2" "$ITER"

# ---- Test 3: State file with phase=plan → allow (empty stdout) ----
rm -f "$STATE_FILE"
create_state_file "$STATE_FILE" "plan" "1" "3" "section-01-auth" "SECTION_COMPLETE" "/tmp/spec.md" "/tmp/planning/" "Plan the auth module"
OUTPUT=$(run_hook_stdout '{"session_id":"test","transcript_path":"","cwd":"'"$TEST_DIR"'"}')
assert_empty "phase=plan → empty stdout (allow)" "$OUTPUT"

# ---- Test 4: State file with active=false → allow (empty stdout) ----
rm -f "$STATE_FILE"
create_state_file "$STATE_FILE" "execute" "1" "3" "section-01-auth" "SECTION_COMPLETE" "/tmp/spec.md" "/tmp/planning/" "Build the auth module"
write_state_field "$STATE_FILE" "active" "false"
OUTPUT=$(run_hook_stdout '{"session_id":"test","transcript_path":"","cwd":"'"$TEST_DIR"'"}')
assert_empty "active=false → empty stdout (allow)" "$OUTPUT"

# ---- Test 5: Promise found in transcript → allow (empty stdout) ----
rm -f "$STATE_FILE"
create_state_file "$STATE_FILE" "execute" "1" "3" "section-01-auth" "SECTION_COMPLETE" "/tmp/spec.md" "/tmp/planning/" "Build the auth module"

TRANSCRIPT2="$TEST_DIR/transcript2.jsonl"
echo '{"role":"user","content":"please build it"}' > "$TRANSCRIPT2"
echo '{"role":"assistant","content":"Done! SECTION_COMPLETE"}' >> "$TRANSCRIPT2"

OUTPUT=$(run_hook_stdout '{"session_id":"test","transcript_path":"'"$TRANSCRIPT2"'","cwd":"'"$TEST_DIR"'"}')
assert_empty "promise found → empty stdout (allow)" "$OUTPUT"

# ---- Test 6: Corrupt transcript → fail-closed (block with error payload) ----
rm -f "$STATE_FILE"
create_state_file "$STATE_FILE" "execute" "1" "3" "section-01-auth" "SECTION_COMPLETE" "/tmp/spec.md" "/tmp/planning/" "Build the auth module"

TRANSCRIPT3="$TEST_DIR/transcript3.jsonl"
echo 'THIS IS NOT VALID JSON' > "$TRANSCRIPT3"

OUTPUT=$(run_hook_stdout '{"session_id":"test","transcript_path":"'"$TRANSCRIPT3"'","cwd":"'"$TEST_DIR"'"}')
assert_contains "corrupt transcript → block decision" '"decision"' "$OUTPUT"
assert_contains "corrupt transcript → block value" '"block"' "$OUTPUT"
assert_contains "corrupt transcript → mentions error" "TOOLING ERROR" "$OUTPUT"

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
