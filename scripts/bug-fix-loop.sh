#!/bin/bash
#
# Automated Bug Fix Loop (CLI Version)
#
# Uses `claude -p` headless mode to fix bugs sequentially.
# More stable than SDK approach, easier to debug.
#
# Usage:
#   ./scripts/bug-fix-loop.sh [--dry-run] [--max N]
#
# Requirements:
#   - Claude Code CLI installed
#   - GitHub CLI (gh) installed
#   - bun, zig, docker-compose available

set -euo pipefail

# Configuration
REPORTS_DIR="reports/bug-fixes"
MAX_BUGS=${MAX_BUGS:-5}
DRY_RUN=${DRY_RUN:-false}
LOG_FILE="$REPORTS_DIR/loop-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --max) MAX_BUGS="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Ensure reports directory exists
mkdir -p "$REPORTS_DIR"

# Log function
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Get list of open bug issues
get_open_bugs() {
    gh issue list --state open --label bug --json number,title --jq '.[] | "\(.number)|\(.title)"' 2>/dev/null || echo ""
}

# Bug priority (hardcoded for now)
get_bug_priority() {
    local issue_num=$1
    case $issue_num in
        40) echo "Critical" ;;
        38|37|41) echo "High" ;;
        36|34|39) echo "Medium" ;;
        35) echo "Low" ;;
        *) echo "Medium" ;;
    esac
}

# Create handoff prompt for a bug
create_prompt() {
    local issue_num=$1
    local issue_title=$2
    local priority=$(get_bug_priority $issue_num)

    cat <<EOF
# Bug Fix Agent Task

Fix GitHub Issue #${issue_num}: ${issue_title}

## Critical Rules
1. Work on plue-git branch (single-branch workflow - NO feature branches)
2. Test-driven: run \`bun playwright test -g "BUG-${issue_num}"\` before and after fix
3. Commit directly to plue-git with descriptive message
4. Close the issue with \`gh issue close ${issue_num} --reason completed\`

## Workflow
1. \`gh issue view ${issue_num}\` - Read the issue details
2. \`bun playwright test -g "BUG-${issue_num}" --reporter=list\` - See failing test
3. Investigate the code, implement minimal fix
4. Verify tests pass
5. \`git add -A && git commit -m "fix: [description] Fixes #${issue_num}"\`
6. \`git push origin plue-git\`
7. \`gh issue close ${issue_num} --reason completed\`

## Context
- Priority: ${priority}
- Auth endpoint: /api/auth/siwe/verify
- Rebuild Zig: \`zig build server\` or \`docker-compose up -d --build api\`
- Route pattern for issues: /api/:user/:repo/issues (no /repos/ prefix)

When done, output a summary with:
- What was changed
- Commit hash
- Test results
EOF
}

# Fix a single bug
fix_bug() {
    local issue_num=$1
    local issue_title=$2
    local start_time=$(date +%s)
    local report_file="$REPORTS_DIR/bug-${issue_num}-$(date +%Y%m%d-%H%M%S).md"

    log "${YELLOW}Starting fix for bug #${issue_num}: ${issue_title}${NC}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "${YELLOW}[DRY RUN] Would run claude -p with prompt for bug #${issue_num}${NC}"
        create_prompt "$issue_num" "$issue_title"
        return 0
    fi

    # Create the prompt
    local prompt=$(create_prompt "$issue_num" "$issue_title")

    # Run Claude Code in headless mode
    log "Running Claude Code..."

    local output
    local exit_code=0

    # Capture output and exit code
    output=$(claude -p "$prompt" \
        --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TodoWrite" \
        --max-turns 30 \
        2>&1) || exit_code=$?

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Write report
    cat > "$report_file" <<EOF
# Bug Fix Report: Issue #${issue_num}

**Status**: $([ $exit_code -eq 0 ] && echo "SUCCESS" || echo "FAILED")
**Date**: $(date -Iseconds)
**Duration**: ${duration}s

## Bug Details
- **Title**: ${issue_title}
- **Priority**: $(get_bug_priority $issue_num)

## Output
\`\`\`
${output}
\`\`\`
EOF

    log "Report written: $report_file"

    # Commit report
    git add "$report_file" 2>/dev/null || true
    git commit -m "docs: Add bug fix report for issue #${issue_num}" 2>/dev/null || true

    # Check if tests pass
    if bun playwright test -g "BUG-${issue_num}" --reporter=list 2>/dev/null; then
        log "${GREEN}Bug #${issue_num} fixed successfully!${NC}"
        return 0
    else
        log "${RED}Bug #${issue_num} tests still failing${NC}"
        return 1
    fi
}

# Main loop
main() {
    log "========================================"
    log "  Automated Bug Fix Loop"
    log "  $(date)"
    log "========================================"
    log ""
    log "Configuration:"
    log "  Max bugs: $MAX_BUGS"
    log "  Dry run: $DRY_RUN"
    log "  Reports: $REPORTS_DIR"
    log ""

    # Ensure we're on plue-git
    current_branch=$(git branch --show-current)
    if [[ "$current_branch" != "plue-git" ]]; then
        log "${RED}Error: Must be on plue-git branch (currently on: $current_branch)${NC}"
        exit 1
    fi

    # Get open bugs
    log "Fetching open bugs..."
    local bugs=$(get_open_bugs)

    if [[ -z "$bugs" ]]; then
        log "No open bugs found!"
        exit 0
    fi

    local count=0
    local success=0
    local failed=0

    # Process each bug
    while IFS='|' read -r issue_num issue_title; do
        if [[ $count -ge $MAX_BUGS ]]; then
            log "Reached max bugs ($MAX_BUGS), stopping"
            break
        fi

        log ""
        log "========================================"
        log "Bug $((count + 1)): #${issue_num}"
        log "========================================"

        if fix_bug "$issue_num" "$issue_title"; then
            ((success++)) || true
        else
            ((failed++)) || true
            # Optionally stop on first failure
            # break
        fi

        ((count++)) || true

    done <<< "$bugs"

    # Summary
    log ""
    log "========================================"
    log "  SUMMARY"
    log "========================================"
    log "Bugs processed: $count"
    log "Successful: $success"
    log "Failed: $failed"
    log "Log file: $LOG_FILE"
}

main "$@"
