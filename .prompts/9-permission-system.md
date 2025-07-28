# Permission System Implementation

## Overview

Implement a comprehensive permission checking system for repository access control in the Plue application, following Gitea's production-proven patterns. This system will serve as the authorization foundation for all git operations, supporting individual users, organizations, teams, and fine-grained unit-level permissions with proper handling of edge cases like archived repositories, mirrors, and restricted users.

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

### 2. Unit-Level Permissions with Public Access Support

Support fine-grained permissions per repository unit with separate access modes for different user types:
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
    units: ?std.EnumMap(UnitType, AccessMode),
    everyone_access_mode: std.EnumMap(UnitType, AccessMode),   // For signed-in users
    anonymous_access_mode: std.EnumMap(UnitType, AccessMode),  // For anonymous users
    
    pub fn unitAccessMode(self: *const Permission, unit_type: UnitType) AccessMode {
        // Admin/Owner mode overrides unit-specific permissions
        if (self.access_mode.atLeast(.Admin)) {
            return self.access_mode;
        }
        
        // If units map is null (admin override), return general access
        if (self.units == null) {
            return self.access_mode;
        }
        
        // Get unit-specific permission or fall back to general access
        const unit_mode = self.units.?.get(unit_type) orelse self.access_mode;
        const everyone_mode = self.everyone_access_mode.get(unit_type) orelse .None;
        const anonymous_mode = self.anonymous_access_mode.get(unit_type) orelse .None;
        
        return @max(unit_mode, @max(everyone_mode, anonymous_mode));
    }
    
    pub fn canAccess(self: *const Permission, unit_type: UnitType, required_mode: AccessMode) bool {
        return self.unitAccessMode(unit_type).atLeast(required_mode);
    }
    
    pub fn canRead(self: *const Permission, unit_type: UnitType) bool {
        return self.canAccess(unit_type, .Read);
    }
    
    pub fn canWrite(self: *const Permission, unit_type: UnitType) bool {
        return self.canAccess(unit_type, .Write);
    }
};
```

### 3. Visibility Types

```zig
pub const Visibility = enum {
    Public,     // Visible to everyone
    Limited,    // Visible to signed-in users (not restricted users)
    Private,    // Visible only to members
};
```

### 4. Request-Level Permission Cache

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

### 5. Error Types

```zig
pub const PermissionError = error{
    RepositoryNotFound,
    UserNotFound,
    DatabaseError,
    InvalidInput,
    RepositoryArchived,    // Write denied to archived repos
    RepositoryMirror,      // Write denied to mirrors
    OrganizationPrivate,   // Access denied to private org
    UserRestricted,        // Restricted user access denied
} || error{OutOfMemory};
```

### 6. Visibility Check Function

```zig
pub fn hasOrgOrUserVisible(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    owner_id: i64,
    owner_type: OwnerType,
    owner_visibility: Visibility,
    requesting_user: ?i64,
) !bool {
    // Anonymous users only see public entities
    if (requesting_user == null) {
        return owner_visibility == .Public;
    }
    
    const user_id = requesting_user.?;
    
    // Load user to check admin status
    const user = try dao.getUser(allocator, user_id);
    defer allocator.free(user.name);
    
    // Admins and self always have visibility
    if (user.is_admin or (owner_type == .user and owner_id == user_id)) {
        return true;
    }
    
    // Check organization membership
    if (owner_type == .organization) {
        // Private orgs require membership
        if (owner_visibility == .Private) {
            return try dao.isOrganizationMember(owner_id, user_id);
        }
        
        // Limited visibility orgs are hidden from restricted users unless they're members
        if (owner_visibility == .Limited and user.is_restricted) {
            return try dao.isOrganizationMember(owner_id, user_id);
        }
    }
    
    return true;
}
```

### 7. Core Permission Loading Function

Implement the main permission loading logic with all edge cases:
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
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };
    
    // Check if repository exists and is not deleted
    const repo = dao.getRepository(allocator, repo_id) catch |err| switch (err) {
        error.NotFound => return PermissionError.RepositoryNotFound,
        else => {
            std.log.err("Permission check failed for repo {d}: {}", .{ repo_id, err });
            return permission; // Fail closed
        },
    };
    defer allocator.free(repo.name);
    
    if (repo.is_deleted) {
        return permission;
    }
    
    // Load repository owner for visibility checks
    const owner = switch (repo.owner_type) {
        .user => try dao.getUser(allocator, repo.owner_id),
        .organization => try dao.getOrganization(allocator, repo.owner_id),
    };
    defer allocator.free(owner.name);
    
    // Handle anonymous users
    if (user_id == null) {
        // Check if owner is visible to anonymous users
        if (!try hasOrgOrUserVisible(allocator, dao, repo.owner_id, repo.owner_type, owner.visibility, null)) {
            return permission;
        }
        
        if (!repo.is_private) {
            permission.access_mode = .Read;
            // Enable read access for all units except settings
            var iter = permission.units.?.iterator();
            while (iter.next()) |entry| {
                if (entry.key != .Settings) {
                    permission.units.?.put(entry.key, .Read);
                    permission.anonymous_access_mode.put(entry.key, .Read);
                }
            }
        }
        return permission;
    }
    
    const uid = user_id.?;
    
    // Check if user exists and is active
    const user = dao.getUser(allocator, uid) catch {
        return permission; // Fail closed
    };
    defer allocator.free(user.name);
    
    if (user.is_deleted or !user.is_active or user.prohibit_login) {
        return permission;
    }
    
    // Check owner visibility
    if (!try hasOrgOrUserVisible(allocator, dao, repo.owner_id, repo.owner_type, owner.visibility, uid)) {
        // Special case: check if user is a collaborator despite org visibility
        const is_collab = try dao.isCollaborator(uid, repo_id);
        if (!is_collab) {
            return permission;
        }
    }
    
    // Check if user is repository owner
    if (repo.owner_id == uid and repo.owner_type == .user) {
        permission.access_mode = .Owner;
        permission.units = null; // Admin override - no unit restrictions
        return permission;
    }
    
    // Check if user is admin
    if (user.is_admin) {
        // Even admins can't access truly private orgs they're not members of
        if (repo.owner_type == .organization and owner.visibility == .Private) {
            if (!try dao.isOrganizationMember(repo.owner_id, uid)) {
                // Continue to check normal permissions
            } else {
                permission.access_mode = .Owner; // Admins get owner access
                permission.units = null; // Admin override
                return permission;
            }
        } else {
            permission.access_mode = .Owner;
            permission.units = null;
            return permission;
        }
    }
    
    // Handle restricted users
    if (user.is_restricted) {
        // Restricted users can't access limited visibility organizations
        if (repo.owner_type == .organization and owner.visibility == .Limited) {
            if (!try dao.isOrganizationMember(repo.owner_id, uid)) {
                return permission; // Deny access
            }
        }
        
        // Restricted users get no default read access to public repos
        // They must have explicit permissions
    }
    
    // Check pre-computed access table first (performance optimization)
    if (try dao.getAccessLevel(uid, repo_id)) |access| {
        permission.access_mode = std.meta.stringToEnum(AccessMode, access.mode) orelse .None;
    }
    
    // Check organization and team permissions
    if (repo.owner_type == .organization) {
        const team_perm = try checkOrgTeamPermission(allocator, dao, repo.owner_id, uid, repo_id);
        
        // Merge permissions taking the maximum
        permission.access_mode = @max(permission.access_mode, team_perm.access_mode);
        
        if (team_perm.units) |team_units| {
            if (permission.units) |*units| {
                var iter = team_units.iterator();
                while (iter.next()) |entry| {
                    const current = units.get(entry.key) orelse .None;
                    units.put(entry.key, @max(current, entry.value.*));
                }
            } else {
                // Team gave admin access
                permission.units = null;
            }
        } else if (team_perm.access_mode.atLeast(.Admin)) {
            // Team gave admin access
            permission.units = null;
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
    if (!repo.is_private and permission.access_mode == .None and !user.is_restricted) {
        permission.access_mode = .Read;
        // Enable read access for public units
        if (permission.units) |*units| {
            var iter = units.iterator();
            while (iter.next()) |entry| {
                if (entry.key != .Settings and entry.value.* == .None) {
                    units.put(entry.key, .Read);
                    permission.everyone_access_mode.put(entry.key, .Read);
                }
            }
        }
    }
    
    // Apply repository state restrictions
    if (repo.is_archived and permission.access_mode.atLeast(.Write)) {
        std.log.warn("Downgrading write access to read for archived repository {d}", .{repo_id});
        permission.access_mode = .Read;
        
        // Downgrade all unit permissions to read
        if (permission.units) |*units| {
            var iter = units.iterator();
            while (iter.next()) |entry| {
                if (entry.value.*.atLeast(.Write)) {
                    units.put(entry.key, .Read);
                }
            }
        }
    }
    
    if (repo.is_mirror and permission.access_mode.atLeast(.Write)) {
        std.log.warn("Downgrading write access to read for mirror repository {d}", .{repo_id});
        permission.access_mode = .Read;
        
        // Downgrade all unit permissions to read
        if (permission.units) |*units| {
            var iter = units.iterator();
            while (iter.next()) |entry| {
                if (entry.value.*.atLeast(.Write)) {
                    units.put(entry.key, .Read);
                }
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
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };
    
    // Get user's teams in this organization that have access to this repository
    const teams = try dao.getUserRepoTeams(allocator, org_id, user_id, repo_id);
    defer teams.deinit();
    
    // Check for admin teams first (they get full access immediately)
    for (teams.items) |team| {
        if (team.hasAdminAccess()) {
            permission.access_mode = .Owner;  // Admin teams get Owner access
            permission.units = null; // Clear units map - admin overrides everything
            return permission;
        }
    }
    
    // Process each unit across all teams using Gitea's algorithm
    var unit_iter = std.enums.values(UnitType);
    while (unit_iter.next()) |unit_type| {
        var max_unit_access = AccessMode.None;
        
        for (teams.items) |team| {
            // Get team's access mode for this unit
            const team_unit_mode = try getTeamUnitAccessMode(allocator, dao, team, unit_type);
            max_unit_access = @max(max_unit_access, team_unit_mode);
        }
        
        if (permission.units) |*units| {
            units.put(unit_type, max_unit_access);
        }
        
        // Update overall access mode to be at least the max unit access
        if (max_unit_access > permission.access_mode) {
            permission.access_mode = max_unit_access;
        }
    }
    
    return permission;
}

fn getTeamUnitAccessMode(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    team: Team,
    unit_type: UnitType,
) !AccessMode {
    // Check if team has unit-specific permissions
    if (team.units) |units_json| {
        // Parse JSON to find unit-specific access
        // This is a simplified version - implement proper JSON parsing
        _ = units_json;
        _ = allocator;
    }
    
    // Fall back to team's general access mode
    return std.meta.stringToEnum(AccessMode, team.access_mode) orelse .None;
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

### 8. Helper Functions for Common Checks

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
    
    // Check for archived/mirror restrictions
    const repo = try dao.getRepository(cache.allocator, repo_id);
    defer cache.allocator.free(repo.name);
    
    if (repo.is_archived or repo.is_mirror) {
        return false;
    }
    
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
    
    // For write operations, check repository state
    if (required_mode.atLeast(.Write)) {
        const repo = try dao.getRepository(cache.allocator, repo_id);
        defer cache.allocator.free(repo.name);
        
        if (repo.is_archived or repo.is_mirror) {
            return false;
        }
    }
    
    return perm.canAccess(unit_type, required_mode);
}

// Special checks for specific operations
pub fn canCreateIssue(cache: *PermissionCache, dao: *DataAccessObject, user_id: i64, repo_id: i64) !bool {
    return canAccessUnit(cache, dao, user_id, repo_id, .Issues, .Write);
}

pub fn canMergePullRequest(cache: *PermissionCache, dao: *DataAccessObject, user_id: i64, repo_id: i64) !bool {
    const perm = try cache.getOrCompute(dao, user_id, repo_id);
    
    // Check repository state
    const repo = try dao.getRepository(cache.allocator, repo_id);
    defer cache.allocator.free(repo.name);
    
    if (repo.is_archived or repo.is_mirror) {
        return false;
    }
    
    // Merging requires write access to code or admin/owner status
    return perm.canAccess(.Code, .Write) or perm.access_mode.atLeast(.Admin);
}
```

### 9. Security Middleware Pattern

```zig
pub fn requireRepositoryAccess(
    comptime required_mode: AccessMode,
    comptime unit_type: UnitType,
) type {
    return struct {
        pub fn middleware(r: zap.Request, ctx: *Context, next: anytype) !void {
            const cache = try PermissionCache.init(ctx.allocator);
            defer cache.deinit();
            
            const user_id = getUserFromRequest(r) catch null;
            const repo_id = try getRepoFromPath(r.path);
            
            // Load repository to check state
            const repo = ctx.dao.getRepository(ctx.allocator, repo_id) catch |err| switch (err) {
                error.NotFound => {
                    r.setStatus(.not_found);
                    try r.sendBody("Repository not found");
                    return;
                },
                else => return err,
            };
            defer ctx.allocator.free(repo.name);
            
            // Block archived repos for write operations
            if (repo.is_archived and required_mode.atLeast(.Write)) {
                r.setStatus(.method_not_allowed);
                try r.sendBody("Repository is archived");
                return;
            }
            
            // Block mirror repos for write operations  
            if (repo.is_mirror and required_mode.atLeast(.Write)) {
                r.setStatus(.method_not_allowed);
                try r.sendBody("Mirror repository is read-only");
                return;
            }
            
            const has_access = canAccessUnit(&cache, ctx.dao, user_id, repo_id, unit_type, required_mode) catch false;
            
            if (!has_access) {
                // Security: Return 404 instead of 403 to avoid leaking repository existence
                r.setStatus(.not_found);
                try r.sendBody("Repository not found");
                return;
            }
            
            // Call next handler
            try next(r, ctx);
        }
    };
}
```

## Database Schema Requirements

```sql
-- Owner types enum
CREATE TYPE owner_type AS ENUM ('user', 'organization');

-- Users table
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    is_admin BOOLEAN DEFAULT FALSE,
    is_restricted BOOLEAN DEFAULT FALSE,  -- Restricted users have limited access
    is_deleted BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    prohibit_login BOOLEAN DEFAULT FALSE,
    visibility VARCHAR(20) DEFAULT 'public' CHECK (visibility IN ('public', 'limited', 'private')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Organizations
CREATE TABLE organizations (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    visibility VARCHAR(20) DEFAULT 'public' CHECK (visibility IN ('public', 'limited', 'private')),
    max_repo_creation INTEGER DEFAULT -1,  -- -1 = unlimited
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
    is_fork BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    visibility VARCHAR(20) DEFAULT 'public' CHECK (visibility IN ('public', 'limited', 'private')),
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

-- Organization memberships
CREATE TABLE org_users (
    org_id BIGINT REFERENCES organizations(id) ON DELETE CASCADE,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    is_public BOOLEAN DEFAULT FALSE,  -- Whether membership is publicly visible
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (org_id, user_id)
);

-- Indexes for performance
CREATE INDEX idx_repositories_owner ON repositories(owner_id, owner_type) WHERE NOT is_deleted;
CREATE INDEX idx_repositories_is_archived ON repositories(is_archived) WHERE NOT is_deleted;
CREATE INDEX idx_repositories_is_mirror ON repositories(is_mirror) WHERE NOT is_deleted;
CREATE INDEX idx_team_users_user ON team_users(user_id);
CREATE INDEX idx_team_repos_repo ON team_repos(repo_id);
CREATE INDEX idx_collaborations_user_repo ON collaborations(user_id, repo_id);
CREATE INDEX idx_access_lookup ON access(user_id, repo_id);
CREATE INDEX idx_user_is_restricted ON users(is_restricted) WHERE NOT is_deleted;
CREATE INDEX idx_org_users_user ON org_users(user_id);
CREATE INDEX idx_org_users_org ON org_users(org_id);
```

## Security Considerations

1. **Fail-Safe Defaults**: 
   - Always start with `AccessMode.None`
   - Database errors result in access denial
   - Invalid data results in access denial

2. **No Permission Elevation**:
   - Restricted users cannot gain admin access
   - Deleted entities result in immediate denial
   - Mirror and archived repositories enforce read-only

3. **Visibility Enforcement**:
   - Private organizations hide all repositories from non-members
   - Limited organizations are hidden from restricted users
   - Anonymous users only see public entities

4. **Audit Logging**:
   - Log successful permission loads at DEBUG level
   - Log errors at ERROR level without exposing sensitive data
   - Log permission downgrades (archive/mirror) at WARN level
   - Do NOT log denied access attempts (following Gitea pattern)

5. **Race Condition Handling**:
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

test "archived repository write denial" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    const owner_id = try dao.createUser(allocator, "owner");
    defer dao.deleteUser(owner_id) catch {};
    
    const repo_id = try dao.createRepository(allocator, "archived-repo", owner_id, .user, false);
    defer dao.deleteRepository(repo_id) catch {};
    
    // Archive the repository
    try dao.setRepositoryArchived(repo_id, true);
    
    // Owner should have read-only access to archived repo
    const perm = try cache.getOrCompute(&dao, owner_id, repo_id);
    try std.testing.expectEqual(AccessMode.Read, perm.access_mode);
    try std.testing.expect(!perm.canWrite(.Code));
}

test "mirror repository write denial" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    const owner_id = try dao.createUser(allocator, "owner");
    defer dao.deleteUser(owner_id) catch {};
    
    const repo_id = try dao.createMirrorRepository(allocator, "mirror-repo", owner_id, .user, "https://github.com/example/repo");
    defer dao.deleteRepository(repo_id) catch {};
    
    // Owner should have read-only access to mirror
    const perm = try cache.getOrCompute(&dao, owner_id, repo_id);
    try std.testing.expectEqual(AccessMode.Read, perm.access_mode);
    
    // Test write operations are denied
    try std.testing.expect(!try canWriteRepository(&cache, &dao, owner_id, repo_id));
}

test "restricted user limited organization access" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    // Create limited visibility organization
    const org_id = try dao.createOrganization(allocator, "limited-org", .Limited);
    defer dao.deleteOrganization(org_id) catch {};
    
    // Create restricted user
    const user_id = try dao.createUser(allocator, "restricted-user");
    defer dao.deleteUser(user_id) catch {};
    try dao.setUserRestricted(user_id, true);
    
    // Create public repo in limited org
    const repo_id = try dao.createRepository(allocator, "public-repo", org_id, .organization, false);
    defer dao.deleteRepository(repo_id) catch {};
    
    // Restricted user should have no access to limited org repos
    const perm = try cache.getOrCompute(&dao, user_id, repo_id);
    try std.testing.expectEqual(AccessMode.None, perm.access_mode);
    
    // Add user as org member
    try dao.addOrganizationMember(org_id, user_id);
    cache.cache.clearRetainingCapacity(); // Clear cache
    
    // Now they should have access
    const perm2 = try cache.getOrCompute(&dao, user_id, repo_id);
    try std.testing.expectEqual(AccessMode.Read, perm2.access_mode);
}

test "private organization visibility" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    // Create private organization
    const org_id = try dao.createOrganization(allocator, "private-org", .Private);
    defer dao.deleteOrganization(org_id) catch {};
    
    // Create users
    const member_id = try dao.createUser(allocator, "member");
    defer dao.deleteUser(member_id) catch {};
    
    const non_member_id = try dao.createUser(allocator, "non-member");
    defer dao.deleteUser(non_member_id) catch {};
    
    const admin_id = try dao.createUser(allocator, "admin");
    defer dao.deleteUser(admin_id) catch {};
    try dao.setUserAdmin(admin_id, true);
    
    // Add member to org
    try dao.addOrganizationMember(org_id, member_id);
    
    // Create public repo in private org
    const repo_id = try dao.createRepository(allocator, "public-repo", org_id, .organization, false);
    defer dao.deleteRepository(repo_id) catch {};
    
    // Non-member should have no access
    const perm1 = try cache.getOrCompute(&dao, non_member_id, repo_id);
    try std.testing.expectEqual(AccessMode.None, perm1.access_mode);
    
    // Member should have read access
    const perm2 = try cache.getOrCompute(&dao, member_id, repo_id);
    try std.testing.expectEqual(AccessMode.Read, perm2.access_mode);
    
    // Admin not in org should have no access
    const perm3 = try cache.getOrCompute(&dao, admin_id, repo_id);
    try std.testing.expectEqual(AccessMode.None, perm3.access_mode);
}

test "admin team permission override" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    // Create organization
    const org_id = try dao.createOrganization(allocator, "test-org", .Public);
    defer dao.deleteOrganization(org_id) catch {};
    
    // Create admin team
    const admin_team_id = try dao.createTeam(allocator, org_id, "admins", "admin");
    defer dao.deleteTeam(admin_team_id) catch {};
    try dao.setTeamCanCreateOrgRepo(admin_team_id, true);
    
    // Create regular team with limited permissions
    const dev_team_id = try dao.createTeam(allocator, org_id, "developers", "write");
    defer dao.deleteTeam(dev_team_id) catch {};
    
    // Create user and add to both teams
    const user_id = try dao.createUser(allocator, "developer");
    defer dao.deleteUser(user_id) catch {};
    
    try dao.addTeamMember(admin_team_id, user_id);
    try dao.addTeamMember(dev_team_id, user_id);
    
    // Create repository
    const repo_id = try dao.createRepository(allocator, "team-repo", org_id, .organization, true);
    defer dao.deleteRepository(repo_id) catch {};
    
    // Add repo to both teams
    try dao.addTeamRepository(admin_team_id, repo_id);
    try dao.addTeamRepository(dev_team_id, repo_id);
    
    // User should get owner access from admin team
    const perm = try cache.getOrCompute(&dao, user_id, repo_id);
    try std.testing.expectEqual(AccessMode.Owner, perm.access_mode);
    try std.testing.expect(perm.units == null); // Admin override
}

test "unit permission inheritance from teams" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    // Create organization
    const org_id = try dao.createOrganization(allocator, "test-org", .Public);
    defer dao.deleteOrganization(org_id) catch {};
    
    // Create teams with different unit permissions
    const issues_team_id = try dao.createTeamWithUnits(allocator, org_id, "issue-triagers", "read",
        \\{"issues": "write", "pulls": "read"}
    );
    defer dao.deleteTeam(issues_team_id) catch {};
    
    const code_team_id = try dao.createTeamWithUnits(allocator, org_id, "code-reviewers", "read",
        \\{"code": "write", "pulls": "write"}  
    );
    defer dao.deleteTeam(code_team_id) catch {};
    
    // Create user and add to both teams
    const user_id = try dao.createUser(allocator, "developer");
    defer dao.deleteUser(user_id) catch {};
    
    try dao.addTeamMember(issues_team_id, user_id);
    try dao.addTeamMember(code_team_id, user_id);
    
    // Create repository
    const repo_id = try dao.createRepository(allocator, "project", org_id, .organization, false);
    defer dao.deleteRepository(repo_id) catch {};
    
    // Add repo to both teams
    try dao.addTeamRepository(issues_team_id, repo_id);
    try dao.addTeamRepository(code_team_id, repo_id);
    
    // User should get combined permissions
    const perm = try cache.getOrCompute(&dao, user_id, repo_id);
    try std.testing.expect(perm.canWrite(.Issues));  // From issues team
    try std.testing.expect(perm.canWrite(.Code));    // From code team
    try std.testing.expect(perm.canWrite(.PullRequests)); // Max from both teams
}

test "everyone vs anonymous access modes" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();
    
    // Create public repository with custom unit settings
    const owner_id = try dao.createUser(allocator, "owner");
    defer dao.deleteUser(owner_id) catch {};
    
    const repo_id = try dao.createRepository(allocator, "public-repo", owner_id, .user, false);
    defer dao.deleteRepository(repo_id) catch {};
    
    // Set different permissions for anonymous vs signed-in users
    try dao.setRepositoryUnitPermissions(repo_id, 
        \\{
        \\  "anonymous": {"code": "read", "issues": "none"},
        \\  "everyone": {"code": "read", "issues": "read"}
        \\}
    );
    
    // Anonymous user should not see issues
    const anon_perm = try cache.getOrCompute(&dao, null, repo_id);
    try std.testing.expect(anon_perm.canRead(.Code));
    try std.testing.expect(!anon_perm.canRead(.Issues));
    
    // Signed-in user should see issues
    const user_id = try dao.createUser(allocator, "viewer");
    defer dao.deleteUser(user_id) catch {};
    
    const user_perm = try cache.getOrCompute(&dao, user_id, repo_id);
    try std.testing.expect(user_perm.canRead(.Code));
    try std.testing.expect(user_perm.canRead(.Issues));
}

test "permission caching doesn't leak between requests" {
    const allocator = std.testing.allocator;
    
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available, skipping", .{});
        return;
    };
    defer dao.deinit();
    
    const owner_id = try dao.createUser(allocator, "owner");
    defer dao.deleteUser(owner_id) catch {};
    
    const repo_id = try dao.createRepository(allocator, "test-repo", owner_id, .user, false);
    defer dao.deleteRepository(repo_id) catch {};
    
    // First request
    {
        var cache1 = PermissionCache.init(allocator);
        defer cache1.deinit();
        
        const perm1 = try cache1.getOrCompute(&dao, owner_id, repo_id);
        try std.testing.expectEqual(AccessMode.Owner, perm1.access_mode);
    }
    
    // Second request - should not have cached data
    {
        var cache2 = PermissionCache.init(allocator);
        defer cache2.deinit();
        
        // Cache should be empty
        try std.testing.expect(cache2.cache.count() == 0);
        
        const perm2 = try cache2.getOrCompute(&dao, owner_id, repo_id);
        try std.testing.expectEqual(AccessMode.Owner, perm2.access_mode);
    }
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
5. **Unit Permission Optimization**: Only compute unit permissions when needed

## Integration Points

```zig
// HTTP handler integration
fn handleGitOperation(r: zap.Request, ctx: *Context) !void {
    const middleware = requireRepositoryAccess(.Read, .Code);
    try middleware.middleware(r, ctx, actualHandler);
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

// Git protocol integration
fn handleGitReceivePack(r: zap.Request, ctx: *Context) !void {
    const cache = try PermissionCache.init(ctx.allocator);
    defer cache.deinit();
    
    const user_id = try getGitAuthUser(r);
    const repo_id = try getRepoFromPath(r.path);
    
    // Check write permission
    const perm = try cache.getOrCompute(ctx.dao, user_id, repo_id);
    
    if (!perm.canWrite(.Code)) {
        r.setStatus(.forbidden);
        try r.sendBody("Permission denied");
        return;
    }
    
    // Check repository state
    const repo = try ctx.dao.getRepository(ctx.allocator, repo_id);
    defer ctx.allocator.free(repo.name);
    
    if (repo.is_archived) {
        r.setStatus(.forbidden);
        try r.sendBody("Cannot push to archived repository");
        return;
    }
    
    if (repo.is_mirror) {
        r.setStatus(.forbidden);
        try r.sendBody("Cannot push to mirror repository");
        return;
    }
    
    // Process git push...
}
```

## Migration Notes

1. **Initial Deployment**: 
   - Start with basic permissions (no teams/units)
   - Add `visibility` columns with default 'public'
   - Populate `access` table for existing collaborations

2. **Organization Migration**:
   - Create organizations from existing user groups
   - Migrate repository ownership
   - Create default teams (Owners, Members)

3. **Unit Permission Migration**:
   - Start with all units having same access as repository
   - Gradually enable unit-specific permissions

4. **Performance Optimization**:
   - Run background job to populate `access` table
   - Add database indexes incrementally
   - Monitor query performance

## Future Enhancements

1. **Deploy Key Support**: Separate permission system for deploy keys
2. **OAuth Scopes**: Integration with OAuth token scopes
3. **Branch Protection**: Per-branch permission rules
4. **IP Restrictions**: Geographic or network-based access control
5. **Time-Based Access**: Temporary elevated permissions
6. **Audit Log Integration**: Comprehensive permission check logging
7. **WebAuthn Support**: Hardware key authentication
8. **External Group Sync**: LDAP/SAML group synchronization