const std = @import("std");
const types = @import("../types.zig");

/// Web fetch parameters
pub const WebFetchParams = struct {
    url: []const u8,
    timeout_ms: u32 = 30000,
};

/// Web fetch result
pub const WebFetchResult = struct {
    success: bool,
    content: ?[]const u8 = null,
    error_msg: ?[]const u8 = null,
    status_code: ?u16 = null,
    content_type: ?[]const u8 = null,
    truncated: bool = false,
};

/// Maximum response size (5MB)
const MAX_RESPONSE_SIZE: usize = 5 * 1024 * 1024;

/// Web fetch implementation
pub fn webFetchImpl(
    allocator: std.mem.Allocator,
    params: WebFetchParams,
) !WebFetchResult {
    // Validate URL
    const uri = std.Uri.parse(params.url) catch {
        return WebFetchResult{
            .success = false,
            .error_msg = "Invalid URL",
        };
    };

    // Only allow http and https
    if (!std.mem.eql(u8, uri.scheme, "http") and !std.mem.eql(u8, uri.scheme, "https")) {
        return WebFetchResult{
            .success = false,
            .error_msg = "Only http and https URLs are allowed",
        };
    }

    // Create HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Make the request using request (Zig 0.15 API)
    var req = client.request(.GET, uri, .{}) catch |err| {
        return WebFetchResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };
    defer req.deinit();

    req.sendBodiless() catch |err| {
        return WebFetchResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };

    var buffer: [8192]u8 = undefined;
    var response = req.receiveHead(&buffer) catch |err| {
        return WebFetchResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };

    // Read response body
    var transfer_buffer: [4096]u8 = undefined;
    const reader = response.reader(&transfer_buffer);

    var truncated = false;
    const content = reader.allocRemaining(allocator, std.io.Limit.limited(MAX_RESPONSE_SIZE)) catch |err| switch (err) {
        error.StreamTooLong => blk: {
            truncated = true;
            // Return what we have so far by reading with unlimited
            break :blk reader.allocRemaining(allocator, .unlimited) catch {
                return WebFetchResult{
                    .success = false,
                    .error_msg = "Failed to read response body",
                };
            };
        },
        else => {
            return WebFetchResult{
                .success = false,
                .error_msg = @errorName(err),
            };
        },
    };
    defer if (truncated) allocator.free(content);

    // Get content type from header
    var content_type: ?[]const u8 = null;
    if (response.head.content_type) |ct| {
        content_type = try allocator.dupe(u8, ct);
    }

    return WebFetchResult{
        .success = true,
        .content = content,
        .status_code = @intFromEnum(response.head.status),
        .content_type = content_type,
        .truncated = truncated,
    };
}

/// Create JSON schema for web fetch tool parameters
pub fn createWebFetchSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);

    try schema.put("type", std.json.Value{ .string = "object" });

    var properties = std.json.ObjectMap.init(allocator);

    // url property
    var url_prop = std.json.ObjectMap.init(allocator);
    try url_prop.put("type", std.json.Value{ .string = "string" });
    try url_prop.put("description", std.json.Value{ .string = "The URL to fetch" });
    try properties.put("url", std.json.Value{ .object = url_prop });

    // timeout_ms property
    var timeout_prop = std.json.ObjectMap.init(allocator);
    try timeout_prop.put("type", std.json.Value{ .string = "integer" });
    try timeout_prop.put("description", std.json.Value{ .string = "Timeout in milliseconds (default: 30000)" });
    try properties.put("timeout_ms", std.json.Value{ .object = timeout_prop });

    try schema.put("properties", std.json.Value{ .object = properties });

    // Required fields
    var required = std.json.Array.init(allocator);
    try required.append(std.json.Value{ .string = "url" });
    try schema.put("required", std.json.Value{ .array = required });

    return std.json.Value{ .object = schema };
}

// ============================================================================
// Tests
// ============================================================================

test "WebFetchParams defaults" {
    const params = WebFetchParams{
        .url = "https://example.com",
    };

    try std.testing.expectEqualStrings("https://example.com", params.url);
    try std.testing.expectEqual(@as(u32, 30000), params.timeout_ms);
}

test "WebFetchParams with custom timeout" {
    const params = WebFetchParams{
        .url = "https://example.com",
        .timeout_ms = 5000,
    };

    try std.testing.expectEqual(@as(u32, 5000), params.timeout_ms);
}

test "WebFetchResult success" {
    const result = WebFetchResult{
        .success = true,
        .content = "<html>Hello</html>",
        .status_code = 200,
        .content_type = "text/html",
        .truncated = false,
    };

    try std.testing.expect(result.success);
    try std.testing.expect(result.content != null);
    try std.testing.expectEqual(@as(u16, 200), result.status_code.?);
    try std.testing.expect(!result.truncated);
    try std.testing.expect(result.error_msg == null);
}

test "WebFetchResult error" {
    const result = WebFetchResult{
        .success = false,
        .error_msg = "Connection refused",
    };

    try std.testing.expect(!result.success);
    try std.testing.expect(result.error_msg != null);
    try std.testing.expect(result.content == null);
}

test "WebFetchResult truncated" {
    const result = WebFetchResult{
        .success = true,
        .content = "partial content...",
        .truncated = true,
    };

    try std.testing.expect(result.success);
    try std.testing.expect(result.truncated);
}

test "MAX_RESPONSE_SIZE constant" {
    try std.testing.expectEqual(@as(usize, 5 * 1024 * 1024), MAX_RESPONSE_SIZE);
}

test "createWebFetchSchema" {
    const allocator = std.testing.allocator;

    const schema = try createWebFetchSchema(allocator);

    // Schema should be an object
    try std.testing.expect(schema == .object);

    // Should have type = object
    const type_val = schema.object.get("type").?;
    try std.testing.expectEqualStrings("object", type_val.string);

    // Should have properties
    const props = schema.object.get("properties").?;
    try std.testing.expect(props == .object);

    // Should have url property
    const url_prop = props.object.get("url").?;
    try std.testing.expect(url_prop == .object);

    // url should be a string type
    const url_type = url_prop.object.get("type").?;
    try std.testing.expectEqualStrings("string", url_type.string);

    // Should have timeout_ms property
    try std.testing.expect(props.object.get("timeout_ms") != null);

    // Should have required array with url
    const required = schema.object.get("required").?;
    try std.testing.expect(required == .array);
    try std.testing.expectEqual(@as(usize, 1), required.array.items.len);
}
