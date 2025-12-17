# Bypass Mode Backend

<metadata>
  <priority>high</priority>
  <category>security-feature</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/, config/, core/</affects>
</metadata>

## Objective

Implement backend enforcement for bypass mode that skips permission checks and allows unrestricted tool execution. This complements the existing TUI bypass mode toggle (UI-only) by adding actual backend permission bypass functionality.

<context>
The TUI already has a bypass mode toggle (lines 68, 948-950 in /Users/williamcory/agent/tui/main.go) that cycles through normal/plan/bypass modes. However, this is purely cosmetic - the backend does not respect or enforce bypass mode behavior.

From the backup implementation (/Users/williamcory/agent-bak-bak/tool/tool.go), bypass mode should:
1. Skip ALL permission checks for file operations (read/write/edit)
2. Skip ALL bash command restrictions
3. Skip ALL webfetch restrictions
4. Execute tools without asking for user approval
5. Be clearly indicated as a dangerous mode (shown in red in TUI)

The current Python backend uses MCP servers for tools and has a PermissionsConfig, but lacks bypass mode support.
</context>

## Requirements

<functional-requirements>
1. Add bypass_mode flag to session configuration
2. When bypass_mode is enabled:
   - Skip all permission checks in tools (bash, edit, write, webfetch)
   - Do NOT prompt user for approval
   - Execute all tool calls immediately
   - Log bypass mode usage for audit trail
3. When bypass_mode is disabled (default):
   - Respect existing permission configurations
   - Use pattern matching for bash/edit permissions
   - Prompt user when needed (future feature)
4. Propagate bypass_mode from TUI to backend via session metadata
5. Add safety warnings in logs when bypass mode is active
</functional-requirements>

<technical-requirements>
1. Add `bypass_mode: bool` field to Session model (core/sessions.py)
2. Update SessionCreateRequest to accept bypass_mode parameter
3. Pass bypass_mode through tool execution context (ToolContext equivalent)
4. Modify permission checking logic in agent execution:
   - Create permission checker utility function
   - Skip checks entirely when bypass_mode=True
   - Log all bypass mode operations
5. Update MCP tool wrappers to respect bypass mode
6. Add session metadata to track bypass mode state changes
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `core/sessions.py` - Add bypass_mode field to Session model
- `core/models.py` - Add bypass_mode to SessionCreateRequest
- `config/permissions_config.py` - Add bypass mode utilities
- `agent/agent.py` - Pass bypass mode through tool context
- `agent/wrapper.py` - Respect bypass mode in tool execution
- `server/routes/sessions.py` - Accept bypass_mode in create endpoint
</files-to-modify>

<reference-implementation>
From /Users/williamcory/agent-bak-bak/tool/tool.go:

```go
type ToolContext struct {
    SessionID string
    MessageID string
    Abort     context.Context
    Mode      string // "normal", "plan", "bypass"
}

func (r *ToolRegistry) Execute(id string, params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
    tool, err := r.Get(id)
    if err != nil {
        return ToolResult{}, err
    }

    // In plan mode, don't actually execute
    if ctx.Mode == "plan" {
        return ToolResult{
            Title:  fmt.Sprintf("[PLAN] %s", tool.Name),
            Output: fmt.Sprintf("Would execute %s with params: %v", tool.Name, params),
        }, nil
    }

    // In bypass mode, skip permission checks (handled in individual tools)

    return tool.Execute(params, ctx)
}
```

Key insights:
- Mode is passed through ToolContext
- Plan mode = dry run (don't execute)
- Bypass mode = execute without permission checks
- Individual tools check context.Mode before permission validation
</reference-implementation>

<example-implementation>

### 1. Update Session Model

```python
# core/sessions.py
from pydantic import BaseModel, Field

class Session(BaseModel):
    id: str
    agent_id: str
    created_at: datetime
    updated_at: datetime
    bypass_mode: bool = Field(
        default=False,
        description="If True, skip all permission checks (DANGEROUS)"
    )
    metadata: dict[str, Any] = Field(default_factory=dict)
```

### 2. Add Permission Checker Utility

```python
# config/permissions_config.py
import logging

logger = logging.getLogger(__name__)

class PermissionChecker:
    """Utility to check permissions with bypass support."""

    @staticmethod
    def should_skip_checks(bypass_mode: bool) -> bool:
        """Check if permission checks should be skipped."""
        if bypass_mode:
            logger.warning("⚠️  BYPASS MODE ACTIVE - Skipping permission checks")
            return True
        return False

    @staticmethod
    def check_bash_permission(
        command: str,
        patterns: list[str],
        bypass_mode: bool = False
    ) -> bool:
        """Check if bash command is allowed."""
        if PermissionChecker.should_skip_checks(bypass_mode):
            return True

        # Normal permission checking logic
        # ... pattern matching against bash_patterns
        return matches_any_pattern(command, patterns)

    @staticmethod
    def check_file_permission(
        file_path: str,
        patterns: list[str],
        bypass_mode: bool = False
    ) -> bool:
        """Check if file operation is allowed."""
        if PermissionChecker.should_skip_checks(bypass_mode):
            return True

        # Normal permission checking logic
        return matches_any_pattern(file_path, patterns)
```

### 3. Update Agent Creation

```python
# agent/agent.py
def create_agent_with_mcp(
    agent_id: str = "default",
    working_dir: str | None = None,
    bypass_mode: bool = False,  # NEW PARAMETER
) -> Agent:
    """Create agent with MCP servers and bypass mode support."""

    # Get agent config
    agent_config = get_agent_config(agent_id)

    # Build system prompt
    system_prompt = _build_system_prompt(
        agent_config.system_prompt,
        working_dir
    )

    # Add bypass mode warning to system prompt if enabled
    if bypass_mode:
        system_prompt = (
            "⚠️  BYPASS MODE ENABLED - All permission checks are disabled.\n\n"
            + system_prompt
        )

    # Store bypass mode in agent dependencies
    deps = AgentDeps(
        bypass_mode=bypass_mode,
        working_dir=working_dir or os.getcwd()
    )

    # Create agent
    agent = Agent(
        model=agent_config.model_id,
        system_prompt=system_prompt,
        deps_type=AgentDeps,
        model_settings=get_anthropic_model_settings(),
    )

    # Register tools with bypass mode context
    # ... tool registration

    return agent
```

### 4. Pass Through Tool Context

```python
# agent/wrapper.py
class ToolExecutionContext:
    """Context passed to tool execution."""

    def __init__(
        self,
        session_id: str,
        bypass_mode: bool = False,
        working_dir: str | None = None
    ):
        self.session_id = session_id
        self.bypass_mode = bypass_mode
        self.working_dir = working_dir

    def should_skip_permissions(self) -> bool:
        """Check if permission checks should be skipped."""
        return self.bypass_mode

# Use in tool wrappers
async def execute_tool_with_context(
    tool_name: str,
    params: dict,
    context: ToolExecutionContext
) -> str:
    """Execute tool with bypass mode awareness."""

    if context.bypass_mode:
        logger.warning(
            f"Executing {tool_name} in BYPASS MODE",
            extra={"session_id": context.session_id}
        )

    # Tool execution logic...
    # Check permissions unless bypassed
    if not context.should_skip_permissions():
        # Check permissions
        if not check_permissions(tool_name, params):
            raise PermissionError(f"Permission denied for {tool_name}")

    # Execute tool
    return await tool.execute(params)
```

</example-implementation>

## Security Considerations

<security>
1. **Audit Logging**: Log ALL bypass mode operations with:
   - Session ID
   - User/client identifier
   - Command/operation executed
   - Timestamp
   - Success/failure status

2. **Warnings**: Clearly warn users that bypass mode is dangerous:
   - Show red text in TUI status line
   - Include warning in system prompt
   - Log warning on every tool execution

3. **Default Disabled**: Bypass mode MUST default to False
   - Never auto-enable
   - Require explicit user action (shift+tab in TUI)

4. **No Persistence**: Don't persist bypass mode across sessions
   - Each new session starts with bypass_mode=False
   - User must explicitly enable for each session

5. **Rate Limiting**: Consider adding rate limits in bypass mode to prevent abuse

6. **Command History**: Track what was executed in bypass mode for security audits
</security>

## Testing Strategy

<testing>
1. **Unit Tests**:
   - Test PermissionChecker with bypass_mode=True/False
   - Test session creation with bypass_mode flag
   - Test tool execution with/without bypass mode

2. **Integration Tests**:
   - Create session with bypass_mode=True
   - Execute restricted bash command (should succeed)
   - Execute file write outside allowed patterns (should succeed)
   - Verify all operations logged

3. **Manual Testing**:
   - Start TUI, cycle to bypass mode (shift+tab twice)
   - Execute normally restricted command: `rm -rf /tmp/test`
   - Verify it executes without permission prompt
   - Check logs show bypass mode warnings

4. **Security Tests**:
   - Verify bypass_mode defaults to False
   - Verify new sessions don't inherit bypass mode
   - Verify audit logs capture bypass operations
</testing>

## Acceptance Criteria

<criteria>
- [ ] Session model includes bypass_mode field (defaults to False)
- [ ] Session creation endpoint accepts bypass_mode parameter
- [ ] PermissionChecker utility respects bypass mode
- [ ] Tool execution skips permission checks when bypass_mode=True
- [ ] All bypass mode operations are logged with warnings
- [ ] TUI can pass bypass_mode flag to backend on session creation
- [ ] System prompt includes bypass mode warning when enabled
- [ ] Tests verify bypass mode behavior for bash/edit/write tools
- [ ] Audit logs capture session_id, tool, operation for all bypass executions
- [ ] Documentation clearly explains security implications
</criteria>

## Migration Path

<migration>
1. **Phase 1** (Backend Foundation):
   - Add bypass_mode to Session model
   - Implement PermissionChecker utility
   - Add logging infrastructure

2. **Phase 2** (Tool Integration):
   - Update agent creation to accept bypass_mode
   - Pass bypass_mode through tool context
   - Modify tool wrappers to respect bypass mode

3. **Phase 3** (TUI Integration):
   - Update TUI session creation to send bypass_mode
   - Verify mode indicator matches backend state
   - Add confirmation dialog before enabling bypass mode

4. **Phase 4** (Testing & Documentation):
   - Write comprehensive tests
   - Document security implications
   - Add examples to README
</migration>

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
2. Run `pytest tests/` to ensure all tests pass
3. Manually test bypass mode in TUI with restricted commands
4. Review audit logs to confirm bypass operations are logged
5. Update CHANGELOG.md with bypass mode feature
6. Rename this file from `20-bypass-mode-backend.md` to `20-bypass-mode-backend.complete.md`
</completion>

## Related Issues

- TUI bypass mode (UI-only): /Users/williamcory/agent/tui/main.go lines 68, 948-950
- Reference implementation: /Users/williamcory/agent-bak-bak/tool/tool.go
- Permission config: /Users/williamcory/agent/config/permissions_config.py
- Session management: /Users/williamcory/agent/core/sessions.py
- OpenCode permission system: /Users/williamcory/agent-bak-bak/issues/04-permission-system.md
