# Implement Enterprise Permission System with Organization/Team Support (ENHANCED WITH GITEA PRODUCTION PATTERNS)

<task_definition>
Implement a comprehensive enterprise-grade permission system for repository access control that provides organization/team support, unit-level permissions, visibility patterns, and request-level caching. This system handles complex permission hierarchies, team-based access control, fine-grained repository permissions, and Git protocol authorization with production-grade security and performance following Gitea's battle-tested patterns.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: Database models, Configuration system
- **Location**: `src/auth/permissions.zig`, `src/auth/teams.zig`, `src/auth/units.zig`
- **Database**: PostgreSQL with advanced indexing for complex queries
- **Security**: Multi-tier RBAC with organization/team/unit-level permissions
- **Memory**: Request-level caching with invalidation cascades, zero allocator storage in structs
- **🆕 Organizations**: Full organization support with team hierarchies
- **🆕 Unit Permissions**: Fine-grained unit-level access control (issues, PRs, wiki, etc.)
- **🆕 Visibility Patterns**: Complex visibility rules with inheritance
- **Integration**: SSH server, HTTP Git server, API endpoints, webhook systems

</technical_requirements>

<business_context>

Plue requires an enterprise-grade permission system to support:

- **🆕 Organization Management**: Multi-tier organization hierarchies with team structures
- **🆕 Team-Based Access**: Granular team permissions with inheritance patterns
- **🆕 Unit-Level Permissions**: Fine-grained control over repository features (issues, PRs, wiki, releases, packages)
- **🆕 Complex Visibility**: Public, private, internal, and limited visibility with organization-specific rules
- **Repository Access Control**: Repository-level permissions with collaborative features
- **Git Protocol Authorization**: SSH and HTTP Git operations with team-aware routing
- **Admin Operations**: Multi-level administration (system, organization, repository)
- **API Access Control**: Context-aware API endpoint authorization
- **🆕 Audit & Compliance**: Comprehensive audit trails with organization-level reporting
- **🆕 Integration Patterns**: Webhook permissions, external authentication, LDAP/SAML integration

The system must scale to thousands of organizations, teams, and repositories while maintaining sub-millisecond permission checks through request-level caching and smart invalidation patterns following Gitea's production architecture.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

**🆕 Enterprise Permission System Data Structures (Gitea Production Patterns)**:

```zig
// Core permission levels with hierarchy
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

// Unit-level permissions for fine-grained control
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

// Visibility types matching Gitea patterns
pub const Visibility = enum {
    Public,     // Visible to everyone
    Limited,    // Visible to signed-in users (not restricted users)
    Private,    // Visible only to members
};

// Organization roles with inheritance
pub const OrgRole = enum(u8) {
    None = 0,
    Member = 1,
    Admin = 2,
    Owner = 3,
    
    pub fn atLeast(self: OrgRole, required: OrgRole) bool {
        return @intFromEnum(self) >= @intFromEnum(required);
    }
};

// Team permissions with repository access
pub const TeamPermission = struct {
    access_mode: AccessMode,
    units: ?std.EnumMap(UnitType, AccessMode),
    
    pub fn unitAccessMode(self: *const TeamPermission, unit_type: UnitType) AccessMode {
        if (self.access_mode.atLeast(.Admin)) {
            return self.access_mode;
        }
        
        if (self.units == null) {
            return self.access_mode;
        }
        
        return self.units.?.get(unit_type) orelse self.access_mode;
    }
};
```

**🆕 Expected Permission Resolution Scenarios**:

```zig
// Multi-context permission checking
const context = PermissionContext{
    .user_id = user_id,
    .repository_id = repo_id,
    .organization_id = org_id,
    .request_id = request_id, // For caching
};

// Repository permission with team inheritance
const permission = try permission_checker.checkUserRepoPermission(allocator, context);

// Unit-level access control
const can_view_issues = permission.canAccess(.Issues, .Read);
const can_manage_wiki = permission.canAccess(.Wiki, .Admin);

// Team-based authorization
const team_permissions = try permission_checker.getUserTeamPermissions(allocator, user_id, org_id);

// Complex visibility checks
const repo_visible = try permission_checker.hasOrgOrUserVisible(allocator, user_id, owner_id, .Organization);

// Git protocol authorization
const git_auth = GitAuthContext{
    .user_id = user_id,
    .repository_path = "org/repo.git",
    .operation = .Push,
    .branch = "main",
};
const can_push = try permission_checker.authorizeGitOperation(allocator, git_auth);
```

**🆕 Database Schema Requirements**:

```sql
-- Organizations table
CREATE TABLE organizations (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(40) UNIQUE NOT NULL,
    visibility INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Teams table with hierarchy support
CREATE TABLE teams (
    id BIGSERIAL PRIMARY KEY,
    org_id BIGINT NOT NULL REFERENCES organizations(id),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    access_mode INTEGER NOT NULL DEFAULT 1,
    parent_id BIGINT REFERENCES teams(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(org_id, name)
);

-- Team members
CREATE TABLE team_members (
    id BIGSERIAL PRIMARY KEY,
    team_id BIGINT NOT NULL REFERENCES teams(id),
    user_id BIGINT NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(team_id, user_id)
);

-- Team repository access
CREATE TABLE team_repos (
    id BIGSERIAL PRIMARY KEY,
    team_id BIGINT NOT NULL REFERENCES teams(id),
    repo_id BIGINT NOT NULL REFERENCES repositories(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(team_id, repo_id)
);

-- Team unit permissions
CREATE TABLE team_units (
    id BIGSERIAL PRIMARY KEY,
    team_id BIGINT NOT NULL REFERENCES teams(id),
    unit_type INTEGER NOT NULL,
    access_mode INTEGER NOT NULL,
    UNIQUE(team_id, unit_type)
);

-- Organization members
CREATE TABLE org_members (
    id BIGSERIAL PRIMARY KEY,
    org_id BIGINT NOT NULL REFERENCES organizations(id),
    user_id BIGINT NOT NULL REFERENCES users(id),
    role INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(org_id, user_id)
);

-- Repository units configuration
CREATE TABLE repo_units (
    id BIGSERIAL PRIMARY KEY,
    repo_id BIGINT NOT NULL REFERENCES repositories(id),
    unit_type INTEGER NOT NULL,
    access_mode INTEGER NOT NULL DEFAULT 1,
    UNIQUE(repo_id, unit_type)
);
```

</input>

<expected_output>

**🆕 Complete Enterprise Permission System Providing**:

1. **Multi-Tier Permission Checker**: Core authorization with organization/team/unit awareness
2. **Team Management System**: Team hierarchies with permission inheritance
3. **Unit-Level Access Control**: Fine-grained feature-level permissions
4. **Organization Role Management**: Complex organization structures with role inheritance
5. **Advanced Visibility Engine**: Complex visibility patterns with organization rules
6. **Repository Access Control**: Enhanced repository permissions with team integration
7. **Git Protocol Authorization**: Team-aware SSH and HTTP Git operation authorization
8. **Request-Level Caching**: High-performance caching with cascade invalidation
9. **Comprehensive Audit System**: Multi-level audit trails with organization reporting
10. **Performance Optimization**: Sub-millisecond checks with smart caching patterns

**🆕 Core Permission System API**:

```zig
pub const PermissionChecker = struct {
    dao: *DataAccessObject,
    cache: *PermissionCache,
    
    pub fn init(allocator: std.mem.Allocator, dao: *DataAccessObject) PermissionChecker {
        return PermissionChecker{
            .dao = dao,
            .cache = PermissionCache.init(allocator),
        };
    }
    
    pub fn deinit(self: *PermissionChecker) void {
        self.cache.deinit();
    }
    
    // 🆕 Main permission checking function with full context
    pub fn checkUserRepoPermission(
        self: *PermissionChecker,
        allocator: std.mem.Allocator,
        user_id: ?i64,
        repo_id: i64,
    ) !Permission {
        const cache_key = PermissionCacheKey{ .user_id = user_id, .repo_id = repo_id };
        
        if (self.cache.get(cache_key)) |cached| {
            return cached;
        }
        
        const permission = try self.loadUserRepoPermission(allocator, user_id, repo_id);
        try self.cache.put(cache_key, permission);
        return permission;
    }
    
    // 🆕 Organization/User visibility checking (Gitea pattern)
    pub fn hasOrgOrUserVisible(
        self: *PermissionChecker,
        allocator: std.mem.Allocator,
        user_id: ?i64,
        owner_id: i64,
        owner_type: OwnerType,
    ) !bool {
        // Implementation based on Gitea's HasOrgOrUserVisible
        if (owner_type == .User) {
            const owner = try self.dao.getUserById(allocator, owner_id) orelse return false;
            defer owner.deinit(allocator);
            
            if (owner.visibility == .Public) return true;
            
            if (owner.visibility == .Limited and user_id != null) {
                const user = try self.dao.getUserById(allocator, user_id.?) orelse return false;
                defer user.deinit(allocator);
                return !user.is_restricted;
            }
            
            if (owner.visibility == .Private) {
                if (user_id == owner_id) return true;
                if (user_id) |uid| {
                    const user = try self.dao.getUserById(allocator, uid) orelse return false;
                    defer user.deinit(allocator);
                    return user.is_admin;
                }
            }
            
            return false;
        }
        
        // Organization visibility logic
        if (owner_type == .Organization) {
            const org = try self.dao.getOrganizationById(allocator, owner_id) orelse return false;
            defer org.deinit(allocator);
            
            if (org.visibility == .Public) return true;
            
            if (org.visibility == .Limited and user_id != null) {
                const user = try self.dao.getUserById(allocator, user_id.?) orelse return false;
                defer user.deinit(allocator);
                return !user.is_restricted;
            }
            
            if (org.visibility == .Private) {
                if (user_id) |uid| {
                    const user = try self.dao.getUserById(allocator, uid) orelse return false;
                    defer user.deinit(allocator);
                    
                    if (user.is_admin) return true;
                    
                    return try self.dao.isOrganizationMember(allocator, org.id, uid);
                }
            }
            
            return false;
        }
        
        return false;
    }
    
    // 🆕 Team permission resolution with inheritance
    pub fn getUserTeamPermissions(
        self: *PermissionChecker,
        allocator: std.mem.Allocator,
        user_id: i64,
        org_id: i64,
    ) ![]TeamPermissionSet {
        const teams = try self.dao.getUserTeams(allocator, user_id, org_id);
        defer teams.deinit(allocator);
        
        var permissions = std.ArrayList(TeamPermissionSet).init(allocator);
        errdefer permissions.deinit();
        
        for (teams.items) |team| {
            const team_permission = try self.resolveTeamPermission(allocator, team.id);
            try permissions.append(TeamPermissionSet{
                .team_id = team.id,
                .permission = team_permission,
            });
        }
        
        return permissions.toOwnedSlice();
    }
    
    // 🆕 Git operation authorization with team context
    pub fn authorizeGitOperation(
        self: *PermissionChecker,
        allocator: std.mem.Allocator,
        context: GitAuthContext,
    ) !AuthorizationResult {
        const repo = try self.dao.getRepositoryByPath(allocator, context.repository_path) orelse {
            return AuthorizationResult{
                .authorized = false,
                .reason = "Repository not found",
            };
        };
        defer repo.deinit(allocator);
        
        const permission = try self.checkUserRepoPermission(allocator, context.user_id, repo.id);
        
        const required_access = switch (context.operation) {
            .Clone, .Fetch => AccessMode.Read,
            .Push => AccessMode.Write,
        };
        
        const has_access = permission.canAccess(.Code, required_access);
        
        return AuthorizationResult{
            .authorized = has_access,
            .reason = if (has_access) null else "Insufficient permissions",
            .permission = permission,
        };
    }
    
    // 🆕 Internal permission loading with full resolution
    fn loadUserRepoPermission(
        self: *PermissionChecker,
        allocator: std.mem.Allocator,
        user_id: ?i64,
        repo_id: i64,
    ) !Permission {
        // Get repository info
        const repo = try self.dao.getRepositoryById(allocator, repo_id) orelse {
            return Permission{
                .access_mode = .None,
                .units = null,
                .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
            };
        };
        defer repo.deinit(allocator);
        
        // Anonymous user access
        if (user_id == null) {
            if (repo.visibility != .Public) {
                return Permission{
                    .access_mode = .None,
                    .units = null,
                    .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                    .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                };
            }
            
            const repo_units = try self.dao.getRepositoryUnits(allocator, repo_id);
            defer repo_units.deinit(allocator);
            
            var anonymous_access = std.EnumMap(UnitType, AccessMode).init(.None);
            for (repo_units.items) |unit| {
                anonymous_access.put(unit.unit_type, unit.access_mode);
            }
            
            return Permission{
                .access_mode = .Read,
                .units = null,
                .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                .anonymous_access_mode = anonymous_access,
            };
        }
        
        const uid = user_id.?;
        
        // Get user info
        const user = try self.dao.getUserById(allocator, uid) orelse {
            return Permission{
                .access_mode = .None,
                .units = null,
                .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
            };
        };
        defer user.deinit(allocator);
        
        // 🆕 Restricted users cannot access Limited visibility repositories
        if (user.is_restricted and repo.visibility == .Limited) {
            return Permission{
                .access_mode = .None,
                .units = null,
                .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
            };
        }
        
        // Admin users have full access
        if (user.is_admin) {
            return Permission{
                .access_mode = .Owner,
                .units = null, // Admin override
                .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
            };
        }
        
        // 🆕 Check repository ownership (user or organization)
        if (repo.owner_type == .User and repo.owner_id == uid) {
            return Permission{
                .access_mode = .Owner,
                .units = null, // Owner override
                .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
            };
        }
        
        // 🆕 Check organization ownership and team permissions
        if (repo.owner_type == .Organization) {
            // Check if user is organization owner
            const is_org_owner = try self.dao.isOrganizationOwner(allocator, repo.owner_id, uid);
            if (is_org_owner) {
                return Permission{
                    .access_mode = .Owner,
                    .units = null,
                    .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                    .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                };
            }
            
            // Check team permissions
            const team_access = try self.dao.getUserTeamRepoPermission(allocator, uid, repo_id);
            if (team_access) |team_perm| {
                defer team_perm.deinit(allocator);
                
                return Permission{
                    .access_mode = team_perm.access_mode,
                    .units = team_perm.units,
                    .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                    .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                };
            }
        }
        
        // Check explicit collaborator permissions
        const collaboration = try self.dao.getCollaboration(allocator, uid, repo_id);
        if (collaboration) |collab| {
            defer collab.deinit(allocator);
            
            return Permission{
                .access_mode = collab.access_mode,
                .units = collab.units,
                .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
                .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
            };
        }
        
        // 🆕 Public/Limited repository default access
        if ((repo.visibility == .Public or 
             (repo.visibility == .Limited and !user.is_restricted))) {
            
            const repo_units = try self.dao.getRepositoryUnits(allocator, repo_id);
            defer repo_units.deinit(allocator);
            
            var everyone_access = std.EnumMap(UnitType, AccessMode).init(.None);
            for (repo_units.items) |unit| {
                everyone_access.put(unit.unit_type, unit.access_mode);
            }
            
            return Permission{
                .access_mode = .Read,
                .units = null,
                .everyone_access_mode = everyone_access,
                .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
            };
        }
        
        // Deny by default
        return Permission{
            .access_mode = .None,
            .units = null,
            .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
            .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
        };
    }
};

// 🆕 Enhanced permission structures
pub const Permission = struct {
    access_mode: AccessMode,
    units: ?std.EnumMap(UnitType, AccessMode),
    everyone_access_mode: std.EnumMap(UnitType, AccessMode),
    anonymous_access_mode: std.EnumMap(UnitType, AccessMode),
    
    pub fn unitAccessMode(self: *const Permission, unit_type: UnitType) AccessMode {
        // Admin/Owner mode overrides unit-specific permissions
        if (self.access_mode.atLeast(.Admin)) {
            return self.access_mode;
        }
        
        if (self.units == null) {
            return self.access_mode;
        }
        
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

// Supporting structures
pub const OwnerType = enum { User, Organization };
pub const GitOperation = enum { Clone, Fetch, Push };
pub const GitAuthContext = struct {
    user_id: ?i64,
    repository_path: []const u8,
    operation: GitOperation,
    branch: ?[]const u8 = null,
};
pub const AuthorizationResult = struct {
    authorized: bool,
    reason: ?[]const u8,
    permission: ?Permission = null,
};
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach - write tests first, then implementation. Run `zig build && zig build test` after EVERY change. Tests must be in the same file as source code.

**CRITICAL**: Zero tolerance for compilation or test failures. Any failing tests indicate YOU caused a regression.

<phase_1>
<title>Phase 1: 🆕 Enterprise Permission Foundation with Multi-Tier Architecture (TDD)</title>

1. **Create enhanced permission module structure**
   ```bash
   mkdir -p src/auth
   touch src/auth/permissions.zig
   touch src/auth/teams.zig  
   touch src/auth/units.zig
   touch src/auth/organizations.zig
   ```

2. **🆕 Write tests for multi-tier permission architecture**
   ```zig
   test "AccessMode hierarchy with atLeast comparison" {
       try testing.expect(AccessMode.Read.atLeast(.Read));
       try testing.expect(AccessMode.Write.atLeast(.Read));
       try testing.expect(AccessMode.Admin.atLeast(.Write));
       try testing.expect(AccessMode.Owner.atLeast(.Admin));
       try testing.expect(!AccessMode.Read.atLeast(.Write));
   }
   
   test "UnitType permissions with access mode validation" {
       const permission = Permission{
           .access_mode = .Read,
           .units = blk: {
               var units = std.EnumMap(UnitType, AccessMode).init(.None);
               units.put(.Issues, .Write);
               units.put(.Wiki, .Read);
               break :blk units;
           },
           .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
           .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
       };
       
       try testing.expect(permission.canWrite(.Issues));
       try testing.expect(permission.canRead(.Wiki));
       try testing.expect(!permission.canWrite(.Wiki));
       try testing.expect(!permission.canAccess(.PullRequests, .Read)); // Not granted
   }
   
   test "Permission unitAccessMode with admin override" {
       const admin_permission = Permission{
           .access_mode = .Admin,
           .units = null, // Admin override
           .everyone_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
           .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).init(.None),
       };
       
       // Admin should have admin access to all units
       try testing.expectEqual(AccessMode.Admin, admin_permission.unitAccessMode(.Issues));
       try testing.expectEqual(AccessMode.Admin, admin_permission.unitAccessMode(.Wiki));
       try testing.expectEqual(AccessMode.Admin, admin_permission.unitAccessMode(.Packages));
   }
   
   test "OrgRole hierarchy with inheritance" {
       try testing.expect(OrgRole.Owner.atLeast(.Admin));
       try testing.expect(OrgRole.Admin.atLeast(.Member));
       try testing.expect(!OrgRole.Member.atLeast(.Admin));
   }
   ```

3. **🆕 Implement multi-tier permission enums and structures**
4. **🆕 Add Permission struct with unit-level access control**
5. **🆕 Create organization role hierarchy**

</phase_1>

<phase_2>
<title>Phase 2: Database Integration and Repository Ownership (TDD)</title>

1. **Write tests for database permission queries**
   ```zig
   test "checkUserRepoPermission for repository owner" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       // Create test user and repository
       const user_id = try dao.createUser(allocator, .{
           .name = "owner-user",
           .email = "owner@example.com",
       });
       
       const repo_id = try dao.createRepository(allocator, .{
           .name = "test-repo",
           .owner_id = user_id,
           .owner_type = .User,
           .visibility = .Private,
       });
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       // Owner should have owner permission
       const permission = try permission_checker.checkUserRepoPermission(allocator, user_id, repo_id);
       try testing.expectEqual(AccessMode.Owner, permission.access_mode);
       try testing.expect(permission.canAccess(.Code, .Owner));
   }
   
   test "checkUserRepoPermission for repository collaborator" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       // Create owner and collaborator
       const owner_id = try dao.createUser(allocator, .{
           .name = "repo-owner",
           .email = "owner@example.com",
       });
       
       const collaborator_id = try dao.createUser(allocator, .{
           .name = "collaborator",
           .email = "collab@example.com",
       });
       
       const repo_id = try dao.createRepository(allocator, .{
           .name = "test-repo",
           .owner_id = owner_id,
           .owner_type = .User,
           .visibility = .Private,
       });
       
       // Grant write permission to collaborator
       try dao.addRepositoryCollaborator(allocator, repo_id, collaborator_id, .Write);
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       const permission = try permission_checker.checkUserRepoPermission(allocator, collaborator_id, repo_id);
       try testing.expectEqual(AccessMode.Write, permission.access_mode);
       try testing.expect(permission.canWrite(.Code));
       try testing.expect(!permission.canAccess(.Settings, .Admin));
   }
   
   test "checkUserRepoPermission for anonymous user on public repository" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       const owner_id = try dao.createUser(allocator, .{
           .name = "public-owner",
           .email = "public@example.com",
       });
       
       const repo_id = try dao.createRepository(allocator, .{
           .name = "public-repo",
           .owner_id = owner_id,
           .owner_type = .User,
           .visibility = .Public,
       });
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       // Anonymous user (null user_id) should have read access
       const permission = try permission_checker.checkUserRepoPermission(allocator, null, repo_id);
       try testing.expect(permission.canRead(.Code));
       try testing.expect(!permission.canWrite(.Code));
   }
   ```

2. **Implement database permission queries**
3. **Add repository ownership detection**
4. **Test anonymous access to public repositories**

</phase_2>

<phase_3>
<title>Phase 3: 🆕 Organization and Team Permission Integration (TDD)</title>

1. **Write tests for organization permissions**
   ```zig
   test "organization owner has access to all org repositories" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       // Create organization and owner
       const org_id = try dao.createOrganization(allocator, .{
           .name = "test-org",
           .visibility = .Public,
       });
       
       const owner_id = try dao.createUser(allocator, .{
           .name = "org-owner",
           .email = "owner@example.com",
       });
       
       // Set user as organization owner
       try dao.addOrganizationMember(allocator, org_id, owner_id, .Owner);
       
       // Create repository owned by organization
       const repo_id = try dao.createRepository(allocator, .{
           .name = "org-repo",
           .owner_id = org_id,
           .owner_type = .Organization,
           .visibility = .Private,
       });
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       // Organization owner should have owner access
       const permission = try permission_checker.checkUserRepoPermission(allocator, owner_id, repo_id);
       try testing.expectEqual(AccessMode.Owner, permission.access_mode);
   }
   
   test "team member has team-specific repository access" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       // Create organization, team, user, and repository
       const org_id = try dao.createOrganization(allocator, .{
           .name = "test-org",
           .visibility = .Public,
       });
       
       const team_id = try dao.createTeam(allocator, .{
           .org_id = org_id,
           .name = "developers",
           .access_mode = .Write,
       });
       
       const user_id = try dao.createUser(allocator, .{
           .name = "team-member",
           .email = "member@example.com",
       });
       
       // Add user to team
       try dao.addTeamMember(allocator, team_id, user_id);
       
       const repo_id = try dao.createRepository(allocator, .{
           .name = "team-repo",
           .owner_id = org_id,
           .owner_type = .Organization,
           .visibility = .Private,
       });
       
       // Grant team access to repository
       try dao.addTeamRepository(allocator, team_id, repo_id);
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       // Team member should have write access
       const permission = try permission_checker.checkUserRepoPermission(allocator, user_id, repo_id);
       try testing.expectEqual(AccessMode.Write, permission.access_mode);
       try testing.expect(permission.canWrite(.Code));
   }
   
   test "hasOrgOrUserVisible checks organization visibility" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       // Create private organization
       const org_id = try dao.createOrganization(allocator, .{
           .name = "private-org",
           .visibility = .Private,
       });
       
       const member_id = try dao.createUser(allocator, .{
           .name = "org-member",
           .email = "member@example.com",
       });
       
       const outsider_id = try dao.createUser(allocator, .{
           .name = "outsider",
           .email = "outsider@example.com",
       });
       
       // Add member to organization
       try dao.addOrganizationMember(allocator, org_id, member_id, .Member);
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       // Member should see private organization
       const member_visible = try permission_checker.hasOrgOrUserVisible(allocator, member_id, org_id, .Organization);
       try testing.expect(member_visible);
       
       // Outsider should not see private organization
       const outsider_visible = try permission_checker.hasOrgOrUserVisible(allocator, outsider_id, org_id, .Organization);
       try testing.expect(!outsider_visible);
   }
   ```

2. **Implement organization membership checking**
3. **Add team-based repository access**
4. **Test organization visibility patterns**

</phase_3>

<phase_4>
<title>Phase 4: 🆕 Request-Level Permission Caching (TDD)</title>

1. **Write tests for permission caching**
   ```zig
   test "permission cache improves lookup performance" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       // Create test data
       const user_id = try dao.createUser(allocator, .{
           .name = "cache-user",
           .email = "cache@example.com",
       });
       
       const repo_id = try dao.createRepository(allocator, .{
           .name = "cache-repo",
           .owner_id = user_id,
           .owner_type = .User,
           .visibility = .Public,
       });
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       // First lookup should hit database
       const start1 = std.time.nanoTimestamp();
       const permission1 = try permission_checker.checkUserRepoPermission(allocator, user_id, repo_id);
       const duration1 = std.time.nanoTimestamp() - start1;
       
       // Second lookup should hit cache (much faster)
       const start2 = std.time.nanoTimestamp();
       const permission2 = try permission_checker.checkUserRepoPermission(allocator, user_id, repo_id);
       const duration2 = std.time.nanoTimestamp() - start2;
       
       // Verify same result and cache is faster
       try testing.expectEqual(permission1.access_mode, permission2.access_mode);
       try testing.expect(duration2 < duration1 / 2); // Cache should be significantly faster
   }
   
   test "permission cache invalidation works correctly" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       const user_id = try dao.createUser(allocator, .{
           .name = "invalidation-user",
           .email = "invalidation@example.com",
       });
       
       const repo_id = try dao.createRepository(allocator, .{
           .name = "invalidation-repo",
           .owner_id = user_id,
           .owner_type = .User,
           .visibility = .Private,
       });
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       // Initial permission check
       const permission1 = try permission_checker.checkUserRepoPermission(allocator, user_id, repo_id);
       try testing.expectEqual(AccessMode.Owner, permission1.access_mode);
       
       // Invalidate cache
       try permission_checker.invalidateUserPermissions(allocator, user_id);
       
       // Next check should reflect any changes (would hit database again)
       const permission2 = try permission_checker.checkUserRepoPermission(allocator, user_id, repo_id);
       try testing.expectEqual(AccessMode.Owner, permission2.access_mode);
   }
   ```

2. **Implement request-level permission caching**
3. **Add cache invalidation logic**
4. **Test cache performance and correctness**

</phase_4>

<phase_5>
<title>Phase 5: 🆕 Git Protocol Authorization (TDD)</title>

1. **Write tests for Git operation authorization**
   ```zig
   test "authorizeGitOperation allows push with write permission" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       const user_id = try dao.createUser(allocator, .{
           .name = "git-user",
           .email = "git@example.com",
       });
       
       const repo_id = try dao.createRepository(allocator, .{
           .name = "git-repo",
           .owner_id = user_id,
           .owner_type = .User,
           .visibility = .Public,
       });
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       const git_context = GitAuthContext{
           .user_id = user_id,
           .repository_path = "git-user/git-repo.git",
           .operation = .Push,
           .branch = "main",
       };
       
       const auth_result = try permission_checker.authorizeGitOperation(allocator, git_context);
       
       try testing.expect(auth_result.authorized);
       try testing.expect(auth_result.reason == null);
       try testing.expect(auth_result.permission.?.canWrite(.Code));
   }
   
   test "authorizeGitOperation denies push without write permission" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       const owner_id = try dao.createUser(allocator, .{
           .name = "repo-owner",
           .email = "owner@example.com",
       });
       
       const reader_id = try dao.createUser(allocator, .{
           .name = "reader-user",
           .email = "reader@example.com",
       });
       
       const repo_id = try dao.createRepository(allocator, .{
           .name = "read-only-repo",
           .owner_id = owner_id,
           .owner_type = .User,
           .visibility = .Private,
       });
       
       // Grant only read permission to reader
       try dao.addRepositoryCollaborator(allocator, repo_id, reader_id, .Read);
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       const git_context = GitAuthContext{
           .user_id = reader_id,
           .repository_path = "repo-owner/read-only-repo.git",
           .operation = .Push,
           .branch = "main",
       };
       
       const auth_result = try permission_checker.authorizeGitOperation(allocator, git_context);
       
       try testing.expect(!auth_result.authorized);
       try testing.expect(auth_result.reason != null);
       try testing.expectEqualStrings("Insufficient permissions", auth_result.reason.?);
   }
   ```

2. **Implement Git protocol authorization**
3. **Add repository path resolution**
4. **Test SSH and HTTP Git operation scenarios**

</phase_5>

<phase_6>
<title>Phase 6: 🆕 Unit-Level Permission Control (TDD)</title>

1. **Write tests for unit-level permissions**
   ```zig
   test "unit-level permissions allow fine-grained access control" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       // Create repository with specific unit permissions
       const owner_id = try dao.createUser(allocator, .{
           .name = "unit-owner",
           .email = "owner@example.com",
       });
       
       const repo_id = try dao.createRepository(allocator, .{
           .name = "unit-repo",
           .owner_id = owner_id,
           .owner_type = .User,
           .visibility = .Public,
       });
       
       // Set specific unit permissions
       try dao.setRepositoryUnitPermission(allocator, repo_id, .Issues, .Write);
       try dao.setRepositoryUnitPermission(allocator, repo_id, .Wiki, .Read);
       try dao.setRepositoryUnitPermission(allocator, repo_id, .Packages, .None);
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       // Regular user accessing public repository
       const user_id = try dao.createUser(allocator, .{
           .name = "regular-user",
           .email = "user@example.com",
       });
       
       const permission = try permission_checker.checkUserRepoPermission(allocator, user_id, repo_id);
       
       // Test unit-specific access
       try testing.expect(permission.canWrite(.Issues));
       try testing.expect(permission.canRead(.Wiki));
       try testing.expect(!permission.canWrite(.Wiki));
       try testing.expect(!permission.canAccess(.Packages, .Read));
   }
   
   test "admin permission overrides unit-level restrictions" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       const owner_id = try dao.createUser(allocator, .{
           .name = "repo-owner",
           .email = "owner@example.com",
       });
       
       const admin_id = try dao.createUser(allocator, .{
           .name = "repo-admin",
           .email = "admin@example.com",
       });
       
       const repo_id = try dao.createRepository(allocator, .{
           .name = "admin-repo",
           .owner_id = owner_id,
           .owner_type = .User,
           .visibility = .Private,
       });
       
       // Grant admin permission
       try dao.addRepositoryCollaborator(allocator, repo_id, admin_id, .Admin);
       
       // Set restrictive unit permissions
       try dao.setRepositoryUnitPermission(allocator, repo_id, .Issues, .None);
       try dao.setRepositoryUnitPermission(allocator, repo_id, .Wiki, .None);
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       const permission = try permission_checker.checkUserRepoPermission(allocator, admin_id, repo_id);
       
       // Admin should override unit restrictions
       try testing.expectEqual(AccessMode.Admin, permission.access_mode);
       try testing.expectEqual(AccessMode.Admin, permission.unitAccessMode(.Issues));
       try testing.expectEqual(AccessMode.Admin, permission.unitAccessMode(.Wiki));
   }
   ```

2. **Implement unit-level permission checking**
3. **Add repository unit configuration**
4. **Test admin override behavior**

</phase_7>

<phase_7>
<title>Phase 7: 🆕 Complete Integration and Performance Testing (TDD)</title>

1. **Write comprehensive integration tests**
   ```zig
   test "complete permission system integration with complex scenarios" {
       const allocator = testing.allocator;
       
       var dao = try setupTestDatabase(allocator);
       defer dao.deinit(allocator);
       
       // Create complex organizational structure
       const org_id = try dao.createOrganization(allocator, .{
           .name = "enterprise-org",
           .visibility = .Private,
       });
       
       const dev_team_id = try dao.createTeam(allocator, .{
           .org_id = org_id,
           .name = "developers",
           .access_mode = .Write,
       });
       
       const admin_team_id = try dao.createTeam(allocator, .{
           .org_id = org_id,
           .name = "admins",
           .access_mode = .Admin,
       });
       
       // Create users with different roles
       const org_owner_id = try dao.createUser(allocator, .{
           .name = "org-owner",
           .email = "owner@enterprise.com",
       });
       
       const dev_user_id = try dao.createUser(allocator, .{
           .name = "developer",
           .email = "dev@enterprise.com",
       });
       
       const external_user_id = try dao.createUser(allocator, .{
           .name = "external",
           .email = "external@example.com",
       });
       
       // Set up organization structure
       try dao.addOrganizationMember(allocator, org_id, org_owner_id, .Owner);
       try dao.addOrganizationMember(allocator, org_id, dev_user_id, .Member);
       try dao.addTeamMember(allocator, dev_team_id, dev_user_id);
       
       // Create repository with complex permissions
       const repo_id = try dao.createRepository(allocator, .{
           .name = "enterprise-repo",
           .owner_id = org_id,
           .owner_type = .Organization,
           .visibility = .Private,
       });
       
       try dao.addTeamRepository(allocator, dev_team_id, repo_id);
       try dao.addRepositoryCollaborator(allocator, repo_id, external_user_id, .Read);
       
       var permission_checker = PermissionChecker.init(allocator, &dao);
       defer permission_checker.deinit();
       
       // Test org owner permissions
       const owner_permission = try permission_checker.checkUserRepoPermission(allocator, org_owner_id, repo_id);
       try testing.expectEqual(AccessMode.Owner, owner_permission.access_mode);
       
       // Test team member permissions
       const dev_permission = try permission_checker.checkUserRepoPermission(allocator, dev_user_id, repo_id);
       try testing.expectEqual(AccessMode.Write, dev_permission.access_mode);
       
       // Test external collaborator permissions
       const external_permission = try permission_checker.checkUserRepoPermission(allocator, external_user_id, repo_id);
       try testing.expectEqual(AccessMode.Read, external_permission.access_mode);
       
       // Test Git operations
       const push_context = GitAuthContext{
           .user_id = dev_user_id,
           .repository_path = "enterprise-org/enterprise-repo.git",
           .operation = .Push,
       };
       
       const push_result = try permission_checker.authorizeGitOperation(allocator, push_context);
       try testing.expect(push_result.authorized);
       
       const external_push_context = GitAuthContext{
           .user_id = external_user_id,
           .repository_path = "enterprise-org/enterprise-repo.git",
           .operation = .Push,
       };
       
       const external_push_result = try permission_checker.authorizeGitOperation(allocator, external_push_context);
       try testing.expect(!external_push_result.authorized);
   }
   ```

2. **Add performance benchmarks**
3. **Test memory usage and cleanup**
4. **Verify cache performance metrics**

</phase_8>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **Database Integration**: All tests use real PostgreSQL database with proper setup/teardown
- **🆕 Performance Testing**: Permission lookup performance with large datasets and caching
- **🆕 Organization Testing**: Complex organizational structures with team hierarchies
- **🆕 Unit Permission Testing**: Fine-grained access control scenarios
- **🆕 Visibility Testing**: Complex visibility patterns with inheritance
- **Security Testing**: Access control bypass attempts and edge cases
- **Concurrency Testing**: Concurrent permission checks and cache invalidation
- **Memory Safety**: Zero memory leaks with comprehensive allocation tracking

</testing_requirements>

<success_criteria>

1. **All tests pass**: Complete test coverage with zero failures
2. **🆕 Enterprise Features**: Full organization/team support with unit-level permissions
3. **🆕 Performance**: Sub-millisecond permission checks with request-level caching
4. **🆕 Team Management**: Complete team hierarchy support with permission inheritance
5. **🆕 Unit-Level Control**: Fine-grained access control for all repository features
6. **🆕 Visibility Patterns**: Complex visibility rules with organization inheritance
7. **Security**: Comprehensive access control with no bypass vulnerabilities
8. **Integration**: Seamless integration with Git protocols and API endpoints
9. **Scalability**: Support for thousands of organizations, teams, and repositories
10. **🆕 Advanced Caching**: Request-level caching with intelligent invalidation
11. **Memory safety**: Zero memory leaks in all operations
12. **🆕 Production Ready**: Battle-tested patterns from Gitea's enterprise deployment

</success_criteria>

</quality_assurance>

<reference_implementations>

**🆕 Enhanced with Gitea Production Patterns:**
- [🆕 Gitea Permission System](https://github.com/go-gitea/gitea/blob/main/models/perm/access/repo_permission.go)
- [🆕 Gitea Organization Management](https://github.com/go-gitea/gitea/blob/main/models/organization/org.go)
- [🆕 Gitea Team Permissions](https://github.com/go-gitea/gitea/blob/main/models/organization/team.go)
- [🆕 Gitea Unit-Level Access](https://github.com/go-gitea/gitea/blob/main/models/organization/team_unit.go)
- [🆕 Gitea Repository Visibility](https://github.com/go-gitea/gitea/blob/main/models/organization/org.go#L400-L500)
- **GitHub Enterprise**: Organization and team management patterns
- **GitLab Enterprise**: Project groups and access level inheritance
- **Enterprise RBAC**: Multi-tier access control implementations

**🆕 Key Gitea Patterns Implemented:**
- Organization/team hierarchies with permission inheritance
- Unit-level permissions for fine-grained feature control  
- Complex visibility patterns (Public/Limited/Private) with organization rules
- Request-level permission caching with cascade invalidation
- Team-based repository access with bulk operations
- hasOrgOrUserVisible pattern for visibility checking
- Admin override patterns for system administration

</reference_implementations>