---
name: angry-ralph-help
description: Show angry-ralph plugin documentation and usage
---

# angry-ralph Help

## What is angry-ralph?

angry-ralph is a unified multi-LLM planning and TDD execution pipeline. It transforms a feature specification into fully implemented, reviewed, and tested code by combining adversarial review via the `gemini` and `codex` CLIs with a built-in Ralph Loop that enforces iterative test-driven development. Every phase produces persistent artifacts, enabling resume and recovery after interruptions.

## Commands

| Command | Description |
|---------|-------------|
| `/angry-ralph @spec.md [--max-review-iterations N]` | Start the pipeline against a spec file |
| `/cancel-ralph` | Cancel the active Ralph Loop |
| `/angry-ralph-help` | Show this help |

## The 6-Phase Workflow

1. **Phase 1: DECOMPOSE** -- Interview the user to clarify ambiguities in the spec.
   Break the spec into planning units based on domain boundaries, deployment targets,
   and estimated size.

2. **Phase 2: PLAN** -- Write a detailed implementation plan with architecture overview,
   component responsibilities, data flow, error handling, testing strategy, and numbered
   implementation sections.

3. **Phase 3: REVIEW** -- Run an adversarial review loop dispatching the
   `external-reviewer` subagent to invoke `gemini` and `codex` against the plan.
   Triage findings by severity (CRITICAL / WARNING / INFO) and iterate until the
   review is clean or max iterations are reached.

4. **Phase 4: SPLIT** -- Finalize the reviewed plan into numbered, self-contained
   section markdown specs under `planning/sections/`, each with scope, dependencies,
   test specifications, and acceptance criteria.

5. **Phase 5: EXECUTE** -- Run the Ralph Loop for each section in order. Each section
   follows a strict TDD red-green cycle: write failing tests first, then implement
   until all tests pass. The loop is test-gated with no iteration cap -- sections
   complete only when the test runner exits cleanly.

6. **Phase 6: FINAL REVIEW** -- Run a full integration review over the completed
   codebase using `gemini` and `codex`, focusing on cross-section integration bugs,
   security vulnerabilities, and plan-vs-code gaps.

## Prerequisites

- **`gemini` CLI** -- Installed and available in PATH
- **`codex` CLI** -- Installed and available in PATH
- **`git`** -- Installed and available in PATH
- **Git repository** -- The current working directory must be inside a git repository

Run the environment validation script to check all prerequisites:

```
angry-ralph/scripts/checks/validate-env.sh
```

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `--max-review-iterations N` | `3` | Max adversarial review rounds in Phase 3 and Phase 6 |

When the maximum review iterations are reached without a clean review, remaining open
items are presented to the user for a proceed-or-continue decision.

The execution loop (Phase 5) has **no iteration cap**. It is purely test-gated: each
section loops until all tests pass and the completion promise is emitted.

## Resume

Re-running `/angry-ralph @spec.md` on a project with existing pipeline artifacts will detect the prior session and offer to resume from the last checkpoint. Resume detection checks:

- The `.claude/angry-ralph.local.md` state file for active phase and section
- The `planning/config.json` for session configuration
- The `planning/` directory for completed plan, review, and section artifacts
- The git log for `feat(section-NN)` commits indicating completed sections

No work is repeated -- the pipeline picks up exactly where it left off.
