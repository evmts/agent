#!/bin/bash

# Workflow Agent Loop
# Alternates between Claude Code and Codex to work on workflows

LOG_FILE="log.txt"
MEMORY_FILE="docs/workflows/memories.md"

# Environment for testing
export DATABASE_URL="${DATABASE_URL:-postgresql://postgres:password@localhost:54321/plue?sslmode=disable}"
export WATCHER_ENABLED="${WATCHER_ENABLED:-false}"

# Focused prompts - verify 01-09 first, then implement 10-15
CLAUDE_PROMPT='Implement Plue Workflows - verify then extend.

1. Read @docs/workflows/memories.md FIRST - see current status and phase definitions

2. VERIFY PHASES 01-09 FIRST (all marked ❌ need verification):
   - Run `zig build` and `zig build test`
   - Start server: `WATCHER_ENABLED=false ./server/zig-out/bin/server-zig`
   - Test CLI: `./server/zig-out/bin/plue --help`
   - Test API: `curl POST /api/workflows/parse` with sample workflow
   - Mark each phase ✅ in memories.md as you verify

3. THEN work on phases 10-15 (in order):
   - Phase 10: Local runner (runner → executor → SSE streaming)
   - Phase 11: Playwright E2E tests for workflows
   - Phase 12: K8s deployment (runner pods, warm pool, gVisor)
   - Phase 13: Terraform (GKE, Cloud SQL, networking)
   - Phase 14: UI completion (workflow list, run details, streaming)
   - Phase 15: Monitoring (Prometheus, Grafana, Loki)

4. Update memories.md with:
   - Verification results (✅ or ❌ for each phase)
   - Tasks completed
   - Any blockers found

Key docs: @CLAUDE.md, @docs/workflows-engineering.md, @docs/infrastructure.md'

CODEX_PROMPT='Review Plue Workflows implementation.

1. Read @docs/workflows/memories.md FIRST

2. VERIFY what Claude claimed:
   - Run `zig build test` - all tests should pass
   - Check phases marked ✅ are actually working
   - If phases 01-09 verified, check phases 10-15 work

3. Review code quality:
   - Error handling
   - Memory management (no leaks)
   - Test coverage
   - Documentation

4. Run E2E tests if they exist: `cd e2e && bun run test`

5. Update memories.md:
   - Confirm or dispute verification claims
   - Note any issues found
   - Suggest improvements

Key context: @CLAUDE.md'

echo "[$(date)] Starting workflow agent loop..." >> "$LOG_FILE"
echo "Workflow Agent Started"
echo "  Log: $LOG_FILE"
echo "  Memory: $MEMORY_FILE"
echo "  Focus: Phases 10-15 (local dev, E2E, K8s, Terraform, UI, monitoring)"
echo "  DATABASE_URL: $DATABASE_URL"
echo "  WATCHER_ENABLED: $WATCHER_ENABLED"
echo "Press Ctrl+C to stop"
echo ""

# Pre-flight check
echo "Running pre-flight build check..."
if ! zig build 2>&1; then
    echo "ERROR: Build failed. Fix before running agents."
    exit 1
fi
echo "Build OK. Starting agent loop..."
echo ""

ITERATION=0

while true; do
    ITERATION=$((ITERATION + 1))

    echo "" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"

    if [ $((ITERATION % 2)) -eq 1 ]; then
        AGENT="claude"
        PROMPT="$CLAUDE_PROMPT"
        echo "[$(date)] Session #$ITERATION - CLAUDE (implementing phases 10-15)..." >> "$LOG_FILE"
        echo "Session #$ITERATION - Claude (implementing)"
    else
        AGENT="codex"
        PROMPT="$CODEX_PROMPT"
        echo "[$(date)] Session #$ITERATION - CODEX (reviewing phases 10-15)..." >> "$LOG_FILE"
        echo "Session #$ITERATION - Codex (reviewing)"
    fi

    echo "========================================" >> "$LOG_FILE"

    # Run agent
    if [ "$AGENT" = "claude" ]; then
        claude --dangerously-skip-permissions --print "$PROMPT" 2>&1 | tee -a "$LOG_FILE"
    else
        codex exec -c model_reasoning_effort="high" --dangerously-bypass-approvals-and-sandbox "$PROMPT" 2>&1 | tee -a "$LOG_FILE"
    fi

    EXIT_CODE=$?
    echo "" >> "$LOG_FILE"
    echo "[$(date)] Session #$ITERATION ended with exit code: $EXIT_CODE" >> "$LOG_FILE"

    echo "[$(date)] Waiting 10 seconds before next session..."
    sleep 10
done
