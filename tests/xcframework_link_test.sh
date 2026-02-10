#!/usr/bin/env bash
set -euo pipefail

XCFW_ROOT="dist/SmithersKit.xcframework"

# Prefer the combined slice if present; otherwise pick the arm64 one.
if [[ -d "$XCFW_ROOT/macos-arm64_x86_64" ]]; then
  XCFW_DIR="$XCFW_ROOT/macos-arm64_x86_64"
  MAC_ARCHES=("arm64" "x86_64")
else
  # Per-arch slices
  XCFW_DIR_ARM64="$XCFW_ROOT/macos-arm64"
  XCFW_DIR_X86="$XCFW_ROOT/macos-x86_64"
  MAC_ARCHES=("arm64" "x86_64")
fi

HDR="${XCFW_DIR:-$XCFW_DIR_ARM64}/Headers"
LIB_UNI="${XCFW_DIR:-$XCFW_DIR_ARM64}/libsmithers-universal.a"

if [[ ! -d "$XCFW_ROOT" ]]; then
  echo "xcframework not found; run: zig build xcframework" >&2
  exit 1
fi

TMP_C=$(mktemp -t sm_link).c
cat > "$TMP_C" <<'C'
#include "libsmithers.h"
#include <stddef.h>

static void wake(void* u) { (void)u; }
static void act(void* u, enum smithers_action_tag_e t, const void* d, size_t l) {
  (void)u; (void)t; (void)d; (void)l;
}

int main(void) {
  struct smithers_config_s cfg = {0};
  cfg.runtime.wakeup = &wake;
  cfg.runtime.action = &act;
  cfg.runtime.userdata = NULL;
  smithers_app_t app = smithers_app_new(&cfg);
  if (app) smithers_app_free(app);
  return 0;
}
C

link_arch() {
  local arch="$1"
  local lib="$2"
  local out
  out=$(mktemp -t sm_link_bin)
  echo "Linking test for $arch using $lib"
  clang -arch "$arch" -mmacosx-version-min=14.0 -I"$HDR" "$TMP_C" "$lib" -o "$out"
  echo "Link OK ($arch): $out"
}

if [[ -f "$LIB_UNI" ]]; then
  # Try both arches against the universal lib if toolchain supports it
  for a in "${MAC_ARCHES[@]}"; do
    if lipo -info "$LIB_UNI" 2>/dev/null | grep -q "$a"; then
      link_arch "$a" "$LIB_UNI"
    fi
  done
else
  # Fallback to per-arch slices
  [[ -d "$XCFW_DIR_ARM64" ]] && link_arch arm64 "$XCFW_DIR_ARM64/libsmithers.a"
  if [[ -d "$XCFW_DIR_X86" ]]; then
    link_arch x86_64 "$XCFW_DIR_X86/libsmithers.a"
  fi
fi
