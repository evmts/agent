const std = @import("std");
const testing = std.testing;

// Log entry structure
pub const LogEntry = struct {
    timestamp: i64,
    level: LogLevel,
    step_name: []const u8,
    message: []const u8,
    metadata: ?std.StringHashMap([]const u8) = null,
    
    pub fn deinit(self: *LogEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.step_name);
        allocator.free(self.message);
        if (self.metadata) |*metadata| {
            var iter = metadata.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            metadata.deinit();
        }
    }
};

// Log levels
pub const LogLevel = enum {
    debug,
    info,
    warn,
    error,
    
    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .error => "ERROR",
        };
    }
};

// Log query options
pub const LogQueryOptions = struct {
    level: ?LogLevel = null,
    step_name: ?[]const u8 = null,
    since: ?i64 = null,
    until: ?i64 = null,
    limit: ?usize = null,
};

// Log storage backend types
pub const LogStorageBackend = enum {
    memory,
    filesystem,
    database,
};

// Mock log storage for testing
pub const LogStorage = struct {
    allocator: std.mem.Allocator,
    backend: LogStorageBackend,
    base_path: ?[]const u8,
    job_logs: std.HashMap(u32, std.ArrayList(LogEntry), std.HashMap.AutoContext(u32), std.hash_map.default_max_load_percentage),
    
    pub fn init(allocator: std.mem.Allocator, config: struct {
        backend: LogStorageBackend,
        base_path: ?[]const u8 = null,
    }) !LogStorage {
        return LogStorage{
            .allocator = allocator,
            .backend = config.backend,
            .base_path = if (config.base_path) |path| try allocator.dupe(u8, path) else null,
            .job_logs = std.HashMap(u32, std.ArrayList(LogEntry), std.HashMap.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *LogStorage) void {
        if (self.base_path) |path| {
            self.allocator.free(path);
        }
        
        // Clean up all stored logs
        var jobs_iter = self.job_logs.iterator();
        while (jobs_iter.next()) |entry| {
            for (entry.value_ptr.items) |*log_entry| {
                log_entry.deinit(self.allocator);
            }
            entry.value_ptr.deinit();
        }
        self.job_logs.deinit();
    }
    
    pub fn storeLog(self: *LogStorage, job_id: u32, log_entry: LogEntry) !void {
        // Get or create job log list
        const result = try self.job_logs.getOrPut(job_id);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(LogEntry).init(self.allocator);
        }
        
        // Create owned copy of log entry
        var owned_entry = LogEntry{
            .timestamp = log_entry.timestamp,
            .level = log_entry.level,
            .step_name = try self.allocator.dupe(u8, log_entry.step_name),
            .message = try self.allocator.dupe(u8, log_entry.message),
        };
        
        if (log_entry.metadata) |metadata| {
            owned_entry.metadata = std.StringHashMap([]const u8).init(self.allocator);
            var iter = metadata.iterator();
            while (iter.next()) |meta_entry| {
                try owned_entry.metadata.?.put(
                    try self.allocator.dupe(u8, meta_entry.key_ptr.*),
                    try self.allocator.dupe(u8, meta_entry.value_ptr.*)
                );
            }
        }
        
        try result.value_ptr.append(owned_entry);
    }
    
    pub fn getJobLogs(self: *LogStorage, job_id: u32, options: LogQueryOptions) ![]LogEntry {
        const job_logs = self.job_logs.get(job_id) orelse {
            return try self.allocator.alloc(LogEntry, 0);
        };
        
        var filtered_logs = std.ArrayList(LogEntry).init(self.allocator);
        defer filtered_logs.deinit();
        
        for (job_logs.items) |log_entry| {
            // Apply filters
            if (options.level) |level| {
                if (log_entry.level != level) continue;
            }
            
            if (options.step_name) |step_name| {
                if (!std.mem.eql(u8, log_entry.step_name, step_name)) continue;
            }
            
            if (options.since) |since| {
                if (log_entry.timestamp < since) continue;
            }
            
            if (options.until) |until| {
                if (log_entry.timestamp > until) continue;
            }
            
            // Create copy for return
            var copied_entry = LogEntry{
                .timestamp = log_entry.timestamp,
                .level = log_entry.level,
                .step_name = try self.allocator.dupe(u8, log_entry.step_name),
                .message = try self.allocator.dupe(u8, log_entry.message),
            };
            
            if (log_entry.metadata) |metadata| {
                copied_entry.metadata = std.StringHashMap([]const u8).init(self.allocator);
                var iter = metadata.iterator();
                while (iter.next()) |meta_entry| {
                    try copied_entry.metadata.?.put(
                        try self.allocator.dupe(u8, meta_entry.key_ptr.*),
                        try self.allocator.dupe(u8, meta_entry.value_ptr.*)
                    );
                }
            }
            
            try filtered_logs.append(copied_entry);
            
            // Apply limit
            if (options.limit) |limit| {
                if (filtered_logs.items.len >= limit) break;
            }
        }
        
        return filtered_logs.toOwnedSlice();
    }
};

// Log stream for real-time logging
pub const LogStream = struct {
    allocator: std.mem.Allocator,
    job_id: u32,
    buffer: std.ArrayList(u8),
    subscribers: std.ArrayList(*const LogSubscriber),
    
    pub const LogSubscriber = struct {
        onLogEntry: *const fn (self: *const LogSubscriber, entry: LogEntry) void,
    };
    
    pub fn init(allocator: std.mem.Allocator, job_id: u32) LogStream {
        return LogStream{
            .allocator = allocator,
            .job_id = job_id,
            .buffer = std.ArrayList(u8).init(allocator),
            .subscribers = std.ArrayList(*const LogSubscriber).init(allocator),
        };
    }
    
    pub fn deinit(self: *LogStream) void {
        self.buffer.deinit();
        self.subscribers.deinit();
    }
    
    pub fn write(self: *LogStream, data: []const u8) !void {
        try self.buffer.appendSlice(data);
    }
    
    pub fn readLine(self: *LogStream) !?[]const u8 {
        // Mock implementation - return buffer contents if any
        if (self.buffer.items.len > 0) {
            const line = try self.allocator.dupe(u8, self.buffer.items);
            self.buffer.clearRetainingCapacity();
            return line;
        }
        return null;
    }
    
    pub fn subscribe(self: *LogStream, subscriber: *const LogSubscriber) !void {
        try self.subscribers.append(subscriber);
    }
    
    fn notifySubscribers(self: *LogStream, entry: LogEntry) void {
        for (self.subscribers.items) |subscriber| {
            subscriber.onLogEntry(subscriber, entry);
        }
    }
};

// Log aggregator for managing multiple job logs
pub const LogAggregator = struct {
    allocator: std.mem.Allocator,
    storage: LogStorage,
    streams: std.HashMap(u32, *LogStream, std.HashMap.AutoContext(u32), std.hash_map.default_max_load_percentage),
    enable_streaming: bool,
    
    pub fn init(allocator: std.mem.Allocator, config: struct {
        storage_backend: LogStorageBackend = .memory,
        enable_streaming: bool = false,
    }) !LogAggregator {
        return LogAggregator{
            .allocator = allocator,
            .storage = try LogStorage.init(allocator, .{
                .backend = config.storage_backend,
            }),
            .streams = std.HashMap(u32, *LogStream, std.HashMap.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .enable_streaming = config.enable_streaming,
        };
    }
    
    pub fn deinit(self: *LogAggregator) void {
        // Clean up streams
        var streams_iter = self.streams.iterator();
        while (streams_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.streams.deinit();
        
        self.storage.deinit();
    }
    
    pub fn createLogStream(self: *LogAggregator, job_id: u32) !*LogStream {
        const stream = try self.allocator.create(LogStream);
        stream.* = LogStream.init(self.allocator, job_id);
        
        try self.streams.put(job_id, stream);
        return stream;
    }
    
    pub fn appendLog(self: *LogAggregator, job_id: u32, entry: LogEntry) !void {
        // Store in persistent storage
        try self.storage.storeLog(job_id, entry);
        
        // Notify stream subscribers if streaming enabled
        if (self.enable_streaming) {
            if (self.streams.get(job_id)) |stream| {
                stream.notifySubscribers(entry);
            }
        }
    }
    
    pub fn subscribe(self: *LogAggregator, job_id: u32, subscriber: anytype) !void {
        const stream = self.streams.get(job_id) orelse {
            return error.JobNotFound;
        };
        
        // Create a type-erased subscriber
        const Subscriber = struct {
            inner: @TypeOf(subscriber),
            
            pub fn onLogEntry(self: *const LogStream.LogSubscriber, entry: LogEntry) void {
                const typed_self = @fieldParentPtr(@This(), "subscriber", self);
                typed_self.inner.onLogEntry(entry) catch {};
            }
            
            subscriber: LogStream.LogSubscriber,
        };
        
        const typed_subscriber = try self.allocator.create(Subscriber);
        typed_subscriber.* = Subscriber{
            .inner = subscriber,
            .subscriber = LogStream.LogSubscriber{
                .onLogEntry = Subscriber.onLogEntry,
            },
        };
        
        try stream.subscribe(&typed_subscriber.subscriber);
    }
};

// Tests for logging system
test "log storage stores and retrieves logs" {
    const allocator = testing.allocator;
    
    var log_storage = try LogStorage.init(allocator, .{
        .backend = .memory,
    });
    defer log_storage.deinit();
    
    const job_id: u32 = 123;
    
    // Store test logs
    const test_logs = [_]LogEntry{
        .{ .timestamp = 1000000000, .level = .info, .step_name = "Build", .message = "Starting build" },
        .{ .timestamp = 1000000001, .level = .info, .step_name = "Build", .message = "Compiling source" },
        .{ .timestamp = 1000000002, .level = .error, .step_name = "Build", .message = "Compilation failed" },
        .{ .timestamp = 1000000003, .level = .info, .step_name = "Build", .message = "Build completed with errors" },
    };
    
    for (test_logs) |log_entry| {
        try log_storage.storeLog(job_id, log_entry);
    }
    
    // Query all logs
    const all_logs = try log_storage.getJobLogs(job_id, .{});
    defer {
        for (all_logs) |*log| {
            log.deinit(allocator);
        }
        allocator.free(all_logs);
    }
    
    try testing.expectEqual(@as(usize, 4), all_logs.len);
    
    // Query error logs only
    const error_logs = try log_storage.getJobLogs(job_id, .{
        .level = .error,
    });
    defer {
        for (error_logs) |*log| {
            log.deinit(allocator);
        }
        allocator.free(error_logs);
    }
    
    try testing.expectEqual(@as(usize, 1), error_logs.len);
    try testing.expect(std.mem.eql(u8, error_logs[0].message, "Compilation failed"));
}

test "log aggregator manages multiple job streams" {
    const allocator = testing.allocator;
    
    var log_aggregator = try LogAggregator.init(allocator, .{
        .storage_backend = .memory,
        .enable_streaming = true,
    });
    defer log_aggregator.deinit();
    
    const job_id: u32 = 456;
    
    // Create log stream
    var log_stream = try log_aggregator.createLogStream(job_id);
    _ = log_stream; // Avoid unused variable warning
    
    // Write log entries
    const log_entries = [_]LogEntry{
        .{
            .timestamp = std.time.nanoTimestamp(),
            .level = .info,
            .step_name = "Setup",
            .message = "Starting step execution",
        },
        .{
            .timestamp = std.time.nanoTimestamp(),
            .level = .info,
            .step_name = "Setup",
            .message = "Environment configured",
        },
        .{
            .timestamp = std.time.nanoTimestamp(),
            .level = .info,
            .step_name = "Setup",
            .message = "Step completed successfully",
        },
    };
    
    for (log_entries) |entry| {
        try log_aggregator.appendLog(job_id, entry);
    }
    
    // Verify logs were stored
    const stored_logs = try log_aggregator.storage.getJobLogs(job_id, .{});
    defer {
        for (stored_logs) |*log| {
            log.deinit(allocator);
        }
        allocator.free(stored_logs);
    }
    
    try testing.expectEqual(@as(usize, 3), stored_logs.len);
    try testing.expect(std.mem.eql(u8, stored_logs[0].message, "Starting step execution"));
    try testing.expect(std.mem.eql(u8, stored_logs[0].step_name, "Setup"));
}

test "log filtering works correctly" {
    const allocator = testing.allocator;
    
    var log_storage = try LogStorage.init(allocator, .{
        .backend = .memory,
    });
    defer log_storage.deinit();
    
    const job_id: u32 = 789;
    
    // Store logs with different levels and steps
    const test_logs = [_]LogEntry{
        .{ .timestamp = 1000, .level = .info, .step_name = "Build", .message = "Build started" },
        .{ .timestamp = 2000, .level = .warn, .step_name = "Build", .message = "Warning occurred" },
        .{ .timestamp = 3000, .level = .error, .step_name = "Test", .message = "Test failed" },
        .{ .timestamp = 4000, .level = .info, .step_name = "Test", .message = "Test completed" },
    };
    
    for (test_logs) |log_entry| {
        try log_storage.storeLog(job_id, log_entry);
    }
    
    // Test level filtering
    const error_logs = try log_storage.getJobLogs(job_id, .{ .level = .error });
    defer {
        for (error_logs) |*log| {
            log.deinit(allocator);
        }
        allocator.free(error_logs);
    }
    try testing.expectEqual(@as(usize, 1), error_logs.len);
    
    // Test step filtering
    const build_logs = try log_storage.getJobLogs(job_id, .{ .step_name = "Build" });
    defer {
        for (build_logs) |*log| {
            log.deinit(allocator);
        }
        allocator.free(build_logs);
    }
    try testing.expectEqual(@as(usize, 2), build_logs.len);
    
    // Test time filtering
    const recent_logs = try log_storage.getJobLogs(job_id, .{ .since = 2500 });
    defer {
        for (recent_logs) |*log| {
            log.deinit(allocator);
        }
        allocator.free(recent_logs);
    }
    try testing.expectEqual(@as(usize, 2), recent_logs.len);
    
    // Test limit
    const limited_logs = try log_storage.getJobLogs(job_id, .{ .limit = 2 });
    defer {
        for (limited_logs) |*log| {
            log.deinit(allocator);
        }
        allocator.free(limited_logs);
    }
    try testing.expectEqual(@as(usize, 2), limited_logs.len);
}