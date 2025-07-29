# Standardize Error Handling Patterns

## Priority: Low

## Problem
The codebase has inconsistent error handling patterns across modules. Some modules use detailed error enums (like `GitError`) while others rely on generic errors, making debugging and error reporting inconsistent.

## Current Inconsistencies

### 1. Detailed Error Enums (Good Example)
```zig
// src/git/command.zig:94-105
pub const GitError = error{
    GitNotFound,
    InvalidArgument,
    CommandInjection,
    Timeout,
    ProcessFailed,
    PermissionDenied,
    InvalidRepository,
    AuthenticationFailed,
    ChildProcessFailed,
    OutputTooLarge,
};
```

### 2. Generic Error Usage (Inconsistent)
```zig
// src/lfs/storage.zig:20-30
pub const LfsStorageError = error{
    InvalidChecksum,
    ObjectNotFound,
    StorageLimitExceeded,
    QuotaExceeded,
    PermissionDenied,
    BackendError,
    DatabaseError,
    CorruptedData,
    OutOfMemory,
};
```

### 3. Mixed Patterns
Some functions return generic errors while others in the same module use specific error enums.

## Expected Solution

1. **Create a project-wide error hierarchy**:
   ```zig
   // src/errors.zig
   pub const PlueError = error{
       // Database errors
       DatabaseConnectionFailed,
       DatabaseQueryFailed,
       DatabaseConstraintViolation,
       RecordNotFound,
       
       // HTTP/API errors
       InvalidRequest,
       Unauthorized,
       Forbidden,
       NotFound,
       RateLimited,
       
       // Git operation errors
       GitCommandFailed,
       InvalidRepository,
       AuthenticationFailed,
       
       // LFS errors
       ObjectNotFound,
       InvalidChecksum,
       StorageLimitExceeded,
       
       // SSH errors
       ConnectionFailed,
       KeyValidationFailed,
       SessionError,
       
       // Actions/CI errors
       WorkflowParsingFailed,
       JobExecutionFailed,
       ContainerError,
       
       // General errors
       InvalidInput,
       PermissionDenied,
       Timeout,
       ResourceExhausted,
       InternalError,
   };
   ```

2. **Create error context utilities**:
   ```zig
   // src/errors.zig
   pub const ErrorContext = struct {
       error_type: PlueError,
       message: []const u8,
       details: ?[]const u8 = null,
       source_location: std.builtin.SourceLocation,
       
       pub fn init(
           error_type: PlueError,
           message: []const u8,
           source_location: std.builtin.SourceLocation
       ) ErrorContext {
           return ErrorContext{
               .error_type = error_type,
               .message = message,
               .source_location = source_location,
           };
       }
   };
   
   pub fn contextualError(
       error_type: PlueError,
       message: []const u8,
       source: std.builtin.SourceLocation
   ) ErrorContext {
       return ErrorContext.init(error_type, message, source);
   }
   ```

3. **Standardize error conversion patterns**:
   ```zig
   // Example usage pattern
   pub fn databaseOperation() PlueError!Result {
       const result = database.query("SELECT ...") catch |err| switch (err) {
           error.ConnectionRefused => return error.DatabaseConnectionFailed,
           error.InvalidQuery => return error.DatabaseQueryFailed,
           error.NotFound => return error.RecordNotFound,
           else => {
               std.log.err("Unexpected database error: {}", .{err});
               return error.InternalError;
           },
       };
       
       return result;
   }
   ```

4. **Create error logging utilities**:
   ```zig
   // src/errors.zig
   pub fn logError(
       context: ErrorContext,
       comptime level: std.log.Level
   ) void {
       std.log.logEnabled(level, .default).* = true;
       std.log.defaultLog(
           level,
           .default,
           "{s} at {s}:{d} - {s}",
           .{ @errorName(context.error_type), context.source_location.file, context.source_location.line, context.message }
       );
   }
   ```

## Migration Strategy

1. **Phase 1**: Create the error hierarchy and utilities
2. **Phase 2**: Update high-traffic modules (database, HTTP handlers)
3. **Phase 3**: Update remaining modules gradually
4. **Phase 4**: Remove old error enums that have been replaced

## Files to Create/Modify
- **Create**: `src/errors.zig` (centralized error definitions)
- **Modify**: `src/database/dao.zig` (standardize database errors)
- **Modify**: `src/server/handlers/*.zig` (standardize HTTP errors)
- **Modify**: `src/git/command.zig` (align with standard patterns)
- **Modify**: `src/lfs/storage.zig` (align with standard patterns)
- **Modify**: Other modules gradually

## Benefits
- Consistent error handling across the entire codebase
- Better error reporting and logging
- Easier debugging with standardized error contexts
- More maintainable error handling code
- Better API error responses

## Implementation Guidelines
1. **Preserve existing functionality** - don't break existing error handling
2. **Add context gradually** - start with new code, migrate old code over time
3. **Keep it simple** - don't over-engineer the error system
4. **Document patterns** - create clear examples for developers

## Testing
- Ensure all existing error handling tests continue to pass
- Add tests for new error context utilities
- Verify error messages are helpful and consistent
- Test error logging functionality

## Documentation
- Update coding standards to include error handling patterns
- Create examples of proper error handling
- Document when to use which error types
- Provide migration guide for existing code