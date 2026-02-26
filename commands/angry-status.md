---
name: angry-status
description: Show current angry-ralph pipeline state
---

# /angry-status Command

Display the current pipeline state at a glance. Read-only — no side effects.

## Procedure

### 1. Check for Pipeline State

Run via the Bash tool:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh status .
```

This reads `.ralph-state/pipeline.json` and `.ralph-state/loop.md`, checks `.done` markers, and prints a formatted summary:

```
angry-ralph status:
  Phase:        <current_phase>
  Completed:    <comma-separated completed_phases>
  Done markers: architect[✓/✗] review[✓/✗] execute[✓/✗]
  Review tier:  <tier> (<reviewers>)
  Config:       .ralph-state/pipeline.json
  Loop:         <section> (iteration <N>) [active|inactive]
```

If no pipeline state exists, it prints: "No active angry-ralph pipeline."
