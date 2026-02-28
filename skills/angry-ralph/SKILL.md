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

This verifies that required tools (`git`, `python3`, `claude`) are in PATH and detects optional external reviewers (`gemini`, `codex`). If required tools are missing, halt and report the error. The script outputs JSON to stdout with the detected `review_tier` and `available_reviewers` — store these in `.ralph-state/pipeline.json` via `pipeline.sh create`.

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
- **`--max-section-review-iterations N`** (optional, default: 2) -- Maximum number of per-section review-fix iterations during Phase 5.
- **`--max-tdd-iterations N`** (optional, default: 20) -- Maximum TDD loop iterations per section before escalating to user.
- **`--auto`** (optional) -- Skip clarifying questions and review approval. Stored in `.ralph-state/pipeline.json` as `"mode": "auto"`.

Validate that the spec file exists and is readable. Store the resolved absolute path for use across all phases.

## Phase 1: DECOMPOSE

Read the input spec file in its entirety. Identify the core problem domain, target tech stack, key features, and constraints. Note all ambiguities, missing details, and implicit assumptions.

Interview the user to resolve ambiguities. Ask clarifying questions one at a time via `AskUserQuestion` -- never batch multiple questions into a single prompt. Continue until all identified ambiguities are resolved. Write the interview transcript to `.planning/angry-ralph-interview.md`.

Evaluate whether the spec requires decomposition into multiple planning units. Apply the splitting heuristics: different domains, independently deployable components, different tech stacks, or estimated size exceeding 500 lines of code. If splitting, write a planning unit manifest to the top of the plan file. If not splitting, treat the entire spec as a single unit.

Create task list items for each planning unit to enable checkpoint tracking.

**--auto mode**: If `mode` is `"auto"` in `.ralph-state/pipeline.json`, do NOT use AskUserQuestion for the interview. Make the most secure, industry-standard architectural assumption for every ambiguity and proceed immediately. Still write interview notes documenting the assumptions made.

Consult `references/planning-protocol.md` for the detailed decomposition procedure, interview rules, and splitting heuristics.

When Phase 1 is complete, update `.ralph-state/pipeline.json`: set `current_phase` to `"plan"` and append `"decompose"` to `completed_phases`.

## Phase 2: PLAN

Write a detailed implementation plan for each planning unit. The plan must include:

- Architecture overview (system purpose, component connections, deployment model)
- Components and responsibilities (name, role, public interface for each)
- Data flow (entry points, transformations, storage, outputs)
- Error handling strategy (categories, propagation, user-facing messages, retry policy)
- Testing strategy (framework, runner command, coverage target, test categories)

Divide the plan into numbered implementation sections. Each section must define its scope, dependencies on prior sections, explicit test specifications, and acceptance criteria. Order sections so foundational components come before dependent ones.

Write the complete plan to `.planning/angry-ralph-plan.md`. Write a synthesized specification incorporating all interview answers and resolved ambiguities to `.planning/angry-ralph-spec.md`.

Run the plan quality checklist before marking Phase 2 complete: verify every component has a section, every section has test specs, section dependencies form a valid DAG, the test runner command is consistent, error handling covers all boundaries, and the synthesized spec reflects all interview answers.

Consult `references/planning-protocol.md` for the plan structure, section format, and quality checklist.

When Phase 2 is complete, update `.ralph-state/pipeline.json`: set `current_phase` to `"review"` and append `"plan"` to `completed_phases`.

## Phase 3: ADVERSARIAL REVIEW

### Transparency

Before beginning the review loop, print the active review tier to inform the user:

```
angry-ralph: Review tier — <TIER_LABEL>
Reviewers: <comma-separated list of active reviewers>
```

Read the `review_tier` and `available_reviewers` from `.ralph-state/pipeline.json` to determine which reviewers to use. Spawn the `external-reviewer` subagent, passing the active tier and available reviewers in the prompt. Before each iteration, create the review output directory: `.planning/reviews/iteration-N/`.

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

**--auto mode**: Run the full review loop and log all findings, but do NOT pause for human approval. Auto-accept and proceed to the split phase. Genuine ambiguity questions are answered with secure defaults.

Consult `references/review-protocol.md` for the triage decision tree, CLI invocation patterns, and iteration control logic.

When Phase 3 is complete, update `.ralph-state/pipeline.json`: set `current_phase` to `"split"` and append `"review"` to `completed_phases`.

## Phase 4: SPLIT

Parse the finalized plan into numbered section markdown specs. Each section spec must be self-contained and include:

- **Scope** -- Files and components created or modified
- **Dependencies** -- Prior sections that must be complete first
- **Test data contracts** -- YAML data contracts defining `input` payloads and `expected_output` or `expected_error` for each test. No language-specific syntax. Each contract has a test name (becomes the function name), input args, and expected results. The implementation subagent translates contracts into the project's test framework. If a section spec has no data contracts, it is incomplete — fix it before proceeding to Phase 5.
- **Acceptance criteria** -- Concrete conditions that mark the section as complete

### Output Files

Write each section spec to `.planning/sections/` with the naming convention:

```
.planning/sections/section-01-name.md
.planning/sections/section-02-name.md
.planning/sections/section-03-name.md
```

Use kebab-case for the name portion. Derive section names from the plan's `## Section N: <Name>` headers.

### Manifest

Write a section manifest to `.planning/sections/index.md` listing all sections in execution order with:

- Section number and name
- Brief scope description (1 sentence)
- Dependencies (by section number)
- Status (initially `pending` for all)

The manifest serves as the single source of truth for section ordering and completion tracking.

When Phase 4 is complete, update `.ralph-state/pipeline.json`: set `current_phase` to `"execute"` and append `"split"` to `completed_phases`.

## Phase 5: EXECUTE (Ralph Loop + TDD)

For each section in the order defined by the manifest:

### 1. Activate the Ralph Loop

Create or update the state file at `.ralph-state/loop.md` with:

```yaml
active: true
phase: execute
iteration: 1
current_section: section-NN-name
completion_promise: SECTION_COMPLETE
```

Set `spec_file` and `planning_dir` to the resolved paths. Populate the prompt body with the section spec content and TDD instructions.

### 2. Dispatch Section to Subagent

Dispatch each section's implementation to a **fresh subagent** via the Task tool. The subagent receives:

- The full section spec content
- The test runner command
- The TDD protocol (red-green cycle rules)
- Instructions to output `SECTION_COMPLETE` only when all tests pass

The main session stays lean — it manages coordination, state transitions, and section dispatch. The subagent gets a clean context window with no accumulated history from prior sections or planning phases.

The **SubagentStop hook** (registered alongside the Stop hook, both pointing to the same `stop-hook.sh`) gates the subagent's exit. If the completion promise is not found in the subagent's transcript, the hook blocks exit and feeds back the section prompt for another iteration.

### 3. Follow TDD: Red-Green Cycle

**Red phase** -- Write test cases that verify the expected behavior described in the section spec. Run the test suite and confirm the tests fail. If any test passes before implementation exists, rewrite the test to exercise the unimplemented behavior.

**Green phase** -- Write the minimum code needed to make all failing tests pass. Run the test suite and confirm all tests pass. If tests fail, debug and fix the implementation -- not the tests. Repeat until every assertion is green.

### 4. Completion Gate

Output the completion promise `SECTION_COMPLETE` only when ALL of the following hold:

- The test runner exits with code 0
- Every assertion passes (no skipped or ignored tests)
- No compilation or runtime errors during test execution
- The implementation satisfies the section spec's acceptance criteria

If the SubagentStop hook detects that `iteration >= max_tdd_iterations` (from `.ralph-state/pipeline.json`, default 20), it allows exit with a `tdd_cap_reached` signal instead of blocking. The main session then asks the user via `AskUserQuestion`: "Section X failed after N TDD iterations. Review errors, skip section, or keep trying (+10 iterations)?"

- **Skip section**: Mark the section as `failed` in `.planning/sections/index.md` and advance to the next section.
- **Keep trying**: Add 10 to `max_tdd_iterations` in `.ralph-state/pipeline.json` and re-dispatch the subagent.
- **Review errors**: Display the last test output for user inspection before deciding.

### 5. Mechanical Gates

After the SubagentStop hook permits exit, run the mechanical gate script BEFORE the AI review:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/lib/mechanical-gates.sh run_all "<test_runner_command>" "<section-spec-path>" "<project-dir>"
```

Three gates, all dumb bash — no AI judgment:

1. **Stub grep** -- `TODO`, `FIXME`, `XXX`, `HACK`, `NotImplementedError`, `pass$` in changed source files. Any match = fail.
2. **Test verification** -- Re-run tests. Exit 0 + at least one test ran. Empty test suite = fail.
3. **Contract compliance** -- Every test function name from the section spec's data contracts must exist in the test files.

If the script exits non-zero: increment `iteration`, feed the gate output back, re-enter TDD loop. Only proceed to the AI review when the script exits 0.

Consult `references/section-review-protocol.md` for gate details.

### 6. Section Review Gate

After mechanical gates pass and before committing, perform an inline code review of the section's changes. The main session executes this review directly — no subagent or external CLI.

1. Run `git diff --name-only HEAD` to identify changed files.
2. Read each changed file and the current section spec.
3. Evaluate against the review checklist (plan-vs-code fidelity, implementation substance, algorithm correctness, test quality, integration readiness).
4. Tag findings as `[CRITICAL]`, `[WARNING]`, or `[INFO]`.

**If CRITICAL or actionable WARNING findings exist:**

1. Write findings to `.planning/reviews/sections/<section-name>/review-N.md`.
2. Swap `completion_promise` to `SECTION_REVIEW_FIX_COMPLETE` and update `review_iteration` in the state file.
3. Dispatch a fresh fix subagent with the findings, section spec, and instructions to fix issues and output `SECTION_REVIEW_FIX_COMPLETE` when tests pass.
4. After the fix subagent exits, re-review. Repeat up to `max_section_review_iterations` times (default: 2, from `.ralph-state/pipeline.json`).
5. When clean or cap reached, restore `completion_promise` to `SECTION_COMPLETE` and reset `review_iteration` to 0.

If the iteration cap is reached with findings still open, log them and proceed to commit. Do not prompt the user.

Consult `references/section-review-protocol.md` for the full review checklist, severity definitions, fix cycle, and output format.

### 7. Atomic Commit

After a section passes all mechanical gates and the review gate clears:

- Stage only the files changed for the completed section
- Commit with message format: `feat(section-NN): <section-name>`
- Do not stage unrelated files or amend previous commits

**If the commit fails** (non-zero exit code from `git commit`):

1. Read the git error output.
2. Ask the user via `AskUserQuestion`: "Commit failed for section-NN: <git error summary>. Options: resolve manually and retry, or skip commit and continue?"
3. If the user resolves manually: verify commit succeeded with `git log -1`, then proceed.
4. If the user skips: log the skip, advance to the next section. The section's code remains unstaged.

Do not silently ignore commit failures. Do not proceed to the next section until the commit succeeds or the user explicitly skips.

### 8. Advance to Next Section

Update the state file: set `current_section` to the next section, reset `iteration` to 1, and replace the prompt body with the next section's spec. If no sections remain, proceed to Phase 6.

Consult `references/tdd-protocol.md` for TDD red-green cycle rules, test command detection, and completion promise constraints.

Consult `references/loop-protocol.md` for state file format, loop lifecycle, section transitions, and atomic commit rules.

When Phase 5 is complete (all sections executed), update `.ralph-state/pipeline.json`: set `current_phase` to `"final_review"` and append `"execute"` to `completed_phases`.

## Phase 6: FINAL REVIEW

Initiate final review only after every implementation section has been completed and committed with all tests passing.

### Transparency

Print the active review tier before spawning the reviewer, same as Phase 3.

### Self-Healing Review Loop

Phase 6 uses a review-fix-review loop — it does NOT declare completion after a single triage pass. The loop ensures fixes are verified and don't introduce new issues.

For each iteration (up to `max_review_iterations`, default 3):

1. Create the review directory: `mkdir -p .planning/reviews/final/iteration-N/`
2. Spawn the `external-reviewer` subagent with review type `"final integration review"`.
3. Provide the subagent with the active review tier, available reviewers, project directory path, plan file path, and sections directory.
4. The subagent invokes the available reviewers, focusing on integration bugs, security vulnerabilities, plan-vs-code gaps, and missing error handling. All findings tagged with source.
5. Triage all findings: fix CRITICAL immediately, evaluate WARNING, resolve clear questions, escalate genuine ambiguity via `AskUserQuestion`.
6. If zero CRITICAL and zero actionable WARNING findings remain — break. Review is clean.
7. If findings were fixed: re-run the full test suite, commit fixes as `fix: address final review findings (iteration N)`, then loop back to step 1 for re-review.

### Iteration Cap

When `max_review_iterations` is exhausted with findings still open:
- Log remaining findings to `.planning/reviews/final/unresolved.md`
- Proceed to completion — do NOT block the pipeline
- The unresolved file serves as a production roadmap

### Pipeline Completion

Produce a summary report at `.planning/reviews/final/review-summary.md`: total iterations, findings per severity, fixes with commits, unresolved items.

Deactivate the state file by setting `active=false` or removing it entirely. Update `.ralph-state/pipeline.json`: set `current_phase` to `"complete"` and append `"final_review"` to `completed_phases`. Report full pipeline completion to the user. List every commit made during the session in chronological order.

Consult `references/final-review-protocol.md` for the complete final review loop, triage decision tree, fix rules, and completion steps.

## Diagnosis Mode (/angry-diagnose)

When invoked via `/angry-diagnose`, the pipeline runs a 4-phase diagnosis workflow instead of the standard 6-phase spec-to-code pipeline. The command file handles setup and creates pipeline.json with `mode: "diagnose"`.

### Phase 1: INVESTIGATE

Build a case file from the user's problem description and any provided context files. Gather relevant source files, trace dependencies, check recent git history, and optionally interview the user.

Output: `.planning/diagnosis/case-file.md`

### Phase 2: DIAGNOSE (Differential Diagnosis)

Spawn the `external-reviewer` subagent with a diagnosis-specific prompt (not the standard plan/code review prompt). Each reviewer generates at least 3 competing hypotheses for the root cause, including at least 1 non-obvious hypothesis. Merge, deduplicate, rank by consensus and evidence strength, cap at `max_hypotheses`.

Output: `.planning/diagnosis/hypotheses.md`

### Phase 3: FIX (Hypothesis-Driven TDD)

For each hypothesis in rank order, write a diagnostic test designed to prove/disprove it. Run the test: if it fails, the hypothesis is confirmed; if it passes, it's eliminated. Once a root cause is confirmed, implement the minimum fix to make the failing diagnostic test pass. Run full test suite.

Output: `.planning/diagnosis/fix-report.md`

### Phase 4: VERIFY (Adversarial Verification)

Run mechanical gates (stub check + test verify, skip spec compliance). Spawn `external-reviewer` with a verification prompt challenging the fix. Triage findings per `references/review-protocol.md`. Atomic commit on success.

### Detailed Procedure

Consult `references/diagnosis-protocol.md` for the complete diagnosis procedure, including:
- Case file structure and context gathering rules
- Diagnosis prompt template for external reviewers
- Hypothesis merge/rank/cap algorithm
- Systematic elimination via diagnostic tests
- Fix report format
- Verification prompt and iteration control

## State Management

### State File (Ralph Loop)

The Ralph Loop state file lives at `.ralph-state/loop.md`. Managed via `scripts/lib/state.sh`.

### Pipeline Config

Pipeline configuration lives at `.ralph-state/pipeline.json`. Managed via `scripts/lib/pipeline.sh`.

### Done Markers

Phase completion tracked by marker files in `.ralph-state/phases/`:
- `architect.done` -- Phases 1-2 complete
- `review.done` -- Phase 3 complete
- `execute.done` -- Phases 4-6 complete

Diagnosis mode (`/angry-diagnose`) uses its own markers:
- `investigate.done` -- Phase 1 complete
- `diagnose.done` -- Phase 2 complete
- `fix.done` -- Phase 3 complete

Managed via `pipeline.sh write_done|check_done|remove_done`.

### Phase Transition Tracking

At each phase boundary, update via pipeline.sh:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . current_phase <phase_name>
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh append . completed_phases <previous_phase>
```

### Task List

Maintain task list items for each phase and section. Update task status as work progresses. The task list enables checkpoint recovery after `/clear` by providing a persistent record of what has been completed.

## Resume & Recovery

### Detecting Existing State

On re-invocation, check `.ralph-state/` for prior state:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh check_done . architect
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh check_done . review
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh check_done . execute
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh read . current_phase
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh read . completed_sections
```

Also check if `.ralph-state/loop.md` exists with `active=true` for mid-section resume.

### Resume Logic

- `.done` markers determine which phases are complete
- `pipeline.json` `current_phase` and `completed_sections` provide finer-grained resume
- Active `loop.md` indicates mid-section TDD resume
- Offer user choice: resume or start fresh

## Additional Resources

All detailed procedures are defined in the reference protocol files. Consult these for step-by-step instructions, decision trees, and rules that govern each phase:

- **`references/planning-protocol.md`** -- Decomposition and plan writing procedures. Covers the full interview process, splitting heuristics, plan structure with section format, and the quality checklist.
- **`references/review-protocol.md`** -- Review loop and triage rules. Defines review tier detection, CLI invocation patterns for gemini, codex, and claude fallback, source attribution tags, the triage decision tree, and iteration control logic.
- **`references/tdd-protocol.md`** -- Test-driven development enforcement. Specifies the red-green cycle, test command detection, definition of "tests pass," completion promise rules, and handling of test failures and flaky tests.
- **`references/loop-protocol.md`** -- Ralph Loop state machine and lifecycle. Documents the state file format, field definitions, loop activation, section-to-section transitions, atomic commit rules, and the cancel mechanism.
- **`references/section-review-protocol.md`** -- Per-section code review gate. Defines the inline review checklist, severity tags, fix subagent dispatch with promise swap, iteration cap, and output storage.
- **`references/final-review-protocol.md`** -- Integration review procedure. Covers trigger conditions, CLI review focus areas, triage logic, post-triage actions, and pipeline completion reporting.
- **`references/diagnosis-protocol.md`** -- Adversarial bug diagnosis procedure. Covers case file construction, diagnosis prompt template for external reviewers, hypothesis merge/rank/cap algorithm, systematic elimination via diagnostic tests, fix report format, and verification iteration control.
