const std = @import("std");

// Main application module
// This is a placeholder for application-specific logic
pub const AppContext = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !*AppContext {
        const ctx = try allocator.create(AppContext);
        ctx.* = .{ .allocator = allocator };
        return ctx;
    }
    
    pub fn deinit(self: *AppContext) void {
        self.allocator.destroy(self);
    }
};