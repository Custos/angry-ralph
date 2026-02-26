#!/usr/bin/env bash
# scripts/lib/mechanical-gates.sh — Mechanical gates for Phase 5 TDD loop
# Dumb bash checks that run before the AI review. No LLM judgment.
# Exit 0 = all gates pass. Exit 1 = gate failed (output describes failure).
set -euo pipefail

# Gate 1: Scan changed source files for stub/laziness markers.
# Excludes test files. Prints matching lines on failure.
stub_check() {
  local changed
  changed=$(git diff --name-only HEAD 2>/dev/null || true)
  if [ -z "$changed" ]; then
    return 0
  fi

  # Filter out test files
  local src_files
  src_files=$(echo "$changed" | grep -v -E '(^tests?/|__test__|\.test\.|_test\.|test_|\.spec\.)' || true)
  if [ -z "$src_files" ]; then
    return 0
  fi

  local stubs
  stubs=$(echo "$src_files" | xargs grep -riEn 'todo|fixme|xxx|hack|notimplemented|raise NotImplementedError|pass$' 2>/dev/null || true)
  if [ -n "$stubs" ]; then
    echo "MECHANICAL GATE FAILED: Stub/laziness markers in source files:"
    echo "$stubs"
    return 1
  fi
  return 0
}

# Gate 2: Re-run test suite, verify exit 0 + at least one test ran.
# $1 = test runner command (e.g. "pytest", "npm test")
test_verify() {
  local runner="$1"
  local output
  local exit_code=0

  output=$(eval "$runner" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "MECHANICAL GATE FAILED: Test runner exited with code $exit_code"
    echo "$output"
    return 1
  fi

  # Check at least one test ran. Match common frameworks:
  # pytest: "N passed", jest/vitest: "Tests:.*passed", go: "^ok", cargo: "test result: ok"
  local ran="false"
  if echo "$output" | grep -qE '[0-9]+ passed'; then ran="true"; fi
  if echo "$output" | grep -qE 'Tests:.*[0-9]+ passed'; then ran="true"; fi
  if echo "$output" | grep -qE '^ok\s'; then ran="true"; fi
  if echo "$output" | grep -qE 'test result: ok'; then ran="true"; fi
  # Fallback: any line with "pass" and a number
  if echo "$output" | grep -qiE '[0-9]+\s*(tests?\s+)?pass'; then ran="true"; fi

  if [ "$ran" = "false" ]; then
    echo "MECHANICAL GATE FAILED: Test runner exited 0 but no tests appear to have run."
    echo "Output:"
    echo "$output" | tail -20
    return 1
  fi

  return 0
}

# Gate 3: Verify every test function name from section spec data contracts
# exists in the project's test files.
# $1 = path to section spec markdown
# $2 = project directory (optional, defaults to cwd)
spec_compliance() {
  local spec_file="$1"
  local project_dir="${2:-.}"

  if [ ! -f "$spec_file" ]; then
    echo "MECHANICAL GATE FAILED: Section spec not found: $spec_file"
    return 1
  fi

  # Extract test function names from YAML data contracts in the spec.
  # Matches lines like "test_something:" at the start (indented or not) that look like
  # test function names (start with test_ or test).
  local test_names
  test_names=$(grep -oE '^\s*(test_[a-zA-Z0-9_]+):' "$spec_file" | sed 's/[: ]//g' || true)

  if [ -z "$test_names" ]; then
    # No data contracts found — nothing to check
    return 0
  fi

  # Find all test files in the project
  local test_files
  test_files=$(find "$project_dir" -type f \( -name 'test_*.py' -o -name '*_test.py' -o -name '*.test.*' -o -name '*.spec.*' -o -path '*/tests/*' -o -path '*/test/*' \) 2>/dev/null | grep -v node_modules | grep -v __pycache__ || true)

  if [ -z "$test_files" ]; then
    echo "MECHANICAL GATE FAILED: No test files found in $project_dir"
    return 1
  fi

  local missing=""
  local count=0
  local found=0

  while IFS= read -r name; do
    ((count++)) || true
    if echo "$test_files" | xargs grep -rl "$name" >/dev/null 2>&1; then
      ((found++)) || true
    else
      missing="${missing}  - ${name}\n"
    fi
  done <<< "$test_names"

  if [ -n "$missing" ]; then
    echo "MECHANICAL GATE FAILED: $((count - found))/$count spec'd test functions missing from test files:"
    echo -e "$missing"
    return 1
  fi

  return 0
}

# Run all three gates in sequence. Fails fast on first failure.
# $1 = test runner command
# $2 = section spec path
# $3 = project directory (optional)
run_all() {
  local runner="$1"
  local spec="$2"
  local project_dir="${3:-.}"

  echo "=== Mechanical Gate 1: Stub Check ==="
  stub_check
  echo "PASS"

  echo "=== Mechanical Gate 2: Test Verification ==="
  test_verify "$runner"
  echo "PASS"

  echo "=== Mechanical Gate 3: Spec Contract Compliance ==="
  spec_compliance "$spec" "$project_dir"
  echo "PASS"

  echo "=== All mechanical gates passed ==="
}

# Dispatch: call the function named by $1, pass remaining args.
CMD="${1:-}"
shift || true
case "$CMD" in
  stub_check)      stub_check "$@" ;;
  test_verify)     test_verify "$@" ;;
  spec_compliance) spec_compliance "$@" ;;
  run_all)         run_all "$@" ;;
  *)
    echo "Usage: mechanical-gates.sh <stub_check|test_verify|spec_compliance|run_all> [args...]"
    exit 1
    ;;
esac
