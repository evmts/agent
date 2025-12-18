# Session Forking

<metadata>
  <priority>medium</priority>
  <category>session-management</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>server/, core/, tui/</affects>
</metadata>

## Objective

Implement session forking that allows users to create a new conversation branch from any point in the message history.

<context>
Codex supports forking conversations from any message using the Esc-Esc backtrack mode. This enables:
- Exploring alternative approaches without losing context
- Branching after a failed attempt
- Creating "what if" scenarios
- Recovering from agent mistakes

When forking, a new session is created with messages up to the selected point, allowing the user to continue in a different direction.
</context>

## Requirements

<functional-requirements>
1. Esc-Esc in TUI enters backtrack mode:
   - Press Esc once to enter mode (when composer empty)
   - Press Esc again to step through message history
   - Enter confirms and forks at that point
   - Esc (third time) cancels
2. Fork creates new session:
   - Copies messages up to selected point
   - Sets parent session reference
   - Preserves context and metadata
3. Fork API endpoint:
   - `POST /session/{id}/fork`
   - Accept message index to fork from
   - Return new session ID
4. Visual feedback during backtrack
5. Session tree/history view (optional)
</functional-requirements>

<technical-requirements>
1. Add backtrack mode state to TUI
2. Implement message highlighting during backtrack
3. Create fork endpoint in server
4. Add parentID field to session model
5. Handle file state at fork point (snapshot)
6. Track fork relationships in session metadata
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/main.go` - Add backtrack mode handling
- `tui/internal/app/update_keys.go` - Esc key handling
- `server/routes/sessions.py` - Add fork endpoint
- `core/models/session.py` - Add parentID and fork tracking
</files-to-modify>

<backtrack-mode-ui>
```
┌────────────────────────────────────────────────────┐
│                 BACKTRACK MODE                      │
│  ← Press Esc to step back, Enter to fork here →    │
├────────────────────────────────────────────────────┤
│ You (message 1)                                    │
│ Can you help me implement the login feature?       │
│                                                    │
│ Assistant (message 2)                              │
│ I'll help you implement login. Let me start...    │
│                                                    │
│ You (message 3)                                    │
│ Actually, can we use OAuth instead?                │
│                                                    │
│ ┌────────────────────────────────────────────────┐ │
│ │ > Assistant (message 4) ← FORK POINT          │ │
│ │ Sure, I'll switch to OAuth. First, let me...  │ │
│ └────────────────────────────────────────────────┘ │
│                                                    │
│ [Esc: Step back] [Enter: Fork here] [Esc×3: Cancel]│
└────────────────────────────────────────────────────┘
```
</backtrack-mode-ui>

<fork-endpoint>
```python
# server/routes/sessions.py

class ForkRequest(BaseModel):
    message_index: int  # Fork after this message (0-indexed)
    title: Optional[str] = None  # Title for new session

@router.post("/session/{session_id}/fork")
async def fork_session(
    session_id: str,
    request: ForkRequest
) -> Session:
    """Fork a session from a specific message."""
    parent = get_session(session_id)
    if not parent:
        raise HTTPException(404, f"Session {session_id} not found")

    messages = get_session_messages(session_id)
    if request.message_index >= len(messages):
        raise HTTPException(400, "Message index out of range")

    # Create new session with copied messages
    new_session = Session(
        id=generate_session_id(),
        parent_id=session_id,
        directory=parent.directory,
        title=request.title or f"Fork of {parent.title}",
        fork_point=request.message_index,
    )

    # Copy messages up to fork point
    forked_messages = messages[:request.message_index + 1]
    save_session_messages(new_session.id, forked_messages)

    # Create snapshot at fork point
    create_snapshot(new_session.id, parent.directory)

    save_session(new_session)
    return new_session
```
</fork-endpoint>

<backtrack-state>
```go
type BacktrackState struct {
    Active       bool
    MessageIndex int  // Current position in history
    MaxIndex     int  // Total messages
}

func (m *Model) handleEscKey() tea.Cmd {
    // First Esc: enter backtrack mode (if composer empty)
    if !m.backtrack.Active && m.composer.IsEmpty() {
        m.backtrack.Active = true
        m.backtrack.MessageIndex = len(m.messages) - 1
        m.backtrack.MaxIndex = len(m.messages) - 1
        return nil
    }

    // Second+ Esc: step back in history
    if m.backtrack.Active {
        if m.backtrack.MessageIndex > 0 {
            m.backtrack.MessageIndex--
        } else {
            // At beginning, cancel backtrack
            m.backtrack.Active = false
        }
        return nil
    }

    return nil
}

func (m *Model) handleEnterKey() tea.Cmd {
    if m.backtrack.Active {
        // Fork at current position
        return m.forkSession(m.backtrack.MessageIndex)
    }
    // Normal enter handling...
}

func (m *Model) forkSession(messageIndex int) tea.Cmd {
    return func() tea.Msg {
        newSession, err := m.client.ForkSession(m.sessionID, messageIndex)
        if err != nil {
            return ForkErrorMsg{Err: err}
        }
        return ForkSuccessMsg{Session: newSession}
    }
}
```
</backtrack-state>

## Acceptance Criteria

<criteria>
- [ ] Esc enters backtrack mode when composer empty
- [ ] Esc steps back through message history
- [ ] Current fork point clearly highlighted
- [ ] Enter creates fork at selected point
- [ ] Third Esc cancels backtrack mode
- [ ] New session created with parent reference
- [ ] Messages copied up to fork point
- [ ] Fork point tracked in session metadata
- [ ] Snapshot created at fork point
- [ ] New session loads and works correctly
- [ ] Visual feedback shows backtrack mode active
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
2. Test forking at various points in conversation
3. Verify forked session loads correctly
4. Test parent-child relationship tracking
5. Run `zig build build-go` and `pytest` to ensure all passes
6. Rename this file from `36-session-forking.md` to `36-session-forking.complete.md`
</completion>
