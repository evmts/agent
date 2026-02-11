#!/usr/bin/env bash
set -euo pipefail

XCFW="dist/SmithersKit.xcframework"

if [ ! -d "$XCFW" ]; then
  echo "FAIL: $XCFW not found. Run: zig build xcframework" >&2
  exit 1
fi

if [ ! -f "$XCFW/Info.plist" ]; then
  echo "FAIL: Info.plist missing in xcframework" >&2
  exit 1
fi

HEADER_PATH=$(find "$XCFW" -type f -maxdepth 3 -path '*/Headers/libsmithers.h' | head -n 1 || true)
if [ -z "${HEADER_PATH:-}" ]; then
  echo "FAIL: Headers/libsmithers.h missing in xcframework" >&2
  exit 1
else
  echo "Header found at: $HEADER_PATH"
fi

MODULEMAP_PATH=$(find "$XCFW" -type f -maxdepth 3 -path '*/Headers/module.modulemap' | head -n 1 || true)
if [ -z "${MODULEMAP_PATH:-}" ]; then
  echo "FAIL: Headers/module.modulemap missing in xcframework (needed for Swift imports)" >&2
  exit 1
else
  echo "module.modulemap found at: $MODULEMAP_PATH"
fi

LIBS_LIST=$(find "$XCFW" -name '*.a' -maxdepth 3)
if [ -z "${LIBS_LIST:-}" ]; then
  echo "FAIL: No .a found in xcframework" >&2
  exit 1
fi
echo "Found libs:" "$LIBS_LIST"

if command -v lipo >/dev/null 2>&1; then
  while IFS= read -r lib; do
    [ -z "$lib" ] && continue
    echo "lipo -info $lib"
    lipo -info "$lib" || true
  done <<< "$LIBS_LIST"
fi

FIRST_LIB=$(printf "%s\n" "$LIBS_LIST" | head -n 1)
if command -v nm >/dev/null 2>&1 && [ -n "$FIRST_LIB" ]; then
  if nm -gU "$FIRST_LIB" 2>/dev/null | grep -Eq "[_]?smithers_app_new"; then
    echo "Symbol check OK"
  else
    echo "WARN: smithers_app_new not found (toolchain differences possible)"
  fi
fi

echo "xcframework looks sane."
