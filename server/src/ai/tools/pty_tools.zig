const std = @import("std");
const types = @import("../types.zig");
const pty = @import("../../websocket/pty.zig");

// ============================================================================
// Unified Exec - Create and execute in a PTY session
// ============================================================================

pub const UnifiedExecParams = struct {
    cmd: []const u8,
    workdir: ?[]const u8 = null,
    shell: ?[]const u8 = null,
    yield_time_ms: u32 = 100,
    max_output_tokens: u32 = 4000,
};

pub const UnifiedExecResult = struct {
    success: bool,
    session_id: ?[]const u8 = null,
    output: ?[]const u8 = null,
    error_msg: ?[]const u8 = null,
    running: bool = false,
    exit_code: ?u8 = null,
};

pub fn unifiedExecImpl(
    allocator: std.mem.Allocator,
    params: UnifiedExecParams,
    ctx: types.ToolContext,
) !UnifiedExecResult {
    const workdir = params.workdir orelse ctx.working_dir;

    // Create PTY session
    const session = ctx.pty_manager.createSession(params.cmd, workdir) catch |err| {
        return UnifiedExecResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };

    // Read initial output with yield time
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const timeout_ns: i64 = @as(i64, params.yield_time_ms) * std.time.ns_per_ms;
    const start = std.time.nanoTimestamp();

    while (std.time.nanoTimestamp() - start < timeout_ns) {
        if (session.read()) |maybe_data| {
            if (maybe_data) |data| {
                try output.appendSlice(allocator, data);
            }
        } else |_| {
            // No data yet
        }
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    // Check if still running
    const running = session.running;

    return UnifiedExecResult{
        .success = true,
        .session_id = session.id,
        .output = try output.toOwnedSlice(allocator),
        .running = running,
    };
}

// ============================================================================
// Write Stdin - Send input to a running PTY session
// ============================================================================

pub const WriteStdinParams = struct {
    session_id: []const u8,
    chars: []const u8,
    yield_time_ms: u32 = 100,
    max_output_tokens: u32 = 4000,
};

pub const WriteStdinResult = struct {
    success: bool,
    output: ?[]const u8 = null,
    error_msg: ?[]const u8 = null,
    running: bool = false,
};

pub fn writeStdinImpl(
    allocator: std.mem.Allocator,
    params: WriteStdinParams,
    ctx: types.ToolContext,
) !WriteStdinResult {
    // Get session
    const session = ctx.pty_manager.getSession(params.session_id) catch {
        return WriteStdinResult{
            .success = false,
            .error_msg = "Session not found",
        };
    };

    // Write to stdin
    session.write(params.chars) catch |err| {
        return WriteStdinResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };

    // Read output after write
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const timeout_ns: i64 = @as(i64, params.yield_time_ms) * std.time.ns_per_ms;
    const start = std.time.nanoTimestamp();

    while (std.time.nanoTimestamp() - start < timeout_ns) {
        if (session.read()) |maybe_data| {
            if (maybe_data) |data| {
                try output.appendSlice(allocator, data);
            }
        } else |_| {
            // No data yet
        }
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    return WriteStdinResult{
        .success = true,
        .output = try output.toOwnedSlice(allocator),
        .running = session.running,
    };
}

// ============================================================================
// Close PTY Session
// ============================================================================

pub const ClosePtyParams = struct {
    session_id: []const u8,
};

pub const ClosePtyResult = struct {
    success: bool,
    error_msg: ?[]const u8 = null,
};

pub fn closePtySessionImpl(
    params: ClosePtyParams,
    ctx: types.ToolContext,
) ClosePtyResult {
    ctx.pty_manager.closeSession(params.session_id) catch {
        return ClosePtyResult{
            .success = false,
            .error_msg = "Session not found",
        };
    };

    return ClosePtyResult{
        .success = true,
    };
}

// ============================================================================
// List PTY Sessions
// ============================================================================

pub const PtySessionInfo = struct {
    id: []const u8,
    command: []const u8,
    workdir: []const u8,
    running: bool,
};

pub const ListPtyResult = struct {
    success: bool,
    sessions: []PtySessionInfo = &.{},
    error_msg: ?[]const u8 = null,
};

pub fn listPtySessionsImpl(
    allocator: std.mem.Allocator,
    ctx: types.ToolContext,
) !ListPtyResult {
    var sessions: std.ArrayList(PtySessionInfo) = .{};
    defer sessions.deinit(allocator);

    // Get all sessions from manager
    var iter = ctx.pty_manager.sessions.iterator();
    while (iter.next()) |entry| {
        const session = entry.value_ptr.*;
        try sessions.append(allocator, .{
            .id = session.id,
            .command = session.command,
            .workdir = session.workdir,
            .running = session.running,
        });
    }

    return ListPtyResult{
        .success = true,
        .sessions = try sessions.toOwnedSlice(allocator),
    };
}

// ============================================================================
// Schema Creators
// ============================================================================

pub fn createUnifiedExecSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    var cmd_prop = std.json.ObjectMap.init(allocator);
    try cmd_prop.put("type", std.json.Value{ .string = "string" });
    try cmd_prop.put("description", std.json.Value{ .string = "Command to execute" });
    try properties.put("cmd", std.json.Value{ .object = cmd_prop });

    var workdir_prop = std.json.ObjectMap.init(allocator);
    try workdir_prop.put("type", std.json.Value{ .string = "string" });
    try workdir_prop.put("description", std.json.Value{ .string = "Working directory" });
    try properties.put("workdir", std.json.Value{ .object = workdir_prop });

    try schema.put("properties", std.json.Value{ .object = properties });

    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "cmd" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

pub fn createWriteStdinSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    var session_prop = std.json.ObjectMap.init(allocator);
    try session_prop.put("type", std.json.Value{ .string = "string" });
    try session_prop.put("description", std.json.Value{ .string = "PTY session ID" });
    try properties.put("session_id", std.json.Value{ .object = session_prop });

    var chars_prop = std.json.ObjectMap.init(allocator);
    try chars_prop.put("type", std.json.Value{ .string = "string" });
    try chars_prop.put("description", std.json.Value{ .string = "Characters to send" });
    try properties.put("chars", std.json.Value{ .object = chars_prop });

    try schema.put("properties", std.json.Value{ .object = properties });

    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "session_id" });
    try required.append(std.json.Value{ .string = "chars" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

pub fn createClosePtySchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    var session_prop = std.json.ObjectMap.init(allocator);
    try session_prop.put("type", std.json.Value{ .string = "string" });
    try session_prop.put("description", std.json.Value{ .string = "PTY session ID to close" });
    try properties.put("session_id", std.json.Value{ .object = session_prop });

    try schema.put("properties", std.json.Value{ .object = properties });

    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "session_id" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

pub fn createListPtySchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });
    try schema.put("properties", std.json.Value{ .object = std.json.ObjectMap.init(allocator) });

    return std.json.Value{ .object = schema };
}

// ============================================================================
// Helper for cleaning up JSON values in tests
// ============================================================================

fn freeJsonValue(allocator: std.mem.Allocator, value: *std.json.Value) void {
    switch (value.*) {
        .object => |*obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                freeJsonValue(allocator, entry.value_ptr);
            }
            obj.deinit();
        },
        .array => |*arr| {
            for (arr.items) |*item| {
                freeJsonValue(allocator, item);
            }
            arr.deinit();
        },
        else => {},
    }
}

// ============================================================================
// Tests
// ============================================================================

test "UnifiedExecParams defaults" {
    const params = UnifiedExecParams{
        .cmd = "ls -la",
    };

    try std.testing.expectEqualStrings("ls -la", params.cmd);
    try std.testing.expect(params.workdir == null);
    try std.testing.expect(params.shell == null);
    try std.testing.expectEqual(@as(u32, 100), params.yield_time_ms);
    try std.testing.expectEqual(@as(u32, 4000), params.max_output_tokens);
}

test "UnifiedExecParams with options" {
    const params = UnifiedExecParams{
        .cmd = "npm test",
        .workdir = "/home/user/project",
        .shell = "/bin/zsh",
        .yield_time_ms = 500,
        .max_output_tokens = 8000,
    };

    try std.testing.expectEqualStrings("npm test", params.cmd);
    try std.testing.expectEqualStrings("/home/user/project", params.workdir.?);
    try std.testing.expectEqualStrings("/bin/zsh", params.shell.?);
    try std.testing.expectEqual(@as(u32, 500), params.yield_time_ms);
    try std.testing.expectEqual(@as(u32, 8000), params.max_output_tokens);
}

test "UnifiedExecResult success" {
    const result = UnifiedExecResult{
        .success = true,
        .session_id = "session-123",
        .output = "command output",
        .running = true,
    };

    try std.testing.expect(result.success);
    try std.testing.expectEqualStrings("session-123", result.session_id.?);
    try std.testing.expect(result.output != null);
    try std.testing.expect(result.running);
    try std.testing.expect(result.error_msg == null);
}

test "UnifiedExecResult error" {
    const result = UnifiedExecResult{
        .success = false,
        .error_msg = "Failed to spawn process",
    };

    try std.testing.expect(!result.success);
    try std.testing.expect(result.error_msg != null);
    try std.testing.expect(result.session_id == null);
}

test "WriteStdinParams" {
    const params = WriteStdinParams{
        .session_id = "session-abc",
        .chars = "hello\n",
    };

    try std.testing.expectEqualStrings("session-abc", params.session_id);
    try std.testing.expectEqualStrings("hello\n", params.chars);
    try std.testing.expectEqual(@as(u32, 100), params.yield_time_ms);
}

test "WriteStdinResult success" {
    const result = WriteStdinResult{
        .success = true,
        .output = "response output",
        .running = true,
    };

    try std.testing.expect(result.success);
    try std.testing.expect(result.output != null);
    try std.testing.expect(result.running);
}

test "WriteStdinResult error" {
    const result = WriteStdinResult{
        .success = false,
        .error_msg = "Session not found",
    };

    try std.testing.expect(!result.success);
    try std.testing.expectEqualStrings("Session not found", result.error_msg.?);
}

test "ClosePtyParams" {
    const params = ClosePtyParams{
        .session_id = "session-xyz",
    };

    try std.testing.expectEqualStrings("session-xyz", params.session_id);
}

test "ClosePtyResult success" {
    const result = ClosePtyResult{
        .success = true,
    };

    try std.testing.expect(result.success);
    try std.testing.expect(result.error_msg == null);
}

test "ClosePtyResult error" {
    const result = ClosePtyResult{
        .success = false,
        .error_msg = "Session not found",
    };

    try std.testing.expect(!result.success);
    try std.testing.expect(result.error_msg != null);
}

test "PtySessionInfo" {
    const info = PtySessionInfo{
        .id = "sess-1",
        .command = "bash",
        .workdir = "/home/user",
        .running = true,
    };

    try std.testing.expectEqualStrings("sess-1", info.id);
    try std.testing.expectEqualStrings("bash", info.command);
    try std.testing.expectEqualStrings("/home/user", info.workdir);
    try std.testing.expect(info.running);
}

test "ListPtyResult success" {
    const result = ListPtyResult{
        .success = true,
        .sessions = &.{},
    };

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(usize, 0), result.sessions.len);
}

test "createUnifiedExecSchema" {
    const allocator = std.testing.allocator;

    var schema = try createUnifiedExecSchema(allocator);
    defer freeJsonValue(allocator, &schema);

    try std.testing.expect(schema == .object);

    const type_val = schema.object.get("type").?;
    try std.testing.expectEqualStrings("object", type_val.string);

    const props = schema.object.get("properties").?;
    try std.testing.expect(props.object.get("cmd") != null);
    try std.testing.expect(props.object.get("workdir") != null);

    const required = schema.object.get("required").?;
    try std.testing.expect(required == .array);
    try std.testing.expectEqual(@as(usize, 1), required.array.items.len);
}

test "createWriteStdinSchema" {
    const allocator = std.testing.allocator;

    var schema = try createWriteStdinSchema(allocator);
    defer freeJsonValue(allocator, &schema);

    try std.testing.expect(schema == .object);

    const props = schema.object.get("properties").?;
    try std.testing.expect(props.object.get("session_id") != null);
    try std.testing.expect(props.object.get("chars") != null);

    const required = schema.object.get("required").?;
    try std.testing.expect(required == .array);
    try std.testing.expectEqual(@as(usize, 2), required.array.items.len);
}

test "createClosePtySchema" {
    const allocator = std.testing.allocator;

    var schema = try createClosePtySchema(allocator);
    defer freeJsonValue(allocator, &schema);

    try std.testing.expect(schema == .object);

    const props = schema.object.get("properties").?;
    try std.testing.expect(props.object.get("session_id") != null);

    const required = schema.object.get("required").?;
    try std.testing.expect(required == .array);
    try std.testing.expectEqual(@as(usize, 1), required.array.items.len);
}

test "createListPtySchema" {
    const allocator = std.testing.allocator;

    var schema = try createListPtySchema(allocator);
    defer freeJsonValue(allocator, &schema);

    try std.testing.expect(schema == .object);

    const type_val = schema.object.get("type").?;
    try std.testing.expectEqualStrings("object", type_val.string);

    // List has empty properties (no required parameters)
    const props = schema.object.get("properties").?;
    try std.testing.expect(props == .object);
}
