# /angry-diagnose Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an adversarial bug diagnosis command (`/angry-diagnose`) that performs structured differential diagnosis via external LLMs before fixing bugs.

**Architecture:** 4-phase pipeline (Investigate → Diagnose → Fix → Verify) integrated with existing `.ralph-state/` infrastructure. Reuses `external-reviewer` agent, `validate-env.sh`, `mechanical-gates.sh`, and `pipeline.sh` — no new scripts. Three new markdown files: command, protocol reference, and SKILL.md update. One test addition to verify pipeline.sh handles diagnosis-specific fields.

**Tech Stack:** Markdown (command + protocol), Bash (tests), existing pipeline.sh/state.sh infrastructure

---

### Task 1: Verify pipeline.sh supports arbitrary field writes

The `/angry-diagnose` command stores diagnosis-specific fields (`problem_description`, `context_files`, `max_hypotheses`) in pipeline.json using `pipeline_write`. This should already work since `pipeline_write` does `cfg[field] = value` for any field. We need a test to confirm this works and doesn't break.

**Files:**
- Modify: `tests/test-pipeline.sh` (append after Test 14, around line 179)

**Step 1: Write the failing test**

Add to `tests/test-pipeline.sh` before the `# Summary` section:

```bash
# ---- Test 15: pipeline_write can add arbitrary new fields ----
DIAG_DIR=$(mktemp -d)
bash "$PIPELINE" create "$DIAG_DIR" "/tmp/spec.md" "interactive" "3" "2" "20" "adversarial" "gemini,codex"
bash "$PIPELINE" write "$DIAG_DIR" "problem_description" "API returns 500 on large payloads"
PROB=$(bash "$PIPELINE" read "$DIAG_DIR" "problem_description")
assert_eq "write adds new string field" "API returns 500 on large payloads" "$PROB"

bash "$PIPELINE" write "$DIAG_DIR" "max_hypotheses" "5"
HYPO=$(bash "$PIPELINE" read "$DIAG_DIR" "max_hypotheses")
assert_eq "write adds new numeric field" "5" "$HYPO"

# Verify existing fields are untouched
MODE=$(bash "$PIPELINE" read "$DIAG_DIR" "mode")
assert_eq "existing fields preserved after adding new" "interactive" "$MODE"
rm -rf "$DIAG_DIR"
```

**Step 2: Run test to verify it passes**

Run: `bash tests/test-pipeline.sh`
Expected: All tests PASS including the 3 new assertions (this tests existing behavior, should pass immediately)

**Step 3: Commit**

```bash
git add tests/test-pipeline.sh
git commit -m "test: verify pipeline.sh supports arbitrary field writes for diagnose mode"
```

---

### Task 2: Create the diagnosis protocol reference

This is the core intellectual content — the hypothesis generation, ranking, and elimination procedure.

**Files:**
- Create: `skills/angry-ralph/references/diagnosis-protocol.md`

**Step 1: Write the protocol file**

Create `skills/angry-ralph/references/diagnosis-protocol.md` with:

```markdown
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
```

**Step 2: Verify the file is well-formed**

Read the file back and confirm all sections are present and properly formatted.

**Step 3: Commit**

```bash
git add skills/angry-ralph/references/diagnosis-protocol.md
git commit -m "feat: add diagnosis protocol reference for /angry-diagnose"
```

---

### Task 3: Create the angry-diagnose command

The command file handles argument parsing, environment validation, pipeline setup, and handoff to the skill.

**Files:**
- Create: `commands/angry-diagnose.md`

**Step 1: Write the command file**

Create `commands/angry-diagnose.md`:

```markdown
---
name: angry-diagnose
description: Adversarial bug diagnosis — differential diagnosis via external LLMs, hypothesis-driven TDD fix
---

# /angry-diagnose Command

Adversarial bug investigation pipeline. Generates competing hypotheses for a bug's root cause using external LLMs, then systematically proves/disproves each hypothesis via failing tests before implementing the fix.

## 1. Argument Parsing

Parse the invocation arguments:

- **`@file` references** (optional, multiple) -- Error logs, stack traces, suspect source files as context.
- **Prompt text** (required) -- Description of the problem/symptom.
- **`--auto`** (optional) -- Skip clarifying questions, auto-accept findings, test all hypotheses.
- **`--max-hypotheses N`** (optional, default: `5`) -- Maximum number of hypotheses to generate.
- **`--help`** (optional) -- Print command reference and exit.

### --help Output

If `--help` is passed, print the following and stop:

` ` `
angry-diagnose — Adversarial bug diagnosis with differential diagnosis and hypothesis-driven TDD.

Usage:
  /angry-diagnose [@context-files...] "problem description" [--auto] [--max-hypotheses N]

Examples:
  /angry-diagnose "the API returns 500 on large payloads"
  /angry-diagnose @error.log "users can't login after password reset"
  /angry-diagnose @src/auth.ts @error.log "this middleware leaks sessions"

Options:
  --auto                Skip questions, auto-accept findings, test all hypotheses.
  --max-hypotheses N    Max competing hypotheses to generate (default: 5).

Phases:
  1. INVESTIGATE    Gather context, build case file, interview user.
  2. DIAGNOSE       Generate competing hypotheses via external LLMs (differential diagnosis).
  3. FIX            Prove/disprove hypotheses via diagnostic tests, fix confirmed root cause.
  4. VERIFY         Mechanical gates + adversarial verification of the fix.

State: .ralph-state/ (gitignored)
Artifacts: .planning/diagnosis/ (gitignored)
` ` `

If no prompt text is provided and `--help` is not passed, report the error and display the help text.

## 2. Environment Validation

Run via the Bash tool:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/checks/validate-env.sh
```

Halt on non-zero exit. Capture JSON stdout (`review_tier`, `available_reviewers`).

Confirm git repository:

```bash
git rev-parse --is-inside-work-tree
```

If not in a git repo:
- **`--auto` mode**: Run `git init` automatically.
- **Interactive mode**: Ask whether to `git init`.

## 3. Backwards Compatibility Migration

Run the migration check:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh migrate .
```

If output is `migrated`, inform user.

## 4. Resume Detection

Check `.ralph-state/` for prior diagnosis state:

- `.ralph-state/phases/investigate.done` → Phase 1 done
- `.ralph-state/phases/diagnose.done` → Phase 2 done
- `.ralph-state/phases/fix.done` → Phase 3 done
- `.ralph-state/pipeline.json` → read `mode` field; only resume if `mode` is `"diagnose"`

If prior diagnosis state detected:
- **`--auto` mode**: Resume automatically from the last completed phase.
- **Interactive mode**: Ask via AskUserQuestion: "Resume the previous diagnosis, or start fresh?"

If start fresh: `rm -rf .ralph-state/ .planning/diagnosis/` and continue.

If prior state exists but `mode` is NOT `"diagnose"` (e.g., an angry-ralph pipeline is active): warn the user and ask whether to proceed (this will create diagnosis artifacts alongside existing pipeline artifacts).

## 5. Setup

Create pipeline state. Use the existing `pipeline.sh create` with the problem description as the spec_file field, then override diagnosis-specific fields:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh create . "<PROBLEM_DESCRIPTION>" "<MODE>" "2" "0" "0" "<REVIEW_TIER>" "<AVAILABLE_REVIEWERS>"
```

Then set diagnosis-specific fields:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . current_phase investigate
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . mode diagnose
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . problem_description "<PROBLEM_DESCRIPTION>"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . max_hypotheses "<MAX_HYPOTHESES>"
```

Where `<MODE>` is `auto` if `--auto` was passed, then overwritten to `diagnose`. The `mode` field serves double duty: `diagnose` identifies this as a diagnosis pipeline, and the original auto/interactive distinction is captured by checking if `--auto` was in the original invocation (store as a separate field if needed, or read from `pipeline.json` context).

Actually, simplify: always set `mode` to `diagnose`. Store auto behavior separately:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . auto_mode "<true|false>"
```

Create the diagnosis artifacts directory:

```bash
mkdir -p .planning/diagnosis/reviews
```

## 6. Handoff to Skill

Begin Phase 1 (INVESTIGATE) immediately. Follow the diagnosis protocol at `references/diagnosis-protocol.md`.

### --auto Behavior

When `auto_mode` is `"true"` in pipeline.json:
- **Phase 1**: Skip interview questions. Work with provided context only.
- **Phase 2**: Skip hypothesis presentation. Proceed directly to fix.
- **Phase 3**: Test ALL hypotheses (don't stop at first confirmation). Auto-accept.
- **Phase 4**: Run verification, auto-accept findings.
```

NOTE: The triple backticks in the --help output section above should NOT be escaped — they are literal markdown code fences. When writing the actual file, use proper triple backticks (the space-separated ones above are just for plan readability).

**Step 2: Verify the file has proper YAML frontmatter**

Read the file back. Confirm the `---` frontmatter delimiters, `name`, and `description` fields are present and correctly formatted.

**Step 3: Commit**

```bash
git add commands/angry-diagnose.md
git commit -m "feat: add /angry-diagnose command for adversarial bug diagnosis"
```

---

### Task 4: Add diagnosis mode to SKILL.md

Add a section to the master orchestration skill that references the diagnosis protocol, so the skill knows how to handle diagnosis mode invocations.

**Files:**
- Modify: `skills/angry-ralph/SKILL.md` (append before `## State Management` section, around line 315)

**Step 1: Read the current SKILL.md**

Read `skills/angry-ralph/SKILL.md` to find the exact insertion point.

**Step 2: Add the diagnosis mode section**

Insert the following section before `## State Management` (before line 315):

```markdown
## Diagnosis Mode (/angry-diagnose)

When invoked via `/angry-diagnose`, the pipeline runs a 4-phase diagnosis workflow instead of the standard 6-phase spec-to-code pipeline. The command file handles setup and creates pipeline.json with `mode: "diagnose"`.

### Phase 1: INVESTIGATE

Build a case file from the user's problem description and any provided context files. Gather relevant source files, trace dependencies, check recent git history, and optionally interview the user.

Output: `.planning/diagnosis/case-file.md`

### Phase 2: DIAGNOSE (Differential Diagnosis)

Spawn the `external-reviewer` subagent with a diagnosis-specific prompt (not the standard plan/code review prompt). Each reviewer generates at least 3 competing hypotheses for the root cause, including at least 1 non-obvious hypothesis. Merge, deduplicate, rank by consensus and evidence strength, cap at `max_hypotheses`.

Output: `.planning/diagnosis/hypotheses.md`

### Phase 3: FIX (Hypothesis-Driven TDD)

For each hypothesis in rank order, write a diagnostic test designed to prove/disprove it. Run the test: if it fails, the hypothesis is confirmed; if it passes, it's eliminated. Once a root cause is confirmed, implement the minimum fix to make the failing diagnostic test pass. Run full test suite.

Output: `.planning/diagnosis/fix-report.md`

### Phase 4: VERIFY (Adversarial Verification)

Run mechanical gates (stub check + test verify, skip spec compliance). Spawn `external-reviewer` with a verification prompt challenging the fix. Triage findings per `references/review-protocol.md`. Atomic commit on success.

### Detailed Procedure

Consult `references/diagnosis-protocol.md` for the complete diagnosis procedure, including:
- Case file structure and context gathering rules
- Diagnosis prompt template for external reviewers
- Hypothesis merge/rank/cap algorithm
- Systematic elimination via diagnostic tests
- Fix report format
- Verification prompt and iteration control
```

**Step 3: Commit**

```bash
git add skills/angry-ralph/SKILL.md
git commit -m "feat: add diagnosis mode section to SKILL.md for /angry-diagnose"
```

---

### Task 5: Update --help output in angry-ralph.md

Add `/angry-diagnose` to the command listing in the `--help` output so users discover it.

**Files:**
- Modify: `commands/angry-ralph.md:33-39` (the Commands section of --help output)

**Step 1: Read the current --help section**

Read `commands/angry-ralph.md` lines 27-49 to see the exact text.

**Step 2: Add the new command to the listing**

In the `Commands:` section of the --help output (around line 38), add after the `/angry-fix` line:

```
  /angry-diagnose [@ctx] "problem"    Adversarial bug diagnosis: hypothesize, test, fix.
```

So the Commands section becomes:

```
Commands:
  /angry-ralph @spec [--auto]           Smart monolith: Phases 1-6, idempotent resume.
  /angry-architect @spec [--auto]       Phases 1-2: Decompose + Plan.
  /angry-review [plan|code|section <n>] Phase 3 in pipeline. On-demand anytime.
  /angry-execute [--auto] [--rebuild <section>]  Phases 4-6: Split + TDD + Final Review.
  /angry-fix [context] [prompt]         Surgical TDD strike: test, fix, green, commit.
  /angry-diagnose [@ctx] "problem"      Adversarial diagnosis: hypothesize, test, fix.
  /cancel-ralph                         Kill switch: halt loop, save state, exit.
  /angry-status                         Read-only pipeline state display.
```

**Step 3: Commit**

```bash
git add commands/angry-ralph.md
git commit -m "docs: add /angry-diagnose to --help command listing"
```

---

### Task 6: Run tests and verify

**Step 1: Run the pipeline tests**

Run: `bash tests/test-pipeline.sh`
Expected: All tests pass, including the new Test 15 (arbitrary field writes).

**Step 2: Verify all files are properly structured**

- Confirm `commands/angry-diagnose.md` has valid YAML frontmatter
- Confirm `skills/angry-ralph/references/diagnosis-protocol.md` exists
- Confirm `skills/angry-ralph/SKILL.md` includes the diagnosis mode section
- Confirm `commands/angry-ralph.md` --help includes `/angry-diagnose`

**Step 3: Final commit (if any fixups needed)**

If any issues were found in step 1-2, fix and commit. Otherwise this step is a no-op.
