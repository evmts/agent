# Harden Git Command Security and Remove Global State

## Context

The current `src/git/command.zig` implementation uses runtime discovery to find the `git` executable and relies on global state for caching the path and for a memory arena. This introduces security risks and makes the module non-thread-safe.

1.  **Security Risk**: Searching the `PATH` for an executable at runtime in a server environment is dangerous. An attacker who can manipulate the `PATH` could trick the application into executing a malicious binary.
2.  **Thread Safety**: The global variables `g_git_path` and `g_arena` create race conditions in a multi-threaded server, which can lead to memory corruption or unpredictable behavior.

This task is to refactor the `GitCommand` module to eliminate these issues by requiring a configured path for the git executable and removing all global state.

## Goal

- Eliminate runtime discovery of the `git` executable.
- Remove all global state (`g_git_path`, `g_arena`) from the module.
- Make the `GitCommand` struct fully self-contained and thread-safe.
- Ensure the path to the `git` executable is a configuration parameter.

## Implementation Steps

**CRITICAL**: Follow TDD approach. Update tests before changing the implementation. Run `zig build && zig build test` after every significant change.

### Phase 1: Refactor `GitCommand` Initialization (TDD)

1.  **Update Tests for `GitCommand.init`**

    Modify existing tests that use `GitCommand.init(allocator)` to pass an explicit path to the git executable. The tests will fail until the implementation is updated. You will first need to find a valid `git` path to use for the tests. A helper function within the test file might be appropriate for this.

    ```zig
    // In a test helper or at the top of the test block
    const git_exe_for_test = findGitExecutableForTesting(std.testing.allocator) catch |err| {
        std.log.warn("Git not found, skipping test. Error: {s}", .{@errorName(err)});
        return error.SkipZigTest;
    };
    defer std.testing.allocator.free(git_exe_for_test);

    // Update a test
    test "executes simple git command" {
        const allocator = std.testing.allocator;

        var cmd = try GitCommand.init(allocator, git_exe_for_test); // Pass the path
        defer cmd.deinit(allocator);

        var result = try cmd.run(allocator, &.{"version"});
        defer result.deinit(allocator);

        try std.testing.expect(result.exit_code == 0);
    }
    ```

2.  **Modify `GitCommand.init` Signature**

    Change the `init` function to accept the executable path.

    ```zig
    // In src/git/command.zig
    pub const GitCommand = struct {
        executable_path: []const u8,

        pub fn init(allocator: std.mem.Allocator, git_exe_path: []const u8) !GitCommand {
            // Verify the path exists and is an executable file.
            const stat = std.fs.cwd().statFile(git_exe_path) catch return error.GitNotFound;
            if (stat.kind != .file) return error.GitNotFound;

            // On Unix, you could also check for execute permissions.
            if (builtin.os.tag != .windows) {
                if (stat.mode & 0o111 == 0) return error.PermissionDenied;
            }

            return GitCommand{
                .executable_path = try allocator.dupe(u8, git_exe_path),
            };
        }
        // ... rest of the struct
    };
    ```

### Phase 2: Remove `findGitExecutable` and Global State

1.  **Delete `findGitExecutable` and Related Tests**

    The function `findGitExecutable` is no longer needed. Delete it and its associated tests (`"finds git executable"` and `"detects git version"`). The `getGitVersion` function, which depends on it, should also be removed.

2.  **Remove Global Variables**

    Delete the global `g_git_path` and `g_arena` variables from the top of the file.

    ```zig
    // Remove these lines
    // var g_git_path: ?[]const u8 = null;
    // var g_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    ```

3.  **Update Call Sites**

    Search the codebase for any other places where `GitCommand.init(allocator)` was called and update them to provide the git executable path. This path should ultimately come from a configuration file or an environment variable read at application startup.

## Verification

- All existing tests must pass after the refactoring.
- The application must successfully start and execute git commands using the configured path.
- Run `zig build test` and ensure there are no failures.
- Manually inspect `src/git/command.zig` to confirm that no global variables remain.

## Security Impact

This change significantly improves the security posture of the application by preventing a class of command injection attacks where an attacker could control the `PATH` environment variable to execute a malicious program. It enforces the principle of using explicit, trusted paths for executables.
