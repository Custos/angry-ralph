#!/usr/bin/env bash
# scripts/checks/validate-env.sh — Validate required CLI tools are available
set -euo pipefail

ERRORS=0

check_tool() {
  local tool="$1"
  if command -v "$tool" > /dev/null 2>&1; then
    echo "[OK] $tool found: $(command -v "$tool")"
  else
    echo "[ERROR] $tool not found in PATH"
    ((ERRORS++)) || true
  fi
}

echo "angry-ralph: Validating environment..."
echo ""

check_tool "gemini"
check_tool "codex"
check_tool "git"
check_tool "python3"

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "Environment validation FAILED: $ERRORS tool(s) missing."
  echo "Install missing tools before running angry-ralph."
  exit 1
fi

echo "Environment validation PASSED. All tools available."
exit 0
