# Implement Secure Git Command Execution Wrapper

## Task Definition

Create a secure, high-performance Git command execution wrapper in Zig that provides a safe interface for running Git operations. This wrapper will be the foundation for all Git functionality in Plue, supporting both local operations and Git smart HTTP protocol for remote operations.

## Context & Constraints

### Technical Requirements

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: None (uses only Zig standard library)
- **Performance**: Must handle streaming I/O efficiently for large repositories
- **Compatibility**: Must work in Docker containers (Alpine Linux) and native environments
- **Security**: Zero tolerance for command injection vulnerabilities

### Business Context

Plue is a Git wrapper application that needs to execute Git commands securely and efficiently. This wrapper will be used by:
- CLI commands for local Git operations
- REST API handlers for remote Git operations
- Web UI backend for repository browsing
- Git smart HTTP protocol implementation (git-upload-pack, git-receive-pack)

## Detailed Specifications

### Input

Git commands with arguments that need to be executed securely, with support for:
- Standard Git commands (clone, fetch, push, status, diff, log, etc.)
- Git smart HTTP protocol commands (git-upload-pack, git-receive-pack)
- Streaming I/O for large operations
- Environment variable management
- Timeout enforcement

### Expected Output

A robust Git command wrapper that:
1. Prevents command injection attacks
2. Handles process lifecycle correctly
3. Streams I/O efficiently
4. Enforces timeouts
5. Provides detailed error information
6. Works across different environments

### Steps

**CRITICAL**: Follow TDD approach - write tests first, then implementation. Run `zig build && zig build test` after EVERY change.

#### Phase 1: Core Security Foundation (TDD)

1. **Create module structure**
   ```bash
   mkdir -p src/git
   touch src/git/command.zig
   ```

2. **Write security validation tests first**
   ```zig
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

   test "sanitizes repository paths" {
       const allocator = std.testing.allocator;
       try std.testing.expectError(error.InvalidRepository, validateRepositoryPath("../../../etc"));
       try std.testing.expectError(error.InvalidRepository, validateRepositoryPath("/etc/passwd"));
       try validateRepositoryPath("repos/user/project.git");
   }
   ```

3. **Implement security functions**
   - `isSafeArgumentValue()` - Prevent dash-prefixed values
   - `isValidGitOption()` - Whitelist known Git options
   - `validateRepositoryPath()` - Prevent directory traversal
   - `sanitizeGitUrl()` - Remove credentials from URLs

#### Phase 2: Git Executable Detection (TDD)

1. **Write detection tests**
   ```zig
   test "finds git executable" {
       const allocator = std.testing.allocator;
       const git_path = findGitExecutable(allocator) catch {
           std.log.warn("Git not available, skipping test", .{});
           return;
       };
       defer allocator.free(git_path);
       
       try std.testing.expect(git_path.len > 0);
       try std.testing.expect(std.mem.endsWith(u8, git_path, "git"));
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
   ```

2. **Implement detection logic**
   - Check standard paths: `/usr/bin/git`, `/usr/local/bin/git`
   - Parse PATH environment variable
   - Validate executable exists and is runnable
   - Extract and parse version information

#### Phase 3: Basic Command Execution (TDD)

1. **Write execution tests**
   ```zig
   test "executes simple git command" {
       const allocator = std.testing.allocator;
       
       var cmd = try GitCommand.init(allocator);
       defer cmd.deinit();
       
       const result = try cmd.run(allocator, &.{"version"});
       defer result.deinit(allocator);
       
       try std.testing.expect(result.exit_code == 0);
       try std.testing.expect(std.mem.indexOf(u8, result.stdout, "git version") != null);
   }

   test "captures stderr on failure" {
       const allocator = std.testing.allocator;
       
       var cmd = try GitCommand.init(allocator);
       defer cmd.deinit();
       
       const result = try cmd.run(allocator, &.{"invalid-command"});
       defer result.deinit(allocator);
       
       try std.testing.expect(result.exit_code != 0);
       try std.testing.expect(result.stderr.len > 0);
   }
   ```

2. **Implement GitCommand struct**
   ```zig
   pub const GitCommand = struct {
       executable_path: []const u8,
       allocator: std.mem.Allocator,
       
       pub fn init(allocator: std.mem.Allocator) !GitCommand {
           const path = try findGitExecutable(allocator);
           return GitCommand{
               .executable_path = path,
               .allocator = allocator,
           };
       }
       
       pub fn deinit(self: *GitCommand) void {
           self.allocator.free(self.executable_path);
       }
       
       pub fn run(self: *GitCommand, allocator: std.mem.Allocator, args: []const []const u8) !GitResult {
           // Implementation with ChildProcess
       }
   };
   ```

#### Phase 4: Environment and Working Directory (TDD)

1. **Write environment tests**
   ```zig
   test "sets working directory" {
       const allocator = std.testing.allocator;
       
       // Create temp directory
       const tmp_dir = try std.fs.cwd().makeTempDir("git_test_");
       defer std.fs.cwd().deleteTree(tmp_dir.sub_path) catch {};
       
       var cmd = try GitCommand.init(allocator);
       defer cmd.deinit();
       
       const result = try cmd.runWithOptions(allocator, .{
           .args = &.{"init"},
           .cwd = tmp_dir.sub_path,
       });
       defer result.deinit(allocator);
       
       try std.testing.expect(result.exit_code == 0);
   }

   test "filters environment variables" {
       const allocator = std.testing.allocator;
       
       var cmd = try GitCommand.init(allocator);
       defer cmd.deinit();
       
       const result = try cmd.runWithOptions(allocator, .{
           .args = &.{"config", "--list"},
           .env = &.{
               .{ .name = "GIT_AUTHOR_NAME", .value = "Test User" },
               .{ .name = "MALICIOUS_VAR", .value = "should not pass" },
           },
       });
       defer result.deinit(allocator);
       
       // Verify only safe env vars were passed
   }
   ```

2. **Implement RunOptions**
   ```zig
   pub const RunOptions = struct {
       args: []const []const u8,
       cwd: ?[]const u8 = null,
       env: ?[]const EnvVar = null,
       timeout_ms: u32 = 120000, // 2 minutes default
       stdin: ?[]const u8 = null,
   };
   ```

#### Phase 5: Streaming I/O Support (TDD)

1. **Write streaming tests**
   ```zig
   test "streams large output" {
       const allocator = std.testing.allocator;
       
       var cmd = try GitCommand.init(allocator);
       defer cmd.deinit();
       
       var stdout_chunks = std.ArrayList([]u8).init(allocator);
       defer {
           for (stdout_chunks.items) |chunk| allocator.free(chunk);
           stdout_chunks.deinit();
       }
       
       const exit_code = try cmd.runStreaming(allocator, .{
           .args = &.{"log", "--oneline", "-n", "1000"},
           .stdout_callback = struct {
               fn callback(data: []const u8, context: *std.ArrayList([]u8)) !void {
                   const chunk = try context.allocator.dupe(u8, data);
                   try context.append(chunk);
               }
           }.callback,
           .stdout_context = &stdout_chunks,
       });
       
       try std.testing.expect(exit_code == 0);
       try std.testing.expect(stdout_chunks.items.len > 0);
   }
   ```

2. **Implement streaming execution**
   - Use pipes for stdout/stderr
   - Read in chunks with configurable buffer size
   - Call callbacks for each chunk
   - Handle backpressure correctly

#### Phase 6: Timeout Enforcement (TDD)

1. **Write timeout tests**
   ```zig
   test "enforces timeout" {
       const allocator = std.testing.allocator;
       
       var cmd = try GitCommand.init(allocator);
       defer cmd.deinit();
       
       const start = std.time.milliTimestamp();
       const result = cmd.runWithOptions(allocator, .{
           .args = &.{"clone", "https://github.com/torvalds/linux.git"},
           .timeout_ms = 100, // 100ms timeout
       }) catch |err| switch (err) {
           error.Timeout => {
               const elapsed = std.time.milliTimestamp() - start;
               try std.testing.expect(elapsed < 200); // Should timeout quickly
               return;
           },
           else => return err,
       };
       
       unreachable; // Should have timed out
   }
   ```

2. **Implement timeout mechanism**
   - Use separate thread for timeout monitoring
   - Kill process group on timeout
   - Clean up resources properly

#### Phase 7: Git Protocol Support (TDD)

1. **Write protocol tests**
   ```zig
   test "handles git-upload-pack" {
       const allocator = std.testing.allocator;
       
       var cmd = try GitCommand.init(allocator);
       defer cmd.deinit();
       
       // Test with actual git protocol handshake
       const input = "0067want 1234567890abcdef1234567890abcdef12345678 multi_ack_detailed no-done side-band-64k thin-pack ofs-delta deepen-since deepen-not agent=git/2.39.0\n0000";
       
       const result = try cmd.runWithOptions(allocator, .{
           .args = &.{"upload-pack", "--stateless-rpc", "--advertise-refs", "."},
           .stdin = input,
       });
       defer result.deinit(allocator);
       
       try std.testing.expect(result.exit_code == 0);
       // Verify protocol response format
   }
   ```

2. **Implement protocol-specific handling**
   - Support for git-upload-pack
   - Support for git-receive-pack
   - Handle binary protocol data
   - Proper stdin/stdout handling for protocol

#### Phase 8: Integration with Server (TDD)

1. **Write handler integration test**
   ```zig
   test "integrates with zap handler" {
       const allocator = std.testing.allocator;
       
       // Mock zap request
       var req = TestRequest{
           .path = "/repos/user/project.git/info/refs",
           .query = "service=git-upload-pack",
       };
       
       var ctx = Context{
           .allocator = allocator,
           .dao = undefined, // Mock DAO
       };
       
       try gitSmartHttpHandler(&req, &ctx);
       
       try std.testing.expectEqualStrings("application/x-git-upload-pack-advertisement", req.response_content_type);
   }
   ```

2. **Create server handlers**
   ```zig
   // src/server/handlers/git.zig
   pub fn gitSmartHttpHandler(r: zap.Request, ctx: *Context) !void {
       const allocator = ctx.allocator;
       
       // Parse service type from query
       // Validate repository access
       // Execute appropriate git command
       // Stream response back
   }
   ```

### Critical Implementation Details

1. **Memory Management**
   - Never store allocator in GitCommand struct (pass to methods)
   - Use explicit defer for all allocations
   - Result structs own memory that caller must free
   - Stream callbacks should not retain references to data

2. **Process Management**
   - Always use process groups for timeout handling
   - Clean up child processes on all error paths
   - Handle SIGPIPE for broken connections
   - Set appropriate process limits

3. **Security Hardening**
   - Validate all inputs before process creation
   - Use minimal environment variables
   - Never pass user input directly to shell
   - Implement argument count limits

4. **Docker Compatibility**
   - Handle different Git paths in Alpine
   - Work with limited process capabilities
   - Handle missing locales gracefully

### Common Pitfalls to Avoid

1. **Process Leaks**
   - Always kill child processes on timeout
   - Handle partial reads/writes correctly
   - Clean up on all error paths

2. **Memory Issues**
   - Don't retain pointers to process output after free
   - Handle large outputs without OOM
   - Free partial results on error

3. **Security Vulnerabilities**
   - Never use shell expansion
   - Validate all file paths
   - Sanitize environment variables
   - Limit resource usage

4. **Platform Issues**
   - Test on both Linux and macOS
   - Handle different Git versions
   - Work in restricted containers

## Code Style & Architecture

### Design Patterns

- **Builder Pattern**: Use options struct for complex function parameters
- **Result Pattern**: Return structured results with explicit ownership
- **Callback Pattern**: For streaming operations with context
- **Resource Management**: RAII with init/deinit patterns

### Code Organization

```
project/
├── src/
│   ├── git/
│   │   └── command.zig       # Main Git wrapper implementation
│   ├── server/
│   │   └── handlers/
│   │       └── git.zig       # Git smart HTTP handlers
│   └── commands/
│       └── git.zig           # CLI git commands
```

### Testing Strategy

1. **Unit Tests**: Each security function tested in isolation
2. **Integration Tests**: Full command execution with real Git
3. **Protocol Tests**: Git smart HTTP protocol compliance
4. **Stress Tests**: Large repository operations
5. **Security Tests**: Attempt injection attacks

## Success Criteria

1. **Security**: Zero command injection vulnerabilities
2. **Performance**: Stream 1GB+ repositories without OOM
3. **Compatibility**: Works on Linux, macOS, Docker
4. **Reliability**: Proper cleanup in all scenarios
5. **Integration**: Seamless use in handlers and CLI
6. **Testing**: 100% coverage of security paths
7. **Documentation**: Clear examples for common operations

## Build Verification Protocol

**MANDATORY**: After EVERY code change:
```bash
zig build && zig build test
```

- Build takes <10 seconds - NO EXCUSES
- Zero tolerance for compilation failures
- If tests fail, YOU caused a regression
- Fix immediately before proceeding

## Example Usage

```zig
// CLI usage
const git = try GitCommand.init(allocator);
defer git.deinit();

const result = try git.run(allocator, &.{"status", "--porcelain"});
defer result.deinit(allocator);

std.log.info("Git status: {s}", .{result.stdout});

// Server handler usage
pub fn cloneHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    const repo_url = try r.getParam("url");
    
    var git = try GitCommand.init(allocator);
    defer git.deinit();
    
    // Stream progress to client
    const exit_code = try git.runStreaming(allocator, .{
        .args = &.{"clone", "--progress", repo_url},
        .stderr_callback = sendProgressToClient,
        .stderr_context = r,
    });
    
    if (exit_code != 0) {
        try r.setStatus(.bad_request);
        try r.sendBody("Clone failed");
        return;
    }
    
    try r.sendJson(.{ .status = "success" });
}
```

## References

- Git Documentation: https://git-scm.com/docs
- Git Protocol: https://git-scm.com/book/en/v2/Git-on-the-Server-The-Protocols
- Zig Process API: https://ziglang.org/documentation/master/std/#std.process
- Security Best Practices: OWASP Command Injection