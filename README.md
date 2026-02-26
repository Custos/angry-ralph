# angry-ralph

A Claude Code plugin that transforms a feature spec into a fully implemented, reviewed, and tested codebase — using adversarial multi-LLM review and TDD-gated execution.

> **Built on the shoulders of giants.** angry-ralph unifies and extends three foundational projects by [piercelamb](https://github.com/piercelamb):
>
> - [**deep-project**](https://github.com/piercelamb/deep-project) — Feature decomposition and stakeholder interviews
> - [**deep-plan**](https://github.com/piercelamb/deep-plan) — Detailed implementation planning with section-level specs
> - [**deep-implement**](https://github.com/piercelamb/deep-implement) — TDD execution with strict red-green cycles
>
> angry-ralph combines all three into a single self-contained plugin, adds adversarial review via Gemini and Codex CLIs, and enforces execution with a built-in [Ralph Wiggum Loop](https://github.com/anthropics/claude-code/blob/main/HOOKS.md) — a Stop hook that blocks exit until tests pass.

## What It Does

Give angry-ralph a spec file and it runs a 6-phase pipeline:

| Phase | What Happens |
|-------|-------------|
| **1. DECOMPOSE** | Reads your spec, interviews you to clarify scope, identifies planning units |
| **2. PLAN** | Writes a detailed implementation plan with numbered sections |
| **3. ADVERSARIAL REVIEW** | Dispatches Gemini and Codex CLIs to review the plan, triages findings, iterates up to N times |
| **4. SPLIT** | Finalizes the plan into individual section spec files |
| **5. EXECUTE** | TDD Ralph Loop per section — tests first, implement, all tests pass, atomic commit |
| **6. FINAL REVIEW** | External LLMs review the completed codebase for integration issues |

Every phase produces persistent artifacts on disk. If the session is interrupted, re-running the command detects prior state and offers to resume.

## Prerequisites

**Required:**
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude` in PATH)
- `git`
- `python3`

**Optional (upgrades review tier):**
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini` in PATH)
- [Codex CLI](https://github.com/openai/codex) (`codex` in PATH)

angry-ralph works out-of-the-box with only the required tools. External CLIs upgrade the review from Self-Reflection (Claude reviewing its own work in a fresh session) to Adversarial (cross-model scrutiny).

Verify your environment:

```bash
bash /path/to/angry-ralph/scripts/checks/validate-env.sh
```

## Quick Start

### 1. Clone

```bash
git clone https://github.com/Custos/angry-ralph.git
```

### 2. Launch Claude Code with the plugin

From your **target project directory** (where the code will be built):

```bash
claude --plugin-dir /path/to/angry-ralph
```

Or for fully autonomous execution (no permission prompts):

```bash
claude --plugin-dir /path/to/angry-ralph --dangerously-skip-permissions
```

> **Warning:** `--dangerously-skip-permissions` gives Claude unrestricted access to your filesystem, shell, and network. The Ralph Loop is designed to run autonomously and will hit permission prompts repeatedly without this flag, but you should understand the risk. Use in isolated environments or repositories you trust. The TDD gate and fail-closed Stop hook provide safety at the execution level, but they do not replace filesystem-level caution.

### 3. Run against your spec

```
/angry-ralph @path/to/your-spec.md
```

With a custom review iteration cap:

```
/angry-ralph @path/to/your-spec.md --max-review-iterations 5
```

The current working directory should be a git repo (or angry-ralph will offer to `git init` one for you). This is where the code gets built.

## Commands

| Command | Description |
|---------|-------------|
| `/angry-ralph @spec.md` | Start the 6-phase pipeline against a spec file |
| `/cancel-ralph` | Cancel an active Ralph Loop and remove state |
| `/angry-ralph-help` | Show usage, workflow overview, and prerequisites |

## Architecture

```
.
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── agents/
│   └── external-reviewer.md     # Subagent: invokes gemini + codex CLIs (Bash + Read only)
├── commands/
│   ├── angry-ralph.md           # Main pipeline entry point
│   ├── cancel-ralph.md          # Loop cancellation
│   └── help.md                  # Usage docs
├── hooks/
│   ├── hooks.json               # Stop + SubagentStop hook registration
│   └── stop-hook.sh             # TDD-gated exit interceptor
├── scripts/
│   ├── checks/
│   │   └── validate-env.sh      # Prerequisite validation
│   └── lib/
│       └── state.sh             # State file CRUD (YAML frontmatter)
├── skills/
│   └── angry-ralph/
│       ├── SKILL.md             # Master orchestration skill
│       └── references/
│           ├── planning-protocol.md
│           ├── review-protocol.md
│           ├── tdd-protocol.md
│           ├── loop-protocol.md
│           └── final-review-protocol.md
└── tests/
    ├── test-state.sh
    ├── test-validate-env.sh
    ├── test-stop-hook.sh
    └── test-plugin-structure.sh
```

### Key Components

**External Reviewer Agent** — A sandboxed subagent restricted to `Bash` and `Read` tools only. It invokes `gemini` and `codex` via CLI subprocesses, passing file paths (never stdin). The CLIs read spec/plan/code files from disk and write review output to the `planning/reviews/` directory.

**Ralph Loop (Stop + SubagentStop Hooks)** — During the EXECUTE phase, both the Stop and SubagentStop hooks intercept exit attempts. Each section is dispatched to a fresh subagent with clean context, and the SubagentStop hook gates its completion. The hook checks a state file (`.claude/angry-ralph.local.md`) and the session transcript for a completion promise (`SECTION_COMPLETE`). If the promise isn't found in the last assistant message, the hook blocks exit and feeds the section prompt back — forcing the loop to continue until tests pass. The hook is fail-closed: if transcript parsing fails, it blocks rather than allowing a premature exit. The main session stays lean, managing only coordination and section transitions.

**State Management** — A YAML-frontmatter markdown file tracks loop state (phase, iteration, current section, completion promise). The `state.sh` library provides portable read/write functions using `awk` (no BSD-specific `sed -i`).

## How the Review Loop Works

```
┌─────────────┐
│  Plan/Code   │
└──────┬──────┘
       │
       v
┌─────────────┐     ┌─────────────┐
│  gemini CLI  │     │  codex CLI   │
│  (review)    │     │  (review)    │
└──────┬──────┘     └──────┬──────┘
       │                    │
       v                    v
┌──────────────────────────────┐
│     Claude Triages Findings   │
│  ┌─────────┐  ┌────────────┐ │
│  │Auto-fix │  │AskUser for │ │
│  │clear    │  │genuine     │ │
│  │issues   │  │ambiguity   │ │
│  └─────────┘  └────────────┘ │
└──────────────┬───────────────┘
               │
               v
        Iterate or proceed
     (max N iterations, default 3)
```

Findings are triaged by Claude — clear issues get auto-fixed, genuine ambiguities are surfaced to you via `AskUserQuestion`. The loop runs until both reviewers approve or the iteration cap is reached.

## Testing

Run all tests:

```bash
bash tests/test-state.sh
bash tests/test-validate-env.sh
bash tests/test-stop-hook.sh
bash tests/test-plugin-structure.sh
```

Or all at once:

```bash
for t in tests/test-*.sh; do echo "=== $t ==="; bash "$t"; echo; done
```

**68 tests** across 4 suites covering state management, environment validation, stop hook behavior (including fail-closed on corrupt transcripts), and plugin structure integrity.

## Planning Artifacts

When angry-ralph runs, it creates a `planning/` directory next to your spec file:

```
planning/
├── config.json                 # Session config (phase, timestamps)
├── angry-ralph-plan.md         # The implementation plan
├── angry-ralph-interview.md    # Decomposition interview notes
├── reviews/
│   ├── iteration-1/
│   │   ├── gemini-review.md
│   │   └── codex-review.md
│   └── final/
│       ├── gemini-review.md
│       └── codex-review.md
└── sections/
    ├── index.md
    ├── section-01-name.md
    └── section-02-name.md
```

These artifacts persist across sessions, enabling resume after interruptions.

## Hard Constraints

These are non-negotiable design decisions baked into the plugin:

1. **External reviewer tools**: `Bash` and `Read` only — no file writes from review agents
2. **CLI invocation**: File paths as arguments, never stdin piping
3. **Triage with user input**: Ambiguous review findings always surface via `AskUserQuestion`
4. **TDD enforcement**: Tests written before implementation, must fail first, must pass before commit
5. **Atomic commits**: One commit per completed section
6. **Fail-closed loop**: Stop hook blocks exit if transcript parsing fails
7. **Zero external plugin dependencies**: Everything is self-contained

## License

[MIT](LICENSE)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing, and contribution guidelines.

## Acknowledgments

This project would not exist without the deep-series by [piercelamb](https://github.com/piercelamb):

- [deep-project](https://github.com/piercelamb/deep-project) — The decomposition and interview methodology
- [deep-plan](https://github.com/piercelamb/deep-plan) — The section-based planning approach and multi-LLM review concept
- [deep-implement](https://github.com/piercelamb/deep-implement) — The TDD execution discipline and atomic commit strategy

angry-ralph stands on these foundations and adds the Ralph Loop execution engine, unified plugin packaging, and cross-platform hardening.
