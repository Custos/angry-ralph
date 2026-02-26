# Review Protocol — Adversarial Review Loop (Phase 3)

This reference governs Phase 3 of the angry-ralph workflow. It defines how to spawn
external reviewers, triage their feedback, and iterate until the plan is solid.

## Spawning the External Reviewer

Spawn the `external-reviewer` subagent via the Task tool with `subagent_type`
set to `external-reviewer`. The subagent has access to **Bash and Read tools only** --
it invokes the `gemini` and `codex` CLIs to perform adversarial review. It cannot
modify any files.

### CLI Invocation Rules

Pass file paths as arguments to both CLIs. **Never pipe content via stdin.**

#### Gemini Invocation

```
gemini -p "<review prompt referencing file paths>" --approval-mode plan -o text
```

- Use `--approval-mode plan` to enforce read-only operation.
- Use `-o text` to capture plain text output.
- Reference the plan file by absolute path: `$(pwd)/planning/angry-ralph-plan.md`.

#### Codex Invocation

```
codex exec "<review prompt referencing file paths>" -C "$(pwd)" --sandbox read-only -o <output-file>
```

- Use `--sandbox read-only` to prevent any filesystem writes outside the output file.
- Use `-C "$(pwd)"` to set the working directory.
- Write output to `planning/reviews/iteration-N/codex-review.md`.

## Review Output Format

Instruct both CLIs to produce structured markdown with these sections:

### `## Findings`

Each finding prefixed with a severity tag:
- `[CRITICAL]` -- Blocking issues that must be fixed before proceeding.
- `[WARNING]` -- Potential risks that warrant evaluation.
- `[INFO]` -- Observations and suggestions for awareness only.

### `## Questions`

Ambiguities, missing context, or unclear requirements identified by the reviewer.

### `## Summary`

Overall assessment of the plan's quality and readiness.

## Review File Storage

Before spawning the subagent, create the review directory for the current iteration:

```
mkdir -p planning/reviews/iteration-N/
```

Store review outputs at:
- `planning/reviews/iteration-N/gemini-review.md` -- Gemini output (capture from stdout).
- `planning/reviews/iteration-N/codex-review.md` -- Codex output (written by `-o` flag).

For the final review (Phase 6), store in:
- `planning/reviews/final/gemini-review.md`
- `planning/reviews/final/codex-review.md`

## Triage Decision Tree

After receiving the review payload, process each finding and question as follows:

1. **[CRITICAL] findings** -- Fix the plan immediately. These are blocking issues.
   Do not proceed until every critical finding is resolved.

2. **[WARNING] findings** -- Evaluate severity. Fix if the warning represents a
   real risk to correctness, security, or reliability. Document the rationale
   for any warning left unaddressed.

3. **Questions with clear answers** -- Answer from available context (the spec,
   the plan, project knowledge). Update the plan to incorporate the answer so
   the question does not recur.

4. **Questions with genuine ambiguity** -- MANDATORY: use AskUserQuestion to
   pause and get user input. Do not guess. Do not fabricate. Do not assume.
   Wait for the user to respond before continuing.

5. **[INFO] items** -- Note for awareness. Do not block on these. Optionally
   incorporate useful suggestions into the plan.

## Iteration Control

```
iteration = 0
max_iterations = configured value (default 3)

while iteration < max_iterations:
    create review directory: planning/reviews/iteration-{iteration + 1}/
    spawn external-reviewer subagent
    receive review payload
    triage all findings and questions per the decision tree above
    apply fixes to the plan as needed
    if no CRITICAL/WARNING items AND no unresolved questions:
        break
    iteration += 1

if iteration == max_iterations:
    inform user that max review iterations have been reached
    ask user via AskUserQuestion: proceed to split phase, or continue reviewing?
```

### Break Condition

Exit the loop early when a review iteration returns zero CRITICAL findings,
zero WARNING findings, and zero unresolved questions. This indicates the plan
has passed adversarial scrutiny.

### Max Iterations Reached

When the loop exhausts all iterations without reaching a clean review, present
the user with the remaining open items and ask whether to:
- Proceed to the split phase with known issues noted.
- Continue with additional review iterations.

## Hard Rule -- No Guessing

If ANY question from Gemini or Codex reveals a genuine information gap that
cannot be resolved from available context (the spec, the plan, the codebase,
or prior user answers), use AskUserQuestion. No guessing. No fabricating.
No "I'll assume..." phrasing. Pause and wait for the user.

This rule is non-negotiable and applies to every review iteration, including
the final review in Phase 6.
