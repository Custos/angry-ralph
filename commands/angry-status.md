---
name: angry-status
description: Show current angry-ralph pipeline state
---

# /angry-status Command

Display the current pipeline state at a glance. Read-only — no side effects.

## Procedure

### 1. Check for Pipeline State

Check if `planning/config.json` exists. If not, check if `.claude/angry-ralph.local.md` exists. If neither exists:

```
No active angry-ralph pipeline. Run /angry-ralph @spec.md to start.
```

### 2. Read State Sources

Read available state sources:
- `planning/config.json` — `current_phase`, `completed_phases`, `review_tier`, `available_reviewers`, `max_review_iterations`, `max_section_review_iterations`, `max_tdd_iterations`
- `.claude/angry-ralph.local.md` — `phase`, `current_section`, `iteration`, `completion_promise`, `review_iteration`
- Git log — count `feat(section-NN)` commits for section completion
- `planning/sections/index.md` — total section count (if exists)

### 3. Display Summary

Print formatted output:

```
angry-ralph status:
  Phase:      <current_phase> (<N> of 6)
  Section:    <current_section> (iteration <N>)    [only during execute phase]
  Completed:  <comma-separated completed_phases>
  Sections:   <committed>/<total> committed        [only if sections exist]
  Review tier: <tier> (<reviewers>)
  Config:     planning/config.json
  State file: .claude/angry-ralph.local.md [active|inactive|missing]
```

Adapt output to available information. Omit lines where data is not applicable (e.g., don't show Section line outside execute phase).
