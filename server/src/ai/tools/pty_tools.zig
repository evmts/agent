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
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    const timeout_ns: i64 = @as(i64, params.yield_time_ms) * std.time.ns_per_ms;
    const start = std.time.nanoTimestamp();

    while (std.time.nanoTimestamp() - start < timeout_ns) {
        if (session.read()) |data| {
            try output.appendSlice(data);
        } else |_| {
            // No data yet
        }
        std.time.sleep(10 * std.time.ns_per_ms);
    }

    // Check if still running
    const running = session.isRunning();

    return UnifiedExecResult{
        .success = true,
        .session_id = session.id,
        .output = try output.toOwnedSlice(),
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
    const session = ctx.pty_manager.getSession(params.session_id) orelse {
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
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    const timeout_ns: i64 = @as(i64, params.yield_time_ms) * std.time.ns_per_ms;
    const start = std.time.nanoTimestamp();

    while (std.time.nanoTimestamp() - start < timeout_ns) {
        if (session.read()) |data| {
            try output.appendSlice(data);
        } else |_| {
            // No data yet
        }
        std.time.sleep(10 * std.time.ns_per_ms);
    }

    return WriteStdinResult{
        .success = true,
        .output = try output.toOwnedSlice(),
        .running = session.isRunning(),
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
    const closed = ctx.pty_manager.closeSession(params.session_id);

    if (!closed) {
        return ClosePtyResult{
            .success = false,
            .error_msg = "Session not found",
        };
    }

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
    created_at: i64,
    last_activity: i64,
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
    var sessions = std.ArrayList(PtySessionInfo).init(allocator);
    defer sessions.deinit();

    // Get all sessions from manager
    var iter = ctx.pty_manager.sessions.iterator();
    while (iter.next()) |entry| {
        const session = entry.value_ptr.*;
        try sessions.append(.{
            .id = session.id,
            .command = session.command,
            .workdir = session.workdir,
            .running = session.isRunning(),
            .created_at = session.created_at,
            .last_activity = session.last_activity,
        });
    }

    return ListPtyResult{
        .success = true,
        .sessions = try sessions.toOwnedSlice(),
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
