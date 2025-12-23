#!/bin/bash

# Workflow Agent Loop
# Alternates between Claude Code and Codex to work on workflows spec with persistent memory

LOG_FILE="log.txt"
MEMORY_FILE="docs/workflows/memories.md"

# Create memory file if it doesn't exist
if [ ! -f "$MEMORY_FILE" ]; then
    cat > "$MEMORY_FILE" << 'EOF'
# Workflows Development Memory

This file tracks progress, learnings, and important context for the workflows implementation.

## Session Log

<!-- New entries should be added at the top -->

## Key Decisions

## Open Questions

## Validated Completions

<!-- Only add items here after personally verifying they work -->

## Known Issues

EOF
    echo "[$(date)] Created initial memory file: $MEMORY_FILE" >> "$LOG_FILE"
fi

CLAUDE_PROMPT='You are working on the Plue Workflows system implementation.

## Context Files (READ THESE FIRST)
- @docs/architecture.md - Overall system architecture
- @docs/workflows-prd.md - Product requirements for workflows
- @docs/workflows-engineering.md - Engineering design spec
- @CLAUDE.md - Project conventions and structure
- @docs/workflows/memories.md - CRITICAL: Persistent memory across sessions

## Implementation Specs (in docs/workflows/)
- 01-storage-foundations.md
- 02-restrictedpython-runtime.md
- 03-prompt-parser.md
- 04-type-system-and-validation.md
- 05-definition-discovery-and-registry.md
- 06-execution-engine-shell.md
- 07-llm-agent-tools-streaming.md
- 08-runner-pool-and-sandbox.md
- 09-api-cli-ui.md

## Your Mission

1. **Read memories.md FIRST** - Understand what has been done, what is in progress, and any blockers.

2. **Work on the workflows implementation** according to the specs above. Focus areas:
   - Testing and validation are TOP PRIORITY
   - Write tests before or alongside implementation
   - Validate that code actually works, not just compiles

3. **Verify claims from prior sessions** - If memories.md says something is "done", verify it yourself:
   - Run the tests
   - Check the code exists and is correct
   - Update memories.md if the claim was wrong

4. **Update memories.md** with:
   - What you worked on this session
   - Any important learnings or discoveries
   - Progress made (with verification status)
   - Blockers or issues encountered
   - Next steps for future sessions

5. **Be skeptical** - Do not trust that prior work is correct. Validate everything.

## Output Format

After each session, update docs/workflows/memories.md with a new entry at the top of the Session Log section:

```markdown
### Session [DATE TIME] - Claude
**Focus**: [What you worked on]
**Verified**: [What you personally validated works]
**Progress**: [Concrete changes made]
**Issues**: [Problems encountered]
**Next**: [Suggested next steps]
```

Now read the context files and memories.md, then continue the implementation work with a focus on testing and validation.'

CODEX_PROMPT='You are a code reviewer and improver for the Plue Workflows system.

## Context Files (READ THESE FIRST)
- @docs/architecture.md - Overall system architecture
- @docs/workflows-prd.md - Product requirements for workflows
- @docs/workflows-engineering.md - Engineering design spec
- @CLAUDE.md - Project conventions and structure
- @docs/workflows/memories.md - CRITICAL: Persistent memory across sessions

## Implementation Specs (in docs/workflows/)
- 01-storage-foundations.md through 09-api-cli-ui.md

## Your Mission: REVIEW AND IMPROVE

1. **Read memories.md FIRST** - See what Claude did in the previous session.

2. **Review the recent work**:
   - Check code quality and correctness
   - Verify tests actually test what they claim
   - Look for edge cases, bugs, or missing error handling
   - Ensure code matches the specs in docs/workflows/

3. **Improve what was done**:
   - Fix any bugs or issues you find
   - Add missing tests or improve test coverage
   - Refactor for clarity if needed
   - Add documentation where missing

4. **Validate claims**:
   - If memories.md says tests pass, run them yourself
   - If it says something is complete, verify it
   - Update memories.md with corrections if needed

5. **Update memories.md** with your review:

```markdown
### Session [DATE TIME] - Codex Review
**Reviewed**: [What you reviewed from prior session]
**Issues Found**: [Problems discovered]
**Fixes Applied**: [What you fixed/improved]
**Test Results**: [Actual test output]
**Recommendations**: [Suggestions for next Claude session]
```

6. **Focus on quality over quantity** - Better to fix one thing properly than gloss over many.

Now read the context and memories.md, then review and improve the recent work.'

echo "[$(date)] Starting workflow agent loop (alternating Claude/Codex)..." >> "$LOG_FILE"
echo "Workflow Agent Started - Logging to $LOG_FILE"
echo "Alternating between Claude (implement) and Codex (review)"
echo "Press Ctrl+C to stop"

ITERATION=0

while true; do
    ITERATION=$((ITERATION + 1))

    echo "" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"

    if [ $((ITERATION % 2)) -eq 1 ]; then
        # Odd iterations: Claude implements
        AGENT="claude"
        PROMPT="$CLAUDE_PROMPT"
        echo "[$(date)] Session #$ITERATION - CLAUDE (implementing)..." >> "$LOG_FILE"
        echo "Session #$ITERATION - Claude (implementing)"
    else
        # Even iterations: Codex reviews
        AGENT="codex"
        PROMPT="$CODEX_PROMPT"
        echo "[$(date)] Session #$ITERATION - CODEX (reviewing)..." >> "$LOG_FILE"
        echo "Session #$ITERATION - Codex (reviewing)"
    fi

    echo "========================================" >> "$LOG_FILE"

    # Run the appropriate agent
    if [ "$AGENT" = "claude" ]; then
        claude --print "$PROMPT" 2>&1 | tee -a "$LOG_FILE"
    else
        codex "$PROMPT" 2>&1 | tee -a "$LOG_FILE"
    fi

    EXIT_CODE=$?
    echo "" >> "$LOG_FILE"
    echo "[$(date)] Session ended with exit code: $EXIT_CODE" >> "$LOG_FILE"

    echo "[$(date)] Waiting 10 seconds before next session..."
    sleep 10
done
