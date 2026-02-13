#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.."; pwd)"
cd "$ROOT_DIR"

ZIG_BIN="$(command -v zig)"
ZIG_DIR="$(dirname "$ZIG_BIN")"
SAFE_PATH="$ZIG_DIR:/usr/bin:/bin:/usr/sbin:/sbin"

run_missing_tool_case() {
  local step="$1"
  local missing_tool="$2"
  local expected_error="$3"
  local log_file
  log_file="$(mktemp "/tmp/smithers-${step}.XXXXXX.log")"

  if PATH="$SAFE_PATH" zig build "$step" >"$log_file" 2>&1; then
    echo "FAIL: zig build $step succeeded with $missing_tool removed from PATH." >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  if ! grep -Fq "$expected_error" "$log_file"; then
    echo "FAIL: zig build $step did not print expected error for missing $missing_tool." >&2
    echo "Expected: $expected_error" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi

  echo "PASS: $step fails when $missing_tool is missing."
  rm -f "$log_file"
}

run_missing_tool_case \
  "prettier-check" \
  "prettier" \
  "ERROR: prettier not found. Install: npm install -g prettier"

run_missing_tool_case \
  "typos-check" \
  "typos" \
  "ERROR: typos not found. Install: brew install typos-cli"

run_missing_tool_case \
  "shellcheck" \
  "shellcheck" \
  "ERROR: shellcheck not found. Install: brew install shellcheck"

echo "PASS: lint_tool_gate_test"
