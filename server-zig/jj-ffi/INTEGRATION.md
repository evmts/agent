# JJ-FFI Integration Guide for Zig

This guide explains how to integrate the jj-ffi library into your Zig project.

## Overview

The jj-ffi library provides a C-compatible FFI wrapper around jj-lib, allowing Zig code to interact with Jujutsu repositories. It exposes all core functionality including workspace management, commit operations, and file access.

## Building the Library

### Prerequisites

- Rust toolchain (cargo, rustc)
- Zig 0.13.0 or later
- Git (for jj-lib dependency)

### Build Steps

```bash
cd jj-ffi
cargo build --release
```

This produces:
- `target/release/libjj_ffi.a` (static library)
- `target/release/libjj_ffi.dylib` (macOS dynamic library)

## Integration Methods

### Method 1: Using build.zig

Add to your `build.zig`:

```zig
// Build jj-ffi Rust library
const jj_ffi_build = b.addSystemCommand(&.{
    "cargo",
    "build",
    "--release",
    "--manifest-path",
    "jj-ffi/Cargo.toml",
});

// Link to your executable
exe.step.dependOn(&jj_ffi_build.step);
exe.addIncludePath(b.path("jj-ffi"));
exe.addLibraryPath(b.path("jj-ffi/target/release"));
exe.linkSystemLibrary("jj_ffi");
exe.linkLibC();

// Platform-specific system libraries
if (target.result.os.tag == .macos) {
    exe.linkFramework("Security");
    exe.linkFramework("CoreFoundation");
    exe.linkSystemLibrary("resolv");
} else if (target.result.os.tag == .linux) {
    exe.linkSystemLibrary("pthread");
    exe.linkSystemLibrary("dl");
    exe.linkSystemLibrary("m");
}
```

### Method 2: Manual Compilation

```bash
# Build the library
cd jj-ffi
cargo build --release

# Compile your Zig program
zig build-exe your_program.zig \
    -I./jj-ffi \
    -L./jj-ffi/target/release \
    -ljj_ffi \
    -lc \
    -framework Security \
    -framework CoreFoundation \
    -lresolv
```

## Using the API in Zig

### Basic Setup

```zig
const std = @import("std");

const c = @cImport({
    @cInclude("jj_ffi.h");
});

pub fn main() !void {
    // Your code here
}
```

### Opening a Workspace

```zig
const workspace_path = "/path/to/repo";

// Check if it's a jj workspace
if (!c.jj_is_jj_workspace(workspace_path.ptr)) {
    return error.NotJjWorkspace;
}

// Open the workspace
const result = c.jj_workspace_open(workspace_path.ptr);
defer {
    if (result.success) {
        c.jj_workspace_free(result.workspace);
    }
    if (result.error_message != null) {
        c.jj_string_free(result.error_message);
    }
}

if (!result.success) {
    const err = std.mem.span(result.error_message);
    std.debug.print("Error: {s}\n", .{err});
    return error.WorkspaceOpenFailed;
}

const workspace = result.workspace;
```

### Initializing a New Workspace

```zig
// Init a new jj workspace
const result = c.jj_workspace_init(path.ptr);

// Or init from existing git repo
const result = c.jj_workspace_init_colocated(path.ptr);
```

### Working with Commits

```zig
// Get a specific commit
const commit_result = c.jj_get_commit(workspace, commit_id.ptr);
defer {
    if (commit_result.success and commit_result.commit != null) {
        c.jj_commit_info_free(commit_result.commit);
    }
    if (commit_result.error_message != null) {
        c.jj_string_free(commit_result.error_message);
    }
}

if (commit_result.success) {
    const commit = commit_result.commit.*;
    const change_id = std.mem.span(commit.change_id);
    const desc = std.mem.span(commit.description);
    const author = std.mem.span(commit.author_name);

    std.debug.print("Change: {s}\n", .{change_id});
    std.debug.print("Author: {s}\n", .{author});
    std.debug.print("Description: {s}\n", .{desc});
}
```

### Listing Changes

```zig
// List up to 10 recent changes
const changes = c.jj_list_changes(workspace, 10, null);
defer {
    if (changes.success and changes.commits != null) {
        c.jj_commit_array_free(changes.commits, changes.len);
    }
    if (changes.error_message != null) {
        c.jj_string_free(changes.error_message);
    }
}

if (changes.success) {
    const commits = changes.commits[0..changes.len];
    for (commits) |commit_ptr| {
        const commit = commit_ptr.*;
        const change_id = std.mem.span(commit.change_id);
        std.debug.print("Change: {s}\n", .{change_id});
    }
}
```

### Working with Bookmarks

```zig
const bookmarks = c.jj_list_bookmarks(workspace);
defer {
    if (bookmarks.success and bookmarks.bookmarks != null) {
        c.jj_bookmark_array_free(bookmarks.bookmarks, bookmarks.len);
    }
    if (bookmarks.error_message != null) {
        c.jj_string_free(bookmarks.error_message);
    }
}

if (bookmarks.success) {
    const bookmark_list = bookmarks.bookmarks[0..bookmarks.len];
    for (bookmark_list) |bookmark| {
        const name = std.mem.span(bookmark.name);
        if (bookmark.target_id != null) {
            const target = std.mem.span(bookmark.target_id);
            std.debug.print("{s} -> {s}\n", .{ name, target });
        }
    }
}
```

### Reading Files

```zig
// List files at a revision
const files = c.jj_list_files(workspace, revision.ptr);
defer {
    if (files.success and files.strings != null) {
        c.jj_string_array_free(files.strings, files.len);
    }
    if (files.error_message != null) {
        c.jj_string_free(files.error_message);
    }
}

// Get file content
const content = c.jj_get_file_content(workspace, revision.ptr, file_path.ptr);
defer {
    if (content.string != null) {
        c.jj_string_free(content.string);
    }
    if (content.error_message != null) {
        c.jj_string_free(content.error_message);
    }
}

if (content.success and content.string != null) {
    const text = std.mem.span(content.string);
    std.debug.print("{s}\n", .{text});
}
```

### Getting Current Operation

```zig
const op = c.jj_get_current_operation(workspace);
defer {
    if (op.success and op.operation != null) {
        c.jj_operation_info_free(op.operation);
    }
    if (op.error_message != null) {
        c.jj_string_free(op.error_message);
    }
}

if (op.success) {
    const operation = op.operation.*;
    const id = std.mem.span(operation.id);
    const desc = std.mem.span(operation.description);
    std.debug.print("Operation: {s}\n", .{id});
    std.debug.print("Description: {s}\n", .{desc});
    std.debug.print("Timestamp: {d}\n", .{operation.timestamp});
}
```

## Memory Management

**CRITICAL**: All pointers returned by the FFI must be explicitly freed.

### Result Pattern

Every FFI function that returns data follows this pattern:

```zig
const result = c.some_jj_function(...);
defer {
    // Free the main data if success
    if (result.success and result.data != null) {
        c.appropriate_free_function(result.data);
    }
    // Always free error message if present
    if (result.error_message != null) {
        c.jj_string_free(result.error_message);
    }
}
```

### Free Functions

| Data Type | Free Function |
|-----------|---------------|
| `JjWorkspace*` | `jj_workspace_free()` |
| `JjCommitInfo*` | `jj_commit_info_free()` |
| `JjBookmarkInfo*` | `jj_bookmark_info_free()` |
| `JjOperationInfo*` | `jj_operation_info_free()` |
| `char*` | `jj_string_free()` |
| `char**` array | `jj_string_array_free(ptr, len)` |
| `JjBookmarkInfo[]` | `jj_bookmark_array_free(ptr, len)` |
| `JjCommitInfo*[]` | `jj_commit_array_free(ptr, len)` |

## Error Handling

All functions return result structures with:
- `success`: Boolean indicating success/failure
- `error_message`: Null-terminated string (must be freed) if `success == false`

```zig
if (!result.success) {
    const err = std.mem.span(result.error_message);
    std.log.err("Operation failed: {s}", .{err});
    return error.OperationFailed;
}
```

## Thread Safety

The jj-ffi library is **not thread-safe**. Each workspace handle should be used from a single thread. If you need concurrent access:

1. Open separate workspace handles per thread
2. Use external synchronization (mutex/lock)
3. Ensure each thread owns its workspace handle lifecycle

## Performance Considerations

1. **Workspace Loading**: Opening a workspace loads the repository state. Reuse workspace handles when possible.

2. **Large File Operations**: File content is loaded entirely into memory. For large files, consider:
   - Checking file size first
   - Streaming alternatives in your application layer

3. **Commit Traversal**: `jj_list_changes()` performs BFS traversal. Use the `limit` parameter to control memory usage.

4. **String Copying**: All strings are copied to the Zig side. For frequently accessed data, cache the results.

## Platform Notes

### macOS

Required frameworks:
- `Security` (for cryptographic operations)
- `CoreFoundation` (for system integration)
- `resolv` (for DNS resolution)

### Linux

Required libraries:
- `pthread` (POSIX threads)
- `dl` (dynamic linking)
- `m` (math library)

### Windows

Not yet tested. Expected requirements:
- `ws2_32` (Windows Sockets)
- `userenv` (User environment)
- `bcrypt` (Cryptographic primitives)

## Troubleshooting

### Link Errors

If you get undefined symbol errors:
1. Ensure jj-ffi is built: `cargo build --release`
2. Check library path: `-L./jj-ffi/target/release`
3. Verify system libraries are linked (Security, CoreFoundation on macOS)

### Runtime Errors

**"Workspace is null"**: Check that workspace was successfully opened and not freed.

**"Invalid UTF-8"**: Ensure all strings passed to FFI are valid UTF-8 and null-terminated.

**"Failed to load workspace"**: Path may not contain a jj workspace. Use `jj_is_jj_workspace()` first.

### Memory Leaks

Use Valgrind or similar tools to detect leaks:
```bash
valgrind --leak-check=full ./your_program
```

Ensure all `defer` blocks properly free resources.

## Example Code

See `example.zig` for a complete working example that demonstrates:
- Opening a workspace
- Listing bookmarks
- Traversing commit history
- Reading file contents
- Proper memory management

Build and run:
```bash
./build_example.sh
./example /path/to/jj/workspace
```

## API Reference

See `jj_ffi.h` for complete function signatures and documentation.

Key functions:
- Workspace: `init`, `open`, `init_colocated`, `free`, `is_jj_workspace`
- Commits: `get_commit`, `list_changes`
- Bookmarks: `list_bookmarks`
- Files: `list_files`, `get_file_content`
- Operations: `get_current_operation`

## Version Compatibility

This FFI wrapper is built against jj-lib v0.36.0. API stability:
- **Stable**: Core workspace and commit operations
- **Beta**: Bookmark operations (jj's branch equivalent)
- **Experimental**: File content reading with conflict resolution

Check the jj-lib changelog when upgrading for breaking changes.
