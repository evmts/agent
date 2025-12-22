//! Input validation middleware
//!
//! Validates request body for potentially dangerous content like null bytes
//! and control characters that could lead to injection or data corruption.

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;

const log = std.log.scoped(.validation);

/// Configuration for input validation
pub const ValidationConfig = struct {
    /// Whether to reject null bytes in input
    reject_null_bytes: bool = true,
    /// Whether to reject control characters (0x00-0x1F except tab, newline, carriage return)
    reject_control_chars: bool = true,
    /// Maximum allowed request body size (0 = no limit)
    max_body_size: usize = 0,
};

/// Default validation configuration
pub const default_config = ValidationConfig{};

/// Check if a byte is a forbidden control character
/// Allows tab (0x09), newline (0x0A), carriage return (0x0D), and null (0x00) - null is checked separately
fn isForbiddenControlChar(c: u8) bool {
    return c < 0x20 and c != 0 and c != '\t' and c != '\n' and c != '\r';
}

/// Check if a sequence at position i is a JSON-escaped forbidden character (\u00XX)
/// Returns true if it's an escaped null byte or control character
fn isJsonEscapedForbiddenChar(input: []const u8, i: usize, config: ValidationConfig) bool {
    // Check for \uXXXX pattern
    if (i + 5 >= input.len) return false;
    if (input[i] != '\\' or input[i + 1] != 'u') return false;

    // Parse the hex digits
    const hex = input[i + 2 .. i + 6];
    const value = std.fmt.parseInt(u16, hex, 16) catch return false;

    // Check if it's a null byte
    if (config.reject_null_bytes and value == 0) {
        return true;
    }

    // Check if it's a forbidden control character (0x00-0x1F except tab, newline, CR)
    if (config.reject_control_chars and value < 0x20) {
        // Allow tab (0x09), newline (0x0A), carriage return (0x0D)
        if (value != 0x09 and value != 0x0A and value != 0x0D) {
            return true;
        }
    }

    return false;
}

/// Validate input bytes for null bytes and control characters
/// Checks both raw bytes and JSON-escaped sequences (\u0000)
/// Returns an error message if validation fails, null if valid
pub fn validateInput(input: []const u8, config: ValidationConfig) ?[]const u8 {
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];

        // Check raw null byte
        if (config.reject_null_bytes and c == 0) {
            log.warn("Null byte found at position {d}", .{i});
            return "Request contains null bytes";
        }

        // Check raw control characters
        if (config.reject_control_chars and isForbiddenControlChar(c)) {
            log.warn("Control character 0x{X:0>2} found at position {d}", .{ c, i });
            return "Request contains invalid control characters";
        }

        // Check for JSON-escaped forbidden characters (\u0000, \u0001, etc.)
        if (c == '\\' and isJsonEscapedForbiddenChar(input, i, config)) {
            log.warn("JSON-escaped forbidden character at position {d}", .{i});
            return "Request contains forbidden escape sequences";
        }
    }
    return null;
}

/// Middleware that validates request body
/// Returns true if valid, false if validation failed (response already set)
pub fn validationMiddleware(
    config: ValidationConfig,
) fn (*Context, *httpz.Request, *httpz.Response) anyerror!bool {
    return struct {
        fn handler(_: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
            log.debug("Validation middleware called for method: {s}", .{@tagName(req.method)});

            // Only validate POST/PUT/PATCH requests with body
            if (req.method != .POST and req.method != .PUT and req.method != .PATCH) {
                log.debug("Skipping validation for non-mutating method", .{});
                return true;
            }

            // Get body if present
            const body = req.body() orelse {
                log.debug("No body present, skipping validation", .{});
                return true;
            };

            log.debug("Validating body of {d} bytes", .{body.len});

            // Check body size limit
            if (config.max_body_size > 0 and body.len > config.max_body_size) {
                res.status = 413;
                res.content_type = .JSON;
                try res.writer().writeAll("{\"error\":\"Request body too large\"}");
                return false;
            }

            // Validate content
            if (validateInput(body, config)) |error_msg| {
                log.info("Validation failed: {s}", .{error_msg});
                res.status = 400;
                res.content_type = .JSON;
                // Use a fixed error message for security
                try res.writer().writeAll("{\"error\":\"Invalid input: request contains forbidden characters\"}");
                return false;
            }

            return true;
        }
    }.handler;
}

// ============================================================================
// Tests
// ============================================================================

test "validate input with null byte" {
    const config = ValidationConfig{};

    // Valid input
    try std.testing.expect(validateInput("hello world", config) == null);
    try std.testing.expect(validateInput("hello\tworld", config) == null);
    try std.testing.expect(validateInput("hello\nworld", config) == null);
    try std.testing.expect(validateInput("hello\r\nworld", config) == null);

    // Invalid - raw null byte
    try std.testing.expect(validateInput("hello\x00world", config) != null);
    try std.testing.expect(validateInput("\x00", config) != null);
    try std.testing.expect(validateInput("test\x00repo", config) != null);

    // Invalid - raw control characters
    try std.testing.expect(validateInput("hello\x01world", config) != null);
    try std.testing.expect(validateInput("hello\x02world", config) != null);
    try std.testing.expect(validateInput("hello\x1Fworld", config) != null);

    // Invalid - JSON-escaped null byte
    try std.testing.expect(validateInput("test\\u0000repo", config) != null);
    try std.testing.expect(validateInput("{\"name\":\"test\\u0000repo\"}", config) != null);

    // Invalid - JSON-escaped control characters
    try std.testing.expect(validateInput("test\\u0001repo", config) != null);
    try std.testing.expect(validateInput("test\\u001Frepo", config) != null);

    // Valid - JSON-escaped allowed characters (tab, newline, CR)
    try std.testing.expect(validateInput("test\\u0009repo", config) == null);
    try std.testing.expect(validateInput("test\\u000Arepo", config) == null);
    try std.testing.expect(validateInput("test\\u000Drepo", config) == null);
}

test "validate input with disabled null byte check" {
    const config = ValidationConfig{ .reject_null_bytes = false };

    // Null bytes allowed
    try std.testing.expect(validateInput("hello\x00world", config) == null);

    // Control chars still rejected
    try std.testing.expect(validateInput("hello\x01world", config) != null);
}

test "validate input with disabled control char check" {
    const config = ValidationConfig{ .reject_control_chars = false };

    // Null bytes still rejected
    try std.testing.expect(validateInput("hello\x00world", config) != null);

    // Control chars allowed
    try std.testing.expect(validateInput("hello\x01world", config) == null);
}
