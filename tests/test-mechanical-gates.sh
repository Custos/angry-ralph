#!/usr/bin/env bash
# tests/test-mechanical-gates.sh — Tests for mechanical-gates.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATES="$SCRIPT_DIR/../scripts/lib/mechanical-gates.sh"
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

# ---- Setup: init a git repo in TEST_DIR ----
cd "$TEST_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "test"

# Create initial commit so HEAD exists
echo "init" > init.txt
git add init.txt
git commit -q -m "init"

# ---- Test 1: stub_check passes on clean source ----
mkdir -p src
echo 'def login(user, pw): return True' > src/auth.py
git add src/auth.py
EXIT=0
OUTPUT=$(bash "$GATES" stub_check 2>&1) || EXIT=$?
assert_eq "stub_check passes on clean source" "0" "$EXIT"

# ---- Test 2: stub_check fails on TODO ----
echo '# TODO: implement this' >> src/auth.py
git add src/auth.py
EXIT=0
OUTPUT=$(bash "$GATES" stub_check 2>&1) || EXIT=$?
assert_eq "stub_check fails on TODO" "1" "$EXIT"
assert_contains "stub_check reports TODO" "TODO" "$OUTPUT"

# ---- Test 3: stub_check fails on pass$ (Python stub) ----
git checkout -q -- src/auth.py
echo 'def placeholder():' > src/stub.py
echo '    pass' >> src/stub.py
git add src/stub.py
EXIT=0
OUTPUT=$(bash "$GATES" stub_check 2>&1) || EXIT=$?
assert_eq "stub_check fails on pass$" "1" "$EXIT"
assert_contains "stub_check reports pass" "pass" "$OUTPUT"

# ---- Test 4: stub_check fails on NotImplementedError ----
git checkout -q -- .
echo 'def foo(): raise NotImplementedError' > src/incomplete.py
git add src/incomplete.py
EXIT=0
OUTPUT=$(bash "$GATES" stub_check 2>&1) || EXIT=$?
assert_eq "stub_check fails on NotImplementedError" "1" "$EXIT"

# ---- Test 5: stub_check ignores test files ----
git checkout -q -- .
rm -f src/stub.py src/incomplete.py
# Overwrite auth.py with clean content (index still has TODO from test 2)
echo 'def login(user, pw): return True' > src/auth.py
git add src/auth.py
mkdir -p tests
echo '# TODO: add more tests' > tests/test_auth.py
git add tests/test_auth.py
EXIT=0
OUTPUT=$(bash "$GATES" stub_check 2>&1) || EXIT=$?
assert_eq "stub_check ignores test files" "0" "$EXIT"

# ---- Test 6: spec_compliance passes when all contract tests exist ----
git checkout -q -- .
rm -rf tests src/stub.py src/incomplete.py

# Create a section spec with data contracts
mkdir -p planning/sections
cat > planning/sections/section-01-auth.md << 'SPECEOF'
## Test Data Contracts

test_login_success:
  input:
    function: auth.login
    args: ["alice", "correct"]
  expected_output: true

test_login_rejects_bad_pw:
  input:
    function: auth.login
    args: ["alice", "wrong"]
  expected_error:
    type: AuthError
SPECEOF

# Create test files that contain those function names
mkdir -p tests
cat > tests/test_auth.py << 'TESTEOF'
def test_login_success():
    assert login("alice", "correct") == True

def test_login_rejects_bad_pw():
    with pytest.raises(AuthError):
        login("alice", "wrong")
TESTEOF

EXIT=0
OUTPUT=$(bash "$GATES" spec_compliance "planning/sections/section-01-auth.md" "$TEST_DIR" 2>&1) || EXIT=$?
assert_eq "spec_compliance passes when all tests exist" "0" "$EXIT"

# ---- Test 7: spec_compliance fails when a contract test is missing ----
# Remove one test from the test file
cat > tests/test_auth.py << 'TESTEOF'
def test_login_success():
    assert login("alice", "correct") == True
TESTEOF

EXIT=0
OUTPUT=$(bash "$GATES" spec_compliance "planning/sections/section-01-auth.md" "$TEST_DIR" 2>&1) || EXIT=$?
assert_eq "spec_compliance fails on missing test" "1" "$EXIT"
assert_contains "spec_compliance reports missing test" "test_login_rejects_bad_pw" "$OUTPUT"

# ---- Test 8: spec_compliance passes with no contracts in spec ----
echo "# Just a description, no contracts" > planning/sections/section-02-empty.md
EXIT=0
OUTPUT=$(bash "$GATES" spec_compliance "planning/sections/section-02-empty.md" "$TEST_DIR" 2>&1) || EXIT=$?
assert_eq "spec_compliance passes with no contracts" "0" "$EXIT"

# ---- Test 9: test_verify fails on non-zero exit ----
EXIT=0
OUTPUT=$(bash "$GATES" test_verify "exit 1" 2>&1) || EXIT=$?
assert_eq "test_verify fails on non-zero exit" "1" "$EXIT"
assert_contains "test_verify reports exit code" "exited with code" "$OUTPUT"

# ---- Test 10: test_verify passes on pytest-like output ----
EXIT=0
OUTPUT=$(bash "$GATES" test_verify "echo '3 passed in 0.5s'" 2>&1) || EXIT=$?
assert_eq "test_verify passes on pytest output" "0" "$EXIT"

# ---- Test 11: test_verify fails on zero exit but no tests ran ----
EXIT=0
OUTPUT=$(bash "$GATES" test_verify "echo 'nothing happened'" 2>&1) || EXIT=$?
assert_eq "test_verify fails when no tests ran" "1" "$EXIT"
assert_contains "test_verify reports no tests" "no tests appear" "$OUTPUT"

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
