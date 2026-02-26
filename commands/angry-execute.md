---
name: angry-execute
description: Run Phases 4-6 (Split + TDD Execute + Final Review) of the angry-ralph pipeline
---

# /angry-execute Command

Run Phases 4-6: Split the plan into sections, execute each via TDD Ralph Loop, and run final review.

## 1. Argument Parsing

- **`--auto`** (optional) -- Skip confirmation prompts.
- **`--rebuild <section>`** (optional) -- Delete a section's done marker and re-run it.

If `--rebuild` is passed:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh remove_done . "<section>"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh remove_from_list . "completed_sections" "<section>"
```

Both the `.done` marker file and the `completed_sections` array entry are removed, so the section will be re-executed.

## 2. Prerequisites

Verify `.ralph-state/pipeline.json` exists:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh read . current_phase
```

If empty → error: "No pipeline state found. Run /angry-architect or /angry-ralph first."

Verify Phases 1-2 complete:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh check_done . architect
```

If exit non-zero → error: "Phases 1-2 not complete. Run /angry-architect @spec.md first."

## 3. Phase 4: SPLIT

Check if Phase 3 was run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh check_done . review
```

If not done, ask user: "Phase 3 (review) was not run. Proceed without review, or run /angry-review plan first?"

Follow the angry-ralph skill's Phase 4 (SPLIT) instructions.

## 4. Phase 5: EXECUTE (Ralph Loop + TDD)

For each section in `.planning/sections/index.md`:

Read completed sections:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh read . completed_sections
```

Skip sections already in `completed_sections`. For incomplete sections, execute via TDD Ralph Loop per the skill instructions. Run mechanical gates before section review:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/mechanical-gates.sh run_all "<test_runner>" "<section_spec>" "."
```

On section completion, append to completed_sections:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh append . completed_sections "<section-name>"
```

When all sections complete:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write_done . execute
```

### Strict .done Gating

**MUST NOT** write `execute.done` unless the test suite passes (exit 0 on final test run). If `max_tdd_iterations` is hit and tests still fail:

```
FATAL: TDD cap reached for <section>. Tests still failing after <N> iterations.
Pipeline halted. Review errors and re-run with /angry-execute --rebuild <section>.
```

Exit with non-zero status. Do not write any `.done` marker.

## 5. Phase 6: FINAL REVIEW

Follow the angry-ralph skill's Phase 6 (FINAL REVIEW) instructions.

On completion:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . current_phase complete
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh append . completed_phases execute
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh append . completed_phases final_review
```

Report pipeline completion.
