#!/usr/bin/env bash
# tests/test-state.sh — Tests for state.sh library
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_LIB="$SCRIPT_DIR/../scripts/lib/state.sh"
TEST_DIR=$(mktemp -d)
STATE_FILE="$TEST_DIR/.ralph-state/loop.md"
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

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

# Source the library
source "$STATE_LIB"

# Test 1: create_state_file creates the file with correct frontmatter
mkdir -p "$TEST_DIR/.ralph-state"
create_state_file "$STATE_FILE" "execute" "1" "3" "section-01-auth" "SECTION_COMPLETE" "/tmp/spec.md" "/tmp/planning/" "Build the auth module"

assert_eq "state file exists" "true" "$([ -f "$STATE_FILE" ] && echo true || echo false)"
assert_eq "active field" "true" "$(read_state_field "$STATE_FILE" "active")"
assert_eq "phase field" "execute" "$(read_state_field "$STATE_FILE" "phase")"
assert_eq "iteration field" "1" "$(read_state_field "$STATE_FILE" "iteration")"
assert_eq "max_iterations field" "3" "$(read_state_field "$STATE_FILE" "max_iterations")"
assert_eq "current_section field" "section-01-auth" "$(read_state_field "$STATE_FILE" "current_section")"
assert_eq "completion_promise field" "SECTION_COMPLETE" "$(read_state_field "$STATE_FILE" "completion_promise")"

# Test 1b: review_iteration field defaults to 0
assert_eq "review_iteration defaults to 0" "0" "$(read_state_field "$STATE_FILE" "review_iteration")"

# Test 2: write_state_field updates a field
write_state_field "$STATE_FILE" "iteration" "2"
assert_eq "updated iteration" "2" "$(read_state_field "$STATE_FILE" "iteration")"

write_state_field "$STATE_FILE" "phase" "final_review"
assert_eq "updated phase" "final_review" "$(read_state_field "$STATE_FILE" "phase")"

# Test 2b: write_state_field can update review_iteration
write_state_field "$STATE_FILE" "review_iteration" "1"
assert_eq "updated review_iteration" "1" "$(read_state_field "$STATE_FILE" "review_iteration")"

# Test 2c: write_state_field can swap completion_promise to SECTION_REVIEW_FIX_COMPLETE
write_state_field "$STATE_FILE" "completion_promise" "SECTION_REVIEW_FIX_COMPLETE"
assert_eq "swapped promise to fix" "SECTION_REVIEW_FIX_COMPLETE" "$(read_state_field "$STATE_FILE" "completion_promise")"

# Test 2d: write_state_field can restore completion_promise to SECTION_COMPLETE
write_state_field "$STATE_FILE" "completion_promise" "SECTION_COMPLETE"
assert_eq "restored promise to original" "SECTION_COMPLETE" "$(read_state_field "$STATE_FILE" "completion_promise")"

# Test 3: read prompt body (after frontmatter)
BODY=$(read_state_body "$STATE_FILE")
assert_eq "prompt body" "Build the auth module" "$BODY"

# Test 4: write_state_field does NOT corrupt prompt body containing field-like text
rm -f "$STATE_FILE"
create_state_file "$STATE_FILE" "execute" "1" "3" "section-01-auth" "SECTION_COMPLETE" "/tmp/spec.md" "/tmp/planning/" "phase: this line looks like a field but is in the body"
write_state_field "$STATE_FILE" "phase" "review"
assert_eq "frontmatter phase updated" "review" "$(read_state_field "$STATE_FILE" "phase")"
BODY_AFTER=$(read_state_body "$STATE_FILE")
assert_eq "body preserved after write" "phase: this line looks like a field but is in the body" "$BODY_AFTER"

# Test 5: remove_state_file
remove_state_file "$STATE_FILE"
assert_eq "file removed" "false" "$([ -f "$STATE_FILE" ] && echo true || echo false)"

# Test 6: read_state_field on missing file returns empty
RESULT=$(read_state_field "$STATE_FILE" "active")
assert_eq "missing file returns empty" "" "$RESULT"

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
