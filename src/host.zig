//! Host abstraction (dependency injection via vtable-like struct).
const std = @import("std");

const Allocator = std.mem.Allocator;

pub const HostError = Allocator.Error || error{ Unsupported, Io, NotFound, PermissionDenied };

pub const LogLevel = enum(u8) { err = 0, warn = 1, info = 2, debug = 3 };

/// Table of host-provided functions. Fields are optional; calling a missing
/// entry returns error.Unsupported.
pub const VTable = struct {
    log: ?*const fn (ctx: ?*anyopaque, level: LogLevel, msg: []const u8) HostError!void = null,
    read_file: ?*const fn (ctx: ?*anyopaque, path: []const u8, out: *[*]u8, out_len: *usize, alloc: Allocator) HostError!void = null,
    write_file: ?*const fn (ctx: ?*anyopaque, path: []const u8, bytes: []const u8) HostError!void = null,
};

/// Host handle used by libsmithers.
pub const Host = struct {
    const Self = @This();
    vtable: VTable = .{},
    ctx: ?*anyopaque = null,

    pub fn log(self: *const Self, level: LogLevel, msg: []const u8) HostError!void {
        if (self.vtable.log) |f| return f(self.ctx, level, msg);
        return HostError.Unsupported;
    }

    pub fn readFile(self: *const Self, alloc: Allocator, path: []const u8) HostError![]u8 {
        if (self.vtable.read_file) |f| {
            // Callee allocates with the provided allocator. Initialize the out
            // pointer as undefined; a null integer cast is UB for non-optional pointers.
            var ptr: [*]u8 = undefined;
            var len: usize = 0;
            try f(self.ctx, path, &ptr, &len, alloc);
            if (len == 0) {
                // Ownership contract: caller always frees. Return a 0-len
                // slice from the same allocator to keep ownership consistent.
                return try alloc.alloc(u8, 0);
            }
            return ptr[0..len];
        }
        return HostError.Unsupported;
    }

    pub fn writeFile(self: *const Self, path: []const u8, bytes: []const u8) HostError!void {
        if (self.vtable.write_file) |f| return f(self.ctx, path, bytes);
        return HostError.Unsupported;
    }
};

/// Null host does nothing and returns error.Unsupported for all calls.
pub const null_host = Host{};

test "host vtable log" {
    const testing = std.testing;
    var captured: ?[]const u8 = null;
    const Logger = struct {
        fn logFn(ctx: ?*anyopaque, level: LogLevel, msg: []const u8) HostError!void {
            _ = level;
            const slot: *?[]const u8 = @ptrCast(@alignCast(ctx.?));
            slot.* = msg;
        }
    };

    var host = Host{ .vtable = .{ .log = Logger.logFn }, .ctx = @ptrCast(&captured) };
    try host.log(.info, "hello");
    try testing.expect(captured != null);
    try testing.expectEqualStrings("hello", captured.?);
}

// Compile-time discovery
test {
    std.testing.refAllDecls(@This());
}

/// Optional comptime-injected host interface to enable static DI while keeping
/// the runtime vtable path. This mirrors the libghostty pattern of allowing
/// both approaches.
pub fn StaticHost(comptime Impl: type) type {
    return struct {
        const Self = @This();
        ctx: *Impl,
        pub fn log(self: *const Self, level: LogLevel, msg: []const u8) HostError!void {
            if (@hasDecl(Impl, "log")) {
                try Impl.log(self.ctx, level, msg);
                return;
            }
            return HostError.Unsupported;
        }

        pub fn readFile(self: *const Self, alloc: Allocator, path: []const u8) HostError![]u8 {
            if (@hasDecl(Impl, "readFile")) {
                return try Impl.readFile(self.ctx, alloc, path);
            }
            return HostError.Unsupported;
        }

        pub fn writeFile(self: *const Self, path: []const u8, bytes: []const u8) HostError!void {
            if (@hasDecl(Impl, "writeFile")) {
                try Impl.writeFile(self.ctx, path, bytes);
                return;
            }
            return HostError.Unsupported;
        }
    };
}

test "static host log" {
    const testing = std.testing;
    var cap: ?[]const u8 = null;
    const Impl = struct {
        sink: *?[]const u8,
        pub fn log(self: *@This(), level: LogLevel, msg: []const u8) HostError!void {
            _ = level;
            self.sink.* = msg;
        }
    };
    var impl = Impl{ .sink = &cap };
    var sh = StaticHost(Impl){ .ctx = &impl };
    try sh.log(.info, "hi");
    try testing.expectEqualStrings("hi", cap.?);
}

test "null host returns Unsupported" {
    const testing = std.testing;
    try testing.expectError(HostError.Unsupported, null_host.log(.info, "x"));
    try testing.expectError(HostError.Unsupported, null_host.readFile(testing.allocator, "p"));
    try testing.expectError(HostError.Unsupported, null_host.writeFile("p", "b"));
}
