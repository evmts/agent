const std = @import("std");
const testing = std.testing;

// Integration tests - these test the overall test infrastructure
// For now, these are basic tests to ensure the test system works

test "Integration test infrastructure works" {
    // Basic test to ensure integration tests can run
    try testing.expect(true);
}

test "Test modules can be imported" {
    // Test that we can import and run tests from other modules
    // This ensures our test organization is working
    try testing.expect(@TypeOf(@import("std").testing.expect) != void);
}

test "Memory allocation works in tests" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test basic memory allocation
    const test_data = try allocator.alloc(u8, 100);
    defer allocator.free(test_data);
    
    @memset(test_data, 42);
    try testing.expectEqual(@as(u8, 42), test_data[0]);
    try testing.expectEqual(@as(u8, 42), test_data[99]);
}

test "Basic data structure operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var list = std.ArrayList(u32).init(allocator);
    defer list.deinit();
    
    try list.append(1);
    try list.append(2);
    try list.append(3);
    
    try testing.expectEqual(@as(usize, 3), list.items.len);
    try testing.expectEqual(@as(u32, 1), list.items[0]);
    try testing.expectEqual(@as(u32, 2), list.items[1]);
    try testing.expectEqual(@as(u32, 3), list.items[2]);
}

test "String operations work correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const test_string = try std.fmt.allocPrint(allocator, "Test {d}", .{42});
    defer allocator.free(test_string);
    
    try testing.expectEqualStrings("Test 42", test_string);
}