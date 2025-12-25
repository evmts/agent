---
name: zig
description: Zig development standards for Plue. Use when working with Zig code in server, core, or build system.
---

# Zig Development

## Critical: Use the Zig MCP Server

Zig has frequent breaking changes between versions. LLM training data is often outdated, causing agents to generate incorrect code for:

- **JSON APIs** (`std.json`) - completely redesigned multiple times
- **ArrayList/ArrayHashMap** - API changes in append, put, iterator methods
- **Reader/Writer interfaces** - `anytype` patterns changed
- **Memory allocation** - allocator interface updates
- **Build system** - `build.zig` API changes frequently

### Solution: zig-docs MCP Server

The `zig-docs` MCP server provides accurate, up-to-date documentation:

```bash
# Search std library
mcp__zig-docs__search_std_lib("ArrayList")

# Get specific item docs
mcp__zig-docs__get_std_lib_item("std.ArrayList")

# List builtin functions
mcp__zig-docs__list_builtin_functions()

# Get builtin docs
mcp__zig-docs__get_builtin_function("@addWithOverflow")
```

**Always use the MCP server** before writing Zig code that uses std library APIs.

## Build Commands

```bash
zig build              # Build all
zig build run          # Start dev environment
zig build test         # Run all tests
zig build test:zig     # Zig tests only
```

## Project Structure

| Component | Location |
|-----------|----------|
| API Server | `server/` |
| Build Config | `build.zig` |

## Common Pitfalls

### JSON (std.json)

```zig
// WRONG - old API
const parsed = try std.json.parse(T, data, .{});

// CORRECT - use MCP to verify current API
const parsed = try std.json.parseFromSlice(T, allocator, data, .{});
```

### ArrayList

```zig
// WRONG - old API
try list.append(item);

// CORRECT - may need allocator parameter
try list.append(allocator, item);
```

### Error Handling

```zig
// Always handle errors explicitly
const result = doSomething() catch |err| {
    log.err("Failed: {}", .{err});
    return err;
};
```

## Memory Management

- Track ownership explicitly
- Use `defer` for cleanup
- Prefer arena allocators for request-scoped memory
- Document allocator expectations in function signatures

## Testing

```zig
test "example test" {
    const allocator = std.testing.allocator;
    // allocator detects leaks automatically
}
```

## Related Skills

- `server` - Zig API server details
- `database` - DAOs written in Zig
