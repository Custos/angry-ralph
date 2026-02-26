#!/usr/bin/env bash
# scripts/lib/state.sh — State file management for angry-ralph
# State file format: YAML frontmatter between --- markers, then prompt body

read_state_field() {
  local file="$1" field="$2"
  if [ ! -f "$file" ]; then
    echo ""
    return 0
  fi
  # Extract value from YAML frontmatter (between first and second ---)
  sed -n '/^---$/,/^---$/p' "$file" | grep "^${field}:" | head -1 | sed "s/^${field}: *//; s/^\"//; s/\"$//"
}

write_state_field() {
  local file="$1" field="$2" value="$3"
  if [ ! -f "$file" ]; then
    return 1
  fi
  # Replace field value ONLY within YAML frontmatter (between first two --- markers).
  # Uses awk to track frontmatter boundaries and a temp file for portability (no sed -i).
  local tmpfile
  tmpfile=$(mktemp)
  awk -v field="$field" -v value="$value" '
    BEGIN { fm=0 }
    /^---$/ { fm++; print; next }
    fm == 1 && $0 ~ "^"field":" { print field": "value; next }
    { print }
  ' "$file" > "$tmpfile" && mv "$tmpfile" "$file"
}

read_state_body() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo ""
    return 0
  fi
  # Everything after the second ---
  awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$file" | sed '/^$/d'
}

create_state_file() {
  local file="$1"
  local phase="$2"
  local iteration="$3"
  local max_iterations="$4"
  local current_section="$5"
  local completion_promise="$6"
  local spec_file="$7"
  local planning_dir="$8"
  local prompt_body="$9"

  local dir
  dir=$(dirname "$file")
  mkdir -p "$dir"

  cat > "$file" <<STATEEOF
---
active: true
phase: ${phase}
iteration: ${iteration}
max_iterations: ${max_iterations}
current_section: ${current_section}
completion_promise: ${completion_promise}
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
spec_file: ${spec_file}
planning_dir: ${planning_dir}
---

${prompt_body}
STATEEOF
}

remove_state_file() {
  local file="$1"
  rm -f "$file"
}
