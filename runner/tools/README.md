# Runner Tools

Sandboxed tool implementations for AI agent execution.

## Overview

Tools provide agents with capabilities to interact with the /workspace filesystem
and execute shell commands. All tools enforce strict path validation to prevent
traversal attacks and maintain containment within the workspace.

## Security Model

```
Tool Request
    |
    v
┌──────────────────────────┐
│  Input Validation        │
│  - Type checking         │
│  - Required params       │
└──────────┬───────────────┘
           |
           v
┌──────────────────────────┐
│  Path Normalization      │
│  - os.path.realpath()    │
│  - Resolve symlinks      │
│  - Resolve .. and .      │
└──────────┬───────────────┘
           |
           v
┌──────────────────────────┐
│  Boundary Check          │
│  - startswith(/workspace)│
│  - Reject traversal      │
└──────────┬───────────────┘
           |
           v
┌──────────────────────────┐
│  Execute Operation       │
│  - Read/write file       │
│  - List directory        │
│  - Run command           │
└──────────┬───────────────┘
           |
           v
    Return Result
```

## Available Tools

### read_file

Read contents of a file within workspace.

```python
{
  "path": "src/main.py",          # Required, relative to /workspace
  "start_line": 10,                # Optional, 1-indexed
  "end_line": 50                   # Optional, inclusive
}
```

Features:
- Line range support for large files
- UTF-8 decoding with error replacement
- 100KB truncation for very large files
- Path traversal protection

### write_file

Create or modify files within workspace.

```python
{
  "path": "output.txt",            # Required, relative to /workspace
  "content": "Hello, world!",      # Required
  "append": false                  # Optional, default: false
}
```

Features:
- Automatic parent directory creation
- Append or overwrite mode
- Path traversal protection
- Creates files atomically

### list_files

List files and directories within workspace.

```python
{
  "path": "src",                   # Optional, default: "."
  "recursive": true,               # Optional, default: false
  "include_hidden": false,         # Optional, default: false
  "max_results": 200               # Optional, default: 200
}
```

Features:
- Glob pattern support (*.py, **/*.ts)
- Recursive directory traversal
- Hidden file filtering
- Result truncation

### grep

Search for patterns in files.

```python
{
  "pattern": "TODO",               # Required, regex pattern
  "path": ".",                     # Optional, default: "."
  "include": "*.py",               # Optional, file pattern
  "ignore_case": false,            # Optional, default: false
  "max_results": 100               # Optional, default: 100
}
```

Features:
- Recursive search with grep -rn
- File pattern filtering
- Case-insensitive search
- Line number reporting
- Result truncation

### shell

Execute shell commands within workspace.

```python
{
  "command": "npm test",           # Required
  "working_directory": ".",        # Optional, relative to /workspace
  "timeout": 60                    # Optional, seconds, default: 60
}
```

Features:
- Stdout and stderr capture
- Exit code reporting
- Working directory control
- Timeout protection
- Path traversal protection on working_directory

Note: Shell injection is intentional design. Security boundary is the
gVisor sandbox and filesystem restrictions, not command parsing.

## Tool Definitions

Each tool exports:

| Export              | Type   | Purpose                          |
|---------------------|--------|----------------------------------|
| TOOL_DEFINITION     | dict   | Anthropic tool schema            |
| tool_function       | func   | Implementation (input -> output) |

Example:

```python
GREP_DEFINITION = {
    "name": "grep",
    "description": "Search for patterns in files...",
    "input_schema": {
        "type": "object",
        "properties": {...},
        "required": ["pattern"]
    }
}

def grep_tool(input_data: Dict[str, Any]) -> str:
    # Implementation
    pass
```

## Path Validation Pattern

All tools use this security pattern:

```python
# 1. Construct full path
full_path = os.path.realpath(os.path.join("/workspace", user_path))

# 2. Verify containment
if not full_path.startswith("/workspace/"):
    return "Error: path traversal not allowed"

# 3. Perform operation
with open(full_path, "r") as f:
    return f.read()
```

This prevents:
- Absolute path escapes: /etc/passwd
- Relative traversal: ../../etc/passwd
- Symlink escapes: link-to-etc -> /etc
- Null byte injection: test\x00file

## Error Handling

All tools return string output:

```python
# Success
"File contents here..."
"Successfully wrote 42 bytes to output.txt"

# Errors
"Error: file not found: missing.txt"
"Error: path traversal not allowed"
"Error: permission denied: protected.txt"
```

Errors are returned as strings (not exceptions) to provide clear feedback
to the AI agent about what went wrong.

## Testing

See tests/test_tools.py for comprehensive security tests:

| Test Category        | Coverage                               |
|----------------------|----------------------------------------|
| Path Traversal       | Absolute, relative, symlink escapes    |
| Path Normalization   | .. resolution, trailing slashes        |
| Input Validation     | Missing params, type checking          |
| Boundary Conditions  | Empty paths, null bytes, max results   |

Run tests:

```bash
uv run pytest tests/test_tools.py -v
```
