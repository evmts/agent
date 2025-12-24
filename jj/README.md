# jj-ffi

C-compatible FFI wrapper for jj-lib that can be called from Zig.

This library provides low-level bindings to [Jujutsu](https://github.com/jj-vcs/jj) (jj), a next-generation version control system. Unlike the NAPI wrapper at `/Users/williamcory/agent/snapshot`, this uses C FFI and can be called from Zig, C, C++, or any language with C interop.

## Quick Start

```bash
# Build the library
cd jj-ffi
cargo build --release

# Test the build
./test_build.sh

# Try the example (requires a jj workspace)
./build_example.sh
./example /path/to/jj/workspace
```

## Build Artifacts

Building produces:
- `target/release/libjj_ffi.a` - Static library (~10MB)
- `target/release/libjj_ffi.dylib` (macOS) or `.so` (Linux) or `.dll` (Windows) - Dynamic library
- `jj_ffi.h` - C header file

## Usage from Zig

See `jj_ffi.h` for the complete C API.

### Example

```zig
const c = @cImport({
    @cInclude("jj_ffi.h");
});

pub fn main() !void {
    const path = "/path/to/repo";

    // Open workspace
    const result = c.jj_workspace_open(path);
    defer {
        if (result.success) {
            c.jj_workspace_free(result.workspace);
        }
        if (result.error_message != null) {
            c.jj_string_free(result.error_message);
        }
    }

    if (!result.success) {
        std.debug.print("Error: {s}\n", .{result.error_message});
        return error.WorkspaceOpenFailed;
    }

    // List bookmarks
    const bookmarks = c.jj_list_bookmarks(result.workspace);
    defer {
        if (bookmarks.success) {
            c.jj_bookmark_array_free(bookmarks.bookmarks, bookmarks.len);
        }
        if (bookmarks.error_message != null) {
            c.jj_string_free(bookmarks.error_message);
        }
    }

    // Use bookmarks...
}
```

## Memory Management

All returned strings and structures must be freed using the appropriate `jj_*_free` functions:

- `jj_workspace_free()` - Free workspace handle
- `jj_commit_info_free()` - Free commit info
- `jj_bookmark_info_free()` - Free bookmark info
- `jj_operation_info_free()` - Free operation info
- `jj_string_free()` - Free a C string
- `jj_string_array_free()` - Free an array of strings
- `jj_bookmark_array_free()` - Free an array of bookmarks
- `jj_commit_array_free()` - Free an array of commits

Always check the `success` field of result structures and free the `error_message` if it's not NULL.

## API Functions

### Workspace Management

- `jj_workspace_init(path)` - Initialize new workspace
- `jj_workspace_open(path)` - Open existing workspace
- `jj_workspace_init_colocated(path)` - Init from existing git repo
- `jj_is_jj_workspace(path)` - Check if path is jj workspace

### Repository Operations

- `jj_get_commit(workspace, commit_id)` - Get commit info
- `jj_list_bookmarks(workspace)` - List all bookmarks
- `jj_list_changes(workspace, limit, bookmark)` - List recent changes
- `jj_list_files(workspace, revision)` - List files at revision
- `jj_get_file_content(workspace, revision, path)` - Get file content
- `jj_get_current_operation(workspace)` - Get current operation

## Dependencies

- jj-lib v0.36.0
- tokio (for async runtime)
