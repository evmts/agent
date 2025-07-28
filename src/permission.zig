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

    // Extended types for testing
    const RepositoryExt = struct {
        id: i64,
        owner_id: i64,
        owner_type: OwnerType,
        name: []const u8,
        is_private: bool,
        is_mirror: bool,
        is_archived: bool,
        is_deleted: bool,
        visibility: []const u8,
    };

    const Organization = struct {
        id: i64,
        name: []const u8,
        visibility: []const u8,
        max_repo_creation: i32,
        created_at: i64,
    };

    const Collaboration = struct {
        id: i64,
        repo_id: i64,
        user_id: i64,
        mode: []const u8,
        units: ?[]const u8,
        created_at: i64,
    };

    users: std.StringHashMap(UserExt),
    org_members: std.ArrayList(OrgMember),
    teams: std.ArrayList(Team),
    team_members: std.ArrayList(TeamMember),
    team_repos: std.ArrayList(TeamRepo),
    repos: std.ArrayList(RepositoryExt),
    orgs: std.StringHashMap(Organization),
    collaborations: std.ArrayList(Collaboration),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .users = std.StringHashMap(UserExt).init(allocator),
            .org_members = std.ArrayList(OrgMember).init(allocator),
            .teams = std.ArrayList(Team).init(allocator),
            .team_members = std.ArrayList(TeamMember).init(allocator),
            .team_repos = std.ArrayList(TeamRepo).init(allocator),
            .repos = std.ArrayList(RepositoryExt).init(allocator),
            .orgs = std.StringHashMap(Organization).init(allocator),
            .collaborations = std.ArrayList(Collaboration).init(allocator),
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

        for (self.repos.items) |repo| {
            self.allocator.free(repo.name);
            self.allocator.free(repo.visibility);
        }
        self.repos.deinit();

        var org_it = self.orgs.iterator();
        while (org_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*); // Free the key
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.visibility);
        }
        self.orgs.deinit();

        for (self.collaborations.items) |collab| {
            self.allocator.free(collab.mode);
            if (collab.units) |units| self.allocator.free(units);
        }
        self.collaborations.deinit();
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

    pub fn getRepositoryExt(self: *Self, allocator: std.mem.Allocator, repo_id: i64) !RepositoryExt {
        for (self.repos.items) |repo| {
            if (repo.id == repo_id) {
                return RepositoryExt{
                    .id = repo.id,
                    .owner_id = repo.owner_id,
                    .owner_type = repo.owner_type,
                    .name = try allocator.dupe(u8, repo.name),
                    .is_private = repo.is_private,
                    .is_mirror = repo.is_mirror,
                    .is_archived = repo.is_archived,
                    .is_deleted = repo.is_deleted,
                    .visibility = try allocator.dupe(u8, repo.visibility),
                };
            }
        }
        return error.NotFound;
    }

    pub fn getOrganization(self: *Self, allocator: std.mem.Allocator, org_id: i64) !Organization {
        const key = try std.fmt.allocPrint(self.allocator, "{d}", .{org_id});
        defer self.allocator.free(key);
        
        if (self.orgs.get(key)) |org| {
            return Organization{
                .id = org.id,
                .name = try allocator.dupe(u8, org.name),
                .visibility = try allocator.dupe(u8, org.visibility),
                .max_repo_creation = org.max_repo_creation,
                .created_at = org.created_at,
            };
        }
        return error.NotFound;
    }

    pub fn getCollaboration(self: *Self, allocator: std.mem.Allocator, repo_id: i64, user_id: i64) !Collaboration {
        for (self.collaborations.items) |collab| {
            if (collab.repo_id == repo_id and collab.user_id == user_id) {
                return Collaboration{
                    .id = collab.id,
                    .repo_id = collab.repo_id,
                    .user_id = collab.user_id,
                    .mode = try allocator.dupe(u8, collab.mode),
                    .units = if (collab.units) |u| try allocator.dupe(u8, u) else null,
                    .created_at = collab.created_at,
                };
            }
        }
        return error.NotFound;
    }

    pub fn addRepository(self: *Self, repo: RepositoryExt) !void {
        const repo_copy = RepositoryExt{
            .id = repo.id,
            .owner_id = repo.owner_id,
            .owner_type = repo.owner_type,
            .name = try self.allocator.dupe(u8, repo.name),
            .is_private = repo.is_private,
            .is_mirror = repo.is_mirror,
            .is_archived = repo.is_archived,
            .is_deleted = repo.is_deleted,
            .visibility = try self.allocator.dupe(u8, repo.visibility),
        };
        try self.repos.append(repo_copy);
    }

    pub fn addOrganization(self: *Self, org: Organization) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{d}", .{org.id});
        // Don't defer free the key - it's owned by the hashmap
        
        const org_copy = Organization{
            .id = org.id,
            .name = try self.allocator.dupe(u8, org.name),
            .visibility = try self.allocator.dupe(u8, org.visibility),
            .max_repo_creation = org.max_repo_creation,
            .created_at = org.created_at,
        };
        try self.orgs.put(key, org_copy);
    }

    pub fn addCollaboration(self: *Self, collab: Collaboration) !void {
        const collab_copy = Collaboration{
            .id = collab.id,
            .repo_id = collab.repo_id,
            .user_id = collab.user_id,
            .mode = try self.allocator.dupe(u8, collab.mode),
            .units = if (collab.units) |u| try self.allocator.dupe(u8, u) else null,
            .created_at = collab.created_at,
        };
        try self.collaborations.append(collab_copy);
    }
};

// Forward declaration - interface for DAO
const DataAccessObject = if (@import("builtin").is_test) MockDAO else @import("database/dao.zig");

// Load user repository permission following Gitea patterns
pub fn loadUserRepoPermission(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    user_id: ?i64,
    repo_id: i64,
) PermissionError!Permission {
    var permission = Permission{
        .access_mode = .None,
        .units = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };

    // Load repository with permission fields
    const repo = dao.getRepositoryExt(allocator, repo_id) catch |err| {
        if (err == error.NotFound) return error.RepositoryNotFound;
        return error.DatabaseError;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.visibility);
    }

    // Anonymous user handling
    if (user_id == null) {
        // Anonymous users only get read access to public repos
        if (!repo.is_private and std.mem.eql(u8, repo.visibility, "public")) {
            permission.access_mode = .Read;
            // For anonymous access, all units get read permission
            permission.anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.Read);
        }
        return permission;
    }

    const uid = user_id.?;

    // Load user to check admin/restricted status
    const user = dao.getUserExt(allocator, uid) catch |err| {
        if (err == error.NotFound) return error.UserNotFound;
        return error.DatabaseError;
    };
    defer {
        allocator.free(user.name);
        allocator.free(user.visibility);
    }

    // Check if user is deleted or inactive
    if (user.is_deleted or !user.is_active or user.prohibit_login) {
        return error.UserNotFound;
    }

    // Site admins have full access
    if (user.is_admin) {
        permission.access_mode = .Owner;
        permission.units = null; // Admin override
        return permission;
    }

    // Restricted users get limited access
    if (user.is_restricted) {
        // For now, restricted users get no access
        // In real implementation, we'd check if they explicitly have access
        return permission;
    }

    // Check repository owner visibility
    const owner_visibility = if (repo.owner_type == .organization) blk: {
        const org = dao.getOrganization(allocator, repo.owner_id) catch |err| {
            if (err == error.NotFound) return error.RepositoryNotFound;
            return error.DatabaseError;
        };
        defer {
            allocator.free(org.name);
            allocator.free(org.visibility);
        }
        break :blk std.meta.stringToEnum(Visibility, org.visibility) orelse .Public;
    } else blk: {
        const owner = dao.getUserExt(allocator, repo.owner_id) catch |err| {
            if (err == error.NotFound) return error.RepositoryNotFound;
            return error.DatabaseError;
        };
        defer {
            allocator.free(owner.name);
            allocator.free(owner.visibility);
        }
        break :blk std.meta.stringToEnum(Visibility, owner.visibility) orelse .Public;
    };

    // Check if user can see the owner
    const can_see_owner = try hasOrgOrUserVisible(
        allocator,
        dao,
        repo.owner_id,
        repo.owner_type,
        owner_visibility,
        uid,
    );

    if (!can_see_owner) {
        return permission; // No access
    }

    // Check if user is the repository owner
    if (repo.owner_type == .user and repo.owner_id == uid) {
        permission.access_mode = .Owner;
        permission.units = null; // Owner override
        return permission;
    }

    // Check organization permissions
    if (repo.owner_type == .organization) {
        permission = try checkOrgTeamPermission(allocator, dao, repo.owner_id, uid, repo_id);
    }

    // Check individual collaborations (overwrites team permissions if higher)
    const collab = dao.getCollaboration(allocator, repo_id, uid) catch |err| {
        if (err != error.NotFound) return error.DatabaseError;
        // No collaboration found, keep existing permissions
        return permission;
    };
    defer {
        allocator.free(collab.mode);
        if (collab.units) |u| allocator.free(u);
    }

    const collab_mode = std.meta.stringToEnum(AccessMode, collab.mode) orelse .None;
    if (@intFromEnum(collab_mode) > @intFromEnum(permission.access_mode)) {
        permission.access_mode = collab_mode;
        // TODO: Parse units JSON for fine-grained permissions
    }

    // Apply repository state restrictions
    if (repo.is_archived and permission.access_mode.atLeast(.Write)) {
        // Archived repos are read-only
        permission.access_mode = .Read;
        if (permission.units) |*units| {
            inline for (std.meta.fields(UnitType)) |field| {
                const unit_type = @field(UnitType, field.name);
                const current = units.get(unit_type) orelse .None;
                if (@intFromEnum(current) > @intFromEnum(AccessMode.Read)) {
                    units.put(unit_type, .Read);
                }
            }
        }
    }

    if (repo.is_mirror and permission.access_mode.atLeast(.Write)) {
        // Mirror repos are read-only
        permission.access_mode = .Read;
        if (permission.units) |*units| {
            inline for (std.meta.fields(UnitType)) |field| {
                const unit_type = @field(UnitType, field.name);
                const current = units.get(unit_type) orelse .None;
                if (@intFromEnum(current) > @intFromEnum(AccessMode.Read)) {
                    units.put(unit_type, .Read);
                }
            }
        }
    }

    // Set public access modes for non-private repos
    if (!repo.is_private) {
        const repo_visibility = std.meta.stringToEnum(Visibility, repo.visibility) orelse .Public;
        if (repo_visibility == .Public) {
            // Everyone gets read access to public repos
            permission.everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.Read);
            permission.anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.Read);
        } else if (repo_visibility == .Limited) {
            // Only signed-in users get read access to limited repos
            permission.everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.Read);
        }
    }

    return permission;
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

test "loadUserRepoPermission - anonymous user public repo" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add public repo
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "public-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    const perm = try loadUserRepoPermission(allocator, @ptrCast(&dao), null, 1);
    try testing.expectEqual(AccessMode.Read, perm.access_mode);
    try testing.expectEqual(AccessMode.Read, perm.anonymous_access_mode.get(.Code).?);
}

test "loadUserRepoPermission - anonymous user private repo" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add private repo
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "private-repo",
        .is_private = true,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "private",
    });

    const perm = try loadUserRepoPermission(allocator, @ptrCast(&dao), null, 1);
    try testing.expectEqual(AccessMode.None, perm.access_mode);
}

test "loadUserRepoPermission - site admin" {
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

    // Add private repo
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "private-repo",
        .is_private = true,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "private",
    });

    const perm = try loadUserRepoPermission(allocator, @ptrCast(&dao), 123, 1);
    try testing.expectEqual(AccessMode.Owner, perm.access_mode);
    try testing.expect(perm.units == null); // Admin override
}

test "loadUserRepoPermission - repository owner" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add repository owner
    try dao.addUser(.{
        .id = 100,
        .name = "owner",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add repository owned by user
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "my-repo",
        .is_private = true,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "private",
    });

    const perm = try loadUserRepoPermission(allocator, @ptrCast(&dao), 100, 1);
    try testing.expectEqual(AccessMode.Owner, perm.access_mode);
    try testing.expect(perm.units == null); // Owner override
}

test "loadUserRepoPermission - organization team member" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add user
    try dao.addUser(.{
        .id = 123,
        .name = "member",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add organization
    try dao.addOrganization(.{
        .id = 10,
        .name = "test-org",
        .visibility = "public",
        .max_repo_creation = -1,
        .created_at = 1234567890,
    });

    // Add repository owned by org
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 10,
        .owner_type = .organization,
        .name = "org-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    // Add team with write access
    try dao.addTeam(.{
        .id = 1,
        .org_id = 10,
        .name = "developers",
        .access_mode = "Write",
        .can_create_org_repo = false,
        .is_owner_team = false,
        .units = null,
        .created_at = 1234567890,
    });

    // Add user to team
    try dao.addTeamMember(1, 123);
    
    // Add repo to team
    try dao.addTeamRepo(1, 1);

    const perm = try loadUserRepoPermission(allocator, @ptrCast(&dao), 123, 1);
    try testing.expectEqual(AccessMode.Write, perm.access_mode);
}

test "loadUserRepoPermission - collaborator" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add user
    try dao.addUser(.{
        .id = 123,
        .name = "collaborator",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add repo owner
    try dao.addUser(.{
        .id = 100,
        .name = "owner",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "private-repo",
        .is_private = true,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "private",
    });

    // Add collaboration with write access
    try dao.addCollaboration(.{
        .id = 1,
        .repo_id = 1,
        .user_id = 123,
        .mode = "Write",
        .units = null,
        .created_at = 1234567890,
    });

    const perm = try loadUserRepoPermission(allocator, @ptrCast(&dao), 123, 1);
    try testing.expectEqual(AccessMode.Write, perm.access_mode);
}

test "loadUserRepoPermission - archived repository" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add repository owner
    try dao.addUser(.{
        .id = 100,
        .name = "owner",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add archived repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "archived-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = true,
        .is_deleted = false,
        .visibility = "public",
    });

    const perm = try loadUserRepoPermission(allocator, @ptrCast(&dao), 100, 1);
    // Owner would normally have Owner access, but archived repos are read-only
    try testing.expectEqual(AccessMode.Read, perm.access_mode);
}

test "loadUserRepoPermission - mirror repository" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add repository owner
    try dao.addUser(.{
        .id = 100,
        .name = "owner",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add mirror repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "mirror-repo",
        .is_private = false,
        .is_mirror = true,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    const perm = try loadUserRepoPermission(allocator, @ptrCast(&dao), 100, 1);
    // Owner would normally have Owner access, but mirror repos are read-only
    try testing.expectEqual(AccessMode.Read, perm.access_mode);
}

test "loadUserRepoPermission - restricted user" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add restricted user
    try dao.addUser(.{
        .id = 123,
        .name = "restricted",
        .is_admin = false,
        .is_restricted = true,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add public repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "public-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    const perm = try loadUserRepoPermission(allocator, @ptrCast(&dao), 123, 1);
    // Restricted users get no access for now
    try testing.expectEqual(AccessMode.None, perm.access_mode);
}

test "loadUserRepoPermission - deleted user" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add deleted user
    try dao.addUser(.{
        .id = 123,
        .name = "deleted",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = true,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    try testing.expectError(error.UserNotFound, loadUserRepoPermission(allocator, @ptrCast(&dao), 123, 1));
}

test "loadUserRepoPermission - inactive user" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add inactive user
    try dao.addUser(.{
        .id = 123,
        .name = "inactive",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = false,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    try testing.expectError(error.UserNotFound, loadUserRepoPermission(allocator, @ptrCast(&dao), 123, 1));
}

test "loadUserRepoPermission - user with login prohibited" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add user with login prohibited
    try dao.addUser(.{
        .id = 123,
        .name = "banned",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = true,
        .visibility = "public",
    });

    // Add repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    try testing.expectError(error.UserNotFound, loadUserRepoPermission(allocator, @ptrCast(&dao), 123, 1));
}

test "loadUserRepoPermission - repository not found" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add user
    try dao.addUser(.{
        .id = 123,
        .name = "user",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    try testing.expectError(error.RepositoryNotFound, loadUserRepoPermission(allocator, @ptrCast(&dao), 123, 999));
}

// Helper functions for common permission checks
pub fn canRead(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    user_id: ?i64,
    repo_id: i64,
    unit_type: UnitType,
) !bool {
    const perm = try loadUserRepoPermission(allocator, dao, user_id, repo_id);
    return perm.canRead(unit_type);
}

pub fn canWrite(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    user_id: ?i64,
    repo_id: i64,
    unit_type: UnitType,
) !bool {
    const perm = try loadUserRepoPermission(allocator, dao, user_id, repo_id);
    return perm.canWrite(unit_type);
}

pub fn canAccessUnit(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    user_id: ?i64,
    repo_id: i64,
    unit_type: UnitType,
    required_mode: AccessMode,
) !bool {
    const perm = try loadUserRepoPermission(allocator, dao, user_id, repo_id);
    return perm.canAccess(unit_type, required_mode);
}

test "helper functions - canRead" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add public repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "public-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    // Anonymous user can read public repo
    try testing.expect(try canRead(allocator, @ptrCast(&dao), null, 1, .Code));
    try testing.expect(try canRead(allocator, @ptrCast(&dao), null, 1, .Issues));
}

test "helper functions - canWrite" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Add user
    try dao.addUser(.{
        .id = 100,
        .name = "owner",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add repository owned by user
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "my-repo",
        .is_private = true,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "private",
    });

    // Owner can write to their repo
    try testing.expect(try canWrite(allocator, @ptrCast(&dao), 100, 1, .Code));
    try testing.expect(try canWrite(allocator, @ptrCast(&dao), 100, 1, .Issues));

    // Anonymous cannot write
    try testing.expect(!try canWrite(allocator, @ptrCast(&dao), null, 1, .Code));
}

test "helper functions - canAccessUnit" {
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

    // Add private repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "private-repo",
        .is_private = true,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "private",
    });

    // Admin can access all units at any level
    try testing.expect(try canAccessUnit(allocator, @ptrCast(&dao), 123, 1, .Code, .Read));
    try testing.expect(try canAccessUnit(allocator, @ptrCast(&dao), 123, 1, .Code, .Write));
    try testing.expect(try canAccessUnit(allocator, @ptrCast(&dao), 123, 1, .Code, .Admin));
    try testing.expect(try canAccessUnit(allocator, @ptrCast(&dao), 123, 1, .Code, .Owner));

    // Anonymous cannot access private repo
    try testing.expect(!try canAccessUnit(allocator, @ptrCast(&dao), null, 1, .Code, .Read));
}

test "helper functions - error propagation" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Test that errors are propagated correctly
    try testing.expectError(error.RepositoryNotFound, canRead(allocator, @ptrCast(&dao), null, 999, .Code));
    try testing.expectError(error.RepositoryNotFound, canWrite(allocator, @ptrCast(&dao), null, 999, .Code));
    try testing.expectError(error.RepositoryNotFound, canAccessUnit(allocator, @ptrCast(&dao), null, 999, .Code, .Read));
}

// Security middleware context
pub const SecurityContext = struct {
    user_id: ?i64,
    is_authenticated: bool,
    is_admin: bool,
    permission_cache: *PermissionCache,
    dao: *DataAccessObject,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        dao: *DataAccessObject,
        cache: *PermissionCache,
        user_id: ?i64,
    ) !SecurityContext {
        var ctx = SecurityContext{
            .user_id = user_id,
            .is_authenticated = user_id != null,
            .is_admin = false,
            .permission_cache = cache,
            .dao = dao,
            .allocator = allocator,
        };

        // Load admin status if user is authenticated
        if (user_id) |uid| {
            const user = dao.getUserExt(allocator, uid) catch |err| {
                if (err == error.NotFound) return error.UserNotFound;
                return error.DatabaseError;
            };
            defer {
                allocator.free(user.name);
                allocator.free(user.visibility);
            }
            ctx.is_admin = user.is_admin;
        }

        return ctx;
    }

    pub fn requireAuthentication(self: *const SecurityContext) !void {
        if (!self.is_authenticated) {
            return error.AuthenticationRequired;
        }
    }

    pub fn requireAdmin(self: *const SecurityContext) !void {
        try self.requireAuthentication();
        if (!self.is_admin) {
            return error.AdminRequired;
        }
    }

    pub fn requireRepoRead(self: *SecurityContext, repo_id: i64, unit_type: UnitType) !void {
        const perm = try self.permission_cache.getOrCompute(self.dao, self.user_id, repo_id);
        if (!perm.canRead(unit_type)) {
            return error.AccessDenied;
        }
    }

    pub fn requireRepoWrite(self: *SecurityContext, repo_id: i64, unit_type: UnitType) !void {
        const perm = try self.permission_cache.getOrCompute(self.dao, self.user_id, repo_id);
        if (!perm.canWrite(unit_type)) {
            return error.AccessDenied;
        }
    }

    pub fn requireRepoAdmin(self: *SecurityContext, repo_id: i64) !void {
        const perm = try self.permission_cache.getOrCompute(self.dao, self.user_id, repo_id);
        if (!perm.access_mode.atLeast(.Admin)) {
            return error.AccessDenied;
        }
    }

    pub fn requireRepoOwner(self: *SecurityContext, repo_id: i64) !void {
        const perm = try self.permission_cache.getOrCompute(self.dao, self.user_id, repo_id);
        if (!perm.access_mode.atLeast(.Owner)) {
            return error.AccessDenied;
        }
    }
};

// Security middleware errors
pub const SecurityError = error{
    AuthenticationRequired,
    AdminRequired,
    AccessDenied,
} || PermissionError;

test "SecurityContext - init and basic checks" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

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

    // Test anonymous context
    const anon_ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, null);
    try testing.expect(!anon_ctx.is_authenticated);
    try testing.expect(!anon_ctx.is_admin);
    try testing.expectError(error.AuthenticationRequired, anon_ctx.requireAuthentication());
    try testing.expectError(error.AuthenticationRequired, anon_ctx.requireAdmin());

    // Test authenticated admin context
    const admin_ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 123);
    try testing.expect(admin_ctx.is_authenticated);
    try testing.expect(admin_ctx.is_admin);
    try admin_ctx.requireAuthentication();
    try admin_ctx.requireAdmin();
}

test "SecurityContext - repository permissions" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    // Add regular user
    try dao.addUser(.{
        .id = 123,
        .name = "user",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add repository owned by user
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 123,
        .owner_type = .user,
        .name = "my-repo",
        .is_private = true,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "private",
    });

    // Add public repository owned by someone else
    try dao.addRepository(.{
        .id = 2,
        .owner_id = 999,
        .owner_type = .user,
        .name = "other-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    // Test user context
    var user_ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 123);
    
    // User can read/write/admin/own their own repo
    try user_ctx.requireRepoRead(1, .Code);
    try user_ctx.requireRepoWrite(1, .Code);
    try user_ctx.requireRepoAdmin(1);
    try user_ctx.requireRepoOwner(1);

    // User can read public repo but not write
    try user_ctx.requireRepoRead(2, .Code);
    try testing.expectError(error.AccessDenied, user_ctx.requireRepoWrite(2, .Code));
    try testing.expectError(error.AccessDenied, user_ctx.requireRepoAdmin(2));
    try testing.expectError(error.AccessDenied, user_ctx.requireRepoOwner(2));
}

test "SecurityContext - cached permissions" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    // Add user
    try dao.addUser(.{
        .id = 123,
        .name = "user",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Add repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    var ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 123);
    
    // First call should compute permission
    try testing.expectEqual(@as(usize, 0), cache.cache.count());
    try ctx.requireRepoRead(1, .Code);
    try testing.expectEqual(@as(usize, 1), cache.cache.count());
    
    // Second call should use cached value
    try ctx.requireRepoRead(1, .Code);
    try testing.expectEqual(@as(usize, 1), cache.cache.count());
}

// Example usage pattern for HTTP handlers
pub fn exampleHttpHandler(allocator: std.mem.Allocator, security_ctx: *SecurityContext, repo_id: i64) !void {
    // Check permissions at the start of the handler
    try security_ctx.requireRepoWrite(repo_id, .Code);
    
    // Rest of the handler logic here...
    _ = allocator;
}

// Comprehensive integration tests
test "integration - complex organization permissions" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    // Create organization
    try dao.addOrganization(.{
        .id = 10,
        .name = "test-org",
        .visibility = "public",
        .max_repo_creation = -1,
        .created_at = 1234567890,
    });

    // Create users
    try dao.addUser(.{
        .id = 100,
        .name = "owner",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    try dao.addUser(.{
        .id = 101,
        .name = "developer",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    try dao.addUser(.{
        .id = 102,
        .name = "reader",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Create repository owned by organization
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 10,
        .owner_type = .organization,
        .name = "org-repo",
        .is_private = true,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "private",
    });

    // Create teams
    try dao.addTeam(.{
        .id = 1,
        .org_id = 10,
        .name = "owners",
        .access_mode = "Owner",
        .can_create_org_repo = true,
        .is_owner_team = true,
        .units = null,
        .created_at = 1234567890,
    });

    try dao.addTeam(.{
        .id = 2,
        .org_id = 10,
        .name = "developers",
        .access_mode = "Write",
        .can_create_org_repo = false,
        .is_owner_team = false,
        .units = null,
        .created_at = 1234567890,
    });

    try dao.addTeam(.{
        .id = 3,
        .org_id = 10,
        .name = "readers",
        .access_mode = "Read",
        .can_create_org_repo = false,
        .is_owner_team = false,
        .units = null,
        .created_at = 1234567890,
    });

    // Add users to teams
    try dao.addTeamMember(1, 100); // owner in owners team
    try dao.addTeamMember(2, 101); // developer in developers team
    try dao.addTeamMember(3, 102); // reader in readers team

    // Add repository to teams
    try dao.addTeamRepo(1, 1);
    try dao.addTeamRepo(2, 1);
    try dao.addTeamRepo(3, 1);

    // Test owner permissions
    var owner_ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 100);
    try owner_ctx.requireRepoRead(1, .Code);
    try owner_ctx.requireRepoWrite(1, .Code);
    try owner_ctx.requireRepoAdmin(1);
    try owner_ctx.requireRepoOwner(1);

    // Test developer permissions
    var dev_ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 101);
    try dev_ctx.requireRepoRead(1, .Code);
    try dev_ctx.requireRepoWrite(1, .Code);
    try testing.expectError(error.AccessDenied, dev_ctx.requireRepoAdmin(1));
    try testing.expectError(error.AccessDenied, dev_ctx.requireRepoOwner(1));

    // Test reader permissions
    var reader_ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 102);
    try reader_ctx.requireRepoRead(1, .Code);
    try testing.expectError(error.AccessDenied, reader_ctx.requireRepoWrite(1, .Code));
    try testing.expectError(error.AccessDenied, reader_ctx.requireRepoAdmin(1));
    try testing.expectError(error.AccessDenied, reader_ctx.requireRepoOwner(1));

    // Test non-member (no access to private org repo)
    var non_member_ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 999);
    try testing.expectError(error.AccessDenied, non_member_ctx.requireRepoRead(1, .Code));
}

test "integration - collaboration overrides team permissions" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    // Create organization and users
    try dao.addOrganization(.{
        .id = 10,
        .name = "test-org",
        .visibility = "public",
        .max_repo_creation = -1,
        .created_at = 1234567890,
    });

    try dao.addUser(.{
        .id = 100,
        .name = "user",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Create repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 10,
        .owner_type = .organization,
        .name = "org-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    // Create team with read access
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

    // Add user to team
    try dao.addTeamMember(1, 100);
    try dao.addTeamRepo(1, 1);

    // User has read access via team
    var ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 100);
    try ctx.requireRepoRead(1, .Code);
    try testing.expectError(error.AccessDenied, ctx.requireRepoWrite(1, .Code));

    // Add collaboration with write access
    try dao.addCollaboration(.{
        .id = 1,
        .repo_id = 1,
        .user_id = 100,
        .mode = "Write",
        .units = null,
        .created_at = 1234567890,
    });

    // Clear cache to force re-computation
    cache.deinit();
    cache = PermissionCache.init(allocator);

    // Now user has write access
    ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 100);
    try ctx.requireRepoRead(1, .Code);
    try ctx.requireRepoWrite(1, .Code);
}

test "integration - private organization visibility" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    // Create private organization
    try dao.addOrganization(.{
        .id = 10,
        .name = "private-org",
        .visibility = "private",
        .max_repo_creation = -1,
        .created_at = 1234567890,
    });

    // Create users
    try dao.addUser(.{
        .id = 100,
        .name = "member",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    try dao.addUser(.{
        .id = 101,
        .name = "non-member",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Create public repository in private org
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 10,
        .owner_type = .organization,
        .name = "public-repo-private-org",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    // Add member to organization
    try dao.addOrgMember(10, 100);

    // Member can see repo despite private org
    var member_ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 100);
    try member_ctx.requireRepoRead(1, .Code);

    // Non-member cannot see repo because org is private
    var non_member_ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 101);
    const perm = try loadUserRepoPermission(allocator, @ptrCast(&dao), 101, 1);
    try testing.expectEqual(AccessMode.None, perm.access_mode);
}

test "integration - restricted user permissions" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    // Create restricted user
    try dao.addUser(.{
        .id = 100,
        .name = "restricted",
        .is_admin = false,
        .is_restricted = true,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Create public repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 999,
        .owner_type = .user,
        .name = "public-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    // Create limited visibility organization
    try dao.addOrganization(.{
        .id = 10,
        .name = "limited-org",
        .visibility = "limited",
        .max_repo_creation = -1,
        .created_at = 1234567890,
    });

    // Create repo in limited org
    try dao.addRepository(.{
        .id = 2,
        .owner_id = 10,
        .owner_type = .organization,
        .name = "limited-org-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    var ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 100);
    
    // Restricted users currently get no access
    const perm1 = try loadUserRepoPermission(allocator, @ptrCast(&dao), 100, 1);
    try testing.expectEqual(AccessMode.None, perm1.access_mode);

    // Restricted users can't see limited orgs unless member
    const perm2 = try loadUserRepoPermission(allocator, @ptrCast(&dao), 100, 2);
    try testing.expectEqual(AccessMode.None, perm2.access_mode);

    // Add restricted user as org member
    try dao.addOrgMember(10, 100);

    // Clear cache
    cache.deinit();
    cache = PermissionCache.init(allocator);

    // Now they can see the limited org
    const visible = try hasOrgOrUserVisible(allocator, @ptrCast(&dao), 10, .organization, .Limited, 100);
    try testing.expect(visible);
}

test "integration - repository state restrictions" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    // Create repository owner
    try dao.addUser(.{
        .id = 100,
        .name = "owner",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Create normal repository
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "normal-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    // Create archived repository
    try dao.addRepository(.{
        .id = 2,
        .owner_id = 100,
        .owner_type = .user,
        .name = "archived-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = true,
        .is_deleted = false,
        .visibility = "public",
    });

    // Create mirror repository
    try dao.addRepository(.{
        .id = 3,
        .owner_id = 100,
        .owner_type = .user,
        .name = "mirror-repo",
        .is_private = false,
        .is_mirror = true,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    var ctx = try SecurityContext.init(allocator, @ptrCast(&dao), &cache, 100);

    // Owner can write to normal repo
    try ctx.requireRepoWrite(1, .Code);

    // Owner cannot write to archived repo
    try testing.expectError(error.AccessDenied, ctx.requireRepoWrite(2, .Code));
    try ctx.requireRepoRead(2, .Code); // Can still read

    // Owner cannot write to mirror repo
    try testing.expectError(error.AccessDenied, ctx.requireRepoWrite(3, .Code));
    try ctx.requireRepoRead(3, .Code); // Can still read
}

test "integration - visibility and public access modes" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();

    // Create repositories with different visibility
    try dao.addRepository(.{
        .id = 1,
        .owner_id = 100,
        .owner_type = .user,
        .name = "public-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "public",
    });

    try dao.addRepository(.{
        .id = 2,
        .owner_id = 100,
        .owner_type = .user,
        .name = "limited-repo",
        .is_private = false,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "limited",
    });

    try dao.addRepository(.{
        .id = 3,
        .owner_id = 100,
        .owner_type = .user,
        .name = "private-repo",
        .is_private = true,
        .is_mirror = false,
        .is_archived = false,
        .is_deleted = false,
        .visibility = "private",
    });

    // Test anonymous access
    const perm1 = try loadUserRepoPermission(allocator, @ptrCast(&dao), null, 1);
    try testing.expectEqual(AccessMode.Read, perm1.access_mode);
    try testing.expectEqual(AccessMode.Read, perm1.anonymous_access_mode.get(.Code).?);

    const perm2 = try loadUserRepoPermission(allocator, @ptrCast(&dao), null, 2);
    try testing.expectEqual(AccessMode.None, perm2.access_mode);

    const perm3 = try loadUserRepoPermission(allocator, @ptrCast(&dao), null, 3);
    try testing.expectEqual(AccessMode.None, perm3.access_mode);

    // Create authenticated user
    try dao.addUser(.{
        .id = 200,
        .name = "user",
        .is_admin = false,
        .is_restricted = false,
        .is_deleted = false,
        .is_active = true,
        .prohibit_login = false,
        .visibility = "public",
    });

    // Test authenticated access
    const perm4 = try loadUserRepoPermission(allocator, @ptrCast(&dao), 200, 2);
    try testing.expectEqual(AccessMode.Read, perm4.access_mode);
    try testing.expectEqual(AccessMode.Read, perm4.everyone_access_mode.get(.Code).?);
}