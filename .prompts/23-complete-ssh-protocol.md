# Complete SSH Git Protocol Implementation

## Issue Found

The SSH server implementation (Prompt 8) only completed the infrastructure layer but never implemented the actual Git protocol handling. The SSH server can accept connections but cannot execute Git commands.

## Current State vs Required

**What exists**:
- ✅ SSH server infrastructure
- ✅ Authentication system
- ✅ Channel handling
- ✅ Public key management
- ❌ Git protocol execution
- ❌ Command parsing and validation
- ❌ Repository access control
- ❌ Git command execution

**Evidence from Review**:
```zig
// src/ssh/server.zig - handleExecRequest
pub fn handleExecRequest(self: *SshConnection, allocator: std.mem.Allocator, command: []const u8) !void {
    // TODO: Parse git commands and execute them
    // For now, just echo back
    try self.channel.write(allocator, command);
}
```

## Complete Implementation Requirements

### Git Command Parser

```zig
const GitSshCommand = struct {
    command_type: CommandType,
    repository_path: []const u8,
    extra_args: []const []const u8,
    
    const CommandType = enum {
        git_upload_pack,    // git clone/fetch
        git_receive_pack,   // git push
        git_upload_archive, // git archive
        invalid,
    };
    
    pub fn parse(allocator: std.mem.Allocator, command: []const u8) !GitSshCommand {
        // Parse commands like:
        // git-upload-pack '/user/repo.git'
        // git receive-pack '/org/repo.git'
        // git upload-archive '/user/repo.git'
        
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();
        
        var iter = std.mem.tokenize(u8, command, " ");
        while (iter.next()) |part| {
            // Handle quoted arguments properly
            const cleaned = try parseQuotedArg(allocator, part);
            try parts.append(cleaned);
        }
        
        if (parts.items.len < 2) return error.InvalidCommand;
        
        const cmd_type = parseCommandType(parts.items[0]);
        if (cmd_type == .invalid) return error.InvalidGitCommand;
        
        return GitSshCommand{
            .command_type = cmd_type,
            .repository_path = try cleanRepoPath(allocator, parts.items[1]),
            .extra_args = parts.items[2..],
        };
    }
};
```

### Repository Access Control

```zig
const AccessControl = struct {
    db: *DatabaseConnection,
    
    pub fn checkAccess(
        self: *AccessControl,
        allocator: std.mem.Allocator,
        user_id: u32,
        repo_path: []const u8,
        operation: GitOperation,
    ) !AccessLevel {
        // Parse owner/repo from path
        const repo_info = try parseRepoPath(allocator, repo_path);
        defer repo_info.deinit();
        
        // Look up repository in database
        const repo = try self.db.getRepositoryByPath(
            allocator,
            repo_info.owner,
            repo_info.name,
        ) orelse return error.RepositoryNotFound;
        defer repo.deinit();
        
        // Check user permissions
        const perm = try self.db.getUserRepositoryPermission(
            allocator,
            user_id,
            repo.id,
        );
        
        return switch (operation) {
            .read => if (perm >= .read) .allowed else .denied,
            .write => if (perm >= .write) .allowed else .denied,
        };
    }
};
```

### Git Protocol Handler

```zig
const GitProtocolHandler = struct {
    allocator: std.mem.Allocator,
    connection: *SshConnection,
    git_command: *GitCommand,
    access_control: *AccessControl,
    
    pub fn handleGitCommand(
        self: *GitProtocolHandler,
        user_id: u32,
        command: []const u8,
    ) !void {
        // Parse the SSH command
        const git_cmd = try GitSshCommand.parse(self.allocator, command);
        defer git_cmd.deinit();
        
        // Determine required access level
        const required_access = switch (git_cmd.command_type) {
            .git_upload_pack, .git_upload_archive => GitOperation.read,
            .git_receive_pack => GitOperation.write,
            .invalid => return error.InvalidCommand,
        };
        
        // Check access permissions
        const access = try self.access_control.checkAccess(
            self.allocator,
            user_id,
            git_cmd.repository_path,
            required_access,
        );
        
        if (access == .denied) {
            try self.connection.sendError("Permission denied");
            return error.PermissionDenied;
        }
        
        // Get absolute repository path
        const repo_abs_path = try self.resolveRepoPath(git_cmd.repository_path);
        defer self.allocator.free(repo_abs_path);
        
        // Execute git command with SSH transport
        try self.executeGitProtocol(git_cmd, repo_abs_path);
    }
    
    fn executeGitProtocol(
        self: *GitProtocolHandler,
        git_cmd: GitSshCommand,
        repo_path: []const u8,
    ) !void {
        // Build git command arguments
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        
        const cmd_name = switch (git_cmd.command_type) {
            .git_upload_pack => "upload-pack",
            .git_receive_pack => "receive-pack",
            .git_upload_archive => "upload-archive",
            .invalid => unreachable,
        };
        
        try args.append(cmd_name);
        try args.append("--stateless-rpc");
        try args.append(repo_path);
        try args.appendSlice(git_cmd.extra_args);
        
        // Set up git environment
        var env = std.ArrayList(GitCommand.EnvVar).init(self.allocator);
        defer env.deinit();
        
        try env.append(.{
            .name = "GIT_PROTOCOL",
            .value = "version=2",
        });
        
        // Stream git process I/O through SSH channel
        try self.streamGitCommand(args.items, env.items);
    }
    
    fn streamGitCommand(
        self: *GitProtocolHandler,
        args: []const []const u8,
        env: []const GitCommand.EnvVar,
    ) !void {
        var stdout_buf: [8192]u8 = undefined;
        var stderr_buf: [1024]u8 = undefined;
        
        const exit_code = try self.git_command.runStreaming(.{
            .allocator = self.allocator,
            .args = args,
            .env = env,
            .stdin_callback = struct {
                conn: *SshConnection,
                fn callback(ctx: *anyopaque, buffer: []u8) !usize {
                    const connection = @as(*SshConnection, @ptrCast(ctx));
                    return connection.channel.read(buffer);
                }
            }{ .conn = self.connection }.callback,
            .stdout_callback = struct {
                conn: *SshConnection,
                fn callback(ctx: *anyopaque, data: []const u8) !void {
                    const connection = @as(*SshConnection, @ptrCast(ctx));
                    try connection.channel.write(data);
                }
            }{ .conn = self.connection }.callback,
            .context = self.connection,
        });
        
        // Send exit status
        try self.connection.sendExitStatus(exit_code);
    }
};
```

### Updated SSH Server Integration

```zig
// In src/ssh/server.zig
pub fn handleExecRequest(
    self: *SshConnection,
    allocator: std.mem.Allocator,
    command: []const u8,
) !void {
    log.info("SSH exec request from user {}: {s}", .{ self.user_id, command });
    
    // Create protocol handler
    var handler = GitProtocolHandler{
        .allocator = allocator,
        .connection = self,
        .git_command = self.server.git_command,
        .access_control = self.server.access_control,
    };
    
    // Handle the git command
    handler.handleGitCommand(self.user_id.?, command) catch |err| {
        log.err("Git command failed: {}", .{err});
        try self.sendError("Git command failed");
        try self.sendExitStatus(1);
        return;
    };
    
    // Close the channel after command completes
    try self.channel.close();
}
```

## Implementation Steps

### Phase 1: Command Parsing and Validation
1. Implement `GitSshCommand` parser with tests
2. Handle all Git SSH command formats
3. Properly parse quoted arguments
4. Validate repository paths

### Phase 2: Access Control Integration
1. Implement repository path parsing
2. Database lookups for permissions
3. User authentication state
4. Permission caching for performance

### Phase 3: Git Protocol Execution
1. Integrate with existing GitCommand
2. Implement streaming I/O callbacks
3. Handle Git protocol negotiation
4. Error handling and logging

### Phase 4: Testing and Production Features
1. End-to-end SSH git operations
2. Concurrent connection handling
3. Resource limits and timeouts
4. Audit logging

## Test Requirements

```zig
test "handles git-upload-pack via SSH" {
    // Set up test repo and SSH server
    var server = try createTestSshServer(allocator);
    defer server.deinit();
    
    const repo_path = try createTestRepo(allocator, "test-repo");
    defer cleanupTestRepo(repo_path);
    
    // Connect via SSH
    var client = try SshClient.connect(allocator, server.address);
    defer client.deinit();
    
    // Execute git-upload-pack
    const result = try client.exec("git-upload-pack '/test/test-repo.git'");
    defer result.deinit();
    
    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}

test "denies access to unauthorized repositories" {
    var server = try createTestSshServer(allocator);
    defer server.deinit();
    
    var client = try connectAsUser(allocator, server, "limited_user");
    defer client.deinit();
    
    const result = try client.exec("git-upload-pack '/private/repo.git'");
    defer result.deinit();
    
    try testing.expect(result.exit_code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Permission denied") != null);
}
```

## Security Considerations

1. **Command Injection**: Strictly parse and validate all commands
2. **Path Traversal**: Ensure repository paths are canonical
3. **Resource Limits**: Limit concurrent operations per user
4. **Audit Trail**: Log all Git operations with user/repo/timestamp
5. **Rate Limiting**: Prevent brute force and DoS attacks

## Priority: HIGH

Without this, the SSH server is non-functional for Git operations. This blocks:
- Git clone via SSH
- Git push via SSH  
- Private repository access
- Secure Git operations

## Estimated Effort: 5-7 days