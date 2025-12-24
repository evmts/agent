//! Edge Notifier Service
//!
//! Sends push-based cache invalidation notifications to Cloudflare Durable Objects.
//! Notifies the edge cache when SQL data or git repository state changes.

const std = @import("std");
const json = @import("../lib/json.zig");

const log = std.log.scoped(.edge_notifier);

/// Types of invalidation events
pub const InvalidationType = enum {
    sql,
    git,

    pub fn toString(self: InvalidationType) []const u8 {
        return switch (self) {
            .sql => "sql",
            .git => "git",
        };
    }
};

/// Invalidation message sent to Durable Objects
pub const InvalidationMessage = struct {
    type: InvalidationType,
    table: ?[]const u8 = null,
    repo_key: ?[]const u8 = null,
    merkle_root: ?[]const u8 = null,
    timestamp: i64,

    /// Serialize the message to JSON
    pub fn toJson(self: *const InvalidationMessage, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
        defer buffer.deinit(allocator);

        const writer = buffer.writer(allocator);

        try json.beginObject(writer);

        // type field
        try json.writeKey(writer, "type");
        try json.writeString(writer, self.type.toString());

        // timestamp field
        try json.writeSeparator(writer);
        try json.writeKey(writer, "timestamp");
        try json.writeNumber(writer, self.timestamp);

        // table field (for SQL invalidations)
        if (self.table) |table| {
            try json.writeSeparator(writer);
            try json.writeKey(writer, "table");
            try json.writeString(writer, table);
        }

        // repo_key field
        if (self.repo_key) |repo_key| {
            try json.writeSeparator(writer);
            try json.writeKey(writer, "repo_key");
            try json.writeString(writer, repo_key);
        }

        // merkle_root field (for git invalidations)
        if (self.merkle_root) |merkle_root| {
            try json.writeSeparator(writer);
            try json.writeKey(writer, "merkle_root");
            try json.writeString(writer, merkle_root);
        }

        try json.endObject(writer);

        return try buffer.toOwnedSlice(allocator);
    }
};

/// Edge Notifier Service
pub const EdgeNotifier = struct {
    allocator: std.mem.Allocator,
    edge_base_url: []const u8,
    push_secret: []const u8,

    /// Initialize the edge notifier
    pub fn init(allocator: std.mem.Allocator, edge_base_url: []const u8, push_secret: []const u8) EdgeNotifier {
        return .{
            .allocator = allocator,
            .edge_base_url = edge_base_url,
            .push_secret = push_secret,
        };
    }

    /// Notify the edge of a SQL table change
    /// This sends to the global Durable Object
    pub fn notifySqlChange(self: *EdgeNotifier, table: []const u8, repo_key: ?[]const u8) !void {
        const timestamp = std.time.timestamp();

        const msg = InvalidationMessage{
            .type = .sql,
            .table = table,
            .repo_key = repo_key,
            .timestamp = timestamp,
        };

        try self.sendInvalidation("global", &msg);
    }

    /// Notify the edge of a git repository change
    /// This sends to a repository-specific Durable Object
    pub fn notifyGitChange(self: *EdgeNotifier, repo_key: []const u8, merkle_root: []const u8) !void {
        const timestamp = std.time.timestamp();

        const msg = InvalidationMessage{
            .type = .git,
            .repo_key = repo_key,
            .merkle_root = merkle_root,
            .timestamp = timestamp,
        };

        // Build DO name: "repo:{owner}/{repo}"
        const do_name = try std.fmt.allocPrint(self.allocator, "repo:{s}", .{repo_key});
        defer self.allocator.free(do_name);

        try self.sendInvalidation(do_name, &msg);
    }

    /// Send an invalidation notification to a Durable Object
    /// Implements retry logic with exponential backoff
    fn sendInvalidation(self: *EdgeNotifier, do_name: []const u8, msg: *const InvalidationMessage) !void {
        // Skip if edge URL is not configured
        if (self.edge_base_url.len == 0) {
            log.debug("Edge URL not configured, skipping invalidation notification", .{});
            return;
        }

        // Build the URL: {edge_base_url}/do/{do_name}/invalidate
        const url = try std.fmt.allocPrint(self.allocator, "{s}/do/{s}/invalidate", .{ self.edge_base_url, do_name });
        defer self.allocator.free(url);

        // Serialize the message
        const json_body = try msg.toJson(self.allocator);
        defer self.allocator.free(json_body);

        log.debug("Sending invalidation to {s}: {s}", .{ url, json_body });

        // Retry logic: 3 attempts with exponential backoff (100ms, 200ms, 400ms)
        const max_attempts = 3;
        const base_delay_ms = 100;

        var attempt: u32 = 0;
        var last_error: ?anyerror = null;

        while (attempt < max_attempts) : (attempt += 1) {
            if (attempt > 0) {
                const delay_ms = base_delay_ms * (@as(u64, 1) << @intCast(attempt - 1));
                log.debug("Retrying invalidation (attempt {d}/{d}) after {d}ms", .{ attempt + 1, max_attempts, delay_ms });
                std.Thread.sleep(delay_ms * std.time.ns_per_ms);
            }

            // Send the request
            const result = self.sendHttpPost(url, json_body) catch |err| {
                log.warn("Failed to send invalidation (attempt {d}/{d}): {}", .{ attempt + 1, max_attempts, err });
                last_error = err;
                continue;
            };

            // Success
            log.info("Invalidation sent successfully to {s} (attempt {d}/{d})", .{ do_name, attempt + 1, max_attempts });
            return result;
        }

        // All retries failed
        if (last_error) |err| {
            log.err("Failed to send invalidation after {d} attempts: {}", .{ max_attempts, err });
            return err;
        }
    }

    /// Send an HTTP POST request
    /// This is a blocking operation
    fn sendHttpPost(self: *EdgeNotifier, url_str: []const u8, body: []const u8) !void {
        // Parse the URL
        const uri = std.Uri.parse(url_str) catch |err| {
            log.err("Failed to parse URL: {}", .{err});
            return error.InvalidUrl;
        };

        // Create HTTP client
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Set Authorization header with push secret
        var auth_value_buf: [256]u8 = undefined;
        const auth_value = try std.fmt.bufPrint(&auth_value_buf, "Bearer {s}", .{self.push_secret});

        // Build headers
        const headers_list = [_]std.http.Header{
            .{ .name = "authorization", .value = auth_value },
            .{ .name = "content-type", .value = "application/json" },
        };

        // Create a buffer to store the response
        var response_buf: [4096]u8 = undefined;
        var response_writer = std.io.fixedBufferStream(&response_buf);

        // Send the request using fetch
        const result = try client.fetch(.{
            .location = .{ .uri = uri },
            .method = .POST,
            .payload = body,
            .extra_headers = &headers_list,
            .response_writer = @ptrCast(&response_writer),
        });

        // Check status code
        if (result.status != .ok and result.status != .no_content) {
            log.warn("Edge invalidation returned non-OK status: {}", .{result.status});
            return error.InvalidationFailed;
        }

        const response_body = response_writer.getWritten();
        if (response_body.len > 0) {
            log.debug("Edge response: {s}", .{response_body});
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

test "InvalidationMessage SQL change serialization" {
    const allocator = std.testing.allocator;

    const msg = InvalidationMessage{
        .type = .sql,
        .table = "repositories",
        .repo_key = "user/repo",
        .timestamp = 1234567890,
    };

    const json_str = try msg.toJson(allocator);
    defer allocator.free(json_str);

    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"type\":\"sql\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"table\":\"repositories\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"repo_key\":\"user/repo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"timestamp\":1234567890") != null);
}

test "InvalidationMessage git change serialization" {
    const allocator = std.testing.allocator;

    const msg = InvalidationMessage{
        .type = .git,
        .repo_key = "alice/project",
        .merkle_root = "abc123def456",
        .timestamp = 9876543210,
    };

    const json_str = try msg.toJson(allocator);
    defer allocator.free(json_str);

    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"type\":\"git\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"repo_key\":\"alice/project\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"merkle_root\":\"abc123def456\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"timestamp\":9876543210") != null);
}
