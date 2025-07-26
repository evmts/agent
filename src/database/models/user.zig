const std = @import("std");

pub const UserType = enum(i16) {
    individual = 0,
    organization = 1,
};

pub const User = struct {
    id: i64,
    name: []const u8,
    email: ?[]const u8,
    passwd: ?[]const u8,
    type: UserType,
    is_admin: bool,
    avatar: ?[]const u8,
    created_unix: i64,
    updated_unix: i64,
};

pub const OrgUser = struct {
    id: i64,
    uid: i64,
    org_id: i64,
    is_owner: bool,
};

pub const PublicKey = struct {
    id: i64,
    owner_id: i64,
    name: []const u8,
    content: []const u8,
    fingerprint: []const u8,
    created_unix: i64,
    updated_unix: i64,
};

pub const AuthToken = struct {
    id: i64,
    user_id: i64,
    token: []const u8,
    created_unix: i64,
    expires_unix: i64,
};

test "User model" {
    const user = User{
        .id = 1,
        .name = "testuser",
        .email = "test@example.com",
        .passwd = "hashed_password",
        .type = .individual,
        .is_admin = false,
        .avatar = null,
        .created_unix = 1234567890,
        .updated_unix = 1234567890,
    };
    
    try std.testing.expectEqual(@as(i64, 1), user.id);
    try std.testing.expectEqualStrings("testuser", user.name);
    try std.testing.expectEqual(UserType.individual, user.type);
}

test "OrgUser model" {
    const org_user = OrgUser{
        .id = 1,
        .uid = 123,
        .org_id = 456,
        .is_owner = true,
    };
    
    try std.testing.expectEqual(@as(i64, 123), org_user.uid);
    try std.testing.expectEqual(@as(i64, 456), org_user.org_id);
    try std.testing.expectEqual(true, org_user.is_owner);
}

test "PublicKey model" {
    const key = PublicKey{
        .id = 1,
        .owner_id = 123,
        .name = "My Laptop",
        .content = "ssh-rsa AAAAB3NzaC1yc2EA...",
        .fingerprint = "SHA256:abcd1234...",
        .created_unix = 1234567890,
        .updated_unix = 1234567890,
    };
    
    try std.testing.expectEqual(@as(i64, 123), key.owner_id);
    try std.testing.expectEqualStrings("My Laptop", key.name);
}

test "User database operations" {
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
    dao.deleteUser(allocator, "test_org") catch {};
    dao.deleteUser(allocator, "test_member") catch {};
    
    // Create organization user
    const org = User{
        .id = 0,
        .name = "test_org",
        .email = "org@test.com",
        .passwd = null,
        .type = .organization,
        .is_admin = false,
        .avatar = "https://example.com/avatar.png",
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, org);
    
    // Create individual user
    const member = User{
        .id = 0,
        .name = "test_member",
        .email = "member@test.com",
        .passwd = "hashed",
        .type = .individual,
        .is_admin = true,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, member);
    
    // Get created users
    const org_user = try dao.getUserByName(allocator, "test_org");
    defer if (org_user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    const member_user = try dao.getUserByName(allocator, "test_member");
    defer if (member_user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    try std.testing.expect(org_user != null);
    try std.testing.expect(member_user != null);
    
    // Test organization membership
    try dao.addUserToOrg(allocator, member_user.?.id, org_user.?.id, false);
    
    const org_users = try dao.getOrgUsers(allocator, org_user.?.id);
    defer allocator.free(org_users);
    
    try std.testing.expectEqual(@as(usize, 1), org_users.len);
    try std.testing.expectEqual(member_user.?.id, org_users[0].uid);
    try std.testing.expectEqual(false, org_users[0].is_owner);
    
    // Test SSH keys
    const ssh_key = PublicKey{
        .id = 0,
        .owner_id = member_user.?.id,
        .name = "Test Key",
        .content = "ssh-rsa AAAAB3NzaC1yc2EA... test@example.com",
        .fingerprint = "SHA256:test_fingerprint",
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.addPublicKey(allocator, ssh_key);
    
    const keys = try dao.getUserPublicKeys(allocator, member_user.?.id);
    defer {
        for (keys) |key| {
            allocator.free(key.name);
            allocator.free(key.content);
            allocator.free(key.fingerprint);
        }
        allocator.free(keys);
    }
    
    try std.testing.expectEqual(@as(usize, 1), keys.len);
    try std.testing.expectEqualStrings("Test Key", keys[0].name);
    
    // Cleanup
    dao.deleteUser(allocator, "test_org") catch {};
    dao.deleteUser(allocator, "test_member") catch {};
}