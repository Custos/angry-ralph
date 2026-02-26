#!/usr/bin/env bash
# hooks/stop-hook.sh — Stop hook for TDD-gated Ralph Loop execution
# Reads hook input JSON from stdin, checks state, and decides whether to
# allow exit or block and feed back the section prompt.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../scripts/lib/state.sh"

# Read hook input JSON from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('cwd',''))")
TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('transcript_path',''))")

# Determine project dir (CLAUDE_PROJECT_DIR override for testing, else CWD)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}"
STATE_FILE="$PROJECT_DIR/.claude/angry-ralph.local.md"

# 1. No state file → allow exit
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# 2. Read state fields
ACTIVE=$(read_state_field "$STATE_FILE" "active")
PHASE=$(read_state_field "$STATE_FILE" "phase")
ITERATION=$(read_state_field "$STATE_FILE" "iteration")
CURRENT_SECTION=$(read_state_field "$STATE_FILE" "current_section")
COMPLETION_PROMISE=$(read_state_field "$STATE_FILE" "completion_promise")

# Read TDD iteration cap from config.json (if it exists)
MAX_TDD_ITERATIONS=""
CONFIG_FILE="$PROJECT_DIR/planning/config.json"
if [ -f "$CONFIG_FILE" ]; then
  MAX_TDD_ITERATIONS=$(python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    print(cfg.get('max_tdd_iterations', ''))
except: print('')
" "$CONFIG_FILE" 2>/dev/null) || true
fi

# 3. If active=false → allow exit
if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

# 4. If phase is NOT "execute" → allow exit
if [ "$PHASE" != "execute" ]; then
  exit 0
fi

# 5. Phase IS "execute": check if completion promise appears in transcript
# Uses python3 to parse JSONL backwards (no tac dependency).
# Fail-closed: if parsing fails for any reason, we block exit with an error payload.
PROMISE_FOUND="false"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  PROMISE_RESULT=$(python3 -c "
import json, sys
promise = sys.argv[1]
transcript = sys.argv[2]
try:
    lines = open(transcript).readlines()
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        role = entry.get('role', entry.get('type', ''))
        if role == 'assistant':
            content = entry.get('content', '')
            if isinstance(content, list):
                content = ' '.join(c.get('text', '') for c in content if isinstance(c, dict))
            if promise in str(content):
                print('found')
            else:
                print('not_found')
            sys.exit(0)
    print('not_found')
except Exception as e:
    print('error:' + str(e), file=sys.stderr)
    print('parse_error')
" "$COMPLETION_PROMISE" "$TRANSCRIPT_PATH" 2>/dev/null)

  case "$PROMISE_RESULT" in
    found) PROMISE_FOUND="true" ;;
    not_found) PROMISE_FOUND="false" ;;
    *)
      # Fail-closed: parsing failed, block exit with error payload
      python3 -c "
import json
print(json.dumps({
    'decision': 'block',
    'reason': 'Transcript parsing failed. Cannot verify completion promise.',
    'systemMessage': 'angry-ralph: TOOLING ERROR. Transcript could not be parsed. Ensure python3 is working and the transcript file is valid JSONL. The loop is blocking exit as a safety measure.'
}))
"
      exit 0
      ;;
  esac
fi

# 6. If promise found → allow exit
if [ "$PROMISE_FOUND" = "true" ]; then
  exit 0
fi

# 6b. Check TDD iteration cap — if iteration >= cap, allow exit with cap_reached signal
if [ -n "$MAX_TDD_ITERATIONS" ] && [ "$ITERATION" -ge "$MAX_TDD_ITERATIONS" ]; then
  python3 -c "
import json
print(json.dumps({
    'decision': 'allow',
    'tdd_cap_reached': True,
    'reason': 'TDD iteration cap reached. Section needs user review.',
    'systemMessage': 'angry-ralph: TDD iteration cap ($MAX_TDD_ITERATIONS) reached for $CURRENT_SECTION. Tests have not passed after $ITERATION iterations. Ask the user what to do.'
}))
"
  exit 0
fi

# 7. Promise NOT found → block exit: increment iteration, output blocking JSON
NEW_ITERATION=$((ITERATION + 1))
write_state_field "$STATE_FILE" "iteration" "$NEW_ITERATION"

# Read the prompt body from the state file
PROMPT_BODY=$(read_state_body "$STATE_FILE")

# Build valid JSON output using python3 to handle all escaping
SYSTEM_MSG="angry-ralph loop iteration ${NEW_ITERATION} for ${CURRENT_SECTION}. TDD rules: write failing tests first, then implement. Output ${COMPLETION_PROMISE} only when ALL tests pass."
python3 -c "
import json, sys
reason = sys.argv[1]
sys_msg = sys.argv[2]
print(json.dumps({'decision': 'block', 'reason': reason, 'systemMessage': sys_msg}))
" "$PROMPT_BODY" "$SYSTEM_MSG"
