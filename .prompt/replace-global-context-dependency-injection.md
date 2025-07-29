# Replace Global Context with Dependency Injection

## Priority: Medium

## Problem
The HTTP server uses a global context variable (`global_context` in `src/server/server.zig:23`) to provide handlers access to shared resources. This creates tight coupling and makes testing more difficult.

## Current Code
```zig
// Global context for handlers to access
var global_context: *Context = undefined;

pub fn init(allocator: std.mem.Allocator, dao: *DataAccessObject) !Server {
    // ...
    // Store context globally for handler access
    global_context = context;
    // ...
}

fn on_request(r: zap.Request) void {
    // ...
    router.callHandler(r, health.healthHandler, global_context);
    // ...
}
```

## Expected Solution

1. **Modify the router system** to pass context through the request cycle:
   ```zig
   const Router = struct {
       context: *Context,
       
       pub fn init(context: *Context) Router {
           return Router{ .context = context };
       }
       
       pub fn handleRequest(self: *Router, r: zap.Request) void {
           // Route and call handlers with self.context
       }
   };
   ```

2. **Update the server to use the router**:
   ```zig
   pub const Server = struct {
       listener: zap.HttpListener,
       router: Router,
       
       pub fn init(allocator: std.mem.Allocator, dao: *DataAccessObject) !Server {
           const context = try allocator.create(Context);
           context.* = Context{ .dao = dao, .allocator = allocator };
           
           const router = Router.init(context);
           
           return Server{
               .listener = zap.HttpListener.init(.{
                   .port = 8000,
                   .on_request = handleRequest,
                   // ...
               }),
               .router = router,
           };
       }
       
       fn handleRequest(r: zap.Request) void {
           // Need to access server instance somehow...
       }
   };
   ```

3. **Alternative: Use zap's user_data feature** if available:
   ```zig
   const listener = zap.HttpListener.init(.{
       .port = 8000,
       .on_request = on_request,
       .user_data = context,
       // ...
   });
   ```

## Files to Modify
- `src/server/server.zig` (main changes)
- `src/server/router.zig` (if it needs updating)
- All handler files may need signature updates

## Challenges
- The zap HTTP library may impose constraints on how context is passed
- Need to investigate zap's capabilities for request context
- Handler function signatures may need to change

## Research Needed
1. Check zap documentation for context passing mechanisms
2. Investigate if zap supports user_data or similar features
3. Determine if request handlers can access server instance

## Benefits
- Eliminates global state
- Makes testing easier (can inject mock contexts)
- Better separation of concerns
- Thread-safe context handling

## Testing
- Ensure all existing tests continue to pass
- Add tests for different context scenarios
- Verify no race conditions with context access
- Test with mock contexts for unit testing