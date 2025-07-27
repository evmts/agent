# Refactor Large Files into Smaller Modules

## Context

Our Plue project has grown significantly, with some files becoming too large to maintain effectively:
- `src/server/server.zig`: 5914 lines with 70 handler functions
- `src/database/dao.zig`: 1429 lines with all database operations

This violates the single responsibility principle and makes the codebase harder to navigate and maintain. We need to break these large files into smaller, focused modules.

## Goal

Refactor the codebase by splitting large files into smaller, logical modules while maintaining:
- Clear separation of concerns
- Easy navigation and understanding
- Minimal circular dependencies
- Consistent naming and organization

## Current File Sizes

```
5914 src/server/server.zig     # 70 handler functions
1429 src/database/dao.zig      # All database operations
 299 src/gui/webui/window.zig
 257 src/gui/webui/binding.zig
 246 src/gui/webui/event.zig
 219 src/database/models/issue.zig
 195 src/database/models/user.zig
```

## Proposed Structure

### 1. Server Handlers Refactoring

Split `src/server/server.zig` into:

```
src/server/
├── server.zig          # Main server setup, routing, middleware (~200 lines)
├── handlers/
│   ├── auth.zig        # Authentication middleware and helpers
│   ├── users.zig       # User management handlers
│   ├── orgs.zig        # Organization handlers
│   ├── repos.zig       # Repository handlers
│   ├── branches.zig    # Branch management handlers
│   ├── issues.zig      # Issue and comment handlers
│   ├── labels.zig      # Label management handlers
│   ├── pulls.zig       # Pull request handlers
│   ├── actions.zig     # CI/CD actions handlers
│   ├── admin.zig       # Admin endpoints
│   └── health.zig      # Health and status endpoints
└── utils/
    ├── json.zig        # JSON response helpers
    └── errors.zig      # Error response utilities
```

### 2. Database Operations Refactoring

Split `src/database/dao.zig` into:

```
src/database/
├── dao.zig             # Main DAO struct and pool management (~100 lines)
├── operations/
│   ├── users.zig       # User CRUD operations
│   ├── auth.zig        # Auth token operations
│   ├── orgs.zig        # Organization operations
│   ├── repos.zig       # Repository operations
│   ├── branches.zig    # Branch operations
│   ├── issues.zig      # Issue operations
│   ├── labels.zig      # Label operations
│   ├── reviews.zig     # Review operations
│   ├── actions.zig     # CI/CD operations
│   └── admin.zig       # Admin operations
└── models/             # (existing)
    ├── user.zig
    ├── repository.zig
    ├── issue.zig
    └── action.zig
```

## Implementation Steps

### Phase 1: Server Handler Refactoring

1. **Create handler directory structure**
   ```bash
   mkdir -p src/server/handlers
   mkdir -p src/server/utils
   ```

2. **Extract utility functions**
   - Move `writeJson`, `writeError` to `src/server/utils/json.zig`
   - Create error handling utilities in `src/server/utils/errors.zig`

3. **Move handlers by domain**
   - Extract user handlers (`getCurrentUserHandler`, `getUsersHandler`, etc.) to `handlers/users.zig`
   - Extract org handlers to `handlers/orgs.zig`
   - Continue for each domain area

4. **Update imports in server.zig**
   - Import handler modules
   - Keep routing logic in main server file

### Phase 2: Database Operations Refactoring

1. **Create operations directory structure**
   ```bash
   mkdir -p src/database/operations
   ```

2. **Extract operations by domain**
   - Move user operations (`createUser`, `getUserByName`, etc.) to `operations/users.zig`
   - Move auth operations to `operations/auth.zig`
   - Continue for each domain area

3. **Update DAO struct**
   - Keep pool management in main `dao.zig`
   - Import operation modules
   - Expose operations through DAO methods

### Phase 3: Integration and Testing

1. **Update all imports**
   - Fix import paths throughout the codebase
   - Ensure no circular dependencies

2. **Run comprehensive tests**
   ```bash
   zig build && zig build test
   ```

3. **Verify functionality**
   - Test all endpoints remain functional
   - Ensure database operations work correctly

## Benefits

1. **Improved Maintainability**
   - Smaller files are easier to understand and modify
   - Related functionality is grouped together

2. **Better Team Collaboration**
   - Multiple developers can work on different modules
   - Reduced merge conflicts

3. **Clearer Architecture**
   - Domain boundaries are explicit
   - Dependencies are more visible

4. **Faster Compilation**
   - Changes to one handler don't require recompiling all handlers
   - Better incremental compilation

## Migration Guidelines

### For Each Extracted Module

1. **Create new file with proper imports**
   ```zig
   const std = @import("std");
   const httpz = @import("httpz");
   const Context = @import("../server.zig").Context;
   ```

2. **Move related functions**
   - Keep functions that work together
   - Include helper functions used only by those handlers

3. **Add module tests**
   - Move related tests with the functions
   - Ensure tests still pass

4. **Export public functions**
   ```zig
   pub const getUserHandler = getUserHandler;
   pub const createUserHandler = createUserHandler;
   ```

### Naming Conventions

- Handler files: `{domain}.zig` (e.g., `users.zig`, `repos.zig`)
- Operation files: `{domain}.zig` in operations folder
- Keep consistent with existing patterns

## Success Criteria

1. No single file exceeds 1000 lines
2. All tests continue to pass
3. Clear separation of concerns
4. No circular dependencies
5. Improved code navigation
6. Consistent naming and organization

## Example: Extracting User Handlers

Create `src/server/handlers/users.zig`:

```zig
const std = @import("std");
const httpz = @import("httpz");
const server = @import("../server.zig");
const json_utils = @import("../utils/json.zig");

const Context = server.Context;

pub fn getCurrentUserHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const auth = try server.authenticateRequest(ctx, req, res) orelse return;
    
    const user = try ctx.dao.getUserById(req.arena, auth.user_id) orelse {
        return json_utils.writeError(res, req.arena, 404, "User not found");
    };
    
    try json_utils.writeJson(res, req.arena, user);
}

pub fn getUsersHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const users = try ctx.dao.listUsers(req.arena);
    try json_utils.writeJson(res, req.arena, users);
}

// ... more user handlers ...

test "user handlers" {
    // Move user handler tests here
}
```

## Notes

- Start with the largest files first (server.zig)
- Test after each extraction to ensure nothing breaks
- Consider creating a shared types module if needed
- Keep the refactoring incremental and reversible
- Document any shared dependencies clearly