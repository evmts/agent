# Permission System Implementation

## Overview

Implement a comprehensive permission checking system for repository access control in the Plue application, following Gitea's production-proven patterns. This system will serve as the authorization foundation for all git operations, supporting individual users, organizations, teams, and fine-grained unit-level permissions.

## Core Requirements

### 1. Access Mode Enumeration

Create an `AccessMode` enum with the following permission levels:
```zig
pub const AccessMode = enum(u8) {
    None = 0,
    Read = 1,
    Write = 2,
    Admin = 3,
    Owner = 4,
    
    pub fn atLeast(self: AccessMode, required: AccessMode) bool {
        return @intFromEnum(self) >= @intFromEnum(required);
    }
};
```

### 2. Unit-Level Permissions

Support fine-grained permissions per repository unit (Issues, PRs, Wiki, etc.):
```zig
pub const UnitType = enum {
    Code,
    Issues,
    PullRequests,
    Wiki,
    Projects,
    Actions,
    Packages,
    Settings,
};

pub const Permission = struct {
    access_mode: AccessMode,
    units: std.EnumMap(UnitType, AccessMode),
    
    pub fn canAccess(self: *const Permission, unit_type: UnitType, required_mode: AccessMode) bool {
        const unit_mode = self.units.get(unit_type) orelse self.access_mode;
        return unit_mode.atLeast(required_mode);
    }
    
    pub fn canRead(self: *const Permission, unit_type: UnitType) bool {
        return self.canAccess(unit_type, .Read);
    }
    
    pub fn canWrite(self: *const Permission, unit_type: UnitType) bool {
        return self.canAccess(unit_type, .Write);
    }
};
```

### 3. Request-Level Permission Cache

Implement ephemeral caching for the duration of a single request:
```zig
pub const PermissionCache = struct {
    const CacheKey = struct { 
        user_id: ?i64, 
        repo_id: i64,
        
        pub fn hash(self: CacheKey) u64 {
            var hasher = std.hash.Wyhash.init(0);
            std.hash.autoHash(&hasher, self.user_id);
            std.hash.autoHash(&hasher, self.repo_id);
            return hasher.final();
        }
    };
    
    cache: std.HashMap(CacheKey, Permission, std.hash_map.AutoContext(CacheKey), 80),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) PermissionCache {
        return .{
            .cache = std.HashMap(CacheKey, Permission, std.hash_map.AutoContext(CacheKey), 80).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *PermissionCache) void {
        self.cache.deinit();
    }
    
    pub fn getOrCompute(
        self: *PermissionCache,
        dao: *DataAccessObject,
        user_id: ?i64,
        repo_id: i64,
    ) !Permission {
        const key = CacheKey{ .user_id = user_id, .repo_id = repo_id };
        if (self.cache.get(key)) |cached| {
            return cached;
        }
        
        const permission = try loadUserRepoPermission(self.allocator, dao, user_id, repo_id);
        try self.cache.put(key, permission);
        return permission;
    }
};
```

### 4. Core Permission Loading Function

Implement the main permission loading logic with organization/team support:
```zig
pub fn loadUserRepoPermission(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    user_id: ?i64,
    repo_id: i64,
) !Permission {
    // Default deny with no unit access
    var permission = Permission{
        .access_mode = .None,
        .units = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };
    
    // Check if repository exists and is not deleted
    const repo = dao.getRepository(allocator, repo_id) catch |err| {
        std.log.err("Permission check failed for repo {d}: {}", .{ repo_id, err });
        return permission; // Fail closed
    };
    defer allocator.free(repo.name);
    
    if (repo.is_deleted) {
        return permission;
    }
    
    // Handle anonymous users
    if (user_id == null) {
        if (!repo.is_private) {
            permission.access_mode = .Read;
            // Enable read access for all units except settings
            var iter = permission.units.iterator();
            while (iter.next()) |entry| {
                if (entry.key != .Settings) {
                    permission.units.put(entry.key, .Read);
                }
            }
        }
        return permission;
    }
    
    const uid = user_id.?;
    
    // Check if user exists and is not deleted
    const user = dao.getUser(allocator, uid) catch {
        return permission; // Fail closed
    };
    defer allocator.free(user.name);
    
    if (user.is_deleted) {
        return permission;
    }
    
    // Check if user is repository owner
    if (repo.owner_id == uid and repo.owner_type == .user) {
        permission.access_mode = .Owner;
        permission.units = std.EnumMap(UnitType, AccessMode).initFull(.Owner);
        return permission;
    }
    
    // Check if user is admin (and not restricted)
    if (user.is_admin and !user.is_restricted) {
        permission.access_mode = .Admin;
        permission.units = std.EnumMap(UnitType, AccessMode).initFull(.Admin);
        return permission;
    }
    
    // For restricted users, deny access to private repos unless explicitly granted
    if (user.is_restricted and repo.is_private) {
        // Must have explicit access grant
        permission.access_mode = .None;
    }
    
    // Check pre-computed access table first (performance optimization)
    if (try dao.getAccessLevel(uid, repo_id)) |access| {
        permission.access_mode = std.meta.stringToEnum(AccessMode, access.mode) orelse .None;
    }
    
    // Check organization and team permissions
    if (repo.owner_type == .organization) {
        const team_perm = try checkOrgTeamPermission(allocator, dao, repo.owner_id, uid, repo_id);
        permission.access_mode = @max(permission.access_mode, team_perm.access_mode);
        
        // Merge unit permissions
        var iter = team_perm.units.iterator();
        while (iter.next()) |entry| {
            const current = permission.units.get(entry.key) orelse .None;
            permission.units.put(entry.key, @max(current, entry.value.*));
        }
    }
    
    // Check individual collaboration permissions
    if (try dao.getCollaboration(allocator, uid, repo_id)) |collab| {
        defer allocator.free(collab.mode);
        const collab_mode = std.meta.stringToEnum(AccessMode, collab.mode) orelse .None;
        permission.access_mode = @max(permission.access_mode, collab_mode);
        
        // Apply collaboration unit permissions if specified
        if (collab.units) |units| {
            defer allocator.free(units);
            // Parse and apply unit-specific permissions
            applyUnitPermissions(&permission, units, collab_mode);
        }
    }
    
    // Public repository default access (if not already set)
    if (!repo.is_private and permission.access_mode == .None) {
        permission.access_mode = .Read;
        // Enable read access for public units
        var iter = permission.units.iterator();
        while (iter.next()) |entry| {
            if (entry.key != .Settings and entry.value.* == .None) {
                permission.units.put(entry.key, .Read);
            }
        }
    }
    
    // Log successful permission load for audit
    std.log.debug("Permission loaded for user {?d} in repo {d}, access: {}", .{ user_id, repo_id, permission.access_mode });
    
    return permission;
}

fn checkOrgTeamPermission(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    org_id: i64,
    user_id: i64,
    repo_id: i64,
) !Permission {
    var permission = Permission{
        .access_mode = .None,
        .units = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };
    
    // Get user's teams in this organization that have access to this repository
    const teams = try dao.getUserRepoTeams(allocator, org_id, user_id, repo_id);
    defer teams.deinit();
    
    // Check for owner/admin teams first (they get full access)
    for (teams.items) |team| {
        if (team.is_owner_team) {
            permission.access_mode = .Owner;
            permission.units = std.EnumMap(UnitType, AccessMode).initFull(.Owner);
            return permission;
        }
        if (team.can_create_org_repo) {
            permission.access_mode = .Admin;
            permission.units = std.EnumMap(UnitType, AccessMode).initFull(.Admin);
        }
    }
    
    // Find maximum permission level from all teams
    for (teams.items) |team| {
        const team_mode = std.meta.stringToEnum(AccessMode, team.access_mode) orelse .None;
        permission.access_mode = @max(permission.access_mode, team_mode);
        
        // Apply team unit permissions
        if (team.units) |units| {
            applyUnitPermissions(&permission, units, team_mode);
        }
    }
    
    return permission;
}

fn applyUnitPermissions(permission: *Permission, units_json: []const u8, default_mode: AccessMode) void {
    // Parse JSON unit permissions and apply them
    // Format: {"issues": "write", "pulls": "admin", "wiki": "none"}
    // Implementation depends on JSON parsing approach
    _ = units_json;
    _ = default_mode;
    // TODO: Implement JSON parsing for unit permissions
}
```

### 5. Helper Functions for Common Checks

```zig
pub fn canReadRepository(
    cache: *PermissionCache,
    dao: *DataAccessObject,
    user_id: ?i64,
    repo_id: i64,
) !bool {
    const perm = try cache.getOrCompute(dao, user_id, repo_id);
    return perm.access_mode.atLeast(.Read);
}

pub fn canWriteRepository(
    cache: *PermissionCache,
    dao: *DataAccessObject,
    user_id: i64,
    repo_id: i64,
) !bool {
    const perm = try cache.getOrCompute(dao, user_id, repo_id);
    return perm.access_mode.atLeast(.Write);
}

pub fn canAccessUnit(
    cache: *PermissionCache,
    dao: *DataAccessObject,
    user_id: ?i64,
    repo_id: i64,
    unit_type: UnitType,
    required_mode: AccessMode,
) !bool {
    const perm = try cache.getOrCompute(dao, user_id, repo_id);
    return perm.canAccess(unit_type, required_mode);
}

// Special checks for specific operations
pub fn canCreateIssue(cache: *PermissionCache, dao: *DataAccessObject, user_id: i64, repo_id: i64) !bool {
    return canAccessUnit(cache, dao, user_id, repo_id, .Issues, .Write);
}

pub fn canMergePullRequest(cache: *PermissionCache, dao: *DataAccessObject, user_id: i64, repo_id: i64) !bool {
    const perm = try cache.getOrCompute(dao, user_id, repo_id);
    // Merging requires write access to code or admin/owner status
    return perm.canAccess(.Code, .Write) or perm.access_mode.atLeast(.Admin);
}
```

## Database Schema Requirements

```sql
-- Users table
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    is_admin BOOLEAN DEFAULT FALSE,
    is_restricted BOOLEAN DEFAULT FALSE,  -- Restricted users have limited access
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Owner types enum
CREATE TYPE owner_type AS ENUM ('user', 'organization');

-- Organizations
CREATE TABLE organizations (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    visibility VARCHAR(20) DEFAULT 'public',  -- public, limited, private
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Repositories table
CREATE TABLE repositories (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    owner_id BIGINT NOT NULL,  -- References either users.id or organizations.id
    owner_type owner_type NOT NULL,
    is_private BOOLEAN DEFAULT FALSE,
    is_mirror BOOLEAN DEFAULT FALSE,  -- Mirrors are always read-only
    is_archived BOOLEAN DEFAULT FALSE,  -- Archived repos are read-only
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(owner_id, owner_type, name)
);

-- Teams
CREATE TABLE teams (
    id BIGSERIAL PRIMARY KEY,
    org_id BIGINT REFERENCES organizations(id),
    name VARCHAR(255) NOT NULL,
    access_mode VARCHAR(20) NOT NULL DEFAULT 'read',
    can_create_org_repo BOOLEAN DEFAULT FALSE,  -- Admin teams
    is_owner_team BOOLEAN DEFAULT FALSE,  -- Special owner team
    units JSONB,  -- Unit-specific permissions: {"issues": "write", "wiki": "admin"}
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(org_id, name)
);

-- Team memberships
CREATE TABLE team_users (
    team_id BIGINT REFERENCES teams(id) ON DELETE CASCADE,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (team_id, user_id)
);

-- Team repository access
CREATE TABLE team_repos (
    team_id BIGINT REFERENCES teams(id) ON DELETE CASCADE,
    repo_id BIGINT REFERENCES repositories(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (team_id, repo_id)
);

-- Individual collaborations
CREATE TABLE collaborations (
    id BIGSERIAL PRIMARY KEY,
    repo_id BIGINT REFERENCES repositories(id) ON DELETE CASCADE,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    mode VARCHAR(20) NOT NULL CHECK (mode IN ('read', 'write', 'admin')),
    units JSONB,  -- Optional unit-specific permissions
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(repo_id, user_id)
);

-- Pre-computed access levels (performance optimization)
-- This table is maintained by triggers/background jobs
CREATE TABLE access (
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    repo_id BIGINT REFERENCES repositories(id) ON DELETE CASCADE,
    mode VARCHAR(20) NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, repo_id)
);

-- Indexes for performance
CREATE INDEX idx_repositories_owner ON repositories(owner_id, owner_type) WHERE NOT is_deleted;
CREATE INDEX idx_team_users_user ON team_users(user_id);
CREATE INDEX idx_team_repos_repo ON team_repos(repo_id);
CREATE INDEX idx_collaborations_user_repo ON collaborations(user_id, repo_id);
CREATE INDEX idx_access_lookup ON access(user_id, repo_id);
```

## Security Considerations

1. **Fail-Safe Defaults**: 
   - Always start with `AccessMode.None`
   - Database errors result in access denial
   - Invalid data results in access denial

2. **No Permission Elevation**:
   - Restricted users cannot gain admin access
   - Deleted entities result in immediate denial
   - Mirror repositories enforce read-only

3. **Audit Logging**:
   - Log successful permission loads at DEBUG level
   - Log errors at ERROR level without exposing sensitive data
   - Do NOT log denied access attempts (following Gitea pattern)

4. **Race Condition Handling**:
   - Accept eventual consistency
   - No locking on permission checks
   - Database constraints prevent corruption

## Testing Strategy

```zig
test "basic user permissions" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    // Test owner access
    const owner_id = try dao.createUser(allocator, "owner");
    defer dao.deleteUser(owner_id) catch {};
    
    const repo_id = try dao.createRepository(allocator, "test-repo", owner_id, .user, false);
    defer dao.deleteRepository(repo_id) catch {};
    
    const perm = try cache.getOrCompute(&dao, owner_id, repo_id);
    try std.testing.expectEqual(AccessMode.Owner, perm.access_mode);
    try std.testing.expect(perm.canWrite(.Code));
}

test "organization team permissions" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    // Create organization and team
    const org_id = try dao.createOrganization(allocator, "test-org");
    defer dao.deleteOrganization(org_id) catch {};
    
    const team_id = try dao.createTeam(allocator, org_id, "developers", "write");
    defer dao.deleteTeam(team_id) catch {};
    
    const user_id = try dao.createUser(allocator, "developer");
    defer dao.deleteUser(user_id) catch {};
    
    try dao.addTeamMember(team_id, user_id);
    
    const repo_id = try dao.createRepository(allocator, "team-repo", org_id, .organization, true);
    defer dao.deleteRepository(repo_id) catch {};
    
    try dao.addTeamRepository(team_id, repo_id);
    
    const perm = try cache.getOrCompute(&dao, user_id, repo_id);
    try std.testing.expectEqual(AccessMode.Write, perm.access_mode);
}

test "restricted user limitations" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    // Create restricted admin
    const admin_id = try dao.createUser(allocator, "restricted-admin");
    defer dao.deleteUser(admin_id) catch {};
    
    try dao.setUserAdmin(admin_id, true);
    try dao.setUserRestricted(admin_id, true);
    
    const repo_id = try dao.createRepository(allocator, "private-repo", 1, .user, true);
    defer dao.deleteRepository(repo_id) catch {};
    
    // Restricted admin should not have access to private repos
    const perm = try cache.getOrCompute(&dao, admin_id, repo_id);
    try std.testing.expectEqual(AccessMode.None, perm.access_mode);
}

test "unit-level permissions" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    const user_id = try dao.createUser(allocator, "contributor");
    defer dao.deleteUser(user_id) catch {};
    
    const repo_id = try dao.createRepository(allocator, "project", 1, .user, false);
    defer dao.deleteRepository(repo_id) catch {};
    
    // Grant write access to issues only
    try dao.addCollaborationWithUnits(repo_id, user_id, "read", 
        \\{"issues": "write", "pulls": "read", "wiki": "none"}
    );
    
    const perm = try cache.getOrCompute(&dao, user_id, repo_id);
    try std.testing.expect(perm.canWrite(.Issues));
    try std.testing.expect(perm.canRead(.PullRequests));
    try std.testing.expect(!perm.canRead(.Wiki));
}

test "permission caching" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    const user_id = try dao.createUser(allocator, "cached-user");
    defer dao.deleteUser(user_id) catch {};
    
    const repo_id = try dao.createRepository(allocator, "cached-repo", user_id, .user, false);
    defer dao.deleteRepository(repo_id) catch {};
    
    // First call - loads from database
    const perm1 = try cache.getOrCompute(&dao, user_id, repo_id);
    try std.testing.expectEqual(AccessMode.Owner, perm1.access_mode);
    
    // Second call - should use cache
    const perm2 = try cache.getOrCompute(&dao, user_id, repo_id);
    try std.testing.expectEqual(perm1.access_mode, perm2.access_mode);
}

test "fail closed on errors" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    // Test with non-existent repository
    const perm = try cache.getOrCompute(&dao, 123, 999999);
    try std.testing.expectEqual(AccessMode.None, perm.access_mode);
    
    // Test with deleted user
    const user_id = try dao.createUser(allocator, "deleted-user");
    try dao.deleteUser(user_id);
    
    const repo_id = try dao.createRepository(allocator, "active-repo", 1, .user, false);
    defer dao.deleteRepository(repo_id) catch {};
    
    const perm2 = try cache.getOrCompute(&dao, user_id, repo_id);
    try std.testing.expectEqual(AccessMode.None, perm2.access_mode);
}
```

## Performance Considerations

1. **Request-Level Caching**: Use `PermissionCache` for the entire request lifecycle
2. **Pre-computed Access Table**: Maintain `access` table via triggers or background jobs
3. **Efficient Queries**: Single query to `access` table, then lazy-load team data only if needed
4. **Early Returns**: Check common cases first (deleted, owner, admin)

## Integration Points

```zig
// HTTP handler integration
fn handleGitOperation(r: zap.Request, ctx: *Context) !void {
    const cache = try PermissionCache.init(ctx.allocator);
    defer cache.deinit();
    
    const user_id = try getUserFromRequest(r);
    const repo_id = try getRepoFromPath(r.path);
    
    if (!try canReadRepository(&cache, ctx.dao, user_id, repo_id)) {
        r.setStatus(.forbidden);
        try r.sendBody("Access denied");
        return;
    }
    
    // Process git operation...
}

// API endpoint integration
fn handleCreateIssue(r: zap.Request, ctx: *Context) !void {
    const cache = try PermissionCache.init(ctx.allocator);
    defer cache.deinit();
    
    const user_id = try requireAuth(r);
    const repo_id = try getRepoFromPath(r.path);
    
    if (!try canCreateIssue(&cache, ctx.dao, user_id, repo_id)) {
        r.setStatus(.forbidden);
        try r.sendBody("Cannot create issues in this repository");
        return;
    }
    
    // Create issue...
}
```

## Migration Notes

1. **Initial Deployment**: Start with basic permissions, add teams/units incrementally
2. **Access Table Population**: Run background job to populate pre-computed access
3. **Permission Audit**: Log all permission checks initially, reduce to errors only in production
4. **Backwards Compatibility**: Support simple read/write before full unit permissions

## Future Enhancements

1. **Deploy Key Support**: Separate permission system for deploy keys
2. **OAuth Scopes**: Integration with OAuth token scopes
3. **Branch Protection**: Per-branch permission rules
4. **IP Restrictions**: Geographic or network-based access control
5. **Time-Based Access**: Temporary elevated permissions