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

    // Make the request
    var request = client.open(.GET, uri, .{
        .server_header_buffer = undefined,
    }) catch |err| {
        return WebFetchResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };
    defer request.deinit();

    request.send() catch |err| {
        return WebFetchResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };

    request.wait() catch |err| {
        return WebFetchResult{
            .success = false,
            .error_msg = @errorName(err),
        };
    };

    // Read response
    var body = std.ArrayList(u8).init(allocator);
    defer body.deinit();

    const reader = request.reader();
    var truncated = false;

    reader.readAllArrayList(&body, MAX_RESPONSE_SIZE) catch |err| switch (err) {
        error.StreamTooLong => {
            truncated = true;
        },
        else => {
            return WebFetchResult{
                .success = false,
                .error_msg = @errorName(err),
            };
        },
    };

    // Get content type from headers
    var content_type: ?[]const u8 = null;
    if (request.response.headers.getFirstValue("content-type")) |ct| {
        content_type = try allocator.dupe(u8, ct);
    }

    return WebFetchResult{
        .success = true,
        .content = try body.toOwnedSlice(),
        .status_code = @intFromEnum(request.response.status),
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
