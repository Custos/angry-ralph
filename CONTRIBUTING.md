# Contributing to angry-ralph

Thanks for your interest in contributing. This guide covers development setup, testing, and the contribution process.

## Background

angry-ralph builds on the deep-series by [piercelamb](https://github.com/piercelamb):

- [deep-project](https://github.com/piercelamb/deep-project) — Feature decomposition
- [deep-plan](https://github.com/piercelamb/deep-plan) — Implementation planning with multi-LLM review
- [deep-implement](https://github.com/piercelamb/deep-implement) — TDD execution

If you're extending review or planning logic, reading those repos first will give you useful context.

## Development Setup

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [Gemini CLI](https://github.com/google-gemini/gemini-cli)
- [Codex CLI](https://github.com/openai/codex)
- `git`, `python3`, `bash`

### Clone and Test

```bash
git clone https://github.com/Custos/angry-ralph.git

# Run all tests
for t in ./angry-ralph/tests/test-*.sh; do bash "$t"; done

# Validate environment
bash ./angry-ralph/scripts/checks/validate-env.sh
```

### Local Plugin Testing

Load the plugin into Claude Code from your working copy:

```bash
claude --plugin-dir /path/to/angry-ralph
```

For fully autonomous loop execution (no permission prompts):

```bash
claude --plugin-dir /path/to/angry-ralph --dangerously-skip-permissions
```

> **Note:** `--dangerously-skip-permissions` is practically necessary for the Ralph Loop to run without interruption, but it grants unrestricted filesystem and shell access. Use in isolated environments.

Then test commands (`/angry-ralph`, `/cancel-ralph`, `/angry-ralph-help`) in the session.

## Code Style

### Shell Scripts

- Start every script with `#!/usr/bin/env bash` and `set -euo pipefail`
- Use portable constructs — no BSD-specific flags (e.g., `sed -i ''` is macOS-only)
- Use `awk` with temp files instead of `sed -i` for in-place edits
- Use `python3` for JSON parsing instead of `jq` (fewer dependencies)
- Quote all variables: `"$var"`, not `$var`
- Guard arithmetic with `|| true` under `set -e` (bash returns exit 1 when result is 0)

### Markdown Components

- Commands, agents, and skills use YAML frontmatter — follow the existing format exactly
- Agent descriptions must include `<example>` blocks with `<commentary>`
- Skill descriptions use third-person ("This skill should be used when...")
- Skill body uses imperative form ("Run the script", not "You should run the script")

### Hook Scripts

- Use `${CLAUDE_PLUGIN_ROOT}` for all intra-plugin path references
- Hooks receive JSON on stdin — parse with `python3`, not `jq`
- Fail closed: if parsing fails, block rather than allow

## Testing

### Test Suites

| Suite | What It Tests |
|-------|---------------|
| `test-state.sh` | State file CRUD, frontmatter isolation, body preservation |
| `test-validate-env.sh` | Tool detection, missing tool failures |
| `test-stop-hook.sh` | Block/allow decisions, JSON output, iteration increment, fail-closed |
| `test-plugin-structure.sh` | All plugin files exist with correct content |

### Writing Tests

- Follow the existing pattern: `assert_eq`, `assert_contains`, `assert_empty` helpers
- Test the behavior, not the implementation
- Use `mktemp -d` for isolated test directories with a `trap cleanup EXIT`
- For hook tests, assert on stdout content (empty = allow, JSON = block), not exit codes

### Running Tests

```bash
# Individual suite
bash tests/test-state.sh

# All suites
for t in tests/test-*.sh; do echo "=== $t ==="; bash "$t"; echo; done
```

All tests must pass before submitting a PR.

## Making Changes

### Branch and Commit

1. Create a feature branch from `main`
2. Make focused, atomic commits with clear messages
3. Follow the existing commit message style: `feat:`, `fix:`, `test:`, `docs:`

### Pull Requests

1. Ensure all 4 test suites pass (84+ tests)
2. Add tests for new functionality
3. Update the README if you're adding commands, changing prerequisites, or modifying the pipeline
4. Keep PRs focused — one feature or fix per PR

### What to Contribute

Good candidates:
- Bug fixes with regression tests
- New review protocol integrations (additional LLM CLIs)
- Cross-platform compatibility improvements
- Test coverage for edge cases
- Documentation improvements

Please open an issue first for larger changes (new phases, architectural modifications) so we can discuss the approach.

## Project Structure

```
.
├── .claude-plugin/plugin.json   # Plugin manifest
├── agents/                      # Subagent definitions
├── commands/                    # Slash commands
├── hooks/                       # Stop hook (loop enforcement)
├── scripts/                     # Shell libraries and checks
├── skills/                      # Orchestration skill + protocol references
└── tests/                       # Test suites
```

See the [README](README.md) for a full architecture breakdown.
