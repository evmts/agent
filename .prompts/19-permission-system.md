# Permission System Implementation

## Overview

Implement a comprehensive permission checking system for repository access control in the Plue application. This system will serve as the authorization foundation for all git operations, ensuring secure and granular access control.

## Core Requirements

### 1. Access Mode Enumeration

Create an `AccessMode` enum with the following permission levels:
- `None` - No access
- `Read` - Read-only access
- `Write` - Read and write access
- `Admin` - Administrative access
- `Owner` - Full ownership rights

### 2. Permission Checking Function

Implement `check_user_repo_permission()` with this signature:
```zig
pub fn checkUserRepoPermission(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    user_id: ?i64,
    repo_id: i64
) !AccessMode
```

### 3. Permission Logic

The function must handle these scenarios in order:

1. **Deleted/Invalid Cases**: Return `AccessMode.None` for:
   - Deleted repositories
   - Deleted users (when user_id provided)
   - Invalid repository IDs

2. **Public Repository Access**:
   - Anonymous users: `AccessMode.Read`
   - Authenticated users: Check collaborator status first, then default to `AccessMode.Read`

3. **Repository Owner**: Return `AccessMode.Owner`

4. **Admin Users**: Return `AccessMode.Admin` (unless restricted)

5. **Collaborators**: Check collaboration table for specific permissions

6. **Private Repositories**: Default to `AccessMode.None` for non-collaborators

### 4. Security Requirements

- **Fail-Safe Defaults**: Always deny access by default
- **Input Validation**: Validate all inputs before processing
- **No Caching**: Always perform fresh database queries
- **Audit Trail**: Log all permission checks for security auditing

## Implementation Example

```zig
const std = @import("std");
const DataAccessObject = @import("../database/dao.zig");

pub const AccessMode = enum {
    None,
    Read,
    Write,
    Admin,
    Owner,
};

pub fn checkUserRepoPermission(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    user_id: ?i64,
    repo_id: i64
) !AccessMode {
    // Default deny
    var access = AccessMode.None;
    
    // Check if repository exists and is not deleted
    const repo = dao.getRepository(allocator, repo_id) catch |err| {
        std.log.warn("Permission check failed for repo {}: {}", .{ repo_id, err });
        return AccessMode.None;
    };
    defer allocator.free(repo.name);
    
    if (repo.is_deleted) {
        return AccessMode.None;
    }
    
    // Handle anonymous users
    if (user_id == null) {
        return if (repo.is_private) AccessMode.None else AccessMode.Read;
    }
    
    const uid = user_id.?;
    
    // Check if user exists and is not deleted
    const user = dao.getUser(allocator, uid) catch {
        return AccessMode.None;
    };
    defer allocator.free(user.name);
    
    if (user.is_deleted) {
        return AccessMode.None;
    }
    
    // Check if user is repository owner
    if (repo.owner_id == uid) {
        return AccessMode.Owner;
    }
    
    // Check if user is admin (and not restricted)
    if (user.is_admin and !user.is_restricted) {
        return AccessMode.Admin;
    }
    
    // Check collaboration permissions
    const collab = dao.getCollaboration(allocator, uid, repo_id) catch |err| switch (err) {
        error.NotFound => null,
        else => return err,
    };
    
    if (collab) |c| {
        defer allocator.free(c.mode);
        access = std.meta.stringToEnum(AccessMode, c.mode) orelse AccessMode.None;
    }
    
    // Public repository default access
    if (repo.is_private == false and access == AccessMode.None) {
        access = AccessMode.Read;
    }
    
    return access;
}

test "permission checks" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available for testing, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    // Test anonymous access to public repo
    {
        const repo_id = try dao.createRepository(allocator, "public-repo", 1, false);
        defer dao.deleteRepository(repo_id) catch {};
        
        const access = try checkUserRepoPermission(allocator, &dao, null, repo_id);
        try std.testing.expectEqual(AccessMode.Read, access);
    }
    
    // Test owner access
    {
        const user_id = try dao.createUser(allocator, "owner");
        defer dao.deleteUser(user_id) catch {};
        
        const repo_id = try dao.createRepository(allocator, "owned-repo", user_id, true);
        defer dao.deleteRepository(repo_id) catch {};
        
        const access = try checkUserRepoPermission(allocator, &dao, user_id, repo_id);
        try std.testing.expectEqual(AccessMode.Owner, access);
    }
    
    // Test admin access
    {
        const admin_id = try dao.createUser(allocator, "admin");
        defer dao.deleteUser(admin_id) catch {};
        
        try dao.setUserAdmin(admin_id, true);
        
        const repo_id = try dao.createRepository(allocator, "some-repo", 1, true);
        defer dao.deleteRepository(repo_id) catch {};
        
        const access = try checkUserRepoPermission(allocator, &dao, admin_id, repo_id);
        try std.testing.expectEqual(AccessMode.Admin, access);
    }
    
    // Test collaborator access
    {
        const user_id = try dao.createUser(allocator, "collaborator");
        defer dao.deleteUser(user_id) catch {};
        
        const repo_id = try dao.createRepository(allocator, "collab-repo", 1, true);
        defer dao.deleteRepository(repo_id) catch {};
        
        try dao.addCollaborator(repo_id, user_id, "Write");
        
        const access = try checkUserRepoPermission(allocator, &dao, user_id, repo_id);
        try std.testing.expectEqual(AccessMode.Write, access);
    }
    
    // Test restricted admin
    {
        const admin_id = try dao.createUser(allocator, "restricted-admin");
        defer dao.deleteUser(admin_id) catch {};
        
        try dao.setUserAdmin(admin_id, true);
        try dao.setUserRestricted(admin_id, true);
        
        const repo_id = try dao.createRepository(allocator, "private-repo", 1, true);
        defer dao.deleteRepository(repo_id) catch {};
        
        const access = try checkUserRepoPermission(allocator, &dao, admin_id, repo_id);
        try std.testing.expectEqual(AccessMode.None, access);
    }
    
    // Test deleted repository
    {
        const user_id = try dao.createUser(allocator, "user");
        defer dao.deleteUser(user_id) catch {};
        
        const repo_id = try dao.createRepository(allocator, "deleted-repo", user_id, false);
        try dao.deleteRepository(repo_id);
        
        const access = try checkUserRepoPermission(allocator, &dao, user_id, repo_id);
        try std.testing.expectEqual(AccessMode.None, access);
    }
}
```

## Database Schema Requirements

The implementation assumes these database tables exist:

```sql
-- Users table
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    is_admin BOOLEAN DEFAULT FALSE,
    is_restricted BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Repositories table
CREATE TABLE repositories (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    owner_id BIGINT REFERENCES users(id),
    is_private BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Collaborations table
CREATE TABLE collaborations (
    id BIGSERIAL PRIMARY KEY,
    repo_id BIGINT REFERENCES repositories(id),
    user_id BIGINT REFERENCES users(id),
    mode VARCHAR(50) NOT NULL CHECK (mode IN ('Read', 'Write', 'Admin')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(repo_id, user_id)
);
```

## Security Considerations

1. **Never Trust Client Input**: Always validate user_id and repo_id
2. **Deny by Default**: Start with `AccessMode.None` and only upgrade with proof
3. **Check Deletion Status**: Always verify entities are not soft-deleted
4. **Audit Logging**: Log all permission checks with user, repo, and result
5. **No Permission Caching**: Always query fresh data to prevent stale permissions
6. **Handle Database Errors**: Treat errors as permission denied, not server errors

## Testing Strategy

1. **Unit Tests**: Test each permission scenario independently
2. **Integration Tests**: Test with real PostgreSQL database
3. **Edge Cases**:
   - Deleted users/repositories
   - Null user_id (anonymous)
   - Invalid IDs
   - Database connection failures
   - Concurrent permission changes

4. **Security Tests**:
   - Attempt privilege escalation
   - Test restricted admin limitations
   - Verify private repo protection

## Performance Considerations

1. **Database Queries**: Minimize queries by fetching all needed data upfront
2. **Early Returns**: Exit early for common cases (deleted, anonymous)
3. **Index Strategy**: Ensure proper indexes on:
   - `repositories(id, is_deleted)`
   - `users(id, is_deleted)`
   - `collaborations(repo_id, user_id)`

## Integration Points

This permission system will integrate with:
- Git HTTP/SSH handlers for push/pull authorization
- REST API endpoints for access control
- Web UI for displaying appropriate actions
- Audit logging system for compliance

## Error Handling

Use distinct error types for different failures:
```zig
pub const PermissionError = error{
    RepositoryNotFound,
    UserNotFound,
    DatabaseError,
    InvalidInput,
};
```

This allows calling code to handle different scenarios appropriately while maintaining security.

## Future Enhancements

1. **Organization Support**: Add organization-level permissions
2. **Team Access**: Support team-based repository access
3. **Fine-Grained Permissions**: Branch/path-level restrictions
4. **Time-Based Access**: Temporary access tokens
5. **IP Restrictions**: Limit access by IP range