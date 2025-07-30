const std = @import("std");
const pg = @import("pg");
const user_models = @import("models/user.zig");
const repo_models = @import("models/repository.zig");
const issue_models = @import("models/issue.zig");
const milestone_models = @import("models/milestone.zig");
const action_models = @import("models/action.zig");
const permission_models = @import("models/permission.zig");

const DataAccessObject = @This();

pool: *pg.Pool,

pub const User = user_models.User;
pub const UserType = user_models.UserType;
pub const OrgUser = user_models.OrgUser;
pub const PublicKey = user_models.PublicKey;
pub const AuthToken = user_models.AuthToken;
pub const Repository = repo_models.Repository;
pub const Branch = repo_models.Branch;
pub const LFSMetaObject = repo_models.LFSMetaObject;
pub const LFSLock = repo_models.LFSLock;
pub const Issue = issue_models.Issue;
pub const Label = issue_models.Label;
pub const IssueLabel = issue_models.IssueLabel;
pub const Review = issue_models.Review;
pub const ReviewType = issue_models.ReviewType;
pub const Comment = issue_models.Comment;
pub const Milestone = milestone_models.Milestone;
pub const MilestoneState = milestone_models.MilestoneState;
pub const IssueMilestone = milestone_models.IssueMilestone;
pub const ActionRun = action_models.ActionRun;
pub const ActionJob = action_models.ActionJob;
pub const ActionStatus = action_models.ActionStatus;
pub const ActionRunner = action_models.ActionRunner;
pub const ActionRunnerToken = action_models.ActionRunnerToken;
pub const ActionArtifact = action_models.ActionArtifact;
pub const ActionSecret = action_models.ActionSecret;

// Permission models
pub const OwnerType = permission_models.OwnerType;
pub const Organization = permission_models.Organization;
pub const Team = permission_models.Team;
pub const TeamUser = permission_models.TeamUser;
pub const TeamRepo = permission_models.TeamRepo;
pub const Collaboration = permission_models.Collaboration;
pub const Access = permission_models.Access;
pub const OrgUsers = permission_models.OrgUsers;
pub const RepositoryExt = permission_models.RepositoryExt;
pub const UserExt = permission_models.UserExt;

pub fn init(connection_url: []const u8) !DataAccessObject {
    const uri = try std.Uri.parse(connection_url);
    const pool = try pg.Pool.initUri(std.heap.page_allocator, uri, .{ .size = 5 });
    
    return DataAccessObject{
        .pool = pool,
    };
}

pub fn deinit(self: *DataAccessObject) void {
    self.pool.deinit();
}

pub fn createUser(self: *DataAccessObject, allocator: std.mem.Allocator, user: User) !void {
    _ = allocator;
    const unix_time = std.time.timestamp();
    _ = try self.pool.exec(
        \\INSERT INTO users (name, email, passwd, type, is_admin, avatar, created_unix, updated_unix)
        \\VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
    , .{
        user.name, user.email, user.passwd, @intFromEnum(user.type),
        user.is_admin, user.avatar, unix_time, unix_time,
    });
}

pub fn getUserById(self: *DataAccessObject, allocator: std.mem.Allocator, id: i64) !?User {
    var maybe_row = try self.pool.row(
        \\SELECT id, name, email, passwd, type, is_admin, avatar, created_unix, updated_unix
        \\FROM users WHERE id = $1
    , .{id});
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const username = row.get([]const u8, 1);
        const email = row.get(?[]const u8, 2);
        const passwd = row.get(?[]const u8, 3);
        const user_type = row.get(i16, 4);
        const is_admin = row.get(bool, 5);
        const avatar = row.get(?[]const u8, 6);
        const created_unix = row.get(i64, 7);
        const updated_unix = row.get(i64, 8);
        
        // Allocate memory for strings since row data is temporary
        const owned_name = try allocator.dupe(u8, username);
        const owned_email = if (email) |e| try allocator.dupe(u8, e) else null;
        const owned_passwd = if (passwd) |p| try allocator.dupe(u8, p) else null;
        const owned_avatar = if (avatar) |a| try allocator.dupe(u8, a) else null;
        
        return User{
            .id = id,
            .name = owned_name,
            .email = owned_email,
            .passwd = owned_passwd,
            .type = @enumFromInt(user_type),
            .is_admin = is_admin,
            .avatar = owned_avatar,
            .created_unix = created_unix,
            .updated_unix = updated_unix,
        };
    }
    
    return null;
}

pub fn getUserByName(self: *DataAccessObject, allocator: std.mem.Allocator, name: []const u8) !?User {
    var maybe_row = try self.pool.row(
        \\SELECT id, name, email, passwd, type, is_admin, avatar, created_unix, updated_unix
        \\FROM users WHERE name = $1
    , .{name});
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const id = row.get(i64, 0);
        const username = row.get([]const u8, 1);
        const email = row.get(?[]const u8, 2);
        const passwd = row.get(?[]const u8, 3);
        const user_type = row.get(i16, 4);
        const is_admin = row.get(bool, 5);
        const avatar = row.get(?[]const u8, 6);
        const created_unix = row.get(i64, 7);
        const updated_unix = row.get(i64, 8);
        
        // Allocate memory for strings since row data is temporary
        const owned_name = try allocator.dupe(u8, username);
        const owned_email = if (email) |e| try allocator.dupe(u8, e) else null;
        const owned_passwd = if (passwd) |p| try allocator.dupe(u8, p) else null;
        const owned_avatar = if (avatar) |a| try allocator.dupe(u8, a) else null;
        
        return User{
            .id = id,
            .name = owned_name,
            .email = owned_email,
            .passwd = owned_passwd,
            .type = @enumFromInt(user_type),
            .is_admin = is_admin,
            .avatar = owned_avatar,
            .created_unix = created_unix,
            .updated_unix = updated_unix,
        };
    }
    
    return null;
}

pub fn updateUserName(self: *DataAccessObject, allocator: std.mem.Allocator, old_name: []const u8, new_name: []const u8) !void {
    _ = allocator;
    _ = try self.pool.exec("UPDATE users SET name = $1 WHERE name = $2", .{ new_name, old_name });
}

pub fn deleteUser(self: *DataAccessObject, allocator: std.mem.Allocator, name: []const u8) !void {
    _ = allocator;
    _ = try self.pool.exec("DELETE FROM users WHERE name = $1", .{name});
}

pub fn updateUserAvatar(self: *DataAccessObject, allocator: std.mem.Allocator, id: i64, avatar: []const u8) !void {
    _ = allocator;
    const unix_time = std.time.timestamp();
    _ = try self.pool.exec("UPDATE users SET avatar = $1, updated_unix = $2 WHERE id = $3", .{ avatar, unix_time, id });
}

pub fn updateUserEmail(self: *DataAccessObject, allocator: std.mem.Allocator, id: i64, email: []const u8) !void {
    _ = allocator;
    const unix_time = std.time.timestamp();
    _ = try self.pool.exec("UPDATE users SET email = $1, updated_unix = $2 WHERE id = $3", .{ email, unix_time, id });
}

pub fn updateUserPassword(self: *DataAccessObject, allocator: std.mem.Allocator, id: i64, password: []const u8) !void {
    _ = allocator;
    const unix_time = std.time.timestamp();
    _ = try self.pool.exec("UPDATE users SET passwd = $1, updated_unix = $2 WHERE id = $3", .{ password, unix_time, id });
}

pub fn updateUserAdminStatus(self: *DataAccessObject, allocator: std.mem.Allocator, id: i64, is_admin: bool) !void {
    _ = allocator;
    const unix_time = std.time.timestamp();
    _ = try self.pool.exec("UPDATE users SET is_admin = $1, updated_unix = $2 WHERE id = $3", .{ is_admin, unix_time, id });
}

pub fn listUsers(self: *DataAccessObject, allocator: std.mem.Allocator) ![]User {
    var result = try self.pool.query(
        \\SELECT id, name, email, passwd, type, is_admin, avatar, created_unix, updated_unix
        \\FROM users ORDER BY id
    , .{});
    defer result.deinit();
    
    var users = std.ArrayList(User).init(allocator);
    errdefer {
        for (users.items) |user| {
            allocator.free(user.name);
            if (user.email) |e| allocator.free(e);
            if (user.passwd) |p| allocator.free(p);
            if (user.avatar) |a| allocator.free(a);
        }
        users.deinit();
    }
    
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const username = row.get([]const u8, 1);
        const email = row.get(?[]const u8, 2);
        const passwd = row.get(?[]const u8, 3);
        const user_type = row.get(i16, 4);
        const is_admin = row.get(bool, 5);
        const avatar = row.get(?[]const u8, 6);
        const created_unix = row.get(i64, 7);
        const updated_unix = row.get(i64, 8);
        
        const owned_name = try allocator.dupe(u8, username);
        const owned_email = if (email) |e| try allocator.dupe(u8, e) else null;
        const owned_passwd = if (passwd) |p| try allocator.dupe(u8, p) else null;
        const owned_avatar = if (avatar) |a| try allocator.dupe(u8, a) else null;
        
        try users.append(User{
            .id = id,
            .name = owned_name,
            .email = owned_email,
            .passwd = owned_passwd,
            .type = @enumFromInt(user_type),
            .is_admin = is_admin,
            .avatar = owned_avatar,
            .created_unix = created_unix,
            .updated_unix = updated_unix,
        });
    }
    
    return users.toOwnedSlice();
}

// Organization User methods
pub fn addUserToOrg(self: *DataAccessObject, allocator: std.mem.Allocator, uid: i64, org_id: i64, is_owner: bool) !void {
    _ = allocator;
    _ = try self.pool.exec(
        \\INSERT INTO org_user (uid, org_id, is_owner)
        \\VALUES ($1, $2, $3)
    , .{ uid, org_id, is_owner });
}

pub fn getOrgUsers(self: *DataAccessObject, allocator: std.mem.Allocator, org_id: i64) ![]OrgUser {
    var result = try self.pool.query(
        \\SELECT id, uid, org_id, is_owner
        \\FROM org_user WHERE org_id = $1 ORDER BY id
    , .{org_id});
    defer result.deinit();
    
    var org_users = std.ArrayList(OrgUser).init(allocator);
    errdefer org_users.deinit();
    
    while (try result.next()) |row| {
        try org_users.append(OrgUser{
            .id = row.get(i64, 0),
            .uid = row.get(i64, 1),
            .org_id = row.get(i64, 2),
            .is_owner = row.get(bool, 3),
        });
    }
    
    return org_users.toOwnedSlice();
}

pub fn removeUserFromOrg(self: *DataAccessObject, allocator: std.mem.Allocator, uid: i64, org_id: i64) !void {
    _ = allocator;
    _ = try self.pool.exec("DELETE FROM org_user WHERE uid = $1 AND org_id = $2", .{ uid, org_id });
}

pub const UserOrganization = struct {
    org: User,
    is_owner: bool,
};

pub fn getUserOrganizations(self: *DataAccessObject, allocator: std.mem.Allocator, uid: i64) ![]UserOrganization {
    var result = try self.pool.query(
        \\SELECT u.id, u.name, u.email, u.passwd, u.type, u.is_admin, u.avatar, u.created_unix, u.updated_unix, ou.is_owner
        \\FROM org_user ou
        \\JOIN users u ON u.id = ou.org_id
        \\WHERE ou.uid = $1 AND u.type = 1
        \\ORDER BY u.name
    , .{uid});
    defer result.deinit();
    
    var orgs = std.ArrayList(UserOrganization).init(allocator);
    errdefer {
        for (orgs.items) |org| {
            allocator.free(org.org.name);
            if (org.org.email) |e| allocator.free(e);
            if (org.org.passwd) |p| allocator.free(p);
            if (org.org.avatar) |a| allocator.free(a);
        }
        orgs.deinit();
    }
    
    while (try result.next()) |row| {
        const name = row.get([]const u8, 1);
        const email = row.get(?[]const u8, 2);
        const passwd = row.get(?[]const u8, 3);
        const avatar = row.get(?[]const u8, 6);
        
        try orgs.append(UserOrganization{
            .org = User{
                .id = row.get(i64, 0),
                .name = try allocator.dupe(u8, name),
                .email = if (email) |e| try allocator.dupe(u8, e) else null,
                .passwd = if (passwd) |p| try allocator.dupe(u8, p) else null,
                .type = @enumFromInt(row.get(i16, 4)),
                .is_admin = row.get(bool, 5),
                .avatar = if (avatar) |a| try allocator.dupe(u8, a) else null,
                .created_unix = row.get(i64, 7),
                .updated_unix = row.get(i64, 8),
            },
            .is_owner = row.get(bool, 9),
        });
    }
    
    return orgs.toOwnedSlice();
}

// SSH Key methods
pub fn addPublicKey(self: *DataAccessObject, allocator: std.mem.Allocator, key: PublicKey) !void {
    _ = allocator;
    const unix_time = std.time.timestamp();
    _ = try self.pool.exec(
        \\INSERT INTO public_key (owner_id, name, content, fingerprint, created_unix, updated_unix)
        \\VALUES ($1, $2, $3, $4, $5, $6)
    , .{ key.owner_id, key.name, key.content, key.fingerprint, unix_time, unix_time });
}

pub fn createPublicKey(self: *DataAccessObject, allocator: std.mem.Allocator, key: PublicKey) !i64 {
    _ = allocator;
    const unix_time = std.time.timestamp();
    const result = try self.pool.query(
        \\INSERT INTO public_key (owner_id, name, content, fingerprint, created_unix, updated_unix)
        \\VALUES ($1, $2, $3, $4, $5, $6) RETURNING id
    , .{ key.owner_id, key.name, key.content, key.fingerprint, unix_time, unix_time });
    
    if (try result.next()) |row| {
        return row.get(i64, 0);
    }
    
    return error.DatabaseError;
}

pub fn getUserPublicKeys(self: *DataAccessObject, allocator: std.mem.Allocator, owner_id: i64) ![]PublicKey {
    var result = try self.pool.query(
        \\SELECT id, owner_id, name, content, fingerprint, created_unix, updated_unix
        \\FROM public_key WHERE owner_id = $1 ORDER BY id
    , .{owner_id});
    defer result.deinit();
    
    var keys = std.ArrayList(PublicKey).init(allocator);
    errdefer {
        for (keys.items) |key| {
            allocator.free(key.name);
            allocator.free(key.content);
            allocator.free(key.fingerprint);
        }
        keys.deinit();
    }
    
    while (try result.next()) |row| {
        const name = row.get([]const u8, 2);
        const content = row.get([]const u8, 3);
        const fingerprint = row.get([]const u8, 4);
        
        try keys.append(PublicKey{
            .id = row.get(i64, 0),
            .owner_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, name),
            .content = try allocator.dupe(u8, content),
            .fingerprint = try allocator.dupe(u8, fingerprint),
            .created_unix = row.get(i64, 5),
            .updated_unix = row.get(i64, 6),
        });
    }
    
    return keys.toOwnedSlice();
}

pub fn deletePublicKey(self: *DataAccessObject, allocator: std.mem.Allocator, id: i64) !void {
    _ = allocator;
    _ = try self.pool.exec("DELETE FROM public_key WHERE id = $1", .{id});
}

// Auth Token methods
pub fn createAuthToken(self: *DataAccessObject, allocator: std.mem.Allocator, user_id: i64) !AuthToken {
    var token_bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&token_bytes);
    
    // Convert to hex string
    var token_hex: [64]u8 = undefined;
    for (token_bytes, 0..) |b, i| {
        _ = std.fmt.bufPrint(token_hex[i * 2 ..][0..2], "{x:0>2}", .{b}) catch unreachable;
    }
    const token = try allocator.dupe(u8, &token_hex);
    defer allocator.free(token);
    
    const unix_time = std.time.timestamp();
    const expires_unix = unix_time + (30 * 24 * 60 * 60); // 30 days
    
    var row = try self.pool.row(
        \\INSERT INTO auth_token (user_id, token, created_unix, expires_unix)
        \\VALUES ($1, $2, $3, $4)
        \\RETURNING id
    , .{ user_id, token, unix_time, expires_unix }) orelse return error.DatabaseError;
    defer row.deinit() catch {};
    
    const id = row.get(i64, 0);
    
    return AuthToken{
        .id = id,
        .user_id = user_id,
        .token = try allocator.dupe(u8, token),
        .created_unix = unix_time,
        .expires_unix = expires_unix,
    };
}

pub fn getAuthToken(self: *DataAccessObject, allocator: std.mem.Allocator, token: []const u8) !?AuthToken {
    const unix_time = std.time.timestamp();
    
    var maybe_row = try self.pool.row(
        \\SELECT id, user_id, token, created_unix, expires_unix
        \\FROM auth_token WHERE token = $1 AND expires_unix > $2
    , .{ token, unix_time });
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const token_str = row.get([]const u8, 2);
        
        return AuthToken{
            .id = row.get(i64, 0),
            .user_id = row.get(i64, 1),
            .token = try allocator.dupe(u8, token_str),
            .created_unix = row.get(i64, 3),
            .expires_unix = row.get(i64, 4),
        };
    }
    
    return null;
}

pub fn deleteAuthToken(self: *DataAccessObject, allocator: std.mem.Allocator, token: []const u8) !void {
    _ = allocator;
    _ = try self.pool.exec("DELETE FROM auth_token WHERE token = $1", .{token});
}

pub fn deleteExpiredTokens(self: *DataAccessObject, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const unix_time = std.time.timestamp();
    _ = try self.pool.exec("DELETE FROM auth_token WHERE expires_unix < $1", .{unix_time});
}

// Repository methods
pub fn createRepository(self: *DataAccessObject, allocator: std.mem.Allocator, repo: Repository) !i64 {
    _ = allocator;
    const unix_time = std.time.timestamp();
    var row = try self.pool.row(
        \\INSERT INTO repository (owner_id, lower_name, name, description, default_branch, 
        \\  is_private, is_fork, fork_id, created_unix, updated_unix)
        \\VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        \\RETURNING id
    , .{
        repo.owner_id, repo.lower_name, repo.name, repo.description,
        repo.default_branch, repo.is_private, repo.is_fork, repo.fork_id,
        unix_time, unix_time,
    }) orelse return error.DatabaseError;
    defer row.deinit() catch {};
    
    return row.get(i64, 0);
}

pub fn getRepositoryByName(self: *DataAccessObject, allocator: std.mem.Allocator, owner_id: i64, name: []const u8) !?Repository {
    const lower_name = try std.ascii.allocLowerString(allocator, name);
    defer allocator.free(lower_name);
    
    var maybe_row = try self.pool.row(
        \\SELECT id, owner_id, lower_name, name, description, default_branch,
        \\  is_private, is_fork, fork_id, created_unix, updated_unix
        \\FROM repository WHERE owner_id = $1 AND lower_name = $2
    , .{ owner_id, lower_name });
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const repo_name = row.get([]const u8, 3);
        const repo_lower_name = row.get([]const u8, 2);
        const desc = row.get(?[]const u8, 4);
        const default_branch = row.get([]const u8, 5);
        
        return Repository{
            .id = row.get(i64, 0),
            .owner_id = row.get(i64, 1),
            .lower_name = try allocator.dupe(u8, repo_lower_name),
            .name = try allocator.dupe(u8, repo_name),
            .description = if (desc) |d| try allocator.dupe(u8, d) else null,
            .default_branch = try allocator.dupe(u8, default_branch),
            .is_private = row.get(bool, 6),
            .is_fork = row.get(bool, 7),
            .fork_id = row.get(?i64, 8),
            .created_unix = row.get(i64, 9),
            .updated_unix = row.get(i64, 10),
        };
    }
    
    return null;
}

pub const RepositoryUpdate = struct {
    description: ?[]const u8,
    is_private: ?bool,
    default_branch: ?[]const u8,
};

pub fn updateRepository(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64, updates: RepositoryUpdate) !void {
    _ = allocator;
    const unix_time = std.time.timestamp();
    
    // For simplicity, just update with provided fields
    if (updates.description != null and updates.is_private != null and updates.default_branch != null) {
        _ = try self.pool.exec(
            \\UPDATE repository SET description = $1, is_private = $2, default_branch = $3, updated_unix = $4 WHERE id = $5
        , .{ updates.description, updates.is_private.?, updates.default_branch, unix_time, repo_id });
    } else if (updates.description != null) {
        _ = try self.pool.exec(
            \\UPDATE repository SET description = $1, updated_unix = $2 WHERE id = $3
        , .{ updates.description, unix_time, repo_id });
    } else if (updates.is_private != null) {
        _ = try self.pool.exec(
            \\UPDATE repository SET is_private = $1, updated_unix = $2 WHERE id = $3
        , .{ updates.is_private.?, unix_time, repo_id });
    } else if (updates.default_branch != null) {
        _ = try self.pool.exec(
            \\UPDATE repository SET default_branch = $1, updated_unix = $2 WHERE id = $3
        , .{ updates.default_branch, unix_time, repo_id });
    }
}

pub fn deleteRepository(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64) !void {
    _ = allocator;
    _ = try self.pool.exec("DELETE FROM repository WHERE id = $1", .{repo_id});
}

pub fn forkRepository(self: *DataAccessObject, allocator: std.mem.Allocator, source_id: i64, owner_id: i64, name: []const u8) !i64 {
    // Get source repository
    var maybe_row = try self.pool.row(
        \\SELECT lower_name, description, default_branch, is_private
        \\FROM repository WHERE id = $1
    , .{source_id});
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const lower_name = row.get([]const u8, 0);
        const description = row.get(?[]const u8, 1);
        const default_branch = row.get([]const u8, 2);
        const is_private = row.get(bool, 3);
        
        const fork = Repository{
            .id = 0,
            .owner_id = owner_id,
            .lower_name = lower_name,
            .name = name,
            .description = description,
            .default_branch = default_branch,
            .is_private = is_private,
            .is_fork = true,
            .fork_id = source_id,
            .created_unix = 0,
            .updated_unix = 0,
        };
        
        return self.createRepository(allocator, fork);
    }
    
    return error.SourceNotFound;
}

// Branch methods
pub fn createBranch(self: *DataAccessObject, allocator: std.mem.Allocator, branch: Branch) !void {
    _ = allocator;
    _ = try self.pool.exec(
        \\INSERT INTO branch (repo_id, name, commit_id, is_protected)
        \\VALUES ($1, $2, $3, $4)
    , .{ branch.repo_id, branch.name, branch.commit_id, branch.is_protected });
}

pub fn getBranches(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64) ![]Branch {
    var result = try self.pool.query(
        \\SELECT id, repo_id, name, commit_id, is_protected
        \\FROM branch WHERE repo_id = $1 ORDER BY name
    , .{repo_id});
    defer result.deinit();
    
    var branches = std.ArrayList(Branch).init(allocator);
    errdefer {
        for (branches.items) |branch| {
            allocator.free(branch.name);
            if (branch.commit_id) |c| allocator.free(c);
        }
        branches.deinit();
    }
    
    while (try result.next()) |row| {
        const name = row.get([]const u8, 2);
        const commit_id = row.get(?[]const u8, 3);
        
        try branches.append(Branch{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, name),
            .commit_id = if (commit_id) |c| try allocator.dupe(u8, c) else null,
            .is_protected = row.get(bool, 4),
        });
    }
    
    return branches.toOwnedSlice();
}

pub fn getBranchByName(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64, name: []const u8) !?Branch {
    var maybe_row = try self.pool.row(
        \\SELECT id, repo_id, name, commit_id, is_protected
        \\FROM branch WHERE repo_id = $1 AND name = $2
    , .{ repo_id, name });
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const branch_name = row.get([]const u8, 2);
        const commit_id = row.get(?[]const u8, 3);
        
        return Branch{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, branch_name),
            .commit_id = if (commit_id) |c| try allocator.dupe(u8, c) else null,
            .is_protected = row.get(bool, 4),
        };
    }
    
    return null;
}

pub fn deleteBranch(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64, name: []const u8) !void {
    _ = allocator;
    _ = try self.pool.exec("DELETE FROM branch WHERE repo_id = $1 AND name = $2", .{ repo_id, name });
}

// Issue methods
pub fn createIssue(self: *DataAccessObject, allocator: std.mem.Allocator, issue: Issue) !i64 {
    _ = allocator;
    const unix_time = std.time.timestamp();
    
    // Get next issue index for this repo
    var row = try self.pool.row(
        \\SELECT COALESCE(MAX(index), 0) + 1 FROM issue WHERE repo_id = $1
    , .{issue.repo_id}) orelse return error.DatabaseError;
    defer row.deinit() catch {};
    const next_index = row.get(i64, 0);
    
    // Create the issue
    var created_row = try self.pool.row(
        \\INSERT INTO issue (repo_id, index, poster_id, title, content, 
        \\  is_closed, is_pull, assignee_id, created_unix)
        \\VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        \\RETURNING id
    , .{
        issue.repo_id, next_index, issue.poster_id, issue.title,
        issue.content, issue.is_closed, issue.is_pull, issue.assignee_id,
        unix_time,
    }) orelse return error.DatabaseError;
    defer created_row.deinit() catch {};
    
    return created_row.get(i64, 0);
}

pub fn getIssue(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64, index: i64) !?Issue {
    var maybe_row = try self.pool.row(
        \\SELECT id, repo_id, index, poster_id, title, content,
        \\  is_closed, is_pull, assignee_id, created_unix
        \\FROM issue WHERE repo_id = $1 AND index = $2
    , .{ repo_id, index });
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const title = row.get([]const u8, 4);
        const content = row.get(?[]const u8, 5);
        
        return Issue{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .index = row.get(i64, 2),
            .poster_id = row.get(i64, 3),
            .title = try allocator.dupe(u8, title),
            .content = if (content) |c| try allocator.dupe(u8, c) else null,
            .is_closed = row.get(bool, 6),
            .is_pull = row.get(bool, 7),
            .assignee_id = row.get(?i64, 8),
            .created_unix = row.get(i64, 9),
        };
    }
    
    return null;
}

pub const IssueFilters = struct {
    is_closed: ?bool = null,
    is_pull: ?bool = null,
    assignee_id: ?i64 = null,
};

pub fn listIssues(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64, filters: IssueFilters) ![]Issue {
    var query = std.ArrayList(u8).init(allocator);
    defer query.deinit();
    
    try query.appendSlice(
        \\SELECT id, repo_id, index, poster_id, title, content,
        \\  is_closed, is_pull, assignee_id, created_unix
        \\FROM issue WHERE repo_id = $1
    );
    
    if (filters.is_closed) |closed| {
        try query.writer().print(" AND is_closed = {}", .{closed});
    }
    if (filters.is_pull) |pull| {
        try query.writer().print(" AND is_pull = {}", .{pull});
    }
    if (filters.assignee_id) |assignee| {
        try query.writer().print(" AND assignee_id = {}", .{assignee});
    }
    
    try query.appendSlice(" ORDER BY index DESC");
    
    var result = try self.pool.query(query.items, .{repo_id});
    defer result.deinit();
    
    var issues = std.ArrayList(Issue).init(allocator);
    errdefer {
        for (issues.items) |issue| {
            allocator.free(issue.title);
            if (issue.content) |c| allocator.free(c);
        }
        issues.deinit();
    }
    
    while (try result.next()) |row| {
        const title = row.get([]const u8, 4);
        const content = row.get(?[]const u8, 5);
        
        try issues.append(Issue{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .index = row.get(i64, 2),
            .poster_id = row.get(i64, 3),
            .title = try allocator.dupe(u8, title),
            .content = if (content) |c| try allocator.dupe(u8, c) else null,
            .is_closed = row.get(bool, 6),
            .is_pull = row.get(bool, 7),
            .assignee_id = row.get(?i64, 8),
            .created_unix = row.get(i64, 9),
        });
    }
    
    return issues.toOwnedSlice();
}

pub const IssueUpdate = struct {
    title: ?[]const u8 = null,
    content: ?[]const u8 = null,
    is_closed: ?bool = null,
    assignee_id: ?i64 = null,
};

pub fn updateIssue(self: *DataAccessObject, allocator: std.mem.Allocator, issue_id: i64, updates: IssueUpdate) !void {
    _ = allocator;
    
    // Similar pattern to updateRepository
    if (updates.title != null and updates.content != null and updates.is_closed != null and updates.assignee_id != null) {
        _ = try self.pool.exec(
            \\UPDATE issue SET title = $1, content = $2, is_closed = $3, assignee_id = $4 WHERE id = $5
        , .{ updates.title, updates.content, updates.is_closed.?, updates.assignee_id, issue_id });
    } else if (updates.title != null) {
        _ = try self.pool.exec("UPDATE issue SET title = $1 WHERE id = $2", .{ updates.title, issue_id });
    } else if (updates.content != null) {
        _ = try self.pool.exec("UPDATE issue SET content = $1 WHERE id = $2", .{ updates.content, issue_id });
    } else if (updates.is_closed != null) {
        _ = try self.pool.exec("UPDATE issue SET is_closed = $1 WHERE id = $2", .{ updates.is_closed.?, issue_id });
    } else if (updates.assignee_id != null) {
        _ = try self.pool.exec("UPDATE issue SET assignee_id = $1 WHERE id = $2", .{ updates.assignee_id, issue_id });
    }
}

// Comment methods
pub fn createComment(self: *DataAccessObject, allocator: std.mem.Allocator, comment: Comment) !i64 {
    _ = allocator;
    const unix_time = std.time.timestamp();
    
    var row = try self.pool.row(
        \\INSERT INTO comment (poster_id, issue_id, review_id, content, commit_id, line, created_unix)
        \\VALUES ($1, $2, $3, $4, $5, $6, $7)
        \\RETURNING id
    , .{
        comment.poster_id, comment.issue_id, comment.review_id,
        comment.content, comment.commit_id, comment.line, unix_time,
    }) orelse return error.DatabaseError;
    defer row.deinit() catch {};
    
    return row.get(i64, 0);
}

pub fn getComments(self: *DataAccessObject, allocator: std.mem.Allocator, issue_id: i64) ![]Comment {
    var result = try self.pool.query(
        \\SELECT id, poster_id, issue_id, review_id, content, commit_id, line, created_unix
        \\FROM comment WHERE issue_id = $1 ORDER BY id
    , .{issue_id});
    defer result.deinit();
    
    var comments = std.ArrayList(Comment).init(allocator);
    errdefer {
        for (comments.items) |comment| {
            allocator.free(comment.content);
            if (comment.commit_id) |c| allocator.free(c);
        }
        comments.deinit();
    }
    
    while (try result.next()) |row| {
        const content = row.get([]const u8, 4);
        const commit_id = row.get(?[]const u8, 5);
        
        try comments.append(Comment{
            .id = row.get(i64, 0),
            .poster_id = row.get(i64, 1),
            .issue_id = row.get(i64, 2),
            .review_id = row.get(?i64, 3),
            .content = try allocator.dupe(u8, content),
            .commit_id = if (commit_id) |c| try allocator.dupe(u8, c) else null,
            .line = row.get(?i32, 6),
            .created_unix = row.get(i64, 7),
        });
    }
    
    return comments.toOwnedSlice();
}

// Label methods
pub fn createLabel(self: *DataAccessObject, allocator: std.mem.Allocator, label: Label) !i64 {
    _ = allocator;
    
    var row = try self.pool.row(
        \\INSERT INTO label (repo_id, name, color)
        \\VALUES ($1, $2, $3)
        \\RETURNING id
    , .{ label.repo_id, label.name, label.color }) orelse return error.DatabaseError;
    defer row.deinit() catch {};
    
    return row.get(i64, 0);
}

pub fn getLabels(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64) ![]Label {
    var result = try self.pool.query(
        \\SELECT id, repo_id, name, color
        \\FROM label WHERE repo_id = $1 ORDER BY name
    , .{repo_id});
    defer result.deinit();
    
    var labels = std.ArrayList(Label).init(allocator);
    errdefer {
        for (labels.items) |label| {
            allocator.free(label.name);
            allocator.free(label.color);
        }
        labels.deinit();
    }
    
    while (try result.next()) |row| {
        const name = row.get([]const u8, 2);
        const color = row.get([]const u8, 3);
        
        try labels.append(Label{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, name),
            .color = try allocator.dupe(u8, color),
        });
    }
    
    return labels.toOwnedSlice();
}

pub fn getLabelById(self: *DataAccessObject, allocator: std.mem.Allocator, id: i64) !?Label {
    var maybe_row = try self.pool.row(
        \\SELECT id, repo_id, name, color
        \\FROM label WHERE id = $1
    , .{id});
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const name = row.get([]const u8, 2);
        const color = row.get([]const u8, 3);
        
        return Label{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, name),
            .color = try allocator.dupe(u8, color),
        };
    }
    
    return null;
}

pub fn updateLabel(self: *DataAccessObject, allocator: std.mem.Allocator, id: i64, name: ?[]const u8, color: ?[]const u8) !void {
    _ = allocator;
    
    if (name != null and color != null) {
        _ = try self.pool.exec("UPDATE label SET name = $1, color = $2 WHERE id = $3", .{ name, color, id });
    } else if (name != null) {
        _ = try self.pool.exec("UPDATE label SET name = $1 WHERE id = $2", .{ name, id });
    } else if (color != null) {
        _ = try self.pool.exec("UPDATE label SET color = $1 WHERE id = $2", .{ color, id });
    }
}

pub fn deleteLabel(self: *DataAccessObject, allocator: std.mem.Allocator, id: i64) !void {
    _ = allocator;
    _ = try self.pool.exec("DELETE FROM label WHERE id = $1", .{id});
}

pub fn addLabelToIssue(self: *DataAccessObject, allocator: std.mem.Allocator, issue_id: i64, label_id: i64) !void {
    _ = allocator;
    _ = try self.pool.exec(
        \\INSERT INTO issue_label (issue_id, label_id)
        \\VALUES ($1, $2)
        \\ON CONFLICT (issue_id, label_id) DO NOTHING
    , .{ issue_id, label_id });
}

pub fn removeLabelFromIssue(self: *DataAccessObject, allocator: std.mem.Allocator, issue_id: i64, label_id: i64) !void {
    _ = allocator;
    _ = try self.pool.exec("DELETE FROM issue_label WHERE issue_id = $1 AND label_id = $2", .{ issue_id, label_id });
}

pub fn getIssueLabels(self: *DataAccessObject, allocator: std.mem.Allocator, issue_id: i64) ![]Label {
    var result = try self.pool.query(
        \\SELECT l.id, l.repo_id, l.name, l.color
        \\FROM label l
        \\JOIN issue_label il ON il.label_id = l.id
        \\WHERE il.issue_id = $1
        \\ORDER BY l.name
    , .{issue_id});
    defer result.deinit();
    
    var labels = std.ArrayList(Label).init(allocator);
    errdefer {
        for (labels.items) |label| {
            allocator.free(label.name);
            allocator.free(label.color);
        }
        labels.deinit();
    }
    
    while (try result.next()) |row| {
        const name = row.get([]const u8, 2);
        const color = row.get([]const u8, 3);
        
        try labels.append(Label{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, name),
            .color = try allocator.dupe(u8, color),
        });
    }
    
    return labels.toOwnedSlice();
}

// Review methods
pub fn createReview(self: *DataAccessObject, allocator: std.mem.Allocator, review: Review) !i64 {
    _ = allocator;
    
    var row = try self.pool.row(
        \\INSERT INTO review (type, reviewer_id, issue_id, commit_id)
        \\VALUES ($1, $2, $3, $4)
        \\RETURNING id
    , .{ @intFromEnum(review.type), review.reviewer_id, review.issue_id, review.commit_id }) orelse return error.DatabaseError;
    defer row.deinit() catch {};
    
    return row.get(i64, 0);
}

pub fn getReviews(self: *DataAccessObject, allocator: std.mem.Allocator, issue_id: i64) ![]Review {
    var result = try self.pool.query(
        \\SELECT id, type, reviewer_id, issue_id, commit_id
        \\FROM review WHERE issue_id = $1 ORDER BY id
    , .{issue_id});
    defer result.deinit();
    
    var reviews = std.ArrayList(Review).init(allocator);
    errdefer {
        for (reviews.items) |review| {
            if (review.commit_id) |c| allocator.free(c);
        }
        reviews.deinit();
    }
    
    while (try result.next()) |row| {
        const commit_id = row.get(?[]const u8, 4);
        
        try reviews.append(Review{
            .id = row.get(i64, 0),
            .type = @enumFromInt(row.get(i16, 1)),
            .reviewer_id = row.get(i64, 2),
            .issue_id = row.get(i64, 3),
            .commit_id = if (commit_id) |c| try allocator.dupe(u8, c) else null,
        });
    }
    
    return reviews.toOwnedSlice();
}

test "database CRUD operations" {
    const allocator = std.testing.allocator;
    
    // Use test database URL - will be provided via environment in Docker
    const test_db_url = std.posix.getenv("TEST_DATABASE_URL") orelse "postgresql://plue:plue_password@localhost:5432/plue";
    
    var dao = DataAccessObject.init(test_db_url) catch |err| switch (err) {
        error.ConnectionRefused => {
            std.log.warn("Database not available for testing, skipping", .{});
            return;
        },
        else => return err,
    };
    defer dao.deinit();
    
    // Clean up any existing test data
    dao.deleteUser(allocator, "test_alice") catch {};
    dao.deleteUser(allocator, "test_alice_updated") catch {};
    
    // Test create
    const test_user = User{
        .id = 0, // Will be assigned by database
        .name = "test_alice",
        .email = "alice@test.com",
        .passwd = "hashed_password",
        .type = .individual,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0, // Will be set by DAO
        .updated_unix = 0, // Will be set by DAO
    };
    try dao.createUser(allocator, test_user);
    
    // Test read
    const user = try dao.getUserByName(allocator, "test_alice");
    defer if (user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    try std.testing.expect(user != null);
    try std.testing.expectEqualStrings("test_alice", user.?.name);
    try std.testing.expectEqualStrings("alice@test.com", user.?.email.?);
    try std.testing.expectEqual(UserType.individual, user.?.type);
    
    // Test update
    try dao.updateUserName(allocator, "test_alice", "test_alice_updated");
    
    const updated_user = try dao.getUserByName(allocator, "test_alice_updated");
    defer if (updated_user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    try std.testing.expect(updated_user != null);
    try std.testing.expectEqualStrings("test_alice_updated", updated_user.?.name);
    
    // Test admin status update
    try std.testing.expectEqual(false, updated_user.?.is_admin);
    try dao.updateUserAdminStatus(allocator, updated_user.?.id, true);
    
    const admin_user = try dao.getUserByName(allocator, "test_alice_updated");
    defer if (admin_user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    try std.testing.expect(admin_user != null);
    try std.testing.expectEqual(true, admin_user.?.is_admin);
    
    // Test delete
    try dao.deleteUser(allocator, "test_alice_updated");
    
    const deleted_user = try dao.getUserByName(allocator, "test_alice_updated");
    try std.testing.expect(deleted_user == null);
    
    // Test list
    const user1 = User{
        .id = 0,
        .name = "test_user1",
        .email = null,
        .passwd = null,
        .type = .individual,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    const user2 = User{
        .id = 0,
        .name = "test_user2",
        .email = null,
        .passwd = null,
        .type = .organization,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, user1);
    try dao.createUser(allocator, user2);
    
    const users = try dao.listUsers(allocator);
    defer {
        for (users) |list_user| {
            allocator.free(list_user.name);
            if (list_user.email) |e| allocator.free(e);
            if (list_user.passwd) |p| allocator.free(p);
            if (list_user.avatar) |a| allocator.free(a);
        }
        allocator.free(users);
    }
    
    try std.testing.expect(users.len >= 2);
    
    // Clean up
    dao.deleteUser(allocator, "test_user1") catch {};
    dao.deleteUser(allocator, "test_user2") catch {};
}

// Milestone methods
pub fn createMilestone(self: *DataAccessObject, allocator: std.mem.Allocator, milestone: Milestone) !i64 {
    _ = allocator;
    const unix_time = std.time.timestamp();
    
    var row = try self.pool.row(
        \\INSERT INTO milestone (repo_id, name, description, state, due_date, created_unix, updated_unix, closed_unix, open_issues, closed_issues)
        \\VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        \\RETURNING id
    , .{
        milestone.repo_id,
        milestone.name,
        milestone.description,
        @intFromEnum(milestone.state),
        milestone.due_date,
        unix_time,
        unix_time,
        milestone.closed_unix,
        milestone.open_issues,
        milestone.closed_issues,
    }) orelse return error.DatabaseError;
    defer row.deinit() catch {};
    
    return row.get(i64, 0);
}

pub fn getMilestone(self: *DataAccessObject, allocator: std.mem.Allocator, milestone_id: i64) !?Milestone {
    var maybe_row = try self.pool.row(
        \\SELECT id, repo_id, name, description, state, due_date, created_unix, updated_unix, closed_unix, open_issues, closed_issues
        \\FROM milestone WHERE id = $1
    , .{milestone_id});
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const name = row.get([]const u8, 2);
        const description = row.get(?[]const u8, 3);
        
        return Milestone{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, name),
            .description = if (description) |d| try allocator.dupe(u8, d) else null,
            .state = @enumFromInt(row.get(i16, 4)),
            .due_date = row.get(?i64, 5),
            .created_unix = row.get(i64, 6),
            .updated_unix = row.get(i64, 7),
            .closed_unix = row.get(?i64, 8),
            .open_issues = row.get(i32, 9),
            .closed_issues = row.get(i32, 10),
        };
    }
    return null;
}

pub fn updateMilestone(self: *DataAccessObject, allocator: std.mem.Allocator, milestone: Milestone) !void {
    _ = allocator;
    const unix_time = std.time.timestamp();
    
    const affected = try self.pool.exec(
        \\UPDATE milestone SET 
        \\  name = $2, description = $3, state = $4, due_date = $5, 
        \\  updated_unix = $6, closed_unix = $7, open_issues = $8, closed_issues = $9
        \\WHERE id = $1
    , .{
        milestone.id,
        milestone.name,
        milestone.description,
        @intFromEnum(milestone.state),
        milestone.due_date,
        unix_time,
        milestone.closed_unix,
        milestone.open_issues,
        milestone.closed_issues,
    });
    
    if (affected == 0) {
        return error.MilestoneNotFound;
    }
}

pub fn deleteMilestone(self: *DataAccessObject, allocator: std.mem.Allocator, milestone_id: i64) !void {
    _ = allocator;
    
    const affected = try self.pool.exec(
        \\DELETE FROM milestone WHERE id = $1
    , .{milestone_id});
    
    if (affected == 0) {
        return error.MilestoneNotFound;
    }
}

pub fn getMilestones(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64) ![]Milestone {
    var result = try self.pool.query(
        \\SELECT id, repo_id, name, description, state, due_date, created_unix, updated_unix, closed_unix, open_issues, closed_issues
        \\FROM milestone WHERE repo_id = $1 ORDER BY created_unix ASC
    , .{repo_id});
    defer result.deinit();
    
    var milestones = std.ArrayList(Milestone).init(allocator);
    defer milestones.deinit();
    
    while (try result.next()) |row| {
        const name = row.get([]const u8, 2);
        const description = row.get(?[]const u8, 3);
        
        try milestones.append(Milestone{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, name),
            .description = if (description) |d| try allocator.dupe(u8, d) else null,
            .state = @enumFromInt(row.get(i16, 4)),
            .due_date = row.get(?i64, 5),
            .created_unix = row.get(i64, 6),
            .updated_unix = row.get(i64, 7),
            .closed_unix = row.get(?i64, 8),
            .open_issues = row.get(i32, 9),
            .closed_issues = row.get(i32, 10),
        });
    }
    
    return try milestones.toOwnedSlice();
}

pub fn getMilestonesByState(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64, state: MilestoneState) ![]Milestone {
    var result = try self.pool.query(
        \\SELECT id, repo_id, name, description, state, due_date, created_unix, updated_unix, closed_unix, open_issues, closed_issues
        \\FROM milestone WHERE repo_id = $1 AND state = $2 ORDER BY created_unix ASC
    , .{ repo_id, @intFromEnum(state) });
    defer result.deinit();
    
    var milestones = std.ArrayList(Milestone).init(allocator);
    defer milestones.deinit();
    
    while (try result.next()) |row| {
        const name = row.get([]const u8, 2);
        const description = row.get(?[]const u8, 3);
        
        try milestones.append(Milestone{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, name),
            .description = if (description) |d| try allocator.dupe(u8, d) else null,
            .state = @enumFromInt(row.get(i16, 4)),
            .due_date = row.get(?i64, 5),
            .created_unix = row.get(i64, 6),
            .updated_unix = row.get(i64, 7),
            .closed_unix = row.get(?i64, 8),
            .open_issues = row.get(i32, 9),
            .closed_issues = row.get(i32, 10),
        });
    }
    
    return try milestones.toOwnedSlice();
}

pub fn assignIssueToMilestone(self: *DataAccessObject, allocator: std.mem.Allocator, issue_id: i64, milestone_id: i64) !void {
    // First, update the issue to reference the milestone
    const affected = try self.pool.exec(
        \\UPDATE issue SET milestone_id = $1 WHERE id = $2
    , .{ milestone_id, issue_id });
    
    if (affected == 0) {
        return error.IssueNotFound;
    }
    
    // Update milestone issue counts
    try self.updateMilestoneIssueCounts(allocator, milestone_id);
}

pub fn removeIssueFromMilestone(self: *DataAccessObject, allocator: std.mem.Allocator, issue_id: i64) !void {
    // Get the current milestone_id before removing
    var maybe_row = try self.pool.row(
        \\SELECT milestone_id FROM issue WHERE id = $1 AND milestone_id IS NOT NULL
    , .{issue_id});
    
    const milestone_id = if (maybe_row) |*row| blk: {
        defer row.deinit() catch {};
        break :blk row.get(i64, 0);
    } else return error.IssueNotFound;
    
    // Remove milestone assignment
    const affected = try self.pool.exec(
        \\UPDATE issue SET milestone_id = NULL WHERE id = $1
    , .{issue_id});
    
    if (affected == 0) {
        return error.IssueNotFound;
    }
    
    // Update milestone issue counts
    try self.updateMilestoneIssueCounts(allocator, milestone_id);
}

fn updateMilestoneIssueCounts(self: *DataAccessObject, allocator: std.mem.Allocator, milestone_id: i64) !void {
    _ = allocator;
    
    // Count open and closed issues for this milestone
    var maybe_row = try self.pool.row(
        \\SELECT 
        \\  COUNT(CASE WHEN is_closed = false THEN 1 END) as open_count,
        \\  COUNT(CASE WHEN is_closed = true THEN 1 END) as closed_count
        \\FROM issue WHERE milestone_id = $1
    , .{milestone_id});
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const open_count = @as(i32, @intCast(row.get(i64, 0)));
        const closed_count = @as(i32, @intCast(row.get(i64, 1)));
        
        // Update milestone counts
        _ = try self.pool.exec(
            \\UPDATE milestone SET open_issues = $1, closed_issues = $2, updated_unix = $3 WHERE id = $4
        , .{ open_count, closed_count, std.time.timestamp(), milestone_id });
    }
}

// Actions/CI operations
pub fn createActionRun(self: *DataAccessObject, _: std.mem.Allocator, run: ActionRun) !i64 {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "INSERT INTO action_run (repo_id, workflow_id, commit_sha, trigger_event, status, created_unix) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id";
    const result = try client.query(
        query,
        .{
            run.repo_id,
            run.workflow_id,
            run.commit_sha,
            run.trigger_event,
            @intFromEnum(run.status),
            std.time.timestamp(),
        },
    );
    
    if (try result.next()) |row| {
        return row.get(i64, 0);
    }
    
    return error.DatabaseError;
}

pub fn getActionRuns(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64) ![]ActionRun {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "SELECT id, repo_id, workflow_id, commit_sha, trigger_event, status, created_unix FROM action_run WHERE repo_id = $1 ORDER BY created_unix DESC";
    const result = try client.query(query, .{repo_id});
    
    var runs = std.ArrayList(ActionRun).init(allocator);
    defer runs.deinit();
    
    while (try result.next()) |row| {
        const run = ActionRun{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .workflow_id = try allocator.dupe(u8, row.get([]const u8, 2)),
            .commit_sha = try allocator.dupe(u8, row.get([]const u8, 3)),
            .trigger_event = try allocator.dupe(u8, row.get([]const u8, 4)),
            .status = @enumFromInt(row.get(i16, 5)),
            .created_unix = row.get(i64, 6),
        };
        try runs.append(run);
    }
    
    return runs.toOwnedSlice();
}

pub fn getActionRunById(self: *DataAccessObject, allocator: std.mem.Allocator, run_id: i64) !?ActionRun {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "SELECT id, repo_id, workflow_id, commit_sha, trigger_event, status, created_unix FROM action_run WHERE id = $1";
    const result = try client.query(query, .{run_id});
    
    if (try result.next()) |row| {
        return ActionRun{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .workflow_id = try allocator.dupe(u8, row.get([]const u8, 2)),
            .commit_sha = try allocator.dupe(u8, row.get([]const u8, 3)),
            .trigger_event = try allocator.dupe(u8, row.get([]const u8, 4)),
            .status = @enumFromInt(row.get(i16, 5)),
            .created_unix = row.get(i64, 6),
        };
    }
    
    return null;
}

pub fn createActionJob(self: *DataAccessObject, _: std.mem.Allocator, job: ActionJob) !i64 {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "INSERT INTO action_job (run_id, name, runs_on, status, log, started, stopped) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id";
    const result = try client.query(
        query,
        .{
            job.run_id,
            job.name,
            job.runs_on,
            @intFromEnum(job.status),
            job.log,
            job.started,
            job.stopped,
        },
    );
    
    if (try result.next()) |row| {
        return row.get(i64, 0);
    }
    
    return error.DatabaseError;
}

pub fn getActionJobs(self: *DataAccessObject, allocator: std.mem.Allocator, run_id: i64) ![]ActionJob {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "SELECT id, run_id, name, runs_on, status, log, started, stopped FROM action_job WHERE run_id = $1 ORDER BY id";
    const result = try client.query(query, .{run_id});
    
    var jobs = std.ArrayList(ActionJob).init(allocator);
    defer jobs.deinit();
    
    while (try result.next()) |row| {
        const job = ActionJob{
            .id = row.get(i64, 0),
            .run_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, row.get([]const u8, 2)),
            .runs_on = try allocator.dupe(u8, row.get([]const u8, 3)),
            .status = @enumFromInt(row.get(i16, 4)),
            .log = if (row.get(?[]const u8, 5)) |log| try allocator.dupe(u8, log) else null,
            .started = row.get(?i64, 6),
            .stopped = row.get(?i64, 7),
        };
        try jobs.append(job);
    }
    
    return jobs.toOwnedSlice();
}

pub fn createActionArtifact(self: *DataAccessObject, _: std.mem.Allocator, artifact: ActionArtifact) !i64 {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "INSERT INTO action_artifact (job_id, name, path, file_size) VALUES ($1, $2, $3, $4) RETURNING id";
    const result = try client.query(
        query,
        .{
            artifact.job_id,
            artifact.name,
            artifact.path,
            artifact.file_size,
        },
    );
    
    if (try result.next()) |row| {
        return row.get(i64, 0);
    }
    
    return error.DatabaseError;
}

pub fn getActionArtifacts(self: *DataAccessObject, allocator: std.mem.Allocator, job_id: i64) ![]ActionArtifact {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "SELECT id, job_id, name, path, file_size FROM action_artifact WHERE job_id = $1";
    const result = try client.query(query, .{job_id});
    
    var artifacts = std.ArrayList(ActionArtifact).init(allocator);
    defer artifacts.deinit();
    
    while (try result.next()) |row| {
        const artifact = ActionArtifact{
            .id = row.get(i64, 0),
            .job_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, row.get([]const u8, 2)),
            .path = try allocator.dupe(u8, row.get([]const u8, 3)),
            .file_size = row.get(i64, 4),
        };
        try artifacts.append(artifact);
    }
    
    return artifacts.toOwnedSlice();
}

pub fn getActionArtifactById(self: *DataAccessObject, allocator: std.mem.Allocator, artifact_id: i64) !?ActionArtifact {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "SELECT id, job_id, name, path, file_size FROM action_artifact WHERE id = $1";
    const result = try client.query(query, .{artifact_id});
    
    if (try result.next()) |row| {
        return ActionArtifact{
            .id = row.get(i64, 0),
            .job_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, row.get([]const u8, 2)),
            .path = try allocator.dupe(u8, row.get([]const u8, 3)),
            .file_size = row.get(i64, 4),
        };
    }
    
    return null;
}

pub fn createActionSecret(self: *DataAccessObject, _: std.mem.Allocator, secret: ActionSecret) !void {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "INSERT INTO action_secret (owner_id, repo_id, name, data) VALUES ($1, $2, $3, $4) ON CONFLICT (owner_id, repo_id, name) DO UPDATE SET data = $4";
    _ = try client.query(
        query,
        .{
            secret.owner_id,
            secret.repo_id,
            secret.name,
            secret.data,
        },
    );
}

pub fn getActionSecrets(self: *DataAccessObject, allocator: std.mem.Allocator, owner_id: i64, repo_id: i64) ![]ActionSecret {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "SELECT id, owner_id, repo_id, name, data FROM action_secret WHERE (owner_id = $1 AND repo_id = 0) OR (owner_id = 0 AND repo_id = $2) ORDER BY name";
    const result = try client.query(query, .{ owner_id, repo_id });
    
    var secrets = std.ArrayList(ActionSecret).init(allocator);
    defer secrets.deinit();
    
    while (try result.next()) |row| {
        const secret = ActionSecret{
            .id = row.get(i64, 0),
            .owner_id = row.get(i64, 1),
            .repo_id = row.get(i64, 2),
            .name = try allocator.dupe(u8, row.get([]const u8, 3)),
            .data = try allocator.dupe(u8, row.get([]const u8, 4)),
        };
        try secrets.append(secret);
    }
    
    return secrets.toOwnedSlice();
}

pub fn deleteActionSecret(self: *DataAccessObject, _: std.mem.Allocator, owner_id: i64, repo_id: i64, name: []const u8) !void {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "DELETE FROM action_secret WHERE owner_id = $1 AND repo_id = $2 AND name = $3";
    _ = try client.query(query, .{ owner_id, repo_id, name });
}

pub fn createRunnerToken(self: *DataAccessObject, _: std.mem.Allocator, token_hash: []const u8, owner_id: i64, repo_id: i64) !void {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "INSERT INTO action_runner_token (token_hash, owner_id, repo_id) VALUES ($1, $2, $3)";
    _ = try client.query(query, .{ token_hash, owner_id, repo_id });
}

pub fn createRunner(self: *DataAccessObject, _: std.mem.Allocator, runner: ActionRunner) !i64 {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "INSERT INTO action_runner (uuid, name, owner_id, repo_id, token_hash, labels, status, last_online) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id";
    const result = try client.query(
        query,
        .{
            runner.uuid,
            runner.name,
            runner.owner_id,
            runner.repo_id,
            runner.token_hash,
            runner.labels,
            runner.status,
            runner.last_online,
        },
    );
    
    if (try result.next()) |row| {
        return row.get(i64, 0);
    }
    
    return error.DatabaseError;
}

pub fn getRunners(self: *DataAccessObject, allocator: std.mem.Allocator, owner_id: i64, repo_id: i64) ![]ActionRunner {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "SELECT id, uuid, name, owner_id, repo_id, token_hash, labels, status, last_online FROM action_runner WHERE (owner_id = $1 AND repo_id = 0) OR (owner_id = 0 AND repo_id = $2) ORDER BY name";
    const result = try client.query(query, .{ owner_id, repo_id });
    
    var runners = std.ArrayList(ActionRunner).init(allocator);
    defer runners.deinit();
    
    while (try result.next()) |row| {
        const runner = ActionRunner{
            .id = row.get(i64, 0),
            .uuid = try allocator.dupe(u8, row.get([]const u8, 1)),
            .name = try allocator.dupe(u8, row.get([]const u8, 2)),
            .owner_id = row.get(i64, 3),
            .repo_id = row.get(i64, 4),
            .token_hash = try allocator.dupe(u8, row.get([]const u8, 5)),
            .labels = if (row.get(?[]const u8, 6)) |labels| try allocator.dupe(u8, labels) else null,
            .status = try allocator.dupe(u8, row.get([]const u8, 7)),
            .last_online = row.get(?i64, 8),
        };
        try runners.append(runner);
    }
    
    return runners.toOwnedSlice();
}

pub fn deleteRunner(self: *DataAccessObject, _: std.mem.Allocator, runner_id: i64) !void {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "DELETE FROM action_runner WHERE id = $1";
    _ = try client.query(query, .{runner_id});
}

// Permission-related methods

// Get extended user with permission fields
pub fn getUserExt(self: *DataAccessObject, allocator: std.mem.Allocator, user_id: i64) !UserExt {
    var maybe_row = try self.pool.row(
        \\SELECT id, name, is_admin, is_restricted, is_deleted, is_active, prohibit_login, visibility
        \\FROM users WHERE id = $1
    , .{user_id});
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const name = row.get([]const u8, 1);
        const visibility = row.get([]const u8, 7);
        
        return UserExt{
            .id = row.get(i64, 0),
            .name = try allocator.dupe(u8, name),
            .is_admin = row.get(bool, 2),
            .is_restricted = row.get(bool, 3),
            .is_deleted = row.get(bool, 4),
            .is_active = row.get(bool, 5),
            .prohibit_login = row.get(bool, 6),
            .visibility = try allocator.dupe(u8, visibility),
        };
    }
    
    return error.NotFound;
}

// Get extended repository with permission fields
pub fn getRepositoryExt(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64) !RepositoryExt {
    var maybe_row = try self.pool.row(
        \\SELECT id, owner_id, owner_type, name, is_private, is_mirror, is_archived, is_deleted, visibility
        \\FROM repository WHERE id = $1
    , .{repo_id});
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const owner_type_str = row.get([]const u8, 2);
        const owner_type = std.meta.stringToEnum(OwnerType, owner_type_str) orelse .user;
        const name = row.get([]const u8, 3);
        const visibility = row.get([]const u8, 8);
        
        return RepositoryExt{
            .id = row.get(i64, 0),
            .owner_id = row.get(i64, 1),
            .owner_type = owner_type,
            .name = try allocator.dupe(u8, name),
            .is_private = row.get(bool, 4),
            .is_mirror = row.get(bool, 5),
            .is_archived = row.get(bool, 6),
            .is_deleted = row.get(bool, 7),
            .visibility = try allocator.dupe(u8, visibility),
        };
    }
    
    return error.NotFound;
}

// Get organization
pub fn getOrganization(self: *DataAccessObject, allocator: std.mem.Allocator, org_id: i64) !Organization {
    var maybe_row = try self.pool.row(
        \\SELECT id, name, visibility, max_repo_creation, 
        \\       EXTRACT(EPOCH FROM created_at)::BIGINT
        \\FROM organizations WHERE id = $1
    , .{org_id});
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const name = row.get([]const u8, 1);
        const visibility = row.get([]const u8, 2);
        
        return Organization{
            .id = row.get(i64, 0),
            .name = try allocator.dupe(u8, name),
            .visibility = try allocator.dupe(u8, visibility),
            .max_repo_creation = row.get(i32, 3),
            .created_at = row.get(i64, 4),
        };
    }
    
    return error.NotFound;
}

// Check if user is organization member
pub fn isOrganizationMember(self: *DataAccessObject, org_id: i64, user_id: i64) !bool {
    var maybe_row = try self.pool.row(
        \\SELECT 1 FROM org_users WHERE org_id = $1 AND user_id = $2
    , .{ org_id, user_id });
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        return true;
    }
    
    return false;
}

// Check if user is a collaborator
pub fn isCollaborator(self: *DataAccessObject, user_id: i64, repo_id: i64) !bool {
    var maybe_row = try self.pool.row(
        \\SELECT 1 FROM collaborations WHERE user_id = $1 AND repo_id = $2
    , .{ user_id, repo_id });
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        return true;
    }
    
    return false;
}

// Get access level from pre-computed cache
pub fn getAccessLevel(self: *DataAccessObject, user_id: i64, repo_id: i64) !?Access {
    var maybe_row = try self.pool.row(
        \\SELECT user_id, repo_id, mode, EXTRACT(EPOCH FROM updated_at)::BIGINT
        \\FROM access WHERE user_id = $1 AND repo_id = $2
    , .{ user_id, repo_id });
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const mode = row.get([]const u8, 2);
        
        return Access{
            .user_id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .mode = mode, // Caller is responsible for duping if needed
            .updated_at = row.get(i64, 3),
        };
    }
    
    return null;
}

// Get collaboration details
pub fn getCollaboration(self: *DataAccessObject, allocator: std.mem.Allocator, user_id: i64, repo_id: i64) !?Collaboration {
    var maybe_row = try self.pool.row(
        \\SELECT id, repo_id, user_id, mode, units, EXTRACT(EPOCH FROM created_at)::BIGINT
        \\FROM collaborations WHERE user_id = $1 AND repo_id = $2
    , .{ user_id, repo_id });
    
    if (maybe_row) |*row| {
        defer row.deinit() catch {};
        
        const mode = row.get([]const u8, 3);
        const units = row.get(?[]const u8, 4);
        
        return Collaboration{
            .id = row.get(i64, 0),
            .repo_id = row.get(i64, 1),
            .user_id = row.get(i64, 2),
            .mode = try allocator.dupe(u8, mode),
            .units = if (units) |u| try allocator.dupe(u8, u) else null,
            .created_at = row.get(i64, 5),
        };
    }
    
    return null;
}

// Get user's teams in an organization that have access to a repository
pub fn getUserRepoTeams(self: *DataAccessObject, allocator: std.mem.Allocator, org_id: i64, user_id: i64, repo_id: i64) !std.ArrayList(Team) {
    var result = try self.pool.query(
        \\SELECT t.id, t.org_id, t.name, t.access_mode, t.can_create_org_repo, 
        \\       t.is_owner_team, t.units, EXTRACT(EPOCH FROM t.created_at)::BIGINT
        \\FROM teams t
        \\INNER JOIN team_users tu ON t.id = tu.team_id
        \\INNER JOIN team_repos tr ON t.id = tr.team_id
        \\WHERE t.org_id = $1 AND tu.user_id = $2 AND tr.repo_id = $3
    , .{ org_id, user_id, repo_id });
    defer result.deinit();
    
    var teams = std.ArrayList(Team).init(allocator);
    errdefer {
        for (teams.items) |team| {
            allocator.free(team.name);
            allocator.free(team.access_mode);
            if (team.units) |u| allocator.free(u);
        }
        teams.deinit();
    }
    
    while (try result.next()) |row| {
        const name = row.get([]const u8, 2);
        const access_mode = row.get([]const u8, 3);
        const units = row.get(?[]const u8, 6);
        
        const team = Team{
            .id = row.get(i64, 0),
            .org_id = row.get(i64, 1),
            .name = try allocator.dupe(u8, name),
            .access_mode = try allocator.dupe(u8, access_mode),
            .can_create_org_repo = row.get(bool, 4),
            .is_owner_team = row.get(bool, 5),
            .units = if (units) |u| try allocator.dupe(u8, u) else null,
            .created_at = row.get(i64, 7),
        };
        try teams.append(team);
    }
    
    return teams;
}