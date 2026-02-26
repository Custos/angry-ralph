# Review Protocol — Adversarial Review Loop (Phase 3)

This reference governs Phase 3 of the angry-ralph workflow. It defines how to spawn
external reviewers, triage their feedback, and iterate until the plan is solid.

## Review Tier Detection

Before the first review iteration, determine the active review tier from the environment
validation output stored in `.ralph-state/pipeline.json`:

| Tier | Condition | Reviewers Used |
|------|-----------|----------------|
| **Adversarial** | gemini + codex available | gemini, codex |
| **Partial** | one external CLI available | available CLI + claude fallback |
| **Self-Reflection** | no external CLIs | claude only |

### Transparency Message

Print the following message before beginning the review loop:

```
angry-ralph: Review tier — <TIER_LABEL>
Reviewers: <comma-separated list of active reviewers>
```

Example outputs:
- `angry-ralph: Review tier — Adversarial (gemini + codex)`
- `angry-ralph: Review tier — Partial (codex + claude fallback)`
- `angry-ralph: Review tier — Self-Reflection (claude only)`

## Spawning the External Reviewer

Spawn the `external-reviewer` subagent via the Task tool with `subagent_type`
set to `external-reviewer`. The subagent has access to **Bash and Read tools only** --
it invokes the available CLIs to perform review. It cannot modify any files.

When spawning, include in the prompt:
- The active review tier
- Which reviewers are available (from `.ralph-state/pipeline.json` `available_reviewers` field)
- The review type (plan review or final integration review)
- File paths to review artifacts

### CLI Invocation Rules

Pass file paths as arguments to all CLIs. **Never pipe content via stdin.**

#### Gemini Invocation (when available)

```
gemini -p "<review prompt referencing file paths>" --approval-mode plan -o text
```

- Use `--approval-mode plan` to enforce read-only operation.
- Use `-o text` to capture plain text output.
- Reference the plan file by absolute path: `$(pwd)/planning/angry-ralph-plan.md`.

#### Codex Invocation (when available)

```
codex exec "<review prompt referencing file paths>" -C "$(pwd)" --sandbox read-only -o <output-file>
```

- Use `--sandbox read-only` to prevent any filesystem writes outside the output file.
- Use `-C "$(pwd)"` to set the working directory.
- Write output to `planning/reviews/iteration-N/codex-review.md`.

#### Claude Fallback Invocation (when used)

```
claude -p "<review prompt referencing file paths>" --output-format text
```

- Use `--output-format text` to get plain text output.
- The prompt must explicitly state "separate session" and "no prior context" to maximize independence.
- Write output to `planning/reviews/iteration-N/claude-review.md`.

## Parallel Execution and Fallback

When multiple reviewers are available, run them in parallel to minimize wall-clock time:

1. **Adversarial tier**: Launch gemini and codex simultaneously as background jobs.
2. **Wait for both**: Collect exit codes.
3. **Retry on failure**: If a CLI exits with error, retry once. If retry fails, skip and note in output.
4. **Fallback**: If both external CLIs fail, invoke claude as fallback.
5. **Collect results**: Merge all successful reviewer outputs, tagged with source.

This ensures review proceeds even when individual CLIs are broken, and maximizes throughput by running reviewers concurrently.

## Review Output Format

Instruct all CLIs to produce structured markdown with these sections:

### `## Findings`

Each finding prefixed with a severity tag AND a source attribution tag:
- `[Gemini] [CRITICAL]` -- Critical finding from Gemini.
- `[Codex] [WARNING]` -- Warning from Codex.
- `[Claude-Reflection] [INFO]` -- Informational note from Claude fallback.

Severity levels:
- `[CRITICAL]` -- Blocking issues that must be fixed before proceeding.
- `[WARNING]` -- Potential risks that warrant evaluation.
- `[INFO]` -- Observations and suggestions for awareness only.

### `## Questions`

Ambiguities, missing context, or unclear requirements identified by the reviewer.
Each question tagged with its source: `[Gemini]`, `[Codex]`, or `[Claude-Reflection]`.

### `## Summary`

Overall assessment of the plan's quality and readiness.

## Review File Storage

Before spawning the subagent, create the review directory for the current iteration:

```
mkdir -p planning/reviews/iteration-N/
```

Store review outputs at:
- `planning/reviews/iteration-N/gemini-review.md` -- Gemini output (when available).
- `planning/reviews/iteration-N/codex-review.md` -- Codex output (when available).
- `planning/reviews/iteration-N/claude-review.md` -- Claude fallback output (when used).

For the final review (Phase 6), store in:
- `planning/reviews/final/gemini-review.md`
- `planning/reviews/final/codex-review.md`
- `planning/reviews/final/claude-review.md`

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

When triaging, note the source attribution tag on each finding. Findings from
external models (Gemini, Codex) carry higher adversarial confidence than
Claude-Reflection findings, which may share blind spots with the planning session.

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
has passed review scrutiny.

### Max Iterations Reached

When the loop exhausts all iterations without reaching a clean review, present
the user with the remaining open items and ask whether to:
- Proceed to the split phase with known issues noted.
- Continue with additional review iterations.

## Hard Rule -- No Guessing

If ANY question from a reviewer reveals a genuine information gap that
cannot be resolved from available context (the spec, the plan, the codebase,
or prior user answers), use AskUserQuestion. No guessing. No fabricating.
No "I'll assume..." phrasing. Pause and wait for the user.

This rule is non-negotiable and applies to every review iteration, including
the final review in Phase 6.
