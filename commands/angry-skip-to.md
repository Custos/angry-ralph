---
name: angry-skip-to
description: Advance angry-ralph pipeline to a specific phase
---

# /angry-skip-to Command

Skip to a specific pipeline phase, marking all prior phases as complete.

## Usage

```
/angry-skip-to <phase>
```

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
