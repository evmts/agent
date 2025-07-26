const std = @import("std");
const pg = @import("pg");
const user_models = @import("models/user.zig");
const repo_models = @import("models/repository.zig");
const issue_models = @import("models/issue.zig");
const action_models = @import("models/action.zig");

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
pub const ActionRun = action_models.ActionRun;
pub const ActionJob = action_models.ActionJob;
pub const ActionRunner = action_models.ActionRunner;
pub const ActionRunnerToken = action_models.ActionRunnerToken;
pub const ActionArtifact = action_models.ActionArtifact;
pub const ActionSecret = action_models.ActionSecret;
pub const ActionStatus = action_models.ActionStatus;

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