#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.."; pwd)"
cd "$ROOT_DIR"

ORIG_PATH="$PATH"
REAL_ZIG="$(command -v zig)"
TMP_DIR="$(mktemp -d /tmp/smithers-failing-gates.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_and_expect_failure() {
  local label="$1"
  local expected="$2"
  shift 2

  local log_file
  log_file="$TMP_DIR/${label}.log"

  if "$@" >"$log_file" 2>&1; then
    echo "FAIL: ${label} unexpectedly succeeded." >&2
    cat "$log_file" >&2
    exit 1
  fi

  if ! grep -Fq "$expected" "$log_file"; then
    echo "FAIL: ${label} did not include expected marker." >&2
    echo "Expected marker: $expected" >&2
    cat "$log_file" >&2
    exit 1
  fi

  echo "PASS: ${label} failed as expected."
}

# Validate shellcheck failures propagate as non-zero.
SHELLCHECK_FAKE_DIR="$TMP_DIR/fake-shellcheck"
mkdir -p "$SHELLCHECK_FAKE_DIR"
cat >"$SHELLCHECK_FAKE_DIR/shellcheck" <<'SH'
#!/usr/bin/env sh
echo "simulated shellcheck failure" >&2
exit 1
SH
chmod +x "$SHELLCHECK_FAKE_DIR/shellcheck"

SHELLCHECK_WORK_DIR="$TMP_DIR/shellcheck-work"
mkdir -p "$SHELLCHECK_WORK_DIR"
cat >"$SHELLCHECK_WORK_DIR/lint_target.sh" <<'SH'
#!/usr/bin/env sh
echo "lint me"
SH
chmod +x "$SHELLCHECK_WORK_DIR/lint_target.sh"

run_and_expect_failure \
  "shellcheck_step_failure" \
  "simulated shellcheck failure" \
  env PATH="$SHELLCHECK_FAKE_DIR:$ORIG_PATH" sh -c "cd \"$SHELLCHECK_WORK_DIR\" && zig build --build-file \"$ROOT_DIR/build.zig\" shellcheck"

# Validate Playwright failures propagate as non-zero.
PNPM_FAKE_DIR="$TMP_DIR/fake-pnpm"
mkdir -p "$PNPM_FAKE_DIR"
cat >"$PNPM_FAKE_DIR/pnpm" <<'SH'
#!/usr/bin/env sh
if [ "$1" = "install" ]; then
  exit 0
fi
if [ "$1" = "exec" ] && [ "${2:-}" = "playwright" ] && [ "${3:-}" = "test" ]; then
  echo "simulated playwright failure" >&2
  exit 1
fi
echo "unexpected pnpm args: $*" >&2
exit 2
SH
chmod +x "$PNPM_FAKE_DIR/pnpm"

run_and_expect_failure \
  "playwright_step_failure" \
  "simulated playwright failure" \
  env PATH="$PNPM_FAKE_DIR:$ORIG_PATH" zig build playwright

# Validate codex and jj sub-step failures propagate as non-zero.
ZIG_FAKE_DIR="$TMP_DIR/fake-zig"
mkdir -p "$ZIG_FAKE_DIR"
cat >"$ZIG_FAKE_DIR/zig" <<'SH'
#!/usr/bin/env sh
set -eu
if [ "$(pwd)" = "$ROOT_DIR/submodules/codex" ] && [ "${1:-}" = "build" ]; then
  echo "simulated codex build failure" >&2
  exit 1
fi
if [ "$(pwd)" = "$ROOT_DIR/submodules/jj" ] && [ "${1:-}" = "build" ]; then
  echo "simulated jj build failure" >&2
  exit 1
fi
exec "$REAL_ZIG" "$@"
SH
chmod +x "$ZIG_FAKE_DIR/zig"

run_and_expect_failure \
  "codex_step_failure" \
  "simulated codex build failure" \
  env ROOT_DIR="$ROOT_DIR" REAL_ZIG="$REAL_ZIG" PATH="$ZIG_FAKE_DIR:$ORIG_PATH" zig build codex

run_and_expect_failure \
  "jj_step_failure" \
  "simulated jj build failure" \
  env ROOT_DIR="$ROOT_DIR" REAL_ZIG="$REAL_ZIG" PATH="$ZIG_FAKE_DIR:$ORIG_PATH" zig build jj

echo "PASS: failing_gate_steps_test"
