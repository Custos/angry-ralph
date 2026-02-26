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
   - Active review tier and available reviewers (from `planning/config.json`)
   - Project directory path (absolute)
   - Plan file path: `planning/angry-ralph-plan.md`
   - Sections directory: `planning/sections/`
4. The subagent invokes the available reviewers based on the active tier:
   - **Adversarial tier**: gemini + codex CLIs
   - **Partial tier**: available external CLI + claude fallback
   - **Self-Reflection tier**: claude fallback only

## Review Tier Transparency

Before spawning the subagent, print the active review tier:

```
angry-ralph: Final review tier — <TIER_LABEL>
Reviewers: <comma-separated list>
```

## CLI Review Focus

All reviewers (regardless of tier) are prompted to identify:

- **Integration bugs** -- issues that emerge only when sections interact with each other.
- **Emergent security vulnerabilities** -- security concerns not visible when reviewing individual sections in isolation.
- **Plan-vs-code gaps** -- differences between what the plan specifies and what was actually built.
- **Missing error handling** -- cross-cutting concerns (logging, retries, validation) that may have been overlooked.

## Source Attribution

Every finding in the review output must be tagged with its source:
- `[Gemini]` -- Finding from Gemini CLI
- `[Codex]` -- Finding from Codex CLI
- `[Claude-Reflection]` -- Finding from Claude fallback session

This enables the user to assess the variance and quality of each review source.

## Triage Logic

Apply the same decision tree used in Phase 3 (adversarial review):

1. **[CRITICAL]** -- Fix immediately, re-run affected tests, commit the fix.
2. **[WARNING]** -- Evaluate impact; fix if warranted; commit if changed.
3. **Questions with clear answers** -- Resolve autonomously without user input.
4. **Questions with genuine ambiguity** -- Escalate via `AskUserQuestion` (MANDATORY).
5. **[INFO]** -- Note for the record; do not block completion.

When triaging, consider the source: findings from external models carry higher
adversarial confidence than Claude-Reflection findings, which may share blind
spots with the implementation session.

## After Triage

- If any fixes were made, re-run the full test suite to confirm no regressions were introduced.
- Commit all fixes together: `fix: address final review findings`.
- Produce a summary report containing:
  - Total number of findings per severity level, grouped by source.
  - What was fixed and the corresponding commit(s).
  - What was noted but determined not actionable.
  - Any remaining concerns or known limitations.
  - The active review tier used for this review.

## Completion

After the final review and any resulting fixes are complete:

1. Deactivate the state file by setting `active=false` (or remove it entirely).
2. Report full pipeline completion to the user.
3. List every commit made during the session, in chronological order.
