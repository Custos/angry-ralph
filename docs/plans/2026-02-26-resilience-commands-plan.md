# Resilience Hardening, Command Renaming, and New Commands — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Harden angry-ralph against failure modes (infinite TDD loop, CLI hangs, state corruption, git conflicts), rename review commands to `angry-` prefix, and add 4 new pipeline control commands.

**Architecture:** Three implementation layers in priority order: resilience fixes to the existing codebase, command renaming for namespace consistency, then new command files. Each layer builds on the last and can be tested independently.

**Tech Stack:** Bash (hooks/scripts), Markdown (commands/skills/protocols), Python3 (JSON parsing in hooks), existing test framework (assert_eq/assert_contains/assert_empty helpers).

---

### Task 1: Add TDD iteration cap to stop-hook.sh

**Files:**
- Modify: `hooks/stop-hook.sh`

**Step 1: Write the failing test**

Add to `tests/test-stop-hook.sh` before the `# Summary` line:

```bash
# ---- Test 8: TDD cap reached → allow exit (no promise needed) ----
rm -f "$STATE_FILE"
mkdir -p "$TEST_DIR/.claude"
create_state_file "$STATE_FILE" "execute" "20" "3" "section-01-auth" "SECTION_COMPLETE" "/tmp/spec.md" "/tmp/planning/" "Build the auth module"

# Create a config.json with max_tdd_iterations=20
mkdir -p "$TEST_DIR/planning"
echo '{"max_tdd_iterations": 20}' > "$TEST_DIR/planning/config.json"

TRANSCRIPT_CAP="$TEST_DIR/transcript_cap.jsonl"
echo '{"role":"assistant","content":"I cannot make these tests pass"}' > "$TRANSCRIPT_CAP"

OUTPUT=$(run_hook_stdout '{"session_id":"test","transcript_path":"'"$TRANSCRIPT_CAP"'","cwd":"'"$TEST_DIR"'"}')
assert_contains "tdd cap reached → allow with cap_reached" '"decision"' "$OUTPUT"
assert_contains "tdd cap reached → decision is allow" '"allow"' "$OUTPUT"
assert_contains "tdd cap reached → has tdd_cap_reached" "tdd_cap_reached" "$OUTPUT"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-stop-hook.sh`
Expected: FAIL — stop-hook doesn't know about TDD cap yet.

**Step 3: Implement TDD cap in stop-hook.sh**

In `hooks/stop-hook.sh`, after reading state fields (line 29), add config.json reading. Then before the "Promise NOT found" block (line 96), add the cap check.

After the `COMPLETION_PROMISE` read (line 29), add:

```bash
# Read TDD iteration cap from config.json (if it exists)
MAX_TDD_ITERATIONS=""
CONFIG_FILE="$PROJECT_DIR/planning/config.json"
if [ -f "$CONFIG_FILE" ]; then
  MAX_TDD_ITERATIONS=$(python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    print(cfg.get('max_tdd_iterations', ''))
except: print('')
" "$CONFIG_FILE" 2>/dev/null) || true
fi
```

Before the "Promise NOT found → block exit" block (before line 96), insert:

```bash
# 6b. Check TDD iteration cap — if iteration >= cap, allow exit with cap_reached signal
if [ -n "$MAX_TDD_ITERATIONS" ] && [ "$ITERATION" -ge "$MAX_TDD_ITERATIONS" ]; then
  python3 -c "
import json
print(json.dumps({
    'decision': 'allow',
    'tdd_cap_reached': True,
    'reason': 'TDD iteration cap reached. Section needs user review.',
    'systemMessage': 'angry-ralph: TDD iteration cap ($MAX_TDD_ITERATIONS) reached for $CURRENT_SECTION. Tests have not passed after $ITERATION iterations. Ask the user what to do.'
}))
"
  exit 0
fi
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-stop-hook.sh`
Expected: All tests PASS including new cap test.

**Step 5: Commit**

```bash
git add hooks/stop-hook.sh tests/test-stop-hook.sh
git commit -m "feat: add TDD iteration safety cap to stop hook"
```

---

### Task 2: Add --max-tdd-iterations to CLI and config

**Files:**
- Modify: `commands/angry-ralph.md`
- Modify: `commands/help.md`
- Modify: `skills/angry-ralph/SKILL.md`

**Step 1: Add argument to commands/angry-ralph.md**

In argument parsing section, add after `--max-section-review-iterations`:

```markdown
- **`--max-tdd-iterations N`** (optional, default: `20`) -- Maximum TDD loop iterations per section before escalating to user.
```

Update usage block to include `[--max-tdd-iterations N]`.

Add to config.json template:

```json
"max_tdd_iterations": <N>,
```

**Step 2: Add to commands/help.md Configuration table**

Add row:

```markdown
| `--max-tdd-iterations N` | `20` | Max TDD loop iterations per section before escalating |
```

**Step 3: Add to SKILL.md Command Arguments and Phase 5**

Add `--max-tdd-iterations N` to Command Arguments section.

In Phase 5, after the Completion Gate section (step 4), add TDD cap behavior description:

```markdown
If the SubagentStop hook detects that `iteration >= max_tdd_iterations` (from `planning/config.json`, default 20), it allows exit with a `tdd_cap_reached` signal instead of blocking. The main session then asks the user via `AskUserQuestion`: "Section X failed after N TDD iterations. Review errors, skip section, or keep trying (+10 iterations)?"

- **Skip section**: Mark the section as `failed` in `planning/sections/index.md` and advance to the next section.
- **Keep trying**: Add 10 to `max_tdd_iterations` in config.json and re-dispatch the subagent.
- **Review errors**: Display the last test output for user inspection before deciding.
```

**Step 4: Commit**

```bash
git add commands/angry-ralph.md commands/help.md skills/angry-ralph/SKILL.md
git commit -m "feat: add --max-tdd-iterations CLI argument and Phase 5 cap behavior"
```

---

### Task 3: Add TDD cap to loop-protocol.md

**Files:**
- Modify: `skills/angry-ralph/references/loop-protocol.md`

**Step 1: Add cap to Field Definitions**

After `review_iteration` field definition, note that `max_tdd_iterations` is read from `planning/config.json` (not the state file).

**Step 2: Add cap behavior to Loop Lifecycle**

Between "Promise not found → Block exit" and "Successful exit", insert:

```markdown
7b. **TDD cap reached** — If `iteration >= max_tdd_iterations` (from config.json), allow exit with `tdd_cap_reached` signal. Main session escalates to user: skip section, keep trying (+10), or review errors.
```

**Step 3: Commit**

```bash
git add skills/angry-ralph/references/loop-protocol.md
git commit -m "docs: add TDD iteration cap to loop protocol"
```

---

### Task 4: Add state file validation to resume detection

**Files:**
- Modify: `commands/angry-ralph.md`
- Modify: `skills/angry-ralph/SKILL.md`

**Step 1: Add validation to commands/angry-ralph.md Resume Detection**

After "Read `.claude/angry-ralph.local.md` if it exists to determine active state", add:

```markdown
**Validate state file integrity** before reading fields. Check that the file contains opening and closing `---` markers and at least the `active`, `phase`, and `completion_promise` fields. Run:

\`\`\`bash
python3 -c "
import sys
content = open(sys.argv[1]).read()
markers = content.count('---')
if markers < 2:
    print('invalid')
    sys.exit(0)
for field in ['active:', 'phase:', 'completion_promise:']:
    if field not in content:
        print('invalid')
        sys.exit(0)
print('valid')
" .claude/angry-ralph.local.md
\`\`\`

If the output is `invalid`, report: "State file is corrupted. Starting fresh is recommended." Include this in the AskUserQuestion options alongside "Resume" and "Start fresh".
```

**Step 2: Add config.json validation to Resume Detection**

After "Read `planning/config.json` if it exists", add:

```markdown
**Validate config.json integrity** before parsing. Run:

\`\`\`bash
python3 -m json.tool planning/config.json > /dev/null 2>&1
\`\`\`

If exit code is non-zero, report: "Config file is corrupted." and offer start-fresh.
```

**Step 3: Add validation to SKILL.md Resume & Recovery section**

Add a "Validation" subsection under "Detecting Existing State":

```markdown
### Validation Before Resume

Before reading state or config files for resume, validate their integrity:

1. **State file**: Check for two `---` markers and required fields (`active`, `phase`, `completion_promise`). If invalid, offer start-fresh.
2. **Config.json**: Validate as JSON with `python3 -m json.tool`. If invalid, offer start-fresh.

Never attempt to resume from corrupted files — always offer a clean restart.
```

**Step 4: Commit**

```bash
git add commands/angry-ralph.md skills/angry-ralph/SKILL.md
git commit -m "feat: add state file and config.json validation on resume"
```

---

### Task 5: Add git conflict handling to atomic commit

**Files:**
- Modify: `skills/angry-ralph/SKILL.md`
- Modify: `skills/angry-ralph/references/loop-protocol.md`

**Step 1: Update SKILL.md Phase 5 step 6 (Atomic Commit)**

Replace the current Atomic Commit section with:

```markdown
### 6. Atomic Commit

After a section passes all tests and the review gate clears:

- Stage only the files changed for the completed section
- Commit with message format: `feat(section-NN): <section-name>`
- Do not stage unrelated files or amend previous commits

**If the commit fails** (non-zero exit code from `git commit`):

1. Read the git error output.
2. Ask the user via `AskUserQuestion`: "Commit failed for section-NN: <git error summary>. Options: resolve manually and retry, or skip commit and continue?"
3. If the user resolves manually: verify commit succeeded with `git log -1`, then proceed.
4. If the user skips: log the skip, advance to the next section. The section's code remains unstaged.

Do not silently ignore commit failures. Do not proceed to the next section until the commit succeeds or the user explicitly skips.
```

**Step 2: Update loop-protocol.md Atomic Commit Rules**

Add after rule 4 ("Do not amend previous commits"):

```markdown
5. If `git commit` returns a non-zero exit code, do not proceed. Escalate to the user via `AskUserQuestion` with the git error message. Wait for user resolution before advancing.
```

**Step 3: Commit**

```bash
git add skills/angry-ralph/SKILL.md skills/angry-ralph/references/loop-protocol.md
git commit -m "feat: add git conflict handling to atomic commit step"
```

---

### Task 6: Rewrite external-reviewer for parallel execution + resilience

**Files:**
- Modify: `agents/external-reviewer.md`
- Modify: `skills/angry-ralph/references/review-protocol.md`

**Step 1: Rewrite CLI invocation in external-reviewer.md**

Replace the sequential invocation patterns with parallel execution. Add a new section after "Rules You Must Follow":

```markdown
**Execution Strategy:**

When both gemini and codex are available (Adversarial tier), run them in **parallel**:

1. Launch both CLI commands as background jobs.
2. Wait for both to complete.
3. If a CLI exits with a non-zero code:
   a. Retry once.
   b. If retry also fails, skip that reviewer and note: `[<Reviewer>] SKIPPED — CLI invocation failed after retry.`
4. If BOTH external CLIs fail: fall back to claude (Self-Reflection).
5. Collect all successful results and tag with source.

For Partial tier (one CLI + claude): run the available CLI first, then claude. Apply the same retry logic to the CLI.

For Self-Reflection tier: run claude only. No retry needed (claude is always available).
```

Update the Gemini and Codex invocation examples to show background execution:

```bash
# Parallel execution (Adversarial tier)
gemini -p "..." --approval-mode plan -o text > planning/reviews/iteration-N/gemini-review.md 2>&1 &
GEMINI_PID=$!

codex exec "..." -C "$(pwd)" --sandbox read-only -o planning/reviews/iteration-N/codex-review.md &
CODEX_PID=$!

# Wait for both
wait $GEMINI_PID; GEMINI_EXIT=$?
wait $CODEX_PID; CODEX_EXIT=$?

# Retry on failure
if [ $GEMINI_EXIT -ne 0 ]; then
  gemini -p "..." --approval-mode plan -o text > planning/reviews/iteration-N/gemini-review.md 2>&1
  GEMINI_EXIT=$?
fi
# (same for codex)

# Fallback to claude if both failed
if [ $GEMINI_EXIT -ne 0 ] && [ $CODEX_EXIT -ne 0 ]; then
  claude -p "..." --output-format text > planning/reviews/iteration-N/claude-review.md 2>&1
fi
```

**Step 2: Update review-protocol.md**

Add a "Parallel Execution and Fallback" section after "CLI Invocation Rules":

```markdown
## Parallel Execution and Fallback

When multiple reviewers are available, run them in parallel to minimize wall-clock time:

1. **Adversarial tier**: Launch gemini and codex simultaneously as background jobs.
2. **Wait for both**: Collect exit codes.
3. **Retry on failure**: If a CLI exits with error, retry once. If retry fails, skip and note.
4. **Fallback**: If both external CLIs fail, invoke claude as fallback.
5. **Collect results**: Merge all successful reviewer outputs, tagged with source.

This ensures review proceeds even when individual CLIs are broken, and maximizes throughput by running reviewers concurrently.
```

**Step 3: Commit**

```bash
git add agents/external-reviewer.md skills/angry-ralph/references/review-protocol.md
git commit -m "feat: parallel reviewer execution with retry and claude fallback"
```

---

### Task 7: Rename review commands to angry- prefix

**Files:**
- Rename: `commands/review-code.md` → `commands/angry-review-code.md`
- Rename: `commands/review-plan.md` → `commands/angry-review-plan.md`
- Rename: `commands/review-section.md` → `commands/angry-review-section.md`
- Modify: `commands/help.md`
- Modify: `README.md`
- Modify: `tests/test-plugin-structure.sh`

**Step 1: Rename files and update frontmatter**

```bash
git mv commands/review-code.md commands/angry-review-code.md
git mv commands/review-plan.md commands/angry-review-plan.md
git mv commands/review-section.md commands/angry-review-section.md
```

In each renamed file, update the frontmatter `name:` field:
- `name: review-code` → `name: angry-review-code`
- `name: review-plan` → `name: angry-review-plan`
- `name: review-section` → `name: angry-review-section`

**Step 2: Update commands/help.md**

Replace command table entries:
- `/review-code` → `/angry-review-code`
- `/review-plan` → `/angry-review-plan`
- `/review-section <name-or-number>` → `/angry-review-section <name-or-number>`

**Step 3: Update README.md**

Replace command table entries and architecture tree filenames.

**Step 4: Update tests/test-plugin-structure.sh**

Replace all references to old command names/paths:
- `"commands/review-code.md"` → `"commands/angry-review-code.md"`
- `"name: review-code"` → `"name: angry-review-code"`
- Same for review-plan and review-section

**Step 5: Run tests**

Run: `bash tests/test-plugin-structure.sh`
Expected: All PASS with new file paths.

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename review commands to angry- prefix"
```

---

### Task 8: Create /angry-status command

**Files:**
- Create: `commands/angry-status.md`

**Step 1: Write the command**

```markdown
---
name: angry-status
description: Show current angry-ralph pipeline state
---

# /angry-status Command

Display the current pipeline state at a glance. Read-only — no side effects.

## Procedure

### 1. Check for Pipeline State

Check if `planning/config.json` exists. If not, check if `.claude/angry-ralph.local.md` exists. If neither exists:

\`\`\`
No active angry-ralph pipeline. Run /angry-ralph @spec.md to start.
\`\`\`

### 2. Read State Sources

Read available state sources:
- `planning/config.json` — `current_phase`, `completed_phases`, `review_tier`, `available_reviewers`, `max_review_iterations`, `max_section_review_iterations`, `max_tdd_iterations`
- `.claude/angry-ralph.local.md` — `phase`, `current_section`, `iteration`, `completion_promise`, `review_iteration`
- Git log — count `feat(section-NN)` commits for section completion
- `planning/sections/index.md` — total section count (if exists)

### 3. Display Summary

Print formatted output:

\`\`\`
angry-ralph status:
  Phase:      <current_phase> (<N> of 6)
  Section:    <current_section> (iteration <N>)    [only during execute phase]
  Completed:  <comma-separated completed_phases>
  Sections:   <committed>/<total> committed        [only if sections exist]
  Review tier: <tier> (<reviewers>)
  Config:     planning/config.json
  State file: .claude/angry-ralph.local.md [active|inactive|missing]
\`\`\`

Adapt output to available information. Omit lines where data is not applicable (e.g., don't show Section line outside execute phase).
```

**Step 2: Add assertion to tests/test-plugin-structure.sh**

Add:

```bash
assert_exists "angry-status command" "commands/angry-status.md"
assert_contains "angry-status has frontmatter" "commands/angry-status.md" "name: angry-status"
```

**Step 3: Add to help.md and README.md command tables**

**Step 4: Run tests**

Run: `bash tests/test-plugin-structure.sh`
Expected: All PASS.

**Step 5: Commit**

```bash
git add commands/angry-status.md commands/help.md README.md tests/test-plugin-structure.sh
git commit -m "feat: add /angry-status command for pipeline state display"
```

---

### Task 9: Create /angry-skip-to command

**Files:**
- Create: `commands/angry-skip-to.md`

**Step 1: Write the command**

```markdown
---
name: angry-skip-to
description: Advance angry-ralph pipeline to a specific phase
---

# /angry-skip-to Command

Skip to a specific pipeline phase, marking all prior phases as complete.

## Usage

\`\`\`
/angry-skip-to <phase>
\`\`\`

Valid phases: `plan`, `review`, `split`, `execute`, `final_review`

## Procedure

### 1. Validate

Confirm `planning/config.json` exists. If not: "No pipeline found. Run /angry-ralph first."

Validate the phase argument is one of the valid values. If invalid, list valid phases.

### 2. Confirm

Ask via AskUserQuestion: "Skip to <phase>? All prior phases will be marked complete. Planning artifacts are preserved."

### 3. Update State

Define phase order: `["decompose", "plan", "review", "split", "execute", "final_review"]`

Update `planning/config.json`:
- Set `current_phase` to the target phase
- Set `completed_phases` to all phases before the target

Remove `.claude/angry-ralph.local.md` if it exists (clean state for new phase).

### 4. Report

Print: "Pipeline advanced to <phase>. Run /angry-ralph @spec.md to resume from this point."
```

**Step 2: Add assertion to tests/test-plugin-structure.sh**

```bash
assert_exists "angry-skip-to command" "commands/angry-skip-to.md"
assert_contains "angry-skip-to has frontmatter" "commands/angry-skip-to.md" "name: angry-skip-to"
```

**Step 3: Add to help.md and README.md**

**Step 4: Run tests, commit**

```bash
git add commands/angry-skip-to.md commands/help.md README.md tests/test-plugin-structure.sh
git commit -m "feat: add /angry-skip-to command for phase advancement"
```

---

### Task 10: Create /angry-rerun command

**Files:**
- Create: `commands/angry-rerun.md`

**Step 1: Write the command**

```markdown
---
name: angry-rerun
description: Re-run a specific angry-ralph pipeline phase
---

# /angry-rerun Command

Re-run a specific phase, resetting its artifacts.

## Usage

\`\`\`
/angry-rerun <phase>
\`\`\`

Valid phases: `decompose`, `plan`, `review`, `split`, `execute`, `final_review`

## Procedure

### 1. Validate

Confirm `planning/config.json` exists. Validate phase argument.

### 2. Confirm

Ask via AskUserQuestion: "Re-run <phase>? This will delete its artifacts and reset progress to this phase."

### 3. Delete Phase Artifacts

Based on the target phase, delete the corresponding artifacts:

- `decompose` → delete `planning/angry-ralph-interview.md`
- `plan` → delete `planning/angry-ralph-plan.md` and `planning/angry-ralph-spec.md`
- `review` → delete `planning/reviews/iteration-*/`
- `split` → delete `planning/sections/`
- `execute` → remove `.claude/angry-ralph.local.md` (section specs preserved for re-execution)
- `final_review` → delete `planning/reviews/final/`

### 4. Update State

Update `planning/config.json`:
- Set `current_phase` to the target phase
- Remove the target phase and all subsequent phases from `completed_phases`

Remove `.claude/angry-ralph.local.md` if it exists.

### 5. Report

Print: "Phase <phase> reset. Run /angry-ralph @spec.md to resume from this phase."
```

**Step 2: Add assertion to tests/test-plugin-structure.sh**

```bash
assert_exists "angry-rerun command" "commands/angry-rerun.md"
assert_contains "angry-rerun has frontmatter" "commands/angry-rerun.md" "name: angry-rerun"
```

**Step 3: Add to help.md and README.md**

**Step 4: Run tests, commit**

```bash
git add commands/angry-rerun.md commands/help.md README.md tests/test-plugin-structure.sh
git commit -m "feat: add /angry-rerun command for phase re-execution"
```

---

### Task 11: Create /angry-split command

**Files:**
- Create: `commands/angry-split.md`

**Step 1: Write the command**

```markdown
---
name: angry-split
description: Re-generate section specs from the current plan
---

# /angry-split Command

Convenience command to re-run Phase 4 (SPLIT). Regenerates section specs from the current plan.

## Usage

\`\`\`
/angry-split
\`\`\`

## Procedure

### 1. Validate

Confirm `planning/angry-ralph-plan.md` exists. If not: "No plan found. Run /angry-ralph through Phase 2 first."

Confirm `planning/config.json` exists.

### 2. Confirm

Ask via AskUserQuestion: "Re-generate section specs from the current plan? This deletes existing section specs."

### 3. Reset

Delete `planning/sections/` directory.

Update `planning/config.json`:
- Set `current_phase` to `"split"`
- Remove `"split"` and any subsequent phases from `completed_phases`

Remove `.claude/angry-ralph.local.md` if it exists.

### 4. Execute

Begin Phase 4 (SPLIT) immediately. Follow the SPLIT procedure from the angry-ralph skill.
```

**Step 2: Add assertion to tests/test-plugin-structure.sh**

```bash
assert_exists "angry-split command" "commands/angry-split.md"
assert_contains "angry-split has frontmatter" "commands/angry-split.md" "name: angry-split"
```

**Step 3: Add to help.md and README.md**

**Step 4: Run tests, commit**

```bash
git add commands/angry-split.md commands/help.md README.md tests/test-plugin-structure.sh
git commit -m "feat: add /angry-split command for re-generating section specs"
```

---

### Task 12: Final test + doc sweep

**Files:**
- Modify: `README.md` — update test count, architecture tree, command table
- Modify: `CONTRIBUTING.md` — update test count
- Run: all test suites

**Step 1: Count assertions across all test suites**

Run: `for t in tests/test-*.sh; do echo "=== $t ==="; bash "$t" | tail -1; done`

Sum up the total and update README.md and CONTRIBUTING.md with the correct count.

**Step 2: Verify architecture tree in README.md**

Ensure `commands/` section lists all 10 command files:
```
├── commands/
│   ├── angry-ralph.md
│   ├── angry-review-code.md
│   ├── angry-review-plan.md
│   ├── angry-review-section.md
│   ├── angry-skip-to.md
│   ├── angry-rerun.md
│   ├── angry-split.md
│   ├── angry-status.md
│   ├── cancel-ralph.md
│   └── help.md
```

**Step 3: Verify command table in README.md matches help.md**

Both should list all 10 commands with consistent descriptions.

**Step 4: Run all tests one final time**

Run: `for t in tests/test-*.sh; do echo "=== $t ==="; bash "$t"; echo; done`
Expected: ALL PASS, 0 failures.

**Step 5: Commit**

```bash
git add README.md CONTRIBUTING.md
git commit -m "docs: update test counts and command reference for final state"
```

**Step 6: Push**

```bash
git push
```
