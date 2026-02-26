---
name: angry-split
description: Re-generate section specs from the current plan
---

# /angry-split Command

Convenience command to re-run Phase 4 (SPLIT). Regenerates section specs from the current plan.

## Usage

```
/angry-split
```

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
