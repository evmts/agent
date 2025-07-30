const std = @import("std");
const testing = std.testing;
const log = std.log.scoped(.ssh_git_protocol);

const command = @import("command.zig");
const GitCommand = @import("../git/command.zig").GitCommand;
const bindings = @import("bindings.zig");

// Git Protocol Handler for SSH Git operations
// Handles the complete Git protocol execution over SSH channels
// Integrates command parsing, access control, and git execution

pub const GitOperation = enum {
    read,   // clone, fetch, pull operations
    write,  // push operations
};

pub const AccessLevel = enum {
    allowed,
    denied,
};

pub const RepoInfo = struct {
    owner: []const u8,
    name: []const u8,
    
    pub fn deinit(self: *RepoInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.name);
    }
};

pub const GitProtocolError = error{
    InvalidCommand,
    PermissionDenied,
    RepositoryNotFound,
    InvalidRepository,
    GitExecutionFailed,
    ChannelError,
    OutOfMemory,
};

// Parse repository path like "owner/repo.git" or "owner/repo"
pub fn parseRepoPath(allocator: std.mem.Allocator, repo_path: []const u8) !RepoInfo {
    // Remove leading slash if present
    const clean_path = if (repo_path.len > 0 and repo_path[0] == '/') 
        repo_path[1..] 
    else 
        repo_path;
    
    // Find the separator
    const slash_pos = std.mem.indexOf(u8, clean_path, "/") orelse return error.InvalidRepository;
    
    if (slash_pos == 0 or slash_pos == clean_path.len - 1) {
        return error.InvalidRepository;
    }
    
    const owner = clean_path[0..slash_pos];
    var repo_name = clean_path[slash_pos + 1..];
    
    // Remove .git suffix if present
    if (std.mem.endsWith(u8, repo_name, ".git")) {
        repo_name = repo_name[0..repo_name.len - 4];
    }
    
    if (owner.len == 0 or repo_name.len == 0) {
        return error.InvalidRepository;
    }
    
    return RepoInfo{
        .owner = try allocator.dupe(u8, owner),
        .name = try allocator.dupe(u8, repo_name),
    };
}

// Mock access control for now - in production would integrate with database
pub const AccessControl = struct {
    pub fn checkAccess(
        self: *AccessControl,
        allocator: std.mem.Allocator,
        user_id: u32,
        repo_path: []const u8,
        operation: GitOperation,
    ) !AccessLevel {
        _ = self;
        _ = allocator;
        _ = user_id;
        _ = repo_path;
        _ = operation;
        
        // For now, allow all operations - in production would check database
        return .allowed;
    }
};

pub const GitProtocolHandler = struct {
    allocator: std.mem.Allocator,
    channel: *bindings.Channel,
    git_command: *GitCommand,
    access_control: *AccessControl,
    repo_base_path: []const u8,
    
    pub fn init(
        allocator: std.mem.Allocator,
        channel: *bindings.Channel,
        git_cmd: *GitCommand,
        access_control: *AccessControl,
        repo_base_path: []const u8,
    ) GitProtocolHandler {
        return GitProtocolHandler{
            .allocator = allocator,
            .channel = channel,
            .git_command = git_cmd,
            .access_control = access_control,
            .repo_base_path = repo_base_path,
        };
    }
    
    pub fn handleGitCommand(
        self: *GitProtocolHandler,
        user_id: u32,
        command_line: []const u8,
    ) !void {
        log.info("SSH Git Protocol: Handling command '{s}' for user {d}", .{ command_line, user_id });
        
        // Parse the SSH command
        const ssh_cmd = command.SshCommand.parse(self.allocator, command_line) catch |err| {
            log.err("Failed to parse SSH command '{s}': {}", .{ command_line, err });
            try self.sendError("Invalid git command");
            return GitProtocolError.InvalidCommand;
        };
        defer ssh_cmd.deinit(self.allocator);
        
        // Determine required access level
        const required_access = switch (ssh_cmd.command_type) {
            .upload_pack => GitOperation.read,
            .receive_pack => GitOperation.write,
        };
        
        // Check access permissions
        const access = self.access_control.checkAccess(
            self.allocator,
            user_id,
            ssh_cmd.repository_path,
            required_access,
        ) catch |err| {
            log.err("Access control check failed: {}", .{err});
            try self.sendError("Permission check failed");
            return GitProtocolError.PermissionDenied;
        };
        
        if (access == .denied) {
            log.warn("Access denied for user {d} to repository '{s}' (operation: {})", .{ 
                user_id, ssh_cmd.repository_path, required_access 
            });
            try self.sendError("Permission denied");
            return GitProtocolError.PermissionDenied;
        }
        
        // Get absolute repository path
        const repo_abs_path = try self.resolveRepoPath(ssh_cmd.repository_path);
        defer self.allocator.free(repo_abs_path);
        
        log.info("SSH Git Protocol: Executing {} operation on '{s}' for user {d}", .{ 
            required_access, repo_abs_path, user_id 
        });
        
        // Execute git command with SSH transport
        try self.executeGitProtocol(ssh_cmd, repo_abs_path);
    }
    
    fn resolveRepoPath(self: *GitProtocolHandler, repo_path: []const u8) ![]const u8 {
        // Parse the repo path to get owner/name
        var repo_info = parseRepoPath(self.allocator, repo_path) catch |err| {
            log.err("Failed to parse repository path '{s}': {}", .{ repo_path, err });
            return GitProtocolError.InvalidRepository;
        };
        defer repo_info.deinit(self.allocator);
        
        // Build absolute path: /var/lib/plue/repositories/owner/repo.git
        return std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}/{s}.git",
            .{ self.repo_base_path, repo_info.owner, repo_info.name }
        );
    }
    
    fn executeGitProtocol(
        self: *GitProtocolHandler,
        ssh_cmd: command.SshCommand,
        repo_path: []const u8,
    ) !void {
        // Build git command arguments
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (args.items) |arg| self.allocator.free(arg);
            args.deinit();
        }
        
        const cmd_name = switch (ssh_cmd.command_type) {
            .upload_pack => "upload-pack",
            .receive_pack => "receive-pack",
        };
        
        try args.append(try self.allocator.dupe(u8, cmd_name));
        try args.append(try self.allocator.dupe(u8, "--stateless-rpc"));
        try args.append(try self.allocator.dupe(u8, repo_path));
        
        // Set up git environment
        var env = std.ArrayList(GitCommand.EnvVar).init(self.allocator);
        defer env.deinit();
        
        try env.append(.{
            .name = "GIT_PROTOCOL",
            .value = "version=2",
        });
        
        // For now, execute the git command normally and send output to channel
        // In production, this would use streaming I/O with the SSH channel
        const result = self.git_command.runWithOptions(.{
            .args = args.items,
            .cwd = null,
            .env = env.items,
        }) catch |err| {
            log.err("Git command execution failed: {}", .{err});
            try self.sendError("Git command failed");
            return GitProtocolError.GitExecutionFailed;
        };
        
        // Send stdout to SSH channel
        if (result.stdout.len > 0) {
            _ = self.channel.write(result.stdout) catch |err| {
                log.err("Failed to write stdout to SSH channel: {}", .{err});
                return GitProtocolError.ChannelError;
            };
        }
        
        // Send stderr to SSH channel if there are errors
        if (result.stderr.len > 0) {
            _ = self.channel.write(result.stderr) catch |err| {
                log.err("Failed to write stderr to SSH channel: {}", .{err});
                // Don't return error here, stderr is informational
            };
        }
        
        // Send exit status
        try self.sendExitStatus(result.exit_code);
        
        log.info("SSH Git Protocol: Command completed with exit code {d}", .{result.exit_code});
    }
    
    fn sendError(self: *GitProtocolHandler, message: []const u8) !void {
        const error_msg = try std.fmt.allocPrint(self.allocator, "fatal: {s}\n", .{message});
        defer self.allocator.free(error_msg);
        
        _ = self.channel.write(error_msg) catch |err| {
            log.err("Failed to send error message to SSH channel: {}", .{err});
        };
    }
    
    fn sendExitStatus(self: *GitProtocolHandler, exit_code: u8) !void {
        // This would be implemented by the SSH channel to send proper exit status
        // For now, just close the channel if the command failed
        if (exit_code != 0) {
            log.warn("SSH Git Protocol: Command failed with exit code {d}", .{exit_code});
        }
        
        // Close the channel after command completion
        self.channel.close();
    }
};

// Tests
test "parses repository path correctly" {
    const allocator = testing.allocator;
    
    // Test standard format
    {
        var repo_info = try parseRepoPath(allocator, "owner/repo.git");
        defer repo_info.deinit(allocator);
        
        try testing.expectEqualStrings("owner", repo_info.owner);
        try testing.expectEqualStrings("repo", repo_info.name);
    }
    
    // Test without .git suffix
    {
        var repo_info = try parseRepoPath(allocator, "owner/repo");
        defer repo_info.deinit(allocator);
        
        try testing.expectEqualStrings("owner", repo_info.owner);
        try testing.expectEqualStrings("repo", repo_info.name);
    }
    
    // Test with leading slash
    {
        var repo_info = try parseRepoPath(allocator, "/owner/repo.git");
        defer repo_info.deinit(allocator);
        
        try testing.expectEqualStrings("owner", repo_info.owner);
        try testing.expectEqualStrings("repo", repo_info.name);
    }
}

test "rejects invalid repository paths" {
    const allocator = testing.allocator;
    
    try testing.expectError(error.InvalidRepository, parseRepoPath(allocator, ""));
    try testing.expectError(error.InvalidRepository, parseRepoPath(allocator, "/"));
    try testing.expectError(error.InvalidRepository, parseRepoPath(allocator, "no-slash"));
    try testing.expectError(error.InvalidRepository, parseRepoPath(allocator, "/owner/"));
    try testing.expectError(error.InvalidRepository, parseRepoPath(allocator, "owner/"));
}

test "access control allows operations" {
    const allocator = testing.allocator;
    
    var access_control = AccessControl{};
    
    const read_access = try access_control.checkAccess(
        allocator,
        123,
        "owner/repo.git",
        .read,
    );
    try testing.expectEqual(AccessLevel.allowed, read_access);
    
    const write_access = try access_control.checkAccess(
        allocator,
        123,
        "owner/repo.git",
        .write,
    );
    try testing.expectEqual(AccessLevel.allowed, write_access);
}