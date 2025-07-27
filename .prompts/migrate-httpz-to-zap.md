# Migrate from httpz to zap

## Context

We are migrating our web server from httpz to zap (zigzap). The current implementation uses httpz throughout the codebase, and we need to replace it with zap while maintaining all existing functionality.

zap is a blazingly fast web framework for Zig built on top of facil.io. It provides similar functionality to httpz but with a different API design.

## Migration Tasks

### 1. Update Dependencies

Replace the httpz dependency with zap in `build.zig.zon`:
- Remove the httpz dependency entry
- Add zap dependency: `https://github.com/zigzap/zap` (use the latest stable release)

Update `build.zig`:
- Replace `b.dependency("httpz", ...)` with `b.dependency("zap", ...)`
- Replace `exe_mod.addImport("httpz", httpz.module("httpz"))` with `exe_mod.addImport("zap", zap.module("zap"))`

### 2. Refactor Server Structure

The main server file (`src/server/server.zig`) needs significant changes:
- Replace `httpz.Server(*Context)` with zap's listener approach
- Convert from httpz's context-based handlers to zap's request-based handlers
- Update server initialization to use `zap.HttpListener.init()`
- Replace httpz's router with zap's routing approach (consider using simple router dispatch)
- Update the `listen()` method to use zap's listening mechanism

Key differences:
- httpz handlers: `fn(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void`
- zap handlers: `fn(r: zap.Request) !void`

### 3. Update Handler Signatures

All handlers across these files need updating:
- `src/server/handlers/health.zig`
- `src/server/handlers/users.zig`
- `src/server/handlers/orgs.zig`
- `src/server/handlers/repos.zig`

Handler conversion pattern:
```zig
// Old httpz handler
pub fn handler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.body = "response";
}

// New zap handler
pub fn handler(r: zap.Request) !void {
    try r.sendBody("response");
}
```

### 4. Request Handling Updates

Replace httpz request methods with zap equivalents:
- `req.arena` → Use zap's allocator approach or pass allocator separately
- `req.param()` → Use zap's parameter extraction methods
- `req.query()` → Use zap's query string parsing
- Path parameters need to be extracted using zap's approach

### 5. Response Handling Updates

Replace httpz response patterns:
- Setting status codes and bodies needs to use zap's API
- JSON responses: Update `src/server/utils/json.zig` to work with zap's response methods
- Error responses: Adapt error handling to zap's patterns

### 6. Middleware Updates

Update authentication middleware in `src/server/utils/auth.zig`:
- Convert from httpz's middleware pattern to zap's approach
- Ensure request context is properly passed through

### 7. Testing Updates

Update all server tests to work with the new zap implementation:
- Server initialization tests
- Handler tests (if any)
- Integration tests that use the HTTP server

## Important Considerations

1. **Memory Management**: zap may have different memory management patterns than httpz. Ensure proper allocation/deallocation following our CLAUDE.md guidelines.

2. **Request Arena**: httpz provides `req.arena` for request-scoped allocations. Determine zap's equivalent approach and update all handlers accordingly.

3. **Error Handling**: Maintain consistent error handling patterns. zap uses `!void` returns, so ensure errors are properly propagated.

4. **Route Parameters**: httpz uses `:param` syntax for route parameters. Verify zap's syntax and update all routes accordingly.

5. **Content-Type Headers**: Ensure JSON responses still set proper Content-Type headers with zap's API.

6. **Build and Test**: After each file update, run `zig build && zig build test` to ensure no regressions.

## Migration Order

1. Update dependencies in build files
2. Create a minimal zap server to test the setup
3. Migrate the main server.zig file
4. Update JSON utilities
5. Migrate health handlers (simplest)
6. Migrate auth utilities
7. Migrate remaining handlers one by one
8. Update all tests
9. Verify all endpoints work correctly

## Verification

After migration:
1. All existing endpoints must work identically
2. No memory leaks or allocation issues
3. All tests must pass
4. Server must bind to 0.0.0.0:8000 for Docker compatibility
5. Health check endpoint must return same responses

## Documentation Updates

After successfully completing the migration and verifying all functionality:

### 1. Update CONTRIBUTING.md
- Replace any references to httpz with zap
- Update development setup instructions if the migration affects local development
- Update any code examples that show httpz usage

### 2. Update README.md
- Update the tech stack section to mention zap instead of httpz
- Update any architectural diagrams or descriptions that reference httpz
- Ensure dependency installation instructions are current

### 3. Update CLAUDE.md
- Add any zap-specific patterns or guidelines under "HTTP Server Development" section
- Document any new memory management considerations specific to zap
- Update any code examples that reference httpz patterns
- Add any zap-specific debugging or development tips learned during migration