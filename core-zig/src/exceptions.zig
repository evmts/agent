const std = @import("std");

/// Core error types
pub const CoreError = error{
    NotFound,
    InvalidOperation,
    PermissionDenied,
    Validation,
    Timeout,
    Internal,
    OutOfMemory,
    Cancelled,
};

/// Error with context
pub const ErrorWithContext = struct {
    err: CoreError,
    message: []const u8,
    code: ?[]const u8 = null,

    pub fn notFound(message: []const u8) ErrorWithContext {
        return .{ .err = CoreError.NotFound, .message = message, .code = "NOT_FOUND" };
    }

    pub fn invalidOperation(message: []const u8) ErrorWithContext {
        return .{ .err = CoreError.InvalidOperation, .message = message, .code = "INVALID_OPERATION" };
    }

    pub fn permissionDenied(message: []const u8) ErrorWithContext {
        return .{ .err = CoreError.PermissionDenied, .message = message, .code = "PERMISSION_DENIED" };
    }

    pub fn validation(message: []const u8) ErrorWithContext {
        return .{ .err = CoreError.Validation, .message = message, .code = "VALIDATION_ERROR" };
    }

    pub fn timeout(message: []const u8) ErrorWithContext {
        return .{ .err = CoreError.Timeout, .message = message, .code = "TIMEOUT" };
    }

    pub fn internal(message: []const u8) ErrorWithContext {
        return .{ .err = CoreError.Internal, .message = message, .code = "INTERNAL_ERROR" };
    }

    pub fn cancelled(message: []const u8) ErrorWithContext {
        return .{ .err = CoreError.Cancelled, .message = message, .code = "CANCELLED" };
    }
};

test "ErrorWithContext creates proper errors" {
    const err = ErrorWithContext.notFound("Session not found");
    try std.testing.expectEqual(CoreError.NotFound, err.err);
    try std.testing.expectEqualStrings("Session not found", err.message);
    try std.testing.expectEqualStrings("NOT_FOUND", err.code.?);
}
