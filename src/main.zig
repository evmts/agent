const std = @import("std");
const ServerManager = @import("server/manager.zig").ServerManager;
const ServerConfig = @import("server/config.zig").ServerConfig;

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
        return error.InvalidArguments;
    }

    const opencode_path = args[1];

    // Create server configuration
    var server_config = try ServerConfig.initDefault(allocator, opencode_path);
    server_config.port = 0; // Let OS assign port
    server_config.log_file_path = "/tmp/opencode.log";

    // Create and start server manager
    var server = try ServerManager.init(allocator, server_config);
    defer server.deinit();

    // Handle Ctrl+C gracefully
    try std.posix.sigaction(std.posix.SIG.INT, &std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);

    // Start the server
    server.start() catch |err| {
        std.log.err("Failed to start server: {}", .{err});
        return err;
    };

    // Wait for server to be ready
    server.waitReady(30000) catch |err| {
        std.log.err("Server failed to start within timeout: {}", .{err});
        return err;
    };

    std.log.info("OpenCode server running at {s}", .{server.getUrl()});
    std.log.info("Press Ctrl+C to stop the server", .{});

    // Monitor server state
    while (server.getState() == .running) {
        std.time.sleep(1 * std.time.ns_per_s);

        // Check if we received interrupt signal
        if (should_exit.load(.acquire)) {
            std.log.info("Received interrupt signal, shutting down...", .{});
            break;
        }
    }

    // Stop the server gracefully
    try server.stop();
}

var should_exit = std.atomic.Value(bool).init(false);

fn handleSignal(sig: c_int) callconv(.C) void {
    _ = sig;
    should_exit.store(true, .release);
}

test {
    std.testing.refAllDecls(@This());
}

// Example usage as a library
pub fn exampleUsage() !void {
    const allocator = std.heap.page_allocator;

    // Initialize server with custom configuration
    var config = try ServerConfig.initDefault(allocator, "./opencode");
    config.port = 0; // Auto-assign port
    config.startup_timeout_ms = 60000; // 60 seconds
    config.log_file_path = "/var/log/plue/opencode.log";

    var server = try ServerManager.init(allocator, config);
    defer server.deinit();

    // Start server
    try server.start();
    try server.waitReady(config.startup_timeout_ms);

    std.log.info("Server URL: {s}", .{server.getUrl()});

    // Use the server...
    
    // Stop when done
    try server.stop();
}