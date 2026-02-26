# Final Review Protocol

Reference protocol for Phase 6 (FINAL REVIEW) of the angry-ralph workflow. This is the last review gate before the pipeline is considered complete.

---

## When to Trigger

Initiate the final review only after ALL of the following conditions are met:

- Every implementation section in the plan has been completed and committed.
- All section-level tests pass.
- All atomic commits are in place (one per section, plus any review-fix commits).

## How to Execute

1. Create the final review output directory: `mkdir -p planning/reviews/final/`
2. Spawn the `external-reviewer` subagent via the Task tool.
3. Provide the subagent with the following inputs:
   - Review type: `"final integration review"`
   - Project directory path (absolute)
   - Plan file path: `planning/angry-ralph-plan.md`
   - Sections directory: `planning/sections/`
4. The subagent invokes the `gemini` and `codex` CLIs, pointing each at the full codebase.

## CLI Review Focus

The external CLIs are prompted to identify:

- **Integration bugs** -- issues that emerge only when sections interact with each other.
- **Emergent security vulnerabilities** -- security concerns not visible when reviewing individual sections in isolation.
- **Plan-vs-code gaps** -- differences between what the plan specifies and what was actually built.
- **Missing error handling** -- cross-cutting concerns (logging, retries, validation) that may have been overlooked.

## Triage Logic

Apply the same decision tree used in Phase 3 (adversarial review):

1. **[CRITICAL]** -- Fix immediately, re-run affected tests, commit the fix.
2. **[WARNING]** -- Evaluate impact; fix if warranted; commit if changed.
3. **Questions with clear answers** -- Resolve autonomously without user input.
4. **Questions with genuine ambiguity** -- Escalate via `AskUserQuestion` (MANDATORY).
5. **[INFO]** -- Note for the record; do not block completion.

## After Triage

- If any fixes were made, re-run the full test suite to confirm no regressions were introduced.
- Commit all fixes together: `fix: address final review findings`.
- Produce a summary report containing:
  - Total number of findings per severity level.
  - What was fixed and the corresponding commit(s).
  - What was noted but determined not actionable.
  - Any remaining concerns or known limitations.

## Completion

After the final review and any resulting fixes are complete:

1. Deactivate the state file by setting `active=false` (or remove it entirely).
2. Report full pipeline completion to the user.
3. List every commit made during the session, in chronological order.
