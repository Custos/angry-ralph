---
name: angry-ralph
description: Start the angry-ralph unified planning and execution pipeline
hide-from-slash-command-tool: "true"
---

# /angry-ralph Command

When the user invokes `/angry-ralph`, execute the following steps in order.

## 1. Argument Parsing

Parse the invocation arguments:

- **`@file.md`** (required) -- The input specification file.
- **`--auto`** (optional) -- Skip clarifying questions and review approval. Store `"mode": "auto"` in pipeline config.
- **`--help`** (optional) -- Print command reference and exit.
- **`--max-review-iterations N`** (optional, default: `3`)
- **`--max-section-review-iterations N`** (optional, default: `2`)
- **`--max-tdd-iterations N`** (optional, default: `20`)

### --help Output

If `--help` is passed, print the following and stop:

```
angry-ralph — Spec-to-code pipeline with adversarial review and TDD execution.

Usage:
  /angry-ralph @spec.md [--auto] [--max-review-iterations N] [--max-section-review-iterations N] [--max-tdd-iterations N]

Commands:
  /angry-ralph @spec [--auto]           Smart monolith: Phases 1-6, idempotent resume.
  /angry-architect @spec [--auto]       Phases 1-2: Decompose + Plan.
  /angry-review [plan|code|section <n>] Phase 3 in pipeline. On-demand anytime.
  /angry-execute [--auto] [--rebuild <section>]  Phases 4-6: Split + TDD + Final Review.
  /angry-fix [context] [prompt]         Surgical TDD strike: test, fix, green, commit.
  /cancel-ralph                         Kill switch: halt loop, save state, exit.
  /angry-status                         Read-only pipeline state display.

Options:
  --auto                              Skip questions + review approval. Auto-accept and proceed.
  --max-review-iterations N           Max review rounds in Phase 3/6 (default: 3).
  --max-section-review-iterations N   Max per-section review-fix cycles (default: 2).
  --max-tdd-iterations N              Max TDD loop iterations per section (default: 20).

State: .ralph-state/ (gitignored)
Artifacts: planning/ (persistent)
```

If no `@file.md` argument is provided and `--help` is not passed, report the error and display the same help text.

Validate that the referenced spec file exists and is readable. Resolve its absolute path as `SPEC_FILE`.

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

If not in a git repo, ask whether to `git init`. Do not initialize without consent.

## 3. Backwards Compatibility Migration

Run the migration check via the Bash tool:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh migrate .
```

If output is `migrated`, inform user: "Migrated legacy state to .ralph-state/".

## 4. Resume Detection via .done Markers

Check `.ralph-state/` for prior state:

- `.ralph-state/phases/architect.done` → Phases 1-2 done
- `.ralph-state/phases/review.done` → Phase 3 done
- `.ralph-state/phases/execute.done` → Phases 4-6 done. Pipeline complete.
- `.ralph-state/pipeline.json` → read `current_phase` and `completed_sections` for finer resume
- `.ralph-state/loop.md` with `active=true` → mid-section TDD resume

If prior state detected, ask via AskUserQuestion: "Resume the previous run, or start fresh?"

If start fresh: `rm -rf .ralph-state/ planning/` and continue.

## 5. Setup

Initialize state via the Bash tool:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh create . "<SPEC_FILE>" "<MODE>" "<MAX_REVIEW>" "<MAX_SECTION_REVIEW>" "<MAX_TDD>" "<REVIEW_TIER>" "<AVAILABLE_REVIEWERS>"
```

Where `<MODE>` is `auto` if `--auto` was passed, otherwise `interactive`. Substitute actual values for all placeholders.

Create planning directories:

```bash
mkdir -p planning/reviews planning/sections
```

## 6. Handoff to Skill

The angry-ralph skill handles the full 6-phase workflow. Begin Phase 1 immediately.

### --auto Behavior

When `mode` is `"auto"` in pipeline.json:
- **Phase 1**: Do NOT use AskUserQuestion. Make secure, industry-standard assumptions.
- **Phase 3**: Run review and log findings, but auto-accept and proceed without human approval.
- **Phase 5/6**: Skip confirmation prompts.
