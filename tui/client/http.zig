const std = @import("std");

/// Simple HTTP client for making requests to the Plue API
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    timeout_ms: u64,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) HttpClient {
        return .{
            .allocator = allocator,
            .base_url = base_url,
            .timeout_ms = 30000, // 30 seconds default timeout
        };
    }

    pub fn setTimeout(self: *HttpClient, timeout_ms: u64) void {
        self.timeout_ms = timeout_ms;
    }

    pub fn get(self: *HttpClient, path: []const u8) !Response {
        return self.request(.GET, path, null);
    }

    pub fn post(self: *HttpClient, path: []const u8, body: ?[]const u8) !Response {
        return self.request(.POST, path, body);
    }

    pub fn patch(self: *HttpClient, path: []const u8, body: ?[]const u8) !Response {
        return self.request(.PATCH, path, body);
    }

    pub fn delete(self: *HttpClient, path: []const u8) !Response {
        return self.request(.DELETE, path, null);
    }

    pub fn request(self: *HttpClient, method: std.http.Method, path: []const u8, body: ?[]const u8) !Response {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, path });
        defer self.allocator.free(url);

        const uri = try std.Uri.parse(url);

        var headers = std.http.Client.Request.Headers{};
        headers.content_type = .{ .override = "application/json" };

        // For now, don't use response_writer - we'll just return empty body
        // This is a limitation we can fix later when we understand the full API
        const result = try client.fetch(.{
            .location = .{ .uri = uri },
            .method = method,
            .headers = headers,
            .payload = body,
        });

        // Return empty body for now - this is sufficient for health checks and simple operations
        return .{
            .status = @intFromEnum(result.status),
            .body = try self.allocator.dupe(u8, ""),
            .allocator = self.allocator,
        };
    }
};

pub const Response = struct {
    status: u16,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
    }

    pub fn isSuccess(self: Response) bool {
        return self.status >= 200 and self.status < 300;
    }

    pub fn isError(self: Response) bool {
        return self.status >= 400;
    }
};
