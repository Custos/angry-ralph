---
name: cancel-ralph
description: Cancel the active angry-ralph loop
---

# Cancel Ralph Loop

Cancel the active angry-ralph loop by removing the state file.

## Procedure

1. Check whether the state file `.claude/angry-ralph.local.md` exists.

2. If the state file does **not** exist:
   - Report to the user: "No active angry-ralph loop found. Nothing to cancel."
   - Stop. No further action is needed.

3. If the state file exists:
   - Read the YAML frontmatter from `.claude/angry-ralph.local.md`.
   - Extract the `iteration` value.
   - Extract the `phase` value.
   - Extract the `current_section` value.
   - Remove the state file: `rm .claude/angry-ralph.local.md`
   - Report to the user: "Cancelled angry-ralph loop at iteration N (phase: X, section: Y)"
     where N is the iteration count, X is the phase, and Y is the current section name.

## Notes

- This command is non-destructive to project files. It only removes the state file.
- Implementation artifacts (code, tests, plans) are left intact.
- The stop hook will no longer intercept exits once the state file is removed.
- To restart the loop after cancelling, re-invoke `/angry-ralph` with the original spec file.
