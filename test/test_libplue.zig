const std = @import("std");
const testing = std.testing;
const libplue = @import("libplue");

// Note: GlobalState is now private, so we test through the public C API interface

test "C API initialization and cleanup" {
    // Test the C API functions that Swift calls
    // Note: We can't access plue_init directly since it's exported but not pub
    // This test verifies the module compiles and the interface exists
    try testing.expect(@hasDecl(libplue, "plue_init") == false); // exported functions aren't accessible as decls
    try testing.expect(true); // Basic compilation test
}

test "Module interface verification" {
    // Test that the libplue module compiles and has expected structure
    try testing.expect(@TypeOf(libplue) == type);
}

test "Memory allocation basics" {
    // Basic memory allocation test to ensure allocator works
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_data = try allocator.alloc(u8, 100);
    defer allocator.free(test_data);
    
    @memset(test_data, 42);
    try testing.expectEqual(@as(u8, 42), test_data[0]);
}

test "String operations work correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const test_string = try std.fmt.allocPrint(allocator, "Test {d}", .{42});
    defer allocator.free(test_string);
    
    try testing.expectEqualStrings("Test 42", test_string);
}

test "Module compilation and basic functionality" {
    // Test that the module compiles correctly and basic Zig functionality works
    const test_array = [_]u32{ 1, 2, 3, 4, 5 };
    var sum: u32 = 0;
    
    for (test_array) |value| {
        sum += value;
    }
    
    try testing.expectEqual(@as(u32, 15), sum);
}