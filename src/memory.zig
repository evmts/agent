//! Arena helpers and owned-return utilities for libsmithers.
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Duplicate a slice into caller-owned memory (owned-return pattern).
pub fn ownedDupe(alloc: Allocator, bytes: []const u8) Allocator.Error![]u8 {
    return try alloc.dupe(u8, bytes);
}

/// Scoped arena wrapper with explicit lifetime and poisoning on deinit.
pub fn ScopedArena() type {
    return struct {
        const Self = @This();
        arena: std.heap.ArenaAllocator,

        pub fn init(parent: Allocator) Self {
            return .{ .arena = std.heap.ArenaAllocator.init(parent) };
        }

        pub fn allocator(self: *Self) Allocator {
            return self.arena.allocator();
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            self.* = undefined; // poison after free
        }
    };
}

// Tests
test "arena lifecycle" {
    const testing = std.testing;
    var sa = ScopedArena().init(testing.allocator);
    defer sa.deinit();
    const s = try ownedDupe(sa.allocator(), "abc");
    try testing.expectEqualStrings("abc", s);
}

// Discovery
test {
    std.testing.refAllDecls(@This());
}
