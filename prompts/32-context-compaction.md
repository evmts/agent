# Context Compaction

<metadata>
  <priority>high</priority>
  <category>session-management</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/, server/, core/</affects>
</metadata>

## Objective

Implement context compaction that summarizes conversation history to prevent context limit errors, with both automatic and manual (`/compact`) triggering.

<context>
Long conversations can exceed model context limits. Codex implements compaction that:
- Automatically triggers when approaching context limits
- Can be manually triggered with `/compact` slash command
- Summarizes older messages while preserving recent context
- Maintains key information (file paths, decisions, code snippets)
- Reduces token count while preserving conversation meaning

This is critical for extended coding sessions where context accumulates over hundreds of messages.
</context>

## Requirements

<functional-requirements>
1. Automatic compaction:
   - Monitor token count during conversation
   - Trigger when approaching `model_auto_compact_token_limit`
   - Configurable threshold (e.g., 80% of context window)
2. Manual compaction via `/compact` slash command
3. Compaction process:
   - Summarize older messages (beyond last N messages)
   - Preserve recent messages intact (last 5-10)
   - Create summary message with key information
   - Replace old messages with summary
4. Preserve critical information:
   - File paths mentioned
   - Key decisions made
   - Important code snippets
   - Error messages and solutions
5. Show compaction status:
   - "Conversation compacted: X messages → summary"
   - Token count before/after
6. Configurable compaction prompt
</functional-requirements>

<technical-requirements>
1. Add token counting to session state
2. Implement compaction detection logic
3. Create compaction prompt for summarization
4. Implement `/compact` slash command in TUI
5. Add `compact` endpoint to server API
6. Store compaction history in session metadata
7. Add configuration options:
   - `model_auto_compact_token_limit`
   - `compact_prompt` override
   - Messages to preserve count
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `agent/agent.py` - Add compaction logic
- `server/routes/sessions.py` - Add compact endpoint
- `core/models/session.py` - Track token counts and compaction state
- `tui/main.go` - Add /compact command handler
- `config/defaults.py` - Add compaction configuration
</files-to-modify>

<compaction-algorithm>
```python
async def compact_conversation(
    session_id: str,
    messages: list[Message],
    preserve_count: int = 5,
    model: str = "default"
) -> CompactionResult:
    """
    Compact conversation history by summarizing older messages.

    Args:
        session_id: Session to compact
        messages: Full message history
        preserve_count: Number of recent messages to keep intact
        model: Model to use for summarization

    Returns:
        CompactionResult with summary and preserved messages
    """
    if len(messages) <= preserve_count + 1:
        return CompactionResult(
            compacted=False,
            reason="Not enough messages to compact"
        )

    # Split messages
    to_summarize = messages[:-preserve_count]
    to_preserve = messages[-preserve_count:]

    # Calculate tokens before
    tokens_before = count_tokens(messages)

    # Generate summary
    summary = await generate_summary(to_summarize)

    # Create summary message
    summary_message = Message(
        role="system",
        content=f"[Conversation Summary]\n{summary}\n\n[End Summary - {len(to_summarize)} messages compacted]"
    )

    # New message list
    compacted_messages = [summary_message] + to_preserve
    tokens_after = count_tokens(compacted_messages)

    return CompactionResult(
        compacted=True,
        messages=compacted_messages,
        tokens_before=tokens_before,
        tokens_after=tokens_after,
        messages_removed=len(to_summarize),
        summary=summary
    )
```
</compaction-algorithm>

<compaction-prompt>
```
You are summarizing a conversation between a user and an AI coding assistant.
Create a concise summary that preserves:

1. KEY DECISIONS: Important choices made during the conversation
2. FILE CONTEXT: Files that were read, edited, or created
3. CODE CHANGES: Summary of code modifications made
4. ERRORS & SOLUTIONS: Any errors encountered and how they were resolved
5. CURRENT STATE: What the user is currently working on

Format as structured bullet points. Be concise but complete.

CONVERSATION TO SUMMARIZE:
{messages}
```
</compaction-prompt>

<slash-command-handler>
```go
// In TUI slash command handler
case "/compact":
    // Call compact API
    result, err := client.CompactSession(sessionID)
    if err != nil {
        return fmt.Errorf("compaction failed: %w", err)
    }

    if result.Compacted {
        fmt.Printf("✓ Compacted %d messages\n", result.MessagesRemoved)
        fmt.Printf("  Tokens: %d → %d (saved %d)\n",
            result.TokensBefore,
            result.TokensAfter,
            result.TokensBefore - result.TokensAfter)
    } else {
        fmt.Printf("No compaction needed: %s\n", result.Reason)
    }
```
</slash-command-handler>

<auto-compaction>
```python
# In message handling loop
async def process_message(session_id: str, message: str):
    session = get_session(session_id)

    # Check if compaction needed
    current_tokens = count_session_tokens(session)
    threshold = get_config("model_auto_compact_token_limit")

    if current_tokens > threshold:
        logger.info(f"Auto-compacting session {session_id}: {current_tokens} tokens")
        result = await compact_conversation(session_id, session.messages)
        if result.compacted:
            # Notify client of compaction
            emit_event("session.compacted", {
                "session_id": session_id,
                "tokens_saved": result.tokens_before - result.tokens_after
            })

    # Continue with message processing...
```
</auto-compaction>

## Acceptance Criteria

<criteria>
- [ ] `/compact` command triggers manual compaction
- [ ] Auto-compaction triggers at configured threshold
- [ ] Summary preserves key decisions and file context
- [ ] Recent messages (last N) preserved intact
- [ ] Token count shown before/after compaction
- [ ] Compaction event emitted for UI update
- [ ] Configurable compaction prompt
- [ ] Configurable preservation count
- [ ] Compaction history tracked in session metadata
- [ ] Graceful handling when conversation too short
</criteria>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions
</execution-strategy>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Test manual /compact command
3. Test auto-compaction with long conversation
4. Verify summary quality preserves key information
5. Run `pytest` and `zig build build-go` to ensure all passes
6. Rename this file from `32-context-compaction.md` to `32-context-compaction.complete.md`
</completion>
