# Fix Git Command I/O Deadlocks and Re-enable SIGPIPE Handling

## Implementation Summary

**Status**: ⚠️ PARTIALLY IMPLEMENTED (Workaround, not proper fix)

A commit was made that addresses the deadlock issue, but it uses workarounds rather than implementing the proper concurrent I/O solution described in this prompt.

### Partial Implementation
**Commit**: 7b976a9 - 🐛 fix(git): resolve command execution deadlocks and update Zig syntax (Jul 28, 2025)

**What was implemented**:
- ✅ Fixed immediate deadlock by using Child.run for simple cases
- ✅ Updated deprecated Zig syntax (tokenize, for loops, const qualifiers)
- ✅ Fixed memory leaks in environment variable handling
- ✅ Used system temp directories for test files
- ⚠️ **WORKAROUND**: Skipped problematic tests with stdin/streaming
- ❌ Did NOT implement concurrent I/O reading
- ❌ Did NOT re-enable SIGPIPE handling

**Evidence from commit message**:
```
- Fix deadlock in runWithOptions by using Child.run for simple cases
- Skip problematic tests with stdin/streaming
```

**Current state of skipped tests**:
The tests `"streams large output"` and `"handles git-upload-pack with context"` are still skipped, indicating the underlying deadlock issue hasn't been properly resolved.

**What still needs to be done**:

1. **Implement Proper Concurrent I/O** (Phase 1)
   - ❌ Replace sequential stdout/stderr reading with concurrent approach
   - ❌ Use non-blocking I/O or poll/epoll/kqueue
   - ❌ Handle both streams simultaneously to prevent deadlocks
   - ❌ Un-skip and fix the problematic tests

2. **Re-enable SIGPIPE Handler** (Phase 2)
   - ❌ Uncomment and properly initialize the SIGPIPE handler
   - ❌ Ensure it's called once at application startup
   - ❌ Verify it doesn't cause new issues

**Critical Impact**:
The current workaround means that any Git operations requiring streaming I/O or stdin input may still be vulnerable to deadlocks. This affects core Git network protocol operations like `git-upload-pack` and `git-receive-pack`, which are essential for clone/push/pull operations.

**Production Risk**:
⚠️ HIGH - The server could hang indefinitely when handling certain Git operations, requiring manual intervention to recover. This is particularly problematic for:
- Large repository clones
- Operations with significant stderr output
- Any streaming Git protocol operations

**Recommended Priority**:
This should be prioritized for proper implementation as it affects core Git server functionality and reliability.

## Context

The current implementation for running Git commands with `stdin` or streaming I/O in `src/git/command.zig` has a critical flaw that can lead to deadlocks. The code reads the child process's `stdout` stream to completion before attempting to read `stderr`.

If a child process generates enough output on `stderr` to fill its operating system pipe buffer, it will block, waiting for the parent process to read from `stderr`. However, the parent process is stuck waiting to finish reading from `stdout`, resulting in a permanent deadlock where both processes wait for each other indefinitely.

This issue is likely the reason the `SIGPIPE` handler was disabled, as a deadlock during a write to `stdin` could trigger it.

## Goal

- Refactor the I/O handling in `runWithOptions` (for cases with `stdin`) and `runStreaming` to read from `stdout` and `stderr` concurrently, preventing deadlocks.
- Re-enable the `SIGPIPE` handler at application startup to ensure robust behavior in a server environment.
- Fix the tests that were skipped (`"streams large output"`, `"handles git-upload-pack with context"`) due to this bug.

## Implementation Steps

**CRITICAL**: This is a complex I/O problem. The recommended approach is to use non-blocking reads in a loop. Using `poll` (or `epoll`/`kqueue`) is the most robust solution.

### Phase 1: Implement Concurrent I/O Reading (TDD)

1.  **Un-skip the Deadlock-Prone Tests**

    Locate the tests `"streams large output"` and `"handles git-upload-pack with context"` in `src/git/command.zig`. Remove the `return error.SkipZigTest;` line to re-enable them. They should fail or hang, demonstrating the bug.

2.  **Refactor I/O Logic in `runWithOptions` and `runStreaming`**

    The core of this task is to replace the sequential `read` loops with a concurrent one. A single helper function could be created to handle this for both `runWithOptions` and `runStreaming`.

    **Example using non-blocking reads in a loop (simplified):**

    ```zig
    // This is a conceptual example. The actual implementation will need to handle
    // file descriptors, buffers, and callbacks correctly.

    // After child.spawn()
    const stdout_fd = child.stdout.?.handle;
    const stderr_fd = child.stderr.?.handle;

    // Set fds to non-blocking
    _ = try std.posix.fcntl(stdout_fd, .F_SETFL, try std.posix.fcntl(stdout_fd, .F_GETFL, 0) | std.posix.O.NONBLOCK);
    _ = try std.posix.fcntl(stderr_fd, .F_SETFL, try std.posix.fcntl(stderr_fd, .F_GETFL, 0) | std.posix.O.NONBLOCK);

    var stdout_closed = false;
    var stderr_closed = false;
    var buffer: [4096]u8 = undefined;

    while (!stdout_closed or !stderr_closed) {
        if (!stdout_closed) {
            const bytes_read = std.posix.read(stdout_fd, &buffer) catch |err| switch (err) {
                error.WouldBlock => 0, // Nothing to read right now
                else => |e| return e,
            };
            if (bytes_read > 0) {
                // Process stdout data (append to list or call callback)
            } else if (isEof(bytes_read, err)) { // Helper to check for EOF condition
                stdout_closed = true;
            }
        }

        if (!stderr_closed) {
            const bytes_read = std.posix.read(stderr_fd, &buffer) catch |err| switch (err) {
                error.WouldBlock => 0,
                else => |e| return e,
            };
            if (bytes_read > 0) {
                // Process stderr data
            } else if (isEof(bytes_read, err)) {
                stderr_closed = true;
            }
        }

        // If both streams are closed, break the loop.
        // Add a small sleep if no data was read on either stream to prevent busy-spinning.
        if (last_stdout_read == 0 and last_stderr_read == 0) {
            std.time.sleep(std.time.ns_per_ms * 10);
        }
    }
    ```
    **Note**: A `poll`-based implementation would be more efficient than sleeping.

3.  **Verify with Tests**

    Run `zig build test`. The previously skipped tests should now pass, proving that the I/O logic is no longer deadlocking.

### Phase 2: Re-enable SIGPIPE Handler

1.  **Uncomment the `init_sigpipe` Block**

    In `src/git/command.zig`, find the `init_sigpipe` block at the top of the file and uncomment it.

    ```zig
    // Re-enable this block
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
    ```
    This should be called once at application startup. Ensure it's not in a function that gets called repeatedly. Placing it at the module's top level ensures it runs on module load.

2.  **Final Verification**

    Run `zig build test` one last time to ensure that re-enabling the `SIGPIPE` handler does not cause any new issues.

## Verification

- The tests `"streams large output"` and `"handles git-upload-pack with context"` must pass reliably.
- The application should be able to handle large git operations (like `clone` or `cat-file`) involving both `stdin` and `stdout`/`stderr` without hanging.
- The `SIGPIPE` signal should be correctly ignored by the application.

## Impact

Fixing this deadlock is critical for the stability and reliability of the application. Any operation involving `git-upload-pack` or `git-receive-pack` (the core of Git's network protocol) would have been vulnerable to this bug, causing server processes to hang and become unresponsive.
