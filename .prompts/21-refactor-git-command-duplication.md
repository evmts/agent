# Refactor Git Command Logic to Reduce Code Duplication

## Context

In `src/git/command.zig`, the functions `runWithOptions` and `runStreaming` share a significant amount of boilerplate code. This includes:

- Argument validation logic.
- Construction of the `argv` list for the child process.
- Setup and validation of the environment variables map.

This code duplication makes the module harder to maintain. A bug fix or a change in logic (e.g., adding a new allowed environment variable) needs to be applied in multiple places, increasing the risk of inconsistencies.

## Goal

- Refactor the duplicated code into one or more private helper functions.
- Ensure that both `runWithOptions` and `runStreaming` use this shared logic.
- Improve the maintainability and readability of the `GitCommand` module.
- Reduce the chance of future bugs caused by inconsistent logic.

## Implementation Steps

**CRITICAL**: This is a pure refactoring task. No functional changes should be introduced. All tests must pass before and after the changes.

### Phase 1: Argument and Environment Validation

1.  **Create a Helper for Argument Validation**

    Create a private function that takes `[]const []const u8` (the arguments) and performs the validation currently duplicated in both `run...` functions.

    ```zig
    // In GitCommand struct
    fn validateArguments(args: []const []const u8) !void {
        for (args, 0..) |arg, i| {
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
    }
    ```

2.  **Create a Helper for Environment Setup**

    Create a private function that takes `?[]const EnvVar` and returns an initialized `std.process.EnvMap`.

    ```zig
    // In GitCommand struct
    fn prepareEnvMap(allocator: std.mem.Allocator, env_vars: ?[]const EnvVar) !std.process.EnvMap {
        var env_map = std.process.EnvMap.init(allocator);
        errdefer env_map.deinit();

        // Start with minimal environment
        const path_env = std.process.getEnvVarOwned(allocator, "PATH") catch try allocator.dupe(u8, "/usr/local/bin:/usr/bin:/bin");
        defer allocator.free(path_env);
        const home_env = std.process.getEnvVarOwned(allocator, "HOME") catch try allocator.dupe(u8, "/tmp");
        defer allocator.free(home_env);

        try env_map.put("PATH", path_env);
        try env_map.put("HOME", home_env);

        // Add only allowed environment variables from input
        if (env_vars) |vars| {
            for (vars) |env_var| {
                if (isAllowedEnvVar(env_var.name)) {
                    try env_map.put(env_var.name, env_var.value);
                }
            }
        }

        return env_map;
    }
    ```

### Phase 2: Refactor `runWithOptions` and `runStreaming`

1.  **Update `runWithOptions`**

    Call the new helper functions from within `runWithOptions`.

    ```zig
    pub fn runWithOptions(self: *const GitCommand, allocator: std.mem.Allocator, options: RunOptions) !GitResult {
        try validateArguments(options.args);

        // Build full argv... (this can also be a helper)

        var env_map = if (options.env != null) try prepareEnvMap(allocator, options.env) else null;
        defer if (env_map) |*em| em.deinit();

        // ... rest of the function using the prepared argv and env_map
    }
    ```

2.  **Update `runStreaming`**

    Do the same for `runStreaming`.

    ```zig
    pub fn runStreaming(self: *const GitCommand, allocator: std.mem.Allocator, options: StreamingOptions) !u8 {
        try validateArguments(options.args);

        // Build full argv...

        var env_map = if (options.env != null) try prepareEnvMap(allocator, options.env) else null;
        defer if (env_map) |*em| em.deinit();

        // ... rest of the function
    }
    ```

### Phase 3: Create a Central `spawnChild` Helper (Optional but Recommended)

For an even cleaner refactoring, create a single helper function that prepares and spawns the child process.

1.  **Create `spawnChild` Helper**

    This function would encapsulate argument validation, argv building, environment setup, and the call to `child.spawn()`.

    ```zig
    // In GitCommand struct
    fn spawnChild(
        self: *const GitCommand,
        allocator: std.mem.Allocator,
        args: []const []const u8,
        cwd: ?[]const u8,
        env: ?[]const EnvVar,
        stdin_behavior: std.process.Child.StdIoBehavior,
    ) !std.process.Child {
        try validateArguments(args);

        var argv = std.ArrayList([]const u8).init(allocator);
        // errdefer argv.deinit(); // Caller must deinit argv if needed
        try argv.append(self.executable_path);
        try argv.appendSlice(args);

        var env_map = if (env != null) try prepareEnvMap(allocator, env) else null;
        // errdefer if (env_map) |*em| em.deinit(); // Caller must deinit

        var child = std.process.Child.init(argv.items, allocator);
        child.cwd = cwd;
        child.env_map = if (env_map) |*em| em else null;
        child.stdin_behavior = stdin_behavior;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        // Note: The caller is now responsible for de-initializing argv and env_map
        // This can be handled by returning them along with the child process in a struct.

        return child;
    }
    ```

2.  **Refactor `run...` Functions to Use `spawnChild`**

    Both `runWithOptions` and `runStreaming` would become much simpler, primarily responsible for calling `spawnChild` and then handling the I/O and process termination logic.

## Verification

- Run `zig build test` after the refactoring.
- All tests must pass without any changes to the test logic itself.
- The behavior of the application must remain identical.
- Manually review the diff to confirm that the only changes were moving code into helper functions and that no logic was accidentally altered.
