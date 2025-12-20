//! Plue PTY CLI - Test command-line interface
//!
//! Usage: plue-pty <command> [args...]

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

    // Initialize PTY manager
    var manager = lib.PTYManager.init(allocator, 10);
    defer manager.deinit();

    // Create session
    std.debug.print("Creating PTY session for: {s}\n", .{command});

    const session = manager.createSession(command, null) catch |err| {
        std.debug.print("Failed to create session: {}\n", .{err});
        return;
    };

    std.debug.print("Session created with ID: {d}, PID: {d}\n", .{ session.id, session.pid });

    // Read loop
    var buffer: [4096]u8 = undefined;
    var total_read: usize = 0;

    while (session.isRunning() or total_read == 0) {
        const bytes = manager.readOutput(session.id, &buffer) catch |err| {
            std.debug.print("Read error: {}\n", .{err});
            break;
        };

        if (bytes > 0) {
            total_read += bytes;
            std.debug.print("{s}", .{buffer[0..bytes]});
        } else {
            // No data, wait a bit
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }

        // Check status
        _ = manager.getStatus(session.id) catch break;
    }

    // Final status
    const final = manager.getStatus(session.id) catch {
        std.debug.print("\nSession ended.\n", .{});
        return;
    };

    std.debug.print("\nSession ended with exit code: {?d}\n", .{final.exit_code});
}

fn printHelp() void {
    const help =
        \\plue-pty - PTY session manager test CLI
        \\
        \\Usage: plue-pty <command> [args...]
        \\
        \\Arguments:
        \\  <command>    Command to execute in PTY
        \\
        \\Examples:
        \\  plue-pty ls -la
        \\  plue-pty echo "hello world"
        \\  plue-pty bash -c "echo test"
        \\
    ;
    std.debug.print("{s}", .{help});
}
