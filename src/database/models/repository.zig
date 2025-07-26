const std = @import("std");

pub const Repository = struct {
    id: i64,
    owner_id: i64,
    lower_name: []const u8,
    name: []const u8,
    description: ?[]const u8,
    default_branch: []const u8,
    is_private: bool,
    is_fork: bool,
    fork_id: ?i64,
    created_unix: i64,
    updated_unix: i64,
};

pub const Branch = struct {
    id: i64,
    repo_id: i64,
    name: []const u8,
    commit_id: ?[]const u8,
    is_protected: bool,
};

pub const LFSMetaObject = struct {
    oid: []const u8,
    size: i64,
    repository_id: i64,
};

pub const LFSLock = struct {
    id: i64,
    repo_id: i64,
    path: []const u8,
    owner_id: i64,
    created_unix: i64,
};

test "Repository model" {
    const repo = Repository{
        .id = 1,
        .owner_id = 123,
        .lower_name = "my-project",
        .name = "My-Project",
        .description = "A test project",
        .default_branch = "main",
        .is_private = false,
        .is_fork = false,
        .fork_id = null,
        .created_unix = 1234567890,
        .updated_unix = 1234567890,
    };
    
    try std.testing.expectEqual(@as(i64, 1), repo.id);
    try std.testing.expectEqualStrings("my-project", repo.lower_name);
    try std.testing.expectEqualStrings("My-Project", repo.name);
    try std.testing.expectEqual(false, repo.is_private);
}

test "Branch model" {
    const branch = Branch{
        .id = 1,
        .repo_id = 123,
        .name = "main",
        .commit_id = "abc123def456",
        .is_protected = true,
    };
    
    try std.testing.expectEqual(@as(i64, 123), branch.repo_id);
    try std.testing.expectEqualStrings("main", branch.name);
    try std.testing.expectEqual(true, branch.is_protected);
}

test "LFS models" {
    const lfs_obj = LFSMetaObject{
        .oid = "1234567890abcdef",
        .size = 1024 * 1024,
        .repository_id = 123,
    };
    
    const lfs_lock = LFSLock{
        .id = 1,
        .repo_id = 123,
        .path = "large-file.bin",
        .owner_id = 456,
        .created_unix = 1234567890,
    };
    
    try std.testing.expectEqualStrings("1234567890abcdef", lfs_obj.oid);
    try std.testing.expectEqual(@as(i64, 1024 * 1024), lfs_obj.size);
    try std.testing.expectEqualStrings("large-file.bin", lfs_lock.path);
}

test "Repository database operations" {
    const allocator = std.testing.allocator;
    const DataAccessObject = @import("../dao.zig");
    
    const test_db_url = std.posix.getenv("TEST_DATABASE_URL") orelse "postgresql://plue:plue_password@localhost:5432/plue";
    
    var dao = DataAccessObject.init(test_db_url) catch |err| switch (err) {
        error.ConnectionRefused => {
            std.log.warn("Database not available for testing, skipping", .{});
            return;
        },
        else => return err,
    };
    defer dao.deinit();
    
    // Clean up test data
    dao.deleteUser(allocator, "test_repo_owner") catch {};
    
    // Create user to own repository
    const owner = DataAccessObject.User{
        .id = 0,
        .name = "test_repo_owner",
        .email = "owner@test.com",
        .passwd = null,
        .type = .individual,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, owner);
    
    const owner_user = try dao.getUserByName(allocator, "test_repo_owner");
    defer if (owner_user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    try std.testing.expect(owner_user != null);
    
    // Create repository
    const repo = Repository{
        .id = 0,
        .owner_id = owner_user.?.id,
        .lower_name = "test-repo",
        .name = "Test-Repo",
        .description = "A test repository",
        .default_branch = "main",
        .is_private = true,
        .is_fork = false,
        .fork_id = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    
    const repo_id = try dao.createRepository(allocator, repo);
    try std.testing.expect(repo_id > 0);
    
    // Get repository
    const retrieved_repo = try dao.getRepositoryByName(allocator, owner_user.?.id, "Test-Repo");
    defer if (retrieved_repo) |r| {
        allocator.free(r.lower_name);
        allocator.free(r.name);
        if (r.description) |d| allocator.free(d);
        allocator.free(r.default_branch);
    };
    
    try std.testing.expect(retrieved_repo != null);
    try std.testing.expectEqualStrings("test-repo", retrieved_repo.?.lower_name);
    try std.testing.expectEqualStrings("Test-Repo", retrieved_repo.?.name);
    try std.testing.expectEqual(true, retrieved_repo.?.is_private);
    
    // Clean up
    dao.deleteUser(allocator, "test_repo_owner") catch {};
}