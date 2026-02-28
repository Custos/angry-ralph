# Diagnosis Protocol — Adversarial Bug Investigation

This reference governs the `/angry-diagnose` pipeline. It defines how to build a case file,
generate competing hypotheses via external reviewers, and systematically eliminate hypotheses
via diagnostic tests before implementing a fix.

## Phase 1: INVESTIGATE — Build the Case File

### Context Gathering

1. Read all provided `@file` context (error logs, stack traces, suspect source files).
2. If suspect source files are provided: read them, then trace their imports and callers
   (1-2 levels deep) to build a dependency map of the affected area.
3. If only a problem description is provided (no `@file` context): search the codebase for
   relevant keywords, error messages, and related modules. Cast a wide net.
4. For all identified relevant files, check recent git history:
   ```bash
   git log --oneline -10 -- <file>
   ```
5. Identify the test files associated with the affected source files.

### Interview (Interactive Mode Only)

Ask 1-2 clarifying questions via `AskUserQuestion`:
- When does the problem occur? Is it reproducible?
- Were there any recent changes to this area of the code?
- What is the expected vs actual behavior?

In `--auto` mode: skip the interview entirely. Work with the provided context.

### Case File Output

Write `.planning/diagnosis/case-file.md` with this structure:

```
# Case File: <problem summary>

## Symptom
<problem description from user>

## Context Files Provided
- <file1> — <brief description of contents>
- <file2> — <brief description of contents>

## Relevant Source Files Identified
- <source-file> — <why relevant>
  Recent changes: <git log summary>

## Relevant Test Files
- <test-file> — <what it tests>

## Interview Notes
<answers to clarifying questions, or "Skipped (--auto mode)">

## Initial Observations
<anything notable from reading the code — patterns, anti-patterns, suspicious logic>
```

### State Update

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . current_phase diagnose
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh append . completed_phases investigate
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write_done . investigate
```

## Phase 2: DIAGNOSE — Differential Diagnosis

### Hypothesis Generation via External Reviewers

Spawn the `external-reviewer` subagent via the Task tool with `subagent_type` set to
`external-reviewer`. Pass a **diagnosis-specific prompt** — not the standard plan/code
review prompt.

The subagent prompt must include:
- The full case file content
- The content of all relevant source files (read and inline them)
- The problem description
- Instructions to generate hypotheses, NOT review findings

#### Diagnosis Prompt Template

Instruct each reviewer (gemini/codex/claude-fallback) with this methodology:

```
You are a senior engineer performing DIFFERENTIAL DIAGNOSIS on a software bug.
Do NOT propose a fix. Your job is to generate COMPETING HYPOTHESES for the root cause.

SYMPTOM: <problem description>

CONTEXT:
<case file content>
<relevant source file contents>

METHODOLOGY:
1. Generate at least 3 competing hypotheses for the root cause.
2. At least 1 hypothesis must be "non-obvious" — consider: race conditions, configuration
   drift, upstream dependency issues, data corruption, encoding problems, caching staleness,
   environment differences, silent failures in error handling paths.
3. For each hypothesis, provide:
   - DESCRIPTION: What the root cause would be
   - SUSPECTED LOCATION: File + function/line range
   - EVIDENCE FOR: Why this could be the cause
   - EVIDENCE AGAINST: Why this might NOT be the cause
   - DIAGNOSTIC TEST: A specific test that would PROVE or DISPROVE this hypothesis
     (describe what the test should do and what result confirms/eliminates the hypothesis)
4. Rank hypotheses by likelihood.

Output format:
## Hypotheses

### Hypothesis 1: <title>
- **Description:** ...
- **Suspected location:** ...
- **Evidence for:** ...
- **Evidence against:** ...
- **Diagnostic test:** ...
- **Confidence:** HIGH/MEDIUM/LOW

### Hypothesis 2: <title>
...

## Summary
<overall assessment of most likely root cause and investigation strategy>
```

### Merge and Rank

After receiving hypotheses from all reviewers:

1. **Group similar hypotheses** across reviewers. If Gemini and Codex both identify the same
   root cause, merge them into a single hypothesis with higher confidence.
2. **Flag contrarian hypotheses** — hypotheses unique to one reviewer. These are especially
   valuable because they may catch blind spots the other models share.
3. **Rank by:**
   - Reviewer consensus (how many reviewers independently identified it)
   - Evidence strength (how well it matches the symptom)
   - Testability (can we write a clear, deterministic failing test?)
4. **Cap at `max_hypotheses`** (from pipeline.json, default 5).

### Hypotheses Output

Write `.planning/diagnosis/hypotheses.md`:

```
# Differential Diagnosis: <problem summary>

## Ranked Hypotheses

### #1: <title> [Consensus: Gemini + Codex] [Confidence: HIGH]
- **Description:** ...
- **Suspected location:** ...
- **Diagnostic test:** ...
- **Sources:** [Gemini], [Codex]

### #2: <title> [Contrarian: Codex only] [Confidence: MEDIUM]
- **Description:** ...
- **Suspected location:** ...
- **Diagnostic test:** ...
- **Sources:** [Codex]

...
```

### User Presentation (Interactive Mode)

Present the ranked hypotheses to the user. Ask via `AskUserQuestion`:
"These are the ranked hypotheses. Should I proceed with testing them, or do you want to
add/remove/reorder any?"

In `--auto` mode: skip presentation, proceed directly to the fix phase.

### State Update

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . current_phase fix
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh append . completed_phases diagnose
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write_done . diagnose
```

## Phase 3: FIX — Hypothesis-Driven TDD

### Systematic Elimination

For each hypothesis in rank order:

1. **Write a diagnostic test.** The test must be designed to fail IF AND ONLY IF this
   hypothesis is the actual root cause.
   - Example: If hypothesis is "auth middleware doesn't refresh expired tokens" →
     write a test that submits an expired token and asserts that the middleware
     calls the refresh endpoint.
   - The test should be placed in the project's test directory following existing conventions.

2. **Run the test.**
   - If it **FAILS (red)**: This hypothesis is CONFIRMED as a root cause.
     - Mark as `CONFIRMED` in hypotheses.md
     - In interactive mode: stop testing further hypotheses, proceed to fix
     - In `--auto` mode: continue testing remaining hypotheses to find ALL contributing causes
   - If it **PASSES (green)**: This hypothesis is ELIMINATED.
     - Mark as `ELIMINATED` in hypotheses.md
     - Move to next hypothesis

3. **If no hypothesis confirmed** after testing all:
   - Write a diagnostic report summarizing all eliminations
   - In interactive mode: ask user for additional context via AskUserQuestion
   - In `--auto` mode: report failure and exit

### Implement the Fix

Once a root cause is confirmed:

1. The diagnostic test that confirmed the hypothesis is already failing (red).
2. Implement the **minimum code change** to make it pass.
3. Run the full test suite — ALL tests must pass.
4. If existing tests break: fix the implementation, not the tests (same TDD discipline
   as the main angry-ralph pipeline per `references/tdd-protocol.md`).

### Fix Report Output

Write `.planning/diagnosis/fix-report.md`:

```
# Fix Report: <problem summary>

## Hypotheses Tested
| # | Hypothesis | Result | Diagnostic Test |
|---|-----------|--------|-----------------|
| 1 | <title>   | CONFIRMED | <test name>  |
| 2 | <title>   | ELIMINATED | <test name> |
| 3 | <title>   | UNTESTED (stopped after confirmation) | — |

## Confirmed Root Cause
<description of the confirmed root cause>

## Fix Applied
<description of the code change>

## Files Changed
- <file> — <what changed>
```

### State Update

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . current_phase verify
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh append . completed_phases fix
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write_done . fix
```

## Phase 4: VERIFY — Adversarial Fix Verification

### Mechanical Gates

Run the subset of mechanical gates relevant to bug fixes:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/mechanical-gates.sh stub_check
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/mechanical-gates.sh test_verify "<test_runner_command>"
```

Skip `spec_compliance` (Gate 3) — there are no section spec data contracts in diagnose mode.

If either gate fails: loop back to the fix implementation and address the issue.

### Adversarial Verification via External Reviewers

Spawn `external-reviewer` subagent with a verification-specific prompt:

```
You are a senior engineer verifying a bug fix. Your job is to CHALLENGE the fix,
not validate it.

ORIGINAL PROBLEM: <problem description>

CONFIRMED ROOT CAUSE: <from fix report>

FIX APPLIED: <description and changed files>

DIAGNOSTIC TEST: <the test that confirmed the root cause>

HYPOTHESES ELIMINATED: <list of eliminated hypotheses and why>

QUESTIONS TO ANSWER:
1. Does this fix actually address the confirmed root cause, or does it just mask the symptom?
2. Could this fix introduce regressions or side effects in other parts of the system?
3. Are there edge cases the fix doesn't cover?
4. Is the diagnostic test sufficient, or could the root cause manifest differently
   in other scenarios?
5. Were any eliminated hypotheses dismissed too quickly?

Output structured markdown: ## Findings ([CRITICAL], [WARNING], [INFO] prefixes),
## Questions, ## Summary.
```

### Triage

Same decision tree as the main angry-ralph review (per `references/review-protocol.md`):
- `[CRITICAL]` → fix immediately, re-verify
- `[WARNING]` → evaluate, fix if real risk
- `[INFO]` → note for awareness
- Genuine ambiguity → `AskUserQuestion` (MANDATORY)

### Iteration Control

Up to `max_review_iterations` (from pipeline.json, default 2) verification iterations.
Exit early when zero CRITICAL and zero actionable WARNING.

### Atomic Commit

After verification passes:

```bash
git add <changed-files>
git commit -m "fix: <problem description summary>"
```

### Pipeline Completion

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . current_phase complete
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh append . completed_phases verify
```

Remove `.ralph-state/loop.md` if present. Report completion with:
- Confirmed root cause
- Fix applied
- Hypotheses tested (confirmed/eliminated)
- All commits made

## Resume Support

On re-invocation, check done markers:
- `investigate.done` → skip to Phase 2
- `diagnose.done` → skip to Phase 3
- `fix.done` → skip to Phase 4

Read `current_phase` from pipeline.json for finer-grained resume within phases.
