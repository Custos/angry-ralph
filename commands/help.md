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
| `/angry-ralph @spec.md [options]` | Start the pipeline against a spec file |
| `/cancel-ralph` | Cancel the active Ralph Loop |
| `/review-code` | On-demand adversarial review of code against the plan |
| `/review-plan` | On-demand adversarial review of the implementation plan |
| `/review-section <name-or-number>` | On-demand adversarial review of a specific section |
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
   until all tests pass. After TDD passes, an inline review gate checks the code
   against the section spec for stubs, plan-vs-code gaps, and test quality. Issues
   trigger a fix subagent and re-review (up to N iterations, default 2).

6. **Phase 6: FINAL REVIEW** -- Run a self-healing review loop over the completed
   codebase using `gemini` and `codex`. Finds integration bugs, security
   vulnerabilities, and plan-vs-code gaps, then fixes them, re-reviews to verify,
   and repeats until clean or max iterations reached (default 3).

## Prerequisites

**Required:**
- **`claude`** -- Claude Code CLI, installed and available in PATH
- **`git`** -- Installed and available in PATH
- **`python3`** -- Installed and available in PATH
- **Git repository** -- The current working directory must be inside a git repository

**Optional (upgrades review tier):**
- **`gemini` CLI** -- Enables adversarial review via Gemini
- **`codex` CLI** -- Enables adversarial review via Codex

The plugin works out-of-the-box with only the required tools. External CLIs upgrade the review from Self-Reflection (Claude only) to Partial (one CLI + Claude) or Adversarial (both CLIs).

Run the environment validation script to check all prerequisites:

```
angry-ralph/scripts/checks/validate-env.sh
```

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `--max-review-iterations N` | `3` | Max adversarial review rounds in Phase 3 and Phase 6 |
| `--max-section-review-iterations N` | `2` | Max per-section review-fix iterations in Phase 5 |
| `--max-tdd-iterations N` | `20` | Max TDD loop iterations per section before escalating |

When the maximum review iterations are reached without a clean review, remaining open
items are presented to the user for a proceed-or-continue decision.

The TDD loop within each section (Phase 5) has a configurable iteration cap (default 20,
via `--max-tdd-iterations`). When the cap is reached, the pipeline asks the user whether
to skip the section, keep trying (+10 iterations), or review the errors. The section review gate that runs after TDD passes has a configurable cap
(default 2). If the cap is reached with findings still open, they are logged and the
pipeline proceeds.

## Resume

Re-running `/angry-ralph @spec.md` on a project with existing pipeline artifacts will detect the prior session and offer to resume from the last checkpoint. Resume detection checks:

- The `.claude/angry-ralph.local.md` state file for active phase and section
- The `planning/config.json` for session configuration
- The `planning/` directory for completed plan, review, and section artifacts
- The git log for `feat(section-NN)` commits indicating completed sections

No work is repeated -- the pipeline picks up exactly where it left off.
