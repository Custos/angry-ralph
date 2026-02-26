---
name: angry-review
description: Run adversarial review on plan, code, or a specific section
---

# /angry-review Command

Unified review command. Pipeline Phase 3 when run in context, or on-demand anytime.

## 1. Argument Parsing

Parse the first argument as the review target:

- **`plan`** (default) -- Review the implementation plan.
- **`code`** -- Review the codebase against the plan.
- **`section <name>`** -- Review a specific section against its spec.

If no target, default to `plan`.

## 2. Detect Context: Pipeline vs On-Demand

**Pipeline (Phase 3)**: `.ralph-state/pipeline.json` exists AND `current_phase` is `"review"` AND target is `plan`.

Read pipeline state:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh read . current_phase
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh read . review_tier
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh read . available_reviewers
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh read . max_review_iterations
```

**On-demand**: Everything else.

### Pipeline Mode (Phase 3)

1. Follow the angry-ralph skill's Phase 3 (ADVERSARIAL REVIEW) procedure.
2. On completion:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write_done . review
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . current_phase split
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh append . completed_phases review
```

### On-Demand Mode

1. If `.ralph-state/pipeline.json` exists, read `review_tier` and `available_reviewers`. Otherwise run `validate-env.sh`.
2. Create output directory: `.planning/reviews/on-demand/<target>-<timestamp>/`

**For `plan`**: Validate `.planning/angry-ralph-plan.md` exists. Spawn `external-reviewer` subagent with the plan file.

**For `code`**: Validate `.planning/angry-ralph-plan.md` exists. Spawn `external-reviewer` subagent for code review against plan.

**For `section <name>`**: Resolve `.planning/sections/section-<name>.md`. Spawn `external-reviewer` subagent with section spec and changed files.

In all on-demand cases: run triage (CRITICAL/WARNING/INFO), present findings. Do NOT write `.done` markers.
