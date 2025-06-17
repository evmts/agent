const std = @import("std");

// Import Ghostty's C API from their generated header
const c = @cImport({
    @cInclude("ghostty.h");
});

// Global state for the terminal
const TerminalState = struct {
    app: ?*anyopaque = null,
    surface: ?*anyopaque = null,
    initialized: bool = false,
};

var terminal_state = TerminalState{};
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Initialize the Ghostty terminal
export fn ghostty_terminal_init() c_int {
    if (terminal_state.initialized) return 0;
    
    // Initialize Ghostty core
    if (c.ghostty_init() != 0) {
        std.log.err("Failed to initialize Ghostty core", .{});
        return -1;
    }
    
    // Create config
    const config = c.ghostty_config_new();
    if (config == null) {
        std.log.err("Failed to create Ghostty config", .{});
        return -1;
    }
    defer c.ghostty_config_free(config);
    
    // Create the Ghostty app instance
    terminal_state.app = c.ghostty_app_new(null, config);
    if (terminal_state.app == null) {
        std.log.err("Failed to create Ghostty app", .{});
        return -1;
    }
    
    terminal_state.initialized = true;
    std.log.info("Ghostty terminal initialized successfully", .{});
    return 0;
}

/// Deinitialize the Ghostty terminal
export fn ghostty_terminal_deinit() void {
    if (terminal_state.surface) |surface| {
        c.ghostty_surface_free(surface);
        terminal_state.surface = null;
    }
    
    if (terminal_state.app) |app| {
        c.ghostty_app_free(app);
        terminal_state.app = null;
    }
    
    terminal_state.initialized = false;
    _ = gpa.deinit();
}

/// Create a new terminal surface
export fn ghostty_terminal_create_surface() c_int {
    if (!terminal_state.initialized or terminal_state.app == null) {
        return -1;
    }
    
    // Create a new surface
    terminal_state.surface = c.ghostty_surface_new(terminal_state.app, null);
    if (terminal_state.surface == null) {
        std.log.err("Failed to create Ghostty surface", .{});
        return -1;
    }
    
    std.log.info("Ghostty surface created successfully", .{});
    return 0;
}

/// Set the terminal surface size
export fn ghostty_terminal_set_size(width: c_uint, height: c_uint, scale: f64) void {
    _ = scale; // Scale might be handled differently in ghostty
    if (terminal_state.surface) |surface| {
        c.ghostty_surface_set_size(surface, width, height);
    }
}

/// Send key input to the terminal
export fn ghostty_terminal_send_key(key: [*:0]const u8, modifiers: c_uint, action: c_int) void {
    _ = key;
    _ = modifiers;
    _ = action;
    // TODO: Implement proper key input handling with ghostty_input_key_s struct
    // For now, we'll use the text input method instead
}

/// Write data to the terminal PTY
export fn ghostty_terminal_write(data: [*]const u8, len: usize) usize {
    if (terminal_state.surface) |surface| {
        // Create a null-terminated string
        var buf: [4096]u8 = undefined;
        const copy_len = @min(len, buf.len - 1);
        @memcpy(buf[0..copy_len], data[0..copy_len]);
        buf[copy_len] = 0;
        
        c.ghostty_surface_text(surface, &buf, copy_len);
        return copy_len;
    }
    return 0;
}

/// Read data from the terminal PTY
export fn ghostty_terminal_read(buffer: [*]u8, buffer_len: usize) usize {
    _ = buffer;
    _ = buffer_len;
    // TODO: Implement reading from terminal
    // The ghostty API might not expose direct PTY reading
    return 0;
}

/// Draw/render the terminal surface
export fn ghostty_terminal_draw() void {
    if (terminal_state.surface) |surface| {
        c.ghostty_surface_draw(surface);
    }
}

/// Send text input to the terminal
export fn ghostty_terminal_send_text(text: [*:0]const u8) void {
    if (terminal_state.surface) |surface| {
        const len = std.mem.len(text);
        c.ghostty_surface_text(surface, text, len);
    }
}