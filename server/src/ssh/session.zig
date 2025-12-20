/// SSH Session Handler for Git operations
/// Handles git-upload-pack (clone/fetch) and git-receive-pack (push)
const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.ssh_session);

/// Git command execution result
pub const ExecResult = struct {
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,

    pub fn deinit(self: *ExecResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

/// Repositories directory (configurable via env)
const REPOS_DIR = std.posix.getenv("PLUE_REPOS_DIR") orelse "repos";

/// Execute a git command for SSH git operations
pub fn executeGitCommand(
    allocator: std.mem.Allocator,
    command: types.GitCommand,
    stdin_data: []const u8,
) !ExecResult {
    const repo_path = try getRepoPath(allocator, command.user, command.repo);
    defer allocator.free(repo_path);

    // Verify repository exists
    const stat_result = std.fs.cwd().statFile(repo_path) catch |err| {
        log.err("Repository not found: {s} (error: {})", .{ repo_path, err });
        return error.RepositoryNotFound;
    };
    if (stat_result.kind != .directory) {
        return error.NotADirectory;
    }

    // Verify .git directory exists (for colocated jj repos)
    const git_dir = try std.fs.path.join(allocator, &.{ repo_path, ".git" });
    defer allocator.free(git_dir);

    std.fs.cwd().access(git_dir, .{}) catch |err| {
        log.err("Git directory not found: {s} (error: {})", .{ git_dir, err });
        return error.GitDirectoryNotFound;
    };

    // Determine git command
    const git_cmd = switch (command.command) {
        .git_upload_pack => "git-upload-pack",
        .git_receive_pack => "git-receive-pack",
    };

    log.info("Executing: {s} {s}", .{ git_cmd, repo_path });

    // Execute git command
    var child = std.process.Child.init(&.{ git_cmd, repo_path }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Write stdin data
    if (stdin_data.len > 0) {
        try child.stdin.?.writeAll(stdin_data);
    }
    child.stdin.?.close();
    child.stdin = null;

    // Read stdout and stderr
    const stdout = try child.stdout.?.readToEndAlloc(allocator, 100 * 1024 * 1024); // 100MB max
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max

    // Wait for completion
    const term = try child.wait();

    const exit_code: u8 = switch (term) {
        .Exited => |code| @intCast(code),
        .Signal => 128,
        .Stopped => 128,
        .Unknown => 128,
    };

    log.info("Command completed with exit code: {d}", .{exit_code});

    // If this was a push (git-receive-pack) and succeeded, trigger jj sync
    if (command.command == .git_receive_pack and exit_code == 0) {
        log.info("Push successful, triggering jj sync for {s}/{s}", .{ command.user, command.repo });

        // Trigger sync by making HTTP request to internal sync endpoint
        triggerJjSync(allocator, command.user, command.repo) catch |err| {
            // Log error but don't fail the push
            log.err("Failed to trigger jj sync for {s}/{s}: {}", .{ command.user, command.repo, err });
        };
    }

    return ExecResult{
        .exit_code = exit_code,
        .stdout = stdout,
        .stderr = stderr,
    };
}

/// Get full path to a repository
fn getRepoPath(allocator: std.mem.Allocator, user: []const u8, repo: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ REPOS_DIR, user, repo });
}

/// Trigger jj sync to database after successful push
/// Makes HTTP POST request to internal sync endpoint
fn triggerJjSync(allocator: std.mem.Allocator, user: []const u8, repo: []const u8) !void {
    // Get API URL from environment, default to localhost
    const api_url = std.posix.getenv("PLUE_API_URL") orelse "http://localhost:8080";

    // Build URL: POST /api/watcher/sync/:user/:repo
    const url = try std.fmt.allocPrint(allocator, "{s}/api/watcher/sync/{s}/{s}", .{ api_url, user, repo });
    defer allocator.free(url);

    log.debug("Triggering jj sync via: {s}", .{url});

    // Use curl for simplicity (available in most environments)
    // In production, consider using a proper HTTP client library
    var child = std.process.Child.init(&.{
        "curl",
        "-X",
        "POST",
        "-s", // Silent mode
        "-f", // Fail silently on HTTP errors
        "-m",
        "5", // 5 second timeout
        url,
    }, allocator);

    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read and discard output
    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(stdout);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(stderr);

    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                log.warn("Sync trigger failed with exit code {d}: {s}", .{ code, stderr });
                return error.SyncTriggerFailed;
            }
            log.debug("Sync triggered successfully: {s}", .{stdout});
        },
        else => {
            log.warn("Sync trigger terminated abnormally", .{});
            return error.SyncTriggerFailed;
        },
    }
}

/// Validate that the authenticated user has access to the repository
pub fn validateAccess(
    allocator: std.mem.Allocator,
    pool: anytype,
    user_id: i64,
    repo_owner: []const u8,
    repo_name: []const u8,
    is_write: bool,
) !bool {
    _ = allocator;
    // Get a connection from the pool
    var conn = try pool.acquire();
    defer conn.release();

    // Check if repository exists and user has access
    const query = if (is_write)
        \\SELECT r.id FROM repositories r
        \\JOIN users u ON r.owner_id = u.id
        \\WHERE u.username = $1 AND r.name = $2
        \\  AND (r.owner_id = $3 OR EXISTS (
        \\    SELECT 1 FROM collaborators c
        \\    WHERE c.repo_id = r.id AND c.user_id = $3
        \\      AND (c.permission = 'write' OR c.permission = 'admin')
        \\  ))
    else
        \\SELECT r.id FROM repositories r
        \\JOIN users u ON r.owner_id = u.id
        \\WHERE u.username = $1 AND r.name = $2
        \\  AND (r.is_private = false OR r.owner_id = $3 OR EXISTS (
        \\    SELECT 1 FROM collaborators c
        \\    WHERE c.repo_id = r.id AND c.user_id = $3
        \\  ))
    ;

    var result = try conn.query(query, .{ repo_owner, repo_name, user_id });
    defer result.deinit();

    return (try result.next()) != null;
}

/// Channel handler for SSH exec requests
pub const ChannelHandler = struct {
    channel: types.Channel,
    auth_user: ?types.AuthUser,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, channel: types.Channel) ChannelHandler {
        return .{
            .channel = channel,
            .auth_user = null,
            .allocator = allocator,
        };
    }

    pub fn handleExecRequest(
        self: *ChannelHandler,
        pool: anytype,
        command_str: []const u8,
    ) !ExecResult {
        // Parse command
        var command = try types.GitCommand.parse(self.allocator, command_str);
        defer command.deinit(self.allocator);

        log.info("Exec request: {s} {s}/{s}", .{ @tagName(command.command), command.user, command.repo });

        // Check access
        if (self.auth_user) |user| {
            const is_write = command.command == .git_receive_pack;
            const has_access = try validateAccess(
                self.allocator,
                pool,
                user.user_id,
                command.user,
                command.repo,
                is_write,
            );

            if (!has_access) {
                log.warn("Access denied: user_id={d} to {s}/{s}", .{ user.user_id, command.user, command.repo });
                return error.AccessDenied;
            }
        } else {
            log.warn("No authenticated user for exec request", .{});
            return error.NotAuthenticated;
        }

        // Execute command (stdin will be read from SSH channel in real implementation)
        const stdin_data: []const u8 = &.{};
        return executeGitCommand(self.allocator, command, stdin_data);
    }
};

test "getRepoPath" {
    const allocator = std.testing.allocator;

    const path = try getRepoPath(allocator, "alice", "myrepo");
    defer allocator.free(path);

    try std.testing.expect(std.mem.endsWith(u8, path, "alice/myrepo") or
        std.mem.endsWith(u8, path, "alice\\myrepo")); // Windows uses backslash
}
