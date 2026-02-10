#!/usr/bin/env bash
# Run the Smithers v2 build workflow
# Usage: ./run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$SCRIPT_DIR"

# Use CLI agents
unset ANTHROPIC_API_KEY

export SMITHERS_DEBUG=1

echo "Starting Smithers v2 build workflow"
echo "Root directory: $ROOT_DIR"
echo "Press Ctrl+C to stop."
echo ""

bun run /Users/williamcory/guillotine-mini/smithers/src/cli/index.ts run workflow.tsx --input '{}' --root-dir "$ROOT_DIR"
