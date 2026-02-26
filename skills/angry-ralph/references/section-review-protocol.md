# Section Review Protocol: Per-Section Code Review Gate

Reference protocol for the inline code review gate that runs after TDD passes and before the atomic commit during Phase 5 (EXECUTE). The main session performs this review directly — no subagent or external CLI is used.

---

## When to Trigger

The section review gate triggers after the SubagentStop hook allows exit (completion promise found in transcript) and before the atomic commit. The sequence is:

1. TDD subagent outputs `SECTION_COMPLETE`
2. SubagentStop hook verifies promise → allows exit
3. **Section review gate runs** (this protocol)
4. Atomic commit (if review passes)

---

## How to Execute

### 1. Identify Changed Files

Run `git diff --name-only HEAD` to list all files changed since the last commit. These are the files the TDD subagent just created or modified for the current section.

### 2. Read Inputs

Read the following:
- Each changed file (full content)
- The current section spec from `planning/sections/section-NN-name.md`
- The implementation plan from `planning/angry-ralph-plan.md` (the relevant section)

### 3. Evaluate the Review Checklist

Evaluate each changed file against the five review dimensions below. Tag every finding with a severity level.

---

## Review Checklist

### A. Plan-vs-Code Fidelity

- Does the implementation match the section spec's scope?
- Are all acceptance criteria from the section spec addressed?
- Are there files or components created that the spec did not call for?
- Are there spec requirements that have no corresponding implementation?

### B. Implementation Substance

- No stub implementations (functions that return hardcoded values, empty method bodies, `pass`/`TODO`/`FIXME` placeholders)
- No placeholder logic that would pass shallow tests but fail on real input
- Every function/method has a meaningful implementation body

### C. Algorithm/Logic Correctness

- Do algorithms match the plan's specifications (data structures, complexity, approach)?
- Is error handling present at system boundaries (user input, external APIs, file I/O)?
- Are edge cases handled (empty inputs, null/undefined, boundary values)?
- Are there off-by-one errors, incorrect comparisons, or logic inversions?

### D. Test Quality

- Do tests make meaningful assertions (not just `assert True` or checking existence)?
- Do tests cover edge cases described in the section spec?
- Would the tests fail if the implementation were replaced with a stub?
- Are test inputs realistic and varied?

### E. Integration Readiness

- Do exported functions/classes/modules match what downstream sections expect?
- Are there hardcoded configuration values that should be parameterized?
- Are import paths and module names consistent with the project structure?

---

## Severity Tags

- **`[CRITICAL]`** — Blocks the commit. Must be fixed before proceeding. Examples: stub implementation, missing spec requirement, algorithm that doesn't match plan, tests that would pass on empty implementation.
- **`[WARNING]`** — Evaluate case-by-case. Fix if it represents a real risk to correctness or reliability. Document rationale if left unaddressed. Examples: missing edge case handling, weak test assertion.
- **`[INFO]`** — Note for awareness. Does not block. Examples: style inconsistency, minor naming improvement.

---

## Triage and Fix Cycle

### No Issues Found

If the review finds zero CRITICAL and zero WARNING findings, proceed directly to the atomic commit.

### Issues Found

When CRITICAL or actionable WARNING findings are identified:

1. **Log the review** — Write findings to `planning/reviews/sections/<section-name>/review-N.md` where N is the current `review_iteration` + 1.

2. **Swap the completion promise** — Update the state file:
   ```
   write_state_field <state_file> completion_promise SECTION_REVIEW_FIX_COMPLETE
   write_state_field <state_file> review_iteration <N>
   ```

3. **Dispatch a fix subagent** — Use the Task tool to dispatch a fresh subagent with:
   - The review findings (full text)
   - The section spec
   - The list of files to fix
   - Instructions to fix all CRITICAL findings and actionable WARNINGs
   - Instructions to output `SECTION_REVIEW_FIX_COMPLETE` when all fixes are applied and tests pass
   - The test runner command

4. **SubagentStop hook gates** — The hook reads `completion_promise` dynamically from the state file, so the swapped promise `SECTION_REVIEW_FIX_COMPLETE` is automatically enforced. No hook changes needed.

5. **Re-review** — After the fix subagent exits, perform the review again from step 1. Read the newly changed files and re-evaluate.

6. **Restore promise** — When the review passes (or iteration cap is reached), restore the original promise:
   ```
   write_state_field <state_file> completion_promise SECTION_COMPLETE
   ```

### Iteration Cap

The review-fix cycle runs a maximum of `max_section_review_iterations` times (default: 2, configurable via `--max-section-review-iterations`). Read this value from `planning/config.json`.

When the cap is reached with findings still open:
- Log all remaining findings to `planning/reviews/sections/<section-name>/review-N.md`
- Restore `completion_promise` to `SECTION_COMPLETE`
- Proceed to the atomic commit
- Do NOT prompt the user — log and move on

---

## Output Storage

Store review outputs at:

```
planning/reviews/sections/<section-name>/review-1.md
planning/reviews/sections/<section-name>/review-2.md
```

Each review file should contain:
- Timestamp
- Section name
- Review iteration number
- List of findings with severity tags
- Disposition (fixed / deferred / noted)

---

## Hard Rules

1. **The reviewer does NOT modify files.** The main session reads and evaluates only. All fixes are made by a dispatched fix subagent.
2. **No user interaction.** The review gate is fully autonomous. It finds issues, dispatches fixes, re-checks, and proceeds.
3. **Fail forward.** If the iteration cap is reached, log remaining findings and proceed. Never block the pipeline indefinitely.
4. **Promise swap is transparent.** The SubagentStop hook reads `completion_promise` dynamically — no hook modifications needed.
