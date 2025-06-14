const std = @import("std");
const testing = std.testing;
const app_root = @import("app_root");
const app = app_root.App;

test "App module exists and compiles" {
    // Basic test to ensure the app module compiles correctly
    const App = app;
    
    // Test that we can access the App struct
    try testing.expect(@TypeOf(App) == type);
}

test "App init function exists and can be called" {
    // Test that init function exists and doesn't crash
    app.init();
    
    // If we get here, init() completed successfully
    try testing.expect(true);
}

test "App run function exists and can be called" {
    // Test that run function exists and doesn't crash
    app.run();
    
    // If we get here, run() completed successfully
    try testing.expect(true);
}

test "App init and run sequence" {
    // Test the typical initialization sequence
    app.init();
    app.run();
    
    // Both functions should complete without issues
    try testing.expect(true);
}

test "App module has expected structure" {
    // Verify the App struct has the expected functions
    try testing.expect(@hasDecl(app, "init"));
    try testing.expect(@hasDecl(app, "run"));
    
    // Verify function signatures
    const init_info = @typeInfo(@TypeOf(app.init));
    const run_info = @typeInfo(@TypeOf(app.run));
    
    try testing.expect(init_info == .Fn);
    try testing.expect(run_info == .Fn);
}

test "Multiple app lifecycle calls" {
    // Test that we can call init/run multiple times safely
    for (0..5) |_| {
        app.init();
        app.run();
    }
    
    try testing.expect(true);
}