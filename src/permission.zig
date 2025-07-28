const std = @import("std");
const testing = std.testing;

// Permission error types
pub const PermissionError = error{
    RepositoryNotFound,
    UserNotFound,
    DatabaseError,
    InvalidInput,
    RepositoryArchived, // Write denied to archived repos
    RepositoryMirror, // Write denied to mirrors
    OrganizationPrivate, // Access denied to private org
    UserRestricted, // Restricted user access denied
} || error{OutOfMemory};

// Access mode enumeration with permission levels
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

// Test for AccessMode
test "AccessMode.atLeast" {
    // None access tests
    try testing.expect(!AccessMode.None.atLeast(.Read));
    try testing.expect(!AccessMode.None.atLeast(.Write));
    try testing.expect(!AccessMode.None.atLeast(.Admin));
    try testing.expect(!AccessMode.None.atLeast(.Owner));
    try testing.expect(AccessMode.None.atLeast(.None));

    // Read access tests
    try testing.expect(AccessMode.Read.atLeast(.None));
    try testing.expect(AccessMode.Read.atLeast(.Read));
    try testing.expect(!AccessMode.Read.atLeast(.Write));
    try testing.expect(!AccessMode.Read.atLeast(.Admin));
    try testing.expect(!AccessMode.Read.atLeast(.Owner));

    // Write access tests
    try testing.expect(AccessMode.Write.atLeast(.None));
    try testing.expect(AccessMode.Write.atLeast(.Read));
    try testing.expect(AccessMode.Write.atLeast(.Write));
    try testing.expect(!AccessMode.Write.atLeast(.Admin));
    try testing.expect(!AccessMode.Write.atLeast(.Owner));

    // Admin access tests
    try testing.expect(AccessMode.Admin.atLeast(.None));
    try testing.expect(AccessMode.Admin.atLeast(.Read));
    try testing.expect(AccessMode.Admin.atLeast(.Write));
    try testing.expect(AccessMode.Admin.atLeast(.Admin));
    try testing.expect(!AccessMode.Admin.atLeast(.Owner));

    // Owner access tests
    try testing.expect(AccessMode.Owner.atLeast(.None));
    try testing.expect(AccessMode.Owner.atLeast(.Read));
    try testing.expect(AccessMode.Owner.atLeast(.Write));
    try testing.expect(AccessMode.Owner.atLeast(.Admin));
    try testing.expect(AccessMode.Owner.atLeast(.Owner));
}

test "AccessMode ordering" {
    try testing.expect(@intFromEnum(AccessMode.None) < @intFromEnum(AccessMode.Read));
    try testing.expect(@intFromEnum(AccessMode.Read) < @intFromEnum(AccessMode.Write));
    try testing.expect(@intFromEnum(AccessMode.Write) < @intFromEnum(AccessMode.Admin));
    try testing.expect(@intFromEnum(AccessMode.Admin) < @intFromEnum(AccessMode.Owner));
}

// Visibility types for users and organizations
pub const Visibility = enum {
    Public, // Visible to everyone
    Limited, // Visible to signed-in users (not restricted users)
    Private, // Visible only to members
};

test "Visibility enum values" {
    const public_vis = Visibility.Public;
    const limited_vis = Visibility.Limited;
    const private_vis = Visibility.Private;

    // Test that we can compare visibility types
    try testing.expect(public_vis == Visibility.Public);
    try testing.expect(limited_vis == Visibility.Limited);
    try testing.expect(private_vis == Visibility.Private);
    try testing.expect(public_vis != limited_vis);
    try testing.expect(limited_vis != private_vis);
    try testing.expect(public_vis != private_vis);
}

// Repository unit types for fine-grained permissions
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

test "UnitType enum values" {
    // Test all unit types are distinct
    const all_units = [_]UnitType{
        .Code,
        .Issues,
        .PullRequests,
        .Wiki,
        .Projects,
        .Actions,
        .Packages,
        .Settings,
    };

    // Verify all units are unique
    for (all_units, 0..) |unit1, i| {
        for (all_units[i + 1 ..]) |unit2| {
            try testing.expect(unit1 != unit2);
        }
    }

    // Test we can iterate over all values
    var count: usize = 0;
    inline for (std.meta.fields(UnitType)) |_| {
        count += 1;
    }
    try testing.expectEqual(@as(usize, 8), count);
}

// Permission struct with unit-level access control
pub const Permission = struct {
    access_mode: AccessMode,
    units: ?std.EnumMap(UnitType, AccessMode),
    everyone_access_mode: std.EnumMap(UnitType, AccessMode), // For signed-in users
    anonymous_access_mode: std.EnumMap(UnitType, AccessMode), // For anonymous users

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

        // Return the maximum of all applicable modes
        var max_mode = unit_mode;
        if (@intFromEnum(everyone_mode) > @intFromEnum(max_mode)) {
            max_mode = everyone_mode;
        }
        if (@intFromEnum(anonymous_mode) > @intFromEnum(max_mode)) {
            max_mode = anonymous_mode;
        }
        return max_mode;
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

test "Permission unit access with admin override" {
    // Admin should have full access regardless of unit settings
    var units = std.EnumMap(UnitType, AccessMode).initFull(.None);
    units.put(.Code, .Read);

    const perm = Permission{
        .access_mode = .Admin,
        .units = units,
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };

    // Admin should have admin access to all units
    try testing.expectEqual(AccessMode.Admin, perm.unitAccessMode(.Code));
    try testing.expectEqual(AccessMode.Admin, perm.unitAccessMode(.Issues));
    try testing.expect(perm.canWrite(.Code));
    try testing.expect(perm.canWrite(.Issues));
}

test "Permission unit access with null units (admin override)" {
    const perm = Permission{
        .access_mode = .Owner,
        .units = null,
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };

    // Owner with null units should have owner access to all
    try testing.expectEqual(AccessMode.Owner, perm.unitAccessMode(.Code));
    try testing.expectEqual(AccessMode.Owner, perm.unitAccessMode(.Issues));
}

test "Permission unit access normal user" {
    var units = std.EnumMap(UnitType, AccessMode).initFull(.None);
    units.put(.Code, .Read);
    units.put(.Issues, .Write);

    const perm = Permission{
        .access_mode = .Read,
        .units = units,
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };

    // Check specific unit permissions
    try testing.expectEqual(AccessMode.Read, perm.unitAccessMode(.Code));
    try testing.expectEqual(AccessMode.Write, perm.unitAccessMode(.Issues));
    try testing.expectEqual(AccessMode.None, perm.unitAccessMode(.Wiki));

    // Check access methods
    try testing.expect(perm.canRead(.Code));
    try testing.expect(!perm.canWrite(.Code));
    try testing.expect(perm.canWrite(.Issues));
    try testing.expect(!perm.canRead(.Wiki));
}

test "Permission with public access modes" {
    const units = std.EnumMap(UnitType, AccessMode).initFull(.None);
    var everyone_access = std.EnumMap(UnitType, AccessMode).initFull(.None);
    var anonymous_access = std.EnumMap(UnitType, AccessMode).initFull(.None);

    // User has no access, but everyone can read code
    everyone_access.put(.Code, .Read);
    // Anonymous users can read issues
    anonymous_access.put(.Issues, .Read);

    const perm = Permission{
        .access_mode = .None,
        .units = units,
        .everyone_access_mode = everyone_access,
        .anonymous_access_mode = anonymous_access,
    };

    // Should get access from everyone/anonymous modes
    try testing.expectEqual(AccessMode.Read, perm.unitAccessMode(.Code));
    try testing.expectEqual(AccessMode.Read, perm.unitAccessMode(.Issues));
    try testing.expectEqual(AccessMode.None, perm.unitAccessMode(.Wiki));
}

// Owner type (duplicated here to avoid circular imports in tests)
pub const OwnerType = enum {
    user,
    organization,
};

// UserExt type for testing
const UserExt = struct {
    id: i64,
    name: []const u8,
    is_admin: bool,
    is_restricted: bool,
    is_deleted: bool,
    is_active: bool,
    prohibit_login: bool,
    visibility: []const u8,
};

// Team type for testing
const Team = struct {
    id: i64,
    org_id: i64,
    name: []const u8,
    access_mode: []const u8,
    can_create_org_repo: bool,
    is_owner_team: bool,
    units: ?[]const u8,
    created_at: i64,

    pub fn hasAdminAccess(self: Team) bool {
        return self.can_create_org_repo or self.is_owner_team;
    }
};

// Mock DAO for testing (defined before use)
const MockDAO = struct {
    const Self = @This();
    const OrgMember = struct { org_id: i64, user_id: i64 };
    const TeamMember = struct { team_id: i64, user_id: i64 };
    const TeamRepo = struct { team_id: i64, repo_id: i64 };

    users: std.StringHashMap(UserExt),
    org_members: std.ArrayList(OrgMember),
    teams: std.ArrayList(Team),
    team_members: std.ArrayList(TeamMember),
    team_repos: std.ArrayList(TeamRepo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .users = std.StringHashMap(UserExt).init(allocator),
            .org_members = std.ArrayList(OrgMember).init(allocator),
            .teams = std.ArrayList(Team).init(allocator),
            .team_members = std.ArrayList(TeamMember).init(allocator),
            .team_repos = std.ArrayList(TeamRepo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.users.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*); // Free the key
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.visibility);
        }
        self.users.deinit();
        self.org_members.deinit();
        
        for (self.teams.items) |team| {
            self.allocator.free(team.name);
            self.allocator.free(team.access_mode);
            if (team.units) |units| self.allocator.free(units);
        }
        self.teams.deinit();
        self.team_members.deinit();
        self.team_repos.deinit();
    }

    pub fn addUser(self: *Self, user: UserExt) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{d}", .{user.id});
        // Don't defer free the key - it's owned by the hashmap
        
        const user_copy = UserExt{
            .id = user.id,
            .name = try self.allocator.dupe(u8, user.name),
            .is_admin = user.is_admin,
            .is_restricted = user.is_restricted,
            .is_deleted = user.is_deleted,
            .is_active = user.is_active,
            .prohibit_login = user.prohibit_login,
            .visibility = try self.allocator.dupe(u8, user.visibility),
        };
        try self.users.put(key, user_copy);
    }

    pub fn getUserExt(self: *Self, allocator: std.mem.Allocator, user_id: i64) !UserExt {
        const key = try std.fmt.allocPrint(self.allocator, "{d}", .{user_id});
        defer self.allocator.free(key);
        
        if (self.users.get(key)) |user| {
            return UserExt{
                .id = user.id,
                .name = try allocator.dupe(u8, user.name),
                .is_admin = user.is_admin,
                .is_restricted = user.is_restricted,
                .is_deleted = user.is_deleted,
                .is_active = user.is_active,
                .prohibit_login = user.prohibit_login,
                .visibility = try allocator.dupe(u8, user.visibility),
            };
        }
        return error.NotFound;
    }

    pub fn isOrganizationMember(self: *Self, org_id: i64, user_id: i64) !bool {
        for (self.org_members.items) |member| {
            if (member.org_id == org_id and member.user_id == user_id) {
                return true;
            }
        }
        return false;
    }

    pub fn addOrgMember(self: *Self, org_id: i64, user_id: i64) !void {
        try self.org_members.append(OrgMember{ .org_id = org_id, .user_id = user_id });
    }

    pub fn addTeam(self: *Self, team: Team) !void {
        const team_copy = Team{
            .id = team.id,
            .org_id = team.org_id,
            .name = try self.allocator.dupe(u8, team.name),
            .access_mode = try self.allocator.dupe(u8, team.access_mode),
            .can_create_org_repo = team.can_create_org_repo,
            .is_owner_team = team.is_owner_team,
            .units = if (team.units) |u| try self.allocator.dupe(u8, u) else null,
            .created_at = team.created_at,
        };
        try self.teams.append(team_copy);
    }

    pub fn addTeamMember(self: *Self, team_id: i64, user_id: i64) !void {
        try self.team_members.append(TeamMember{ .team_id = team_id, .user_id = user_id });
    }

    pub fn addTeamRepo(self: *Self, team_id: i64, repo_id: i64) !void {
        try self.team_repos.append(TeamRepo{ .team_id = team_id, .repo_id = repo_id });
    }

    pub fn getUserRepoTeams(self: *Self, allocator: std.mem.Allocator, org_id: i64, user_id: i64, repo_id: i64) !std.ArrayList(Team) {
        var result = std.ArrayList(Team).init(allocator);
        errdefer {
            for (result.items) |team| {
                allocator.free(team.name);
                allocator.free(team.access_mode);
                if (team.units) |u| allocator.free(u);
            }
            result.deinit();
        }

        // Find teams where user is member and team has access to repo
        for (self.teams.items) |team| {
            if (team.org_id != org_id) continue;

            // Check if user is member of this team
            var is_member = false;
            for (self.team_members.items) |tm| {
                if (tm.team_id == team.id and tm.user_id == user_id) {
                    is_member = true;
                    break;
                }
            }
            if (!is_member) continue;

            // Check if team has access to this repo
            var has_repo = false;
            for (self.team_repos.items) |tr| {
                if (tr.team_id == team.id and tr.repo_id == repo_id) {
                    has_repo = true;
                    break;
                }
            }
            if (!has_repo) continue;

            // Add copy of team to result
            const team_copy = Team{
                .id = team.id,
                .org_id = team.org_id,
                .name = try allocator.dupe(u8, team.name),
                .access_mode = try allocator.dupe(u8, team.access_mode),
                .can_create_org_repo = team.can_create_org_repo,
                .is_owner_team = team.is_owner_team,
                .units = if (team.units) |u| try allocator.dupe(u8, u) else null,
                .created_at = team.created_at,
            };
            try result.append(team_copy);
        }

        return result;
    }
};

// Forward declaration - interface for DAO
const DataAccessObject = if (@import("builtin").is_test) MockDAO else @import("database/dao.zig");

// Declare loadUserRepoPermission as it will be implemented later
fn loadUserRepoPermission(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    user_id: ?i64,
    repo_id: i64,
) PermissionError!Permission {
    _ = allocator;
    _ = dao;
    _ = user_id;
    _ = repo_id;
    // This will be implemented later
    return Permission{
        .access_mode = .None,
        .units = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };
}

// Request-level permission cache
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

        pub fn eql(self: CacheKey, other: CacheKey) bool {
            return self.user_id == other.user_id and self.repo_id == other.repo_id;
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

test "PermissionCache basic operations" {
    const allocator = testing.allocator;
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    // Test that cache starts empty
    try testing.expectEqual(@as(usize, 0), cache.cache.count());

    // Test cache key hashing and equality
    const key1 = PermissionCache.CacheKey{ .user_id = 123, .repo_id = 456 };
    const key2 = PermissionCache.CacheKey{ .user_id = 123, .repo_id = 456 };
    const key3 = PermissionCache.CacheKey{ .user_id = 789, .repo_id = 456 };

    try testing.expect(key1.eql(key2));
    try testing.expect(!key1.eql(key3));
    try testing.expectEqual(key1.hash(), key2.hash());
}

test "PermissionCache with null user_id" {
    const allocator = testing.allocator;
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    // Test cache keys with null user_id
    const key1 = PermissionCache.CacheKey{ .user_id = null, .repo_id = 123 };
    const key2 = PermissionCache.CacheKey{ .user_id = null, .repo_id = 123 };
    const key3 = PermissionCache.CacheKey{ .user_id = 456, .repo_id = 123 };

    try testing.expect(key1.eql(key2));
    try testing.expect(!key1.eql(key3));
}

// Check if organization or user is visible to requesting user
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
    const user = try dao.getUserExt(allocator, user_id);
    defer allocator.free(user.name);
    defer allocator.free(user.visibility);

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


test "hasOrgOrUserVisible - anonymous user" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Anonymous users only see public entities
    try testing.expect(try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 1, .user, .Public, null));
    try testing.expect(!try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 1, .user, .Limited, null));
    try testing.expect(!try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 1, .user, .Private, null));
}

test "hasOrgOrUserVisible - admin user" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add admin user
    try dao.addUser(.{
        .id = 123,
        .name = "admin",
        .is_admin = true,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Admins see everything
    try testing.expect(try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 1, .user, .Public, 123));
    try testing.expect(try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 1, .user, .Limited, 123));
    try testing.expect(try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 1, .user, .Private, 123));
    try testing.expect(try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 1, .organization, .Private, 123));
}

test "hasOrgOrUserVisible - self visibility" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add regular user
    try dao.addUser(.{
        .id = 456,
        .name = "user",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "private",
    });

    // Users always see themselves
    try testing.expect(try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 456, .user, .Private, 456));
}

test "hasOrgOrUserVisible - organization membership" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add regular user
    try dao.addUser(.{
        .id = 789,
        .name = "member",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add user as org member
    try dao.addOrgMember(100, 789);

    // Member sees private org
    try testing.expect(try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 100, .organization, .Private, 789));
    
    // Non-member doesn't see private org
    try testing.expect(!try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 200, .organization, .Private, 789));
}

test "hasOrgOrUserVisible - restricted user" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add restricted user
    try dao.addUser(.{
        .id = 999,
        .name = "restricted",
        .is_admin = false,
        .is_restricted = true,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Restricted user can't see limited orgs unless member
    try testing.expect(!try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 300, .organization, .Limited, 999));

    // Add as member
    try dao.addOrgMember(300, 999);
    
    // Now they can see it
    try testing.expect(try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 300, .organization, .Limited, 999));
}

// Check organization team permissions
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
    defer {
        for (teams.items) |team| {
            allocator.free(team.name);
            allocator.free(team.access_mode);
            if (team.units) |u| allocator.free(u);
        }
        teams.deinit();
    }

    // Check for admin teams first (they get full access immediately)
    for (teams.items) |team| {
        if (team.hasAdminAccess()) {
            permission.access_mode = .Owner; // Admin teams get Owner access
            permission.units = null; // Clear units map - admin overrides everything
            return permission;
        }
    }

    // Process each unit across all teams
    inline for (std.meta.fields(UnitType)) |field| {
        const unit_type = @field(UnitType, field.name);
        var max_unit_access = AccessMode.None;

        for (teams.items) |team| {
            // Get team's access mode for this unit
            const team_unit_mode = try getTeamUnitAccessMode(allocator, dao, team, unit_type);
            if (@intFromEnum(team_unit_mode) > @intFromEnum(max_unit_access)) {
                max_unit_access = team_unit_mode;
            }
        }

        if (permission.units) |*units| {
            units.put(unit_type, max_unit_access);
        }

        // Update overall access mode to be at least the max unit access
        if (@intFromEnum(max_unit_access) > @intFromEnum(permission.access_mode)) {
            permission.access_mode = max_unit_access;
        }
    }

    return permission;
}

// Get team unit access mode
fn getTeamUnitAccessMode(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    team: Team,
    unit_type: UnitType,
) !AccessMode {
    _ = allocator;
    _ = dao;
    _ = unit_type;
    
    // For now, just return the team's general access mode
    // In a real implementation, we'd parse the units JSON
    return std.meta.stringToEnum(AccessMode, team.access_mode) orelse .None;
}

test "checkOrgTeamPermission - no teams" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    const perm = try checkOrgTeamPermission(allocator, @ptrCast(&dao), 1, 100, 200);
    try testing.expectEqual(AccessMode.None, perm.access_mode);
    try testing.expect(perm.units != null);
}

test "checkOrgTeamPermission - admin team" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add admin team
    try dao.addTeam(.{
        .id = 1,
        .org_id = 10,
        .name = "admins",
        .access_mode = "admin",
        .can_create_org_repo = true,
        .is_owner_team = false,
        .units = null,
        .created_at = 1234567890,
    });

    // Add user to team
    try dao.addTeamMember(1, 100);
    
    // Add repo to team
    try dao.addTeamRepo(1, 200);

    const perm = try checkOrgTeamPermission(allocator, @ptrCast(&dao), 10, 100, 200);
    try testing.expectEqual(AccessMode.Owner, perm.access_mode);
    try testing.expect(perm.units == null); // Admin override
}

test "checkOrgTeamPermission - multiple teams" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add read team
    try dao.addTeam(.{
        .id = 1,
        .org_id = 10,
        .name = "readers",
        .access_mode = "Read",
        .can_create_org_repo = false,
        .is_owner_team = false,
        .units = null,
        .created_at = 1234567890,
    });

    // Add write team
    try dao.addTeam(.{
        .id = 2,
        .org_id = 10,
        .name = "writers",
        .access_mode = "Write",
        .can_create_org_repo = false,
        .is_owner_team = false,
        .units = null,
        .created_at = 1234567890,
    });

    // Add user to both teams
    try dao.addTeamMember(1, 100);
    try dao.addTeamMember(2, 100);
    
    // Add repo to both teams
    try dao.addTeamRepo(1, 200);
    try dao.addTeamRepo(2, 200);

    const perm = try checkOrgTeamPermission(allocator, @ptrCast(&dao), 10, 100, 200);
    try testing.expectEqual(AccessMode.Write, perm.access_mode); // Max of Read and Write
    
    // All units should have Write access
    if (perm.units) |units| {
        inline for (std.meta.fields(UnitType)) |field| {
            const unit_type = @field(UnitType, field.name);
            try testing.expectEqual(AccessMode.Write, units.get(unit_type).?);
        }
    }
}

test "checkOrgTeamPermission - owner team" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add owner team
    try dao.addTeam(.{
        .id = 1,
        .org_id = 10,
        .name = "owners",
        .access_mode = "Owner",
        .can_create_org_repo = false,
        .is_owner_team = true,
        .units = null,
        .created_at = 1234567890,
    });

    // Add user to team
    try dao.addTeamMember(1, 100);
    
    // Add repo to team
    try dao.addTeamRepo(1, 200);

    const perm = try checkOrgTeamPermission(allocator, @ptrCast(&dao), 10, 100, 200);
    try testing.expectEqual(AccessMode.Owner, perm.access_mode);
    try testing.expect(perm.units == null); // Owner team gets admin override
}