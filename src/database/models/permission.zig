const std = @import("std");

// Owner type for repositories
pub const OwnerType = enum {
    user,
    organization,
};

// Organization model
pub const Organization = struct {
    id: i64,
    name: []const u8,
    visibility: []const u8, // "public", "limited", "private"
    max_repo_creation: i32,
    created_at: i64,
};

// Team model
pub const Team = struct {
    id: i64,
    org_id: i64,
    name: []const u8,
    access_mode: []const u8, // "none", "read", "write", "admin", "owner"
    can_create_org_repo: bool,
    is_owner_team: bool,
    units: ?[]const u8, // JSON string
    created_at: i64,

    pub fn hasAdminAccess(self: Team) bool {
        return self.can_create_org_repo or self.is_owner_team;
    }
};

// Team membership
pub const TeamUser = struct {
    team_id: i64,
    user_id: i64,
    created_at: i64,
};

// Team repository access
pub const TeamRepo = struct {
    team_id: i64,
    repo_id: i64,
    created_at: i64,
};

// Individual collaboration
pub const Collaboration = struct {
    id: i64,
    repo_id: i64,
    user_id: i64,
    mode: []const u8, // "none", "read", "write", "admin"
    units: ?[]const u8, // JSON string
    created_at: i64,
};

// Pre-computed access cache
pub const Access = struct {
    user_id: i64,
    repo_id: i64,
    mode: []const u8, // "none", "read", "write", "admin", "owner"
    updated_at: i64,
};

// Organization membership
pub const OrgUsers = struct {
    org_id: i64,
    user_id: i64,
    is_public: bool,
    created_at: i64,
};

// Extended repository model with permission fields
pub const RepositoryExt = struct {
    id: i64,
    owner_id: i64,
    owner_type: OwnerType,
    name: []const u8,
    is_private: bool,
    is_mirror: bool,
    is_archived: bool,
    is_deleted: bool,
    visibility: []const u8, // "public", "limited", "private"
};

// Extended user model with permission fields
pub const UserExt = struct {
    id: i64,
    name: []const u8,
    is_admin: bool,
    is_restricted: bool,
    is_deleted: bool,
    is_active: bool,
    prohibit_login: bool,
    visibility: []const u8, // "public", "limited", "private"
};

test "Permission models" {
    const org = Organization{
        .id = 1,
        .name = "test-org",
        .visibility = "public",
        .max_repo_creation = -1,
        .created_at = 1234567890,
    };
    try std.testing.expect(org.id == 1);

    const team = Team{
        .id = 1,
        .org_id = 1,
        .name = "admins",
        .access_mode = "admin",
        .can_create_org_repo = true,
        .is_owner_team = false,
        .units = null,
        .created_at = 1234567890,
    };
    try std.testing.expect(team.hasAdminAccess());
}