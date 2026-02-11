#!/usr/bin/env bash
set -euo pipefail

# Minimal guard test: simulate missing pnpm
PATH="/usr/bin:/bin"  # likely no pnpm
export PATH

out=$(zig build web 2>&1 || true)
echo "$out" | grep -q "skipping web: pnpm not installed" && echo "web_guard_test: PASS" || {
  echo "web_guard_test: FAIL"; echo "$out"; exit 1;
}

