# TDD Protocol — Red-Green Cycle for Phase 5 (EXECUTE)

This protocol governs test-driven development during the Ralph Loop execution phase.
Every section implementation MUST follow the red-green cycle below.

## Red Phase — Write Failing Tests First

1. Read the section spec to understand acceptance criteria.
2. Write test cases that verify the expected behavior described in the spec.
3. Run the test suite and **confirm the tests fail**.
4. If any test passes before implementation exists, the test is wrong — rewrite it
   to actually exercise the unimplemented behavior.

Never skip the red phase. A test that has never been seen to fail provides no confidence.

## Green Phase — Write Minimal Implementation

1. Write the minimum code needed to make all failing tests pass.
2. Do not over-engineer or add features not required by the section spec.
3. Run the test suite and **confirm all tests pass**.
4. If tests fail, debug and fix the implementation — not the tests.
5. Repeat until every assertion is green.

## Test Command Detection

Detect the project's test runner before executing tests. Common runners:

- **Python:** `pytest`, `python -m pytest`, `python -m unittest`
- **Node.js:** `npm test`, `npx jest`, `npx vitest`
- **Rust:** `cargo test`
- **Go:** `go test ./...`
- **Ruby:** `bundle exec rspec`

If no test runner can be detected, ask the user via `AskUserQuestion`.

## Definition of "Tests Pass"

All four conditions must hold:

- The test runner exits with code 0.
- Every assertion passes — no skipped or ignored tests count as passing.
- No compilation errors occur.
- No runtime errors occur during test execution.

## Completion Promise Rules

The completion promise (`SECTION_COMPLETE`) may **only** be output when:

1. ALL tests for the current section pass (exit code 0).
2. The implementation satisfies the section spec's acceptance criteria.

Violations — never do any of the following:

- Output the completion promise if any test fails.
- Output the completion promise to escape the loop early.
- Output the completion promise before running the test suite at least once.

The stop hook gates session exit on this promise.

## Handling Test Failures

When tests fail after writing implementation code:

1. Read the full test output carefully.
2. Identify the root cause — assume the implementation is at fault, not the test.
3. Fix the implementation.
4. Re-run the test suite.
5. Repeat until all tests are green.

Do NOT modify tests to force them to pass. The only valid reason to change a test is
when it contains a clear, demonstrable bug (e.g., wrong expected value from a misread spec).

## Handling Flaky Tests

If a test passes on some runs and fails on others:

1. Re-run the test suite 2 additional times.
2. If it **consistently fails**, treat as a real failure and fix the implementation.
3. If it **consistently passes** after the initial flake, note the flakiness and proceed.
4. If still inconsistent, investigate the root cause (race condition, non-deterministic
   ordering, external dependency) before proceeding. Do not suppress or skip it.
