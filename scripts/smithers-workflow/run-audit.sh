#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$SCRIPT_DIR"

export USE_CLI_AGENTS=1
export SMITHERS_DEBUG=1
export SMITHERS_UNSAFE=1
unset ANTHROPIC_API_KEY

SMITHERS_CLI="${SMITHERS_CLI:-./node_modules/.bin/smithers}"

echo "Starting Smithers v2 feature audit"
echo "Root directory: $ROOT_DIR"
echo ""

bun "$SMITHERS_CLI" run audit.tsx --input '{}' --root "$ROOT_DIR"
