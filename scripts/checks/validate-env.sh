#!/usr/bin/env bash
# scripts/checks/validate-env.sh — Validate environment and detect review tier
# Required tools (git, python3, claude) cause hard failure.
# Optional tools (gemini, codex) determine the review tier.
# Outputs JSON summary to stdout on success.
set -euo pipefail

REQUIRED_ERRORS=0
AVAILABLE_REVIEWERS=""

check_required() {
  local tool="$1"
  if command -v "$tool" > /dev/null 2>&1; then
    echo "[OK] $tool found: $(command -v "$tool")" >&2
  else
    echo "[ERROR] $tool not found in PATH (required)" >&2
    ((REQUIRED_ERRORS++)) || true
  fi
}

check_optional() {
  local tool="$1"
  if command -v "$tool" > /dev/null 2>&1; then
    echo "[OK] $tool found: $(command -v "$tool")" >&2
    AVAILABLE_REVIEWERS="${AVAILABLE_REVIEWERS}${tool},"
  else
    echo "[WARN] $tool not found in PATH (optional — review tier may be reduced)" >&2
  fi
}

echo "angry-ralph: Validating environment..." >&2
echo "" >&2

# Required tools — hard-fail if missing
check_required "git"
check_required "python3"
check_required "claude"

echo "" >&2

# Optional reviewers — soft check
check_optional "gemini"
check_optional "codex"

echo "" >&2

# Hard-fail on required tools
if [ "$REQUIRED_ERRORS" -gt 0 ]; then
  echo "Environment validation FAILED: $REQUIRED_ERRORS required tool(s) missing." >&2
  exit 1
fi

# Determine review tier
# Remove trailing comma from AVAILABLE_REVIEWERS
AVAILABLE_REVIEWERS="${AVAILABLE_REVIEWERS%,}"

HAS_GEMINI="false"
HAS_CODEX="false"
if echo "$AVAILABLE_REVIEWERS" | grep -q "gemini"; then
  HAS_GEMINI="true"
fi
if echo "$AVAILABLE_REVIEWERS" | grep -q "codex"; then
  HAS_CODEX="true"
fi

if [ "$HAS_GEMINI" = "true" ] && [ "$HAS_CODEX" = "true" ]; then
  REVIEW_TIER="adversarial"
  TIER_LABEL="Adversarial (gemini + codex)"
elif [ "$HAS_GEMINI" = "true" ] || [ "$HAS_CODEX" = "true" ]; then
  REVIEW_TIER="partial"
  TIER_LABEL="Partial (${AVAILABLE_REVIEWERS} + claude fallback)"
else
  REVIEW_TIER="self-reflection"
  TIER_LABEL="Self-Reflection (claude only)"
fi

echo "Review tier: $TIER_LABEL" >&2
echo "Environment validation PASSED." >&2

# Output JSON summary to stdout for downstream consumption
python3 -c "
import json, sys
reviewers = [r for r in sys.argv[1].split(',') if r]
if 'claude' not in reviewers:
    reviewers.append('claude')
print(json.dumps({
    'review_tier': sys.argv[2],
    'available_reviewers': reviewers,
    'has_gemini': sys.argv[3] == 'true',
    'has_codex': sys.argv[4] == 'true'
}))
" "$AVAILABLE_REVIEWERS" "$REVIEW_TIER" "$HAS_GEMINI" "$HAS_CODEX"
