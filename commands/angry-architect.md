---
name: angry-architect
description: Run Phases 1-2 (Decompose + Plan) of the angry-ralph pipeline
---

# /angry-architect Command

Run Phases 1-2 only: Decompose the spec and write the implementation plan.

## 1. Argument Parsing

- **`@file.md`** (required) -- Input specification file.
- **`--auto`** (optional) -- Skip clarifying questions.

If no `@file.md` is provided:

```
Usage: /angry-architect @spec.md [--auto]
```

Validate spec file exists. Resolve absolute path.

## 2. Environment Validation

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/checks/validate-env.sh
```

Halt on failure. Confirm git repo.

## 3. Migration

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh migrate .
```

## 4. Resume Detection

Check `.ralph-state/phases/architect.done`:
- If exists → "Phases 1-2 already complete. Plan at .planning/angry-ralph-plan.md." Stop.
- If `.ralph-state/pipeline.json` exists with `current_phase` beyond `plan` → offer resume.

## 5. Setup

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh create . "<SPEC_FILE>" "<MODE>" "<MAX_REVIEW>" "<MAX_SECTION_REVIEW>" "<MAX_TDD>" "<REVIEW_TIER>" "<AVAILABLE_REVIEWERS>"
mkdir -p .planning/reviews .planning/sections
```

Set `<MODE>` to `auto` if `--auto` passed, otherwise `interactive`.

## 6. Execute Phases 1-2

Follow the angry-ralph skill's Phase 1 (DECOMPOSE) and Phase 2 (PLAN) instructions.

When Phase 2 is complete:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write_done . architect
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . current_phase review
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh append . completed_phases decompose
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh append . completed_phases plan
```

Report: "Phases 1-2 complete. Run /angry-review plan to review, or /angry-execute to proceed."
