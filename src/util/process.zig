const std = @import("std");
const builtin = @import("builtin");

pub const ProcessOptions = struct {
    cwd: ?[]const u8 = null,
    env: ?*const std.process.EnvMap = null,
    stdout: enum { inherit, pipe, ignore } = .pipe,
    stderr: enum { inherit, pipe, ignore } = .pipe,
};

pub const Process = struct {
    allocator: std.mem.Allocator,
    child: std.process.Child,
    stdout_buffer: ?[]u8 = null,
    stderr_buffer: ?[]u8 = null,

    const Self = @This();

    pub fn spawn(allocator: std.mem.Allocator, argv: []const []const u8, options: ProcessOptions) !*Self {
        var process = try allocator.create(Self);
        errdefer allocator.destroy(process);

        process.* = .{
            .allocator = allocator,
            .child = std.process.Child.init(argv, allocator),
            .stdout_buffer = null,
            .stderr_buffer = null,
        };

        // Set child options
        process.child.cwd = options.cwd;
        process.child.env_map = options.env;
        process.child.stdout_behavior = switch (options.stdout) {
            .inherit => .Inherit,
            .pipe => .Pipe,
            .ignore => .Ignore,
        };
        process.child.stderr_behavior = switch (options.stderr) {
            .inherit => .Inherit,
            .pipe => .Pipe,
            .ignore => .Ignore,
        };
        process.child.stdin_behavior = .Ignore;
        process.child.expand_arg0 = .no_expand;

        try process.child.spawn();

        return process;
    }

    pub fn wait(self: *Self) !std.process.Child.Term {
        return try self.child.wait();
    }

    pub fn collectOutput(self: *Self) !void {
        if (self.child.stdout) |stdout| {
            self.stdout_buffer = try stdout.reader().readAllAlloc(self.allocator, 50 * 1024 * 1024);
        }
        if (self.child.stderr) |stderr| {
            self.stderr_buffer = try stderr.reader().readAllAlloc(self.allocator, 50 * 1024 * 1024);
        }
    }

    pub fn kill(self: *Self) !void {
        _ = try self.child.kill();
    }

    pub fn isAlive(self: *const Self) bool {
        // Try to get process status without waiting
        if (builtin.os.tag == .windows) {
            // Windows-specific implementation
            // For now, we can't easily check without waiting
            return true; // Assume alive if not explicitly terminated
        } else {
            // Unix-like systems (macOS, Linux)
            const pid = @as(std.posix.pid_t, @intCast(self.child.id));
            const result = std.posix.kill(pid, 0);
            // If kill(pid, 0) succeeds, process exists
            // If it fails with ESRCH, process doesn't exist
            if (result) {
                return true;
            } else |err| {
                return err != error.ProcessNotFound;
            }
        }
    }

    pub fn getPid(self: *const Self) std.process.Child.Id {
        return self.child.id;
    }

    pub fn getStdout(self: *const Self) ?[]const u8 {
        return self.stdout_buffer;
    }

    pub fn getStderr(self: *const Self) ?[]const u8 {
        return self.stderr_buffer;
    }

    pub fn deinit(self: *Self) void {
        if (self.stdout_buffer) |buf| {
            self.allocator.free(buf);
        }
        if (self.stderr_buffer) |buf| {
            self.allocator.free(buf);
        }
        self.allocator.destroy(self);
    }

    /// Spawn a process and wait for it to complete, returning stdout
    pub fn exec(allocator: std.mem.Allocator, argv: []const []const u8, options: ProcessOptions) ![]const u8 {
        var process = try spawn(allocator, argv, options);
        defer process.deinit();

        try process.collectOutput();
        const term = try process.wait();

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    const stderr = process.getStderr() orelse "";
                    std.log.err("Command failed with exit code {d}: {s}", .{ code, stderr });
                    return error.CommandFailed;
                }
            },
            else => {
                std.log.err("Command terminated abnormally", .{});
                return error.CommandFailed;
            },
        }

        return process.getStdout() orelse "";
    }

    /// Kill process with timeout
    pub fn killWithTimeout(self: *Self, timeout_ms: u32) !void {
        // First try graceful termination (SIGTERM on Unix)
        if (builtin.os.tag != .windows) {
            const pid = @as(std.posix.pid_t, @intCast(self.child.id));
            _ = std.posix.kill(pid, std.posix.SIG.TERM) catch {};

            // Wait for process to terminate gracefully
            var elapsed: u32 = 0;
            while (elapsed < timeout_ms) : (elapsed += 100) {
                if (!self.isAlive()) {
                    return;
                }
                std.time.sleep(100 * std.time.ns_per_ms);
            }
        }

        // Force kill if still alive
        try self.kill();
    }
};

test "process spawn and wait" {
    const allocator = std.testing.allocator;

    const argv = &[_][]const u8{ "echo", "hello world" };
    var process = try Process.spawn(allocator, argv, .{});
    defer process.deinit();

    try process.collectOutput();
    const term = try process.wait();

    try std.testing.expect(term == .Exited);
    try std.testing.expect(term.Exited == 0);

    const stdout = process.getStdout() orelse "";
    try std.testing.expect(std.mem.eql(u8, std.mem.trim(u8, stdout, "\n"), "hello world"));
}

test "process with custom working directory" {
    const allocator = std.testing.allocator;

    const argv = &[_][]const u8{"pwd"};
    var process = try Process.spawn(allocator, argv, .{ .cwd = "/tmp" });
    defer process.deinit();

    try process.collectOutput();
    const term = try process.wait();

    try std.testing.expect(term == .Exited);
    try std.testing.expect(term.Exited == 0);

    const stdout = process.getStdout() orelse "";
    try std.testing.expect(std.mem.eql(u8, std.mem.trim(u8, stdout, "\n"), "/tmp"));
}

test "process exec helper" {
    const allocator = std.testing.allocator;

    const argv = &[_][]const u8{ "echo", "test exec" };
    const output = try Process.exec(allocator, argv, .{});
    defer allocator.free(output);

    try std.testing.expect(std.mem.eql(u8, std.mem.trim(u8, output, "\n"), "test exec"));
}

test "process kill" {
    const allocator = std.testing.allocator;

    const argv = &[_][]const u8{ "sleep", "10" };
    var process = try Process.spawn(allocator, argv, .{});
    defer process.deinit();

    try std.testing.expect(process.isAlive());

    try process.kill();
    const term = try process.wait();

    try std.testing.expect(term != .Exited or term.Exited != 0);
}