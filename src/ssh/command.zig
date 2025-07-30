const std = @import("std");
const testing = std.testing;
const log = std.log.scoped(.ssh_command);
const git_command = @import("../git/command.zig");

// SSH Command Parser for Git operations over SSH
// Handles parsing and validation of SSH commands like "git-upload-pack", "git-receive-pack"

// Phase 1: Core Command Types and Validation - Tests First

test "parses git-upload-pack command" {
    const allocator = testing.allocator;
    
    const cmd = try SshCommand.parse(allocator, "git-upload-pack '/path/to/repo.git'");
    defer cmd.deinit(allocator);
    
    try testing.expectEqual(CommandType.upload_pack, cmd.command_type);
    try testing.expectEqualStrings("/path/to/repo.git", cmd.repository_path);
}

test "parses git-receive-pack command" {
    const allocator = testing.allocator;
    
    const cmd = try SshCommand.parse(allocator, "git-receive-pack '/path/to/repo.git'");
    defer cmd.deinit(allocator);
    
    try testing.expectEqual(CommandType.receive_pack, cmd.command_type);
    try testing.expectEqualStrings("/path/to/repo.git", cmd.repository_path);
}

test "rejects invalid SSH commands" {
    const allocator = testing.allocator;
    
    try testing.expectError(SshCommandError.InvalidCommand, 
        SshCommand.parse(allocator, "rm -rf /"));
    try testing.expectError(SshCommandError.InvalidCommand, 
        SshCommand.parse(allocator, "ls -la"));
    try testing.expectError(SshCommandError.InvalidCommand, 
        SshCommand.parse(allocator, "bash"));
}

test "validates repository path format" {
    const allocator = testing.allocator;
    
    // Valid paths
    {
        const cmd1 = try SshCommand.parse(allocator, "git-upload-pack 'owner/repo.git'");
        defer cmd1.deinit(allocator);
    }
    {
        const cmd2 = try SshCommand.parse(allocator, "git-upload-pack 'org/project.git'");
        defer cmd2.deinit(allocator);
    }
    
    // Invalid paths
    try testing.expectError(SshCommandError.InvalidRepository, 
        SshCommand.parse(allocator, "git-upload-pack '../../../etc/passwd'"));
    try testing.expectError(SshCommandError.InvalidRepository, 
        SshCommand.parse(allocator, "git-upload-pack '/absolute/path'"));
}

test "handles quoted and unquoted paths" {
    const allocator = testing.allocator;
    
    // Quoted path
    const cmd1 = try SshCommand.parse(allocator, "git-upload-pack 'owner/repo.git'");
    defer cmd1.deinit(allocator);
    try testing.expectEqualStrings("owner/repo.git", cmd1.repository_path);
    
    // Double quoted path
    const cmd2 = try SshCommand.parse(allocator, "git-upload-pack \"owner/repo.git\"");
    defer cmd2.deinit(allocator);
    try testing.expectEqualStrings("owner/repo.git", cmd2.repository_path);
    
    // Unquoted path (should still work)
    const cmd3 = try SshCommand.parse(allocator, "git-upload-pack owner/repo.git");
    defer cmd3.deinit(allocator);
    try testing.expectEqualStrings("owner/repo.git", cmd3.repository_path);
}

// Now implement the types and functions to make tests pass

pub const CommandType = enum {
    upload_pack,    // git-upload-pack (read access - clone, fetch, pull)
    receive_pack,   // git-receive-pack (write access - push)
    
    pub fn toString(self: CommandType) []const u8 {
        return switch (self) {
            .upload_pack => "git-upload-pack",
            .receive_pack => "git-receive-pack",
        };
    }
    
    pub fn isWriteOperation(self: CommandType) bool {
        return switch (self) {
            .upload_pack => false,
            .receive_pack => true,
        };
    }
};

pub const SshCommandError = error{
    InvalidCommand,
    InvalidRepository,
    PathTooLong,
    MissingRepository,
    CommandNotAllowed,
    OutOfMemory,
};

pub const SshCommand = struct {
    command_type: CommandType,
    repository_path: []const u8,
    
    pub fn parse(allocator: std.mem.Allocator, command_line: []const u8) SshCommandError!SshCommand {
        const trimmed = std.mem.trim(u8, command_line, " \t\n\r");
        if (trimmed.len == 0) return error.InvalidCommand;
        
        // Split command and arguments
        var parts = std.mem.tokenizeScalar(u8, trimmed, ' ');
        const command = parts.next() orelse return error.InvalidCommand;
        
        // Parse command type
        const command_type = if (std.mem.eql(u8, command, "git-upload-pack"))
            CommandType.upload_pack
        else if (std.mem.eql(u8, command, "git-receive-pack"))
            CommandType.receive_pack
        else
            return error.InvalidCommand;
        
        // Get repository path
        const raw_path = parts.rest();
        if (raw_path.len == 0) return error.MissingRepository;
        
        // Remove quotes if present
        const repository_path = blk: {
            const trimmed_path = std.mem.trim(u8, raw_path, " \t");
            if (trimmed_path.len >= 2) {
                if ((trimmed_path[0] == '\'' and trimmed_path[trimmed_path.len - 1] == '\'') or
                    (trimmed_path[0] == '"' and trimmed_path[trimmed_path.len - 1] == '"')) {
                    break :blk trimmed_path[1..trimmed_path.len - 1];
                }
            }
            break :blk trimmed_path;
        };
        
        // Validate repository path
        try validateRepositoryPath(repository_path);
        
        // Allocate and copy repository path
        const owned_path = try allocator.dupe(u8, repository_path);
        
        return SshCommand{
            .command_type = command_type,
            .repository_path = owned_path,
        };
    }
    
    pub fn deinit(self: *const SshCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.repository_path);
    }
    
    pub fn toGitArgs(self: *const SshCommand, allocator: std.mem.Allocator) ![][]const u8 {
        var args = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (args.items) |arg| allocator.free(arg);
            args.deinit();
        }
        
        // Convert SSH command to git command arguments
        switch (self.command_type) {
            .upload_pack => {
                try args.append(try allocator.dupe(u8, "upload-pack"));
                try args.append(try allocator.dupe(u8, "--strict"));
                try args.append(try allocator.dupe(u8, "--timeout=300"));
                try args.append(try allocator.dupe(u8, self.repository_path));
            },
            .receive_pack => {
                try args.append(try allocator.dupe(u8, "receive-pack"));
                try args.append(try allocator.dupe(u8, "--strict"));
                try args.append(try allocator.dupe(u8, "--atomic"));
                try args.append(try allocator.dupe(u8, self.repository_path));
            },
        }
        
        return args.toOwnedSlice();
    }
};

fn validateRepositoryPath(path: []const u8) SshCommandError!void {
    if (path.len == 0) return error.InvalidRepository;
    if (path.len > 1024) return error.PathTooLong;
    
    // Check for directory traversal
    if (std.mem.indexOf(u8, path, "..") != null) {
        return error.InvalidRepository;
    }
    
    // Check for absolute paths (should be relative to repo base)
    if (path.len > 0 and path[0] == '/') {
        return error.InvalidRepository;
    }
    
    // Check for suspicious characters
    for (path) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '/', '.', '-', '_' => {},
            else => return error.InvalidRepository,
        }
    }
}

// Phase 2: Command Execution Integration - Tests First

test "converts SSH command to git arguments" {
    const allocator = testing.allocator;
    
    const cmd = try SshCommand.parse(allocator, "git-upload-pack 'owner/repo.git'");
    defer cmd.deinit(allocator);
    
    const args = try cmd.toGitArgs(allocator);
    defer {
        for (args) |arg| allocator.free(arg);
        allocator.free(args);
    }
    
    try testing.expect(args.len >= 2);
    try testing.expectEqualStrings("upload-pack", args[0]);
    try testing.expectEqualStrings("owner/repo.git", args[args.len - 1]);
}

test "adds security flags to git commands" {
    const allocator = testing.allocator;
    
    const upload_cmd = try SshCommand.parse(allocator, "git-upload-pack 'repo.git'");
    defer upload_cmd.deinit(allocator);
    
    const upload_args = try upload_cmd.toGitArgs(allocator);
    defer {
        for (upload_args) |arg| allocator.free(arg);
        allocator.free(upload_args);
    }
    
    // Should include --strict flag
    var has_strict = false;
    for (upload_args) |arg| {
        if (std.mem.eql(u8, arg, "--strict")) {
            has_strict = true;
            break;
        }
    }
    try testing.expect(has_strict);
    
    const receive_cmd = try SshCommand.parse(allocator, "git-receive-pack 'repo.git'");
    defer receive_cmd.deinit(allocator);
    
    const receive_args = try receive_cmd.toGitArgs(allocator);
    defer {
        for (receive_args) |arg| allocator.free(arg);
        allocator.free(receive_args);
    }
    
    // Should include --atomic flag for receive-pack
    var has_atomic = false;
    for (receive_args) |arg| {
        if (std.mem.eql(u8, arg, "--atomic")) {
            has_atomic = true;
            break;
        }
    }
    try testing.expect(has_atomic);
}

// Phase 3: Command Context and Security - Tests First

test "creates command context with user info" {
    const context = CommandContext{
        .user_id = 123,
        .username = "testuser",
        .key_id = "key_456",
        .repository_owner = "owner",
        .repository_name = "repo",
        .is_write_operation = false,
        .client_ip = "192.168.1.100",
    };
    
    try testing.expectEqual(@as(u32, 123), context.user_id);
    try testing.expectEqualStrings("testuser", context.username);
    try testing.expect(!context.is_write_operation);
}

test "validates write operation permissions" {
    const allocator = testing.allocator;
    
    const upload_cmd = try SshCommand.parse(allocator, "git-upload-pack 'repo.git'");
    defer upload_cmd.deinit(allocator);
    
    const receive_cmd = try SshCommand.parse(allocator, "git-receive-pack 'repo.git'");
    defer receive_cmd.deinit(allocator);
    
    try testing.expect(!upload_cmd.command_type.isWriteOperation());
    try testing.expect(receive_cmd.command_type.isWriteOperation());
}

pub const CommandContext = struct {
    user_id: u32,
    username: []const u8,
    key_id: []const u8,
    repository_owner: []const u8,
    repository_name: []const u8,
    is_write_operation: bool,
    client_ip: []const u8,
    
    pub fn fromSshCommand(self: *const SshCommand, user_id: u32, username: []const u8, key_id: []const u8, client_ip: []const u8) !CommandContext {
        // Parse repository path to extract owner/name
        var repo_parts = std.mem.tokenizeScalar(u8, self.repository_path, '/');
        const owner = repo_parts.next() orelse return error.InvalidRepository;
        const repo_name_with_ext = repo_parts.next() orelse return error.InvalidRepository;
        
        // Remove .git extension if present
        const repo_name = if (std.mem.endsWith(u8, repo_name_with_ext, ".git"))
            repo_name_with_ext[0..repo_name_with_ext.len - 4]
        else
            repo_name_with_ext;
        
        return CommandContext{
            .user_id = user_id,
            .username = username,
            .key_id = key_id,
            .repository_owner = owner,
            .repository_name = repo_name,
            .is_write_operation = self.command_type.isWriteOperation(),
            .client_ip = client_ip,
        };
    }
};

// Phase 4: Command Execution with Git Integration - Tests First

test "executes git command through SSH interface" {
    const allocator = testing.allocator;
    
    const cmd = try SshCommand.parse(allocator, "git-upload-pack 'test/repo.git'");
    defer cmd.deinit(allocator);
    
    const context = CommandContext{
        .user_id = 123,
        .username = "testuser",
        .key_id = "key_456",
        .repository_owner = "test",
        .repository_name = "repo",
        .is_write_operation = false,
        .client_ip = "127.0.0.1",
    };
    
    var executor = try SshCommandExecutor.init(allocator);
    defer executor.deinit(allocator);
    
    // This should fail gracefully since the repo doesn't exist
    const result = executor.execute(allocator, cmd, context, null) catch |err| switch (err) {
        error.GitNotFound => {
            log.warn("Git not available for testing, skipping", .{});
            return;
        },
        error.ProcessFailed => {
            // Expected - repo doesn't exist
            return;
        },
        else => return err,
    };
    defer result.deinit(allocator);
}

pub const SshCommandExecutor = struct {
    git_cmd: git_command.GitCommand,
    
    pub fn init(allocator: std.mem.Allocator) !SshCommandExecutor {
        return SshCommandExecutor{
            .git_cmd = try git_command.GitCommand.init(allocator, "/usr/bin/git"), // Temporary hardcoded path
        };
    }
    
    pub fn deinit(self: *SshCommandExecutor, allocator: std.mem.Allocator) void {
        self.git_cmd.deinit(allocator);
    }
    
    pub fn execute(
        self: *const SshCommandExecutor,
        allocator: std.mem.Allocator,
        ssh_cmd: SshCommand,
        context: CommandContext,
        stdin_data: ?[]const u8,
    ) !git_command.GitResult {
        // Convert SSH command to git arguments
        const git_args = try ssh_cmd.toGitArgs(allocator);
        defer {
            for (git_args) |arg| allocator.free(arg);
            allocator.free(git_args);
        }
        
        // Create protocol context for git execution
        const protocol_context = git_command.GitCommand.ProtocolContext{
            .pusher_id = try std.fmt.allocPrint(allocator, "{d}", .{context.user_id}),
            .pusher_name = context.username,
            .repo_username = context.repository_owner,
            .repo_name = context.repository_name,
            .is_wiki = false, // SSH doesn't support wiki operations
            .key_id = context.key_id,
        };
        defer allocator.free(protocol_context.pusher_id);
        
        log.info("SSH: User {s} ({d}) executing '{s}' on repository '{s}/{s}'", .{
            context.username, context.user_id, ssh_cmd.command_type.toString(),
            context.repository_owner, context.repository_name
        });
        
        // Log security event for write operations
        if (context.is_write_operation) {
            log.info("SSH Security Event: WRITE_ACCESS from {s} - User {s} pushing to {s}/{s}", .{
                context.client_ip, context.username, context.repository_owner, context.repository_name
            });
        }
        
        // Execute git command with protocol context
        return self.git_cmd.runWithProtocolContext(allocator, .{
            .args = git_args,
            .stdin = stdin_data,
            .protocol_context = protocol_context,
            .timeout_ms = if (context.is_write_operation) 600000 else 300000, // 10min for push, 5min for fetch
        });
    }
};

// Phase 5: Error Handling and Logging - Tests First

test "logs command execution attempts" {
    const allocator = testing.allocator;
    
    const cmd = try SshCommand.parse(allocator, "git-receive-pack 'owner/repo.git'");
    defer cmd.deinit(allocator);
    
    const context = try CommandContext.fromSshCommand(&cmd, 789, "alice", "key_123", "10.0.0.1");
    
    // Should not crash when logging
    log.info("Test log: SSH command {s} from user {s}", .{cmd.command_type.toString(), context.username});
}

test "handles malformed command gracefully" {
    const allocator = testing.allocator;
    
    const malformed_commands = [_][]const u8{
        "",
        "   ",
        "git-upload-pack",
        "git-upload-pack ''",
        "not-a-git-command 'repo.git'",
        "git-upload-pack '../../../etc/passwd'",
    };
    
    for (malformed_commands) |malformed| {
        const result = SshCommand.parse(allocator, malformed);
        try testing.expect(std.meta.isError(result));
    }
}

pub const SshCommandResult = struct {
    success: bool,
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
    command_type: CommandType,
    execution_time_ms: u64,
    
    pub fn deinit(self: *const SshCommandResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

pub fn executeWithLogging(
    allocator: std.mem.Allocator,
    executor: *const SshCommandExecutor,
    ssh_cmd: SshCommand,
    context: CommandContext,
    stdin_data: ?[]const u8,
) !SshCommandResult {
    const start_time = std.time.milliTimestamp();
    
    log.info("SSH: Starting {s} command for user {s} on {s}/{s}", .{
        ssh_cmd.command_type.toString(),
        context.username,
        context.repository_owner,
        context.repository_name,
    });
    
    const result = executor.execute(allocator, ssh_cmd, context, stdin_data) catch |err| {
        const end_time = std.time.milliTimestamp();
        log.err("SSH: Command {s} failed for user {s}: {}", .{
            ssh_cmd.command_type.toString(),
            context.username,
            err,
        });
        
        return SshCommandResult{
            .success = false,
            .exit_code = 255,
            .stdout = try allocator.dupe(u8, ""),
            .stderr = try std.fmt.allocPrint(allocator, "Command failed: {}", .{err}),
            .command_type = ssh_cmd.command_type,
            .execution_time_ms = @intCast(end_time - start_time),
        };
    };
    
    const end_time = std.time.milliTimestamp();
    const execution_time = @as(u64, @intCast(end_time - start_time));
    
    log.info("SSH: Command {s} completed for user {s} in {}ms (exit: {})", .{
        ssh_cmd.command_type.toString(),
        context.username,
        execution_time,
        result.exit_code,
    });
    
    // Log security events
    if (context.is_write_operation and result.exit_code == 0) {
        log.info("SSH Security Event: SUCCESSFUL_PUSH from {s} - User {s} successfully pushed to {s}/{s}", .{
            context.client_ip, context.username, context.repository_owner, context.repository_name
        });
    } else if (result.exit_code != 0) {
        log.warn("SSH: User {s} ({d}) failed to execute '{s}' on repository '{s}/{s}' (exit: {})", .{
            context.username, context.user_id, ssh_cmd.command_type.toString(),
            context.repository_owner, context.repository_name, result.exit_code
        });
    }
    
    return SshCommandResult{
        .success = result.exit_code == 0,
        .exit_code = result.exit_code,
        .stdout = result.stdout,
        .stderr = result.stderr,
        .command_type = ssh_cmd.command_type,
        .execution_time_ms = execution_time,
    };
}