---
name: angry-review-section
description: Run on-demand adversarial review of a specific section's implementation against its spec
---

# /angry-review-section Command

Run an adversarial review of a **specific section's implementation** against its section spec and the overall plan. Useful for targeted validation of individual sections.

## Usage

```
/angry-review-section <section-name-or-number>
```

Examples:
- `/angry-review-section section-01-auth`
- `/angry-review-section 3`
- `/angry-review-section section-05-password-auth`

If no argument is provided, list all available sections from `planning/sections/index.md` and ask the user to pick one via `AskUserQuestion`.

## Procedure

### 1. Validate Prerequisites

Confirm `planning/sections/` directory exists with section specs and `planning/config.json`. If missing:

```
Error: No section specs found. Run /angry-ralph through Phase 4 (SPLIT) first.
```

Read `planning/config.json` for `review_tier` and `available_reviewers`.

### 2. Resolve Section

If the argument is a number (e.g., `3`), find the matching section spec file from `planning/sections/` (e.g., `section-03-*.md`). If the argument is a name, match it directly. If no match:

```
Error: Section '<arg>' not found. Available sections:
  section-01-auth
  section-02-database
  ...
```

### 3. Identify Section Files

Determine which source files belong to this section:
- Read the section spec's **Scope** to identify expected files
- Cross-reference with `git log --oneline --grep="feat(section-NN)"` to find the commit(s) for this section
- Use `git diff-tree --no-commit-id --name-only -r <commit>` to list files from the section's commit

If no commit exists yet (section not yet executed), review the section spec only and note that implementation hasn't started.

### 4. Transparency

```
angry-ralph: On-demand section review tier — <TIER_LABEL>
Reviewers: <comma-separated list>
Section: <section-name>
```

### 5. Spawn External Reviewer

Create the review output directory:

```bash
mkdir -p planning/reviews/on-demand/section-<name>-$(date -u +%Y%m%dT%H%M%SZ)/
```

Spawn the `external-reviewer` subagent with:
- Review type: `"on-demand section review"`
- Active review tier and available reviewers
- Section spec path
- Plan file path: `planning/angry-ralph-plan.md`
- List of source files belonging to this section
- Project directory path

The subagent invokes the available reviewers focusing on:
- **Section spec fidelity** — does the code match the spec's scope and acceptance criteria?
- **Implementation substance** — stubs, TODOs, empty bodies
- **Algorithm correctness** — matches plan specs, handles edge cases
- **Test quality** — meaningful assertions, would fail on stub
- **Integration readiness** — exports match downstream expectations

### 6. Self-Healing Triage Loop

Apply findings using a review-fix-review loop:

1. Triage findings: fix CRITICAL immediately, evaluate WARNING, escalate genuine ambiguity via `AskUserQuestion`.
2. If zero CRITICAL and zero actionable WARNING — done.
3. If fixes were made: re-run the test suite, commit fixes as `fix: address review findings for <section-name>`, re-spawn reviewer for verification.
4. Loop up to `max_review_iterations` from `planning/config.json` (default 3).
5. If cap reached with findings open: log and report.

### 7. Report

Print a summary: section name, findings per severity, fixes applied, remaining items. Reference the review output directory.
