#!/usr/bin/env bash
set -euo pipefail

XCFW="dist/SmithersKit.xcframework"

if [[ ! -d "$XCFW" ]]; then
  echo "FAIL: $XCFW not found. Run: zig build xcframework" >&2
  exit 1
fi

if [[ ! -f "$XCFW/Info.plist" ]]; then
  echo "FAIL: Info.plist missing in xcframework" >&2
  exit 1
fi

mapfile -t HEADER_MATCH < <(find "$XCFW" -type f -path '*/Headers/libsmithers.h' -maxdepth 3)
if [[ ${#HEADER_MATCH[@]} -eq 0 ]]; then
  echo "FAIL: Headers/libsmithers.h missing in xcframework" >&2
  exit 1
else
  echo "Header found at: ${HEADER_MATCH[0]}"
fi

# Verify module.modulemap exists for Swift import support
mapfile -t MODULEMAP < <(find "$XCFW" -type f -path '*/Headers/module.modulemap' -maxdepth 3)
if [[ ${#MODULEMAP[@]} -eq 0 ]]; then
  echo "FAIL: Headers/module.modulemap missing in xcframework (needed for Swift imports)" >&2
  exit 1
else
  echo "module.modulemap found at: ${MODULEMAP[0]}"
fi

mapfile -t LIBS < <(find "$XCFW" -name '*.a' -maxdepth 3)
if [[ ${#LIBS[@]} -eq 0 ]]; then
  echo "FAIL: No .a found in xcframework" >&2
  exit 1
fi

echo "Found libs:" "${LIBS[@]}"

if command -v lipo >/dev/null 2>&1; then
  for lib in "${LIBS[@]}"; do
    echo "lipo -info $lib"
    lipo -info "$lib" || true
  done
fi

if command -v nm >/dev/null 2>&1; then
  if nm -gU "${LIBS[0]}" | grep -Eq "[_]?smithers_app_new"; then
    echo "Symbol check OK"
  else
    echo "WARN: smithers_app_new not found (toolchain differences possible)"
  fi
fi

echo "xcframework looks sane."
