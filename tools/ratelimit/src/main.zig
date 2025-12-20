//! Plue Rate Limiter CLI - Test command-line interface
//!
//! Usage:
//!   plue-ratelimit check <key>       Check if request allowed
//!   plue-ratelimit remaining <key>   Get remaining requests
//!   plue-ratelimit reset <key>       Reset limit for key
//!   plue-ratelimit status            Show all tracked keys
//!   plue-ratelimit bench [count]     Run benchmark

const std = @import("std");
const lib = @import("lib.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    const command = args.next() orelse {
        printHelp();
        return;
    };

    if (std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "--help")) {
        printHelp();
        return;
    }

    // Default: 100 requests per 60 seconds
    var limiter = lib.RateLimiter.init(allocator, 100, 60000);
    defer limiter.deinit();

    if (std.mem.eql(u8, command, "check")) {
        const key = args.next() orelse {
            std.debug.print("Error: missing key argument\n", .{});
            return;
        };

        const allowed = limiter.check(key) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            return;
        };

        if (allowed) {
            std.debug.print("ALLOWED - {d} remaining\n", .{limiter.getRemaining(key)});
        } else {
            std.debug.print("RATE LIMITED - try again later\n", .{});
        }
    } else if (std.mem.eql(u8, command, "remaining")) {
        const key = args.next() orelse {
            std.debug.print("Error: missing key argument\n", .{});
            return;
        };

        const remaining = limiter.getRemaining(key);
        std.debug.print("{d} requests remaining\n", .{remaining});
    } else if (std.mem.eql(u8, command, "reset")) {
        const key = args.next() orelse {
            std.debug.print("Error: missing key argument\n", .{});
            return;
        };

        limiter.reset(key);
        std.debug.print("Reset limit for key: {s}\n", .{key});
    } else if (std.mem.eql(u8, command, "status")) {
        std.debug.print("Tracked keys: {d}\n", .{limiter.count()});
        std.debug.print("Max requests: 100 per 60s\n", .{});
    } else if (std.mem.eql(u8, command, "bench")) {
        const count_str = args.next() orelse "1000000";
        const count = std.fmt.parseInt(u32, count_str, 10) catch 1000000;

        runBenchmark(allocator, count);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        printHelp();
    }
}

fn runBenchmark(allocator: std.mem.Allocator, count: u32) void {
    std.debug.print("Running benchmark with {d} operations...\n", .{count});

    // High limit so we measure raw performance
    var limiter = lib.RateLimiter.init(allocator, 1000000000, 60000);
    defer limiter.deinit();

    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        // Use different keys to test hash map performance
        var key_buf: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "user{d}", .{i % 1000}) catch "user0";
        _ = limiter.check(key) catch {};
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = end - start;
    const elapsed_ms = @divFloor(elapsed_ns, std.time.ns_per_ms);
    const ops_per_sec = if (elapsed_ns > 0)
        @divFloor(@as(i128, count) * std.time.ns_per_s, elapsed_ns)
    else
        0;

    std.debug.print("\nResults:\n", .{});
    std.debug.print("  Operations: {d}\n", .{count});
    std.debug.print("  Time: {d}ms\n", .{elapsed_ms});
    std.debug.print("  Throughput: {d} ops/sec\n", .{ops_per_sec});
    std.debug.print("  Unique keys tracked: {d}\n", .{limiter.count()});
}

fn printHelp() void {
    const help =
        \\plue-ratelimit - Rate limiting test CLI
        \\
        \\Usage:
        \\  plue-ratelimit check <key>       Check if request is allowed
        \\  plue-ratelimit remaining <key>   Get remaining requests for key
        \\  plue-ratelimit reset <key>       Reset rate limit for key
        \\  plue-ratelimit status            Show rate limiter status
        \\  plue-ratelimit bench [count]     Run performance benchmark
        \\
        \\Default configuration: 100 requests per 60 seconds
        \\
        \\Examples:
        \\  plue-ratelimit check 192.168.1.1
        \\  plue-ratelimit check user:123
        \\  plue-ratelimit bench 1000000
        \\
    ;
    std.debug.print("{s}", .{help});
}
