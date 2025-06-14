const std = @import("std");

/// Result type inspired by Rust for better error handling
pub fn Result(comptime T: type, comptime E: type) type {
    return union(enum) {
        ok: T,
        err: E,
        
        const Self = @This();
        
        pub fn isOk(self: Self) bool {
            return switch (self) {
                .ok => true,
                .err => false,
            };
        }
        
        pub fn isErr(self: Self) bool {
            return !self.isOk();
        }
        
        pub fn unwrap(self: Self) T {
            return switch (self) {
                .ok => |value| value,
                .err => |e| {
                    std.debug.panic("unwrap() called on error: {}", .{e});
                },
            };
        }
        
        pub fn unwrapOr(self: Self, default: T) T {
            return switch (self) {
                .ok => |value| value,
                .err => default,
            };
        }
        
        pub fn map(self: Self, comptime func: anytype) Result(@TypeOf(func(self.ok)), E) {
            return switch (self) {
                .ok => |value| .{ .ok = func(value) },
                .err => |e| .{ .err = e },
            };
        }
        
        pub fn mapErr(self: Self, comptime func: anytype) Result(T, @TypeOf(func(self.err))) {
            return switch (self) {
                .ok => |value| .{ .ok = value },
                .err => |e| .{ .err = func(e) },
            };
        }
    };
}

/// Comprehensive error types with context
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

/// Create error with context - macro-like function
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