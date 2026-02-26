---
name: angry-review-plan
description: Run on-demand adversarial review of the implementation plan
---

# /angry-review-plan Command

Run an adversarial plan review at any time — same as Phase 3 but invokable on-demand. Reviews the **implementation plan** using the external-reviewer infrastructure.

## When to Use

- After manually editing the plan: re-validate changes
- Before resuming execution: verify the plan is still sound
- After addressing deferred review findings: confirm fixes
- Independent validation: get a fresh adversarial look at any time

## Procedure

### 1. Validate Prerequisites

Confirm `planning/angry-ralph-plan.md` and `planning/config.json` exist. If missing:

```
Error: No plan found. Run /angry-ralph first to generate a plan.
```

Read `planning/config.json` for `review_tier` and `available_reviewers`.

### 2. Transparency

Print the active review tier:

```
angry-ralph: On-demand plan review tier — <TIER_LABEL>
Reviewers: <comma-separated list>
```

### 3. Spawn External Reviewer

Create the review output directory:

```bash
mkdir -p planning/reviews/on-demand/plan-$(date -u +%Y%m%dT%H%M%SZ)/
```

Spawn the `external-reviewer` subagent with:
- Review type: `"on-demand plan review"`
- Active review tier and available reviewers
- Plan file path: `planning/angry-ralph-plan.md`
- Spec file path (from `planning/config.json`)

The subagent invokes the available reviewers focusing on:
- **Logic flaws** — incorrect assumptions, missing edge cases
- **Security vulnerabilities** — architectural security gaps
- **Systemic breaking points** — single points of failure, scalability concerns
- **Ambiguities** — unclear requirements that could lead to wrong implementations

### 4. Self-Healing Triage Loop

Apply findings using a review-fix-review loop:

1. Triage findings: fix CRITICAL in the plan immediately, evaluate WARNING, resolve clear questions, escalate genuine ambiguity via `AskUserQuestion`.
2. If zero CRITICAL and zero actionable WARNING — done.
3. If fixes were made to the plan: re-spawn reviewer for verification.
4. Loop up to `max_review_iterations` from `planning/config.json` (default 3).
5. If cap reached with findings open: log and report.

### 5. Report

Print a summary: total findings per severity, what was fixed in the plan, what remains. Reference the review output directory for full details.
