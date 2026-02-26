# Loop Protocol: Execute Phase

Reference protocol for the Ralph Loop state machine during Phase 5 (EXECUTE). The loop uses a state file and Stop hook to create an iterative execution cycle that enforces TDD-gated section completion.

---

## State File

Location: `.claude/angry-ralph.local.md`

Format: YAML frontmatter between `---` markers, followed by the prompt body.

```yaml
---
active: true
phase: execute
iteration: 1
max_iterations: 0
current_section: section-01-name
completion_promise: SECTION_COMPLETE
started_at: "2026-02-25T12:00:00Z"
spec_file: path/to/spec.md
planning_dir: path/to/planning/
---

The prompt text that gets fed back on each loop iteration.
```

### Field Definitions

- `active` — `true` or `false`. Controls whether the loop is running.
- `phase` — One of: `plan`, `review`, `split`, `execute`, `final_review`.
- `iteration` — Current iteration number. Incremented by the Stop hook on each blocked exit.
- `max_iterations` — Maximum iterations allowed. `0` means unlimited (test-gated exit only).
- `current_section` — The section identifier currently being implemented.
- `completion_promise` — The exact string that must appear in output to permit exit.
- `started_at` — ISO 8601 timestamp of when the loop was activated.
- `spec_file` — Path to the original spec file.
- `planning_dir` — Path to the planning directory.

---

## Loop Lifecycle

1. **Activate** — Create or update the state file with `phase=execute` and set `current_section`.
2. **Iterate** — Work on the section: write tests first, then write implementation to pass them.
3. **Exit attempt** — The session attempts to stop after completing work.
4. **Stop hook intercepts** — Read the state file and check the transcript for the completion promise.
5. **Promise found** — Allow exit. Proceed to atomic commit.
6. **Promise not found** — Block exit. Increment `iteration` and feed back the prompt body.
7. **Successful exit** — Perform an atomic commit and advance to the next section.

---

## Activating the Loop

To start the loop for a given section:

1. Read the section spec from `planning/sections/section-NN-name.md`.
2. Construct the prompt body from the section spec content combined with TDD instructions.
3. Create or update the state file with:
   - `phase=execute`
   - `iteration=1`
   - `current_section=section-NN-name`
   - `completion_promise=SECTION_COMPLETE`
4. The Stop hook is now active and will intercept all exit attempts.

---

## Section-to-Section Transition

After a section completes (all tests pass and the commit is done):

1. Update the state file: set `current_section` to the next section identifier.
2. Reset `iteration` to `1`.
3. Replace the prompt body with the next section's spec content.
4. If no more sections remain, set `active=false` or remove the state file entirely.

---

## Atomic Commit Rules

After each section passes all tests:

1. Stage only the files changed for the completed section.
2. Create a commit with message format: `feat(section-NN): <section-name>`.
3. Do not stage unrelated files.
4. Do not amend previous commits.

---

## Cancel Mechanism

The `/cancel-ralph` command terminates the loop:

1. Check whether `.claude/angry-ralph.local.md` exists.
2. Read the `iteration` count from the state file for reporting.
3. Remove the state file.
4. Report: "Cancelled angry-ralph loop at iteration N".
