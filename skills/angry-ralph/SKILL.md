---
name: angry-ralph
description: This skill should be used when the user asks to "run angry-ralph", "plan and implement a feature", "start the planning pipeline", "decompose and build", or invokes the /angry-ralph command. Orchestrates a 6-phase pipeline from decomposition through adversarial multi-LLM review to TDD execution via Ralph Loop.
version: 0.1.0
---

# angry-ralph: Master Orchestration Skill

## Overview

angry-ralph is a unified pipeline that transforms a feature spec into a fully implemented, reviewed, and tested codebase through six sequential phases: decomposition, planning, adversarial review, section splitting, TDD execution, and final integration review. It combines deep project analysis with multi-LLM adversarial scrutiny by dispatching the `external-reviewer` subagent to invoke the `gemini` and `codex` CLIs against plans and code. The Ralph Loop state machine enforces test-driven development during execution, gating section completion on all tests passing before allowing progression. Every phase produces persistent artifacts, enabling resume and recovery after interruptions.

## Prerequisites

### Environment Validation

Run the environment validation script before proceeding with any phase:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/checks/validate-env.sh
```

This verifies that required tools (`git`, `python3`, `claude`) are in PATH and detects optional external reviewers (`gemini`, `codex`). If required tools are missing, halt and report the error. The script outputs JSON to stdout with the detected `review_tier` and `available_reviewers` — store these in `planning/config.json` for use during review phases.

**Review Tiers:**

| Tier | Condition | Reviewers |
|------|-----------|-----------|
| **Adversarial** | gemini + codex available | gemini, codex |
| **Partial** | one external CLI available | available CLI + claude fallback |
| **Self-Reflection** | no external CLIs | claude only (fresh session) |

The plugin works out-of-the-box with zero external CLIs. External tools upgrade the review quality but are not required.

### Git Repository

Confirm the current working directory is a git repository. Run `git rev-parse --is-inside-work-tree` and check for exit code 0. If not inside a git repo, ask the user whether to initialize one with `git init`. Do not initialize without explicit user consent.

### Command Arguments

Parse the invocation arguments:

- **`@file.md`** (required) -- Path to the input specification file. Reject invocation if no spec file is provided.
- **`--max-review-iterations N`** (optional, default: 3) -- Maximum number of adversarial review iterations in Phase 3 and Phase 6.

Validate that the spec file exists and is readable. Store the resolved absolute path for use across all phases.

## Phase 1: DECOMPOSE

Read the input spec file in its entirety. Identify the core problem domain, target tech stack, key features, and constraints. Note all ambiguities, missing details, and implicit assumptions.

Interview the user to resolve ambiguities. Ask clarifying questions one at a time via `AskUserQuestion` -- never batch multiple questions into a single prompt. Continue until all identified ambiguities are resolved. Write the interview transcript to `planning/angry-ralph-interview.md`.

Evaluate whether the spec requires decomposition into multiple planning units. Apply the splitting heuristics: different domains, independently deployable components, different tech stacks, or estimated size exceeding 500 lines of code. If splitting, write a planning unit manifest to the top of the plan file. If not splitting, treat the entire spec as a single unit.

Create task list items for each planning unit to enable checkpoint tracking.

Consult `references/planning-protocol.md` for the detailed decomposition procedure, interview rules, and splitting heuristics.

## Phase 2: PLAN

Write a detailed implementation plan for each planning unit. The plan must include:

- Architecture overview (system purpose, component connections, deployment model)
- Components and responsibilities (name, role, public interface for each)
- Data flow (entry points, transformations, storage, outputs)
- Error handling strategy (categories, propagation, user-facing messages, retry policy)
- Testing strategy (framework, runner command, coverage target, test categories)

Divide the plan into numbered implementation sections. Each section must define its scope, dependencies on prior sections, explicit test specifications, and acceptance criteria. Order sections so foundational components come before dependent ones.

Write the complete plan to `planning/angry-ralph-plan.md`. Write a synthesized specification incorporating all interview answers and resolved ambiguities to `planning/angry-ralph-spec.md`.

Run the plan quality checklist before marking Phase 2 complete: verify every component has a section, every section has test specs, section dependencies form a valid DAG, the test runner command is consistent, error handling covers all boundaries, and the synthesized spec reflects all interview answers.

Consult `references/planning-protocol.md` for the plan structure, section format, and quality checklist.

## Phase 3: ADVERSARIAL REVIEW

### Transparency

Before beginning the review loop, print the active review tier to inform the user:

```
angry-ralph: Review tier — <TIER_LABEL>
Reviewers: <comma-separated list of active reviewers>
```

Read the `review_tier` and `available_reviewers` from `planning/config.json` to determine which reviewers to use. Spawn the `external-reviewer` subagent, passing the active tier and available reviewers in the prompt. Before each iteration, create the review output directory: `planning/reviews/iteration-N/`.

The subagent produces structured markdown with `## Findings` (tagged with source attribution `[Gemini]`, `[Codex]`, or `[Claude-Reflection]` AND severity `[CRITICAL]`, `[WARNING]`, `[INFO]`), `## Questions`, and `## Summary`.

### Triage Decision Tree

Process each finding and question from the review payload:

1. **[CRITICAL] findings** -- Fix the plan immediately. These block progression.
2. **[WARNING] findings** -- Evaluate severity. Fix if the warning represents a real risk to correctness, security, or reliability. Document rationale for any warning left unaddressed.
3. **Questions with clear answers** -- Resolve from available context (the spec, plan, project knowledge). Update the plan so the question does not recur.
4. **Questions with genuine ambiguity** -- MANDATORY: use `AskUserQuestion` to pause and get user input. Do not guess. Do not fabricate. Do not assume. Wait for the user response before continuing.
5. **[INFO] items** -- Note for awareness. Do not block on these.

### HARD RULE

If any question from Gemini or Codex reveals genuine ambiguity that cannot be resolved from available context, pause and ask the user via `AskUserQuestion`. This is non-negotiable. No guessing, no fabricating, no assuming.

### Iteration Control

Track iteration count against `--max-review-iterations` (default 3). Exit the review loop early when a review iteration returns zero CRITICAL findings, zero WARNING findings, and zero unresolved questions. When max iterations are reached without a clean review, present the remaining open items to the user and ask via `AskUserQuestion` whether to proceed to the split phase or continue reviewing.

Consult `references/review-protocol.md` for the triage decision tree, CLI invocation patterns, and iteration control logic.

## Phase 4: SPLIT

Parse the finalized plan into numbered section markdown specs. Each section spec must be self-contained and include:

- **Scope** -- Files and components created or modified
- **Dependencies** -- Prior sections that must be complete first
- **Test specifications** -- Explicit list of tests with names, inputs, expected behavior, and runner command
- **Acceptance criteria** -- Concrete conditions that mark the section as complete

### Output Files

Write each section spec to `planning/sections/` with the naming convention:

```
planning/sections/section-01-name.md
planning/sections/section-02-name.md
planning/sections/section-03-name.md
```

Use kebab-case for the name portion. Derive section names from the plan's `## Section N: <Name>` headers.

### Manifest

Write a section manifest to `planning/sections/index.md` listing all sections in execution order with:

- Section number and name
- Brief scope description (1 sentence)
- Dependencies (by section number)
- Status (initially `pending` for all)

The manifest serves as the single source of truth for section ordering and completion tracking.

## Phase 5: EXECUTE (Ralph Loop + TDD)

For each section in the order defined by the manifest:

### 1. Activate the Ralph Loop

Create or update the state file at `.claude/angry-ralph.local.md` with:

```yaml
active: true
phase: execute
iteration: 1
current_section: section-NN-name
completion_promise: SECTION_COMPLETE
```

Set `spec_file` and `planning_dir` to the resolved paths. Populate the prompt body with the section spec content and TDD instructions.

### 2. Follow TDD: Red-Green Cycle

**Red phase** -- Write test cases that verify the expected behavior described in the section spec. Run the test suite and confirm the tests fail. If any test passes before implementation exists, rewrite the test to exercise the unimplemented behavior.

**Green phase** -- Write the minimum code needed to make all failing tests pass. Run the test suite and confirm all tests pass. If tests fail, debug and fix the implementation -- not the tests. Repeat until every assertion is green.

### 3. Completion Gate

Output the completion promise `SECTION_COMPLETE` only when ALL of the following hold:

- The test runner exits with code 0
- Every assertion passes (no skipped or ignored tests)
- No compilation or runtime errors during test execution
- The implementation satisfies the section spec's acceptance criteria

The stop hook intercepts exit attempts and checks the transcript for the completion promise. If the promise is not found, the hook blocks exit and feeds back the section prompt for another iteration.

### 4. Atomic Commit

After a section passes all tests and the stop hook permits exit:

- Stage only the files changed for the completed section
- Commit with message format: `feat(section-NN): <section-name>`
- Do not stage unrelated files or amend previous commits

### 5. Advance to Next Section

Update the state file: set `current_section` to the next section, reset `iteration` to 1, and replace the prompt body with the next section's spec. If no sections remain, proceed to Phase 6.

Consult `references/tdd-protocol.md` for TDD red-green cycle rules, test command detection, and completion promise constraints.

Consult `references/loop-protocol.md` for state file format, loop lifecycle, section transitions, and atomic commit rules.

## Phase 6: FINAL REVIEW

Initiate final review only after every implementation section has been completed and committed with all tests passing.

### Transparency

Print the active review tier before spawning the reviewer, same as Phase 3.

### Procedure

1. Create the final review directory: `mkdir -p planning/reviews/final/`
2. Spawn the `external-reviewer` subagent with review type set to `"final integration review"`.
3. Provide the subagent with the active review tier, available reviewers, project directory path, plan file path, and sections directory.
4. The subagent invokes the available reviewers based on the active tier, focusing on integration bugs, emergent security vulnerabilities, plan-vs-code gaps, and missing error handling. All findings are tagged with their source (`[Gemini]`, `[Codex]`, or `[Claude-Reflection]`).

### Triage

Apply the same triage decision tree as Phase 3. Fix all CRITICAL issues immediately, evaluate WARNING items, resolve clear questions autonomously, and escalate genuine ambiguities to the user via `AskUserQuestion` (MANDATORY).

### After Triage

If any fixes were made, re-run the full test suite to confirm no regressions. Commit all fixes together: `fix: address final review findings`.

Produce a summary report: total findings per severity, what was fixed with corresponding commits, what was noted but not actionable, and any remaining known limitations.

### Pipeline Completion

Deactivate the state file by setting `active=false` or removing it entirely. Report full pipeline completion to the user. List every commit made during the session in chronological order.

Consult `references/final-review-protocol.md` for the complete final review procedure, CLI focus areas, and completion steps.

## State Management

### State File

The Ralph Loop state file lives at `.claude/angry-ralph.local.md`. It uses YAML frontmatter between `---` markers followed by a prompt body. Key fields:

- `active` -- Whether the loop is running (`true` / `false`)
- `phase` -- Current pipeline phase (`plan`, `review`, `split`, `execute`, `final_review`)
- `iteration` -- Current iteration number within the active phase
- `max_iterations` -- Maximum iterations allowed (0 = unlimited, test-gated only)
- `current_section` -- Section identifier being implemented during execute phase
- `completion_promise` -- Exact string required in transcript to permit exit
- `started_at` -- ISO 8601 timestamp of activation
- `spec_file` -- Absolute path to the original spec file
- `planning_dir` -- Absolute path to the planning directory

### Session Config

Store session configuration in `planning/config.json` for resume support. Include:

- Original spec file path
- Max review iterations setting
- Pipeline start timestamp
- Current phase at time of last checkpoint
- List of completed phases

### Task List

Maintain task list items for each phase and section. Update task status as work progresses. The task list enables checkpoint recovery after `/clear` by providing a persistent record of what has been completed.

## Resume & Recovery

### Detecting Existing State

On re-invocation, check for existing pipeline artifacts before starting fresh:

1. Check if `planning/` directory exists.
2. Check if `.claude/angry-ralph.local.md` exists and read its fields.
3. Check if `planning/config.json` exists.

### Resume from State File

If the state file exists with `active=true`:

- Read the `phase` field to determine the current pipeline phase.
- Read `current_section` to determine position within the execute phase.
- Resume from the exact point indicated. Do not repeat completed work.

### Resume from File Artifacts

If planning files exist but no state file is present:

- Check for `planning/angry-ralph-plan.md` -- if present, Phase 1 and Phase 2 are complete.
- Check for `planning/reviews/` directories -- if present, count completed review iterations.
- Check for `planning/sections/index.md` -- if present, Phase 4 (SPLIT) is complete.
- Check for `feat(section-NN)` commits in git log -- determine which sections have been executed.
- Reconstruct the pipeline position from these artifacts and resume accordingly.

### Recovery After `/clear`

After a `/clear` command resets conversation context:

- Read the task list to reconstruct workflow position.
- Read the state file for current phase and section.
- Read `planning/config.json` for session configuration.
- Combine these sources to resume without repeating completed work.
- Report the detected state to the user before continuing.

## Additional Resources

All detailed procedures are defined in the reference protocol files. Consult these for step-by-step instructions, decision trees, and rules that govern each phase:

- **`references/planning-protocol.md`** -- Decomposition and plan writing procedures. Covers the full interview process, splitting heuristics, plan structure with section format, and the quality checklist.
- **`references/review-protocol.md`** -- Review loop and triage rules. Defines review tier detection, CLI invocation patterns for gemini, codex, and claude fallback, source attribution tags, the triage decision tree, and iteration control logic.
- **`references/tdd-protocol.md`** -- Test-driven development enforcement. Specifies the red-green cycle, test command detection, definition of "tests pass," completion promise rules, and handling of test failures and flaky tests.
- **`references/loop-protocol.md`** -- Ralph Loop state machine and lifecycle. Documents the state file format, field definitions, loop activation, section-to-section transitions, atomic commit rules, and the cancel mechanism.
- **`references/final-review-protocol.md`** -- Integration review procedure. Covers trigger conditions, CLI review focus areas, triage logic, post-triage actions, and pipeline completion reporting.
