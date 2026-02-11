#!/usr/bin/env bash
set -euo pipefail

# Verify that the web/build step in build.zig skips gracefully when pnpm is missing,
# and runs when pnpm is present.

ZIG_BIN="$(command -v zig || true)"
if [[ -z "${ZIG_BIN}" ]]; then
  echo "zig not found in PATH; cannot run test" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"

have_pnpm=0
if command -v pnpm >/dev/null 2>&1; then
  have_pnpm=1
fi

echo "[1/2] Simulate missing pnpm (should print skip message)" >&2
# Run zig with a sanitized PATH that excludes pnpm but still allows zig.
# We invoke zig by absolute path so it remains reachable even if PATH is trimmed.
SANITIZED_PATH="/usr/bin:/bin"
set +e
OUTPUT_MISSING=$(env PATH="${SANITIZED_PATH}" "${ZIG_BIN}" build web 2>&1)
STATUS_MISSING=$?
set -e

if [[ ${STATUS_MISSING} -ne 0 ]]; then
  echo "Expected success exit code when pnpm is missing; got ${STATUS_MISSING}" >&2
  echo "=== Output ===" >&2
  echo "${OUTPUT_MISSING}" >&2
  exit 1
fi

if ! grep -q "skipping web: pnpm not installed" <<<"${OUTPUT_MISSING}"; then
  echo "Did not find expected skip message when pnpm is missing" >&2
  echo "=== Output ===" >&2
  echo "${OUTPUT_MISSING}" >&2
  exit 1
fi

echo "OK: skip message present when pnpm missing" >&2

if [[ ${have_pnpm} -eq 1 ]]; then
  echo "[2/2] pnpm present (should run pnpm install && pnpm build)" >&2
  # This will execute the real web build step; tolerate its normal output.
  "${ZIG_BIN}" build web
  echo "OK: web build executed with pnpm present" >&2
else
  echo "[2/2] pnpm not present on host; skipping positive execution test" >&2
fi

# Print a compact test summary for capture by the harness.
echo "web_guard_test: PASS"
SH
chmod +x tests/web_guard_test.sh
