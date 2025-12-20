//! JSON utilities for safe parsing and serialization.
//!
//! Uses std.json for proper handling of escaped characters and edge cases.

const std = @import("std");

const log = std.log.scoped(.json);

/// Parse a JSON string and extract a string field value.
/// Returns null if the field doesn't exist or isn't a string.
pub fn getString(allocator: std.mem.Allocator, json_str: []const u8, field: []const u8) !?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch |err| {
        log.debug("JSON parse error: {}", .{err});
        return null;
    };
    defer parsed.deinit();

    if (parsed.value != .object) return null;

    if (parsed.value.object.get(field)) |value| {
        if (value == .string) {
            return try allocator.dupe(u8, value.string);
        }
    }
    return null;
}

/// Parse a JSON string and extract an integer field value.
pub fn getInt(allocator: std.mem.Allocator, json_str: []const u8, field: []const u8) !?i64 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch |err| {
        log.debug("JSON parse error: {}", .{err});
        return null;
    };
    defer parsed.deinit();

    if (parsed.value != .object) return null;

    if (parsed.value.object.get(field)) |value| {
        if (value == .integer) {
            return value.integer;
        }
    }
    return null;
}

/// Parse a JSON string and extract a boolean field value.
pub fn getBool(allocator: std.mem.Allocator, json_str: []const u8, field: []const u8) !?bool {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch |err| {
        log.debug("JSON parse error: {}", .{err});
        return null;
    };
    defer parsed.deinit();

    if (parsed.value != .object) return null;

    if (parsed.value.object.get(field)) |value| {
        if (value == .bool) {
            return value.bool;
        }
    }
    return null;
}

/// Parse a JSON string and extract a string array field value.
pub fn getStringArray(allocator: std.mem.Allocator, json_str: []const u8, field: []const u8) !?[]const []const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch |err| {
        log.debug("JSON parse error: {}", .{err});
        return null;
    };
    defer parsed.deinit();

    if (parsed.value != .object) return null;

    if (parsed.value.object.get(field)) |value| {
        if (value == .array) {
            var result = std.ArrayList([]const u8){};
            errdefer {
                for (result.items) |item| allocator.free(item);
                result.deinit(allocator);
            }

            for (value.array.items) |item| {
                if (item == .string) {
                    try result.append(allocator, try allocator.dupe(u8, item.string));
                }
            }
            return try result.toOwnedSlice(allocator);
        }
    }
    return null;
}

/// Escape a string for JSON output.
/// Handles special characters: ", \, \n, \r, \t, and control characters.
pub fn escapeString(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    for (input) |c| {
        switch (c) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => {
                // Control characters (excluding \t=0x09, \n=0x0A, \r=0x0D) - encode as \u00XX
                try result.appendSlice(allocator, "\\u00");
                const hex = "0123456789abcdef";
                try result.append(allocator, hex[c >> 4]);
                try result.append(allocator, hex[c & 0x0F]);
            },
            else => try result.append(allocator, c),
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Write a JSON string value with proper escaping to a writer.
pub fn writeString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => {
                // Control characters (excluding \t=0x09, \n=0x0A, \r=0x0D) - encode as \u00XX
                try writer.writeAll("\\u00");
                const hex = "0123456789abcdef";
                try writer.writeByte(hex[c >> 4]);
                try writer.writeByte(hex[c & 0x0F]);
            },
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

/// Helper to start a JSON object.
pub fn beginObject(writer: anytype) !void {
    try writer.writeByte('{');
}

/// Helper to end a JSON object.
pub fn endObject(writer: anytype) !void {
    try writer.writeByte('}');
}

/// Helper to start a JSON array.
pub fn beginArray(writer: anytype) !void {
    try writer.writeByte('[');
}

/// Helper to end a JSON array.
pub fn endArray(writer: anytype) !void {
    try writer.writeByte(']');
}

/// Write a JSON key (with colon).
pub fn writeKey(writer: anytype, key: []const u8) !void {
    try writeString(writer, key);
    try writer.writeByte(':');
}

/// Write a JSON number value.
pub fn writeNumber(writer: anytype, value: anytype) !void {
    try writer.print("{d}", .{value});
}

/// Write a JSON boolean value.
pub fn writeBool(writer: anytype, value: bool) !void {
    try writer.writeAll(if (value) "true" else "false");
}

/// Write a JSON null value.
pub fn writeNull(writer: anytype) !void {
    try writer.writeAll("null");
}

/// Write a comma separator.
pub fn writeSeparator(writer: anytype) !void {
    try writer.writeByte(',');
}

/// Parse full JSON into a Value type for complex parsing needs.
pub fn parse(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(std.json.Value) {
    return try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
}

/// Stringify a value to JSON.
pub fn stringify(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return try std.json.stringifyAlloc(allocator, value, .{});
}

// =============================================================================
// Tests
// =============================================================================

test "escapeString handles special characters" {
    const allocator = std.testing.allocator;

    const result = try escapeString(allocator, "Hello \"World\"\nNew\\Line");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello \\\"World\\\"\\nNew\\\\Line", result);
}

test "getString extracts field" {
    const allocator = std.testing.allocator;

    const result = try getString(allocator, "{\"name\":\"John\",\"age\":30}", "name");
    defer if (result) |r| allocator.free(r);

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("John", result.?);
}

test "getString handles escaped quotes" {
    const allocator = std.testing.allocator;

    const result = try getString(allocator, "{\"message\":\"Hello \\\"World\\\"\"}", "message");
    defer if (result) |r| allocator.free(r);

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("Hello \"World\"", result.?);
}

test "getInt extracts integer field" {
    const allocator = std.testing.allocator;

    const result = try getInt(allocator, "{\"count\":42}", "count");

    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 42), result.?);
}

test "getBool extracts boolean field" {
    const allocator = std.testing.allocator;

    const result = try getBool(allocator, "{\"active\":true}", "active");

    try std.testing.expect(result != null);
    try std.testing.expect(result.?);
}
