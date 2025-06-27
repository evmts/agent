# Enhance Error Handling System for Plue AI Editor

You are an AI agent executing a well-scoped task to build an AI editor in Zig. This task focuses on enhancing the existing error handling system to match the comprehensive API specification defined in PLUE_CORE_API.md.

## Context

<context>
<project_overview>
Plue is a multi-agent coding assistant with a hybrid Swift-Zig architecture where:
- Zig owns ALL business logic and state management
- Swift is purely a presentation layer
- All errors must be properly propagated across the FFI boundary
- Error context must be preserved for debugging
</project_overview>

<existing_error_system>
The project already has a basic error system in src/error.zig:
```zig
pub const PlueError = error{
    Unknown,
    Unimplemented,
    OutOfMemory,
};
```

This needs to be significantly enhanced to match the API specification which defines:
- Comprehensive error codes with specific meanings
- Thread-local error message storage
- Detailed error JSON with stack traces and context
- Proper FFI error code mapping
</existing_error_system>

<api_specification>
From PLUE_CORE_API.md:
```c
// Error codes
typedef enum {
    PLUE_OK = 0,
    PLUE_ERROR_INVALID_PARAM = -1,
    PLUE_ERROR_NOT_FOUND = -2,
    PLUE_ERROR_ALREADY_EXISTS = -3,
    PLUE_ERROR_PROVIDER_AUTH = -4,
    PLUE_ERROR_PROVIDER_INIT = -5,
    PLUE_ERROR_JSON_PARSE = -6,
    PLUE_ERROR_IO = -7,
    PLUE_ERROR_TIMEOUT = -8,
    PLUE_ERROR_ABORTED = -9,
    PLUE_ERROR_UNKNOWN = -99
} plue_error_t;

// Get human-readable error message for last error on current thread
export fn plue_get_last_error() [*:0]const u8;

// Get detailed error JSON with stack trace and context
export fn plue_get_last_error_json() [*:0]const u8;
```
</api_specification>

<reference_implementation>
OpenCode (in opencode/ directory) has sophisticated error handling:
- opencode/packages/opencode/src/util/error.ts - NamedError pattern with context
- opencode/packages/opencode/src/util/log.ts - Structured logging with error tracking
- Errors include stack traces, context objects, and service attribution
</reference_implementation>
</context>

## Task: Enhance Error Handling System

### Requirements

1. **Expand error enum** to cover all API-specified error types with clear semantics
2. **Implement thread-local error storage** for detailed error information
3. **Create error context system** that captures:
   - Error location (file, function, line)
   - Stack trace information
   - Contextual data (parameters, state)
   - Timestamp and thread ID
4. **Build FFI error mapping** to convert Zig errors to C error codes
5. **Implement error serialization** to JSON with all context
6. **Add error propagation helpers** for clean error handling patterns

### Detailed Steps

1. **Redesign error.zig with comprehensive error types**:
   ```zig
   // Match API specification exactly
   pub const ErrorCode = enum(c_int) {
       ok = 0,
       invalid_param = -1,
       not_found = -2,
       already_exists = -3,
       provider_auth = -4,
       provider_init = -5,
       json_parse = -6,
       io = -7,
       timeout = -8,
       aborted = -9,
       unknown = -99,
   };
   
   // Rich error type for internal use
   pub const PlueError = error{
       InvalidParameter,
       NotFound,
       AlreadyExists,
       ProviderAuthFailed,
       ProviderInitFailed,
       JsonParseFailed,
       IoError,
       Timeout,
       Aborted,
       OutOfMemory,
       Unknown,
   };
   ```

2. **Implement thread-local error storage**:
   - Use Zig's thread-local storage for error context
   - Store last error message, code, and detailed context
   - Ensure thread safety without locks
   - Clean up storage on thread exit

3. **Create error context capture system**:
   ```zig
   pub const ErrorContext = struct {
       code: ErrorCode,
       message: []const u8,
       file: []const u8,
       function: []const u8,
       line: u32,
       thread_id: u64,
       timestamp: i64,
       stack_trace: ?*std.builtin.StackTrace,
       context_data: ?std.json.Value,
       
       pub fn init(allocator: Allocator, err: PlueError, message: []const u8) !ErrorContext {
           // Capture all context including stack trace
       }
       
       pub fn toJson(self: ErrorContext, allocator: Allocator) ![]u8 {
           // Serialize to detailed JSON format
       }
   };
   ```

4. **Build error mapping infrastructure**:
   ```zig
   // Convert Zig errors to FFI codes
   pub fn errorToCode(err: PlueError) ErrorCode {
       return switch (err) {
           error.InvalidParameter => .invalid_param,
           error.NotFound => .not_found,
           // ... complete mapping
       };
   }
   
   // Set thread-local error with context
   pub fn setError(err: PlueError, comptime fmt: []const u8, args: anytype) void {
       // Format message, capture context, store thread-local
   }
   ```

5. **Implement FFI error functions**:
   ```zig
   export fn plue_get_last_error() [*:0]const u8 {
       // Return human-readable error message from thread-local storage
   }
   
   export fn plue_get_last_error_json() [*:0]const u8 {
       // Return detailed JSON with full context
   }
   ```

6. **Create error handling helpers**:
   ```zig
   // Result type for FFI boundaries
   pub fn FfiResult(comptime T: type) type {
       return union(enum) {
           ok: T,
           err: ErrorCode,
           
           pub fn fromZigError(err: PlueError) FfiResult(T) {
               setError(err, "Operation failed", .{});
               return .{ .err = errorToCode(err) };
           }
       };
   }
   
   // Try with automatic error capture
   pub fn tryWithContext(comptime fmt: []const u8, args: anytype, expr: anytype) !@TypeOf(expr) {
       return expr catch |err| {
           setError(err, fmt, args);
           return err;
       };
   }
   ```

7. **Add error propagation patterns**:
   - Implement error wrapping for better context
   - Create error chain tracking
   - Add helpers for common error scenarios
   - Ensure all allocations use proper error handling

### Implementation Approach

Follow strict TDD methodology:

1. **Write comprehensive tests first**:
   - Test error code mappings
   - Test thread-local storage isolation
   - Test error context capture
   - Test JSON serialization format
   - Test FFI boundary behavior
   - Test error propagation patterns

2. **Implement incrementally with commits**:
   - Commit after basic error enum changes
   - Commit after thread-local storage works
   - Commit after context capture implemented
   - Commit after FFI functions work
   - Commit after each test suite passes

3. **Ensure idiomatic Zig patterns**:
   - Use comptime for zero-cost abstractions
   - Leverage Zig's error union types
   - Follow Zig naming conventions
   - Use proper memory management with allocators

### Git Workflow

```bash
git worktree add worktrees/enhanced-error-handling -b feat/enhanced-error-handling
cd worktrees/enhanced-error-handling
```

Commit strategy:
- `feat: expand error enum to match API specification`
- `feat: implement thread-local error storage system`
- `feat: add error context capture with stack traces`
- `feat: create FFI error mapping functions`
- `test: comprehensive error handling test suite`
- `refactor: update existing code to use new error system`

## Success Criteria

✅ **Task is complete when**:
1. All error codes from API specification are implemented
2. Thread-local error storage works correctly across multiple threads
3. Error context includes file, line, function, and stack trace
4. JSON error output matches expected format with full details
5. FFI functions return proper C strings that Swift can consume
6. All existing error handling is migrated to new system
7. Comprehensive test coverage (>95%) for error paths
8. No memory leaks in error handling code

## Technical Considerations

<zig_best_practices>
- Use `threadlocal` for thread-local variables
- Capture stack traces with `@returnAddress()` and debug info
- Use arena allocators for error message formatting
- Ensure all error paths are tested with `std.testing.expectError`
- Follow Zig error handling conventions (error unions, try, catch)
</zig_best_practices>

<performance_requirements>
- Error handling should have minimal overhead in success case
- Thread-local access must be lock-free
- Error context capture should be lazy (only on actual errors)
- JSON serialization should reuse buffers where possible
</performance_requirements>

<integration_notes>
- Update libplue.zig to export new error functions
- Ensure all existing FFI functions use new error system
- Document error handling patterns for future development
- Consider error telemetry/metrics for production
</integration_notes>

Remember: This error system is foundational - many other components depend on it. Make it robust, well-tested, and easy to use throughout the codebase.