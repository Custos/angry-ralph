---
name: angry-rerun
description: Re-run a specific angry-ralph pipeline phase
---

# /angry-rerun Command

Re-run a specific phase, resetting its artifacts.

## Usage

```
/angry-rerun <phase>
```

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
