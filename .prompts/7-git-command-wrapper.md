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

**CRITICAL**: Follow TDD approach - write tests first, then implementation. Run `zig build && zig build test` after EVERY change. Always add tests to the same file as the source code.

**Note** Though we tried our best all code should be treated as pseudocode. it is your job to make sure it gets implemented correctly and think harder about the implementation in context as you are making them.
**Amendments** You may run into an issue and need to change the plan. This is meant to be avoided at all costs and should never happen for sake of just reducing scope or workload. It should only be because the spec didn't take something into account. If you learn anything major as you go consider adding amendments to bottom of this md file

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
   ```

3. **Implement security functions**
   - `isSafeArgumentValue()` - Prevent dash-prefixed values
   - `isValidGitOption()` - Whitelist known Git options
   - `isBrokenGitArgument()` - Blacklist known problematic arguments
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
   ```

2. **Implement GitCommand struct**

   ```zig
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
       defer cmd.deinit(allocator);

       const result = try cmd.runWithOptions(allocator, .{
           .args = &.{"init"},
           .cwd = tmp_dir.sub_path,
       });
       defer result.deinit(allocator);

       try std.testing.expect(result.exit_code == 0);
   }

   test "uses strict environment allow-list" {
       const allocator = std.testing.allocator;

       var cmd = try GitCommand.init(allocator);
       defer cmd.deinit(allocator);

       // Test that parent process env vars don't leak
       try std.os.setenv("DATABASE_URL", "postgresql://secret", true);
       try std.os.setenv("AWS_SECRET_ACCESS_KEY", "secret-key", true);
       
       const result = try cmd.runWithOptions(allocator, .{
           .args = &.{"config", "--list"},
           .env = &.{
               .{ .name = "GIT_AUTHOR_NAME", .value = "Test User" },
               .{ .name = "GIT_COMMITTER_EMAIL", .value = "test@example.com" },
               .{ .name = "MALICIOUS_VAR", .value = "should not pass" },
           },
       });
       defer result.deinit(allocator);

       // Verify only allowed GIT_* vars were passed
       try std.testing.expect(std.mem.indexOf(u8, result.stdout, "GIT_AUTHOR_NAME=Test User") != null);
       try std.testing.expect(std.mem.indexOf(u8, result.stdout, "DATABASE_URL") == null);
       try std.testing.expect(std.mem.indexOf(u8, result.stdout, "AWS_SECRET_ACCESS_KEY") == null);
       try std.testing.expect(std.mem.indexOf(u8, result.stdout, "MALICIOUS_VAR") == null);
   }
   ```

2. **Implement RunOptions with strict environment control**
   ```zig
   pub const EnvVar = struct {
       name: []const u8,
       value: []const u8,
   };

   pub const RunOptions = struct {
       args: []const []const u8,
       cwd: ?[]const u8 = null,
       env: ?[]const EnvVar = null,  // Only allowed vars will be passed
       timeout_ms: u32 = 120000, // 2 minutes default
       stdin: ?[]const u8 = null,
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
   ```

#### Phase 5: Streaming I/O Support (TDD)

1. **Write streaming tests**

   ```zig
   test "streams large output" {
       const allocator = std.testing.allocator;

       var cmd = try GitCommand.init(allocator);
       defer cmd.deinit(allocator);

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

2. **Implement streaming execution with proper I/O handling**
   ```zig
   // Set up non-blocking pipes
   var stdout_pipe = try std.posix.pipe();
   var stderr_pipe = try std.posix.pipe();
   
   // Configure non-blocking I/O
   const flags = try std.posix.fcntl(stdout_pipe[0], .F_GETFL, 0);
   _ = try std.posix.fcntl(stdout_pipe[0], .F_SETFL, flags | std.posix.O.NONBLOCK);
   
   // Efficient buffer size (4-16KB typical)
   const BUFFER_SIZE = 16 * 1024;
   var buffer: [BUFFER_SIZE]u8 = undefined;
   
   // Read loop with poll for efficiency
   var pollfds = [_]std.posix.pollfd{
       .{ .fd = stdout_pipe[0], .events = std.posix.POLL.IN, .revents = 0 },
       .{ .fd = stderr_pipe[0], .events = std.posix.POLL.IN, .revents = 0 },
   };
   
   while (true) {
       _ = try std.posix.poll(&pollfds, 1000); // 1 second timeout
       
       if (pollfds[0].revents & std.posix.POLL.IN != 0) {
           const n = std.posix.read(stdout_pipe[0], &buffer) catch |err| switch (err) {
               error.WouldBlock => continue,
               else => return err,
           };
           
           if (n == 0) break; // EOF
           
           // Call callback with chunk
           try options.stdout_callback(buffer[0..n], options.stdout_context);
       }
   }
   ```

#### Phase 6: Timeout Enforcement (TDD)

1. **Write timeout tests**

   ```zig
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
               try std.testing.expect(elapsed < 200); // Should timeout quickly
               return;
           },
           else => return err,
       };

       unreachable; // Should have timed out
   }
   ```

2. **Implement timeout mechanism with process groups**
   ```zig
   // Note: std.process.Child doesn't expose setpgid directly
   // Must use manual fork/exec pattern for process groups
   const pid = try std.posix.fork();
   
   if (pid == 0) {
       // Child: Create new process group
       _ = std.posix.setpgid(0, 0) catch std.posix.exit(1);
       
       // Set resource limits if needed
       const rlim = std.posix.rlimit{
           .cur = 256 * 1024 * 1024, // 256MB memory limit
           .max = 256 * 1024 * 1024,
       };
       _ = std.posix.setrlimit(.AS, &rlim) catch {};
       
       // Execute git
       const argv = [_:null]?[*:0]const u8{ git_path, args... };
       std.posix.execvpeZ(git_path, &argv, envp) catch std.posix.exit(1);
   }
   
   // Parent: Monitor with timeout thread
   const State = struct {
       mutex: std.Thread.Mutex = .{},
       is_done: bool = false,
       child_pgid: std.posix.pid_t,
   };
   
   var state = State{ .child_pgid = pid };
   const monitor = try std.Thread.spawn(.{}, monitorThread, .{ &state, timeout_ms });
   
   // On timeout, kill entire process group
   fn monitorThread(state: *State, timeout_ms: u64) void {
       std.time.sleep(timeout_ms * std.time.ns_per_ms);
       
       state.mutex.lock();
       defer state.mutex.unlock();
       
       if (!state.is_done) {
           // Kill entire process group (negative PID)
           _ = std.posix.kill(-state.child_pgid, .TERM) catch {};
           std.time.sleep(100 * std.time.ns_per_ms);
           _ = std.posix.kill(-state.child_pgid, .KILL) catch {};
       }
   }
   ```

#### Phase 7: Git Protocol Support (TDD)

1. **Write protocol tests with contextual environment**

   ```zig
   test "handles git-upload-pack with context" {
       const allocator = std.testing.allocator;

       var cmd = try GitCommand.init(allocator);
       defer cmd.deinit(allocator);

       // Test with actual git protocol handshake
       const input = "0067want 1234567890abcdef1234567890abcdef12345678 multi_ack_detailed no-done side-band-64k thin-pack ofs-delta deepen-since deepen-not agent=git/2.39.0\n0000";

       const result = try cmd.runWithProtocolContext(allocator, .{
           .args = &.{"upload-pack", "--stateless-rpc", "--advertise-refs", "."},
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

       try std.testing.expect(result.exit_code == 0);
       // Verify protocol response format
   }

   test "sets protocol environment variables" {
       const allocator = std.testing.allocator;

       var cmd = try GitCommand.init(allocator);
       defer cmd.deinit(allocator);

       const result = try cmd.runWithProtocolContext(allocator, .{
           .args = &.{"config", "--list"},
           .protocol_context = .{
               .pusher_id = "456",
               .pusher_name = "alice",
               .repo_username = "org",
               .repo_name = "repo",
               .is_wiki = true,
           },
       });
       defer result.deinit(allocator);

       // These would be available to hooks
       try std.testing.expect(result.exit_code == 0);
   }
   ```

2. **Implement protocol-specific handling**
   ```zig
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
   ```

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
   - GitCommandError should be stack-allocated when possible
   - Use ArenaAllocator for request-scoped operations
   - Combine ArenaAllocator (temporary) with GeneralPurposeAllocator (long-lived)

2. **Process Management**

   - Always use process groups for timeout handling (requires manual fork/exec)
   - Clean up child processes on all error paths
   - Ignore SIGPIPE at startup: `std.posix.sigaction(.PIPE, &.{ .handler = .{ .handler = std.posix.SIG.IGN } }, null)`
   - Set resource limits with setrlimit before exec
   - Use dedicated monitoring thread for timeouts (not async/await)

3. **Security Hardening**

   - Validate all inputs before process creation
   - Start with empty environment, add only from allow-list
   - Never pass user input directly to shell
   - Implement argument count limits
   - Maintain blacklist for known problematic arguments

4. **Docker Compatibility**
   - Handle different Git paths in Alpine
   - Work with limited process capabilities
   - Handle missing locales gracefully
   - Cache git executable path globally after first lookup

5. **Error Handling**
   - Parse stderr for specific Git errors (e.g., "repository not found")
   - Differentiate spawn errors from execution errors
   - Use Diagnostics Pattern for rich error context
   - Map errno values to domain-specific errors

6. **I/O Patterns**
   - Use 4-16KB buffers for pipe reads
   - Configure non-blocking I/O with fcntl
   - Use poll() to avoid busy-waiting on pipes
   - Handle error.WouldBlock gracefully

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
defer git.deinit(allocator);

const result = try git.run(allocator, &.{"status", "--porcelain"});
defer result.deinit(allocator);

std.log.info("Git status: {s}", .{result.stdout});

// Server handler usage
pub fn cloneHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    const repo_url = try r.getParam("url");

    var git = try GitCommand.init(allocator);
    defer git.deinit(allocator);

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
- Gitea Implementation: https://github.com/go-gitea/gitea/blob/main/modules/git/command.go

## Amendments

### Implementation Guidance from Zig Research

1. **Process Groups Require Manual Fork/Exec**
   - `std.process.Child` doesn't expose `setpgid` functionality
   - Must use `std.posix.fork()` and `std.posix.setpgid(0, 0)` pattern
   - Call `setpgid` in child before `execvpe` to avoid race conditions
   - Complete pattern:
   ```zig
   const pid = try std.posix.fork();
   if (pid == 0) {
       // Child process
       _ = std.posix.setpgid(0, 0) catch std.posix.exit(1);
       const argv = [_:null]?[*:0]const u8{ "git", "status", null };
       const envp = [_:null]?[*:0]const u8{ null };
       std.posix.execvpeZ("git", &argv, &envp) catch std.posix.exit(1);
   }
   ```

2. **SIGPIPE Handling Pattern**
   ```zig
   // At application startup
   var sa = std.posix.Sigaction{
       .handler = .{ .handler = std.posix.SIG.IGN },
       .mask = std.posix.empty_sigset,
       .flags = 0,
   };
   try std.posix.sigaction(.PIPE, &sa, null);
   ```

3. **Memory Allocation Strategy**
   - Use `ArenaAllocator` for per-command temporary memory
   - Use `GeneralPurposeAllocator` for long-lived results
   - Global arena for caching git executable path

4. **Non-Blocking I/O Pattern**
   ```zig
   const flags = try std.posix.fcntl(fd, .F_GETFL, 0);
   _ = try std.posix.fcntl(fd, .F_SETFL, flags | std.posix.O.NONBLOCK);
   ```

5. **Platform-Specific Considerations**
   - Windows: Check for `git.exe`, handle different process termination
   - Use `std.fs.path` for cross-platform path handling
   - Git paths in Alpine: `/usr/bin/git` (busybox)

6. **Complete findGitExecutable Implementation**
   ```zig
   var g_git_path: ?[]const u8 = null;
   var g_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
   
   pub fn findGitExecutable(allocator: std.mem.Allocator) ![]const u8 {
       if (g_git_path) |path| return path;
       
       const path_env = try std.process.getEnvVarOwned(allocator, "PATH");
       defer allocator.free(path_env);
       
       var it = std.mem.tokenize(u8, path_env, &[_]u8{std.fs.path.delimiter});
       while (it.next()) |dir| {
           const git_name = if (builtin.os.tag == .windows) "git.exe" else "git";
           const git_path = try std.fs.path.join(allocator, &.{ dir, git_name });
           defer allocator.free(git_path);
           
           // Check if executable
           const stat = std.fs.cwd().statFile(git_path) catch continue;
           if (stat.kind != .file) continue;
           if (builtin.os.tag.isDarwin() or builtin.os.tag == .linux) {
               if (stat.mode & 0o111 == 0) continue;
           }
           
           g_git_path = try g_arena.allocator().dupe(u8, git_path);
           return g_git_path.?;
       }
       
       return error.GitNotFound;
   }
   ```

7. **String Ownership Pattern**
   ```zig
   const GitResult = struct {
       stdout: []u8,
       stderr: []u8,
       exit_code: u8,
       
       pub fn init(allocator: std.mem.Allocator, stdout: []const u8, stderr: []const u8, code: u8) !GitResult {
           return GitResult{
               .stdout = try allocator.dupe(u8, stdout),
               .stderr = try allocator.dupe(u8, stderr),
               .exit_code = code,
           };
       }
       
       pub fn deinit(self: *GitResult, allocator: std.mem.Allocator) void {
           allocator.free(self.stdout);
           allocator.free(self.stderr);
           self.* = undefined; // Invalidate
       }
   };
   ```

8. **Callback Pattern for Streaming**
   ```zig
   // Prefer comptime callbacks for performance
   pub fn runStreamingComptime(
       self: *const GitCommand,
       allocator: std.mem.Allocator,
       options: RunOptions,
       comptime CallbackT: type,
       callback: CallbackT,
       context: anytype,
   ) !u8 {
       // Compiler can inline the callback
   }
   
   // Runtime callbacks for flexibility
   pub fn runStreamingRuntime(
       self: *const GitCommand,
       allocator: std.mem.Allocator,
       options: RunOptions,
       callback: *const fn([]const u8, *anyopaque) anyerror!void,
       context: *anyopaque,
   ) !u8 {
       // Indirect function call overhead
   }
   ```

### Additional Security Insights from Gitea Analysis

1. **Broken Arguments List**
   - `--upload-archive`: Old syntax, security risk
   - `--output`: Can write to arbitrary files
   - `-c` is allowed but values must be hardcoded by application

2. **Protocol Headers**
   - Upload-pack advertisement: `Content-Type: application/x-git-upload-pack-advertisement`
   - Upload-pack result: `Content-Type: application/x-git-upload-pack-result`
   - Include `Cache-Control: no-cache`

3. **Hook Environment Variables**
   - Pass context via `PLUE_*` variables for hooks
   - Pre-receive is synchronous (can reject push)
   - Post-receive is asynchronous (for side effects)

### Error Handling Patterns from Zig Research

1. **Spawn vs Execution Errors**
   ```zig
   // Spawn errors (can't start process)
   child.spawn() catch |err| switch (err) {
       error.FileNotFound => return error.GitNotFound,
       error.AccessDenied => return error.PermissionDenied,
       else => return err,
   };
   
   // Execution errors (process ran but failed)
   const term = try child.wait();
   switch (term) {
       .Exited => |code| if (code != 0) return error.ProcessFailed,
       .Signal => |sig| return error.ProcessKilled,
       else => return error.UnknownTermination,
   }
   ```

2. **Diagnostics Pattern for Rich Errors**
   ```zig
   const GitDiagnostics = struct {
       command: []const u8 = "",
       args: []const []const u8 = &.{},
       exit_code: ?u8 = null,
       stderr: []const u8 = "",
       cwd: []const u8 = "",
   };
   
   pub fn runWithDiagnostics(
       self: *const GitCommand,
       allocator: std.mem.Allocator,
       options: RunOptions,
       diags: ?*GitDiagnostics,
   ) GitError!GitResult {
       // On error, populate diagnostics before returning
       errdefer if (diags) |d| {
           d.command = self.executable_path;
           d.args = options.args;
           d.cwd = options.cwd orelse std.fs.cwd().realpathAlloc(allocator, ".") catch "";
       };
   }
   ```

3. **Thread Safety Patterns**
   ```zig
   // Option 1: Thread-local instances (simplest)
   threadlocal var tl_git_cmd: ?GitCommand = null;
   
   // Option 2: Mutex-protected shared instance
   const SharedGitCommand = struct {
       mutex: std.Thread.Mutex = .{},
       cmd: GitCommand,
       
       pub fn run(self: *SharedGitCommand, allocator: std.mem.Allocator, args: []const []const u8) !GitResult {
           self.mutex.lock();
           defer self.mutex.unlock();
           return self.cmd.run(allocator, args);
       }
   };
   
   // Option 3: Atomic counters for statistics
   var active_git_processes = std.atomic.Atomic(u32).init(0);
   _ = active_git_processes.fetchAdd(1, .Monotonic);
   defer _ = active_git_processes.fetchSub(1, .Monotonic);
   ```

4. **Testing Patterns**
   ```zig
   // Dependency injection for testability
   const GitRunner = struct {
       runFn: *const fn (allocator: std.mem.Allocator, args: []const []const u8) anyerror!GitResult,
       context: *anyopaque,
   };
   
   // Platform-specific test
   test "posix process groups" {
       if (builtin.os.tag == .windows) return error.SkipZigTest;
       // Test logic
   }
   ```

_This section will be updated with any significant learnings or changes discovered during implementation._
