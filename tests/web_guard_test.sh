#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.."; pwd)"
cd "$ROOT_DIR"

ZIG_BIN="$(command -v zig)"
if [ -z "$ZIG_BIN" ]; then
  echo "zig not found in PATH; cannot run test"
  exit 0
fi

SAFE_PATH="$(dirname "$ZIG_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"

run_missing_pnpm_case() {
  local step="$1"
  local expected="$2"
  local out

  if out="$(env PATH="$SAFE_PATH" zig build "$step" 2>&1)"; then
    echo "web_guard_test: FAIL ($step unexpectedly succeeded)"
    echo "$out"
    exit 1
  fi

  if ! echo "$out" | grep -Fq "$expected"; then
    echo "web_guard_test: FAIL ($step missing expected error)"
    echo "expected: $expected"
    echo "$out"
    exit 1
  fi
}

run_missing_pnpm_case "web" "ERROR: pnpm not found. Install: npm install -g pnpm"
run_missing_pnpm_case "playwright" "ERROR: pnpm not found. Install: npm install -g pnpm"

echo "web_guard_test: PASS"
