# CLI Architecture Overhaul Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace 10 messy commands with 7 clean, composable phase commands. Migrate state from `.claude/angry-ralph.local.md` + `planning/config.json` to unified `.ralph-state/` directory. Add `--auto` mode, `--help` flag, `--rebuild` flag, and `/angry-fix` surgical TDD command.

**Architecture:** Bottom-up: migrate state infrastructure first (paths, tests, hook), then kill old commands, create new commands, update protocols and docs. Every task is backwards-compatible until the final cleanup.

**Tech Stack:** Bash (state.sh, stop-hook.sh, tests), Markdown (commands, skill, protocols), JSON (hooks.json, plugin.json)

---

### Task 1: Migrate state.sh path + add pipeline.json helpers

The state library currently hardcodes no paths (it takes `$file` args), so it needs no path changes itself. But the tests use `.claude/angry-ralph.local.md` as the test path — update to `.ralph-state/loop.md`. Also add a `create_pipeline_json` helper function to state.sh for the new `.ralph-state/pipeline.json`.

**Files:**
- Modify: `scripts/lib/state.sh:42-73` (add `create_pipeline_json` function)
- Modify: `tests/test-state.sh:8` (change `STATE_FILE` path)

**Step 1: Update test-state.sh to use new path**

In `tests/test-state.sh`, change line 8:

```bash
# OLD:
STATE_FILE="$TEST_DIR/.claude/angry-ralph.local.md"
# NEW:
STATE_FILE="$TEST_DIR/.ralph-state/loop.md"
```

Also change `mkdir -p "$TEST_DIR/.claude"` (line 32) to `mkdir -p "$TEST_DIR/.ralph-state"`.

**Step 2: Run tests to verify they still pass**

Run: `bash tests/test-state.sh`
Expected: All 18 tests PASS (state.sh functions are path-agnostic, only the test variable changed)

**Step 3: Add `create_pipeline_json` to state.sh**

Append after the `remove_state_file` function:

```bash
create_pipeline_json() {
  local file="$1"
  local spec_file="$2"
  local mode="$3"
  local max_review_iterations="${4:-3}"
  local max_section_review_iterations="${5:-2}"
  local max_tdd_iterations="${6:-20}"
  local review_tier="${7:-self-reflection}"
  local available_reviewers="${8:-}"

  local dir
  dir=$(dirname "$file")
  mkdir -p "$dir"

  python3 -c "
import json, datetime
cfg = {
    'spec_file': '$spec_file',
    'mode': '$mode',
    'max_review_iterations': $max_review_iterations,
    'max_section_review_iterations': $max_section_review_iterations,
    'max_tdd_iterations': $max_tdd_iterations,
    'started_at': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'review_tier': '$review_tier',
    'available_reviewers': [r for r in '$available_reviewers'.split(',') if r],
    'current_phase': 'decompose',
    'completed_phases': [],
    'completed_sections': []
}
with open('$file', 'w') as f:
    json.dump(cfg, f, indent=2)
"
}
```

**Step 4: Add tests for `create_pipeline_json`**

Add after the existing tests in `test-state.sh`, before the summary:

```bash
# Test 7: create_pipeline_json creates valid JSON
PIPELINE_FILE="$TEST_DIR/.ralph-state/pipeline.json"
create_pipeline_json "$PIPELINE_FILE" "/tmp/spec.md" "interactive" "3" "2" "20" "adversarial" "gemini,codex"
assert_eq "pipeline.json exists" "true" "$([ -f "$PIPELINE_FILE" ] && echo true || echo false)"
PIPELINE_MODE=$(python3 -c "import json; print(json.load(open('$PIPELINE_FILE'))['mode'])")
assert_eq "pipeline.json mode" "interactive" "$PIPELINE_MODE"
PIPELINE_TIER=$(python3 -c "import json; print(json.load(open('$PIPELINE_FILE'))['review_tier'])")
assert_eq "pipeline.json review_tier" "adversarial" "$PIPELINE_TIER"
PIPELINE_CAP=$(python3 -c "import json; print(json.load(open('$PIPELINE_FILE'))['max_tdd_iterations'])")
assert_eq "pipeline.json max_tdd_iterations" "20" "$PIPELINE_CAP"
```

**Step 5: Run tests**

Run: `bash tests/test-state.sh`
Expected: All 22 tests PASS (18 original + 4 new)

**Step 6: Commit**

```bash
git add tests/test-state.sh scripts/lib/state.sh
git commit -m "feat: migrate state tests to .ralph-state/ path, add create_pipeline_json"
```

---

### Task 2: Migrate stop-hook.sh to .ralph-state/ paths

The stop hook reads state from `.claude/angry-ralph.local.md` and config from `planning/config.json`. Update both to `.ralph-state/loop.md` and `.ralph-state/pipeline.json`.

**Files:**
- Modify: `hooks/stop-hook.sh:17` (STATE_FILE path)
- Modify: `hooks/stop-hook.sh:33` (CONFIG_FILE path)

**Step 1: Update test-stop-hook.sh to use new paths**

In `tests/test-stop-hook.sh`:
- Line 9: Change `STATE_FILE="$TEST_DIR/.claude/angry-ralph.local.md"` to `STATE_FILE="$TEST_DIR/.ralph-state/loop.md"`
- Line 68: Change `mkdir -p "$TEST_DIR/.claude"` to `mkdir -p "$TEST_DIR/.ralph-state"`
- Line 149: Change `mkdir -p "$TEST_DIR/.claude"` to `mkdir -p "$TEST_DIR/.ralph-state"`
- Lines 153-154: Change `mkdir -p "$TEST_DIR/planning"` + config path to `"$TEST_DIR/.ralph-state"` (pipeline.json already in .ralph-state/)

For the TDD cap test (Test 8), update the config path:
```bash
# OLD:
mkdir -p "$TEST_DIR/planning"
echo '{"max_tdd_iterations": 20}' > "$TEST_DIR/planning/config.json"
# NEW:
echo '{"max_tdd_iterations": 20}' > "$TEST_DIR/.ralph-state/pipeline.json"
```

**Step 2: Run tests to verify they fail (paths don't match yet)**

Run: `bash tests/test-stop-hook.sh`
Expected: FAIL (hook still reads old paths)

**Step 3: Update stop-hook.sh**

Line 17: Change `STATE_FILE="$PROJECT_DIR/.claude/angry-ralph.local.md"` to `STATE_FILE="$PROJECT_DIR/.ralph-state/loop.md"`

Line 33: Change `CONFIG_FILE="$PROJECT_DIR/planning/config.json"` to `CONFIG_FILE="$PROJECT_DIR/.ralph-state/pipeline.json"`

**Step 4: Run tests to verify they pass**

Run: `bash tests/test-stop-hook.sh`
Expected: All 20 tests PASS

**Step 5: Commit**

```bash
git add hooks/stop-hook.sh tests/test-stop-hook.sh
git commit -m "feat: migrate stop-hook to .ralph-state/ paths"
```

---

### Task 3: Delete killed commands

Remove the 7 command files that are being replaced. This is a clean deletion — no replacement yet.

**Files:**
- Delete: `commands/angry-skip-to.md`
- Delete: `commands/angry-rerun.md`
- Delete: `commands/angry-split.md`
- Delete: `commands/help.md`
- Delete: `commands/angry-review-code.md`
- Delete: `commands/angry-review-plan.md`
- Delete: `commands/angry-review-section.md`

**Step 1: Delete the files**

```bash
cd /Users/jfeinblum/code/angryralph/angry-ralph
rm commands/angry-skip-to.md commands/angry-rerun.md commands/angry-split.md commands/help.md commands/angry-review-code.md commands/angry-review-plan.md commands/angry-review-section.md
```

**Step 2: Verify remaining commands**

```bash
ls commands/
```

Expected: `angry-ralph.md`, `angry-status.md`, `cancel-ralph.md` (3 files remain)

**Step 3: Commit**

```bash
git add -u commands/
git commit -m "feat: kill 7 escape-hatch commands (replaced by composable phase commands)"
```

---

### Task 4: Rewrite `/angry-ralph` command for .ralph-state/ + --auto + --help

Rewrite the main command to use `.ralph-state/`, add `--auto` and `--help` flags, add backwards-compat migration, and add `.done` marker-based resume.

**Files:**
- Modify: `commands/angry-ralph.md` (full rewrite)

**Step 1: Rewrite angry-ralph.md**

Replace entire content with:

```markdown
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
- **`--auto`** (optional) -- Skip clarifying questions and review approval. Append to system prompt: "Do NOT ask clarifying questions. Make the most secure, industry-standard architectural assumption and proceed immediately."
- **`--help`** (optional) -- Print command reference and exit.
- **`--max-review-iterations N`** (optional, default: `3`) -- Maximum adversarial review iterations for Phase 3 and Phase 6.
- **`--max-section-review-iterations N`** (optional, default: `2`) -- Maximum per-section review-fix iterations during Phase 5.
- **`--max-tdd-iterations N`** (optional, default: `20`) -- Maximum TDD loop iterations per section before escalating.

### --help Output

If `--help` is passed, print the following and stop:

```
angry-ralph — Spec-to-code pipeline with adversarial review and TDD execution.

Usage:
  /angry-ralph @spec.md [--auto] [--max-review-iterations N] [--max-section-review-iterations N] [--max-tdd-iterations N]

Commands:
  /angry-ralph @spec [--auto]           Smart monolith: Phases 1-6, idempotent resume.
  /angry-architect @spec [--auto]       Phases 1-2: Decompose + Plan.
  /angry-review [plan|code|section <n>] Phase 3 in pipeline. On-demand anytime with target.
  /angry-execute [--auto] [--rebuild <section>]  Phases 4-6: Split + TDD + Final Review.
  /angry-fix [context] [prompt]         Surgical TDD strike: write failing test, fix, green, commit.
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

Validate that the referenced spec file exists and is readable. Resolve its absolute path and store it as `SPEC_FILE`. Derive `SPEC_DIR` as the directory containing the spec file.

## 2. Environment Validation

Run the environment validation script via the Bash tool:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/checks/validate-env.sh
```

If the script exits with a non-zero code, report the error and stop. If it succeeds, capture its JSON stdout (`review_tier`, `available_reviewers`).

Confirm git repository. If not, ask whether to `git init`. Do not initialize without consent.

## 3. Backwards Compatibility Migration

If `.claude/angry-ralph.local.md` exists and `.ralph-state/` does not:

```bash
mkdir -p .ralph-state
mv .claude/angry-ralph.local.md .ralph-state/loop.md
```

If `planning/config.json` exists and `.ralph-state/pipeline.json` does not, copy the config:

```bash
cp planning/config.json .ralph-state/pipeline.json
```

## 4. Resume Detection via .done Markers

Check for `.ralph-state/` directory:

- If `.ralph-state/phases/architect.done` exists → Phases 1-2 done.
- If `.ralph-state/phases/review.done` exists → Phase 3 done.
- If `.ralph-state/phases/execute.done` exists → Phases 4-6 done. Pipeline complete.
- If `.ralph-state/pipeline.json` exists → read `current_phase` and `completed_sections` for finer resume.
- If `.ralph-state/loop.md` exists with `active=true` → mid-section TDD resume.

If prior state is detected, inform the user and ask via AskUserQuestion: "Resume the previous run, or start fresh?"

If start fresh: `rm -rf .ralph-state/ planning/` and continue.

If no prior state, proceed to setup.

## 5. Setup

Create state directory:

```bash
mkdir -p .ralph-state/phases
mkdir -p planning/reviews planning/sections
```

Initialize `.ralph-state/pipeline.json` with:

```json
{
  "spec_file": "<absolute path>",
  "mode": "<interactive|auto>",
  "max_review_iterations": <N>,
  "max_section_review_iterations": <N>,
  "max_tdd_iterations": <N>,
  "started_at": "<ISO 8601>",
  "review_tier": "<adversarial|partial|self-reflection>",
  "available_reviewers": ["<list>"],
  "current_phase": "decompose",
  "completed_phases": [],
  "completed_sections": []
}
```

Set `"mode": "auto"` if `--auto` was passed, otherwise `"mode": "interactive"`.

## 6. Handoff to Skill

The angry-ralph skill handles the full 6-phase workflow. Create task list items:

1. Phase 1: DECOMPOSE
2. Phase 2: PLAN
3. Phase 3: REVIEW
4. Phase 4: SPLIT
5. Phase 5: EXECUTE
6. Phase 6: FINAL REVIEW

Begin Phase 1 immediately.

### --auto Behavior

When `mode` is `"auto"` in pipeline.json:
- **Phase 1**: Do NOT use AskUserQuestion for interview. Make secure, industry-standard assumptions.
- **Phase 3**: Run review and log findings, but auto-accept and proceed without human approval pause.
- **Phase 5/6**: Skip any final confirmation prompts.
```

**Step 2: Verify file saved correctly**

Read the file back and confirm frontmatter is valid.

**Step 3: Commit**

```bash
git add commands/angry-ralph.md
git commit -m "feat: rewrite /angry-ralph for .ralph-state/, --auto, --help, .done markers"
```

---

### Task 5: Create `/angry-architect` command

New command for Phases 1-2 only (Decompose + Plan).

**Files:**
- Create: `commands/angry-architect.md`

**Step 1: Create the command file**

```markdown
---
name: angry-architect
description: Run Phases 1-2 (Decompose + Plan) of the angry-ralph pipeline
---

# /angry-architect Command

Run Phases 1 and 2 of the angry-ralph pipeline: Decompose the spec and write the implementation plan. Does NOT run review, split, or execution.

## 1. Argument Parsing

- **`@file.md`** (required) -- Input specification file.
- **`--auto`** (optional) -- Skip clarifying questions. Append to system prompt: "Do NOT ask clarifying questions. Make the most secure, industry-standard architectural assumption and proceed immediately."

If no `@file.md` is provided, report error:

```
Usage: /angry-architect @spec.md [--auto]
```

Validate spec file exists. Resolve absolute path.

## 2. Environment Validation

Run `${CLAUDE_PLUGIN_ROOT}/scripts/checks/validate-env.sh`. Halt on failure. Confirm git repo.

## 3. Backwards Compatibility Migration

Same as `/angry-ralph` step 3.

## 4. Resume Detection

If `.ralph-state/phases/architect.done` exists:
- Report: "Phases 1-2 already complete. Plan at planning/angry-ralph-plan.md."
- Stop. (Idempotent — does not re-run.)

If `.ralph-state/pipeline.json` exists, check `current_phase`. If `plan` or later, offer resume.

## 5. Setup

Create `.ralph-state/phases/` and `planning/` directories. Initialize `.ralph-state/pipeline.json` (same as /angry-ralph step 5). Set `mode` to `"auto"` if `--auto` passed.

## 6. Execute Phases 1-2

Follow the angry-ralph skill's Phase 1 (DECOMPOSE) and Phase 2 (PLAN) instructions.

When Phase 2 is complete:
- Write `.ralph-state/phases/architect.done` (touch the file).
- Update `pipeline.json`: set `current_phase` to `"review"`, append `"decompose"` and `"plan"` to `completed_phases`.
- Report: "Phases 1-2 complete. Plan written to planning/angry-ralph-plan.md. Run /angry-review plan to review, or /angry-execute to proceed."
```

**Step 2: Verify file**

Read back and confirm frontmatter.

**Step 3: Commit**

```bash
git add commands/angry-architect.md
git commit -m "feat: add /angry-architect command (Phases 1-2)"
```

---

### Task 6: Create `/angry-review` command

Unified review command with subcommand pattern. Consolidates 3 old review commands.

**Files:**
- Create: `commands/angry-review.md`

**Step 1: Create the command file**

```markdown
---
name: angry-review
description: Run adversarial review on plan, code, or a specific section
---

# /angry-review Command

Unified review command. When run as Phase 3 in the pipeline, writes `review.done`. When run on-demand, writes to `planning/reviews/on-demand/`.

## 1. Argument Parsing

Parse the first argument as the review target:

- **`plan`** -- Review the implementation plan (`planning/angry-ralph-plan.md`).
- **`code`** -- Review the codebase against the plan.
- **`section <name>`** -- Review a specific section against its spec.

If no target is provided, default to `plan`.

## 2. Detect Context: Pipeline vs On-Demand

**Pipeline context** (Phase 3): `.ralph-state/pipeline.json` exists AND `current_phase` is `"review"` AND target is `plan`.

**On-demand context**: Everything else.

### Pipeline Mode (Phase 3)

1. Read `review_tier` and `available_reviewers` from `.ralph-state/pipeline.json`.
2. Read `max_review_iterations` from `.ralph-state/pipeline.json`.
3. Follow the angry-ralph skill's Phase 3 (ADVERSARIAL REVIEW) procedure.
4. On completion, write `.ralph-state/phases/review.done`.
5. Update `pipeline.json`: set `current_phase` to `"split"`, append `"review"` to `completed_phases`.

### On-Demand Mode

1. Read `review_tier` and `available_reviewers` from `.ralph-state/pipeline.json` (if exists, else run validate-env.sh).
2. Create output directory: `planning/reviews/on-demand/<target>-<timestamp>/`

**For `plan`:**
- Validate `planning/angry-ralph-plan.md` exists.
- Spawn `external-reviewer` subagent with the plan file.
- Write results to the on-demand directory.

**For `code`:**
- Validate `planning/angry-ralph-plan.md` exists.
- Spawn `external-reviewer` subagent with review type "code review against plan".
- The subagent reviews the codebase against the plan.
- Write results to the on-demand directory.

**For `section <name>`:**
- Resolve section spec: `planning/sections/section-<name>.md` or match by partial name.
- Spawn `external-reviewer` subagent with the section spec and changed files.
- Write results to the on-demand directory.

In all on-demand cases:
- Run the full triage decision tree (CRITICAL/WARNING/INFO).
- Present findings to the user.
- Do NOT write `.done` markers.
```

**Step 2: Verify file**

**Step 3: Commit**

```bash
git add commands/angry-review.md
git commit -m "feat: add /angry-review command (unified plan|code|section review)"
```

---

### Task 7: Create `/angry-execute` command

Phases 4-6 with `--auto` and `--rebuild` flags.

**Files:**
- Create: `commands/angry-execute.md`

**Step 1: Create the command file**

```markdown
---
name: angry-execute
description: Run Phases 4-6 (Split + TDD Execute + Final Review) of the angry-ralph pipeline
---

# /angry-execute Command

Run Phases 4-6 of the angry-ralph pipeline: Split the plan into sections, execute each via TDD Ralph Loop, and run final integration review.

## 1. Argument Parsing

- **`--auto`** (optional) -- Skip confirmation prompts. Start executing immediately.
- **`--rebuild <section>`** (optional) -- Delete a section's done marker and re-run it. Example: `--rebuild section-03-api`.

If `--rebuild` is passed:
1. Delete the section marker: `rm -f .ralph-state/phases/execute-<section>.done`
2. Remove the section from `completed_sections` in pipeline.json.
3. Continue to the idempotent pipeline (it will see the section as incomplete).

## 2. Prerequisites

Verify `.ralph-state/pipeline.json` exists. If not, error:

```
No pipeline state found. Run /angry-architect or /angry-ralph first.
```

Verify that Phases 1-2 are complete: `.ralph-state/phases/architect.done` must exist. If not:

```
Phases 1-2 not complete. Run /angry-architect @spec.md first.
```

## 3. Idempotent Phase Execution

### Phase 4: SPLIT

If `.ralph-state/phases/review.done` does NOT exist (Phase 3 not done):
- Ask user: "Phase 3 (review) was not run. Proceed without review, or run /angry-review plan first?"
- If user wants review: stop and tell them to run `/angry-review plan`.

Follow the angry-ralph skill's Phase 4 (SPLIT) instructions.

### Phase 5: EXECUTE (Ralph Loop + TDD)

For each section in `planning/sections/index.md`:
- Check if section already completed: look for `section-NN-name` in `completed_sections` in pipeline.json.
- If completed, skip.
- If not completed, execute via TDD Ralph Loop per the skill instructions.
- On section completion, append to `completed_sections` in pipeline.json.

When all sections complete, write `.ralph-state/phases/execute.done`.

### Phase 6: FINAL REVIEW

Follow the angry-ralph skill's Phase 6 (FINAL REVIEW) instructions.

On completion:
- Update pipeline.json: `current_phase` to `"complete"`.
- Report pipeline completion.

### Strict .done Gating

**MUST NOT** write `execute.done` unless the test suite passes (exit 0 on final test run). If `max_tdd_iterations` is hit and tests still fail, hard-crash the pipeline:

```
FATAL: TDD cap reached for <section>. Tests still failing after <N> iterations.
Pipeline halted. Review errors and re-run with /angry-execute --rebuild <section>.
```

Exit with non-zero status. Do not write any `.done` marker. Do not silently proceed.
```

**Step 2: Verify file**

**Step 3: Commit**

```bash
git add commands/angry-execute.md
git commit -m "feat: add /angry-execute command (Phases 4-6, --rebuild, strict .done gating)"
```

---

### Task 8: Create `/angry-fix` command

Surgical post-pipeline TDD remediation.

**Files:**
- Create: `commands/angry-fix.md`

**Step 1: Create the command file**

```markdown
---
name: angry-fix
description: Surgical TDD strike — write failing test, fix, green, commit
---

# /angry-fix Command

Surgical post-pipeline TDD remediation. No planning phase. No review phase. Just fix and ship.

## 1. Argument Parsing

Accept context and a prompt:

- **`@file` references** (optional) -- File paths, error logs, test output to provide as context.
- **Prompt text** (required) -- Description of what to fix.

Example: `/angry-fix @error.log "Fix these integration blockers"`

If no prompt is provided:
```
Usage: /angry-fix [context] [prompt]
Example: /angry-fix @error.log "Fix the auth middleware timeout"
```

## 2. Procedure

1. Read all provided `@file` context.
2. Write a failing test based on the prompt. The test must capture the expected correct behavior.
3. Run the test suite and confirm the new test fails (red phase).
4. Implement the fix — minimum code to make the test pass.
5. Run the test suite and confirm ALL tests pass (green phase), not just the new test.
6. If tests fail, iterate: debug and fix implementation, re-run. Follow TDD protocol.
7. When all tests pass, create an atomic commit: `fix: <description from prompt>`.

## 3. Constraints

- No planning artifacts are created or modified.
- No review is run.
- No `.ralph-state/` state is modified.
- This is a standalone surgical operation.
- Follow `references/tdd-protocol.md` for TDD rules.
```

**Step 2: Verify file**

**Step 3: Commit**

```bash
git add commands/angry-fix.md
git commit -m "feat: add /angry-fix command (surgical TDD strike)"
```

---

### Task 9: Update `/cancel-ralph` and `/angry-status` for .ralph-state/

Migrate both existing commands to read from `.ralph-state/` instead of `.claude/`.

**Files:**
- Modify: `commands/cancel-ralph.md`
- Modify: `commands/angry-status.md`

**Step 1: Update cancel-ralph.md**

Replace all references to `.claude/angry-ralph.local.md` with `.ralph-state/loop.md`:

- Line 12: `.ralph-state/loop.md`
- Line 19: `.ralph-state/loop.md`
- Line 23: `rm .ralph-state/loop.md`
- Line 32: re-invoke `/angry-ralph`

**Step 2: Update angry-status.md**

Replace:
- `planning/config.json` → `.ralph-state/pipeline.json`
- `.claude/angry-ralph.local.md` → `.ralph-state/loop.md`
- Add `.ralph-state/phases/*.done` marker checks to the display
- Update state file display line to show `.ralph-state/loop.md`

New display format:

```
angry-ralph status:
  Phase:      <current_phase> (<N> of 6)
  Section:    <current_section> (iteration <N>)    [only during execute]
  Completed:  <comma-separated completed_phases>
  Sections:   <committed>/<total> committed        [only if sections exist]
  Done markers: architect[✓/✗] review[✓/✗] execute[✓/✗]
  Review tier: <tier> (<reviewers>)
  Config:     .ralph-state/pipeline.json
  State file: .ralph-state/loop.md [active|inactive|missing]
```

**Step 3: Commit**

```bash
git add commands/cancel-ralph.md commands/angry-status.md
git commit -m "feat: migrate /cancel-ralph and /angry-status to .ralph-state/ paths"
```

---

### Task 10: Update SKILL.md for .ralph-state/ and --auto

The master orchestration skill references `.claude/angry-ralph.local.md` and `planning/config.json` extensively. Update all paths and add --auto behavior.

**Files:**
- Modify: `skills/angry-ralph/SKILL.md`

**Step 1: Global path replacements**

- Replace ALL `.claude/angry-ralph.local.md` → `.ralph-state/loop.md`
- Replace ALL `planning/config.json` → `.ralph-state/pipeline.json`

**Step 2: Update Command Arguments section (around line 41)**

Add `--auto` flag:
```
- **`--auto`** (optional) -- Skip clarifying questions and review approval. Stored in `.ralph-state/pipeline.json` as `"mode": "auto"`.
```

**Step 3: Update Phase 1 for --auto**

After the interview instructions, add:

```
**--auto mode**: If `mode` is `"auto"` in `.ralph-state/pipeline.json`, do NOT use AskUserQuestion for the interview. Make the most secure, industry-standard architectural assumption for every ambiguity and proceed immediately. Still write interview notes documenting the assumptions made.
```

**Step 4: Update Phase 3 for --auto**

After the iteration control section, add:

```
**--auto mode**: Run the full review loop and log all findings. But do NOT pause for human approval at the end. Auto-accept and proceed to the split phase. Genuine ambiguity questions are still answered with secure defaults (not escalated to user).
```

**Step 5: Update Phase 5 section**

- State file path: `.ralph-state/loop.md`
- `.done` marker: After all sections complete, write `.ralph-state/phases/execute.done`
- Strict gating: Add note that `execute.done` MUST NOT be written unless tests pass

**Step 6: Update Phase 6 Completion section**

- Deactivate state file at `.ralph-state/loop.md`
- Write pipeline completion in `.ralph-state/pipeline.json`

**Step 7: Update State Management section**

Replace the entire "State File" subsection to reference `.ralph-state/loop.md`.
Replace "Session Config" subsection to reference `.ralph-state/pipeline.json`.
Add new "Done Markers" subsection describing `.ralph-state/phases/*.done`.

**Step 8: Update Resume & Recovery section**

Replace all path references. Add `.done` marker-based resume logic.

**Step 9: Commit**

```bash
git add skills/angry-ralph/SKILL.md
git commit -m "feat: update SKILL.md for .ralph-state/, --auto mode, .done markers"
```

---

### Task 11: Update loop-protocol.md for .ralph-state/

**Files:**
- Modify: `skills/angry-ralph/references/loop-protocol.md`

**Step 1: Replace paths**

- Line 9: `.claude/angry-ralph.local.md` → `.ralph-state/loop.md`
- Line 39: `planning/config.json` → `.ralph-state/pipeline.json`

**Step 2: Update Cancel Mechanism section**

- Line 106: `.claude/angry-ralph.local.md` → `.ralph-state/loop.md`

**Step 3: Add .done marker note**

After the "Successful exit" step in Loop Lifecycle, add:

```
10. **Done marker** — After the final section completes and commits, write `.ralph-state/phases/execute.done`. MUST NOT write this marker unless the test suite exits 0.
```

**Step 4: Commit**

```bash
git add skills/angry-ralph/references/loop-protocol.md
git commit -m "feat: update loop-protocol.md for .ralph-state/ paths"
```

---

### Task 12: Update section-review-protocol.md and final-review-protocol.md

Update config path references in both review protocols.

**Files:**
- Modify: `skills/angry-ralph/references/section-review-protocol.md`
- Modify: `skills/angry-ralph/references/final-review-protocol.md`

**Step 1: Update section-review-protocol.md**

Line 119: `planning/config.json` → `.ralph-state/pipeline.json`

**Step 2: Update final-review-protocol.md**

Line 63: `config.json` → `.ralph-state/pipeline.json`
Line 131: `planning/config.json` → `.ralph-state/pipeline.json`

**Step 3: Commit**

```bash
git add skills/angry-ralph/references/section-review-protocol.md skills/angry-ralph/references/final-review-protocol.md
git commit -m "feat: update review protocols for .ralph-state/ paths"
```

---

### Task 13: Update review-protocol.md for .ralph-state/

**Files:**
- Modify: `skills/angry-ralph/references/review-protocol.md`

**Step 1: Replace paths**

- Line 9: `planning/config.json` → `.ralph-state/pipeline.json`
- Line 39: `config.json` → `.ralph-state/pipeline.json`

**Step 2: Commit**

```bash
git add skills/angry-ralph/references/review-protocol.md
git commit -m "feat: update review-protocol.md for .ralph-state/ paths"
```

---

### Task 14: Update test-plugin-structure.sh

Remove assertions for killed commands, add assertions for new commands.

**Files:**
- Modify: `tests/test-plugin-structure.sh`

**Step 1: Remove assertions for killed commands**

Delete these assertion lines:
- `angry-review-code command` (exists + frontmatter)
- `angry-review-plan command` (exists + frontmatter)
- `angry-review-section command` (exists + frontmatter)
- `angry-skip-to command` (exists + frontmatter)
- `angry-rerun command` (exists + frontmatter)
- `angry-split command` (exists + frontmatter)
- `help command` and `help has frontmatter` — replace with new help check

That removes 14 assertions.

**Step 2: Add assertions for new commands**

```bash
# New commands
assert_exists "angry-architect command" "commands/angry-architect.md"
assert_contains "angry-architect has frontmatter" "commands/angry-architect.md" "name: angry-architect"
assert_exists "angry-review command" "commands/angry-review.md"
assert_contains "angry-review has frontmatter" "commands/angry-review.md" "name: angry-review"
assert_exists "angry-execute command" "commands/angry-execute.md"
assert_contains "angry-execute has frontmatter" "commands/angry-execute.md" "name: angry-execute"
assert_exists "angry-fix command" "commands/angry-fix.md"
assert_contains "angry-fix has frontmatter" "commands/angry-fix.md" "name: angry-fix"
```

That adds 8 assertions. Net: -14 + 8 = -6 assertions.

**Step 3: Run tests**

Run: `bash tests/test-plugin-structure.sh`
Expected: All assertions PASS

**Step 4: Commit**

```bash
git add tests/test-plugin-structure.sh
git commit -m "feat: update plugin structure tests for new command roster"
```

---

### Task 15: Update README.md

Update the command table, architecture tree, pipeline table, planning artifacts, prerequisites, and test count.

**Files:**
- Modify: `README.md`

**Step 1: Update Commands table (lines 91-105)**

Replace with:

```markdown
| Command | Description |
|---------|-------------|
| `/angry-ralph @spec.md [--auto] [--help]` | Start the 6-phase pipeline (idempotent resume) |
| `/angry-architect @spec.md [--auto]` | Phases 1-2: Decompose + Plan |
| `/angry-review [plan\|code\|section <name>]` | Phase 3 in pipeline. On-demand anytime. |
| `/angry-execute [--auto] [--rebuild <section>]` | Phases 4-6: Split + TDD + Final Review |
| `/angry-fix [context] [prompt]` | Surgical TDD strike: test, fix, green, commit |
| `/cancel-ralph` | Kill switch: halt loop, save state, exit |
| `/angry-status` | Read-only pipeline state display |
```

**Step 2: Update Architecture tree (lines 108-148)**

Replace command listing to show only the 7 commands. Remove killed commands. Add new ones.

**Step 3: Update Quick Start usage examples**

Add `--auto` example:
```
/angry-ralph @path/to/your-spec.md --auto
```

**Step 4: Update test count**

Reflect new test count after Task 14 changes.

**Step 5: Update Planning Artifacts tree**

Add `.ralph-state/` directory structure. Add `planning/reviews/on-demand/` path.

**Step 6: Commit**

```bash
git add README.md
git commit -m "docs: update README for CLI overhaul (7 commands, .ralph-state/)"
```

---

### Task 16: Update CONTRIBUTING.md

Update command references and test count.

**Files:**
- Modify: `CONTRIBUTING.md`

**Step 1: Update test commands reference**

Line 52: Update command list to new commands (`/angry-ralph`, `/cancel-ralph`, `/angry-status`, `/angry-architect`, `/angry-review`, `/angry-execute`, `/angry-fix`).

**Step 2: Update test count**

Reflect new test count.

**Step 3: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: update CONTRIBUTING.md for CLI overhaul"
```

---

### Task 17: Run full test suite + push

Final verification that everything works together.

**Step 1: Run all tests**

```bash
cd /Users/jfeinblum/code/angryralph/angry-ralph
for t in tests/test-*.sh; do echo "=== $t ==="; bash "$t"; echo; done
```

Expected: All tests pass across all 4 suites.

**Step 2: Check for any missed old path references**

```bash
grep -r "angry-ralph.local.md" --include="*.sh" --include="*.md" --include="*.json" .
grep -r "planning/config.json" --include="*.sh" --include="*.md" --include="*.json" . | grep -v "docs/plans/"
```

Expected: No matches (all migrated to `.ralph-state/` paths). Matches in `docs/plans/` are fine (historical design docs).

**Step 3: Verify command count**

```bash
ls commands/ | wc -l
```

Expected: 7 files (angry-ralph.md, angry-architect.md, angry-review.md, angry-execute.md, angry-fix.md, angry-status.md, cancel-ralph.md)

**Step 4: Push**

```bash
git push
```
