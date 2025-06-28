const std = @import("std");
const ServerManager = @import("server/manager.zig").ServerManager;
const ServerConfig = @import("server/config.zig").ServerConfig;

// Simple test executable for OpenCode server management
pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.err("Usage: {s} <opencode-path>", .{args[0]});
        std.log.err("Example: {s} ./opencode", .{args[0]});
        return error.InvalidArguments;
    }

    const opencode_path = args[1];

    // Verify OpenCode path exists
    var dir = std.fs.openDirAbsolute(opencode_path, .{}) catch |err| {
        std.log.err("OpenCode path '{s}' does not exist or is not accessible: {}", .{ opencode_path, err });
        return err;
    };
    dir.close();

    std.log.info("Starting OpenCode server management test", .{});
    std.log.info("OpenCode path: {s}", .{opencode_path});

    // Create server configuration
    var server_config = try ServerConfig.initDefault(allocator, opencode_path);
    server_config.port = 0; // Let OS assign port
    server_config.log_file_path = "/tmp/opencode-test.log";

    // Create and start server manager
    var server = try ServerManager.init(allocator, server_config);
    defer server.deinit();

    // Handle Ctrl+C gracefully
    std.posix.sigaction(std.posix.SIG.INT, &std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);

    // Start the server
    std.log.info("Starting OpenCode server...", .{});
    server.start() catch |err| {
        std.log.err("Failed to start server: {}", .{err});
        return err;
    };

    // Wait for server to be ready
    std.log.info("Waiting for server to be ready (timeout: 30s)...", .{});
    server.waitReady(30000) catch |err| {
        std.log.err("Server failed to start within timeout: {}", .{err});
        
        // Check process output for debugging
        if (server.process) |process| {
            if (process.getStdout()) |stdout| {
                std.log.err("Server stdout:\n{s}", .{stdout});
            }
            if (process.getStderr()) |stderr| {
                std.log.err("Server stderr:\n{s}", .{stderr});
            }
        }
        
        return err;
    };

    std.log.info("✅ OpenCode server running at {s}", .{server.getUrl()});
    std.log.info("Press Ctrl+C to stop the server", .{});

    // Monitor server state
    var last_state = server.getState();
    while (server.getState() == .running) {
        std.time.sleep(1 * std.time.ns_per_s);

        // Log state changes
        const current_state = server.getState();
        if (current_state != last_state) {
            std.log.info("Server state changed: {} -> {}", .{ last_state, current_state });
            last_state = current_state;
        }

        // Check if we received interrupt signal
        if (should_exit.load(.acquire)) {
            std.log.info("Received interrupt signal, shutting down...", .{});
            break;
        }
    }

    // Stop the server gracefully
    std.log.info("Stopping server...", .{});
    try server.stop();
    std.log.info("✅ Server stopped successfully", .{});

    // Display final statistics
    std.log.info("Test completed successfully!", .{});
    if (server.log_file) |_| {
        std.log.info("Server logs written to: /tmp/opencode-test.log", .{});
    }
}

var should_exit = std.atomic.Value(bool).init(false);

fn handleSignal(sig: c_int) callconv(.C) void {
    _ = sig;
    should_exit.store(true, .release);
}