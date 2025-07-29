# Enhance HTTP Error Context

## Priority: Medium

## Problem
HTTP handlers in the server module return generic error messages that lose important context about what went wrong. This makes debugging difficult and provides poor user experience.

## Current Issues

### Example 1: Generic Database Errors (src/server/handlers/users.zig:16-19)
```zig
const user = ctx.dao.getUserById(allocator, user_id) catch |err| {
    std.log.err("Failed to get user by ID: {}", .{err});
    try json.writeError(r, allocator, .internal_server_error, "Database error");
    return;
};
```

### Example 2: Lost Error Context (src/server/server.zig:510-513)
```zig
var dao = DataAccessObject.init(test_db_url) catch {
    std.log.warn("Database not available for testing, skipping server test", .{});
    return;
};
```

## Expected Solution

1. **Create structured error responses** with more specific error codes:
   ```zig
   const user = ctx.dao.getUserById(allocator, user_id) catch |err| switch (err) {
       error.ConnectionRefused => {
           try json.writeError(r, allocator, .service_unavailable, "Database connection failed");
           return;
       },
       error.NotFound => {
           try json.writeError(r, allocator, .not_found, "User not found");
           return;
       },
       else => {
           std.log.err("Failed to get user by ID: {}", .{err});
           try json.writeError(r, allocator, .internal_server_error, "Database operation failed");
           return;
       },
   };
   ```

2. **Add error context preservation** in middleware and utilities

3. **Create consistent error response format** with error codes and detailed messages

## Files to Modify
- `src/server/handlers/users.zig`
- `src/server/handlers/orgs.zig` 
- `src/server/handlers/repos.zig`
- `src/server/utils/json.zig` (enhance error response structure)
- Any other HTTP handlers with generic error handling

## Testing
- Add tests for different error conditions
- Verify error responses have appropriate HTTP status codes
- Test that sensitive information is not leaked in error messages
- Ensure logging still captures detailed error information

## Benefits
- Better debugging experience for developers
- More helpful error messages for API consumers
- Proper HTTP status codes for different error conditions
- Maintained security (no sensitive data in responses)