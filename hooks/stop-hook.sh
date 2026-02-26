#!/usr/bin/env bash
# hooks/stop-hook.sh — Stop hook for TDD-gated Ralph Loop execution
# Reads hook input JSON from stdin, checks state, and decides whether to
# allow exit or block and feed back the section prompt.
#
# Error strategy:
#   Fail-OPEN  before confirming active execute-phase loop (exit 0 on errors)
#   Fail-CLOSED once gating a confirmed active TDD loop (block on parse errors)
# -e is intentionally omitted to prevent silent non-zero exits.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_SH="$SCRIPT_DIR/../scripts/lib/state.sh"

# If state.sh missing, allow exit (plugin may be partially installed)
if [ ! -f "$STATE_SH" ]; then
  exit 0
fi
source "$STATE_SH"

# Read hook input JSON from stdin
INPUT=$(cat) || INPUT=""

# Parse CWD and transcript path. If JSON parsing fails, allow exit —
# no active loop can be gated without valid hook input.
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('cwd',''))" 2>/dev/null) || { exit 0; }
TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('transcript_path',''))" 2>/dev/null) || { exit 0; }

# Determine project dir (CLAUDE_PROJECT_DIR override for testing, else CWD)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}"
STATE_FILE="$PROJECT_DIR/.ralph-state/loop.md"

# 1. No state file → allow exit
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# 2. Read state fields (fail-open: if reads fail, defaults allow exit at step 3/4)
ACTIVE=$(read_state_field "$STATE_FILE" "active") || ACTIVE=""
PHASE=$(read_state_field "$STATE_FILE" "phase") || PHASE=""
ITERATION=$(read_state_field "$STATE_FILE" "iteration") || ITERATION="0"
CURRENT_SECTION=$(read_state_field "$STATE_FILE" "current_section") || CURRENT_SECTION=""
COMPLETION_PROMISE=$(read_state_field "$STATE_FILE" "completion_promise") || COMPLETION_PROMISE=""

# Read TDD iteration cap from config.json (if it exists)
MAX_TDD_ITERATIONS=""
CONFIG_FILE="$PROJECT_DIR/.ralph-state/pipeline.json"
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
" "$COMPLETION_PROMISE" "$TRANSCRIPT_PATH" 2>/dev/null) || PROMISE_RESULT="parse_error"

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
if [ -n "$MAX_TDD_ITERATIONS" ] && [ "$ITERATION" -ge "$MAX_TDD_ITERATIONS" ] 2>/dev/null; then
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
write_state_field "$STATE_FILE" "iteration" "$NEW_ITERATION" || true

# Read the prompt body from the state file
PROMPT_BODY=$(read_state_body "$STATE_FILE") || PROMPT_BODY=""

# Build valid JSON output using python3 to handle all escaping
SYSTEM_MSG="angry-ralph loop iteration ${NEW_ITERATION} for ${CURRENT_SECTION}. TDD rules: write failing tests first, then implement. Output ${COMPLETION_PROMISE} only when ALL tests pass."
python3 -c "
import json, sys
reason = sys.argv[1]
sys_msg = sys.argv[2]
print(json.dumps({'decision': 'block', 'reason': reason, 'systemMessage': sys_msg}))
" "$PROMPT_BODY" "$SYSTEM_MSG"
