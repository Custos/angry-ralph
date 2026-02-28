# /angry-diagnose — Adversarial Bug Diagnosis Pipeline

**Date:** 2026-02-27
**Status:** Approved

## Overview

`/angry-diagnose` is a pipeline-integrated command that performs adversarial root cause analysis on bugs in existing code. Unlike `/angry-fix` (which goes straight to test-fix-commit), `/angry-diagnose` first performs a structured **differential diagnosis** — generating competing hypotheses via external LLMs, then systematically proving/disproving each via failing tests before implementing the fix.

The core insight: break the LLM's tunnel vision when debugging. Don't guess the root cause and patch. Generate multiple competing hypotheses, challenge them adversarially, and only fix once the true cause is isolated by a failing test.

## Command Interface

```
/angry-diagnose [@context-files...] "problem description" [--auto] [--max-hypotheses N]
```

**Arguments:**
- `@file` references (optional, multiple) — error logs, stack traces, suspect source files
- Prompt text (required) — symptom description
- `--auto` — skip clarifying questions, auto-accept findings, test all hypotheses
- `--max-hypotheses N` (default 5) — cap on hypotheses to generate
- `--help` — print usage

**Examples:**
```
/angry-diagnose "the API returns 500 on large payloads"
/angry-diagnose @error.log "users can't login after password reset"
/angry-diagnose @src/auth.ts @error.log "this middleware leaks sessions"
```

## Architecture

4-phase pipeline: **Investigate → Diagnose → Fix → Verify**

Pipeline-integrated: uses `.ralph-state/` for state management, `.planning/diagnosis/` for artifacts. Resume-capable via done markers.

Reuses existing infrastructure:
- `validate-env.sh` for review tier detection
- `external-reviewer` agent for hypothesis generation and fix verification
- `mechanical-gates.sh` for pre-commit checks
- `pipeline.sh` for state management

## Phase 1: INVESTIGATE

**Purpose:** Build a "case file" — gather all relevant context before asking external reviewers for hypotheses.

**Process:**
1. Parse arguments; validate any `@file` references exist
2. Run `validate-env.sh` — detect review tier and available reviewers
3. Confirm git repo (same pattern as `/angry-ralph`)
4. Create pipeline state: `pipeline.sh create` with mode `diagnose`, fields: `problem_description`, `context_files`
5. Create `.planning/diagnosis/` directory for artifacts
6. Context gathering (main session, no subagent):
   - Read all provided `@file` context
   - If suspect source files provided: read them, trace imports/callers/callees (1-2 levels deep)
   - If only a problem description: search codebase for relevant keywords, error messages, related modules
   - Identify: relevant source files, test files, config files, recent git changes to those files (`git log --oneline -10 -- <files>`)
7. Interview (unless `--auto`):
   - Ask 1-2 clarifying questions about the symptom: when does it happen, is it reproducible, any recent changes?
   - In `--auto` mode: skip, work with what's provided
8. Output: `.planning/diagnosis/case-file.md` — structured document with symptom, context, relevant files, recent changes, interview notes
9. State update: `current_phase = "diagnose"`, append `"investigate"` to `completed_phases`, write `investigate.done`

## Phase 2: DIAGNOSE (Differential Diagnosis)

**Purpose:** Generate competing hypotheses using external reviewers, then rank them.

**Process:**
1. Read case file from Phase 1
2. Spawn `external-reviewer` subagent with diagnosis-specific prompt:
   - Pass: case file, all relevant source files, problem description
   - Each reviewer generates **at least 3 competing hypotheses**
   - Each hypothesis includes: description, suspected location (file + function/line range), why it could be the cause, what evidence would prove/disprove it
   - Must include at least 1 "non-obvious" hypothesis (race condition, config issue, upstream dependency, data corruption, etc.)
   - Tag each with source: `[Gemini]`, `[Codex]`, `[Claude-Reflection]`
3. Merge and deduplicate hypotheses:
   - Group similar hypotheses across reviewers
   - Multiple reviewers identifying same cause → higher confidence
   - Unique-to-one-reviewer hypothesis → flag as "contrarian" (don't discard)
4. Rank by: reviewer consensus, evidence strength, testability
5. Cap at `max_hypotheses` (default 5)
6. Output: `.planning/diagnosis/hypotheses.md` — ranked list with descriptions, locations, proposed tests
7. Present to user (unless `--auto`): show ranked hypotheses, ask if any should be added/removed
8. State update: `current_phase = "fix"`, append `"diagnose"` to `completed_phases`, write `diagnose.done`

## Phase 3: FIX (Hypothesis-Driven TDD)

**Purpose:** Systematically prove/disprove hypotheses via failing tests, then fix the true root cause.

**Process:**
1. Read ranked hypotheses from Phase 2
2. For each hypothesis in rank order:
   a. Write a **diagnostic test** — fails if and only if this hypothesis is the actual root cause
   b. Run the test:
      - **Fails (red)** → hypothesis CONFIRMED as root cause. Stop testing further hypotheses (unless `--auto`, which tests all to find multiple contributing causes).
      - **Passes (green)** → hypothesis ELIMINATED. Move to next.
3. If no hypothesis confirmed after testing all:
   - Generate diagnostic report summarizing eliminations
   - Ask user for additional context (unless `--auto`)
   - If `--auto`: report failure, exit
4. Implement the fix:
   - With confirmed root cause isolated by a failing test, implement the minimum code change to make it pass
   - Run full test suite — confirm ALL tests pass (green phase)
   - If existing tests break: fix implementation, not tests
5. Output: `.planning/diagnosis/fix-report.md` — hypotheses tested (CONFIRMED/ELIMINATED), root cause, fix description, files changed
6. State update: `current_phase = "verify"`, append `"fix"` to `completed_phases`, write `fix.done`

## Phase 4: VERIFY (Adversarial Verification)

**Purpose:** Challenge the fix — ensure it solves the problem without introducing new issues.

**Process:**
1. Read fix report from Phase 3
2. Mechanical gates (reuse `mechanical-gates.sh`):
   - Stub grep: no TODOs, FIXMEs in changed files
   - Test verify: full test suite passes, at least one test ran
   - If gates fail: loop back to fix phase
3. Spawn `external-reviewer` subagent with verification prompt:
   - Pass: original problem, case file, hypotheses, fix report, changed files
   - Reviewers answer: does fix address root cause? Could it introduce regressions? Edge cases missed? Is diagnostic test sufficient?
   - Tag findings with source and severity
4. Triage (same decision tree as angry-ralph review):
   - CRITICAL → fix immediately, re-verify
   - WARNING → evaluate, fix if real risk
   - INFO → note for awareness
5. Iteration control: up to `max_review_iterations` (default 2)
6. Atomic commit: `fix: <problem description summary>`
7. Pipeline completion:
   - `current_phase = "complete"`, append `"verify"` to `completed_phases`
   - Report: root cause, fix applied, all commits, hypotheses tested
   - Remove `.ralph-state/loop.md` if present

## State Management

**Pipeline config** (`.ralph-state/pipeline.json`):
- `mode`: `"diagnose"`
- `problem_description`: symptom text
- `context_files`: list of provided `@file` paths
- `max_hypotheses`: cap on hypotheses (default 5)
- `max_review_iterations`: verification iterations (default 2)
- Standard fields: `current_phase`, `completed_phases`, `review_tier`, `available_reviewers`

**Done markers** (`.ralph-state/phases/`):
- `investigate.done`
- `diagnose.done`
- `fix.done`
- `verify.done` (alias for completion)

**Artifacts** (`.planning/diagnosis/`):
- `case-file.md` — Phase 1 output
- `hypotheses.md` — Phase 2 output
- `fix-report.md` — Phase 3 output
- `reviews/` — Phase 4 review outputs

## Files to Create/Modify

**New files:**
- `commands/angry-diagnose.md` — command definition (similar structure to angry-fix.md + angry-ralph.md patterns)
- `skills/angry-ralph/references/diagnosis-protocol.md` — diagnosis-specific protocol (hypothesis generation, ranking, elimination)

**Modified files:**
- `plugin.json` — register new command
- `skills/angry-ralph/SKILL.md` — add diagnosis mode support (reference to diagnosis-protocol.md)

**Reused unchanged:**
- `agents/external-reviewer.md` — hypothesis generation and fix verification (new prompt types, same agent)
- `scripts/checks/validate-env.sh` — review tier detection
- `scripts/lib/pipeline.sh` — state management
- `scripts/lib/mechanical-gates.sh` — pre-commit checks

## Relationship to Existing Commands

| Command | Purpose | Investigation | Review | TDD |
|---------|---------|--------------|--------|-----|
| `/angry-ralph` | Spec → code | N/A (starts from spec) | Full adversarial | Full loop |
| `/angry-fix` | Surgical fix | None (user knows the cause) | None | Single cycle |
| `/angry-diagnose` | Bug investigation | Structured differential diagnosis | Hypothesis generation + fix verification | Hypothesis-driven |
| `/angry-review` | On-demand review | N/A | Adversarial review | None |
