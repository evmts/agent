# JJ-FFI Project Documentation

## Project Overview

This project provides a C-compatible Foreign Function Interface (FFI) wrapper for jj-lib, enabling Zig applications to interact with Jujutsu version control repositories. Unlike the NAPI wrapper at `/Users/williamcory/agent/snapshot`, which is designed for Node.js/Bun, this FFI wrapper uses `#[no_mangle]` extern "C" functions and can be called from any language that supports C FFI.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Zig Application                       │
│                  (your server-zig code)                      │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            │ C FFI
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                      jj-ffi (Rust)                           │
│  - C-compatible function exports (#[no_mangle])              │
│  - Memory management (Box, CString)                          │
│  - Error handling (result structures)                        │
│  - Type conversions (Rust ↔ C)                              │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            │ Native Rust calls
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                      jj-lib v0.36.0                          │
│  - Workspace management                                      │
│  - Repository operations                                     │
│  - Commit history                                            │
│  - File access                                               │
└─────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. C-Compatible ABI

**Decision**: Use `extern "C"` with `#[no_mangle]` instead of higher-level bindings.

**Rationale**:
- Maximum compatibility (works with Zig, C, C++, etc.)
- Stable ABI across Rust versions
- Predictable linking behavior
- No runtime dependencies on Rust-specific features

### 2. Static + Dynamic Library

**Decision**: Build both `staticlib` and `cdylib` crate types.

**Rationale**:
- `staticlib`: Better for distribution, single binary
- `cdylib`: Easier for development, faster iteration
- Flexibility for different deployment scenarios

### 3. Explicit Memory Management

**Decision**: Require manual deallocation with `*_free()` functions.

**Rationale**:
- C FFI has no automatic memory management
- Explicit ownership prevents double-free bugs
- Clear responsibility boundary between Rust and caller
- Familiar pattern for C/Zig developers

### 4. Result Structures

**Decision**: Return result structs with `success` + `error_message` instead of using errno or return codes.

**Rationale**:
- More descriptive error messages
- Type-safe (each function has appropriate return type)
- No global state (thread-safe error reporting)
- Easier to use from Zig with defer blocks

### 5. Null-Terminated Strings

**Decision**: Use C strings (`*mut c_char`) instead of length-prefixed slices.

**Rationale**:
- Standard C convention
- Zig has excellent C interop (std.mem.span)
- Simpler FFI boundary
- Compatible with printf-style debugging

## File Structure

```
jj-ffi/
├── Cargo.toml           # Rust package configuration
├── src/
│   └── lib.rs           # Main FFI implementation (~1000 lines)
├── jj_ffi.h             # C header file (~200 lines)
├── README.md            # Quick start guide
├── INTEGRATION.md       # Comprehensive integration guide
├── PROJECT.md           # This file
├── example.zig          # Working example demonstrating all features
├── build_example.sh     # Script to build example
└── .gitignore           # Ignore target/, Cargo.lock, etc.
```

## API Design

### Workspace Handle

```c
typedef struct JjWorkspace JjWorkspace;  // Opaque pointer
```

The workspace is an opaque handle. Callers never see the internal structure, ensuring:
- Implementation flexibility
- Safe memory management
- Clear ownership semantics

### Result Pattern

Every function follows this pattern:

```c
typedef struct {
    DataType* data;           // NULL if error
    bool success;             // true if operation succeeded
    char* error_message;      // NULL if success, must free otherwise
} DataTypeResult;
```

This enables idiomatic Zig usage:

```zig
const result = c.jj_function();
defer {
    if (result.success) c.free_data(result.data);
    if (result.error_message != null) c.jj_string_free(result.error_message);
}
```

### Data Structures

All structures are `#[repr(C)]` to ensure:
- Predictable memory layout
- No padding surprises
- ABI stability

Example:

```c
typedef struct JjCommitInfo {
    char* id;
    char* change_id;
    char* description;
    // ... more fields
    char** parent_ids;
    size_t parent_ids_len;
    bool is_empty;
} JjCommitInfo;
```

## Implementation Details

### String Handling

**Rust to C**:
```rust
let s = CString::new(rust_string).unwrap_or_default().into_raw();
```

This:
1. Converts Rust `String` to null-terminated `CString`
2. Transfers ownership to caller (`.into_raw()`)
3. Returns `*mut c_char` pointer

**Freeing**:
```rust
#[no_mangle]
pub unsafe extern "C" fn jj_string_free(s: *mut c_char) {
    if !s.is_null() {
        let _ = CString::from_raw(s);  // Drops and deallocates
    }
}
```

### Array Handling

**Rust to C**:
```rust
let vec: Vec<T> = /* ... */;
let len = vec.len();
let ptr = if len > 0 {
    Box::into_raw(vec.into_boxed_slice()) as *mut T
} else {
    std::ptr::null_mut()
};
```

Returns pointer + length, Zig creates slice:
```zig
const items = result.ptr[0..result.len];
```

**Freeing**:
```rust
#[no_mangle]
pub unsafe extern "C" fn jj_array_free(ptr: *mut T, len: usize) {
    if !ptr.is_null() {
        let _ = Box::from_raw(std::slice::from_raw_parts_mut(ptr, len));
    }
}
```

### Async Operations

jj-lib uses async I/O for file operations. We handle this by:

```rust
// Create runtime for async operations
let rt = tokio::runtime::Runtime::new()?;

// Block on async operation
let result = rt.block_on(async {
    let mut reader = store.read_file(&path, &id).await?;
    let mut buf = Vec::new();
    reader.read_to_end(&mut buf).await?;
    Ok(buf)
})?;
```

This is necessary because C FFI functions must be synchronous.

### Error Handling

**Rust Side**:
```rust
match operation() {
    Ok(value) => ResultType {
        data: Box::into_raw(Box::new(value)),
        success: true,
        error_message: std::ptr::null_mut(),
    },
    Err(e) => ResultType {
        data: std::ptr::null_mut(),
        success: false,
        error_message: CString::new(format!("{}", e)).unwrap().into_raw(),
    },
}
```

**Zig Side**:
```zig
if (!result.success) {
    const err = std.mem.span(result.error_message);
    std.log.err("Operation failed: {s}", .{err});
    return error.OperationFailed;
}
```

## Memory Safety

### Ownership Rules

1. **Workspace Handle**: Owned by caller after successful init/open
2. **Strings**: Owned by caller after FFI returns them
3. **Arrays**: Owned by caller, must free both array and elements
4. **Error Messages**: Always owned by caller if non-null

### Common Pitfalls

**❌ Double Free**:
```zig
c.jj_string_free(s);
c.jj_string_free(s);  // CRASH!
```

**✓ Correct**:
```zig
defer c.jj_string_free(s);
// Only freed once
```

**❌ Use After Free**:
```zig
c.jj_workspace_free(ws);
c.jj_list_bookmarks(ws);  // CRASH!
```

**✓ Correct**:
```zig
defer c.jj_workspace_free(ws);
// Use workspace before defer runs
```

**❌ Memory Leak**:
```zig
const result = c.jj_list_files(ws, rev);
// Forgot to free!
```

**✓ Correct**:
```zig
const result = c.jj_list_files(ws, rev);
defer {
    if (result.success) c.jj_string_array_free(result.strings, result.len);
    if (result.error_message != null) c.jj_string_free(result.error_message);
}
```

## Testing Strategy

### Unit Tests (Rust)

Test the FFI layer in isolation:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_workspace_lifecycle() {
        let path = CString::new("/tmp/test-repo").unwrap();
        let result = unsafe { jj_workspace_init(path.as_ptr()) };
        assert!(result.success);
        unsafe { jj_workspace_free(result.workspace) };
    }
}
```

### Integration Tests (Zig)

Test the Zig integration:

```zig
test "can open workspace" {
    const result = c.jj_workspace_open("/path/to/test/repo");
    defer c.jj_workspace_free(result.workspace);
    try std.testing.expect(result.success);
}
```

### Example Program

The `example.zig` serves as:
- Living documentation
- Integration test
- Smoke test for releases
- Reference implementation

## Performance Considerations

### Workspace Reuse

❌ **Inefficient**:
```zig
for (operations) |op| {
    const ws = c.jj_workspace_open(path);
    defer c.jj_workspace_free(ws.workspace);
    // Use workspace
}
```

✓ **Efficient**:
```zig
const ws = c.jj_workspace_open(path);
defer c.jj_workspace_free(ws.workspace);
for (operations) |op| {
    // Reuse workspace
}
```

### String Copying

FFI requires copying strings. For hot paths:

1. Cache frequently accessed data
2. Use commit IDs (hex strings) as keys
3. Consider building higher-level abstractions

### Large Operations

For `list_changes()` with large repos:
- Use the `limit` parameter
- Implement pagination
- Consider streaming alternatives

## Platform Support

### macOS (Tested)

Required linker flags:
```
-framework Security
-framework CoreFoundation
-lresolv
```

### Linux (Should Work)

Required linker flags:
```
-lpthread
-ldl
-lm
```

### Windows (Untested)

Expected requirements:
```
-lws2_32
-luserenv
-lbcrypt
```

## Future Enhancements

### Potential Additions

1. **Streaming File API**: Avoid loading entire files into memory
2. **Transaction Support**: Create commits, modify files
3. **Conflict Resolution**: Expose conflict resolution APIs
4. **Callbacks**: Progress reporting for long operations
5. **Async API**: Native async support for Zig's event loop

### API Stability

This is v0.1.0. Breaking changes may occur until v1.0.0.

**Stable**:
- Core workspace operations
- Commit queries
- File reading

**Unstable**:
- Bookmark operations (jj API still evolving)
- Operation metadata structure

## Contributing

### Adding New Functions

1. Add Rust implementation to `src/lib.rs`
2. Add C declaration to `jj_ffi.h`
3. Update `INTEGRATION.md` with usage example
4. Add example to `example.zig`

### Memory Management

All new functions returning allocated data must:
1. Use appropriate result struct
2. Provide corresponding `*_free()` function
3. Document ownership in comments

### Error Handling

Follow the pattern:
```rust
match risky_operation() {
    Ok(value) => Result {
        data: /* ownership transfer */,
        success: true,
        error_message: std::ptr::null_mut(),
    },
    Err(e) => Result {
        data: std::ptr::null_mut(),
        success: false,
        error_message: CString::new(format!("{}", e))
            .unwrap_or_else(|_| CString::new("Unknown error").unwrap())
            .into_raw(),
    },
}
```

## Build System Integration

### For build.zig

The current integration builds jj-ffi as part of the Zig build:

```zig
const jj_ffi_build = b.addSystemCommand(&.{
    "cargo", "build", "--release",
    "--manifest-path", "jj-ffi/Cargo.toml",
});
exe.step.dependOn(&jj_ffi_build.step);
```

This ensures jj-ffi is always up-to-date.

### For CI/CD

Recommended workflow:
1. Build jj-ffi: `cd jj-ffi && cargo build --release`
2. Run jj-ffi tests: `cargo test`
3. Build Zig executable: `zig build`
4. Run integration tests: `zig build test`

## Dependencies

### Direct Dependencies

- `jj-lib v0.36.0`: Core library (pinned for stability)
- `tokio v1`: Async runtime for file operations

### Transitive Dependencies

jj-lib brings in:
- Git support (libgit2)
- Cryptographic libraries (SHA, Blake2)
- Serialization (serde)

Total size: ~150 dependencies, ~10MB static library

## License

Follow jj-lib's license (Apache 2.0). Ensure compliance when distributing.

## References

- [jj-lib documentation](https://github.com/jj-vcs/jj/tree/main/lib)
- [jj book](https://jj-vcs.github.io/jj/)
- [Zig C FFI](https://ziglang.org/documentation/master/#C)
- [Rust FFI](https://doc.rust-lang.org/nomicon/ffi.html)

## Contact

For issues specific to this FFI wrapper, file a bug report with:
1. Zig version
2. Rust version
3. Platform (OS, architecture)
4. Minimal reproduction case
5. Error messages (both Rust and Zig sides)
