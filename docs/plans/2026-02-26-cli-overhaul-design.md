# Design: CLI Architecture Overhaul

**Date:** 2026-02-26
**Status:** Approved

## Context

angry-ralph grew to 10 commands, most of which exist as escape hatches for a monolithic pipeline. `/angry-skip-to`, `/angry-rerun`, `/angry-split` are band-aids. The upstream "Deep Trilogy" (deep-project, deep-plan, deep-implement) proves that discrete, composable commands are the right model. This overhaul kills the escape hatches and replaces them with first-class phase commands.

## Final Command Roster (7 commands)

| Command | What it does |
|---------|-------------|
| `/angry-ralph @spec [--auto] [--help]` | Smart monolith: Phases 1-6, idempotent resume. `--auto` skips questions + review approval. `--help` prints command reference. |
| `/angry-architect @spec [--auto]` | Phases 1-2: Decompose + Plan. |
| `/angry-review [plan\|code\|section <name>]` | Phase 3 in pipeline. On-demand anytime with target. |
| `/angry-execute [--auto] [--rebuild <section>]` | Phases 4-6: Split + TDD + Final Review. `--rebuild` deletes a section's done marker and re-runs. |
| `/angry-fix [context] [prompt]` | Surgical TDD strike: write failing test, fix, green, commit. |
| `/cancel-ralph` | Kill switch: halt loop, save state, exit. |
| `/angry-status` | Read-only pipeline state display. |

### Killed Commands

- `/angry-skip-to` — Replaced by running `/angry-execute` directly
- `/angry-rerun` — Replaced by running any phase command directly
- `/angry-split` — Subsumed by `/angry-execute` (Phase 4 is its first step)
- `/angry-ralph-help` — Replaced by `/angry-ralph --help`
- `/angry-review-code` — Consolidated into `/angry-review code`
- `/angry-review-plan` — Consolidated into `/angry-review plan`
- `/angry-review-section` — Consolidated into `/angry-review section <name>`

## State Management — `.ralph-state/`

Replace split state (`.claude/angry-ralph.local.md` + `planning/config.json`) with unified `.ralph-state/` directory.

```
.ralph-state/
├── pipeline.json          # Config, phase tracking, timestamps
├── loop.md                # Active TDD loop state (YAML frontmatter + prompt body)
└── phases/
    ├── architect.done     # Marker: Phases 1+2 complete
    ├── review.done        # Marker: Phase 3 complete
    └── execute.done       # Marker: Phases 4-6 complete
```

### pipeline.json

```json
{
  "spec_file": "/abs/path/to/spec.md",
  "mode": "interactive",
  "max_review_iterations": 3,
  "max_section_review_iterations": 2,
  "max_tdd_iterations": 20,
  "started_at": "2026-02-26T...",
  "review_tier": "adversarial",
  "available_reviewers": ["gemini", "codex"],
  "current_phase": "execute",
  "completed_sections": ["section-01-auth", "section-02-api"]
}
```

### loop.md

Same YAML frontmatter + body format as current `.claude/angry-ralph.local.md`. Same fields, same stop hook mechanism, new path.

### .done Marker Files

Idempotency via filesystem. Each command checks: does my `.done` marker exist? If yes, skip. No JSON parsing needed.

### Strict .done Gating (No False Success)

`/angry-execute` MUST NOT write `execute.done` unless the test suite passes (`exit 0`). If `max_tdd_iterations` is hit and tests still fail, hard-crash the pipeline with a non-zero exit code and alert the user. No silent progression.

### Separation of Concerns

- `.ralph-state/` = ephemeral state tracking (gitignored)
- `planning/` = persistent artifacts (plan, reviews, sections)
- `planning/config.json` is eliminated — `pipeline.json` is the single source of truth

## `--auto` Mode

When `--auto` is passed to `/angry-ralph` or `/angry-architect`:
- Append to LLM system prompt: "Do NOT ask clarifying questions. Make the most secure, industry-standard architectural assumption and proceed immediately."
- Skip the human-in-the-loop pause after Phase 3 review. Review still runs and logs findings, but agent auto-accepts and proceeds.
- Stored in `pipeline.json` as `"mode": "auto"`.

When `--auto` is passed to `/angry-execute`:
- Skip any final confirmation prompts. Start churning out code immediately.

## `--rebuild <section>` Flag

On `/angry-execute --rebuild section-03-api`:
1. `rm .ralph-state/phases/execute-section-03-api.done` (or equivalent section marker)
2. Kick off the idempotent pipeline — it sees the section as incomplete and rebuilds it.

No complex state mutation. Just delete a marker and re-run.

## `/angry-fix [context] [prompt]`

Surgical post-pipeline TDD remediation:
1. Accept context (file paths, error logs via `@file` references) and a prompt describing the bug.
2. Write a failing test based on the prompt.
3. Run TDD loop: implement fix, run tests, iterate until green.
4. Atomic commit when tests pass.
5. No planning phase. No review phase. Just fix and ship.

Usage: `/angry-fix @error.log "Fix these integration blockers"`

## `/angry-review [target]`

Unified review command with subcommand pattern:
- `/angry-review plan` — Adversarial review of `planning/angry-ralph-plan.md`. During pipeline = Phase 3.
- `/angry-review code` — Adversarial review of codebase against the plan.
- `/angry-review section <name>` — Review of a specific section against its spec.

All targets use the same `external-reviewer` subagent. Same retry/fallback logic (parallel execution, retry once, claude fallback).

When run as Phase 3 in the pipeline, writes `review.done` on completion.
When run on-demand, writes to `planning/reviews/on-demand/`.

## Backwards Compatibility

Lean migration on initialization: if legacy `.claude/angry-ralph.local.md` exists and `.ralph-state/` does not, `mv` the file and `mkdir` the new directory. Two lines. No migration framework.

## Stop Hook Changes

`hooks/stop-hook.sh` reads `.ralph-state/loop.md` instead of `.claude/angry-ralph.local.md`. Reads `max_tdd_iterations` from `.ralph-state/pipeline.json` instead of `planning/config.json`. Same parsing logic, new paths.

## Verification

1. All existing test suites adapted to new paths — all must pass
2. New tests for `.done` marker creation/detection
3. New tests for `--auto` flag parsing
4. Manual verification: interrupt and resume at each phase boundary
5. Manual verification: `/angry-fix` with a real bug
