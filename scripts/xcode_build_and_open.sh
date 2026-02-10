#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d macos ]]; then
  echo "skipping: macos/ not found"; exit 0
fi

# Use a deterministic derived data under .build/xcode for consistency.
DERIVED="$(pwd)/.build/xcode"
mkdir -p "$DERIVED"

xcodebuild \
  -project macos/Smithers.xcodeproj \
  -scheme Smithers \
  -derivedDataPath "$DERIVED" \
  build

APP="$DERIVED/Build/Products/Debug/Smithers.app"
if [[ -d "$APP" ]]; then
  open "$APP"
else
  echo "build ok; app not found at $APP"
fi

