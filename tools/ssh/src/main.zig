//! Plue SSH Server CLI - Test command-line interface
//!
//! Usage:
//!   plue-ssh start --port 2222 --key /path/to/hostkey

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

    if (std.mem.eql(u8, command, "start")) {
        var port: u16 = 2222;
        var key_path: []const u8 = "/etc/ssh/ssh_host_rsa_key";

        // Parse options
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--port")) {
                if (args.next()) |port_str| {
                    port = std.fmt.parseInt(u16, port_str, 10) catch 2222;
                }
            } else if (std.mem.eql(u8, arg, "--key")) {
                if (args.next()) |k| {
                    key_path = k;
                }
            }
        }

        std.debug.print("Starting SSH server on port {d}...\n", .{port});
        std.debug.print("Host key: {s}\n", .{key_path});

        const config = lib.ServerConfig{
            .port = port,
            .host_key_path = key_path,
            .max_connections = 100,
        };

        const server = lib.SSHServer.init(allocator, config) catch |err| {
            std.debug.print("Failed to initialize server: {}\n", .{err});
            return;
        };
        defer server.deinit();

        // Set a test auth callback that accepts all
        server.setAuthCallback(testAuthCallback);

        server.start() catch |err| {
            std.debug.print("Failed to start server: {}\n", .{err});
            return;
        };

        std.debug.print("SSH server running. Press Ctrl+C to stop.\n", .{});

        // Wait for interrupt
        while (server.running) {
            std.Thread.sleep(1 * std.time.ns_per_s);
            std.debug.print("Connections: {d}\n", .{server.getConnectionCount()});
        }
    } else if (std.mem.eql(u8, command, "genkey")) {
        std.debug.print("Generating test host key...\n", .{});
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "ssh-keygen", "-t", "rsa", "-f", "test_host_key", "-N", "" },
        }) catch |err| {
            std.debug.print("Failed to generate key: {}\n", .{err});
            return;
        };
        std.debug.print("{s}", .{result.stdout});
        if (result.stderr.len > 0) {
            std.debug.print("{s}", .{result.stderr});
        }
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        printHelp();
    }
}

/// Test auth callback - accepts all connections (for testing only!)
fn testAuthCallback(username: [*:0]const u8, pubkey: [*:0]const u8) callconv(.c) bool {
    std.debug.print("Auth request: user={s}, key={s}...\n", .{
        std.mem.span(username),
        std.mem.span(pubkey)[0..@min(32, std.mem.span(pubkey).len)],
    });
    return true; // Accept all for testing
}

fn printHelp() void {
    const help =
        \\plue-ssh - SSH server for Git operations
        \\
        \\Usage:
        \\  plue-ssh start [options]    Start the SSH server
        \\  plue-ssh genkey             Generate a test host key
        \\
        \\Options:
        \\  --port <port>               Port to listen on (default: 2222)
        \\  --key <path>                Path to host key (default: /etc/ssh/ssh_host_rsa_key)
        \\
        \\Examples:
        \\  plue-ssh genkey
        \\  plue-ssh start --port 2222 --key ./test_host_key
        \\
        \\Environment:
        \\  The server requires a host key. Generate one with 'genkey' or use an existing key.
        \\
    ;
    std.debug.print("{s}", .{help});
}
