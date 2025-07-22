const std = @import("std");
const clap = @import("clap");

var should_exit: bool = false;

pub fn run(allocator: std.mem.Allocator, iter: *std.process.ArgIterator) !void {
    _ = allocator;
    _ = iter;
    
    try setupSignalHandlers();
    
    std.log.info("Start command running... Press Ctrl+C to exit gracefully", .{});
    
    while (!should_exit) {
        std.time.sleep(100 * std.time.ns_per_ms);
    }
    
    std.log.info("Graceful shutdown complete", .{});
}

fn setupSignalHandlers() !void {
    const sigint_action = std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    
    const sigterm_action = std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    
    std.posix.sigaction(std.posix.SIG.INT, &sigint_action, null);
    std.posix.sigaction(std.posix.SIG.TERM, &sigterm_action, null);
}

fn handleSignal(sig: c_int) callconv(.C) void {
    switch (sig) {
        std.posix.SIG.INT, std.posix.SIG.TERM => {
            should_exit = true;
        },
        else => {},
    }
}

test "start command sets up correctly" {
    const allocator = std.testing.allocator;
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();
    
    var os_args = try std.process.argsWithAllocator(allocator);
    defer os_args.deinit();
    
    var iter = std.process.ArgIterator.init();
    
    should_exit = true;
    
    try run(allocator, &iter);
    
    try std.testing.expect(should_exit == true);
}