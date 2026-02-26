# Design: Resilience Hardening, Command Renaming, and New Commands

**Date:** 2026-02-26
**Status:** Approved

## Context

The angry-ralph pipeline has failure modes that can hang the system (infinite TDD loop, CLI hangs), crash silently (state/config corruption), or leave the user unable to control the pipeline (no status, no phase skip/rerun). Additionally, the on-demand review commands lack namespace consistency. This design addresses all three categories in priority order.

## Implementation Layers

### Layer 1: Resilience Hardening

#### 1a. TDD Iteration Safety Cap

**Problem:** Tests that can never pass cause an infinite loop. No escape except `/cancel-ralph`.

**Solution:**
- New CLI arg: `--max-tdd-iterations N` (default: 20)
- Stored in `planning/config.json` as `max_tdd_iterations`
- Stop hook reads cap from config.json, allows exit when `iteration >= max_tdd_iterations`
- Main session detects cap-reached, asks user: "Section X failed after N iterations. Review errors, skip section, or keep trying (+10)?"
- Skip: mark section as `failed` in `planning/sections/index.md`, advance to next
- Keep trying: increment cap by 10, re-dispatch subagent

**Files:**
- `commands/angry-ralph.md` — add argument, add to config.json template
- `commands/help.md` — add to Configuration table
- `skills/angry-ralph/SKILL.md` — add to Command Arguments, document cap behavior in Phase 5
- `skills/angry-ralph/references/loop-protocol.md` — add cap behavior to Loop Lifecycle
- `hooks/stop-hook.sh` — read `max_tdd_iterations` from config.json, compare against `iteration`
- `tests/test-stop-hook.sh` — test cap-reached allows exit

#### 1b. State File and Config.json Validation

**Problem:** Corrupted state file causes silent wrong-resume. Corrupted config.json crashes.

**Solution — State file validation on resume:**
- Check for opening and closing `---` markers
- Check required fields present: `active`, `phase`, `completion_promise`
- If invalid: report "State file is corrupted" and offer start-fresh via AskUserQuestion

**Solution — Config.json validation on resume:**
- Run `python3 -m json.tool planning/config.json > /dev/null 2>&1`
- If invalid: report "Config file is corrupted" and offer start-fresh via AskUserQuestion

**Files:**
- `commands/angry-ralph.md` — add validation steps to Resume Detection
- `skills/angry-ralph/SKILL.md` — add validation to Resume & Recovery section

#### 1c. Git Conflict Handling

**Problem:** Atomic commit fails silently. Undocumented behavior.

**Solution:**
- After `git commit`, check exit code
- If non-zero: report git error to user via AskUserQuestion: "Commit failed: <error>. Resolve manually and retry, or skip commit?"
- Do not proceed to next section until commit succeeds or user explicitly skips

**Files:**
- `skills/angry-ralph/SKILL.md` — add error handling to Phase 5 step 6 (Atomic Commit)
- `skills/angry-ralph/references/loop-protocol.md` — add to Atomic Commit Rules

#### 1d. External Reviewer Parallel Execution + Resilience

**Problem:** Sequential CLI invocation. No timeout. If CLI hangs or errors, no recovery.

**Solution:**
- Run gemini and codex in parallel (bash background jobs)
- Detect failures: non-zero exit code
- On failure: retry once
- On second failure: skip that reviewer, note in output
- If both external CLIs fail: fall back to claude
- Collect all successful results, tag with source

**Files:**
- `agents/external-reviewer.md` — rewrite CLI invocation to parallel with retry logic
- `skills/angry-ralph/references/review-protocol.md` — document parallel execution and fallback chain

---

### Layer 2: Command Renaming

Rename on-demand review commands to `angry-` prefix for namespace consistency:

| Current | New | File |
|---------|-----|------|
| `/review-code` | `/angry-review-code` | `commands/angry-review-code.md` |
| `/review-plan` | `/angry-review-plan` | `commands/angry-review-plan.md` |
| `/review-section` | `/angry-review-section` | `commands/angry-review-section.md` |

Delete old command files. Update frontmatter `name:` field. Update all references in:
- `commands/help.md`
- `README.md`
- `tests/test-plugin-structure.sh`

---

### Layer 3: New Commands

#### `/angry-status`

**Purpose:** Read-only display of current pipeline state.

**Behavior:**
1. Read state file (if exists): phase, section, iteration, completion_promise
2. Read config.json (if exists): current_phase, completed_phases, review_tier
3. Count git log `feat(section-NN)` commits for section completion
4. Display formatted summary

**Output format:**
```
angry-ralph status:
  Phase:     execute (5 of 6)
  Section:   section-03-auth (iteration 4)
  Completed: decompose, plan, review, split
  Sections:  2/5 committed
  Review tier: adversarial (gemini + codex)
```

If no pipeline state exists: "No active angry-ralph pipeline. Run /angry-ralph @spec.md to start."

**File:** `commands/angry-status.md`

#### `/angry-skip-to <phase>`

**Purpose:** Advance pipeline to a specific phase, skipping intermediate phases.

**Valid phases:** `plan`, `review`, `split`, `execute`, `final_review`

**Behavior:**
1. Validate phase argument
2. Confirm via AskUserQuestion: "Skip to <phase>? This marks all prior phases as complete."
3. Update config.json: set `current_phase`, fill `completed_phases` with skipped phases
4. Remove state file if present
5. Report new state

Does NOT delete planning artifacts. Does NOT automatically start the new phase (user re-invokes `/angry-ralph` to resume from new position).

**File:** `commands/angry-skip-to.md`

#### `/angry-rerun <phase>`

**Purpose:** Re-run a specific phase, resetting its artifacts.

**Valid phases:** `decompose`, `plan`, `review`, `split`, `execute`, `final_review`

**Behavior:**
1. Validate phase argument
2. Confirm via AskUserQuestion: "Re-run <phase>? This resets its artifacts."
3. Delete phase-specific artifacts:
   - `decompose`: delete `planning/angry-ralph-interview.md`
   - `plan`: delete `planning/angry-ralph-plan.md`, `planning/angry-ralph-spec.md`
   - `review`: delete `planning/reviews/iteration-*/`
   - `split`: delete `planning/sections/`
   - `execute`: remove state file (sections remain, can re-execute)
   - `final_review`: delete `planning/reviews/final/`
4. Update config.json: remove phase from `completed_phases`, set `current_phase`
5. Remove state file if present
6. Report new state

**File:** `commands/angry-rerun.md`

#### `/angry-split`

**Purpose:** Convenience alias for `/angry-rerun split`.

**Behavior:**
1. Confirm: "Re-generate section specs from the current plan?"
2. Delete `planning/sections/`
3. Update config.json: set `current_phase` to `"split"`, remove `"split"` from `completed_phases`
4. Remove state file if present
5. Begin Phase 4 (SPLIT) immediately

**File:** `commands/angry-split.md`

---

### Updated Command Reference (Final State)

| Command | Description |
|---------|-------------|
| `/angry-ralph @spec.md [options]` | Start the 6-phase pipeline |
| `/cancel-ralph` | Cancel active Ralph Loop |
| `/angry-status` | Show current pipeline state |
| `/angry-skip-to <phase>` | Advance to a specific phase |
| `/angry-rerun <phase>` | Re-run a specific phase |
| `/angry-split` | Re-generate section specs from current plan |
| `/angry-review-code` | On-demand adversarial code review |
| `/angry-review-plan` | On-demand adversarial plan review |
| `/angry-review-section <name>` | On-demand section review |
| `/angry-ralph-help` | Show documentation |

### CLI Arguments (Final State)

| Argument | Default | Description |
|----------|---------|-------------|
| `--max-review-iterations N` | `3` | Max review iterations (Phase 3/6) |
| `--max-section-review-iterations N` | `2` | Max per-section review-fix iterations (Phase 5) |
| `--max-tdd-iterations N` | `20` | Max TDD loop iterations before escalating |

---

## Failure Mode Coverage (After Implementation)

| Failure | Before | After |
|---------|--------|-------|
| Infinite TDD loop | Hangs forever | Cap at N, ask user |
| External CLI hangs | Blocks review | Parallel + retry + fallback |
| State file corruption | Silent wrong resume | Validate, offer start-fresh |
| Config.json corruption | Crashes | Validate, offer start-fresh |
| Git conflict on commit | Undocumented | Detect, ask user |
| Can't see pipeline state | Read files manually | `/angry-status` |
| Can't skip phases | Manual state hacking | `/angry-skip-to` |
| Can't re-run phases | Manual state hacking | `/angry-rerun` |
| Can't re-split | Manual file deletion | `/angry-split` |

## Verification

1. Run all existing test suites — all must pass
2. New tests for TDD cap behavior in stop-hook
3. New tests for renamed command files in plugin-structure
4. New tests for new command files in plugin-structure
5. Manual verification: create corrupted state/config files, verify validation catches them
6. Manual verification: `/angry-status` with various pipeline states
