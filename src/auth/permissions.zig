const std = @import("std");
const testing = std.testing;
const RepositoryDAO = @import("../dao/repository.zig").RepositoryDAO;
const UserDAO = @import("../dao/user.zig").UserDAO;

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
    Public, // Visible to everyone
    Limited, // Visible to signed-in users (not restricted users)
    Private, // Visible only to members
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

// Enhanced permission structures
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

        var max_access: AccessMode = .None;

        // Check unit-specific permissions first
        if (self.units) |units| {
            if (units.get(unit_type)) |unit_mode| {
                max_access = unit_mode;
            }
        }

        // Check everyone access
        if (self.everyone_access_mode.get(unit_type)) |everyone_mode| {
            if (everyone_mode.atLeast(max_access)) {
                max_access = everyone_mode;
            }
        }

        // Check anonymous access
        if (self.anonymous_access_mode.get(unit_type)) |anonymous_mode| {
            if (anonymous_mode.atLeast(max_access)) {
                max_access = anonymous_mode;
            }
        }

        // If no specific unit permissions are set and no everyone/anonymous access,
        // and we have units defined, return None for unspecified units
        if (max_access == .None and self.units != null) {
            return .None;
        }

        // If no units are defined at all, use the base access_mode
        if (self.units == null and max_access == .None) {
            max_access = self.access_mode;
        }

        return max_access;
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

pub const TeamPermissionSet = struct {
    team_id: i64,
    permission: TeamPermission,
};

pub const PermissionContext = struct {
    user_id: ?i64,
    repository_id: i64,
    organization_id: ?i64,
    request_id: ?u64, // For caching
};

pub const PermissionCacheKey = struct {
    user_id: ?i64,
    repo_id: i64,

    pub fn eql(self: PermissionCacheKey, other: PermissionCacheKey) bool {
        return self.user_id == other.user_id and self.repo_id == other.repo_id;
    }

    pub fn hash(self: PermissionCacheKey) u64 {
        var hasher = std.hash.Wyhash.init(0);
        if (self.user_id) |uid| {
            hasher.update(std.mem.asBytes(&uid));
        }
        hasher.update(std.mem.asBytes(&self.repo_id));
        return hasher.final();
    }
};

const PermissionCacheContext = struct {
    pub fn hash(self: @This(), key: PermissionCacheKey) u64 {
        _ = self;
        return key.hash();
    }

    pub fn eql(self: @This(), a: PermissionCacheKey, b: PermissionCacheKey) bool {
        _ = self;
        return a.eql(b);
    }
};

pub const PermissionCache = struct {
    allocator: std.mem.Allocator,
    cache: std.HashMap(PermissionCacheKey, Permission, PermissionCacheContext, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator) PermissionCache {
        return PermissionCache{
            .allocator = allocator,
            .cache = std.HashMap(PermissionCacheKey, Permission, PermissionCacheContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *PermissionCache) void {
        self.cache.deinit();
    }

    pub fn get(self: *const PermissionCache, key: PermissionCacheKey) ?Permission {
        return self.cache.get(key);
    }

    pub fn put(self: *PermissionCache, key: PermissionCacheKey, permission: Permission) !void {
        try self.cache.put(key, permission);
    }

    pub fn invalidateUser(self: *PermissionCache, user_id: i64) void {
        var iterator = self.cache.iterator();
        var keys_to_remove = std.ArrayList(PermissionCacheKey).init(self.allocator);
        defer keys_to_remove.deinit();

        while (iterator.next()) |entry| {
            if (entry.key_ptr.user_id == user_id) {
                keys_to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        for (keys_to_remove.items) |key| {
            _ = self.cache.remove(key);
        }
    }
};

// Repository data structures for database integration
pub const Repository = struct {
    id: i64,
    name: []const u8,
    owner_id: i64,
    owner_type: OwnerType,
    visibility: Visibility,
    
    pub fn deinit(self: Repository, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const User = struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    is_admin: bool = false,
    
    pub fn deinit(self: User, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.email);
    }
};

pub const Organization = struct {
    id: i64,
    name: []const u8,
    visibility: Visibility,
    
    pub fn deinit(self: Organization, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const Collaborator = struct {
    user_id: i64,
    access_mode: AccessMode,
};

// Member structure for organization members
const OrgMember = struct {
    user_id: i64,
    role: OrgRole,
};

// Mock DAO for testing
const MockDAO = struct {
    allocator: std.mem.Allocator,
    users: std.ArrayList(User),
    repositories: std.ArrayList(Repository),
    organizations: std.ArrayList(Organization),
    collaborators: std.HashMap(i64, std.ArrayList(Collaborator), MockDAO.HashContext, std.hash_map.default_max_load_percentage),
    org_members: std.HashMap(i64, std.ArrayList(OrgMember), MockDAO.HashContext, std.hash_map.default_max_load_percentage),
    
    const HashContext = struct {
        pub fn hash(self: @This(), key: i64) u64 {
            _ = self;
            return @as(u64, @intCast(key));
        }
        
        pub fn eql(self: @This(), a: i64, b: i64) bool {
            _ = self;
            return a == b;
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) MockDAO {
        return MockDAO{
            .allocator = allocator,
            .users = std.ArrayList(User).init(allocator),
            .repositories = std.ArrayList(Repository).init(allocator),
            .organizations = std.ArrayList(Organization).init(allocator),
            .collaborators = std.HashMap(i64, std.ArrayList(Collaborator), MockDAO.HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .org_members = std.HashMap(i64, std.ArrayList(OrgMember), MockDAO.HashContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *MockDAO) void {
        for (self.users.items) |user| {
            user.deinit(self.allocator);
        }
        self.users.deinit();
        
        for (self.repositories.items) |repo| {
            repo.deinit(self.allocator);
        }
        self.repositories.deinit();
        
        for (self.organizations.items) |org| {
            org.deinit(self.allocator);
        }
        self.organizations.deinit();
        
        var collab_iter = self.collaborators.iterator();
        while (collab_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.collaborators.deinit();
        
        var member_iter = self.org_members.iterator();
        while (member_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.org_members.deinit();
    }
    
    pub fn createUser(self: *MockDAO, user: struct { name: []const u8, email: []const u8, is_admin: bool = false }) !i64 {
        const id = @as(i64, @intCast(self.users.items.len + 1));
        try self.users.append(User{
            .id = id,
            .name = try self.allocator.dupe(u8, user.name),
            .email = try self.allocator.dupe(u8, user.email),
            .is_admin = user.is_admin,
        });
        return id;
    }
    
    pub fn createRepository(self: *MockDAO, repo: struct { name: []const u8, owner_id: i64, owner_type: OwnerType, visibility: Visibility }) !i64 {
        const id = @as(i64, @intCast(self.repositories.items.len + 1));
        try self.repositories.append(Repository{
            .id = id,
            .name = try self.allocator.dupe(u8, repo.name),
            .owner_id = repo.owner_id,
            .owner_type = repo.owner_type,
            .visibility = repo.visibility,
        });
        return id;
    }
    
    pub fn createOrganization(self: *MockDAO, org: struct { name: []const u8, visibility: Visibility }) !i64 {
        const id = @as(i64, @intCast(self.organizations.items.len + 1));
        try self.organizations.append(Organization{
            .id = id,
            .name = try self.allocator.dupe(u8, org.name),
            .visibility = org.visibility,
        });
        return id;
    }
    
    pub fn getUserById(self: *MockDAO, user_id: i64) !?User {
        for (self.users.items) |user| {
            if (user.id == user_id) {
                return User{
                    .id = user.id,
                    .name = try self.allocator.dupe(u8, user.name),
                    .email = try self.allocator.dupe(u8, user.email),
                    .is_admin = user.is_admin,
                };
            }
        }
        return null;
    }
    
    pub fn getRepositoryById(self: *MockDAO, repo_id: i64) !?Repository {
        for (self.repositories.items) |repo| {
            if (repo.id == repo_id) {
                return Repository{
                    .id = repo.id,
                    .name = try self.allocator.dupe(u8, repo.name),
                    .owner_id = repo.owner_id,
                    .owner_type = repo.owner_type,
                    .visibility = repo.visibility,
                };
            }
        }
        return null;
    }
    
    pub fn getOrganizationById(self: *MockDAO, org_id: i64) !?Organization {
        for (self.organizations.items) |org| {
            if (org.id == org_id) {
                return Organization{
                    .id = org.id,
                    .name = try self.allocator.dupe(u8, org.name),
                    .visibility = org.visibility,
                };
            }
        }
        return null;
    }
    
    pub fn addRepositoryCollaborator(self: *MockDAO, repo_id: i64, user_id: i64, access_mode: AccessMode) !void {
        if (self.collaborators.getPtr(repo_id)) |collaborators| {
            try collaborators.append(Collaborator{
                .user_id = user_id,
                .access_mode = access_mode,
            });
        } else {
            const new_list = std.ArrayList(Collaborator).init(self.allocator);
            try self.collaborators.put(repo_id, new_list);
            const collaborators = self.collaborators.getPtr(repo_id).?;
            try collaborators.append(Collaborator{
                .user_id = user_id,
                .access_mode = access_mode,
            });
        }
    }
    
    pub fn getRepositoryCollaborator(self: *MockDAO, repo_id: i64, user_id: i64) ?AccessMode {
        if (self.collaborators.get(repo_id)) |collaborators| {
            for (collaborators.items) |collab| {
                if (collab.user_id == user_id) {
                    return collab.access_mode;
                }
            }
        }
        return null;
    }
    
    pub fn addOrganizationMember(self: *MockDAO, org_id: i64, user_id: i64, role: OrgRole) !void {
        if (self.org_members.getPtr(org_id)) |members| {
            try members.append(OrgMember{ .user_id = user_id, .role = role });
        } else {
            const new_list = std.ArrayList(OrgMember).init(self.allocator);
            try self.org_members.put(org_id, new_list);
            const members = self.org_members.getPtr(org_id).?;
            try members.append(OrgMember{ .user_id = user_id, .role = role });
        }
    }
    
    pub fn getOrganizationMemberRole(self: *MockDAO, org_id: i64, user_id: i64) ?OrgRole {
        if (self.org_members.get(org_id)) |members| {
            for (members.items) |member| {
                if (member.user_id == user_id) {
                    return member.role;
                }
            }
        }
        return null;
    }
    
    pub fn isOrganizationMember(self: *MockDAO, org_id: i64, user_id: i64) !bool {
        return self.getOrganizationMemberRole(org_id, user_id) != null;
    }
};

// Permission checker with database integration
pub const PermissionChecker = struct {
    dao: *MockDAO,
    cache: PermissionCache,
    
    pub fn init(allocator: std.mem.Allocator, dao: *MockDAO) PermissionChecker {
        return PermissionChecker{
            .dao = dao,
            .cache = PermissionCache.init(allocator),
        };
    }
    
    pub fn deinit(self: *PermissionChecker) void {
        self.cache.deinit();
    }
    
    pub fn checkUserRepoPermission(self: *PermissionChecker, allocator: std.mem.Allocator, user_id: ?i64, repo_id: i64) !Permission {
        // Check cache first
        const cache_key = PermissionCacheKey{ .user_id = user_id, .repo_id = repo_id };
        if (self.cache.get(cache_key)) |cached_permission| {
            return cached_permission;
        }
        
        const permission = try self.loadUserRepoPermission(allocator, user_id, repo_id);
        
        // Cache the permission
        try self.cache.put(cache_key, permission);
        
        return permission;
    }
    
    fn loadUserRepoPermission(self: *PermissionChecker, allocator: std.mem.Allocator, user_id: ?i64, repo_id: i64) !Permission {
        const repo = try self.dao.getRepositoryById(repo_id) orelse {
            return Permission{
                .access_mode = .None,
                .units = null,
                .everyone_access_mode = std.EnumMap(UnitType, AccessMode){},
                .anonymous_access_mode = std.EnumMap(UnitType, AccessMode){},
            };
        };
        defer repo.deinit(allocator);
        
        // Anonymous user handling
        if (user_id == null) {
            return self.getAnonymousPermission(repo);
        }
        
        const uid = user_id.?;
        
        // Check if user is repository owner
        if (repo.owner_type == .User and repo.owner_id == uid) {
            return Permission{
                .access_mode = .Owner,
                .units = null,
                .everyone_access_mode = std.EnumMap(UnitType, AccessMode){},
                .anonymous_access_mode = std.EnumMap(UnitType, AccessMode){},
            };
        }
        
        // Check collaborator access
        if (self.dao.getRepositoryCollaborator(repo_id, uid)) |access_mode| {
            return Permission{
                .access_mode = access_mode,
                .units = null,
                .everyone_access_mode = std.EnumMap(UnitType, AccessMode){},
                .anonymous_access_mode = std.EnumMap(UnitType, AccessMode){},
            };
        }
        
        // Check organization membership if repo is owned by organization
        if (repo.owner_type == .Organization) {
            if (self.dao.getOrganizationMemberRole(repo.owner_id, uid)) |role| {
                const access_mode = switch (role) {
                    .None => AccessMode.None,
                    .Member => AccessMode.Read,
                    .Admin => AccessMode.Admin,
                    .Owner => AccessMode.Owner,
                };
                return Permission{
                    .access_mode = access_mode,
                    .units = null,
                    .everyone_access_mode = std.EnumMap(UnitType, AccessMode){},
                    .anonymous_access_mode = std.EnumMap(UnitType, AccessMode){},
                };
            }
        }
        
        // Check if user is site admin
        if (try self.dao.getUserById(uid)) |user| {
            defer user.deinit(allocator);
            if (user.is_admin) {
                return Permission{
                    .access_mode = .Admin,
                    .units = null,
                    .everyone_access_mode = std.EnumMap(UnitType, AccessMode){},
                    .anonymous_access_mode = std.EnumMap(UnitType, AccessMode){},
                };
            }
        }
        
        // Default permission based on repository visibility
        return self.getPublicAccessPermission(repo);
    }
    
    fn getAnonymousPermission(self: *PermissionChecker, repo: Repository) Permission {
        _ = self;
        if (repo.visibility == .Public) {
            var anonymous_access = std.EnumMap(UnitType, AccessMode){};
            anonymous_access.put(.Code, .Read);
            anonymous_access.put(.Issues, .Read);
            anonymous_access.put(.Wiki, .Read);
            
            return Permission{
                .access_mode = .None,
                .units = null,
                .everyone_access_mode = std.EnumMap(UnitType, AccessMode){},
                .anonymous_access_mode = anonymous_access,
            };
        }
        
        return Permission{
            .access_mode = .None,
            .units = null,
            .everyone_access_mode = std.EnumMap(UnitType, AccessMode){},
            .anonymous_access_mode = std.EnumMap(UnitType, AccessMode){},
        };
    }
    
    fn getPublicAccessPermission(self: *PermissionChecker, repo: Repository) Permission {
        _ = self;
        if (repo.visibility == .Public) {
            var everyone_access = std.EnumMap(UnitType, AccessMode){};
            everyone_access.put(.Code, .Read);
            everyone_access.put(.Issues, .Read);
            everyone_access.put(.Wiki, .Read);
            
            return Permission{
                .access_mode = .None,
                .units = null,
                .everyone_access_mode = everyone_access,
                .anonymous_access_mode = std.EnumMap(UnitType, AccessMode){},
            };
        }
        
        return Permission{
            .access_mode = .None,
            .units = null,
            .everyone_access_mode = std.EnumMap(UnitType, AccessMode){},
            .anonymous_access_mode = std.EnumMap(UnitType, AccessMode){},
        };
    }
};

fn setupTestDatabase(allocator: std.mem.Allocator) !MockDAO {
    return MockDAO.init(allocator);
}

// Tests for Phase 1: Enterprise Permission Foundation with Multi-Tier Architecture
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
            var units = std.EnumMap(UnitType, AccessMode){};
            units.put(.Issues, .Write);
            units.put(.Wiki, .Read);
            break :blk units;
        },
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode){},
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode){},
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
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode){},
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode){},
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

test "TeamPermission unitAccessMode with unit override" {
    const team_permission = TeamPermission{
        .access_mode = .Write,
        .units = blk: {
            var units = std.EnumMap(UnitType, AccessMode){};
            units.put(.Issues, .Admin);
            units.put(.Wiki, .Read);
            break :blk units;
        },
    };

    try testing.expectEqual(AccessMode.Admin, team_permission.unitAccessMode(.Issues));
    try testing.expectEqual(AccessMode.Read, team_permission.unitAccessMode(.Wiki));
    try testing.expectEqual(AccessMode.Write, team_permission.unitAccessMode(.Code)); // Fallback to access_mode
}

test "TeamPermission admin access overrides unit restrictions" {
    const admin_team_permission = TeamPermission{
        .access_mode = .Admin,
        .units = blk: {
            var units = std.EnumMap(UnitType, AccessMode){};
            units.put(.Issues, .Read); // Restricted, but should be overridden
            break :blk units;
        },
    };

    // Admin access should override unit restrictions
    try testing.expectEqual(AccessMode.Admin, admin_team_permission.unitAccessMode(.Issues));
    try testing.expectEqual(AccessMode.Admin, admin_team_permission.unitAccessMode(.Wiki));
}

test "Permission cache operations work correctly" {
    const allocator = testing.allocator;

    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    const cache_key = PermissionCacheKey{ .user_id = 123, .repo_id = 456 };
    const permission = Permission{
        .access_mode = .Write,
        .units = null,
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode){},
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode){},
    };

    // Test cache miss
    try testing.expect(cache.get(cache_key) == null);

    // Test cache put and hit
    try cache.put(cache_key, permission);
    const cached_permission = cache.get(cache_key);
    try testing.expect(cached_permission != null);
    try testing.expectEqual(AccessMode.Write, cached_permission.?.access_mode);

    // Test cache invalidation
    cache.invalidateUser(123);
    try testing.expect(cache.get(cache_key) == null);
}

test "PermissionCacheKey hash and equality work correctly" {
    const key1 = PermissionCacheKey{ .user_id = 123, .repo_id = 456 };
    const key2 = PermissionCacheKey{ .user_id = 123, .repo_id = 456 };
    const key3 = PermissionCacheKey{ .user_id = 124, .repo_id = 456 };

    // Test equality
    try testing.expect(key1.eql(key2));
    try testing.expect(!key1.eql(key3));

    // Test hash consistency
    try testing.expectEqual(key1.hash(), key2.hash());
    try testing.expect(key1.hash() != key3.hash());
}

test "Permission everyone and anonymous access modes" {
    const permission = Permission{
        .access_mode = .None,
        .units = null,
        .everyone_access_mode = blk: {
            var everyone = std.EnumMap(UnitType, AccessMode){};
            everyone.put(.Code, .Read);
            break :blk everyone;
        },
        .anonymous_access_mode = blk: {
            var anonymous = std.EnumMap(UnitType, AccessMode){};
            anonymous.put(.Issues, .Read);
            break :blk anonymous;
        },
    };

    // Should use everyone/anonymous access modes when higher than user access
    try testing.expect(permission.canRead(.Code)); // From everyone_access_mode
    try testing.expect(permission.canRead(.Issues)); // From anonymous_access_mode
    try testing.expect(!permission.canRead(.Wiki)); // No access granted
}

// Tests for Phase 2: Database Integration and Repository Ownership
test "checkUserRepoPermission for repository owner" {
    const allocator = testing.allocator;
    
    var dao = try setupTestDatabase(allocator);
    defer dao.deinit();
    
    const owner_id = try dao.createUser(.{
        .name = "owner",
        .email = "owner@example.com",
    });
    
    const repo_id = try dao.createRepository(.{
        .name = "test-repo",
        .owner_id = owner_id,
        .owner_type = .User,
        .visibility = .Private,
    });
    
    var permission_checker = PermissionChecker.init(allocator, &dao);
    defer permission_checker.deinit();
    
    const permission = try permission_checker.checkUserRepoPermission(allocator, owner_id, repo_id);
    try testing.expectEqual(AccessMode.Owner, permission.access_mode);
    try testing.expect(permission.canAccess(.Settings, .Admin));
}

test "checkUserRepoPermission for repository collaborator" {
    const allocator = testing.allocator;
    
    var dao = try setupTestDatabase(allocator);
    defer dao.deinit();
    
    // Create owner and collaborator
    const owner_id = try dao.createUser(.{
        .name = "repo-owner",
        .email = "owner@example.com",
    });
    
    const collaborator_id = try dao.createUser(.{
        .name = "collaborator",
        .email = "collab@example.com",
    });
    
    const repo_id = try dao.createRepository(.{
        .name = "test-repo",
        .owner_id = owner_id,
        .owner_type = .User,
        .visibility = .Private,
    });
    
    // Grant write permission to collaborator
    try dao.addRepositoryCollaborator(repo_id, collaborator_id, .Write);
    
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
    defer dao.deinit();
    
    const owner_id = try dao.createUser(.{
        .name = "public-owner",
        .email = "public@example.com",
    });
    
    const repo_id = try dao.createRepository(.{
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

test "checkUserRepoPermission for organization member" {
    const allocator = testing.allocator;
    
    var dao = try setupTestDatabase(allocator);
    defer dao.deinit();
    
    // Create organization and member
    const org_id = try dao.createOrganization(.{
        .name = "test-org",
        .visibility = .Public,
    });
    
    const member_id = try dao.createUser(.{
        .name = "org-member",
        .email = "member@example.com",
    });
    
    // Add user as organization admin
    try dao.addOrganizationMember(org_id, member_id, .Admin);
    
    // Create repository owned by organization
    const repo_id = try dao.createRepository(.{
        .name = "org-repo",
        .owner_id = org_id,
        .owner_type = .Organization,
        .visibility = .Private,
    });
    
    var permission_checker = PermissionChecker.init(allocator, &dao);
    defer permission_checker.deinit();
    
    const permission = try permission_checker.checkUserRepoPermission(allocator, member_id, repo_id);
    try testing.expectEqual(AccessMode.Admin, permission.access_mode);
    try testing.expect(permission.canAccess(.Settings, .Admin));
}

test "checkUserRepoPermission uses cache correctly" {
    const allocator = testing.allocator;
    
    var dao = try setupTestDatabase(allocator);
    defer dao.deinit();
    
    const owner_id = try dao.createUser(.{
        .name = "cached-owner",
        .email = "cached@example.com",
    });
    
    const repo_id = try dao.createRepository(.{
        .name = "cached-repo",
        .owner_id = owner_id,
        .owner_type = .User,
        .visibility = .Private,
    });
    
    var permission_checker = PermissionChecker.init(allocator, &dao);
    defer permission_checker.deinit();
    
    // First call should load from database
    const permission1 = try permission_checker.checkUserRepoPermission(allocator, owner_id, repo_id);
    try testing.expectEqual(AccessMode.Owner, permission1.access_mode);
    
    // Second call should use cache
    const permission2 = try permission_checker.checkUserRepoPermission(allocator, owner_id, repo_id);
    try testing.expectEqual(AccessMode.Owner, permission2.access_mode);
    
    // Verify cache contains the permission
    const cache_key = PermissionCacheKey{ .user_id = owner_id, .repo_id = repo_id };
    const cached_permission = permission_checker.cache.get(cache_key);
    try testing.expect(cached_permission != null);
    try testing.expectEqual(AccessMode.Owner, cached_permission.?.access_mode);
}