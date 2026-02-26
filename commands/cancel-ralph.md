---
name: cancel-ralph
description: Cancel the active angry-ralph loop
---

# /cancel-ralph Command

Cancel the active angry-ralph loop by removing the state file.

## Procedure

1. Check whether `.ralph-state/loop.md` exists.

2. If the state file does **not** exist:
   - Report: "No active angry-ralph loop found. Nothing to cancel."
   - Stop.

3. If the state file exists:
   - Read state via the Bash tool:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh read .ralph-state/loop.md iteration
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh read .ralph-state/loop.md phase
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh read .ralph-state/loop.md current_section
   ```

   - Remove the state file: `rm .ralph-state/loop.md`
   - Report: "Cancelled angry-ralph loop at iteration N (phase: X, section: Y)"

## Notes

- Non-destructive to project files. Only removes the loop state file.
- Implementation artifacts (code, tests, plans) are left intact.
- The stop hook will no longer intercept exits once the state file is removed.
- To restart, re-invoke `/angry-ralph` or `/angry-execute`.
