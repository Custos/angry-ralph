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

assert_output_contains() {
  local desc="$1" expected_substr="$2"
  shift 2
  local output
  output=$("$@" 2>&1) || true
  if echo "$output" | grep -qi "$expected_substr"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (output missing '$expected_substr')"
    echo "  output: $output"
    ((FAIL++)) || true
  fi
}

# Test 1: Script runs and succeeds in normal env (gemini, codex, git all present)
assert_exit "succeeds with all tools present" 0 bash "$VALIDATE"

# Test 2: Output confirms tools found
assert_output_contains "reports gemini found" "gemini" bash "$VALIDATE"
assert_output_contains "reports codex found" "codex" bash "$VALIDATE"
assert_output_contains "reports git found" "git" bash "$VALIDATE"
assert_output_contains "reports python3 found" "python3" bash "$VALIDATE"

# Test 3: Script fails with modified PATH missing gemini
assert_exit "fails without gemini" 1 env PATH="/usr/bin:/bin" bash "$VALIDATE"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
