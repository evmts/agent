const std = @import("std");
const pg = @import("pg");

const DataAccessObject = @This();

pool: *pg.Pool,

const User = struct {
    id: i32,
    name: []const u8,
};

pub fn init(connection_url: []const u8) !DataAccessObject {
    const uri = try std.Uri.parse(connection_url);
    const pool = try pg.Pool.initUri(std.heap.page_allocator, uri, 5, 10_000);
    
    return DataAccessObject{
        .pool = pool,
    };
}

pub fn deinit(self: *DataAccessObject) void {
    self.pool.deinit();
}

pub fn createUser(self: *DataAccessObject, allocator: std.mem.Allocator, name: []const u8) !void {
    _ = allocator;
    _ = try self.pool.exec("INSERT INTO users (name) VALUES ($1)", .{name});
}

pub fn getUserByName(self: *DataAccessObject, allocator: std.mem.Allocator, name: []const u8) !?User {
    const row = self.pool.row("SELECT id, name FROM users WHERE name = $1", .{name}) catch |err| switch (err) {
        error.NoRows => return null,
        else => return err,
    };
    defer row.deinit();
    
    const id = row.get(i32, 0);
    const username = row.get([]const u8, 1);
    
    // Allocate memory for the name since row data is temporary
    const owned_name = try allocator.dupe(u8, username);
    
    return User{
        .id = id,
        .name = owned_name,
    };
}

pub fn updateUserName(self: *DataAccessObject, allocator: std.mem.Allocator, old_name: []const u8, new_name: []const u8) !void {
    _ = allocator;
    _ = try self.pool.exec("UPDATE users SET name = $1 WHERE name = $2", .{ new_name, old_name });
}

pub fn deleteUser(self: *DataAccessObject, allocator: std.mem.Allocator, name: []const u8) !void {
    _ = allocator;
    _ = try self.pool.exec("DELETE FROM users WHERE name = $1", .{name});
}

pub fn listUsers(self: *DataAccessObject, allocator: std.mem.Allocator) ![]User {
    var result = try self.pool.query("SELECT id, name FROM users ORDER BY id", .{});
    defer result.deinit();
    
    var users = std.ArrayList(User).init(allocator);
    defer users.deinit();
    
    while (try result.next()) |row| {
        const id = row.get(i32, 0);
        const username = row.get([]const u8, 1);
        
        // Allocate memory for the name
        const owned_name = try allocator.dupe(u8, username);
        
        try users.append(User{
            .id = id,
            .name = owned_name,
        });
    }
    
    return users.toOwnedSlice();
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
    try dao.createUser(allocator, "test_alice");
    
    // Test read
    const user = try dao.getUserByName(allocator, "test_alice");
    defer if (user) |u| allocator.free(u.name);
    
    try std.testing.expect(user != null);
    try std.testing.expectEqualStrings("test_alice", user.?.name);
    
    // Test update
    try dao.updateUserName(allocator, "test_alice", "test_alice_updated");
    
    const updated_user = try dao.getUserByName(allocator, "test_alice_updated");
    defer if (updated_user) |u| allocator.free(u.name);
    
    try std.testing.expect(updated_user != null);
    try std.testing.expectEqualStrings("test_alice_updated", updated_user.?.name);
    
    // Test delete
    try dao.deleteUser(allocator, "test_alice_updated");
    
    const deleted_user = try dao.getUserByName(allocator, "test_alice_updated");
    try std.testing.expect(deleted_user == null);
    
    // Test list
    try dao.createUser(allocator, "test_user1");
    try dao.createUser(allocator, "test_user2");
    
    const users = try dao.listUsers(allocator);
    defer {
        for (users) |user| {
            allocator.free(user.name);
        }
        allocator.free(users);
    }
    
    try std.testing.expect(users.len >= 2);
    
    // Clean up
    dao.deleteUser(allocator, "test_user1") catch {};
    dao.deleteUser(allocator, "test_user2") catch {};
}