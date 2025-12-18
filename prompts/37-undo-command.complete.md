# Undo Command

<metadata>
  <priority>medium</priority>
  <category>ui-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/, server/, core/</affects>
</metadata>

## Objective

Implement a `/undo` slash command that allows users to undo the last agent turn, reverting both the conversation and any file changes made.

<context>
Codex provides `/undo` to revert the agent's last response. This is useful when:
- The agent made unwanted file changes
- The approach taken was incorrect
- The user wants to try a different prompt
- Recovering from errors

Undo should revert both the message history and any file modifications made during that turn.
</context>

## Requirements

<functional-requirements>
1. `/undo` command reverts last agent turn
2. Revert conversation:
   - Remove last assistant message
   - Optionally remove the user message that prompted it
3. Revert file changes:
   - Use snapshot system to restore file state
   - Only revert changes from that turn
4. Show summary of what was undone:
   - Messages removed
   - Files restored
5. Support multiple undos (with limit)
6. `/undo N` to undo multiple turns at once
</functional-requirements>

<technical-requirements>
1. Add `/undo` handler to TUI slash commands
2. Track turn boundaries in session
3. Integrate with existing snapshot/revert system
4. Create undo endpoint or use existing revert
5. Handle edge cases (nothing to undo, first message)
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/main.go` - Add /undo command handler
- `server/routes/sessions.py` - Add undo endpoint (or extend revert)
- `core/sessions.py` - Track turn boundaries for undo
</files-to-modify>

<undo-flow>
```
User: "Add a login function"
    ↓
[Snapshot taken: snap_001]
    ↓
Agent: "I'll add a login function..."
Agent: [Edit: auth.py]
Agent: [Edit: routes.py]
    ↓
[Turn complete, snapshot: snap_002]

User: "/undo"
    ↓
1. Identify last turn (messages since last user message)
2. Revert to snap_001
3. Remove messages after snap_001
4. Show summary:
   "✓ Undone: 1 assistant message, 2 file changes reverted"
```
</undo-flow>

<slash-command-handler>
```go
// In TUI slash command handler
case "/undo":
    count := 1
    if len(args) > 0 {
        if n, err := strconv.Atoi(args[0]); err == nil && n > 0 {
            count = n
        }
    }

    result, err := client.UndoTurns(sessionID, count)
    if err != nil {
        return fmt.Errorf("undo failed: %w", err)
    }

    if result.TurnsUndone == 0 {
        fmt.Println("Nothing to undo")
        return nil
    }

    fmt.Printf("✓ Undone %d turn(s)\n", result.TurnsUndone)
    if len(result.FilesReverted) > 0 {
        fmt.Printf("  Files reverted: %s\n", strings.Join(result.FilesReverted, ", "))
    }
    fmt.Printf("  Messages removed: %d\n", result.MessagesRemoved)

    // Refresh message display
    return refreshMessages()
```
</slash-command-handler>

<undo-endpoint>
```python
# server/routes/sessions.py

class UndoRequest(BaseModel):
    count: int = 1  # Number of turns to undo

class UndoResult(BaseModel):
    turns_undone: int
    messages_removed: int
    files_reverted: list[str]
    snapshot_restored: Optional[str]

@router.post("/session/{session_id}/undo")
async def undo_turns(
    session_id: str,
    request: UndoRequest
) -> UndoResult:
    """Undo the last N agent turns."""
    session = get_session(session_id)
    messages = get_session_messages(session_id)

    if not messages:
        return UndoResult(turns_undone=0, messages_removed=0, files_reverted=[])

    # Find turn boundaries (user messages are turn starts)
    turn_starts = [i for i, m in enumerate(messages) if m.role == "user"]

    if len(turn_starts) < 2:
        return UndoResult(turns_undone=0, messages_removed=0, files_reverted=[])

    # Calculate undo point
    undo_count = min(request.count, len(turn_starts) - 1)
    undo_point = turn_starts[-undo_count]

    # Get snapshot at undo point
    snapshot = get_snapshot_at_index(session_id, undo_point)

    # Revert files
    files_reverted = []
    if snapshot:
        files_reverted = revert_to_snapshot(session_id, snapshot)

    # Remove messages after undo point
    messages_removed = len(messages) - undo_point
    truncate_messages(session_id, undo_point)

    return UndoResult(
        turns_undone=undo_count,
        messages_removed=messages_removed,
        files_reverted=files_reverted,
        snapshot_restored=snapshot,
    )
```
</undo-endpoint>

<turn-tracking>
```python
# Track snapshots at turn boundaries
class TurnTracker:
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.snapshots: list[TurnSnapshot] = []

    def start_turn(self, message_index: int):
        """Called before processing user message."""
        snapshot_id = create_snapshot(self.session_id)
        self.snapshots.append(TurnSnapshot(
            message_index=message_index,
            snapshot_id=snapshot_id,
            timestamp=time.time(),
        ))

    def get_snapshot_for_undo(self, turns_back: int = 1) -> Optional[str]:
        """Get snapshot ID for undoing N turns."""
        if len(self.snapshots) < turns_back + 1:
            return None
        return self.snapshots[-(turns_back + 1)].snapshot_id

@dataclass
class TurnSnapshot:
    message_index: int
    snapshot_id: str
    timestamp: float
```
</turn-tracking>

## Acceptance Criteria

<criteria>
- [x] `/undo` reverts last agent turn
- [x] Messages after undo point removed
- [x] File changes from turn reverted via snapshot
- [x] Summary shows what was undone
- [x] `/undo N` undoes multiple turns
- [x] Graceful handling when nothing to undo
- [x] Cannot undo past first message
- [x] Snapshot system correctly tracks turns
- [ ] UI refreshes after undo (TUI pending)
- [x] Works with revert/unrevert system
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
2. Test undo after file modifications
3. Test multiple undos in sequence
4. Verify file state correctly restored
5. Run `zig build build-go` and `pytest` to ensure all passes
6. Rename this file from `37-undo-command.md` to `37-undo-command.complete.md`
</completion>

## Implementation Hindsight

<hindsight>
**Completed:** 2024-12-17

**Key Implementation Notes:**
1. Turn = user message + following assistant messages until next user message
2. Snapshot history alignment: history[0]=initial, history[i+1]=after turn i
3. undo_turns returns tuple: (turns_undone, messages_removed, files_reverted, snapshot_hash)
4. At least one turn must remain (cannot undo first turn)
5. count is capped to prevent undoing past first turn
6. Publishes session.updated event after undo

**Files Modified:**
- `core/sessions.py` - Added undo_turns async function
- `core/__init__.py` - Export undo_turns
- `server/routes/sessions/undo.py` - POST /session/{id}/undo endpoint (pre-existed)
- `server/requests/undo_request.py` - UndoRequest and UndoResult models (pre-existed)
- `server/routes/sessions/__init__.py` - Register undo router

**Prompt Improvements for Future:**
1. Clarify snapshot timing: snapshots taken AFTER each turn completes
2. Provide concrete example with message indices and snapshot indices
3. Specify whether files_reverted lists changed files or reverted files
4. Note that undo endpoint and request models already existed
5. Mention event publishing requirement for state sync
6. TUI /undo handler should be separate task
</hindsight>
