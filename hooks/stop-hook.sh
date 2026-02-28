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

# ---- FAST PATH: read stdin and check state file before loading anything ----
# This minimizes overhead when no angry-ralph pipeline is active.
INPUT=$(cat) || INPUT=""

CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('cwd',''))" 2>/dev/null) || { exit 0; }

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}"
STATE_FILE="$PROJECT_DIR/.ralph-state/loop.md"

# No state file → allow exit immediately (most common case)
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# ---- STATE FILE EXISTS: load dependencies and proceed with gating logic ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_SH="$SCRIPT_DIR/../scripts/lib/state.sh"

# If state.sh missing, allow exit (plugin may be partially installed)
if [ ! -f "$STATE_SH" ]; then
  exit 0
fi
source "$STATE_SH"

TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('transcript_path',''))" 2>/dev/null) || { exit 0; }
HOOK_EVENT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('hook_event_name',''))" 2>/dev/null) || HOOK_EVENT=""

# Read state fields (fail-open: if reads fail, defaults allow exit at step 3/4)
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

# If active=false → allow exit
if [ "$ACTIVE" != "true" ]; then
  exit 0
fi

# If phase is NOT "execute" → allow exit
if [ "$PHASE" != "execute" ]; then
  exit 0
fi

# Empty promise guard — if promise is blank/null, block (never bypass loop)
if [ -z "$COMPLETION_PROMISE" ]; then
  python3 -c "
import json
print(json.dumps({
    'decision': 'block',
    'reason': 'No completion promise defined. State file may be corrupt.',
    'systemMessage': 'angry-ralph: SAFETY BLOCK. completion_promise is empty in .ralph-state/loop.md. A blank promise would bypass the TDD gate. Fix the state file or run /cancel-ralph.'
}))
"
  exit 0
fi

# Phase IS "execute": check if completion promise appears in transcript
# Uses python3 to parse JSONL backwards (no tac dependency).
# Handles both flat format (role/content at top level) and nested format
# (message.role/message.content) used by real Claude transcripts.
# Fail-closed: if parsing fails for any reason, we block exit with an error payload.
PROMISE_FOUND="false"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  PROMISE_RESULT=$(python3 -c "
import json, sys

promise = sys.argv[1]
transcript = sys.argv[2]

def extract_role_content(entry):
    # Flat format: {\"role\": \"assistant\", \"content\": \"...\"}
    role = entry.get('role', '')
    content = entry.get('content', '')
    # Nested format: {\"type\": \"message\", \"message\": {\"role\": \"assistant\", \"content\": [...]}}
    if not role and 'message' in entry:
        msg = entry['message']
        if isinstance(msg, dict):
            role = msg.get('role', '')
            content = msg.get('content', '')
    # Normalize content: list of blocks → joined text
    if isinstance(content, list):
        content = ' '.join(
            c.get('text', '') for c in content if isinstance(c, dict)
        )
    return role, str(content)

try:
    lines = open(transcript).readlines()
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        role, content = extract_role_content(entry)
        if role == 'assistant':
            if promise in content:
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

# If promise found → allow exit
if [ "$PROMISE_FOUND" = "true" ]; then
  exit 0
fi

# SubagentStop scope guard — if this is a SubagentStop event and the promise
# doesn't appear ANYWHERE in the transcript, this subagent was never told about the
# promise (e.g., review subagent, external reviewer). Allow exit — not a TDD subagent.
if [ "$HOOK_EVENT" = "SubagentStop" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  PROMISE_IN_TRANSCRIPT=$(python3 -c "
import sys
promise = sys.argv[1]
try:
    text = open(sys.argv[2]).read()
    print('yes' if promise in text else 'no')
except:
    print('no')
" "$COMPLETION_PROMISE" "$TRANSCRIPT_PATH" 2>/dev/null) || PROMISE_IN_TRANSCRIPT="no"
  if [ "$PROMISE_IN_TRANSCRIPT" = "no" ]; then
    # This subagent was never instructed to output the promise → not a TDD subagent
    exit 0
  fi
fi

# Check TDD iteration cap — if iteration >= cap, allow exit with cap_reached signal
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

# Promise NOT found → block exit: increment iteration, output blocking JSON
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
