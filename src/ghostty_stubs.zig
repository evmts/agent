// Stub implementations for Ghostty functions when building without Nix
// These are weak symbols that will be overridden by the real Ghostty library

const std = @import("std");

// Stub implementations with weak linkage
export fn ghostty_init() callconv(.C) c_int {
    std.log.warn("Using Ghostty stub: ghostty_init", .{});
    return 0;
}

export fn ghostty_app_new(options: ?*anyopaque) callconv(.C) ?*anyopaque {
    _ = options;
    std.log.warn("Using Ghostty stub: ghostty_app_new", .{});
    // Return a non-null dummy pointer
    return @as(?*anyopaque, @ptrFromInt(0x1000));
}

export fn ghostty_app_free(app: ?*anyopaque) callconv(.C) void {
    _ = app;
    std.log.warn("Using Ghostty stub: ghostty_app_free", .{});
}

export fn ghostty_surface_new(app: ?*anyopaque, options: ?*anyopaque) callconv(.C) ?*anyopaque {
    _ = app;
    _ = options;
    std.log.warn("Using Ghostty stub: ghostty_surface_new", .{});
    // Return a non-null dummy pointer
    return @as(?*anyopaque, @ptrFromInt(0x2000));
}

export fn ghostty_surface_free(surface: ?*anyopaque) callconv(.C) void {
    _ = surface;
    std.log.warn("Using Ghostty stub: ghostty_surface_free", .{});
}

export fn ghostty_surface_draw(surface: ?*anyopaque) callconv(.C) void {
    _ = surface;
    std.log.warn("Using Ghostty stub: ghostty_surface_draw", .{});
}

export fn ghostty_surface_set_size(surface: ?*anyopaque, width: c_uint, height: c_uint, scale: f64) callconv(.C) void {
    _ = surface;
    std.log.warn("Using Ghostty stub: ghostty_surface_set_size {}x{} @ {}x", .{ width, height, scale });
}

export fn ghostty_surface_key(surface: ?*anyopaque, key: [*:0]const u8, mods: c_uint, action: c_int, text: ?[*:0]const u8) callconv(.C) void {
    _ = surface;
    _ = text;
    std.log.warn("Using Ghostty stub: ghostty_surface_key {s} mods={} action={}", .{ key, mods, action });
}

export fn ghostty_surface_write_to_pty(surface: ?*anyopaque, data: [*]const u8, len: usize) callconv(.C) usize {
    _ = surface;
    _ = data;
    std.log.warn("Using Ghostty stub: ghostty_surface_write_to_pty {} bytes", .{len});
    return len; // Pretend we wrote all bytes
}

export fn ghostty_surface_read_from_pty(surface: ?*anyopaque, data: [*]u8, len: usize) callconv(.C) usize {
    _ = surface;
    _ = data;
    _ = len;
    std.log.warn("Using Ghostty stub: ghostty_surface_read_from_pty", .{});
    return 0; // No data available
}