// Stub implementation of ghostty library
// This is used when the actual libghostty is not available

const c = @cImport({
    @cInclude("ghostty.h");
});

// Export stub functions that match the ghostty C API
export fn ghostty_init() void {}

export fn ghostty_context_new() ?*anyopaque {
    return null;
}

export fn ghostty_context_destroy(ctx: ?*anyopaque) void {
    _ = ctx;
}

export fn ghostty_surface_new(ctx: ?*anyopaque) ?*anyopaque {
    _ = ctx;
    return null;
}

export fn ghostty_surface_destroy(surface: ?*anyopaque) void {
    _ = surface;
}

export fn ghostty_surface_free(surface: ?*anyopaque) void {
    _ = surface;
}

export fn ghostty_surface_draw(surface: ?*anyopaque) void {
    _ = surface;
}

export fn ghostty_surface_set_size(surface: ?*anyopaque, width: u32, height: u32) void {
    _ = surface;
    _ = width;
    _ = height;
}

export fn ghostty_surface_text(surface: ?*anyopaque, text: [*c]const u8, len: usize) void {
    _ = surface;
    _ = text;
    _ = len;
}

export fn ghostty_app_new(cfg: ?*anyopaque) ?*anyopaque {
    _ = cfg;
    return null;
}

export fn ghostty_app_free(app: ?*anyopaque) void {
    _ = app;
}

export fn ghostty_config_new() ?*anyopaque {
    return null;
}

export fn ghostty_config_free(cfg: ?*anyopaque) void {
    _ = cfg;
}