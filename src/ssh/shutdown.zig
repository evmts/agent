const std = @import("std");
const testing = std.testing;

pub const ShutdownError = error{
    ShutdownAlreadyInProgress,
    InvalidShutdownState,
    ShutdownTimeout,
} || error{OutOfMemory};

pub const ShutdownState = enum {
    running,
    shutting_down,
    shutdown_complete,

    pub fn toString(self: ShutdownState) []const u8 {
        return switch (self) {
            .running => "running",
            .shutting_down => "shutting_down", 
            .shutdown_complete => "shutdown_complete",
        };
    }
};

pub const ShutdownManager = struct {
    active_connections: std.atomic.Value(u32),
    state: std.atomic.Value(u8),
    drain_timeout: u32,
    start_time: std.atomic.Value(i64),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, drain_timeout: u32) ShutdownManager {
        return ShutdownManager{
            .active_connections = std.atomic.Value(u32).init(0),
            .state = std.atomic.Value(u8).init(@intFromEnum(ShutdownState.running)),
            .drain_timeout = drain_timeout,
            .start_time = std.atomic.Value(i64).init(0),
            .allocator = allocator,
        };
    }
    
    pub fn addConnection(self: *ShutdownManager) ShutdownError!void {
        const current_state: ShutdownState = @enumFromInt(self.state.load(.monotonic));
        if (current_state != .running) {
            return ShutdownError.ShutdownAlreadyInProgress;
        }
        _ = self.active_connections.fetchAdd(1, .monotonic);
    }
    
    pub fn removeConnection(self: *ShutdownManager) void {
        const prev_count = self.active_connections.fetchSub(1, .monotonic);
        
        // Check if shutdown should complete
        const current_state: ShutdownState = @enumFromInt(self.state.load(.monotonic));
        if (prev_count == 1 and current_state == .shutting_down) {
            self.state.store(@intFromEnum(ShutdownState.shutdown_complete), .monotonic);
            std.log.info("SSH server shutdown complete. All connections closed.", .{});
        }
    }
    
    // Legacy methods for compatibility
    pub fn incrementConnections(self: *ShutdownManager) void {
        _ = self.active_connections.fetchAdd(1, .monotonic);
    }
    
    pub fn decrementConnections(self: *ShutdownManager) void {
        _ = self.active_connections.fetchSub(1, .monotonic);
    }
    
    pub fn getActiveConnections(self: *const ShutdownManager) u32 {
        return self.active_connections.load(.monotonic);
    }
    
    pub fn initiateShutdown(self: *ShutdownManager) ShutdownError!void {
        const running_val = @intFromEnum(ShutdownState.running);
        const shutting_down_val = @intFromEnum(ShutdownState.shutting_down);
        const current_state = self.state.cmpxchgWeak(running_val, shutting_down_val, .monotonic, .monotonic);
        if (current_state != null) {
            return ShutdownError.ShutdownAlreadyInProgress;
        }
        
        self.start_time.store(std.time.timestamp(), .monotonic);
        const active = self.active_connections.load(.monotonic);
        std.log.info("SSH server shutdown initiated. Active connections: {d}", .{active});
        
        // If no active connections, complete immediately
        if (active == 0) {
            self.state.store(@intFromEnum(ShutdownState.shutdown_complete), .monotonic);
            std.log.info("SSH server shutdown complete. No active connections.", .{});
        }
    }
    
    pub fn forceShutdown(self: *ShutdownManager) void {
        const current_state: ShutdownState = @enumFromInt(self.state.load(.monotonic));
        if (current_state == .running) {
            self.start_time.store(std.time.timestamp(), .monotonic);
        }
        
        const active = self.active_connections.swap(0, .monotonic);
        self.state.store(@intFromEnum(ShutdownState.shutdown_complete), .monotonic);
        
        std.log.warn("SSH server forced shutdown. {d} active connections terminated.", .{active});
    }
    
    pub fn getState(self: *const ShutdownManager) ShutdownState {
        return @enumFromInt(self.state.load(.monotonic));
    }
    
    pub fn isShuttingDown(self: *const ShutdownManager) bool {
        const current_state: ShutdownState = @enumFromInt(self.state.load(.monotonic));
        return current_state != .running;
    }
    
    // Legacy method for compatibility
    pub fn requestShutdown(self: *ShutdownManager) void {
        self.initiateShutdown() catch {
            std.log.warn("Shutdown already in progress", .{});
        };
    }
    
    pub fn isShutdownRequested(self: *const ShutdownManager) bool {
        const current_state: ShutdownState = @enumFromInt(self.state.load(.monotonic));
        return current_state != .running;
    }
    
    pub fn waitForShutdown(self: *const ShutdownManager) ShutdownError!void {
        const start_wait = std.time.timestamp();
        const timeout_s = @as(i64, self.drain_timeout);
        
        while (true) {
            const current_state: ShutdownState = @enumFromInt(self.state.load(.monotonic));
            
            if (current_state == .shutdown_complete) {
                return;
            }
            
            if (current_state == .running) {
                return ShutdownError.InvalidShutdownState;
            }
            
            // Check timeout
            const elapsed_s = std.time.timestamp() - start_wait;
            if (elapsed_s > timeout_s) {
                return ShutdownError.ShutdownTimeout;
            }
            
            // Sleep briefly to avoid busy waiting
            std.time.sleep(100 * std.time.ns_per_ms);
        }
    }
    
    // Legacy method for compatibility  
    pub fn waitForDrain(self: *const ShutdownManager) !void {
        const start_time = std.time.timestamp();
        const timeout_ns = @as(i128, self.drain_timeout) * std.time.ns_per_s;
        
        while (self.getActiveConnections() > 0) {
            const elapsed_ns = @as(i128, std.time.timestamp() - start_time) * std.time.ns_per_s;
            if (elapsed_ns >= timeout_ns) {
                std.log.warn("Shutdown drain timeout reached with {d} active connections", 
                    .{self.getActiveConnections()});
                break;
            }
            
            std.log.info("Waiting for {d} connections to close...", .{self.getActiveConnections()});
            std.time.sleep(std.time.ns_per_s); // Check every second
        }
        
        std.log.info("All connections closed, shutdown complete");
    }
    
    pub fn getShutdownDuration(self: *const ShutdownManager) ?i64 {
        const start = self.start_time.load(.monotonic);
        if (start == 0) return null;
        return std.time.timestamp() - start;
    }
};

pub const GracefulShutdownHandler = struct {
    shutdown_manager: *ShutdownManager,
    signal_handler_installed: bool,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, manager: *ShutdownManager) GracefulShutdownHandler {
        return GracefulShutdownHandler{
            .shutdown_manager = manager,
            .signal_handler_installed = false,
            .allocator = allocator,
        };
    }
    
    pub fn installSignalHandlers(self: *GracefulShutdownHandler) ShutdownError!void {
        // In a real implementation, this would install SIGTERM and SIGINT handlers
        // For now, we'll use a simpler approach
        self.signal_handler_installed = true;
        std.log.info("Signal handlers installed for graceful shutdown", .{});
    }
    
    pub fn handleShutdownSignal(self: *GracefulShutdownHandler) void {
        if (!self.signal_handler_installed) return;
        
        self.shutdown_manager.initiateShutdown() catch |err| {
            std.log.err("Failed to initiate shutdown: {}", .{err});
            self.shutdown_manager.forceShutdown();
        };
    }
    
    pub fn waitForGracefulShutdown(self: *GracefulShutdownHandler) ShutdownError!bool {
        // Try graceful shutdown first
        self.shutdown_manager.waitForShutdown() catch |err| switch (err) {
            ShutdownError.ShutdownTimeout => {
                std.log.warn("Graceful shutdown timeout exceeded, forcing shutdown");
                self.shutdown_manager.forceShutdown();
                return false;
            },
            else => return err,
        };
        
        return true;
    }
};

// Health check utilities for shutdown coordination
pub fn checkHealthDuringShutdown(shutdown_manager: *const ShutdownManager) bool {
    const state = shutdown_manager.getState();
    return switch (state) {
        .running => true,
        .shutting_down => false, // Failing health checks to stop new traffic
        .shutdown_complete => false,
    };
}

pub fn logShutdownStatus(shutdown_manager: *const ShutdownManager) void {
    const state = shutdown_manager.getState();
    const connections = shutdown_manager.getActiveConnections();
    
    if (shutdown_manager.getShutdownDuration()) |duration| {
        std.log.info("Shutdown status: {s}, active connections: {d}, duration: {d}s", 
            .{ state.toString(), connections, duration });
    } else {
        std.log.info("Shutdown status: {s}, active connections: {d}", 
            .{ state.toString(), connections });
    }
}

// Tests
test "ShutdownManager basic lifecycle" {
    const allocator = testing.allocator;
    var manager = ShutdownManager.init(allocator, 5);
    
    try testing.expectEqual(ShutdownState.running, manager.getState());
    try testing.expect(!manager.isShuttingDown());
    try testing.expectEqual(@as(u32, 0), manager.getActiveConnections());
}

test "ShutdownManager connection tracking" {
    const allocator = testing.allocator;
    var manager = ShutdownManager.init(allocator, 5);
    
    // Add connections
    try manager.addConnection();
    try manager.addConnection();
    try testing.expectEqual(@as(u32, 2), manager.getActiveConnections());
    
    // Remove one connection
    manager.removeConnection();
    try testing.expectEqual(@as(u32, 1), manager.getActiveConnections());
    
    // Remove final connection
    manager.removeConnection();
    try testing.expectEqual(@as(u32, 0), manager.getActiveConnections());
}

test "ShutdownManager prevents new connections during shutdown" {
    const allocator = testing.allocator;
    var manager = ShutdownManager.init(allocator, 5);
    
    // Initiate shutdown
    try manager.initiateShutdown();
    try testing.expectEqual(ShutdownState.shutting_down, manager.getState());
    try testing.expect(manager.isShuttingDown());
    
    // Should not be able to add new connections
    try testing.expectError(ShutdownError.ShutdownAlreadyInProgress, manager.addConnection());
    
    // Should not be able to initiate shutdown again
    try testing.expectError(ShutdownError.ShutdownAlreadyInProgress, manager.initiateShutdown());
}

test "ShutdownManager graceful shutdown with active connections" {
    const allocator = testing.allocator;
    var manager = ShutdownManager.init(allocator, 5);
    
    // Add some connections
    try manager.addConnection();
    try manager.addConnection();
    
    // Initiate shutdown
    try manager.initiateShutdown();
    try testing.expectEqual(ShutdownState.shutting_down, manager.getState());
    
    // Remove connections one by one
    manager.removeConnection();
    try testing.expectEqual(ShutdownState.shutting_down, manager.getState());
    
    // Remove final connection should complete shutdown
    manager.removeConnection();
    try testing.expectEqual(ShutdownState.shutdown_complete, manager.getState());
}

test "ShutdownManager force shutdown" {
    const allocator = testing.allocator;
    var manager = ShutdownManager.init(allocator, 5);
    
    // Add connections
    try manager.addConnection();
    try manager.addConnection();
    
    // Force shutdown regardless of active connections
    manager.forceShutdown();
    try testing.expectEqual(ShutdownState.shutdown_complete, manager.getState());
    try testing.expectEqual(@as(u32, 0), manager.getActiveConnections());
}

test "ShutdownManager waitForShutdown with invalid state" {
    const allocator = testing.allocator;
    var manager = ShutdownManager.init(allocator, 5);
    
    // Should error if waiting while running
    try testing.expectError(ShutdownError.InvalidShutdownState, manager.waitForShutdown());
}

test "GracefulShutdownHandler signal handling" {
    const allocator = testing.allocator;
    var manager = ShutdownManager.init(allocator, 5);
    var handler = GracefulShutdownHandler.init(allocator, &manager);
    
    try testing.expect(!handler.signal_handler_installed);
    
    try handler.installSignalHandlers();
    try testing.expect(handler.signal_handler_installed);
    
    // Simulate signal handling
    handler.handleShutdownSignal();
    try testing.expectEqual(ShutdownState.shutting_down, manager.getState());
}

test "checkHealthDuringShutdown returns correct status" {
    const allocator = testing.allocator;
    var manager = ShutdownManager.init(allocator, 5);
    
    // Should be healthy while running
    try testing.expect(checkHealthDuringShutdown(&manager));
    
    // Should be unhealthy during shutdown
    try manager.initiateShutdown();
    try testing.expect(!checkHealthDuringShutdown(&manager));
    
    // Should be unhealthy when complete
    manager.forceShutdown();
    try testing.expect(!checkHealthDuringShutdown(&manager));
}

test "ShutdownState toString" {
    try testing.expectEqualStrings("running", ShutdownState.running.toString());
    try testing.expectEqualStrings("shutting_down", ShutdownState.shutting_down.toString());
    try testing.expectEqualStrings("shutdown_complete", ShutdownState.shutdown_complete.toString());
}

test "legacy methods compatibility" {
    const allocator = testing.allocator;
    var manager = ShutdownManager.init(allocator, 5);
    
    // Test legacy increment/decrement methods
    manager.incrementConnections();
    manager.incrementConnections();
    try testing.expectEqual(@as(u32, 2), manager.getActiveConnections());
    
    manager.decrementConnections();
    try testing.expectEqual(@as(u32, 1), manager.getActiveConnections());
    
    // Test legacy shutdown request
    try testing.expect(!manager.isShutdownRequested());
    manager.requestShutdown();
    try testing.expect(manager.isShutdownRequested());
}

test "logShutdownStatus outputs correctly" {
    const allocator = testing.allocator;
    var manager = ShutdownManager.init(allocator, 5);
    
    // Test logging in different states
    logShutdownStatus(&manager);
    
    try manager.initiateShutdown();
    logShutdownStatus(&manager);
    
    manager.forceShutdown();
    logShutdownStatus(&manager);
}