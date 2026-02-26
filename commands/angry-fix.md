---
name: angry-fix
description: Surgical TDD strike — write failing test, fix, green, commit
---

# /angry-fix Command

Surgical post-pipeline TDD remediation. No planning. No review. Just fix and ship.

## 1. Argument Parsing

- **`@file` references** (optional) -- File paths, error logs, test output as context.
- **Prompt text** (required) -- Description of what to fix.

Example: `/angry-fix @error.log "Fix the auth middleware timeout"`

If no prompt:

```
Usage: /angry-fix [context] [prompt]
Example: /angry-fix @error.log "Fix the auth middleware timeout"
```

## 2. Procedure

1. Read all provided `@file` context.
2. Write a failing test that captures the expected correct behavior.
3. Run the test suite — confirm the new test fails (red phase).
4. Implement the fix — minimum code to make the test pass.
5. Run the full test suite — confirm ALL tests pass (green phase).
6. If tests fail, iterate: debug, fix, re-run.
7. When all tests pass, create an atomic commit: `fix: <description from prompt>`.

## 3. Constraints

- No planning artifacts created or modified.
- No review phase.
- No `.ralph-state/` state modified.
- Standalone surgical operation.
- Follow `references/tdd-protocol.md` for TDD rules.
