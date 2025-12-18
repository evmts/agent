# Model Switching Command

<metadata>
  <priority>high</priority>
  <category>ui-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/, server/, agent/</affects>
</metadata>

## Objective

Implement a `/model` slash command that allows users to switch models and configure reasoning effort during an active session.

<context>
Codex allows users to change models mid-conversation with `/model`. This is useful for:
- Switching to a faster model for simple tasks
- Upgrading to a more capable model for complex reasoning
- Adjusting reasoning effort (minimal/low/medium/high)
- Comparing responses across different models

The command should show available models, current selection, and allow configuration changes without starting a new session.
</context>

## Requirements

<functional-requirements>
1. `/model` command opens model selection UI
2. Show available models with current selection highlighted
3. Allow changing:
   - Model (claude-sonnet, claude-opus, etc.)
   - Reasoning effort level (if supported)
4. Apply changes to current session immediately
5. Persist model preference for new sessions
6. Show model capabilities/context window info
7. Keyboard navigation for model selection
</functional-requirements>

<technical-requirements>
1. Add `/model` handler to TUI slash commands
2. Create model selection overlay component
3. Add `PATCH /session/{id}` endpoint for model updates
4. Update session model field and reinitialize agent
5. Fetch available models from configuration
6. Handle model-specific capabilities (reasoning, context window)
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/main.go` - Add /model command handler
- `tui/internal/components/model_selector.go` (CREATE) - Model selection UI
- `server/routes/sessions.py` - Add model update endpoint
- `config/defaults.py` - Define available models
- `agent/agent.py` - Support dynamic model switching
</files-to-modify>

<cli-interface>
```
/model                    Open model selection UI
/model <model-name>       Switch directly to specified model
/model --list             List available models
```
</cli-interface>

<model-selector-ui>
```
┌────────────────── Select Model ──────────────────┐
│                                                   │
│  Current: claude-sonnet-4-20250514               │
│                                                   │
│  Available Models:                                │
│  ──────────────────────────────────────────────  │
│  > claude-opus-4-5-20251101     [200K context]   │
│    claude-sonnet-4-20250514     [200K context]   │
│    claude-haiku-3-5-20241022    [200K context]   │
│                                                   │
│  Reasoning Effort: ○ minimal ○ low ● medium ○ high│
│                                                   │
│  [Enter: Select] [↑↓: Navigate] [Esc: Cancel]    │
└───────────────────────────────────────────────────┘
```
</model-selector-ui>

<model-config>
```python
# config/defaults.py
AVAILABLE_MODELS = [
    {
        "id": "claude-opus-4-5-20251101",
        "name": "Claude Opus 4.5",
        "context_window": 200000,
        "supports_reasoning": True,
        "reasoning_levels": ["minimal", "low", "medium", "high"],
    },
    {
        "id": "claude-sonnet-4-20250514",
        "name": "Claude Sonnet 4",
        "context_window": 200000,
        "supports_reasoning": True,
        "reasoning_levels": ["minimal", "low", "medium", "high"],
    },
    {
        "id": "claude-haiku-3-5-20241022",
        "name": "Claude Haiku 3.5",
        "context_window": 200000,
        "supports_reasoning": False,
    },
]

DEFAULT_MODEL = "claude-sonnet-4-20250514"
DEFAULT_REASONING_EFFORT = "medium"
```
</model-config>

<session-update-api>
```python
# server/routes/sessions.py
@router.patch("/session/{session_id}")
async def update_session(
    session_id: str,
    update: SessionUpdate
) -> Session:
    """Update session configuration including model."""
    session = get_session(session_id)

    if update.model:
        # Validate model exists
        if update.model not in [m["id"] for m in AVAILABLE_MODELS]:
            raise HTTPException(400, f"Unknown model: {update.model}")

        session.model = update.model
        # Reinitialize agent with new model
        await reinitialize_agent(session_id, update.model)

    if update.reasoning_effort:
        session.reasoning_effort = update.reasoning_effort

    return session

class SessionUpdate(BaseModel):
    model: Optional[str] = None
    reasoning_effort: Optional[str] = None
```
</session-update-api>

## Acceptance Criteria

<criteria>
- [ ] `/model` opens model selection overlay
- [ ] Current model highlighted in selection list
- [ ] Arrow keys navigate model list
- [ ] Enter selects model and closes overlay
- [ ] Esc cancels without changes
- [ ] Model change applies to current session immediately
- [ ] Reasoning effort selector (if model supports it)
- [ ] `/model <name>` switches directly without UI
- [ ] `/model --list` shows available models
- [ ] Error handling for invalid model names
- [ ] Model info shows context window size
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
2. Test model switching during active conversation
3. Verify reasoning effort changes take effect
4. Run `zig build build-go` and `pytest` to ensure all passes
5. Rename this file from `33-model-switching.md` to `33-model-switching.complete.md`
</completion>
