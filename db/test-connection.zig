const std = @import("std");
const pg = @import("pg");

test "basic connection" {
    const allocator = std.testing.allocator;

    std.debug.print("\n=== Testing PostgreSQL Connection ===\n", .{});

    const pool = pg.Pool.init(allocator, .{
        .size = 1,
        .connect = .{
            .host = "localhost",
            .port = 54321,
        },
        .auth = .{
            .database = "plue_test",
            .username = "postgres",
            .password = "password",
            .timeout = 5_000,
        },
    }) catch |err| {
        std.debug.print("Failed to init pool: {}\n", .{err});
        return err;
    };
    defer pool.deinit();

    std.debug.print("Pool initialized successfully\n", .{});

    const result = pool.query("SELECT 1 as num", .{}) catch |err| {
        std.debug.print("Query failed: {}\n", .{err});
        return err;
    };
    defer result.deinit();

    std.debug.print("Query executed successfully\n", .{});

    if (try result.next()) |row| {
        const num = row.get(i32, 0);
        std.debug.print("Got result: {}\n", .{num});
        try std.testing.expectEqual(@as(i32, 1), num);
    }

    std.debug.print("=== Test Complete ===\n", .{});
}
