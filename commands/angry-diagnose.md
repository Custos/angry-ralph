---
name: angry-diagnose
description: Adversarial bug diagnosis — differential diagnosis via external LLMs, hypothesis-driven TDD fix
---

# /angry-diagnose Command

Adversarial bug investigation pipeline. Generates competing hypotheses for a bug's root cause using external LLMs, then systematically proves/disproves each hypothesis via failing tests before implementing the fix.

## 1. Argument Parsing

Parse the invocation arguments:

- **`@file` references** (optional, multiple) -- Error logs, stack traces, suspect source files as context.
- **Prompt text** (required) -- Description of the problem/symptom.
- **`--auto`** (optional) -- Skip clarifying questions, auto-accept findings, test all hypotheses.
- **`--max-hypotheses N`** (optional, default: `5`) -- Maximum number of hypotheses to generate.
- **`--help`** (optional) -- Print command reference and exit.

### --help Output

If `--help` is passed, print the following and stop:

```
angry-diagnose — Adversarial bug diagnosis with differential diagnosis and hypothesis-driven TDD.

Usage:
  /angry-diagnose [@context-files...] "problem description" [--auto] [--max-hypotheses N]

Examples:
  /angry-diagnose "the API returns 500 on large payloads"
  /angry-diagnose @error.log "users can't login after password reset"
  /angry-diagnose @src/auth.ts @error.log "this middleware leaks sessions"

Options:
  --auto                Skip questions, auto-accept findings, test all hypotheses.
  --max-hypotheses N    Max competing hypotheses to generate (default: 5).

Phases:
  1. INVESTIGATE    Gather context, build case file, interview user.
  2. DIAGNOSE       Generate competing hypotheses via external LLMs (differential diagnosis).
  3. FIX            Prove/disprove hypotheses via diagnostic tests, fix confirmed root cause.
  4. VERIFY         Mechanical gates + adversarial verification of the fix.

State: .ralph-state/ (gitignored)
Artifacts: .planning/diagnosis/ (gitignored)
```

If no prompt text is provided and `--help` is not passed, report the error and display the help text.

## 2. Environment Validation

Run via the Bash tool:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/checks/validate-env.sh
```

Halt on non-zero exit. Capture JSON stdout (`review_tier`, `available_reviewers`).

Confirm git repository:

```bash
git rev-parse --is-inside-work-tree
```

If not in a git repo:
- **`--auto` mode**: Run `git init` automatically.
- **Interactive mode**: Ask whether to `git init`.

## 3. Backwards Compatibility Migration

Run the migration check:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh migrate .
```

If output is `migrated`, inform user.

## 4. Resume Detection

Check `.ralph-state/` for prior diagnosis state:

- `.ralph-state/phases/investigate.done` → Phase 1 done
- `.ralph-state/phases/diagnose.done` → Phase 2 done
- `.ralph-state/phases/fix.done` → Phase 3 done
- `.ralph-state/pipeline.json` → read `mode` field; only resume if `mode` is `"diagnose"`

If prior diagnosis state detected:
- **`--auto` mode**: Resume automatically from the last completed phase.
- **Interactive mode**: Ask via AskUserQuestion: "Resume the previous diagnosis, or start fresh?"

If start fresh: `rm -rf .ralph-state/ .planning/diagnosis/` and continue.

If prior state exists but `mode` is NOT `"diagnose"` (e.g., an angry-ralph pipeline is active): warn the user and ask whether to proceed (this will create diagnosis artifacts alongside existing pipeline artifacts).

## 5. Setup

Create pipeline state. Use the existing `pipeline.sh create` with the problem description as the spec_file field, then override diagnosis-specific fields:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh create . "<PROBLEM_DESCRIPTION>" "<MODE>" "2" "0" "0" "<REVIEW_TIER>" "<AVAILABLE_REVIEWERS>"
```

Then set diagnosis-specific fields:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . current_phase investigate
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . mode diagnose
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . problem_description "<PROBLEM_DESCRIPTION>"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . max_hypotheses "<MAX_HYPOTHESES>"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib/pipeline.sh write . auto_mode "<true|false>"
```

Create the diagnosis artifacts directory:

```bash
mkdir -p .planning/diagnosis/reviews
```

## 6. Handoff to Skill

Begin Phase 1 (INVESTIGATE) immediately. Follow the diagnosis protocol at `references/diagnosis-protocol.md`.

### --auto Behavior

When `auto_mode` is `"true"` in pipeline.json:
- **Phase 1**: Skip interview questions. Work with provided context only.
- **Phase 2**: Skip hypothesis presentation. Proceed directly to fix.
- **Phase 3**: Test ALL hypotheses (don't stop at first confirmation). Auto-accept.
- **Phase 4**: Run verification, auto-accept findings.
