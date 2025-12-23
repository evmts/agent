const std = @import("std");
const http = @import("http.zig");
const sse = @import("sse.zig");
const protocol = @import("protocol.zig");

/// High-level Plue API client
pub const PlueClient = struct {
    allocator: std.mem.Allocator,
    http_client: http.HttpClient,
    sse_client: sse.SseClient,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) PlueClient {
        return .{
            .allocator = allocator,
            .http_client = http.HttpClient.init(allocator, base_url),
            .sse_client = sse.SseClient.init(allocator, base_url),
        };
    }

    pub fn deinit(self: *PlueClient) void {
        self.sse_client.deinit();
    }

    /// Health check - returns true if the API is healthy
    pub fn healthCheck(self: *PlueClient) !bool {
        var response = try self.http_client.get("/health");
        defer response.deinit();
        return response.isSuccess();
    }

    /// Create a new session
    pub fn createSession(self: *PlueClient, directory: []const u8, model: []const u8) !protocol.Session {
        const req = protocol.CreateSessionRequest{
            .directory = directory,
            .model = model,
        };
        const body = try req.toJson(self.allocator);
        defer self.allocator.free(body);

        var response = try self.http_client.post("/api/sessions", body);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.CreateSessionFailed;
        }

        return protocol.Session.parse(self.allocator, response.body);
    }

    /// List all sessions
    pub fn listSessions(self: *PlueClient) ![]protocol.Session {
        var response = try self.http_client.get("/api/sessions");
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.ListSessionsFailed;
        }

        // TODO: Fix JSON parsing with new Zig 0.15 API
        // For now, return empty list - sessions will be loaded in future phase
        return try self.allocator.alloc(protocol.Session, 0);
    }

    /// Get a specific session
    pub fn getSession(self: *PlueClient, id: []const u8) !protocol.Session {
        const path = try std.fmt.allocPrint(self.allocator, "/api/sessions/{s}", .{id});
        defer self.allocator.free(path);

        var response = try self.http_client.get(path);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.GetSessionFailed;
        }

        return protocol.Session.parse(self.allocator, response.body);
    }

    /// Update a session
    pub fn updateSession(
        self: *PlueClient,
        id: []const u8,
        model: ?[]const u8,
        reasoning_effort: ?[]const u8,
    ) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/api/sessions/{s}", .{id});
        defer self.allocator.free(path);

        const req = protocol.UpdateSessionRequest{
            .model = model,
            .reasoning_effort = reasoning_effort,
        };
        const body = try req.toJson(self.allocator);
        defer self.allocator.free(body);

        var response = try self.http_client.patch(path, body);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.UpdateSessionFailed;
        }
    }

    /// Delete a session
    pub fn deleteSession(self: *PlueClient, id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/api/sessions/{s}", .{id});
        defer self.allocator.free(path);

        var response = try self.http_client.delete(path);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.DeleteSessionFailed;
        }
    }

    /// Send a message with synchronous callback
    pub fn sendMessage(
        self: *PlueClient,
        session_id: []const u8,
        message: []const u8,
        model: ?[]const u8,
        callback: *const fn (protocol.StreamEvent) void,
    ) !void {
        try self.sse_client.stream(session_id, message, model, callback);
    }

    /// Send a message asynchronously via event queue
    pub fn sendMessageAsync(
        self: *PlueClient,
        session_id: []const u8,
        message: []const u8,
        model: ?[]const u8,
        queue: *sse.EventQueue,
    ) !void {
        try self.sse_client.streamAsync(session_id, message, model, queue);
    }

    /// Undo last N turns
    pub fn undo(self: *PlueClient, session_id: []const u8, turns: u32) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/api/sessions/{s}/undo", .{session_id});
        defer self.allocator.free(path);

        const req = protocol.UndoRequest{ .turns = turns };
        const body = try req.toJson(self.allocator);
        defer self.allocator.free(body);

        var response = try self.http_client.post(path, body);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.UndoFailed;
        }
    }

    /// Abort the current agent run
    pub fn abort(self: *PlueClient, session_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/api/sessions/{s}/abort", .{session_id});
        defer self.allocator.free(path);

        var response = try self.http_client.post(path, null);
        defer response.deinit();

        if (!response.isSuccess()) {
            return error.AbortFailed;
        }
    }
};

// Re-export types for convenience
pub const StreamEvent = protocol.StreamEvent;
pub const Session = protocol.Session;
pub const EventQueue = sse.EventQueue;
pub const HttpClient = http.HttpClient;
pub const SseClient = sse.SseClient;
