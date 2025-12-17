# File Safety Tools - Read-Before-Write Enforcement

This module implements read-before-write enforcement to prevent blind file overwrites and race conditions.

## Architecture

### Core Components

1. **FileTimeTracker** (`file_time.py`)
   - Tracks file modification times when files are read
   - Validates files haven't been modified before writes
   - Normalizes paths and resolves symlinks for accurate tracking

2. **Session-Scoped Tracking** (`core/state.py`)
   - Each session has its own FileTimeTracker instance
   - Prevents cross-session interference
   - Automatically cleaned up when sessions end

3. **Helper Functions** (`filesystem.py`)
   - `set_current_session_id()` - Sets the active session for tracking
   - `mark_file_read()` - Records a file as read
   - `check_file_writable()` - Enforces read-before-write rules

4. **Integration Points** (`wrapper.py`)
   - Sets session context before agent execution
   - Can intercept tool calls for enforcement (optional)

## How It Works

### Reading Files

When a file is read:
1. The file's current modification time is recorded
2. The file path is normalized (absolute + symlink resolution)
3. The timestamp is stored in the session's tracker

### Writing Files

When a file is written:
1. If the file exists, check if it's been read in this session
2. If not read, raise error: "File has not been read in this session"
3. If read, verify the modification time hasn't changed
4. If changed, raise error: "File has been modified since it was last read"
5. If checks pass, allow write and update timestamp

### New Files

New files (non-existent paths) can be written without requiring a read.

## Current Implementation Status

### ✅ Completed

- FileTimeTracker class with full path normalization
- Session-scoped tracking infrastructure
- Helper functions for marking reads and checking writes
- Comprehensive test suite (20 tests, all passing)
- Context variable for session tracking
- Session ID propagation in wrapper

### ⚠️ Partial / In Progress

- **MCP Tool Interception**: The wrapper sets session context but doesn't yet intercept MCP filesystem calls
- **Custom File Tools**: Safe file operation tools exist but aren't registered with the agent yet

### 🔄 Integration Options

There are two approaches to complete the integration:

#### Option 1: Replace MCP Filesystem Server (Recommended)

Remove the MCP filesystem server and use custom tools instead:

```python
# In create_agent_with_mcp():

# Don't add filesystem MCP server
mcp_servers = [shell_server]  # Only shell, no filesystem

# Register custom tools with session dependency
@agent.tool_plain
async def read_file(path: str, session_id: str = "default") -> str:
    from .tools.filesystem import set_current_session_id, mark_file_read
    set_current_session_id(session_id)

    with open(path, 'r') as f:
        content = f.read()

    mark_file_read(path)
    return content

@agent.tool_plain
async def write_file(path: str, content: str, session_id: str = "default") -> str:
    from .tools.filesystem import set_current_session_id, check_file_writable, mark_file_read
    set_current_session_id(session_id)

    check_file_writable(path)  # Enforce safety

    with open(path, 'w') as f:
        f.write(content)

    mark_file_read(path)  # Update tracking
    return f"Successfully wrote {len(content)} bytes"
```

**Pros:**
- Full control over safety enforcement
- No dependency on external MCP server behavior
- Clear error messages
- Complete integration

**Cons:**
- Must implement all file operations ourselves
- Lose MCP server features (search_files, etc.)

#### Option 2: MCP Server Wrapper/Proxy

Create a proxy MCP server that wraps the filesystem server and adds safety checks.

**Pros:**
- Keeps all MCP filesystem features
- Transparent to agent code

**Cons:**
- More complex implementation
- Requires MCP protocol knowledge
- Harder to debug

## Usage Examples

### Direct Usage

```python
from agent.tools.file_time import FileTimeTracker
from agent.tools.filesystem import set_current_session_id, mark_file_read, check_file_writable

# Set up session
set_current_session_id("session-123")

# Read a file
with open("/path/to/file.txt") as f:
    content = f.read()
mark_file_read("/path/to/file.txt")

# Write the file (this will succeed)
check_file_writable("/path/to/file.txt")  # No error
with open("/path/to/file.txt", "w") as f:
    f.write("new content")

# Try to write without reading first
check_file_writable("/path/to/other.txt")  # Raises ValueError!
```

### With Agent Wrapper

```python
async with create_mcp_wrapper(model_id="claude-sonnet-4") as wrapper:
    # Session ID is automatically set
    async for event in wrapper.stream_async("Read and modify config.py", session_id="session-123"):
        print(event)
```

## Testing

Run the test suite:

```bash
pytest tests/test_agent/test_tools/test_file_safety.py -v
```

Test coverage:
- Path normalization (relative, absolute)
- Symlink resolution
- Session isolation
- External modification detection
- New file creation
- Edge cases (permissions, rapid cycles, etc.)

## Error Messages

The system provides clear, actionable error messages:

### File Not Read
```
ValueError: File /path/to/file.txt has not been read in this session.
You MUST use the Read tool first before writing to existing files
```

### File Modified Externally
```
ValueError: File /path/to/file.txt has been modified since it was last read.
Please use the Read tool again to get the latest contents
```

## Future Enhancements

1. **Conflict Resolution**: Provide diff when external modifications detected
2. **Auto-Retry**: Automatically re-read and retry on external modification
3. **Batch Operations**: Track multiple files in a single operation
4. **TTL for Reads**: Expire read timestamps after a configurable duration
5. **Bypass Mode**: Allow disabling safety for specific tools or sessions
6. **Audit Log**: Track all file operations for debugging

## Design Decisions

### Why Session-Scoped?

Session-scoped tracking prevents issues when multiple conversations/sessions operate on the same files simultaneously. Each session has its own timeline of file operations.

### Why Modification Time?

Using modification time (mtime) is the standard approach for detecting external changes. It's:
- Fast (no content hashing required)
- Reliable on most filesystems
- Standard in tools like Make, Git, etc.

### Why Allow New Files?

Requiring reads for new files would be overly restrictive. The agent needs to create new files freely. The safety concern is only about overwriting existing content without reading it first.

### Why Context Variables?

ContextVars are async-safe and automatically propagate through async call chains. This makes them ideal for tracking session state across tool calls.

## Related Files

- `agent/tools/file_time.py` - FileTimeTracker implementation
- `agent/tools/filesystem.py` - Helper functions and safe file operations
- `agent/tools/safe_file_ops.py` - Pre-built safe file tools (not yet integrated)
- `core/state.py` - Session state management
- `agent/wrapper.py` - Session context propagation
- `tests/test_agent/test_tools/test_file_safety.py` - Test suite
