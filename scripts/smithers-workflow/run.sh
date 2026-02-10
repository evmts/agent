#!/usr/bin/env bash
# Run the Smithers v2 build workflow
# Usage: ./run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$SCRIPT_DIR"

export USE_CLI_AGENTS=1
export SMITHERS_DEBUG=1
export SMITHERS_UNSAFE=1
unset ANTHROPIC_API_KEY

SMITHERS_CLI="${SMITHERS_CLI:-smithers}"

echo "Starting Smithers v2 build workflow"
echo "Root directory: $ROOT_DIR"
echo "Press Ctrl+C to stop."
echo ""

bun run "$SMITHERS_CLI" run workflow.tsx --input '{}' --root-dir "$ROOT_DIR"
