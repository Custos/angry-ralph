#!/usr/bin/env bash
# tests/test-validate-env.sh — Tests for validate-env.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATE="$SCRIPT_DIR/../scripts/checks/validate-env.sh"
PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected_exit="$2"
  shift 2
  local actual_exit=0
  "$@" > /dev/null 2>&1 || actual_exit=$?
  if [[ "$expected_exit" == "$actual_exit" ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    ((FAIL++)) || true
  fi
}

assert_stderr_contains() {
  local desc="$1" expected_substr="$2"
  shift 2
  local output
  output=$("$@" 2>&1 >/dev/null) || true
  if echo "$output" | grep -qi "$expected_substr"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (stderr missing '$expected_substr')"
    echo "  output: $output"
    ((FAIL++)) || true
  fi
}

assert_stdout_contains() {
  local desc="$1" expected_substr="$2"
  shift 2
  local output
  output=$("$@" 2>/dev/null) || true
  if echo "$output" | grep -q "$expected_substr"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (stdout missing '$expected_substr')"
    echo "  output: $output"
    ((FAIL++)) || true
  fi
}

# Test 1: Script succeeds with all tools present (exit 0)
assert_exit "succeeds with all tools present" 0 bash "$VALIDATE"

# Test 2: Stderr reports required tools found
assert_stderr_contains "reports git found" "git" bash "$VALIDATE"
assert_stderr_contains "reports python3 found" "python3" bash "$VALIDATE"
assert_stderr_contains "reports claude found" "claude" bash "$VALIDATE"

# Test 3: Stderr reports optional tools found (when present)
assert_stderr_contains "reports gemini found" "gemini" bash "$VALIDATE"
assert_stderr_contains "reports codex found" "codex" bash "$VALIDATE"

# Test 4: JSON output contains review_tier
assert_stdout_contains "JSON has review_tier" "review_tier" bash "$VALIDATE"
assert_stdout_contains "JSON has available_reviewers" "available_reviewers" bash "$VALIDATE"

# Test 5: JSON output is valid JSON
JSON_OUTPUT=$(bash "$VALIDATE" 2>/dev/null)
VALID_JSON=$(echo "$JSON_OUTPUT" | python3 -c "import sys,json; json.loads(sys.stdin.read()); print('true')" 2>/dev/null || echo "false")
if [ "$VALID_JSON" = "true" ]; then
  echo "PASS: stdout is valid JSON"
  ((PASS++)) || true
else
  echo "FAIL: stdout is not valid JSON"
  echo "  output: $JSON_OUTPUT"
  ((FAIL++)) || true
fi

# Test 6: Still hard-fails when required tool (git/python3/claude) is missing
assert_exit "fails without claude" 1 env PATH="/usr/bin:/bin" bash "$VALIDATE"

# Test 7: Does NOT fail when only gemini/codex are missing (soft check)
assert_exit "succeeds without gemini+codex" 0 env PATH="/usr/bin:/bin:/Users/jfeinblum/.local/bin" bash "$VALIDATE"

# Test 8: Self-reflection tier when no optional tools
SR_OUTPUT=$(env PATH="/usr/bin:/bin:/Users/jfeinblum/.local/bin" bash "$VALIDATE" 2>/dev/null) || true
SR_TIER=$(echo "$SR_OUTPUT" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['review_tier'])" 2>/dev/null || echo "")
if [ "$SR_TIER" = "self-reflection" ]; then
  echo "PASS: self-reflection tier when no optional tools"
  ((PASS++)) || true
else
  echo "FAIL: expected self-reflection tier, got '$SR_TIER'"
  ((FAIL++)) || true
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
