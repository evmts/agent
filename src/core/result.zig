const std = @import("std");

/// Native Zig error handling utilities and patterns
/// 
/// Zig provides native error handling with error unions (ErrorType!ReturnType)
/// - Use `try` operator (equivalent to Rust's `?` operator)
/// - Use `catch unreachable` (equivalent to Rust's `unwrap()`)
/// - Use `catch default_value` (equivalent to Rust's `unwrap_or()`)
/// - Use `catch |err| { ... }` for error handling
///
/// Examples:
///   var result: PlueError!u32 = getValue();
///   var value = try result;              // Propagate error
///   var value = result catch unreachable; // Panic on error (unwrap)
///   var value = result catch 0;          // Use default on error (unwrap_or)
///   var value = result catch |err| blk: { // Handle error
///       std.log.err("Error: {}", .{err});
///       break :blk 0;
///   };

/// Comprehensive error types for Plue application
pub const PlueError = error{
    OutOfMemory,
    InvalidState,
    InvalidInput,
    NetworkError,
    ParseError,
    CryptoError,
    IoError,
    Timeout,
    PermissionDenied,
    NotFound,
    AlreadyExists,
    Cancelled,
    Unknown,
};

/// Enhanced error context for better debugging and logging
pub const ErrorContext = struct {
    code: PlueError,
    message: []const u8,
    file: []const u8,
    line: u32,
    
    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            "{s}:{d} - {s}: {s}",
            .{ self.file, self.line, @errorName(self.code), self.message },
        );
    }
};

/// Create error with context information
pub fn errorWithContext(
    code: PlueError,
    message: []const u8,
    src: std.builtin.SourceLocation,
) ErrorContext {
    return .{
        .code = code,
        .message = message,
        .file = src.file,
        .line = src.line,
    };
}

/// Utility functions for working with Zig's native error unions
pub const ErrorUtils = struct {
    /// Convert error union to optional, logging errors
    pub fn toOptional(comptime T: type, result: anyerror!T) ?T {
        return result catch |err| {
            std.log.err("Error occurred: {}", .{err});
            return null;
        };
    }
    
    /// Convert error union to value with default, logging errors
    pub fn withDefault(comptime T: type, result: anyerror!T, default: T) T {
        return result catch |err| {
            std.log.warn("Using default value due to error: {}", .{err});
            return default;
        };
    }
    
    /// Map error union to different value type
    pub fn map(
        comptime T: type,
        comptime U: type,
        result: anyerror!T,
        mapper: *const fn (T) U,
    ) anyerror!U {
        const value = try result;
        return mapper(value);
    }
    
    /// Chain error unions (flatMap equivalent)
    pub fn chain(
        comptime T: type,
        comptime U: type,
        result: anyerror!T,
        chainer: *const fn (T) anyerror!U,
    ) anyerror!U {
        const value = try result;
        return try chainer(value);
    }
    
    /// Collect multiple error unions into a single result
    pub fn collect(comptime T: type, allocator: std.mem.Allocator, results: []const anyerror!T) anyerror![]T {
        var values = try allocator.alloc(T, results.len);
        errdefer allocator.free(values);
        
        for (results, 0..) |result, i| {
            values[i] = try result;
        }
        
        return values;
    }
};