---
name: review-code
description: Run on-demand adversarial review of the current codebase against the implementation plan
---

# /review-code Command

Run an adversarial code review at any time — outside the normal Phase 3/6 pipeline gates. This reviews the **current codebase** against the **implementation plan**, using the same external-reviewer infrastructure.

## When to Use

- Mid-execution: review completed sections before the full pipeline finishes
- After manual changes: verify hand-written code aligns with the plan
- Post-pipeline: re-review after addressing deferred findings
- Spot-check: validate specific concerns without running the full pipeline

## Procedure

### 1. Validate Prerequisites

Confirm a `planning/` directory exists with at least `planning/angry-ralph-plan.md` and `planning/config.json`. If missing, report:

```
Error: No planning artifacts found. Run /angry-ralph first to generate a plan.
```

Read `planning/config.json` for `review_tier` and `available_reviewers`.

### 2. Transparency

Print the active review tier:

```
angry-ralph: On-demand code review tier — <TIER_LABEL>
Reviewers: <comma-separated list>
```

### 3. Determine Scope

Identify what to review. By default, review all source files (exclude `planning/`, `node_modules/`, `.git/`, test fixtures). If the user provided arguments after `/review-code`, treat them as file paths or glob patterns to narrow scope.

### 4. Spawn External Reviewer

Create the review output directory:

```bash
mkdir -p planning/reviews/on-demand/code-$(date -u +%Y%m%dT%H%M%SZ)/
```

Spawn the `external-reviewer` subagent with:
- Review type: `"on-demand code review"`
- Active review tier and available reviewers
- Project directory path
- Plan file path: `planning/angry-ralph-plan.md`
- Sections directory: `planning/sections/`
- Scope description (all code or specific files)

The subagent invokes the available reviewers focusing on:
- **Plan-vs-code gaps** — differences between what the plan specifies and what exists
- **Implementation substance** — stubs, TODOs, empty bodies, placeholder logic
- **Integration issues** — cross-section bugs, missing error handling
- **Security vulnerabilities** — injection, auth bypass, secrets in code

### 5. Self-Healing Triage Loop

Apply findings using a review-fix-review loop (same pattern as Phase 6):

1. Triage findings: fix CRITICAL immediately, evaluate WARNING, resolve clear questions, escalate genuine ambiguity via `AskUserQuestion`.
2. If zero CRITICAL and zero actionable WARNING — done.
3. If fixes were made: re-run the full test suite, commit fixes as `fix: address on-demand code review findings`, re-spawn reviewer for verification.
4. Loop up to `max_review_iterations` from `planning/config.json` (default 3).
5. If cap reached with findings open: log to the review directory and report.

### 6. Report

Print a summary: total findings per severity, what was fixed, what remains. Reference the review output directory for full details.
