const std = @import("std");
const testing = std.testing;
const pty = @import("pty.zig");

test "PTY Manager - create and close session" {
    var manager = pty.Manager.init(testing.allocator);
    defer manager.deinit();

    // Create a simple echo session
    const session = try manager.createSession("echo 'Hello from PTY'", "/tmp");

    // Verify session was created
    try testing.expect(session.running);
    try testing.expectEqualStrings("echo 'Hello from PTY'", session.command);
    try testing.expectEqualStrings("/tmp", session.workdir);
    try testing.expect(session.pid > 0);

    // Store ID for later lookup
    const session_id = try testing.allocator.dupe(u8, session.id);
    defer testing.allocator.free(session_id);

    // Wait a bit for command to execute
    std.Thread.sleep(200 * std.time.ns_per_ms);

    // Try to read some output
    var attempts: usize = 0;
    var got_output = false;
    while (attempts < 10) : (attempts += 1) {
        if (try session.read()) |data| {
            if (data.len > 0) {
                got_output = true;
                std.debug.print("PTY output: {s}\n", .{data});
                break;
            }
        }
        std.Thread.sleep(50 * std.time.ns_per_ms);
    }

    // We should have gotten some output
    try testing.expect(got_output);

    // Close the session
    try manager.closeSession(session_id);

    // Verify session is gone
    const result = manager.getSession(session_id);
    try testing.expectError(pty.PtyError.SessionNotFound, result);
}

test "PTY Manager - list sessions" {
    var manager = pty.Manager.init(testing.allocator);
    defer manager.deinit();

    // Create multiple sessions
    const session1 = try manager.createSession("sleep 1", "/tmp");
    const session2 = try manager.createSession("sleep 2", "/tmp");

    // List sessions
    const sessions = try manager.listSessions(testing.allocator);
    defer testing.allocator.free(sessions);

    // Should have 2 sessions
    try testing.expectEqual(@as(usize, 2), sessions.len);

    // Verify session info
    var found1 = false;
    var found2 = false;
    for (sessions) |session_info| {
        if (std.mem.eql(u8, session_info.id, session1.id)) {
            found1 = true;
            try testing.expectEqualStrings("sleep 1", session_info.command);
        }
        if (std.mem.eql(u8, session_info.id, session2.id)) {
            found2 = true;
            try testing.expectEqualStrings("sleep 2", session_info.command);
        }
    }
    try testing.expect(found1 and found2);

    // Cleanup
    try manager.closeSession(session1.id);
    try manager.closeSession(session2.id);
}

test "PTY Manager - write to session" {
    var manager = pty.Manager.init(testing.allocator);
    defer manager.deinit();

    // Create a bash session
    const session = try manager.createSession("bash", "/tmp");
    defer manager.closeSession(session.id) catch {};

    // Wait for bash to start
    std.Thread.sleep(100 * std.time.ns_per_ms);

    // Write a command
    try session.write("echo 'Test write'\n");

    // Wait for output
    std.time.sleep(100 * std.time.ns_per_ms);

    // Read output
    var got_echo = false;
    var attempts: usize = 0;
    while (attempts < 20) : (attempts += 1) {
        if (try session.read()) |data| {
            if (data.len > 0) {
                std.debug.print("Bash output: {s}\n", .{data});
                if (std.mem.indexOf(u8, data, "Test write") != null) {
                    got_echo = true;
                    break;
                }
            }
        }
        std.Thread.sleep(50 * std.time.ns_per_ms);
    }

    try testing.expect(got_echo);

    // Send exit command
    try session.write("exit\n");
    std.time.sleep(100 * std.time.ns_per_ms);

    // Check status - should have exited
    session.checkStatus();
    try testing.expect(!session.running);
}

test "PTY Manager - session termination" {
    var manager = pty.Manager.init(testing.allocator);
    defer manager.deinit();

    // Create a long-running session
    const session = try manager.createSession("sleep 100", "/tmp");

    // Verify it's running
    try testing.expect(session.running);

    // Terminate it
    try session.terminate();

    // Should be stopped
    try testing.expect(!session.running);

    // Close the session
    try manager.closeSession(session.id);
}

test "PTY Session - process exit detection" {
    var manager = pty.Manager.init(testing.allocator);
    defer manager.deinit();

    // Create a short-lived session
    const session = try manager.createSession("echo 'quick exit' && exit 0", "/tmp");
    const session_id = try testing.allocator.dupe(u8, session.id);
    defer testing.allocator.free(session_id);

    // Initially running
    try testing.expect(session.running);

    // Wait for process to exit
    std.time.sleep(200 * std.time.ns_per_ms);

    // Check status
    session.checkStatus();

    // Should have exited
    try testing.expect(!session.running);

    // Cleanup
    try manager.closeSession(session_id);
}

test "PTY Manager - concurrent sessions" {
    var manager = pty.Manager.init(testing.allocator);
    defer manager.deinit();

    // Create multiple sessions
    var sessions: [5]*pty.Session = undefined;
    for (&sessions, 0..) |*s, i| {
        const cmd = try std.fmt.allocPrint(testing.allocator, "echo 'Session {d}'", .{i});
        defer testing.allocator.free(cmd);
        s.* = try manager.createSession(cmd, "/tmp");
    }

    // All should be running
    for (sessions) |session| {
        try testing.expect(session.running);
    }

    // Wait for all to complete
    std.Thread.sleep(300 * std.time.ns_per_ms);

    // Check status
    for (sessions) |session| {
        session.checkStatus();
    }

    // Cleanup all
    for (sessions) |session| {
        try manager.closeSession(session.id);
    }

    // Verify all are gone
    const remaining = try manager.listSessions(testing.allocator);
    defer testing.allocator.free(remaining);
    try testing.expectEqual(@as(usize, 0), remaining.len);
}
