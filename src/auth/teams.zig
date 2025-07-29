const std = @import("std");
const testing = std.testing;
const permissions = @import("permissions.zig");
const AccessMode = permissions.AccessMode;
const UnitType = permissions.UnitType;
const TeamPermission = permissions.TeamPermission;

// Team structure with hierarchy support
pub const Team = struct {
    id: i64,
    org_id: i64,
    name: []const u8,
    description: ?[]const u8 = null,
    access_mode: AccessMode,
    parent_id: ?i64 = null,
    
    pub fn deinit(self: Team, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |desc| {
            allocator.free(desc);
        }
    }
};

// Team member association
pub const TeamMember = struct {
    team_id: i64,
    user_id: i64,
    created_at: i64,
};

// Team repository access
pub const TeamRepository = struct {
    team_id: i64,
    repo_id: i64,
    created_at: i64,
};

// Team unit permissions for fine-grained control
pub const TeamUnit = struct {
    team_id: i64,
    unit_type: UnitType,
    access_mode: AccessMode,
};

// Team management system
pub const TeamManager = struct {
    allocator: std.mem.Allocator,
    teams: std.ArrayList(Team),
    team_members: std.ArrayList(TeamMember),
    team_repositories: std.ArrayList(TeamRepository),
    team_units: std.ArrayList(TeamUnit),
    
    pub fn init(allocator: std.mem.Allocator) TeamManager {
        return TeamManager{
            .allocator = allocator,
            .teams = std.ArrayList(Team).init(allocator),
            .team_members = std.ArrayList(TeamMember).init(allocator),
            .team_repositories = std.ArrayList(TeamRepository).init(allocator),
            .team_units = std.ArrayList(TeamUnit).init(allocator),
        };
    }
    
    pub fn deinit(self: *TeamManager) void {
        for (self.teams.items) |team| {
            team.deinit(self.allocator);
        }
        self.teams.deinit();
        self.team_members.deinit();
        self.team_repositories.deinit();
        self.team_units.deinit();
    }
    
    pub fn createTeam(self: *TeamManager, team_data: struct {
        org_id: i64,
        name: []const u8,
        description: ?[]const u8 = null,
        access_mode: AccessMode,
        parent_id: ?i64 = null,
    }) !i64 {
        const team_id = @as(i64, @intCast(self.teams.items.len + 1));
        
        const team = Team{
            .id = team_id,
            .org_id = team_data.org_id,
            .name = try self.allocator.dupe(u8, team_data.name),
            .description = if (team_data.description) |desc| try self.allocator.dupe(u8, desc) else null,
            .access_mode = team_data.access_mode,
            .parent_id = team_data.parent_id,
        };
        
        try self.teams.append(team);
        return team_id;
    }
    
    pub fn getTeamById(self: *TeamManager, team_id: i64) ?*const Team {
        for (self.teams.items) |*team| {
            if (team.id == team_id) {
                return team;
            }
        }
        return null;
    }
    
    pub fn addTeamMember(self: *TeamManager, team_id: i64, user_id: i64) !void {
        const member = TeamMember{
            .team_id = team_id,
            .user_id = user_id,
            .created_at = std.time.timestamp(),
        };
        try self.team_members.append(member);
    }
    
    pub fn removeTeamMember(self: *TeamManager, team_id: i64, user_id: i64) void {
        var i: usize = 0;
        while (i < self.team_members.items.len) {
            const member = self.team_members.items[i];
            if (member.team_id == team_id and member.user_id == user_id) {
                _ = self.team_members.swapRemove(i);
                return;
            }
            i += 1;
        }
    }
    
    pub fn isTeamMember(self: *TeamManager, team_id: i64, user_id: i64) bool {
        for (self.team_members.items) |member| {
            if (member.team_id == team_id and member.user_id == user_id) {
                return true;
            }
        }
        return false;
    }
    
    pub fn getUserTeams(self: *TeamManager, allocator: std.mem.Allocator, user_id: i64, org_id: i64) ![]const Team {
        var user_teams = std.ArrayList(Team).init(allocator);
        errdefer user_teams.deinit();
        
        for (self.team_members.items) |member| {
            if (member.user_id == user_id) {
                if (self.getTeamById(member.team_id)) |team| {
                    if (team.org_id == org_id) {
                        try user_teams.append(Team{
                            .id = team.id,
                            .org_id = team.org_id,
                            .name = try allocator.dupe(u8, team.name),
                            .description = if (team.description) |desc| try allocator.dupe(u8, desc) else null,
                            .access_mode = team.access_mode,
                            .parent_id = team.parent_id,
                        });
                    }
                }
            }
        }
        
        return user_teams.toOwnedSlice();
    }
    
    pub fn addTeamRepository(self: *TeamManager, team_id: i64, repo_id: i64) !void {
        const team_repo = TeamRepository{
            .team_id = team_id,
            .repo_id = repo_id,
            .created_at = std.time.timestamp(),
        };
        try self.team_repositories.append(team_repo);
    }
    
    pub fn hasTeamRepositoryAccess(self: *TeamManager, team_id: i64, repo_id: i64) bool {
        for (self.team_repositories.items) |team_repo| {
            if (team_repo.team_id == team_id and team_repo.repo_id == repo_id) {
                return true;
            }
        }
        return false;
    }
    
    pub fn getUserTeamRepoPermission(self: *TeamManager, user_id: i64, repo_id: i64) ?TeamPermission {
        // Find teams the user belongs to that have access to this repository
        var highest_access: AccessMode = .None;
        var team_units: ?std.EnumMap(UnitType, AccessMode) = null;
        
        for (self.team_members.items) |member| {
            if (member.user_id == user_id) {
                if (self.hasTeamRepositoryAccess(member.team_id, repo_id)) {
                    if (self.getTeamById(member.team_id)) |team| {
                        if (team.access_mode.atLeast(highest_access)) {
                            highest_access = team.access_mode;
                            
                            // Check for team-specific unit permissions
                            var units = std.EnumMap(UnitType, AccessMode){};
                            for (self.team_units.items) |team_unit| {
                                if (team_unit.team_id == member.team_id) {
                                    units.put(team_unit.unit_type, team_unit.access_mode);
                                }
                            }
                            
                            // Only set units if there are specific unit permissions
                            var has_units = false;
                            var unit_iter = units.iterator();
                            while (unit_iter.next()) |entry| {
                                if (entry.value.* != .None) {
                                    has_units = true;
                                    break;
                                }
                            }
                            
                            if (has_units) {
                                team_units = units;
                            }
                        }
                    }
                }
            }
        }
        
        if (highest_access == .None) {
            return null;
        }
        
        return TeamPermission{
            .access_mode = highest_access,
            .units = team_units,
        };
    }
    
    pub fn setTeamUnitPermission(self: *TeamManager, team_id: i64, unit_type: UnitType, access_mode: AccessMode) !void {
        // Check if permission already exists
        for (self.team_units.items) |*team_unit| {
            if (team_unit.team_id == team_id and team_unit.unit_type == unit_type) {
                team_unit.access_mode = access_mode;
                return;
            }
        }
        
        // Add new permission
        const team_unit = TeamUnit{
            .team_id = team_id,
            .unit_type = unit_type,
            .access_mode = access_mode,
        };
        try self.team_units.append(team_unit);
    }
    
    pub fn getTeamUnitPermission(self: *TeamManager, team_id: i64, unit_type: UnitType) ?AccessMode {
        for (self.team_units.items) |team_unit| {
            if (team_unit.team_id == team_id and team_unit.unit_type == unit_type) {
                return team_unit.access_mode;
            }
        }
        return null;
    }
    
    pub fn resolveTeamPermission(self: *TeamManager, team_id: i64) TeamPermission {
        if (self.getTeamById(team_id)) |team| {
            var units = std.EnumMap(UnitType, AccessMode){};
            var has_units = false;
            
            // Collect unit-specific permissions
            for (self.team_units.items) |team_unit| {
                if (team_unit.team_id == team_id) {
                    units.put(team_unit.unit_type, team_unit.access_mode);
                    has_units = true;
                }
            }
            
            return TeamPermission{
                .access_mode = team.access_mode,
                .units = if (has_units) units else null,
            };
        }
        
        return TeamPermission{
            .access_mode = .None,
            .units = null,
        };
    }
    
    pub fn getTeamHierarchy(self: *TeamManager, allocator: std.mem.Allocator, org_id: i64) ![]const Team {
        var org_teams = std.ArrayList(Team).init(allocator);
        errdefer org_teams.deinit();
        
        for (self.teams.items) |team| {
            if (team.org_id == org_id) {
                try org_teams.append(Team{
                    .id = team.id,
                    .org_id = team.org_id,
                    .name = try allocator.dupe(u8, team.name),
                    .description = if (team.description) |desc| try allocator.dupe(u8, desc) else null,
                    .access_mode = team.access_mode,
                    .parent_id = team.parent_id,
                });
            }
        }
        
        return org_teams.toOwnedSlice();
    }
};

// Tests for team management system
test "TeamManager creates and manages teams correctly" {
    const allocator = testing.allocator;
    
    var team_manager = TeamManager.init(allocator);
    defer team_manager.deinit();
    
    // Create a team
    const team_id = try team_manager.createTeam(.{
        .org_id = 1,
        .name = "Developers",
        .description = "Development team",
        .access_mode = .Write,
    });
    
    try testing.expectEqual(@as(i64, 1), team_id);
    
    // Retrieve the team
    const team = team_manager.getTeamById(team_id);
    try testing.expect(team != null);
    try testing.expectEqualStrings("Developers", team.?.name);
    try testing.expectEqual(AccessMode.Write, team.?.access_mode);
    try testing.expect(team.?.description != null);
    try testing.expectEqualStrings("Development team", team.?.description.?);
}

test "TeamManager handles team membership correctly" {
    const allocator = testing.allocator;
    
    var team_manager = TeamManager.init(allocator);
    defer team_manager.deinit();
    
    const team_id = try team_manager.createTeam(.{
        .org_id = 1,
        .name = "Test Team",
        .access_mode = .Read,
    });
    
    const user_id: i64 = 123;
    
    // Initially user is not a member
    try testing.expect(!team_manager.isTeamMember(team_id, user_id));
    
    // Add user to team
    try team_manager.addTeamMember(team_id, user_id);
    try testing.expect(team_manager.isTeamMember(team_id, user_id));
    
    // Remove user from team
    team_manager.removeTeamMember(team_id, user_id);
    try testing.expect(!team_manager.isTeamMember(team_id, user_id));
}

test "TeamManager resolves team repository permissions correctly" {
    const allocator = testing.allocator;
    
    var team_manager = TeamManager.init(allocator);
    defer team_manager.deinit();
    
    const team_id = try team_manager.createTeam(.{
        .org_id = 1,
        .name = "Admin Team",
        .access_mode = .Admin,
    });
    
    const user_id: i64 = 456;
    const repo_id: i64 = 789;
    
    // Add user to team and grant team access to repository
    try team_manager.addTeamMember(team_id, user_id);
    try team_manager.addTeamRepository(team_id, repo_id);
    
    // User should have admin permission through team
    const permission = team_manager.getUserTeamRepoPermission(user_id, repo_id);
    try testing.expect(permission != null);
    try testing.expectEqual(AccessMode.Admin, permission.?.access_mode);
}

test "TeamManager handles unit-level team permissions" {
    const allocator = testing.allocator;
    
    var team_manager = TeamManager.init(allocator);
    defer team_manager.deinit();
    
    const team_id = try team_manager.createTeam(.{
        .org_id = 1,
        .name = "Unit Team",
        .access_mode = .Write,
    });
    
    // Set unit-specific permissions
    try team_manager.setTeamUnitPermission(team_id, .Issues, .Admin);
    try team_manager.setTeamUnitPermission(team_id, .Wiki, .Read);
    
    // Verify unit permissions
    try testing.expectEqual(
        AccessMode.Admin,
        team_manager.getTeamUnitPermission(team_id, .Issues).?
    );
    try testing.expectEqual(
        AccessMode.Read,
        team_manager.getTeamUnitPermission(team_id, .Wiki).?
    );
    try testing.expect(team_manager.getTeamUnitPermission(team_id, .Code) == null);
    
    // Resolve team permission
    const team_permission = team_manager.resolveTeamPermission(team_id);
    try testing.expectEqual(AccessMode.Write, team_permission.access_mode);
    try testing.expect(team_permission.units != null);
    try testing.expectEqual(AccessMode.Admin, team_permission.unitAccessMode(.Issues));
    try testing.expectEqual(AccessMode.Read, team_permission.unitAccessMode(.Wiki));
    try testing.expectEqual(AccessMode.Write, team_permission.unitAccessMode(.Code)); // Fallback
}

test "TeamManager gets user teams for organization" {
    const allocator = testing.allocator;
    
    var team_manager = TeamManager.init(allocator);
    defer team_manager.deinit();
    
    const org1_id: i64 = 1;
    const org2_id: i64 = 2;
    const user_id: i64 = 123;
    
    // Create teams in different organizations
    const team1_id = try team_manager.createTeam(.{
        .org_id = org1_id,
        .name = "Org1 Team",
        .access_mode = .Write,
    });
    
    const team2_id = try team_manager.createTeam(.{
        .org_id = org2_id,
        .name = "Org2 Team",
        .access_mode = .Read,
    });
    
    const team3_id = try team_manager.createTeam(.{
        .org_id = org1_id,
        .name = "Another Org1 Team",
        .access_mode = .Admin,
    });
    
    // Add user to all teams
    try team_manager.addTeamMember(team1_id, user_id);
    try team_manager.addTeamMember(team2_id, user_id);
    try team_manager.addTeamMember(team3_id, user_id);
    
    // Get user teams for org1
    const org1_teams = try team_manager.getUserTeams(allocator, user_id, org1_id);
    defer {
        for (org1_teams) |team| {
            team.deinit(allocator);
        }
        allocator.free(org1_teams);
    }
    
    try testing.expectEqual(@as(usize, 2), org1_teams.len);
    
    // Verify team names (order might vary)
    var found_names = std.StringHashMap(bool).init(allocator);
    defer found_names.deinit();
    
    for (org1_teams) |team| {
        try found_names.put(team.name, true);
    }
    
    try testing.expect(found_names.contains("Org1 Team"));
    try testing.expect(found_names.contains("Another Org1 Team"));
    try testing.expect(!found_names.contains("Org2 Team"));
}

test "TeamManager resolves highest team permission for user with multiple teams" {
    const allocator = testing.allocator;
    
    var team_manager = TeamManager.init(allocator);
    defer team_manager.deinit();
    
    const user_id: i64 = 123;
    const repo_id: i64 = 456;
    
    // Create teams with different access levels
    const read_team_id = try team_manager.createTeam(.{
        .org_id = 1,
        .name = "Read Team",
        .access_mode = .Read,
    });
    
    const write_team_id = try team_manager.createTeam(.{
        .org_id = 1,
        .name = "Write Team",
        .access_mode = .Write,
    });
    
    const admin_team_id = try team_manager.createTeam(.{
        .org_id = 1,
        .name = "Admin Team",
        .access_mode = .Admin,
    });
    
    // Add user to all teams and grant repository access
    try team_manager.addTeamMember(read_team_id, user_id);
    try team_manager.addTeamMember(write_team_id, user_id);
    try team_manager.addTeamMember(admin_team_id, user_id);
    
    try team_manager.addTeamRepository(read_team_id, repo_id);
    try team_manager.addTeamRepository(write_team_id, repo_id);
    try team_manager.addTeamRepository(admin_team_id, repo_id);
    
    // Should get highest permission (Admin)
    const permission = team_manager.getUserTeamRepoPermission(user_id, repo_id);
    try testing.expect(permission != null);
    try testing.expectEqual(AccessMode.Admin, permission.?.access_mode);
}