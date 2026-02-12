#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.."; pwd)"
cd "$ROOT_DIR"

LOG_DIR="$(mktemp -d /tmp/smithers-xcfw-single-writer.XXXXXX)"
trap 'rm -rf "$LOG_DIR"' EXIT

echo "Using log directory: $LOG_DIR"

if command -v rg >/dev/null 2>&1; then
  search_regex() {
    rg -n "$1" "$2"
  }
  search_fixed() {
    rg -n -F "$1" "$2"
  }
else
  echo "WARN: rg not found; using grep fallback for pattern checks."
  search_regex() {
    grep -n -E "$1" "$2"
  }
  search_fixed() {
    grep -n -F "$1" "$2"
  }
fi

if search_regex "xcode-build:.*zig build xcframework|if \\[ ! -d dist/SmithersKit\\.xcframework \\]; then zig build xcframework" build.zig >/dev/null; then
  echo "FAIL: build.zig still contains an xcode-build fallback that rebuilds xcframework." >&2
  exit 1
fi

if search_regex "xcode-test:.*zig build xcframework|if \\[ ! -d dist/SmithersKit\\.xcframework \\]; then echo 'xcode-test:.*zig build xcframework'" build.zig >/dev/null; then
  echo "FAIL: build.zig still contains an xcode-test fallback that rebuilds xcframework." >&2
  exit 1
fi

if search_fixed "\\n  zig build xcframework" macos/Smithers.xcodeproj/project.pbxproj >/dev/null || \
  search_regex "zig build xcframework \\|\\|" macos/Smithers.xcodeproj/project.pbxproj >/dev/null; then
  echo "FAIL: Xcode verify phase still rebuilds xcframework; it must be verify-only." >&2
  exit 1
fi

for run in 1 2 3; do
  log_file="$LOG_DIR/run-${run}.log"
  echo "Run $run/3: rm -rf dist/SmithersKit.xcframework && zig build all"

  if rm -rf dist/SmithersKit.xcframework && zig build all >"$log_file" 2>&1; then
    if search_regex "exited with code 70|couldn’t be copied to|xcode-build: failed to build xcframework|run xcodebuild failure" "$log_file" >/dev/null; then
      echo "FAIL: race signature detected in successful run output (run $run)." >&2
      cat "$log_file" >&2
      exit 1
    fi
  else
    echo "FAIL: zig build all failed on run $run." >&2
    cat "$log_file" >&2
    exit 1
  fi
done

echo "PASS: xcframework single-writer regression check passed (3/3)."
