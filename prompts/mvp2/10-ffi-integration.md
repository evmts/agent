# Complete FFI Integration and Core Library

## Context

You are implementing the final FFI integration layer that ties together all components built in previous tasks. This creates the complete `libplue.zig` library that implements the entire PLUE_CORE_API.md specification.

### Project State

From previous tasks, you have implemented:
- OpenCode server management
- HTTP client infrastructure  
- API client for OpenCode endpoints
- Session management bridge
- Message system bridge
- Provider management bridge
- Tool system bridge
- Configuration integration
- State synchronization

Now you need to create the unified FFI layer that exports everything.

### Remaining Core API Requirements (from PLUE_CORE_API.md)

```c
// Memory Management
export fn plue_free_state(state: ?*anyopaque) void;
export fn plue_free_string(str: [*c]u8) void;
export fn plue_free_json(json: [*c]u8) void;

// Core Initialization
export fn plue_init(config_json: [*:0]const u8) c_int;
export fn plue_shutdown() void;
export fn plue_get_version() [*:0]const u8;
export fn plue_get_app_info() [*:0]const u8;
export fn plue_set_cwd(path: [*:0]const u8) c_int;

// Error Handling
export fn plue_get_last_error() [*:0]const u8;
export fn plue_get_last_error_json() [*:0]const u8;

// Event System
export fn plue_event_subscribe(callback: plue_event_callback, user_data: ?*anyopaque) u32;
export fn plue_event_unsubscribe(subscription_id: u32) void;
export fn plue_event_poll() [*c]u8;
```

## Requirements

### 1. Core Library Structure (`src/libplue.zig`)

Create the main library file that exports everything:

```zig
const std = @import("std");
const builtin = @import("builtin");

// Import all subsystems
const server = @import("server/manager.zig");
const session = @import("session/ffi.zig");
const message = @import("message/ffi.zig");
const provider = @import("provider/ffi.zig");
const tool = @import("tool/ffi.zig");
const config = @import("config/ffi.zig");
const state = @import("state/ffi.zig");
const event_system = @import("event/system.zig");
const error_handling = @import("error/handling.zig");
const memory = @import("core/memory.zig");

// Version information
const VERSION = "0.1.0";
const BUILD_COMMIT = @embedFile("../.git/HEAD") catch "unknown";

/// Global library state
const LibraryState = struct {
    allocator: std.mem.Allocator,
    initialized: bool = false,
    server_manager: ?*server.ServerManager = null,
    opencode_api: ?*opencode.OpenCodeApi = null,
    event_bus: ?*event_system.EventBus = null,
    start_time: i64,
    working_directory: []const u8,
    
    /// Cleanup all resources
    fn deinit(self: *LibraryState) void {
        // Stop all subsystems
        if (self.server_manager) |mgr| {
            mgr.stop() catch {};
            mgr.deinit();
            self.allocator.destroy(mgr);
        }
        
        if (self.opencode_api) |api| {
            api.deinit();
            self.allocator.destroy(api);
        }
        
        if (self.event_bus) |bus| {
            bus.deinit();
            self.allocator.destroy(bus);
        }
        
        // Free working directory
        self.allocator.free(self.working_directory);
        
        self.initialized = false;
    }
};

/// Global library instance
var library: ?LibraryState = null;
var library_mutex = std.Thread.Mutex{};

/// Initialize the Plue core library
export fn plue_init(config_json: [*:0]const u8) c_int {
    library_mutex.lock();
    defer library_mutex.unlock();
    
    // Check if already initialized
    if (library != null and library.?.initialized) {
        error_handling.setLastError(error.AlreadyInitialized, "Library is already initialized");
        return -1;
    }
    
    // Create allocator
    const allocator = std.heap.c_allocator;
    
    // Initialize library state
    library = LibraryState{
        .allocator = allocator,
        .start_time = std.time.milliTimestamp(),
        .working_directory = std.fs.cwd().realpathAlloc(allocator, ".") catch |err| {
            error_handling.setLastError(err, "Failed to get working directory");
            return -1;
        },
    };
    
    // Parse configuration
    const config_slice = if (config_json != null) std.mem.span(config_json) else null;
    
    // Initialize error handling
    error_handling.init(allocator);
    
    // Initialize event bus
    library.?.event_bus = allocator.create(event_system.EventBus) catch |err| {
        error_handling.setLastError(err, "Failed to create event bus");
        library.?.deinit();
        library = null;
        return -1;
    };
    library.?.event_bus.?.* = event_system.EventBus.init(allocator) catch |err| {
        error_handling.setLastError(err, "Failed to initialize event bus");
        library.?.deinit();
        library = null;
        return -1;
    };
    
    // Initialize memory tracking
    memory.init(allocator);
    
    // Initialize server manager
    const server_config = server.ServerConfig.initDefault(allocator) catch |err| {
        error_handling.setLastError(err, "Failed to create server config");
        library.?.deinit();
        library = null;
        return -1;
    };
    
    library.?.server_manager = allocator.create(server.ServerManager) catch |err| {
        error_handling.setLastError(err, "Failed to create server manager");
        library.?.deinit();
        library = null;
        return -1;
    };
    
    library.?.server_manager.?.* = server.ServerManager.init(allocator, server_config) catch |err| {
        error_handling.setLastError(err, "Failed to initialize server manager");
        library.?.deinit();
        library = null;
        return -1;
    };
    
    // Start OpenCode server
    library.?.server_manager.?.start() catch |err| {
        error_handling.setLastError(err, "Failed to start OpenCode server");
        library.?.deinit();
        library = null;
        return -1;
    };
    
    // Initialize OpenCode API client
    const server_url = library.?.server_manager.?.getUrl() catch |err| {
        error_handling.setLastError(err, "Failed to get server URL");
        library.?.deinit();
        library = null;
        return -1;
    };
    
    library.?.opencode_api = allocator.create(opencode.OpenCodeApi) catch |err| {
        error_handling.setLastError(err, "Failed to create API client");
        library.?.deinit();
        library = null;
        return -1;
    };
    
    library.?.opencode_api.?.* = opencode.OpenCodeApi.init(allocator, server_url) catch |err| {
        error_handling.setLastError(err, "Failed to initialize API client");
        library.?.deinit();
        library = null;
        return -1;
    };
    
    // Wait for server to be ready
    library.?.opencode_api.?.waitForReady(30000) catch |err| {
        error_handling.setLastError(err, "OpenCode server failed to start");
        library.?.deinit();
        library = null;
        return -1;
    };
    
    // Initialize all subsystems
    initializeSubsystems() catch |err| {
        error_handling.setLastError(err, "Failed to initialize subsystems");
        library.?.deinit();
        library = null;
        return -1;
    };
    
    // Load configuration
    config.init(allocator) catch |err| {
        error_handling.setLastError(err, "Failed to initialize config");
        library.?.deinit();
        library = null;
        return -1;
    };
    
    _ = plue_config_load();
    
    library.?.initialized = true;
    
    // Emit initialization event
    event_system.emitGlobalEvent(.{ .library_initialized = .{
        .version = VERSION,
        .timestamp = library.?.start_time,
    } }) catch {};
    
    return 0;
}

/// Initialize all subsystems
fn initializeSubsystems() !void {
    const lib = &library.?;
    
    // Initialize session management
    try session.init(lib.allocator, lib.opencode_api.?);
    
    // Initialize message system
    try message.init(lib.allocator, lib.opencode_api.?);
    
    // Initialize provider management
    try provider.init(lib.allocator, lib.opencode_api.?);
    
    // Initialize tool system
    try tool.init(lib.allocator, lib.opencode_api.?);
    
    // Initialize state synchronization
    try state.init(lib.allocator, lib.opencode_api.?);
}

/// Shutdown the core library and free all resources
export fn plue_shutdown() void {
    library_mutex.lock();
    defer library_mutex.unlock();
    
    if (library) |*lib| {
        // Emit shutdown event
        event_system.emitGlobalEvent(.{ .library_shutdown = {} }) catch {};
        
        // Clean up all subsystems
        lib.deinit();
        library = null;
    }
    
    // Clean up error handling
    error_handling.deinit();
    
    // Clean up memory tracking
    memory.deinit();
}

/// Get current library version
export fn plue_get_version() [*:0]const u8 {
    return VERSION;
}

/// Get application info as JSON
export fn plue_get_app_info() [*:0]const u8 {
    library_mutex.lock();
    defer library_mutex.unlock();
    
    if (library == null or !library.?.initialized) {
        error_handling.setLastError(error.NotInitialized, "Library not initialized");
        return "";
    }
    
    const lib = &library.?;
    
    // Get system info
    const user = std.process.getEnvVarOwned(lib.allocator, "USER") catch "unknown";
    defer lib.allocator.free(user);
    
    const is_git = detectGitRepo(lib.allocator) catch false;
    
    const app_info = .{
        .version = VERSION,
        .build = .{
            .commit = std.mem.trim(u8, BUILD_COMMIT, "\n"),
            .target = @tagName(builtin.target.os.tag),
            .mode = @tagName(builtin.mode),
        },
        .user = user,
        .git = is_git,
        .paths = .{
            .cwd = lib.working_directory,
            .home = std.process.getEnvVarOwned(lib.allocator, "HOME") catch null,
        },
        .time = .{
            .started = lib.start_time,
            .uptime_ms = std.time.milliTimestamp() - lib.start_time,
        },
        .server = .{
            .running = if (lib.server_manager) |mgr| mgr.getState() == .running else false,
            .url = if (lib.server_manager) |mgr| mgr.getUrl() catch null else null,
        },
    };
    
    const json_string = std.json.stringifyAlloc(
        lib.allocator,
        app_info,
        .{ .whitespace = .indent_2 },
    ) catch |err| {
        error_handling.setLastError(err, "Failed to create app info");
        return "";
    };
    
    // Store in memory manager for later freeing
    memory.trackJson(json_string) catch {
        lib.allocator.free(json_string);
        return "";
    };
    
    return @ptrCast([*:0]const u8, json_string.ptr);
}

/// Set the current working directory
export fn plue_set_cwd(path: [*:0]const u8) c_int {
    if (path == null) {
        error_handling.setLastError(error.InvalidParam, "Path is null");
        return -1;
    }
    
    library_mutex.lock();
    defer library_mutex.unlock();
    
    if (library == null or !library.?.initialized) {
        error_handling.setLastError(error.NotInitialized, "Library not initialized");
        return -1;
    }
    
    const path_slice = std.mem.span(path);
    
    // Change directory
    std.os.chdir(path_slice) catch |err| {
        error_handling.setLastError(err, "Failed to change directory");
        return -1;
    };
    
    // Update stored working directory
    const lib = &library.?;
    lib.allocator.free(lib.working_directory);
    lib.working_directory = lib.allocator.dupe(u8, path_slice) catch |err| {
        error_handling.setLastError(err, "Failed to update working directory");
        return -1;
    };
    
    return 0;
}

/// Detect if current directory is a git repository
fn detectGitRepo(allocator: std.mem.Allocator) !bool {
    const git_path = try std.fs.path.join(allocator, &.{ ".git" });
    defer allocator.free(git_path);
    
    std.fs.accessAbsolute(git_path, .{}) catch return false;
    return true;
}
```

### 2. Memory Management (`src/core/memory.zig`)

Implement memory tracking and freeing:

```zig
const std = @import("std");

/// Memory tracking for allocated strings
const MemoryTracker = struct {
    allocator: std.mem.Allocator,
    strings: std.AutoHashMap(usize, []u8),
    json_strings: std.AutoHashMap(usize, []u8),
    mutex: std.Thread.Mutex,
    
    fn init(allocator: std.mem.Allocator) MemoryTracker {
        return .{
            .allocator = allocator,
            .strings = std.AutoHashMap(usize, []u8).init(allocator),
            .json_strings = std.AutoHashMap(usize, []u8).init(allocator),
            .mutex = .{},
        };
    }
    
    fn deinit(self: *MemoryTracker) void {
        // Free all tracked strings
        var it = self.strings.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.strings.deinit();
        
        var json_it = self.json_strings.iterator();
        while (json_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.json_strings.deinit();
    }
    
    fn trackString(self: *MemoryTracker, str: []u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const addr = @intFromPtr(str.ptr);
        try self.strings.put(addr, str);
    }
    
    fn trackJson(self: *MemoryTracker, json: []u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const addr = @intFromPtr(json.ptr);
        try self.json_strings.put(addr, json);
    }
    
    fn freeString(self: *MemoryTracker, ptr: [*c]u8) void {
        if (ptr == null) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const addr = @intFromPtr(ptr);
        if (self.strings.fetchRemove(addr)) |entry| {
            self.allocator.free(entry.value);
        }
    }
    
    fn freeJson(self: *MemoryTracker, ptr: [*c]u8) void {
        if (ptr == null) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const addr = @intFromPtr(ptr);
        if (self.json_strings.fetchRemove(addr)) |entry| {
            self.allocator.free(entry.value);
        }
    }
};

/// Global memory tracker
var memory_tracker: ?MemoryTracker = null;

/// Initialize memory tracking
pub fn init(allocator: std.mem.Allocator) void {
    memory_tracker = MemoryTracker.init(allocator);
}

/// Cleanup memory tracking
pub fn deinit() void {
    if (memory_tracker) |*tracker| {
        tracker.deinit();
        memory_tracker = null;
    }
}

/// Track a string allocation
pub fn trackString(str: []u8) !void {
    if (memory_tracker) |*tracker| {
        try tracker.trackString(str);
    }
}

/// Track a JSON allocation
pub fn trackJson(json: []u8) !void {
    if (memory_tracker) |*tracker| {
        try tracker.trackJson(json);
    }
}

/// Free any state structure returned by Zig
export fn plue_free_state(state: ?*anyopaque) void {
    // State structures handle their own cleanup through reference counting
    // This is here for API compatibility
    _ = state;
}

/// Free a string allocated by Zig
export fn plue_free_string(str: [*c]u8) void {
    if (memory_tracker) |*tracker| {
        tracker.freeString(str);
    }
}

/// Free a JSON response allocated by Zig
export fn plue_free_json(json: [*c]u8) void {
    if (memory_tracker) |*tracker| {
        tracker.freeJson(json);
    }
}
```

### 3. Error Handling (`src/error/handling.zig`)

Enhanced error handling with JSON support:

```zig
const std = @import("std");

pub const PlueError = error{
    // Initialization errors
    NotInitialized,
    AlreadyInitialized,
    
    // Parameter errors
    InvalidParam,
    MissingParam,
    
    // Resource errors
    NotFound,
    AlreadyExists,
    
    // Provider errors
    ProviderAuth,
    ProviderInit,
    UnknownProvider,
    NotAuthenticated,
    
    // Parse errors
    JsonParse,
    InvalidFormat,
    
    // IO errors
    IoError,
    PermissionDenied,
    
    // Network errors
    Timeout,
    ConnectionFailed,
    
    // Operation errors
    Aborted,
    OperationFailed,
    
    // State errors
    NoState,
    StateMismatch,
    
    // Generic
    Unknown,
};

const ErrorInfo = struct {
    code: PlueError,
    message: []const u8,
    details: ?[]const u8 = null,
    stack_trace: ?[]const u8 = null,
    timestamp: i64,
};

/// Thread-local error storage
threadlocal var last_error: ?ErrorInfo = null;
var error_allocator: std.mem.Allocator = undefined;

/// Initialize error handling
pub fn init(allocator: std.mem.Allocator) void {
    error_allocator = allocator;
}

/// Cleanup error handling
pub fn deinit() void {
    clearLastError();
}

/// Set last error with context
pub fn setLastError(err: anyerror, message: []const u8) void {
    clearLastError();
    
    const error_code = mapErrorCode(err);
    
    last_error = ErrorInfo{
        .code = error_code,
        .message = error_allocator.dupe(u8, message) catch message,
        .details = if (@errorReturnTrace()) |trace| 
            std.fmt.allocPrint(error_allocator, "{}", .{trace}) catch null
        else 
            null,
        .stack_trace = captureStackTrace(),
        .timestamp = std.time.milliTimestamp(),
    };
}

/// Clear last error
fn clearLastError() void {
    if (last_error) |*err| {
        if (err.message.ptr != @intFromPtr("") and err.message.len > 0) {
            error_allocator.free(err.message);
        }
        if (err.details) |details| {
            error_allocator.free(details);
        }
        if (err.stack_trace) |trace| {
            error_allocator.free(trace);
        }
        last_error = null;
    }
}

/// Map generic errors to PlueError
fn mapErrorCode(err: anyerror) PlueError {
    return switch (err) {
        error.OutOfMemory => PlueError.Unknown,
        error.FileNotFound => PlueError.NotFound,
        error.AccessDenied => PlueError.PermissionDenied,
        error.Unexpected => PlueError.Unknown,
        else => {
            // Check if it's already a PlueError
            inline for (@typeInfo(PlueError).ErrorSet.?) |e| {
                if (std.mem.eql(u8, @errorName(err), e.name)) {
                    return @field(PlueError, e.name);
                }
            }
            return PlueError.Unknown;
        },
    };
}

/// Capture current stack trace
fn captureStackTrace() ?[]const u8 {
    // In debug builds, capture stack trace
    if (builtin.mode == .Debug) {
        var buffer: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        
        // This is a simplified example - real implementation would use
        // std.debug.captureStackTrace and format it nicely
        return std.fmt.allocPrint(
            error_allocator,
            "Stack trace capture not implemented",
            .{},
        ) catch null;
    }
    return null;
}

/// Get human-readable error message for last error on current thread
export fn plue_get_last_error() [*:0]const u8 {
    if (last_error) |err| {
        return @ptrCast([*:0]const u8, err.message.ptr);
    }
    return "No error";
}

/// Get detailed error JSON with stack trace and context
export fn plue_get_last_error_json() [*:0]const u8 {
    if (last_error) |err| {
        const error_obj = .{
            .error = .{
                .code = @errorName(err.code),
                .message = err.message,
                .details = err.details,
                .stack_trace = err.stack_trace,
                .timestamp = err.timestamp,
            },
        };
        
        const json = std.json.stringifyAlloc(
            error_allocator,
            error_obj,
            .{ .whitespace = .indent_2 },
        ) catch return "{}";
        
        // Note: This leaks memory but is acceptable for error messages
        return @ptrCast([*:0]const u8, json.ptr);
    }
    
    return "{}";
}
```

### 4. Event System (`src/event/system.zig`)

Global event bus implementation:

```zig
const std = @import("std");

pub const EventType = enum(u8) {
    // Session events
    SESSION_CREATED,
    SESSION_UPDATED,
    SESSION_DELETED,
    
    // Message events
    MESSAGE_CREATED,
    MESSAGE_UPDATED,
    MESSAGE_PART_UPDATED,
    
    // Provider events
    PROVIDER_CHANGED,
    
    // Config events
    CONFIG_CHANGED,
    
    // System events
    ERROR,
    LIBRARY_INITIALIZED,
    LIBRARY_SHUTDOWN,
};

pub const Event = struct {
    type: EventType,
    data: []const u8, // JSON data
    timestamp: i64,
};

pub const Subscription = struct {
    id: u32,
    callback: *const fn (EventType, [*c]const u8, ?*anyopaque) callconv(.C) void,
    user_data: ?*anyopaque,
    active: bool = true,
};

pub const EventBus = struct {
    allocator: std.mem.Allocator,
    subscriptions: std.ArrayList(Subscription),
    event_queue: std.ArrayList(Event),
    next_subscription_id: u32 = 1,
    mutex: std.Thread.Mutex,
    
    pub fn init(allocator: std.mem.Allocator) !EventBus {
        return EventBus{
            .allocator = allocator,
            .subscriptions = std.ArrayList(Subscription).init(allocator),
            .event_queue = std.ArrayList(Event).init(allocator),
            .mutex = .{},
        };
    }
    
    pub fn deinit(self: *EventBus) void {
        // Free queued events
        for (self.event_queue.items) |event| {
            self.allocator.free(event.data);
        }
        self.event_queue.deinit();
        self.subscriptions.deinit();
    }
    
    pub fn subscribe(
        self: *EventBus,
        callback: *const fn (EventType, [*c]const u8, ?*anyopaque) callconv(.C) void,
        user_data: ?*anyopaque,
    ) !u32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const id = self.next_subscription_id;
        self.next_subscription_id += 1;
        
        try self.subscriptions.append(.{
            .id = id,
            .callback = callback,
            .user_data = user_data,
        });
        
        return id;
    }
    
    pub fn unsubscribe(self: *EventBus, id: u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        for (self.subscriptions.items, 0..) |sub, i| {
            if (sub.id == id) {
                _ = self.subscriptions.swapRemove(i);
                break;
            }
        }
    }
    
    pub fn emit(self: *EventBus, event_type: EventType, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const event = Event{
            .type = event_type,
            .data = try self.allocator.dupe(u8, data),
            .timestamp = std.time.milliTimestamp(),
        };
        
        // Queue event
        try self.event_queue.append(event);
        
        // Notify subscribers
        for (self.subscriptions.items) |sub| {
            if (sub.active) {
                sub.callback(@intFromEnum(event_type), event.data.ptr, sub.user_data);
            }
        }
    }
    
    pub fn poll(self: *EventBus) ?Event {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.event_queue.items.len > 0) {
            return self.event_queue.orderedRemove(0);
        }
        
        return null;
    }
};

/// Global event bus instance
var global_event_bus: ?*EventBus = null;

/// Set global event bus
pub fn setGlobalEventBus(bus: *EventBus) void {
    global_event_bus = bus;
}

/// Emit event to global bus
pub fn emitGlobalEvent(event: anytype) !void {
    if (global_event_bus) |bus| {
        const json = try std.json.stringifyAlloc(bus.allocator, event, .{});
        defer bus.allocator.free(json);
        
        const event_type = detectEventType(event);
        try bus.emit(event_type, json);
    }
}

fn detectEventType(event: anytype) EventType {
    const T = @TypeOf(event);
    if (@hasField(T, "library_initialized")) return .LIBRARY_INITIALIZED;
    if (@hasField(T, "library_shutdown")) return .LIBRARY_SHUTDOWN;
    if (@hasField(T, "session_created")) return .SESSION_CREATED;
    if (@hasField(T, "session_updated")) return .SESSION_UPDATED;
    if (@hasField(T, "session_deleted")) return .SESSION_DELETED;
    if (@hasField(T, "message_created")) return .MESSAGE_CREATED;
    if (@hasField(T, "message_updated")) return .MESSAGE_UPDATED;
    if (@hasField(T, "provider_changed")) return .PROVIDER_CHANGED;
    if (@hasField(T, "config_changed")) return .CONFIG_CHANGED;
    return .ERROR;
}

/// Event callback type
pub const plue_event_callback = *const fn (u8, [*c]const u8, ?*anyopaque) callconv(.C) void;

/// Subscribe to events
export fn plue_event_subscribe(callback: plue_event_callback, user_data: ?*anyopaque) u32 {
    if (global_event_bus) |bus| {
        return bus.subscribe(callback, user_data) catch {
            error_handling.setLastError(error.OperationFailed, "Failed to subscribe");
            return 0;
        };
    }
    
    error_handling.setLastError(error.NotInitialized, "Event bus not initialized");
    return 0;
}

/// Unsubscribe from events
export fn plue_event_unsubscribe(subscription_id: u32) void {
    if (global_event_bus) |bus| {
        bus.unsubscribe(subscription_id);
    }
}

/// Poll for events (alternative to callbacks)
export fn plue_event_poll() [*c]u8 {
    if (global_event_bus) |bus| {
        if (bus.poll()) |event| {
            // Create event JSON
            const event_obj = .{
                .type = @intFromEnum(event.type),
                .data = std.json.parseFromSlice(
                    std.json.Value,
                    bus.allocator,
                    event.data,
                    .{},
                ) catch std.json.Value{ .null = {} },
                .timestamp = event.timestamp,
            };
            
            const json = std.json.stringifyAlloc(
                bus.allocator,
                event_obj,
                .{},
            ) catch return null;
            
            // Track for cleanup
            memory.trackJson(json) catch {
                bus.allocator.free(json);
                return null;
            };
            
            // Free original event data
            bus.allocator.free(event.data);
            
            return json.ptr;
        }
    }
    
    return null;
}
```

### 5. Integration Tests (`test/integration.zig`)

Comprehensive integration tests:

```zig
const std = @import("std");
const plue = @import("../src/libplue.zig");
const testing = std.testing;

test "full library lifecycle" {
    // Initialize
    try testing.expectEqual(@as(c_int, 0), plue.plue_init(null));
    defer plue.plue_shutdown();
    
    // Get version
    const version = plue.plue_get_version();
    try testing.expect(version != null);
    
    // Get app info
    const app_info = plue.plue_get_app_info();
    try testing.expect(app_info != null);
    plue.plue_free_json(@ptrCast([*c]u8, app_info));
}

test "session management flow" {
    try testing.expectEqual(@as(c_int, 0), plue.plue_init(null));
    defer plue.plue_shutdown();
    
    // Create session
    const session = plue.plue_session_create(null);
    try testing.expect(session != null);
    defer plue.plue_session_destroy(session);
    
    // Get session info
    const info = plue.plue_session_get_info(session);
    try testing.expect(info != null);
    plue.plue_free_json(info);
    
    // Update title
    try testing.expectEqual(@as(c_int, 0), plue.plue_session_update_title(session, "Test Session"));
}

test "message sending and streaming" {
    try testing.expectEqual(@as(c_int, 0), plue.plue_init(null));
    defer plue.plue_shutdown();
    
    // Create session
    const session = plue.plue_session_create(null);
    try testing.expect(session != null);
    defer plue.plue_session_destroy(session);
    
    // Send message
    const message_json = 
        \\{"text": "Hello, world!", "attachments": []}
    ;
    const message_id = plue.plue_message_send(session, message_json);
    try testing.expect(message_id != null);
    defer plue.plue_free_string(message_id);
    
    // List messages
    const messages = plue.plue_message_list(session);
    try testing.expect(messages != null);
    plue.plue_free_json(messages);
}

test "provider management" {
    try testing.expectEqual(@as(c_int, 0), plue.plue_init(null));
    defer plue.plue_shutdown();
    
    // List providers
    const providers = plue.plue_provider_list();
    try testing.expect(providers != null);
    plue.plue_free_json(providers);
    
    // Configure provider
    const config = 
        \\{"apiKey": "test-key"}
    ;
    const result = plue.plue_provider_configure("anthropic", config);
    try testing.expect(result == 0 or result == -1); // May fail without real key
}

test "tool execution" {
    try testing.expectEqual(@as(c_int, 0), plue.plue_init(null));
    defer plue.plue_shutdown();
    
    // List tools
    const tools = plue.plue_tool_list();
    try testing.expect(tools != null);
    plue.plue_free_json(tools);
    
    // Execute read tool
    var context = plue.plue_tool_context_t{
        .session_id = null,
        .message_id = null,
        .abort_signal = null,
        .metadata_callback = null,
        .user_data = null,
    };
    
    const params = 
        \\{"file_path": "/tmp/test.txt"}
    ;
    const result = plue.plue_tool_execute("read", params, &context);
    // May be null if file doesn't exist
    if (result != null) {
        plue.plue_free_json(result);
    }
}

test "configuration management" {
    try testing.expectEqual(@as(c_int, 0), plue.plue_init(null));
    defer plue.plue_shutdown();
    
    // Load config
    try testing.expectEqual(@as(c_int, 0), plue.plue_config_load());
    
    // Get config
    const config = plue.plue_config_get();
    try testing.expect(config != null);
    plue.plue_free_json(config);
    
    // Update config
    const updates = 
        \\{"theme": "dark"}
    ;
    try testing.expectEqual(@as(c_int, 0), plue.plue_config_update(updates, false));
}

test "state synchronization" {
    try testing.expectEqual(@as(c_int, 0), plue.plue_init(null));
    defer plue.plue_shutdown();
    
    // Get state snapshot
    const snapshot = plue.plue_state_get_snapshot();
    try testing.expect(snapshot != null);
    defer plue.plue_state_free_snapshot(snapshot);
    
    // Get JSON
    const json = plue.plue_state_snapshot_to_json(snapshot);
    try testing.expect(json != null);
    
    // Get changes (should be null for first snapshot)
    const changes = plue.plue_state_get_changes(snapshot);
    if (changes != null) {
        plue.plue_free_json(changes);
    }
}

test "event system" {
    try testing.expectEqual(@as(c_int, 0), plue.plue_init(null));
    defer plue.plue_shutdown();
    
    // Subscribe to events
    const Context = struct {
        received: bool = false,
    };
    var ctx = Context{};
    
    const subscription = plue.plue_event_subscribe(struct {
        fn callback(event_type: u8, data: [*c]const u8, user_data: ?*anyopaque) callconv(.C) void {
            _ = event_type;
            _ = data;
            const context = @ptrCast(*Context, @alignCast(@alignOf(Context), user_data.?));
            context.received = true;
        }
    }.callback, &ctx);
    
    try testing.expect(subscription > 0);
    defer plue.plue_event_unsubscribe(subscription);
    
    // Poll for events
    const event = plue.plue_event_poll();
    if (event != null) {
        plue.plue_free_json(event);
    }
}

test "error handling" {
    // Test before init
    const error_msg = plue.plue_get_last_error();
    try testing.expect(error_msg != null);
    
    // Test with invalid operation
    const session = plue.plue_session_create(null);
    try testing.expect(session == null);
    
    const error_json = plue.plue_get_last_error_json();
    try testing.expect(error_json != null);
}
```

### 6. Build Configuration (`build.zig`)

Update build configuration:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Build static library
    const lib = b.addStaticLibrary(.{
        .name = "plue",
        .root_source_file = b.path("src/libplue.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Build shared library
    const shared_lib = b.addSharedLibrary(.{
        .name = "plue",
        .root_source_file = b.path("src/libplue.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Install artifacts
    b.installArtifact(lib);
    b.installArtifact(shared_lib);
    
    // Install headers
    const install_header = b.addInstallFile(
        b.path("include/plue.h"),
        "include/plue.h",
    );
    b.getInstallStep().dependOn(&install_header.step);
    
    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("test/integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run integration tests");
    test_step.dependOn(&run_tests.step);
    
    // Documentation
    const docs = b.addStaticLibrary(.{
        .name = "plue-docs",
        .root_source_file = b.path("src/libplue.zig"),
        .target = target,
        .optimize = .Debug,
    });
    docs.emit_docs = .emit;
    
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);
}
```

## Implementation Steps

### Step 1: Create Core Library
1. Create `src/libplue.zig`
2. Implement initialization/shutdown
3. Add version and info functions
4. Wire up all subsystems

### Step 2: Implement Memory Management
1. Create `src/core/memory.zig`
2. Add allocation tracking
3. Implement free functions
4. Test memory leaks

### Step 3: Enhance Error Handling
1. Update `src/error/handling.zig`
2. Add JSON error format
3. Implement thread-local storage
4. Test error propagation

### Step 4: Create Event System
1. Create `src/event/system.zig`
2. Implement event bus
3. Add subscription management
4. Test event delivery

### Step 5: Write Integration Tests
1. Create `test/integration.zig`
2. Test full workflows
3. Verify memory management
4. Check error handling

### Step 6: Update Build System
1. Update `build.zig`
2. Configure library outputs
3. Add test targets
4. Generate documentation

## Testing Requirements

1. **Unit Tests** (>95% coverage):
   - Each subsystem individually
   - Memory management
   - Error handling
   - Event system

2. **Integration Tests**:
   - Full library lifecycle
   - All API functions
   - Memory leak detection
   - Thread safety

3. **Stress Tests**:
   - Concurrent operations
   - Large data volumes
   - Rapid init/shutdown
   - Error recovery

## Success Criteria

The implementation is complete when:
- [ ] All PLUE_CORE_API.md functions are implemented
- [ ] Memory management is leak-free
- [ ] Error handling is comprehensive
- [ ] Event system works reliably
- [ ] Integration tests pass
- [ ] Documentation is complete
- [ ] Library can be used from C/Swift
- [ ] Performance meets requirements

## Git Workflow

Complete the implementation:
```bash
cd ../plue-server-management

# Final commits
git add -A
git commit -m "feat: implement core FFI library

- Add libplue.zig with all exports
- Implement memory management
- Add comprehensive error handling
- Create event system
- Wire up all subsystems"

# Create pull request
git push origin feat_add_opencode_server_management
gh pr create --title "feat: add OpenCode server management and FFI integration" \
  --body "Implements complete MVP2 architecture with OpenCode integration"
```

## Final Checklist

Before marking complete:
- [ ] All 10 implementation tasks completed
- [ ] PLUE_CORE_API.md fully implemented
- [ ] All tests passing
- [ ] No memory leaks
- [ ] Documentation updated
- [ ] Swift integration tested
- [ ] Performance acceptable
- [ ] Code reviewed

This completes the MVP2 implementation!