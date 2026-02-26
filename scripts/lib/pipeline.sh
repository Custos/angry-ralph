#!/usr/bin/env bash
# scripts/lib/pipeline.sh — .ralph-state/ pipeline management
# Handles idempotency (.done markers), pipeline.json CRUD, and legacy migration.
set -euo pipefail

# Ensure .ralph-state/ and .planning/ are in the project's .gitignore.
# Idempotent: only appends entries that are missing.
# $1 = project directory
ensure_gitignore() {
  local project_dir="$1"
  local gitignore="$project_dir/.gitignore"
  local entries=(".ralph-state/" ".planning/")

  for entry in "${entries[@]}"; do
    if [ ! -f "$gitignore" ] || ! grep -qxF "$entry" "$gitignore"; then
      echo "$entry" >> "$gitignore"
    fi
  done
}

# Initialize .ralph-state/ directory structure.
# $1 = project directory
pipeline_init() {
  local project_dir="$1"
  mkdir -p "$project_dir/.ralph-state/phases"
  ensure_gitignore "$project_dir"
}

# Create pipeline.json with initial config.
# $1=project_dir $2=spec_file $3=mode $4=max_review $5=max_section_review
# $6=max_tdd $7=review_tier $8=available_reviewers (comma-separated)
pipeline_create() {
  local project_dir="$1"
  local spec_file="$2"
  local mode="${3:-interactive}"
  local max_review="${4:-3}"
  local max_section_review="${5:-2}"
  local max_tdd="${6:-20}"
  local review_tier="${7:-self-reflection}"
  local available_reviewers="${8:-}"

  pipeline_init "$project_dir"

  python3 -c "
import json, datetime, sys
cfg = {
    'spec_file': sys.argv[1],
    'mode': sys.argv[2],
    'max_review_iterations': int(sys.argv[3]),
    'max_section_review_iterations': int(sys.argv[4]),
    'max_tdd_iterations': int(sys.argv[5]),
    'started_at': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'review_tier': sys.argv[6],
    'available_reviewers': [r for r in sys.argv[7].split(',') if r],
    'current_phase': 'decompose',
    'completed_phases': [],
    'completed_sections': []
}
with open(sys.argv[8], 'w') as f:
    json.dump(cfg, f, indent=2)
" "$spec_file" "$mode" "$max_review" "$max_section_review" "$max_tdd" \
  "$review_tier" "$available_reviewers" "$project_dir/.ralph-state/pipeline.json"
}

# Read a field from pipeline.json.
# $1 = project directory, $2 = field name
pipeline_read() {
  local project_dir="$1"
  local field="$2"
  local pfile="$project_dir/.ralph-state/pipeline.json"

  if [ ! -f "$pfile" ]; then
    echo ""
    return 0
  fi

  python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    val = cfg.get(sys.argv[2], '')
    if isinstance(val, list):
        print(','.join(str(v) for v in val))
    else:
        print(val)
except:
    print('')
" "$pfile" "$field"
}

# Update a field in pipeline.json.
# $1 = project directory, $2 = field name, $3 = value
# For list append, use pipeline_append instead.
pipeline_write() {
  local project_dir="$1"
  local field="$2"
  local value="$3"
  local pfile="$project_dir/.ralph-state/pipeline.json"

  python3 -c "
import json, sys
pfile = sys.argv[1]
field = sys.argv[2]
value = sys.argv[3]
try:
    value = int(value)
except ValueError:
    pass
with open(pfile, 'r') as f:
    cfg = json.load(f)
cfg[field] = value
with open(pfile, 'w') as f:
    json.dump(cfg, f, indent=2)
" "$pfile" "$field" "$value"
}

# Append a value to a list field in pipeline.json.
# $1 = project directory, $2 = field name, $3 = value to append
pipeline_append() {
  local project_dir="$1"
  local field="$2"
  local value="$3"
  local pfile="$project_dir/.ralph-state/pipeline.json"

  python3 -c "
import json, sys
pfile = sys.argv[1]
field = sys.argv[2]
value = sys.argv[3]
with open(pfile, 'r') as f:
    cfg = json.load(f)
lst = cfg.get(field, [])
if value not in lst:
    lst.append(value)
cfg[field] = lst
with open(pfile, 'w') as f:
    json.dump(cfg, f, indent=2)
" "$pfile" "$field" "$value"
}

# Remove a value from a list field in pipeline.json.
# $1 = project directory, $2 = field name, $3 = value to remove
pipeline_remove_from_list() {
  local project_dir="$1"
  local field="$2"
  local value="$3"
  local pfile="$project_dir/.ralph-state/pipeline.json"

  python3 -c "
import json, sys
pfile = sys.argv[1]
field = sys.argv[2]
value = sys.argv[3]
with open(pfile, 'r') as f:
    cfg = json.load(f)
lst = cfg.get(field, [])
lst = [v for v in lst if v != value]
cfg[field] = lst
with open(pfile, 'w') as f:
    json.dump(cfg, f, indent=2)
" "$pfile" "$field" "$value"
}

# Check if a .done marker exists.
# $1 = project directory, $2 = phase name (architect, review, execute)
# Returns: exit 0 if done, exit 1 if not.
check_done() {
  local project_dir="$1"
  local phase="$2"
  [ -f "$project_dir/.ralph-state/phases/${phase}.done" ]
}

# Write a .done marker.
# $1 = project directory, $2 = phase name
write_done() {
  local project_dir="$1"
  local phase="$2"
  mkdir -p "$project_dir/.ralph-state/phases"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$project_dir/.ralph-state/phases/${phase}.done"
}

# Remove a .done marker (for --rebuild).
# $1 = project directory, $2 = phase or section name
remove_done() {
  local project_dir="$1"
  local name="$2"
  rm -f "$project_dir/.ralph-state/phases/${name}.done"
}

# Migrate legacy state files to .ralph-state/.
# $1 = project directory
# Returns: "migrated" if migration happened, "none" if nothing to migrate.
migrate_legacy() {
  local project_dir="$1"
  local did_migrate="none"

  if [ -f "$project_dir/.claude/angry-ralph.local.md" ] && [ ! -d "$project_dir/.ralph-state" ]; then
    mkdir -p "$project_dir/.ralph-state"
    mv "$project_dir/.claude/angry-ralph.local.md" "$project_dir/.ralph-state/loop.md"
    did_migrate="migrated"
  fi

  if [ -f "$project_dir/planning/config.json" ] && [ ! -f "$project_dir/.ralph-state/pipeline.json" ]; then
    mkdir -p "$project_dir/.ralph-state"
    cp "$project_dir/planning/config.json" "$project_dir/.ralph-state/pipeline.json"
    did_migrate="migrated"
  fi

  # Migrate planning/ → .planning/ (v0.2.0 → v0.3.0)
  if [ -d "$project_dir/planning" ] && [ ! -d "$project_dir/.planning" ]; then
    mv "$project_dir/planning" "$project_dir/.planning"
    did_migrate="migrated"
  fi

  echo "$did_migrate"
}

# Print pipeline status summary.
# $1 = project directory
pipeline_status() {
  local project_dir="$1"
  local pfile="$project_dir/.ralph-state/pipeline.json"

  if [ ! -f "$pfile" ]; then
    echo "No active angry-ralph pipeline."
    return 0
  fi

  local phase completed tier reviewers
  phase=$(pipeline_read "$project_dir" "current_phase")
  completed=$(pipeline_read "$project_dir" "completed_phases")
  tier=$(pipeline_read "$project_dir" "review_tier")
  reviewers=$(pipeline_read "$project_dir" "available_reviewers")

  local arch_done rev_done exec_done
  arch_done=$(check_done "$project_dir" "architect" && echo "✓" || echo "✗")
  rev_done=$(check_done "$project_dir" "review" && echo "✓" || echo "✗")
  exec_done=$(check_done "$project_dir" "execute" && echo "✓" || echo "✗")

  echo "angry-ralph status:"
  echo "  Phase:        $phase"
  echo "  Completed:    ${completed:-none}"
  echo "  Done markers: architect[$arch_done] review[$rev_done] execute[$exec_done]"
  echo "  Review tier:  $tier ($reviewers)"
  echo "  Config:       .ralph-state/pipeline.json"

  if [ -f "$project_dir/.ralph-state/loop.md" ]; then
    local loop_active loop_section loop_iter
    # source state.sh if not already loaded
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$script_dir/state.sh"
    loop_active=$(read_state_field "$project_dir/.ralph-state/loop.md" "active")
    loop_section=$(read_state_field "$project_dir/.ralph-state/loop.md" "current_section")
    loop_iter=$(read_state_field "$project_dir/.ralph-state/loop.md" "iteration")
    echo "  Loop:         $loop_section (iteration $loop_iter) [${loop_active}]"
  else
    echo "  Loop:         inactive"
  fi
}

# Dispatch: call the function named by $1, pass remaining args.
CMD="${1:-}"
shift || true
case "$CMD" in
  init)           pipeline_init "$@" ;;
  create)         pipeline_create "$@" ;;
  read)           pipeline_read "$@" ;;
  write)          pipeline_write "$@" ;;
  append)         pipeline_append "$@" ;;
  remove_from_list) pipeline_remove_from_list "$@" ;;
  check_done)     check_done "$@" ;;
  write_done)     write_done "$@" ;;
  remove_done)    remove_done "$@" ;;
  migrate)        migrate_legacy "$@" ;;
  status)         pipeline_status "$@" ;;
  *)
    echo "Usage: pipeline.sh <init|create|read|write|append|remove_from_list|check_done|write_done|remove_done|migrate|status> [args...]"
    exit 1
    ;;
esac
