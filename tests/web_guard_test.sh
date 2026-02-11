#!/usr/bin/env bash
set -euo pipefail

# Minimal guard test: simulate missing pnpm without hiding zig
ZIG_BIN=$(command -v zig)
if [ -z "$ZIG_BIN" ]; then echo "zig not found in PATH; cannot run test"; exit 0; fi
# Constrain PATH to likely exclude pnpm but keep system + zig location
SAFE_PATH="/usr/bin:/bin"
case "$ZIG_BIN" in
  /usr/*) : ;; # already covered
  *) SAFE_PATH="$SAFE_PATH:$(dirname "$ZIG_BIN")" ;;
esac
PATH="$SAFE_PATH"; export PATH

out="$("$ZIG_BIN" build web 2>&1 || true)"
echo "$out" | grep -q "skipping web: pnpm not installed" && echo "web_guard_test: PASS" || {
  echo "web_guard_test: FAIL"; echo "$out"; exit 1;
}
