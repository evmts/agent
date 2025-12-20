//! Plue JWT CLI - Test command-line interface
//!
//! Usage:
//!   plue-jwt sign <payload-json>
//!   plue-jwt verify <token>

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

    // Get secret from env or use default for testing
    const secret = std.posix.getenv("JWT_SECRET") orelse "test-secret-key-for-development";

    var manager = lib.JWTManager.init(allocator, secret);

    if (std.mem.eql(u8, command, "sign")) {
        const payload = args.next() orelse {
            std.debug.print("Error: missing payload argument\n", .{});
            std.debug.print("Usage: plue-jwt sign '<json-payload>'\n", .{});
            return;
        };

        const token = manager.sign(payload) catch |err| {
            std.debug.print("Error signing JWT: {}\n", .{err});
            return;
        };
        defer manager.free(token);

        std.debug.print("{s}\n", .{token});
    } else if (std.mem.eql(u8, command, "verify")) {
        const token = args.next() orelse {
            std.debug.print("Error: missing token argument\n", .{});
            std.debug.print("Usage: plue-jwt verify '<token>'\n", .{});
            return;
        };

        const payload = manager.verify(token) catch |err| {
            std.debug.print("Verification failed: {}\n", .{err});
            return;
        };
        defer manager.free(payload);

        std.debug.print("Valid token!\n", .{});
        std.debug.print("Payload: {s}\n", .{payload});
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        printHelp();
    }
}

fn printHelp() void {
    const help =
        \\plue-jwt - JWT signing and verification CLI
        \\
        \\Usage:
        \\  plue-jwt sign '<json-payload>'    Sign a payload and output JWT
        \\  plue-jwt verify '<token>'         Verify a JWT and show payload
        \\
        \\Environment:
        \\  JWT_SECRET                        Secret key for HMAC-SHA256
        \\                                    (default: test-secret-key-for-development)
        \\
        \\Examples:
        \\  plue-jwt sign '{"userId":123,"username":"alice"}'
        \\  plue-jwt verify 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
        \\
        \\  # With custom secret:
        \\  JWT_SECRET=my-secret plue-jwt sign '{"test":true}'
        \\
    ;
    std.debug.print("{s}", .{help});
}
