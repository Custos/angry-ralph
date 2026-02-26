---
name: angry-ralph
description: Start the angry-ralph unified planning and execution pipeline
hide-from-slash-command-tool: "true"
---

# /angry-ralph Command

When the user invokes `/angry-ralph`, execute the following steps in order.

## 1. Argument Parsing

Parse the invocation arguments:

- **`@file.md`** (required) -- The input specification file. This is the `@`-prefixed file reference provided by the user.
- **`--max-review-iterations N`** (optional, default: `3`) -- Maximum adversarial review iterations for Phase 3 and Phase 6.
- **`--max-section-review-iterations N`** (optional, default: `2`) -- Maximum per-section review-fix iterations during Phase 5.
- **`--max-tdd-iterations N`** (optional, default: `20`) -- Maximum TDD loop iterations per section before escalating to user.

If no `@file.md` argument is provided, report an error and display usage:

```
Error: No spec file provided.

Usage: /angry-ralph @spec-file.md [options]

  @spec-file.md                    Path to the input specification file (required)
  --max-review-iterations N        Max review loop iterations (default: 3)
  --max-section-review-iterations N  Max per-section review-fix iterations (default: 2)
  --max-tdd-iterations N           Max TDD loop iterations per section (default: 20)
```

Stop execution after displaying usage.

Validate that the referenced spec file exists and is readable. Resolve its absolute path and store it as `SPEC_FILE`. Derive `SPEC_DIR` as the directory containing the spec file.

## 2. Environment Validation

Run the environment validation script via the Bash tool:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/checks/validate-env.sh
```

If the script exits with a non-zero code, report the validation error to the user and stop (this means a required tool like `git`, `python3`, or `claude` is missing). Do not proceed to any subsequent step.

If the script succeeds, capture its JSON stdout output. This contains `review_tier` and `available_reviewers` which determine which review tier is active. Store these values for inclusion in `planning/config.json` during setup.

Confirm the current working directory is inside a git repository by running:

```bash
git rev-parse --is-inside-work-tree
```

If not inside a git repo, ask the user via AskUserQuestion whether to initialize one with `git init`. Do not initialize without explicit consent. If the user declines, stop execution.

## 3. Resume Detection

Check for evidence of a prior angry-ralph run:

1. Check if `.claude/angry-ralph.local.md` exists in the project root.
2. Check if a `planning/` directory exists as a sibling to the spec file (`SPEC_DIR/planning/`).

If **either** artifact exists:

- Read `planning/config.json` if it exists to determine the last recorded phase.

  **Validate config.json integrity** before parsing. Run:

  ```bash
  python3 -m json.tool planning/config.json > /dev/null 2>&1
  ```

  If exit code is non-zero, report: "Config file is corrupted." and offer start-fresh.

- Read `.claude/angry-ralph.local.md` if it exists to determine active state.

  **Validate state file integrity** before reading fields. Check that the file contains opening and closing `---` markers and at least the `active`, `phase`, and `completion_promise` fields. Run:

  ```bash
  python3 -c "
  import sys
  content = open(sys.argv[1]).read()
  markers = content.count('---')
  if markers < 2:
      print('invalid')
      sys.exit(0)
  for field in ['active:', 'phase:', 'completion_promise:']:
      if field not in content:
          print('invalid')
          sys.exit(0)
  print('valid')
  " .claude/angry-ralph.local.md
  ```

  If the output is `invalid`, report: "State file is corrupted. Starting fresh is recommended." Include this in the AskUserQuestion options alongside "Resume" and "Start fresh".
- Inform the user that a previous run was detected and summarize its state (phase, section if applicable).
- Ask the user via AskUserQuestion: "Resume the previous run, or start fresh? (Starting fresh will delete existing planning artifacts.)"
- If the user chooses **resume**: skip to the appropriate phase based on detected state. Consult the angry-ralph skill's Resume & Recovery section for the full procedure.
- If the user chooses **start fresh**: delete `planning/` directory and `.claude/angry-ralph.local.md`, then continue with setup below.

If **neither** artifact exists, proceed directly to setup.

## 4. Setup

Create the planning directory structure:

```bash
mkdir -p "${SPEC_DIR}/planning/reviews"
mkdir -p "${SPEC_DIR}/planning/sections"
```

Initialize the session config file at `${SPEC_DIR}/planning/config.json`:

```json
{
  "spec_file": "<absolute path to spec file>",
  "max_review_iterations": <N>,
  "max_section_review_iterations": <N>,
  "max_tdd_iterations": <N>,
  "started_at": "<ISO 8601 timestamp>",
  "current_phase": "decompose",
  "completed_phases": [],
  "review_tier": "<adversarial|partial|self-reflection>",
  "available_reviewers": ["<list from validate-env output>"]
}
```

Use actual resolved values for all fields. The `review_tier` and `available_reviewers` come from the JSON output of the environment validation script.

## 5. Handoff to Skill

The angry-ralph skill handles the full 6-phase workflow. Create task list items to track progress:

1. **Phase 1: DECOMPOSE** -- Read spec, interview user, identify planning units
2. **Phase 2: PLAN** -- Write detailed implementation plan with sections
3. **Phase 3: REVIEW** -- LLM review via available reviewers (tier-dependent)
4. **Phase 4: SPLIT** -- Parse plan into section specs
5. **Phase 5: EXECUTE** -- TDD Ralph Loop for each section
6. **Phase 6: FINAL REVIEW** -- Integration review of completed codebase

After creating the task list, begin **Phase 1: DECOMPOSE** immediately. Follow the procedures defined in the angry-ralph skill, starting with the DECOMPOSE phase instructions. Read the spec file and begin the interview process.
