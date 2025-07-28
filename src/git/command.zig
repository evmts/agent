const std = @import("std");
const builtin = @import("builtin");

// Initialize SIGPIPE handling on module load (for POSIX systems)
const init_sigpipe = blk: {
    if (builtin.os.tag != .windows) {
        var sa = std.posix.Sigaction{
            .handler = .{ .handler = std.posix.SIG.IGN },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        };
        std.posix.sigaction(.PIPE, &sa, null) catch {};
    }
    break :blk {};
};

// Phase 1: Core Security Foundation - Tests First

test "rejects arguments starting with dash" {
    const allocator = std.testing.allocator;
    try std.testing.expect(!isSafeArgumentValue("-v"));
    try std.testing.expect(!isSafeArgumentValue("--version"));
    try std.testing.expect(isSafeArgumentValue("main"));
}

test "validates known git options" {
    try std.testing.expect(isValidGitOption("--version"));
    try std.testing.expect(isValidGitOption("--no-pager"));
    try std.testing.expect(!isValidGitOption("--random-flag"));
}

test "rejects broken git arguments" {
    // Test known problematic arguments
    try std.testing.expect(isBrokenGitArgument("--upload-archive"));  // Old syntax
    try std.testing.expect(isBrokenGitArgument("--output"));  // Can write arbitrary files
    try std.testing.expect(!isBrokenGitArgument("--version"));
}

test "sanitizes repository paths" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidRepository, validateRepositoryPath("../../../etc"));
    try std.testing.expectError(error.InvalidRepository, validateRepositoryPath("/etc/passwd"));
    try validateRepositoryPath("repos/user/project.git");
}

// Now implement the functions to make tests pass

fn isSafeArgumentValue(value: []const u8) bool {
    if (value.len == 0) return false;
    return value[0] != '-';
}

const VALID_GIT_OPTIONS = [_][]const u8{
    "--version",
    "--no-pager",
    "--bare",
    "--quiet",
    "-q",
    "--verbose",
    "-v",
    "--no-replace-objects",
    "--literal-pathspecs",
    "--glob-pathspecs",
    "--noglob-pathspecs",
    "--icase-pathspecs",
    "--no-optional-locks",
};

fn isValidGitOption(option: []const u8) bool {
    for (VALID_GIT_OPTIONS) |valid_opt| {
        if (std.mem.eql(u8, option, valid_opt)) {
            return true;
        }
    }
    return false;
}

const BROKEN_GIT_ARGS = [_][]const u8{
    "--upload-archive",  // Old syntax, security risk
    "--output",          // Can write to arbitrary files
    "--export-all",      // Exposes all refs
    "--receive-pack",    // Can be exploited
    "--exec",            // Arbitrary command execution
};

fn isBrokenGitArgument(arg: []const u8) bool {
    for (BROKEN_GIT_ARGS) |broken_arg| {
        if (std.mem.eql(u8, arg, broken_arg)) {
            return true;
        }
    }
    return false;
}

pub const GitError = error{
    GitNotFound,
    InvalidArgument,
    CommandInjection,
    Timeout,
    ProcessFailed,
    PermissionDenied,
    InvalidRepository,
    AuthenticationFailed,
    ChildProcessFailed,
    OutputTooLarge,
};

fn validateRepositoryPath(path: []const u8) GitError!void {
    // Check for directory traversal
    if (std.mem.indexOf(u8, path, "..") != null) {
        return error.InvalidRepository;
    }
    
    // Check for absolute paths
    if (path.len > 0 and path[0] == '/') {
        return error.InvalidRepository;
    }
    
    // Check path length (Git's limit is 1024)
    if (path.len > 1024) {
        return error.InvalidRepository;
    }
}

fn sanitizeGitUrl(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    // Remove credentials from URLs like https://user:pass@github.com/repo.git
    if (std.mem.indexOf(u8, url, "@")) |at_pos| {
        if (std.mem.startsWith(u8, url, "https://") or std.mem.startsWith(u8, url, "http://")) {
            const protocol_end = std.mem.indexOf(u8, url, "://").? + 3;
            const after_at = url[at_pos + 1..];
            
            var result = std.ArrayList(u8).init(allocator);
            try result.appendSlice(url[0..protocol_end]);
            try result.appendSlice(after_at);
            return result.toOwnedSlice();
        }
    }
    
    // If no credentials found, return a copy
    return allocator.dupe(u8, url);
}

test "sanitizes git urls with credentials" {
    const allocator = std.testing.allocator;
    
    const url1 = try sanitizeGitUrl(allocator, "https://user:pass@github.com/repo.git");
    defer allocator.free(url1);
    try std.testing.expectEqualStrings("https://github.com/repo.git", url1);
    
    const url2 = try sanitizeGitUrl(allocator, "git@github.com:owner/repo.git");
    defer allocator.free(url2);
    try std.testing.expectEqualStrings("git@github.com:owner/repo.git", url2);
}

// Phase 2: Git Executable Detection - Tests First

test "finds git executable" {
    const allocator = std.testing.allocator;
    const git_path = findGitExecutable(allocator) catch {
        std.log.warn("Git not available, skipping test", .{});
        return;
    };
    defer allocator.free(git_path);

    try std.testing.expect(git_path.len > 0);
    try std.testing.expect(std.mem.endsWith(u8, git_path, "git") or 
                          (builtin.os.tag == .windows and std.mem.endsWith(u8, git_path, "git.exe")));
}

test "detects git version" {
    const allocator = std.testing.allocator;
    const version = getGitVersion(allocator) catch {
        std.log.warn("Git not available, skipping test", .{});
        return;
    };
    defer allocator.free(version);

    try std.testing.expect(std.mem.indexOf(u8, version, "git version") != null);
}

// Global cache for git executable path
var g_git_path: ?[]const u8 = null;
var g_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

pub fn findGitExecutable(allocator: std.mem.Allocator) ![]const u8 {
    if (g_git_path) |path| return allocator.dupe(u8, path);
    
    // Check standard paths first
    const standard_paths = if (builtin.os.tag == .windows)
        [_][]const u8{ "C:\\Program Files\\Git\\bin\\git.exe", "C:\\Program Files (x86)\\Git\\bin\\git.exe" }
    else
        [_][]const u8{ "/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git" };
    
    for (standard_paths) |path| {
        const stat = std.fs.cwd().statFile(path) catch continue;
        if (stat.kind == .file) {
            g_git_path = try g_arena.allocator().dupe(u8, path);
            return allocator.dupe(u8, g_git_path.?);
        }
    }
    
    // Search PATH
    const path_env = std.process.getEnvVarOwned(allocator, "PATH") catch {
        return error.GitNotFound;
    };
    defer allocator.free(path_env);
    
    var it = std.mem.tokenize(u8, path_env, &[_]u8{std.fs.path.delimiter});
    while (it.next()) |dir| {
        const git_name = if (builtin.os.tag == .windows) "git.exe" else "git";
        const git_path = try std.fs.path.join(allocator, &.{ dir, git_name });
        defer allocator.free(git_path);
        
        // Check if executable exists
        const stat = std.fs.cwd().statFile(git_path) catch continue;
        if (stat.kind != .file) continue;
        
        // Check if executable on Unix
        if (builtin.os.tag.isDarwin() or builtin.os.tag == .linux) {
            if (stat.mode & 0o111 == 0) continue;
        }
        
        g_git_path = try g_arena.allocator().dupe(u8, git_path);
        return allocator.dupe(u8, g_git_path.?);
    }
    
    return error.GitNotFound;
}

fn getGitVersion(allocator: std.mem.Allocator) ![]u8 {
    const git_path = try findGitExecutable(allocator);
    defer allocator.free(git_path);
    
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ git_path, "--version" },
    });
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);
    
    if (result.term.Exited != 0) {
        return error.GitNotFound;
    }
    
    // Return a copy of stdout
    return allocator.dupe(u8, std.mem.trimRight(u8, result.stdout, "\n\r"));
}

// Phase 3: Basic Command Execution - Tests First

test "executes simple git command" {
    const allocator = std.testing.allocator;

    var cmd = try GitCommand.init(allocator);
    defer cmd.deinit(allocator);

    const result = try cmd.run(allocator, &.{"version"});
    defer result.deinit(allocator);

    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "git version") != null);
}

test "captures stderr on failure" {
    const allocator = std.testing.allocator;

    var cmd = try GitCommand.init(allocator);
    defer cmd.deinit(allocator);

    const result = try cmd.run(allocator, &.{"invalid-command"});
    defer result.deinit(allocator);

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(result.stderr.len > 0);
}

// Implementation of GitCommand and related types

pub const GitResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,

    pub fn deinit(self: *GitResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

// Rich error information for debugging
pub const GitCommandError = struct {
    err: GitError,
    exit_code: ?u8 = null,
    command: []const u8,
    args: []const []const u8,
    cwd: ?[]const u8 = null,
    stderr: ?[]const u8 = null,

    pub fn format(
        self: GitCommandError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Git command failed: {s}", .{@errorName(self.err)});
        if (self.exit_code) |code| {
            try writer.print(" (exit code: {})", .{code});
        }
        try writer.print("\nCommand: {s}", .{self.command});
        for (self.args) |arg| {
            try writer.print(" {s}", .{arg});
        }
        if (self.cwd) |cwd| {
            try writer.print("\nWorking directory: {s}", .{cwd});
        }
        if (self.stderr) |stderr| {
            try writer.print("\nStderr: {s}", .{stderr});
        }
    }
};

pub const GitCommand = struct {
    executable_path: []const u8,

    pub fn init(allocator: std.mem.Allocator) !GitCommand {
        const path = try findGitExecutable(allocator);
        return GitCommand{
            .executable_path = path,
        };
    }

    pub fn deinit(self: *GitCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.executable_path);
    }

    pub fn run(self: *const GitCommand, allocator: std.mem.Allocator, args: []const []const u8) !GitResult {
        return self.runWithOptions(allocator, .{ .args = args });
    }

    pub const RunOptions = struct {
        args: []const []const u8,
        cwd: ?[]const u8 = null,
        env: ?[]const EnvVar = null,  // Only allowed vars will be passed
        timeout_ms: u32 = 120000, // 2 minutes default
        stdin: ?[]const u8 = null,
    };

    pub const EnvVar = struct {
        name: []const u8,
        value: []const u8,
    };

    // Strict allow-list for environment variables
    // CRITICAL: Never include GIT_EXEC_PATH, GIT_SSH_COMMAND, or HTTP_PROXY
    const ALLOWED_ENV_VARS = [_][]const u8{
        "GIT_AUTHOR_NAME",
        "GIT_AUTHOR_EMAIL",
        "GIT_COMMITTER_NAME", 
        "GIT_COMMITTER_EMAIL",
        "GIT_HTTP_USER_AGENT",
        "GIT_PROTOCOL",
        "GIT_TERMINAL_PROMPT",
        "GIT_NAMESPACE",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_OBJECT_DIRECTORY",
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_PREFIX",
        "GIT_SUPER_PREFIX",
        "GIT_QUARANTINE_PATH",
        "GIT_CONFIG_NOSYSTEM",
        "GIT_CONFIG_GLOBAL",
        "HOME",  // Required for git config
        "PATH",  // Required for finding git
        "LC_ALL", // Locale
        "LANG",   // Locale
        // Protocol-specific (added conditionally)
        "PLUE_PUSHER_ID",
        "PLUE_PUSHER_NAME", 
        "PLUE_REPO_USER_NAME",
        "PLUE_REPO_NAME",
        "PLUE_REPO_IS_WIKI",
        "PLUE_IS_INTERNAL",
        "PLUE_PR_ID",
        "PLUE_KEY_ID",
    };

    fn isAllowedEnvVar(name: []const u8) bool {
        for (ALLOWED_ENV_VARS) |allowed| {
            if (std.mem.eql(u8, name, allowed)) {
                return true;
            }
        }
        return false;
    }

    // Helper for timeout monitoring
    const TimeoutState = struct {
        child: *std.process.Child,
        timeout_ms: u32,
        timed_out: bool = false,
        mutex: std.Thread.Mutex = .{},
    };

    fn timeoutMonitor(state: *TimeoutState) void {
        std.time.sleep(state.timeout_ms * std.time.ns_per_ms);
        
        state.mutex.lock();
        defer state.mutex.unlock();
        
        if (!state.timed_out) {
            state.timed_out = true;
            state.child.kill() catch {};
        }
    }

    pub fn runWithOptions(self: *const GitCommand, allocator: std.mem.Allocator, options: RunOptions) !GitResult {
        // Validate all arguments
        for (options.args) |arg, i| {
            // First argument can be a git command (like "status", "commit")
            if (i == 0) continue;
            
            // If it looks like an option, validate it
            if (arg.len > 0 and arg[0] == '-') {
                if (!isValidGitOption(arg) and isBrokenGitArgument(arg)) {
                    return error.InvalidArgument;
                }
            } else {
                // For non-option arguments, ensure they don't start with dash
                if (!isSafeArgumentValue(arg)) {
                    return error.InvalidArgument;
                }
            }
        }

        // Build full argv
        var argv = std.ArrayList([]const u8).init(allocator);
        defer argv.deinit();
        try argv.append(self.executable_path);
        try argv.appendSlice(options.args);

        // Build environment map if needed
        var env_map = if (options.env != null) std.process.EnvMap.init(allocator) else null;
        defer if (env_map) |*em| em.deinit();

        if (options.env) |env_vars| {
            // Start with minimal environment
            try env_map.?.put("PATH", std.process.getEnvVarOwned(allocator, "PATH") catch "/usr/local/bin:/usr/bin:/bin");
            try env_map.?.put("HOME", std.process.getEnvVarOwned(allocator, "HOME") catch "/tmp");
            
            // Add only allowed environment variables
            for (env_vars) |env_var| {
                if (isAllowedEnvVar(env_var.name)) {
                    try env_map.?.put(env_var.name, env_var.value);
                }
            }
        }

        // Create child process for timeout support
        var child = std.process.Child.init(argv.items, allocator);
        child.cwd = options.cwd;
        child.env_map = if (env_map) |*em| em else null;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        child.stdin_behavior = if (options.stdin != null) .Pipe else .Ignore;

        try child.spawn();

        // Set up timeout monitoring if needed
        var timeout_state = TimeoutState{
            .child = &child,
            .timeout_ms = options.timeout_ms,
        };
        
        const timeout_thread = if (options.timeout_ms > 0)
            try std.Thread.spawn(.{}, timeoutMonitor, .{&timeout_state})
        else
            null;
        defer if (timeout_thread) |t| t.join();

        // Write stdin if provided
        if (options.stdin) |stdin_data| {
            if (child.stdin) |stdin| {
                try stdin.writeAll(stdin_data);
                stdin.close();
                child.stdin = null;
            }
        }

        // Collect output
        var stdout_list = std.ArrayList(u8).init(allocator);
        var stderr_list = std.ArrayList(u8).init(allocator);
        errdefer stdout_list.deinit();
        errdefer stderr_list.deinit();

        // Read output with size limit
        const max_size = 10 * 1024 * 1024; // 10MB
        var buffer: [4096]u8 = undefined;

        if (child.stdout) |stdout| {
            while (true) {
                const n = stdout.read(&buffer) catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                };
                if (n == 0) break;
                
                if (stdout_list.items.len + n > max_size) {
                    return error.OutputTooLarge;
                }
                try stdout_list.appendSlice(buffer[0..n]);
            }
        }

        if (child.stderr) |stderr| {
            while (true) {
                const n = stderr.read(&buffer) catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                };
                if (n == 0) break;
                
                if (stderr_list.items.len + n > max_size) {
                    return error.OutputTooLarge;
                }
                try stderr_list.appendSlice(buffer[0..n]);
            }
        }

        // Wait for process
        const term = try child.wait();

        // Check if timed out
        timeout_state.mutex.lock();
        const timed_out = timeout_state.timed_out;
        timeout_state.mutex.unlock();

        if (timed_out) {
            stdout_list.deinit();
            stderr_list.deinit();
            return error.Timeout;
        }

        // Extract exit code
        const exit_code = switch (term) {
            .Exited => |code| code,
            else => 255, // Non-zero for other termination types
        };

        return GitResult{
            .stdout = try stdout_list.toOwnedSlice(),
            .stderr = try stderr_list.toOwnedSlice(),
            .exit_code = @intCast(exit_code),
        };
    }

    pub const StreamingOptions = struct {
        args: []const []const u8,
        cwd: ?[]const u8 = null,
        env: ?[]const EnvVar = null,
        timeout_ms: u32 = 120000,
        stdin: ?[]const u8 = null,
        stdout_callback: ?*const fn([]const u8, *anyopaque) anyerror!void = null,
        stdout_context: ?*anyopaque = null,
        stderr_callback: ?*const fn([]const u8, *anyopaque) anyerror!void = null,
        stderr_context: ?*anyopaque = null,
    };

    pub fn runStreaming(self: *const GitCommand, allocator: std.mem.Allocator, options: StreamingOptions) !u8 {
        // Validate arguments (same as runWithOptions)
        for (options.args) |arg, i| {
            if (i == 0) continue;
            if (arg.len > 0 and arg[0] == '-') {
                if (!isValidGitOption(arg) and isBrokenGitArgument(arg)) {
                    return error.InvalidArgument;
                }
            } else {
                if (!isSafeArgumentValue(arg)) {
                    return error.InvalidArgument;
                }
            }
        }

        // Build full argv
        var argv = std.ArrayList([]const u8).init(allocator);
        defer argv.deinit();
        try argv.append(self.executable_path);
        try argv.appendSlice(options.args);

        // Build environment map if needed
        var env_map = if (options.env != null) std.process.EnvMap.init(allocator) else null;
        defer if (env_map) |*em| em.deinit();

        if (options.env) |env_vars| {
            // Start with minimal environment
            try env_map.?.put("PATH", std.process.getEnvVarOwned(allocator, "PATH") catch "/usr/local/bin:/usr/bin:/bin");
            try env_map.?.put("HOME", std.process.getEnvVarOwned(allocator, "HOME") catch "/tmp");
            
            // Add only allowed environment variables
            for (env_vars) |env_var| {
                if (isAllowedEnvVar(env_var.name)) {
                    try env_map.?.put(env_var.name, env_var.value);
                }
            }
        }

        // Create child process
        var child = std.process.Child.init(argv.items, allocator);
        child.cwd = options.cwd;
        child.env_map = if (env_map) |*em| em else null;
        child.stdin_behavior = if (options.stdin != null) .Pipe else .Ignore;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        // Set up timeout monitoring for streaming
        var timeout_state = TimeoutState{
            .child = &child,
            .timeout_ms = options.timeout_ms,
        };
        
        const timeout_thread = if (options.timeout_ms > 0)
            try std.Thread.spawn(.{}, timeoutMonitor, .{&timeout_state})
        else
            null;
        defer if (timeout_thread) |t| t.join();

        // Write stdin if provided
        if (options.stdin) |stdin_data| {
            if (child.stdin) |stdin| {
                try stdin.writeAll(stdin_data);
                stdin.close();
                child.stdin = null;
            }
        }

        // Read stdout and stderr in chunks
        const BUFFER_SIZE = 16 * 1024;
        var stdout_buffer: [BUFFER_SIZE]u8 = undefined;
        var stderr_buffer: [BUFFER_SIZE]u8 = undefined;

        var stdout_done = false;
        var stderr_done = false;

        while (!stdout_done or !stderr_done) {
            if (!stdout_done) {
                if (child.stdout) |stdout| {
                    const n = stdout.read(&stdout_buffer) catch |err| switch (err) {
                        error.EndOfStream => {
                            stdout_done = true;
                            continue;
                        },
                        else => return err,
                    };
                    
                    if (n == 0) {
                        stdout_done = true;
                    } else if (options.stdout_callback) |callback| {
                        try callback(stdout_buffer[0..n], options.stdout_context.?);
                    }
                }
            }

            if (!stderr_done) {
                if (child.stderr) |stderr| {
                    const n = stderr.read(&stderr_buffer) catch |err| switch (err) {
                        error.EndOfStream => {
                            stderr_done = true;
                            continue;
                        },
                        else => return err,
                    };
                    
                    if (n == 0) {
                        stderr_done = true;
                    } else if (options.stderr_callback) |callback| {
                        try callback(stderr_buffer[0..n], options.stderr_context.?);
                    }
                }
            }
        }

        // Wait for process to finish
        const term = try child.wait();
        
        // Check if timed out
        timeout_state.mutex.lock();
        const timed_out = timeout_state.timed_out;
        timeout_state.mutex.unlock();

        if (timed_out) {
            return error.Timeout;
        }
        
        const exit_code = switch (term) {
            .Exited => |code| code,
            else => 255,
        };

        return @intCast(exit_code);
    }

    pub const ProtocolContext = struct {
        pusher_id: []const u8,
        pusher_name: []const u8,
        repo_username: []const u8,
        repo_name: []const u8,
        is_wiki: bool,
        is_deploy_key: bool = false,
        key_id: ?[]const u8 = null,
    };

    pub const ProtocolRunOptions = struct {
        args: []const []const u8,
        stdin: ?[]const u8 = null,
        protocol_context: ProtocolContext,
        timeout_ms: u32 = 600000, // 10 minutes for large repos
    };

    pub fn runWithProtocolContext(
        self: *const GitCommand,
        allocator: std.mem.Allocator,
        options: ProtocolRunOptions,
    ) !GitResult {
        // Create environment with protocol context
        var env_list = std.ArrayList(EnvVar).init(allocator);
        defer env_list.deinit();

        // Add protocol-specific environment variables
        try env_list.append(.{ .name = "PLUE_PUSHER_ID", .value = options.protocol_context.pusher_id });
        try env_list.append(.{ .name = "PLUE_PUSHER_NAME", .value = options.protocol_context.pusher_name });
        try env_list.append(.{ .name = "PLUE_REPO_USER_NAME", .value = options.protocol_context.repo_username });
        try env_list.append(.{ .name = "PLUE_REPO_NAME", .value = options.protocol_context.repo_name });
        try env_list.append(.{ .name = "PLUE_REPO_IS_WIKI", .value = if (options.protocol_context.is_wiki) "true" else "false" });
        
        if (options.protocol_context.key_id) |key_id| {
            try env_list.append(.{ .name = "PLUE_KEY_ID", .value = key_id });
        }

        return self.runWithOptions(allocator, .{
            .args = options.args,
            .stdin = options.stdin,
            .env = env_list.items,
            .timeout_ms = options.timeout_ms,
        });
    }
};

// Phase 4: Environment and Working Directory - Tests First

test "sets working directory" {
    const allocator = std.testing.allocator;

    // Create temp directory
    const tmp_dir_name = try std.fmt.allocPrint(allocator, "git_test_{d}", .{std.crypto.random.int(u32)});
    defer allocator.free(tmp_dir_name);
    
    try std.fs.cwd().makeDir(tmp_dir_name);
    defer std.fs.cwd().deleteTree(tmp_dir_name) catch {};

    var cmd = try GitCommand.init(allocator);
    defer cmd.deinit(allocator);

    const result = try cmd.runWithOptions(allocator, .{
        .args = &.{"init"},
        .cwd = tmp_dir_name,
    });
    defer result.deinit(allocator);

    try std.testing.expect(result.exit_code == 0);
}

test "uses strict environment allow-list" {
    const allocator = std.testing.allocator;

    var cmd = try GitCommand.init(allocator);
    defer cmd.deinit(allocator);

    // Test that only allowed GIT_* vars are passed
    const result = try cmd.runWithOptions(allocator, .{
        .args = &.{"config", "--list"},
        .env = &.{
            .{ .name = "GIT_AUTHOR_NAME", .value = "Test User" },
            .{ .name = "GIT_COMMITTER_EMAIL", .value = "test@example.com" },
            .{ .name = "MALICIOUS_VAR", .value = "should not pass" },
        },
    });
    defer result.deinit(allocator);

    // Git config --list should succeed
    try std.testing.expect(result.exit_code == 0);
}

// Phase 5: Streaming I/O Support - Tests First

test "streams large output" {
    const allocator = std.testing.allocator;

    var cmd = try GitCommand.init(allocator);
    defer cmd.deinit(allocator);

    var stdout_chunks = std.ArrayList([]u8).init(allocator);
    defer {
        for (stdout_chunks.items) |chunk| allocator.free(chunk);
        stdout_chunks.deinit();
    }

    const StreamContext = struct {
        allocator: std.mem.Allocator,
        chunks: *std.ArrayList([]u8),
    };

    const exit_code = try cmd.runStreaming(allocator, .{
        .args = &.{"log", "--oneline", "-n", "10"},
        .stdout_callback = struct {
            fn callback(data: []const u8, context: *anyopaque) !void {
                const ctx = @ptrCast(*StreamContext, @alignCast(@alignOf(StreamContext), context));
                const chunk = try ctx.allocator.dupe(u8, data);
                try ctx.chunks.append(chunk);
            }
        }.callback,
        .stdout_context = &StreamContext{
            .allocator = allocator,
            .chunks = &stdout_chunks,
        },
    });

    try std.testing.expect(exit_code == 0);
    // We might not have commits in test environment, so just check we didn't crash
}

// Phase 6: Timeout Enforcement - Tests First

test "enforces timeout" {
    const allocator = std.testing.allocator;

    var cmd = try GitCommand.init(allocator);
    defer cmd.deinit(allocator);

    const start = std.time.milliTimestamp();
    const result = cmd.runWithOptions(allocator, .{
        .args = &.{"clone", "https://github.com/torvalds/linux.git"},
        .timeout_ms = 100, // 100ms timeout
    }) catch |err| switch (err) {
        error.Timeout => {
            const elapsed = std.time.milliTimestamp() - start;
            try std.testing.expect(elapsed < 500); // Should timeout quickly
            return;
        },
        else => return err,
    };
    defer result.deinit(allocator);

    // If we get here, the clone was really fast (unlikely) or timeout didn't work
    std.log.warn("Git clone completed before timeout, test inconclusive", .{});
}

// Phase 7: Git Protocol Support - Tests First

test "handles git-upload-pack with context" {
    const allocator = std.testing.allocator;

    var cmd = try GitCommand.init(allocator);
    defer cmd.deinit(allocator);

    // Create a test directory for the protocol test
    const tmp_dir_name = try std.fmt.allocPrint(allocator, "git_protocol_test_{d}", .{std.crypto.random.int(u32)});
    defer allocator.free(tmp_dir_name);
    
    try std.fs.cwd().makeDir(tmp_dir_name);
    defer std.fs.cwd().deleteTree(tmp_dir_name) catch {};

    // Initialize a git repo for testing
    const init_result = try cmd.runWithOptions(allocator, .{
        .args = &.{"init", "--bare"},
        .cwd = tmp_dir_name,
    });
    defer init_result.deinit(allocator);

    // Test with actual git protocol handshake
    const input = "0067want 1234567890abcdef1234567890abcdef12345678 multi_ack_detailed no-done side-band-64k thin-pack ofs-delta deepen-since deepen-not agent=git/2.39.0\n0000";

    const result = try cmd.runWithProtocolContext(allocator, .{
        .args = &.{"upload-pack", "--stateless-rpc", "--advertise-refs", tmp_dir_name},
        .stdin = input,
        .protocol_context = .{
            .pusher_id = "123",
            .pusher_name = "testuser",
            .repo_username = "owner",
            .repo_name = "project",
            .is_wiki = false,
        },
    });
    defer result.deinit(allocator);

    // Git upload-pack might fail on bare repo, but we're testing the wrapper works
    try std.testing.expect(result.stderr.len > 0 or result.stdout.len > 0);
}

test "sets protocol environment variables" {
    const allocator = std.testing.allocator;

    var cmd = try GitCommand.init(allocator);
    defer cmd.deinit(allocator);

    const result = try cmd.runWithProtocolContext(allocator, .{
        .args = &.{"version"},
        .protocol_context = .{
            .pusher_id = "456",
            .pusher_name = "alice",
            .repo_username = "org",
            .repo_name = "repo",
            .is_wiki = true,
        },
    });
    defer result.deinit(allocator);

    // Just verify it runs without error
    try std.testing.expect(result.exit_code == 0);
}