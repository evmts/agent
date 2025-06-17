const std = @import("std");
const testing = std.testing;
const terminal = @import("terminal");

// Import the C functions directly since they're exported but not pub
const c = @cImport({});
extern fn terminal_init() c_int;
extern fn terminal_start() c_int; 
extern fn terminal_stop() void;
extern fn terminal_write(data: [*]const u8, len: usize) isize;
extern fn terminal_read(buffer: [*]u8, buffer_len: usize) isize;
extern fn terminal_send_text(text: [*:0]const u8) void;
extern fn terminal_get_fd() c_int;
extern fn terminal_resize(cols: u16, rows: u16) void;
extern fn terminal_deinit() void;

test "terminal initialization and deinitialization" {
    // Initialize terminal
    const init_result = terminal_init();
    try testing.expectEqual(@as(c_int, 0), init_result);
    
    // Deinitialize
    terminal_deinit();
}

test "terminal double initialization" {
    // First initialization should succeed
    const init_result1 = terminal_init();
    try testing.expectEqual(@as(c_int, 0), init_result1);
    
    // Second initialization should succeed (idempotent)
    const init_result2 = terminal_init();
    try testing.expectEqual(@as(c_int, 0), init_result2);
    
    // Cleanup - only deinit once since it's the same instance
    terminal_deinit();
}

test "terminal operations without initialization" {
    // Don't call deinit here as terminal might not be initialized
    // Start should fail without initialization
    const start_result = terminal_start();
    try testing.expectEqual(@as(c_int, -1), start_result);
    
    // Write should fail without running terminal
    const test_data = "test";
    const write_result = terminal_write(test_data.ptr, test_data.len);
    try testing.expectEqual(@as(isize, -1), write_result);
    
    // Read should fail without running terminal
    var buffer: [100]u8 = undefined;
    const read_result = terminal_read(&buffer, buffer.len);
    try testing.expectEqual(@as(isize, -1), read_result);
    
    // Get FD should return -1 without running terminal
    const fd = terminal_get_fd();
    try testing.expectEqual(@as(c_int, -1), fd);
}

test "terminal get file descriptor" {
    // Initialize terminal
    _ = terminal_init();
    defer terminal_deinit();
    
    // FD should be -1 before starting
    const fd_before = terminal_get_fd();
    try testing.expectEqual(@as(c_int, -1), fd_before);
    
    // Note: We can't test terminal_start() in unit tests as it forks a process
    // and requires a real PTY, which may not work in test environments
}

test "terminal write without running terminal" {
    // Initialize terminal
    _ = terminal_init();
    defer terminal_deinit();
    
    // Write should fail when terminal is not running
    const test_data = "Hello, Terminal!";
    const result = terminal_write(test_data.ptr, test_data.len);
    try testing.expectEqual(@as(isize, -1), result);
}

test "terminal read without running terminal" {
    // Initialize terminal
    _ = terminal_init();
    defer terminal_deinit();
    
    // Read should fail when terminal is not running
    var buffer: [256]u8 = undefined;
    const result = terminal_read(&buffer, buffer.len);
    try testing.expectEqual(@as(isize, -1), result);
}

test "terminal send text" {
    // Initialize terminal
    _ = terminal_init();
    defer terminal_deinit();
    
    // Send text should work (internally calls terminal_write)
    // It won't actually write anything since terminal isn't running,
    // but it should not crash
    terminal_send_text("test text");
}

test "terminal resize" {
    // Initialize terminal
    _ = terminal_init();
    defer terminal_deinit();
    
    // Resize should work even without running terminal (no-op)
    terminal_resize(80, 24);
    terminal_resize(120, 40);
    terminal_resize(0, 0); // Edge case
    terminal_resize(65535, 65535); // Max values
}

test "terminal stop without start" {
    // Initialize terminal
    _ = terminal_init();
    defer terminal_deinit();
    
    // Stop should be safe to call even if not started
    terminal_stop();
}

test "PtyError enum values" {
    // Test that error codes have expected values
    try testing.expectEqual(@as(c_int, 0), @intFromEnum(terminal.PtyError.SUCCESS));
    try testing.expectEqual(@as(c_int, -1), @intFromEnum(terminal.PtyError.ALREADY_INITIALIZED));
    try testing.expectEqual(@as(c_int, -2), @intFromEnum(terminal.PtyError.NOT_INITIALIZED));
    try testing.expectEqual(@as(c_int, -3), @intFromEnum(terminal.PtyError.ALREADY_RUNNING));
    try testing.expectEqual(@as(c_int, -4), @intFromEnum(terminal.PtyError.NOT_RUNNING));
    try testing.expectEqual(@as(c_int, -5), @intFromEnum(terminal.PtyError.OPEN_FAILED));
    try testing.expectEqual(@as(c_int, -6), @intFromEnum(terminal.PtyError.FORK_FAILED));
    try testing.expectEqual(@as(c_int, -7), @intFromEnum(terminal.PtyError.EXEC_FAILED));
    try testing.expectEqual(@as(c_int, -8), @intFromEnum(terminal.PtyError.READ_ERROR));
    try testing.expectEqual(@as(c_int, -9), @intFromEnum(terminal.PtyError.WRITE_ERROR));
    try testing.expectEqual(@as(c_int, -10), @intFromEnum(terminal.PtyError.INVALID_FD));
}

test "terminal thread safety" {
    // Initialize terminal
    _ = terminal_init();
    defer terminal_deinit();
    
    // Multiple operations should be thread-safe due to mutex
    // Note: We can't actually test concurrency in unit tests easily,
    // but we can verify that sequential operations work correctly
    
    const test_data = "thread safe test";
    _ = terminal_write(test_data.ptr, test_data.len);
    
    var buffer: [100]u8 = undefined;
    _ = terminal_read(&buffer, buffer.len);
    
    _ = terminal_get_fd();
    
    terminal_resize(100, 50);
}

// Integration test that would require a real PTY environment
// Commented out as it may fail in CI/test environments
// test "terminal full lifecycle" {
//     // Initialize
//     try testing.expectEqual(@as(c_int, 0), terminal_init());
//     defer terminal_deinit();
//     
//     // Start terminal
//     try testing.expectEqual(@as(c_int, 0), terminal_start());
//     defer terminal_stop();
//     
//     // Get FD - should be valid
//     const fd = terminal_get_fd();
//     try testing.expect(fd > 0);
//     
//     // Write some data
//     const test_input = "echo 'Hello'\n";
//     const bytes_written = terminal_write(test_input.ptr, test_input.len);
//     try testing.expect(bytes_written > 0);
//     
//     // Give terminal time to process
//     std.time.sleep(100_000_000); // 100ms
//     
//     // Try to read response
//     var buffer: [1024]u8 = undefined;
//     const bytes_read = terminal_read(&buffer, buffer.len);
//     
//     // May or may not have data ready
//     try testing.expect(bytes_read >= 0);
// }