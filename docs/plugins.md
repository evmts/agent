# Plugin System

The plugin system provides a Vite/Rollup-style middleware architecture for customizing agent behavior. Plugins intercept the agent loop at various lifecycle points, allowing you to log, modify, or even short-circuit tool execution.

## Quick Start

1. Enable the plugin feature:
   ```bash
   # Via API
   curl -X POST http://localhost:8000/feature/plugins/enable
   ```

2. Create a plugin file in `~/.agent/plugins/`:
   ```bash
   mkdir -p ~/.agent/plugins
   cat > ~/.agent/plugins/logger.py << 'EOF'
   """Logs all tool calls."""
   __plugin__ = {"api": "1.0", "name": "logger"}

   @on_begin
   async def start(ctx):
       print(f"[logger] Request started: {ctx.session_id}")

   @on_tool_call
   async def log_tool(ctx, call):
       print(f"[logger] Tool: {call.tool_name}")
       return None  # Don't modify

   @on_done
   async def end(ctx):
       print(f"[logger] Request completed")
   EOF
   ```

3. Configure your session to use the plugin:
   ```bash
   # Create session with plugins
   curl -X POST http://localhost:8000/session \
     -H "Content-Type: application/json" \
     -d '{"plugins": ["logger"]}'
   ```

4. Or use the `/plugin` command to create plugins interactively:
   ```
   /plugin
   ```

## How It Works

Plugins form a **pipeline** that executes at specific hook points in the agent loop:

```
┌──────────────────────────────────────────────────────────────────────┐
│ Agent Request Lifecycle                                              │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐                                                     │
│  │ on_begin    │ → Plugin1 → Plugin2 → Plugin3...                    │
│  └─────────────┘                                                     │
│         ↓                                                            │
│  ┌─────────────────────────────────────────────────────┐             │
│  │ Agent processes message                             │             │
│  │                                                     │             │
│  │   Tool Call                                         │             │
│  │       ↓                                             │             │
│  │   ┌──────────────┐                                  │             │
│  │   │ on_tool_call │ → P1 → P2 → P3... (can modify)   │             │
│  │   └──────────────┘                                  │             │
│  │       ↓                                             │             │
│  │   ┌─────────────────┐                               │             │
│  │   │ on_resolve_tool │ → First to return wins        │             │
│  │   └─────────────────┘                               │             │
│  │       ↓                                             │             │
│  │   [Tool Executes]                                   │             │
│  │       ↓                                             │             │
│  │   ┌────────────────┐                                │             │
│  │   │ on_tool_result │ → P1 → P2 → P3... (transform)  │             │
│  │   └────────────────┘                                │             │
│  │                                                     │             │
│  └─────────────────────────────────────────────────────┘             │
│         ↓                                                            │
│  ┌─────────────┐                                                     │
│  │ on_final    │ → Plugin1 → Plugin2 → ... (transform text)          │
│  └─────────────┘                                                     │
│         ↓                                                            │
│  ┌─────────────┐                                                     │
│  │ on_done     │ → Plugin1 → Plugin2 → ... (cleanup)                 │
│  └─────────────┘                                                     │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Key behaviors:**
- Plugins execute in the order they're listed in the session config
- Most hooks chain transformations through all plugins
- `on_resolve_tool` short-circuits: first plugin to return a result wins
- Plugin errors are logged but don't crash the pipeline

## Plugin File Format

### Basic Structure

```python
"""Description of what this plugin does."""

# Plugin metadata (optional but recommended)
__plugin__ = {
    "api": "1.0",        # API version (required for compatibility)
    "name": "my_plugin"  # Plugin name (defaults to filename)
}

# Hook functions - use any combination of these
@on_begin
async def init(ctx):
    """Called once when request starts."""
    ctx.state["data"] = []

@on_tool_call
async def before_tool(ctx, call):
    """Called before each tool executes."""
    return None  # Return modified ToolCall or None

@on_resolve_tool
async def intercept_tool(ctx, call):
    """Return ToolResult to skip default execution."""
    return None  # Return ToolResult or None

@on_tool_result
async def after_tool(ctx, call, result):
    """Called after tool executes."""
    return None  # Return modified ToolResult or None

@on_final
async def transform(ctx, text):
    """Called before final response."""
    return text  # Return modified text or None

@on_done
async def cleanup(ctx):
    """Called when request completes."""
    pass
```

### Decorators Available

The following decorators are automatically injected into plugin files:

| Decorator | Description |
|-----------|-------------|
| `@on_begin` | Request initialization |
| `@on_tool_call` | Before tool execution |
| `@on_resolve_tool` | Custom tool execution |
| `@on_tool_result` | After tool execution |
| `@on_final` | Transform final response |
| `@on_done` | Request cleanup |

### Models Available

These models are also injected automatically:

```python
@dataclass
class PluginContext:
    session_id: str          # Current session ID
    working_dir: str         # Working directory
    user_text: str           # User's message
    state: dict[str, Any]    # Mutable state (shared across hooks)
    memory: list[dict]       # Context injection (future use)

@dataclass
class ToolCall:
    tool_name: str           # Name of the tool
    tool_call_id: str        # Unique call ID
    input: dict[str, Any]    # Tool arguments

@dataclass
class ToolResult:
    tool_call_id: str        # Matching call ID
    tool_name: str           # Name of the tool
    output: str              # Tool output
    success: bool = True     # Whether tool succeeded
    error: str | None = None # Error message if failed
```

## Hooks Reference

### on_begin

Called at the start of each request. Use this to initialize plugin state.

```python
@on_begin
async def init(ctx):
    ctx.state["request_start"] = time.time()
    ctx.state["tools_called"] = 0
```

**Parameters:**
- `ctx`: PluginContext

**Returns:** None

### on_tool_call

Called before each tool executes. Can modify or log the tool call.

```python
@on_tool_call
async def log_tool(ctx, call):
    print(f"Calling {call.tool_name} with {call.input}")
    return None  # Don't modify
```

```python
@on_tool_call
async def modify_tool(ctx, call):
    if call.tool_name == "shell":
        # Add timeout to all shell commands
        new_input = {**call.input, "timeout": 30}
        return ToolCall(
            tool_name=call.tool_name,
            tool_call_id=call.tool_call_id,
            input=new_input,
        )
    return None
```

**Parameters:**
- `ctx`: PluginContext
- `call`: ToolCall

**Returns:** `ToolCall` (modified) or `None` (unchanged)

### on_resolve_tool

Can intercept tool execution entirely. First plugin to return a result wins.

```python
@on_resolve_tool
async def mock_dangerous(ctx, call):
    if call.tool_name == "shell" and "rm -rf" in call.input.get("cmd", ""):
        return ToolResult(
            tool_call_id=call.tool_call_id,
            tool_name=call.tool_name,
            output="Command blocked by security plugin",
            success=False,
        )
    return None  # Let tool execute normally
```

**Parameters:**
- `ctx`: PluginContext
- `call`: ToolCall

**Returns:** `ToolResult` (intercept) or `None` (continue to next plugin/default execution)

### on_tool_result

Called after each tool executes. Can transform the result.

```python
@on_tool_result
async def truncate_output(ctx, call, result):
    if len(result.output) > 1000:
        return ToolResult(
            tool_call_id=result.tool_call_id,
            tool_name=result.tool_name,
            output=result.output[:1000] + "\n... (truncated)",
            success=result.success,
        )
    return None
```

**Parameters:**
- `ctx`: PluginContext
- `call`: ToolCall
- `result`: ToolResult

**Returns:** `ToolResult` (modified) or `None` (unchanged)

### on_final

Called before the final response is returned. Can transform the text.

```python
@on_final
async def add_signature(ctx, text):
    return f"{text}\n\n---\nPowered by MyPlugin"
```

**Parameters:**
- `ctx`: PluginContext
- `text`: str

**Returns:** `str` (modified) or `None` (unchanged)

### on_done

Called when the request completes. Use for cleanup.

```python
@on_done
async def log_stats(ctx):
    duration = time.time() - ctx.state.get("request_start", 0)
    print(f"Request took {duration:.2f}s")
```

**Parameters:**
- `ctx`: PluginContext

**Returns:** None

## API Endpoints

### GET `/plugin/list`

Lists all available plugins.

**Response:**
```json
{
  "plugins": [
    {
      "name": "logger",
      "hooks": ["on_begin", "on_tool_call", "on_done"],
      "metadata": {"api": "1.0", "name": "logger"},
      "error": null
    }
  ],
  "feature_enabled": true
}
```

### GET `/plugin/{name}`

Gets detailed information about a specific plugin.

**Response:**
```json
{
  "name": "logger",
  "path": "/Users/user/.agent/plugins/logger.py",
  "hooks": ["on_begin", "on_tool_call", "on_done"],
  "metadata": {"api": "1.0", "name": "logger"},
  "content": "\"\"\"Logs all tool calls.\"\"\"..."
}
```

### POST `/plugin/save`

Saves a new plugin or updates an existing one.

**Request:**
```json
{
  "name": "my_plugin",
  "content": "__plugin__ = {...}\n\n@on_begin\nasync def init(ctx): ..."
}
```

**Response:**
```json
{
  "name": "my_plugin",
  "path": "/Users/user/.agent/plugins/my_plugin.py"
}
```

### DELETE `/plugin/{name}`

Deletes a plugin.

**Response:**
```json
{
  "deleted": "my_plugin"
}
```

### POST `/plugin/{name}/reload`

Force reloads a plugin from disk.

**Response:**
```json
{
  "name": "logger",
  "hooks": ["on_begin", "on_tool_call", "on_done"],
  "metadata": {"api": "1.0", "name": "logger"}
}
```

### POST `/plugin/validate`

Validates plugin code without saving.

**Request:**
```json
{
  "name": "test_plugin",
  "content": "@on_begin\nasync def init(ctx): pass"
}
```

**Response (valid):**
```json
{
  "name": "test_plugin",
  "hooks": ["on_begin"],
  "metadata": {"api": "1.0", "name": "test_plugin"}
}
```

**Response (invalid):**
```json
{
  "detail": "Invalid plugin code: SyntaxError..."
}
```

## Python API

```python
from plugins import (
    PluginPipeline,
    plugin_registry,
    load_plugin_from_file,
    save_plugin,
    list_plugins,
    delete_plugin,
)
from plugins.models import PluginContext, ToolCall, ToolResult

# Discover available plugins
available = plugin_registry.discover()  # ['logger', 'footer']

# Load plugins
plugin = plugin_registry.load("logger")

# Load multiple plugins in order
plugins = plugin_registry.load_many(["logger", "footer"])

# Create pipeline
pipeline = PluginPipeline(plugins)

# Execute hooks
ctx = PluginContext(
    session_id="ses_123",
    working_dir="/path/to/project",
    user_text="Hello",
)

await pipeline.on_begin(ctx)

call = ToolCall(tool_name="shell", tool_call_id="1", input={"cmd": "ls"})
call = await pipeline.on_tool_call(ctx, call)

# Check if any plugin wants to resolve the tool
resolved = await pipeline.on_resolve_tool(ctx, call)
if resolved:
    result = resolved
else:
    result = await execute_tool(call)  # Default execution

result = await pipeline.on_tool_result(ctx, call, result)

final_text = await pipeline.on_final(ctx, "Response text")

await pipeline.on_done(ctx)

# Storage operations
save_plugin("my_plugin", plugin_source_code)
delete_plugin("my_plugin")
```

## Example Plugins

### Logger Plugin

Logs all tool calls and results for debugging.

```python
"""Logs all tool calls and results."""
__plugin__ = {"api": "1.0", "name": "logger"}

import logging
logger = logging.getLogger("plugin.logger")

@on_begin
async def log_start(ctx):
    logger.info(f"Request started: {ctx.session_id}")
    ctx.state["tool_count"] = 0

@on_tool_call
async def log_tool(ctx, call):
    ctx.state["tool_count"] += 1
    logger.info(f"Tool #{ctx.state['tool_count']}: {call.tool_name}")
    return None

@on_done
async def log_end(ctx):
    logger.info(f"Request completed: {ctx.state['tool_count']} tools called")
```

### Response Footer Plugin

Adds session information to every response.

```python
"""Adds a footer to responses."""
__plugin__ = {"api": "1.0", "name": "footer"}

@on_begin
async def init(ctx):
    ctx.state["tools_used"] = []

@on_tool_call
async def track_tool(ctx, call):
    if call.tool_name not in ctx.state["tools_used"]:
        ctx.state["tools_used"].append(call.tool_name)
    return None

@on_final
async def add_footer(ctx, text):
    tools = ", ".join(ctx.state["tools_used"]) or "none"
    return f"{text}\n\n---\nSession: {ctx.session_id}\nTools: {tools}"
```

### Shell Blocker Plugin

Blocks dangerous shell commands.

```python
"""Blocks dangerous shell commands."""
__plugin__ = {"api": "1.0", "name": "shell_blocker"}

BLOCKED = ["rm -rf /", "sudo rm", ":(){ :|:& };:"]

@on_tool_call
async def check_shell(ctx, call):
    if call.tool_name == "shell":
        cmd = call.input.get("cmd", "")
        for pattern in BLOCKED:
            if pattern in cmd:
                return ToolCall(
                    tool_name=call.tool_name,
                    tool_call_id=call.tool_call_id,
                    input={"cmd": "echo 'Blocked by security policy'"},
                )
    return None
```

### Tool Mocker Plugin

Mocks specific tools for testing.

```python
"""Mocks tools for testing."""
__plugin__ = {"api": "1.0", "name": "mocker"}

MOCKS = {
    "shell": {"cmd": "echo test"}: "mocked shell output",
}

@on_resolve_tool
async def mock_tool(ctx, call):
    mock_key = (call.tool_name, tuple(sorted(call.input.items())))
    if mock_key in MOCKS:
        return ToolResult(
            tool_call_id=call.tool_call_id,
            tool_name=call.tool_name,
            output=MOCKS[mock_key],
        )
    return None
```

## Configuration

### Feature Flag

The plugin system must be enabled via feature flag:

```python
# config/features.py
"plugins": FeatureFlag(
    name="plugins",
    description="Enable plugin system for agent customization",
    stage=FeatureStage.EXPERIMENTAL,
    default=False,
)
```

Enable via API:
```bash
curl -X POST http://localhost:8000/feature/plugins/enable
```

### Session Configuration

Plugins are configured per-session:

```python
# Session model includes:
class Session:
    plugins: list[str] = []  # Plugin names to activate
```

Configure via API:
```bash
# Create session with plugins
curl -X POST http://localhost:8000/session \
  -H "Content-Type: application/json" \
  -d '{"plugins": ["logger", "footer"]}'

# Update session plugins
curl -X PATCH http://localhost:8000/session/{id} \
  -H "Content-Type: application/json" \
  -d '{"plugins": ["logger"]}'
```

## Best Practices

1. **Keep plugins focused**: Each plugin should do one thing well
2. **Use async/await**: All hooks should be async functions
3. **Return None by default**: Only return values when modifying
4. **Handle errors gracefully**: Plugin errors shouldn't crash the agent
5. **Use ctx.state for data**: Share data between hooks via state dict
6. **Log important events**: Use Python logging for observability
7. **Version your plugins**: Include API version in `__plugin__`
8. **Test thoroughly**: Write tests for your plugin logic

## Troubleshooting

### Plugin Not Loading

- Ensure file is in `~/.agent/plugins/`
- Check file has `.py` extension
- Verify syntax is valid Python
- Check API version is compatible (1.x)

### Hooks Not Running

- Confirm plugins feature is enabled
- Check session has the plugin configured
- Verify hook function is decorated correctly
- Check plugin loaded without errors: `GET /plugin/{name}`

### Plugin Errors

- Check server logs for error messages
- Plugin errors are logged but don't stop execution
- Use `POST /plugin/validate` to check code before saving

### State Not Persisting

- `ctx.state` is per-request only
- State is not persisted between requests
- Use external storage for persistent data
