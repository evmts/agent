const std = @import("std");
const testing = std.testing;
const libplue = @import("libplue");

test "GlobalState initialization and deinitialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = libplue.GlobalState.init(allocator);
    try testing.expect(state.initialized);
    try testing.expect(state.allocator.ptr == allocator.ptr);

    state.deinit();
    try testing.expect(!state.initialized);
}

test "GlobalState message processing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = libplue.GlobalState.init(allocator);
    defer state.deinit();

    const test_message = "Hello, Plue!";
    const response = state.processMessage(test_message);
    
    try testing.expect(response != null);
    if (response) |resp| {
        defer allocator.free(resp);
        try testing.expect(std.mem.startsWith(u8, resp, "Echo: "));
        try testing.expect(std.mem.endsWith(u8, resp, test_message));
    }
}

test "GlobalState handles empty message" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = libplue.GlobalState.init(allocator);
    defer state.deinit();

    const response = state.processMessage("");
    
    try testing.expect(response != null);
    if (response) |resp| {
        defer allocator.free(resp);
        try testing.expectEqualStrings("Echo: ", resp);
    }
}

test "C API initialization and cleanup" {
    // Test the C API functions that Swift calls
    const init_result = libplue.plue_init();
    try testing.expectEqual(@as(c_int, 0), init_result);
    
    // Clean up
    libplue.plue_deinit();
}

test "C API message processing integration" {
    // Initialize the C API
    const init_result = libplue.plue_init();
    try testing.expectEqual(@as(c_int, 0), init_result);
    defer libplue.plue_deinit();

    // Test message processing through C API
    const test_message = "Integration test";
    const c_message: [*:0]const u8 = test_message.ptr;
    
    const response = libplue.plue_process_message(c_message);
    try testing.expect(std.mem.len(response) > 0);
    
    // The response should contain our test message
    const response_slice = std.mem.span(response);
    try testing.expect(std.mem.indexOf(u8, response_slice, test_message) != null);
    
    // Free the response
    libplue.plue_free_string(response);
}

test "C API handles null scenarios gracefully" {
    // Test without initialization (should handle gracefully)
    const response = libplue.plue_process_message("");
    try testing.expectEqualStrings("", std.mem.span(response));
}

test "Memory leak detection in message processing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    var state = libplue.GlobalState.init(allocator);
    defer state.deinit();

    // Process multiple messages to test for leaks
    for (0..100) |i| {
        const message = try std.fmt.allocPrint(allocator, "Test message {d}", .{i});
        defer allocator.free(message);
        
        const response = state.processMessage(message);
        if (response) |resp| {
            defer allocator.free(resp);
            try testing.expect(resp.len > 0);
        }
    }
}

test "Concurrent message processing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = libplue.GlobalState.init(allocator);
    defer state.deinit();

    // Test that the same state can handle multiple messages
    const messages = [_][]const u8{
        "Message 1",
        "Message 2", 
        "Message 3",
    };

    for (messages) |msg| {
        const response = state.processMessage(msg);
        try testing.expect(response != null);
        if (response) |resp| {
            defer allocator.free(resp);
            try testing.expect(std.mem.indexOf(u8, resp, msg) != null);
        }
    }
}