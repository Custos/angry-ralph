#!/usr/bin/env bash
# tests/test-pipeline.sh — Tests for pipeline.sh (.ralph-state/ management)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/../scripts/lib/pipeline.sh"
TEST_DIR=$(mktemp -d)
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

# ---- Test 1: pipeline_init creates directory structure ----
bash "$PIPELINE" init "$TEST_DIR"
assert_eq ".ralph-state/ created" "true" "$([ -d "$TEST_DIR/.ralph-state/phases" ] && echo true || echo false)"

# ---- Test 1b: pipeline_init ensures .gitignore entries ----
assert_eq ".gitignore exists" "true" "$([ -f "$TEST_DIR/.gitignore" ] && echo true || echo false)"
assert_eq ".gitignore has .ralph-state/" "true" "$(grep -qxF '.ralph-state/' "$TEST_DIR/.gitignore" && echo true || echo false)"
assert_eq ".gitignore has .planning/" "true" "$(grep -qxF '.planning/' "$TEST_DIR/.gitignore" && echo true || echo false)"

# ---- Test 1c: ensure_gitignore is idempotent ----
bash "$PIPELINE" init "$TEST_DIR"
COUNT=$(grep -cxF '.ralph-state/' "$TEST_DIR/.gitignore")
assert_eq ".gitignore no duplicate .ralph-state/" "1" "$COUNT"

# ---- Test 2: pipeline_create writes valid JSON ----
bash "$PIPELINE" create "$TEST_DIR" "/tmp/spec.md" "interactive" "3" "2" "20" "adversarial" "gemini,codex"
assert_eq "pipeline.json exists" "true" "$([ -f "$TEST_DIR/.ralph-state/pipeline.json" ] && echo true || echo false)"

VALID=$(python3 -m json.tool "$TEST_DIR/.ralph-state/pipeline.json" > /dev/null 2>&1 && echo true || echo false)
assert_eq "pipeline.json is valid JSON" "true" "$VALID"

# ---- Test 3: pipeline_read reads fields ----
MODE=$(bash "$PIPELINE" read "$TEST_DIR" "mode")
assert_eq "read mode" "interactive" "$MODE"

TIER=$(bash "$PIPELINE" read "$TEST_DIR" "review_tier")
assert_eq "read review_tier" "adversarial" "$TIER"

CAP=$(bash "$PIPELINE" read "$TEST_DIR" "max_tdd_iterations")
assert_eq "read max_tdd_iterations" "20" "$CAP"

PHASE=$(bash "$PIPELINE" read "$TEST_DIR" "current_phase")
assert_eq "read current_phase" "decompose" "$PHASE"

REVIEWERS=$(bash "$PIPELINE" read "$TEST_DIR" "available_reviewers")
assert_eq "read available_reviewers" "gemini,codex" "$REVIEWERS"

# ---- Test 4: pipeline_write updates a field ----
bash "$PIPELINE" write "$TEST_DIR" "current_phase" "plan"
PHASE=$(bash "$PIPELINE" read "$TEST_DIR" "current_phase")
assert_eq "write updates phase" "plan" "$PHASE"

# ---- Test 5: pipeline_append adds to list ----
bash "$PIPELINE" append "$TEST_DIR" "completed_phases" "decompose"
COMPLETED=$(bash "$PIPELINE" read "$TEST_DIR" "completed_phases")
assert_eq "append adds to list" "decompose" "$COMPLETED"

bash "$PIPELINE" append "$TEST_DIR" "completed_phases" "plan"
COMPLETED=$(bash "$PIPELINE" read "$TEST_DIR" "completed_phases")
assert_eq "append adds second item" "decompose,plan" "$COMPLETED"

# ---- Test 6: pipeline_append is idempotent ----
bash "$PIPELINE" append "$TEST_DIR" "completed_phases" "plan"
COMPLETED=$(bash "$PIPELINE" read "$TEST_DIR" "completed_phases")
assert_eq "append is idempotent" "decompose,plan" "$COMPLETED"

# ---- Test 6b: remove_from_list removes a value ----
bash "$PIPELINE" remove_from_list "$TEST_DIR" "completed_phases" "plan"
COMPLETED=$(bash "$PIPELINE" read "$TEST_DIR" "completed_phases")
assert_eq "remove_from_list removes item" "decompose" "$COMPLETED"

# ---- Test 6c: remove_from_list is safe for missing values ----
bash "$PIPELINE" remove_from_list "$TEST_DIR" "completed_phases" "nonexistent"
COMPLETED=$(bash "$PIPELINE" read "$TEST_DIR" "completed_phases")
assert_eq "remove_from_list ignores missing" "decompose" "$COMPLETED"

# Re-add plan for subsequent tests
bash "$PIPELINE" append "$TEST_DIR" "completed_phases" "plan"

# ---- Test 7: check_done returns false when no marker ----
bash "$PIPELINE" check_done "$TEST_DIR" "architect" && DONE="true" || DONE="false"
assert_eq "check_done false when missing" "false" "$DONE"

# ---- Test 8: write_done + check_done ----
bash "$PIPELINE" write_done "$TEST_DIR" "architect"
bash "$PIPELINE" check_done "$TEST_DIR" "architect" && DONE="true" || DONE="false"
assert_eq "check_done true after write" "true" "$DONE"
assert_eq "done marker is a file" "true" "$([ -f "$TEST_DIR/.ralph-state/phases/architect.done" ] && echo true || echo false)"

# ---- Test 9: remove_done deletes marker ----
bash "$PIPELINE" remove_done "$TEST_DIR" "architect"
bash "$PIPELINE" check_done "$TEST_DIR" "architect" && DONE="true" || DONE="false"
assert_eq "check_done false after remove" "false" "$DONE"

# ---- Test 10: migrate_legacy moves state file ----
LEGACY_DIR=$(mktemp -d)
mkdir -p "$LEGACY_DIR/.claude"
echo "---
active: true
phase: execute
---
prompt body" > "$LEGACY_DIR/.claude/angry-ralph.local.md"

mkdir -p "$LEGACY_DIR/planning"
echo '{"current_phase": "execute"}' > "$LEGACY_DIR/planning/config.json"

RESULT=$(bash "$PIPELINE" migrate "$LEGACY_DIR")
assert_eq "migrate returns migrated" "migrated" "$RESULT"
assert_eq "loop.md exists after migrate" "true" "$([ -f "$LEGACY_DIR/.ralph-state/loop.md" ] && echo true || echo false)"
assert_eq "pipeline.json exists after migrate" "true" "$([ -f "$LEGACY_DIR/.ralph-state/pipeline.json" ] && echo true || echo false)"
assert_eq "legacy state file removed" "false" "$([ -f "$LEGACY_DIR/.claude/angry-ralph.local.md" ] && echo true || echo false)"
rm -rf "$LEGACY_DIR"

# ---- Test 11: migrate_legacy is idempotent ----
NO_LEGACY_DIR=$(mktemp -d)
mkdir -p "$NO_LEGACY_DIR/.ralph-state"
RESULT=$(bash "$PIPELINE" migrate "$NO_LEGACY_DIR")
assert_eq "migrate returns none when nothing to do" "none" "$RESULT"
rm -rf "$NO_LEGACY_DIR"

# ---- Test 12: pipeline_create with auto mode ----
AUTO_DIR=$(mktemp -d)
bash "$PIPELINE" create "$AUTO_DIR" "/tmp/spec.md" "auto" "5" "3" "30" "partial" "codex"
MODE=$(bash "$PIPELINE" read "$AUTO_DIR" "mode")
assert_eq "auto mode stored" "auto" "$MODE"
CAP=$(bash "$PIPELINE" read "$AUTO_DIR" "max_review_iterations")
assert_eq "custom max_review" "5" "$CAP"
rm -rf "$AUTO_DIR"

# ---- Test 13: migrate planning/ → .planning/ ----
PLAN_MIG_DIR=$(mktemp -d)
mkdir -p "$PLAN_MIG_DIR/planning/sections"
echo "plan content" > "$PLAN_MIG_DIR/planning/angry-ralph-plan.md"
echo "section" > "$PLAN_MIG_DIR/planning/sections/section-01.md"
mkdir -p "$PLAN_MIG_DIR/.ralph-state"
RESULT=$(bash "$PIPELINE" migrate "$PLAN_MIG_DIR")
assert_eq "migrate planning/ returns migrated" "migrated" "$RESULT"
assert_eq ".planning/ exists after migrate" "true" "$([ -d "$PLAN_MIG_DIR/.planning" ] && echo true || echo false)"
assert_eq "planning/ removed after migrate" "false" "$([ -d "$PLAN_MIG_DIR/planning" ] && echo true || echo false)"
assert_eq ".planning/sections preserved" "true" "$([ -f "$PLAN_MIG_DIR/.planning/sections/section-01.md" ] && echo true || echo false)"
rm -rf "$PLAN_MIG_DIR"

# ---- Test 13b: migrate planning/ is idempotent when .planning/ exists ----
PLAN_BOTH_DIR=$(mktemp -d)
mkdir -p "$PLAN_BOTH_DIR/planning"
mkdir -p "$PLAN_BOTH_DIR/.planning"
mkdir -p "$PLAN_BOTH_DIR/.ralph-state"
RESULT=$(bash "$PIPELINE" migrate "$PLAN_BOTH_DIR")
assert_eq "migrate skips when .planning/ exists" "none" "$RESULT"
rm -rf "$PLAN_BOTH_DIR"

# ---- Test 14: pipeline_read on missing file returns empty ----
EMPTY=$(bash "$PIPELINE" read "/nonexistent" "mode")
assert_eq "read on missing returns empty" "" "$EMPTY"

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
