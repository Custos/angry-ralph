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

## Review-Fix-Review Loop

Phase 6 uses a self-healing loop: review → triage → fix → re-run tests → re-review → repeat until clean or max iterations reached. This ensures fixes are verified and don't introduce new issues.

```
iteration = 0
max_iterations = max_review_iterations from config.json (default 3)

while iteration < max_iterations:
    create review directory: planning/reviews/final/iteration-{iteration + 1}/
    spawn external-reviewer subagent
    receive review payload
    triage all findings per the decision tree below
    if no CRITICAL and no actionable WARNING:
        break  # clean review — proceed to completion
    fix all CRITICAL and actionable WARNING findings
    re-run full test suite — all tests must pass
    commit fixes: "fix: address final review findings (iteration N)"
    iteration += 1

if iteration == max_iterations AND findings remain:
    log remaining findings to planning/reviews/final/unresolved.md
    proceed to completion (do NOT prompt the user)
```

### Triage Decision Tree

Apply to each finding and question in the review payload:

1. **[CRITICAL]** -- Fix immediately. These block completion.
2. **[WARNING]** -- Evaluate impact. Fix if the warning represents a real risk to correctness, security, or reliability. Document rationale for any warning left unaddressed.
3. **Questions with clear answers** -- Resolve autonomously from available context.
4. **Questions with genuine ambiguity** -- Escalate via `AskUserQuestion` (MANDATORY).
5. **[INFO]** -- Note for the record. Do not block.

When triaging, consider the source: findings from external models carry higher adversarial confidence than Claude-Reflection findings, which may share blind spots with the implementation session.

### Fix Rules

- Fix all CRITICAL findings before re-reviewing. Do not defer criticals.
- After fixing, re-run the full test suite. All tests must pass before committing.
- Commit fixes per iteration: `fix: address final review findings (iteration N)`.
- Do NOT bundle fixes from multiple iterations into a single commit.

### Re-Review Verification

Each re-review iteration spawns a fresh external-reviewer subagent. The reviewer sees the current codebase state (including prior fixes). This ensures:
- Fixes actually resolved the identified issues
- Fixes didn't introduce new CRITICAL issues
- Cross-cutting concerns are re-evaluated in light of changes

### Iteration Cap

When `max_review_iterations` is exhausted with findings still open:
- Write all remaining findings to `planning/reviews/final/unresolved.md`
- Proceed to pipeline completion — do NOT prompt the user or block
- The unresolved findings file serves as a production roadmap

## Summary Report

After the loop exits (clean or capped), produce a summary report at `planning/reviews/final/review-summary.md`:

- Total iterations run
- Total findings per severity, grouped by source
- What was fixed and the corresponding commit(s)
- What was noted but not actionable
- Any remaining unresolved findings (with reference to `unresolved.md`)
- The active review tier used

## Completion

After the final review loop and any resulting fixes:

1. Deactivate the state file by setting `active=false` (or remove it entirely).
2. Report full pipeline completion to the user.
3. List every commit made during the session, in chronological order.
