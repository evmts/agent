#!/bin/bash

# Workflow Agent Loop
# Alternates between Claude Code and Codex to work on workflows

LOG_FILE="log.txt"
MEMORY_FILE="docs/workflows/memories.md"

# Environment for testing
export DATABASE_URL="${DATABASE_URL:-postgresql://postgres:password@localhost:54321/plue?sslmode=disable}"
export WATCHER_ENABLED="${WATCHER_ENABLED:-false}"

# Focused prompts for phases 10-15
CLAUDE_PROMPT='Implement Plue Workflows phases 10-15.

CONTEXT: Phases 01-09 are COMPLETE and verified. Focus on phases 10-15.

1. Read @docs/workflows/memories.md FIRST - see phase definitions and tasks
2. Read @docs/workflows-engineering.md for architecture details
3. Read @docs/infrastructure.md for K8s/Terraform context
4. Work on the FIRST incomplete task from phases 10-15:
   - Phase 10: Local runner integration (runner → executor → SSE)
   - Phase 11: Playwright E2E tests for workflows
   - Phase 12: K8s deployment (runner pods, warm pool)
   - Phase 13: Terraform (GKE, Cloud SQL)
   - Phase 14: UI (workflow list, run details, SSE streaming)
   - Phase 15: Monitoring (Prometheus, Grafana)

5. After completing work:
   - Run tests: `zig build test`
   - For E2E: `cd e2e && bun run test`
   - Update memories.md with progress

PRIORITY: Phase 10 (local runner) and Phase 11 (E2E tests) are most important.
Make workflows work end-to-end locally, then add E2E tests to verify.

Key context: @CLAUDE.md, @docs/architecture.md'

CODEX_PROMPT='Review and improve Plue Workflows phases 10-15.

CONTEXT: Phases 01-09 are complete. Focus on reviewing phases 10-15 work.

1. Read @docs/workflows/memories.md FIRST - see phase definitions
2. Run `zig build test` to verify nothing is broken
3. Review recent changes for:
   - Code quality
   - Missing error handling
   - Test coverage
   - Documentation
4. If E2E tests exist, run: `cd e2e && bun run test`
5. Update memories.md with review notes

FOCUS AREAS:
- Phase 10: Is the local runner correctly wired to executor?
- Phase 11: Are E2E tests comprehensive?
- Phase 14: Does UI handle SSE streaming correctly?
- Phase 12-13: Are K8s/Terraform configs valid?

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
