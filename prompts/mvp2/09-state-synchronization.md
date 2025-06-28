# Build State Synchronization System

## Context

You are implementing the state synchronization system that keeps Plue's local state cache in sync with OpenCode's state. This is critical for providing responsive UI updates while maintaining consistency with the backend.

### Project State

From previous tasks, you have:
- All API bridges functioning (session, message, provider, tool)
- Configuration integration working
- OpenCode server running and accessible

Now you need to build efficient state synchronization.

### State Synchronization API Requirements (from PLUE_CORE_API.md)

```c
// Opaque state snapshot handle
typedef struct plue_state_snapshot* plue_state_snapshot_t;

// Get complete application state snapshot
export fn plue_state_get_snapshot() ?*anyopaque;

// Get state as JSON from a snapshot
export fn plue_state_snapshot_to_json(snapshot: ?*anyopaque) [*:0]const u8;

// Free a state snapshot
export fn plue_state_free_snapshot(snapshot: ?*anyopaque) void;

// Get state changes since last snapshot
export fn plue_state_get_changes(last_snapshot: ?*anyopaque) [*c]u8;

// Register for state change notifications
typedef fn(?*anyopaque) callconv(.C) void plue_state_callback;
export fn plue_state_set_callback(callback: plue_state_callback, user_data: ?*anyopaque) void;

// Clear state change callback
export fn plue_state_clear_callback() void;
```

### State Architecture

The state system needs to:
1. Cache OpenCode state locally for performance
2. Monitor OpenCode's event bus for real-time updates
3. Poll periodically as fallback for missed events
4. Detect changes and generate diffs efficiently
5. Notify Swift UI of state changes via callbacks
6. Provide immutable snapshots for thread safety
7. Handle OpenCode's App.state() pattern for service state

**OpenCode State Management**:
- Uses `App.state()` for service-level state management
- State stored per-project in `~/.local/share/opencode/project/{git-hash}/`
- No built-in state synchronization - each service manages its own state
- Event bus provides real-time updates for sessions/messages/etc
- State persistence handled by individual services

## Requirements

### 1. State Types (`src/state/types.zig`)

Define state structures:

```zig
const std = @import("std");
const opencode = @import("../opencode/types.zig");

pub const AppState = struct {
    /// Current sessions
    sessions: []SessionState,
    
    /// Active session ID
    active_session_id: ?[]const u8 = null,
    
    /// Provider states
    providers: []ProviderState,
    
    /// Tool availability
    tools: []ToolState,
    
    /// Current configuration
    config: ConfigState,
    
    /// UI-specific state
    ui: UiState,
    
    /// Metadata
    metadata: StateMetadata,
};

pub const SessionState = struct {
    id: []const u8,
    title: ?[]const u8,
    parent_id: ?[]const u8,
    created: i64,
    updated: i64,
    message_count: u32,
    last_message_id: ?[]const u8,
    is_streaming: bool = false,
    share_url: ?[]const u8 = null,
};

pub const ProviderState = struct {
    id: []const u8,
    name: []const u8,
    enabled: bool,
    authenticated: bool,
    model_count: u32,
    selected_model: ?[]const u8,
    error: ?[]const u8,
};

pub const ToolState = struct {
    name: []const u8,
    available: bool,
    executing: bool = false,
    last_execution: ?i64 = null,
    execution_count: u32 = 0,
};

pub const ConfigState = struct {
    theme: []const u8,
    auto_save: bool,
    telemetry: bool,
    server_status: ServerStatus,
};

pub const ServerStatus = enum {
    stopped,
    starting,
    running,
    error,
};

pub const UiState = struct {
    /// Currently selected tab
    current_tab: TabType = .chat,
    
    /// Sidebar visibility
    sidebar_visible: bool = true,
    
    /// Search query
    search_query: ?[]const u8 = null,
    
    /// Notification count
    unread_notifications: u32 = 0,
};

pub const TabType = enum {
    chat,
    files,
    terminal,
    settings,
};

pub const StateMetadata = struct {
    /// Version for compatibility
    version: u32,
    
    /// Timestamp of this state
    timestamp: i64,
    
    /// Hash for quick comparison
    hash: u64,
    
    /// Sequence number for ordering
    sequence: u64,
};

pub const StateSnapshot = struct {
    /// The actual state data
    state: AppState,
    
    /// Allocator used for this snapshot
    allocator: std.mem.Allocator,
    
    /// JSON representation (lazy)
    json: ?[]const u8 = null,
    
    /// Reference count for memory management
    ref_count: std.atomic.Value(u32),
    
    /// Increment reference count
    pub fn retain(self: *StateSnapshot) void {
        _ = self.ref_count.fetchAdd(1, .monotonic);
    }
    
    /// Decrement reference count
    pub fn release(self: *StateSnapshot) void {
        const prev = self.ref_count.fetchSub(1, .release);
        if (prev == 1) {
            self.deinit();
        }
    }
    
    /// Get JSON representation
    pub fn toJson(self: *StateSnapshot) ![]const u8 {
        if (self.json == null) {
            self.json = try std.json.stringifyAlloc(
                self.allocator,
                self.state,
                .{ .whitespace = .indent_2 },
            );
        }
        return self.json.?;
    }
    
    /// Cleanup
    fn deinit(self: *StateSnapshot) void {
        // Free all allocated memory
        freeState(self.allocator, &self.state);
        if (self.json) |json| {
            self.allocator.free(json);
        }
        self.allocator.destroy(self);
    }
};

pub const StateDiff = struct {
    /// What changed
    changes: []StateChange,
    
    /// From sequence number
    from_sequence: u64,
    
    /// To sequence number
    to_sequence: u64,
};

pub const StateChange = union(enum) {
    session_added: SessionState,
    session_updated: SessionState,
    session_removed: []const u8, // ID
    
    provider_updated: ProviderState,
    
    tool_updated: ToolState,
    
    config_changed: ConfigState,
    
    ui_changed: UiState,
    
    active_session_changed: ?[]const u8,
};

/// Free allocated state memory
fn freeState(allocator: std.mem.Allocator, state: *AppState) void {
    // Free sessions
    for (state.sessions) |*session| {
        allocator.free(session.id);
        if (session.title) |title| allocator.free(title);
        if (session.parent_id) |pid| allocator.free(pid);
        if (session.last_message_id) |mid| allocator.free(mid);
        if (session.share_url) |url| allocator.free(url);
    }
    allocator.free(state.sessions);
    
    // Free providers
    for (state.providers) |*provider| {
        allocator.free(provider.id);
        allocator.free(provider.name);
        if (provider.selected_model) |model| allocator.free(model);
        if (provider.error) |err| allocator.free(err);
    }
    allocator.free(state.providers);
    
    // Free tools
    for (state.tools) |*tool| {
        allocator.free(tool.name);
    }
    allocator.free(state.tools);
    
    // Free UI state
    if (state.ui.search_query) |query| {
        allocator.free(query);
    }
    
    // Free active session ID
    if (state.active_session_id) |id| {
        allocator.free(id);
    }
}
```

### 2. State Manager (`src/state/manager.zig`)

Core state management:

```zig
pub const StateManager = struct {
    allocator: std.mem.Allocator,
    api: *opencode.OpenCodeApi,
    current_state: ?*StateSnapshot,
    state_history: std.ArrayList(*StateSnapshot),
    callbacks: std.ArrayList(StateCallback),
    sync_thread: ?std.Thread,
    sync_interval_ms: u32 = 1000, // 1 second
    running: std.atomic.Value(bool),
    mutex: std.Thread.Mutex,
    sequence_counter: std.atomic.Value(u64),
    
    pub const StateCallback = struct {
        fn_ptr: *const fn (?*anyopaque) callconv(.C) void,
        user_data: ?*anyopaque,
    };
    
    /// Initialize state manager
    pub fn init(allocator: std.mem.Allocator, api: *opencode.OpenCodeApi) !StateManager {
        return StateManager{
            .allocator = allocator,
            .api = api,
            .current_state = null,
            .state_history = std.ArrayList(*StateSnapshot).init(allocator),
            .callbacks = std.ArrayList(StateCallback).init(allocator),
            .sync_thread = null,
            .running = std.atomic.Value(bool).init(false),
            .mutex = .{},
            .sequence_counter = std.atomic.Value(u64).init(0),
        };
    }
    
    /// Start synchronization
    pub fn start(self: *StateManager) !void {
        // Initial state fetch
        try self.fetchState();
        
        // Start sync thread
        self.running.store(true, .release);
        self.sync_thread = try std.Thread.spawn(.{}, syncLoop, .{self});
    }
    
    /// Stop synchronization
    pub fn stop(self: *StateManager) void {
        self.running.store(false, .release);
        if (self.sync_thread) |thread| {
            thread.join();
            self.sync_thread = null;
        }
    }
    
    /// Get current state snapshot
    pub fn getSnapshot(self: *StateManager) ?*StateSnapshot {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.current_state) |state| {
            state.retain();
            return state;
        }
        
        return null;
    }
    
    /// Get state changes since snapshot
    pub fn getChanges(self: *StateManager, since: ?*StateSnapshot) !?StateDiff {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const current = self.current_state orelse return null;
        
        if (since == null) {
            // Return all state as changes
            var changes = std.ArrayList(StateChange).init(self.allocator);
            
            // Add all sessions
            for (current.state.sessions) |session| {
                try changes.append(.{ .session_added = session });
            }
            
            // Add all providers
            for (current.state.providers) |provider| {
                try changes.append(.{ .provider_updated = provider });
            }
            
            // Add all tools
            for (current.state.tools) |tool| {
                try changes.append(.{ .tool_updated = tool });
            }
            
            // Add config
            try changes.append(.{ .config_changed = current.state.config });
            
            // Add UI state
            try changes.append(.{ .ui_changed = current.state.ui });
            
            return StateDiff{
                .changes = try changes.toOwnedSlice(),
                .from_sequence = 0,
                .to_sequence = current.state.metadata.sequence,
            };
        }
        
        // Calculate actual diff
        return try self.calculateDiff(since, current);
    }
    
    /// Set state change callback
    pub fn setCallback(self: *StateManager, callback: StateCallback) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Clear existing callbacks
        self.callbacks.clearRetainingCapacity();
        
        // Add new callback
        try self.callbacks.append(callback);
    }
    
    /// Clear callbacks
    pub fn clearCallback(self: *StateManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.callbacks.clearRetainingCapacity();
    }
    
    /// Sync loop thread function
    fn syncLoop(self: *StateManager) void {
        while (self.running.load(.acquire)) {
            self.fetchState() catch |err| {
                std.log.err("State sync failed: {}", .{err});
            };
            
            // Sleep with interruption check
            const sleep_ms = self.sync_interval_ms;
            var elapsed: u32 = 0;
            while (elapsed < sleep_ms and self.running.load(.acquire)) {
                std.time.sleep(10 * std.time.ns_per_ms);
                elapsed += 10;
            }
        }
    }
    
    /// Fetch state from OpenCode
    fn fetchState(self: *StateManager) !void {
        // Gather state from various sources
        const sessions = try self.fetchSessions();
        const providers = try self.fetchProviders();
        const tools = try self.fetchTools();
        const config = try self.fetchConfig();
        
        // Create new state snapshot
        const new_state = try self.allocator.create(StateSnapshot);
        errdefer self.allocator.destroy(new_state);
        
        new_state.* = .{
            .state = .{
                .sessions = sessions,
                .active_session_id = self.findActiveSession(sessions),
                .providers = providers,
                .tools = tools,
                .config = config,
                .ui = self.getCurrentUiState(),
                .metadata = .{
                    .version = 1,
                    .timestamp = std.time.milliTimestamp(),
                    .hash = try self.calculateStateHash(sessions, providers, tools),
                    .sequence = self.sequence_counter.fetchAdd(1, .monotonic),
                },
            },
            .allocator = self.allocator,
            .ref_count = std.atomic.Value(u32).init(1),
        };
        
        // Check if state actually changed
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const old_state = self.current_state;
        if (old_state) |old| {
            if (new_state.state.metadata.hash == old.state.metadata.hash) {
                // No changes, discard new state
                new_state.release();
                return;
            }
        }
        
        // Update current state
        self.current_state = new_state;
        
        // Add to history (keep last 10)
        try self.state_history.append(new_state);
        new_state.retain();
        
        if (self.state_history.items.len > 10) {
            const removed = self.state_history.orderedRemove(0);
            removed.release();
        }
        
        // Notify callbacks
        for (self.callbacks.items) |callback| {
            callback.fn_ptr(callback.user_data);
        }
        
        // Release old state
        if (old_state) |old| {
            old.release();
        }
    }
    
    /// Fetch sessions
    fn fetchSessions(self: *StateManager) ![]SessionState {
        const sessions = try self.api.session.list();
        
        var result = try self.allocator.alloc(SessionState, sessions.len);
        for (sessions, 0..) |session, i| {
            // Get message count for session
            const messages = try self.api.message.list(session.id);
            
            result[i] = .{
                .id = try self.allocator.dupe(u8, session.id),
                .title = if (session.title) |t| try self.allocator.dupe(u8, t) else null,
                .parent_id = if (session.parent_id) |p| try self.allocator.dupe(u8, p) else null,
                .created = session.time.created,
                .updated = session.time.updated,
                .message_count = @intCast(u32, messages.len),
                .last_message_id = if (messages.len > 0) try self.allocator.dupe(u8, messages[messages.len - 1].id) else null,
                .is_streaming = false, // TODO: Check active streams
            };
        }
        
        return result;
    }
    
    /// Fetch providers
    fn fetchProviders(self: *StateManager) ![]ProviderState {
        const providers = try self.api.provider.list();
        
        var result = std.ArrayList(ProviderState).init(self.allocator);
        
        var it = providers.iterator();
        while (it.next()) |entry| {
            const provider_obj = entry.value_ptr.*.object;
            
            try result.append(.{
                .id = try self.allocator.dupe(u8, entry.key_ptr.*),
                .name = try self.allocator.dupe(u8, provider_obj.get("name").?.string),
                .enabled = provider_obj.get("enabled").?.bool,
                .authenticated = provider_obj.get("authenticated").?.bool,
                .model_count = if (provider_obj.get("models")) |models| @intCast(u32, models.array.items.len) else 0,
                .selected_model = null, // TODO: Track selected model
                .error = null,
            });
        }
        
        return try result.toOwnedSlice();
    }
    
    /// Fetch tools
    fn fetchTools(self: *StateManager) ![]ToolState {
        const tools = try self.api.tool.list();
        
        var result = std.ArrayList(ToolState).init(self.allocator);
        
        var it = tools.iterator();
        while (it.next()) |entry| {
            try result.append(.{
                .name = try self.allocator.dupe(u8, entry.key_ptr.*),
                .available = true,
                .executing = false, // TODO: Track active executions
            });
        }
        
        return try result.toOwnedSlice();
    }
    
    /// Fetch config
    fn fetchConfig(self: *StateManager) !ConfigState {
        // Get from config manager
        return ConfigState{
            .theme = "system", // TODO: Get from config
            .auto_save = true,
            .telemetry = false,
            .server_status = .running,
        };
    }
    
    /// Get current UI state
    fn getCurrentUiState(self: *StateManager) UiState {
        // TODO: Track actual UI state
        return .{};
    }
    
    /// Find active session
    fn findActiveSession(self: *StateManager, sessions: []SessionState) ?[]const u8 {
        // TODO: Track which session is active
        if (sessions.len > 0) {
            return sessions[0].id;
        }
        return null;
    }
    
    /// Calculate state hash
    fn calculateStateHash(
        self: *StateManager,
        sessions: []SessionState,
        providers: []ProviderState,
        tools: []ToolState,
    ) !u64 {
        var hasher = std.hash.Wyhash.init(0);
        
        // Hash sessions
        for (sessions) |session| {
            hasher.update(session.id);
            hasher.update(std.mem.asBytes(&session.updated));
            hasher.update(std.mem.asBytes(&session.message_count));
        }
        
        // Hash providers
        for (providers) |provider| {
            hasher.update(provider.id);
            hasher.update(std.mem.asBytes(&provider.enabled));
            hasher.update(std.mem.asBytes(&provider.authenticated));
        }
        
        // Hash tools
        for (tools) |tool| {
            hasher.update(tool.name);
            hasher.update(std.mem.asBytes(&tool.available));
        }
        
        return hasher.final();
    }
    
    /// Calculate diff between states
    fn calculateDiff(self: *StateManager, old: *StateSnapshot, new: *StateSnapshot) !StateDiff {
        var changes = std.ArrayList(StateChange).init(self.allocator);
        
        // Compare sessions
        try self.diffSessions(&changes, old.state.sessions, new.state.sessions);
        
        // Compare providers
        try self.diffProviders(&changes, old.state.providers, new.state.providers);
        
        // Compare tools
        try self.diffTools(&changes, old.state.tools, new.state.tools);
        
        // Compare config
        if (!std.meta.eql(old.state.config, new.state.config)) {
            try changes.append(.{ .config_changed = new.state.config });
        }
        
        // Compare UI state
        if (!std.meta.eql(old.state.ui, new.state.ui)) {
            try changes.append(.{ .ui_changed = new.state.ui });
        }
        
        // Compare active session
        const old_active = old.state.active_session_id;
        const new_active = new.state.active_session_id;
        if (!std.mem.eql(u8, old_active orelse "", new_active orelse "")) {
            try changes.append(.{ .active_session_changed = new_active });
        }
        
        return StateDiff{
            .changes = try changes.toOwnedSlice(),
            .from_sequence = old.state.metadata.sequence,
            .to_sequence = new.state.metadata.sequence,
        };
    }
    
    fn diffSessions(
        self: *StateManager,
        changes: *std.ArrayList(StateChange),
        old: []SessionState,
        new: []SessionState,
    ) !void {
        // Create maps for efficient lookup
        var old_map = std.StringHashMap(SessionState).init(self.allocator);
        defer old_map.deinit();
        for (old) |session| {
            try old_map.put(session.id, session);
        }
        
        var new_map = std.StringHashMap(SessionState).init(self.allocator);
        defer new_map.deinit();
        for (new) |session| {
            try new_map.put(session.id, session);
        }
        
        // Find added and updated
        for (new) |session| {
            if (old_map.get(session.id)) |old_session| {
                if (!sessionEquals(old_session, session)) {
                    try changes.append(.{ .session_updated = session });
                }
            } else {
                try changes.append(.{ .session_added = session });
            }
        }
        
        // Find removed
        for (old) |session| {
            if (!new_map.contains(session.id)) {
                try changes.append(.{ .session_removed = session.id });
            }
        }
    }
    
    fn diffProviders(
        self: *StateManager,
        changes: *std.ArrayList(StateChange),
        old: []ProviderState,
        new: []ProviderState,
    ) !void {
        // Similar diff logic for providers
        // ...
    }
    
    fn diffTools(
        self: *StateManager,
        changes: *std.ArrayList(StateChange),
        old: []ToolState,
        new: []ToolState,
    ) !void {
        // Similar diff logic for tools
        // ...
    }
};

fn sessionEquals(a: SessionState, b: SessionState) bool {
    return std.mem.eql(u8, a.id, b.id) and
        a.updated == b.updated and
        a.message_count == b.message_count and
        a.is_streaming == b.is_streaming;
}
```

### 3. FFI Implementation (`src/state/ffi.zig`)

Implement C FFI functions:

```zig
const std = @import("std");
const c = @cImport({});
const StateManager = @import("manager.zig").StateManager;
const types = @import("types.zig");
const error_handling = @import("../error/handling.zig");

/// Global state manager
var state_manager: ?*StateManager = null;

/// Initialize state manager
pub fn init(allocator: std.mem.Allocator, api: *opencode.OpenCodeApi) !void {
    state_manager = try allocator.create(StateManager);
    state_manager.?.* = try StateManager.init(allocator, api);
    try state_manager.?.start();
}

/// Get complete application state snapshot
export fn plue_state_get_snapshot() ?*anyopaque {
    const manager = state_manager orelse {
        error_handling.setLastError(error.NotInitialized, "State manager not initialized");
        return null;
    };
    
    const snapshot = manager.getSnapshot() orelse {
        error_handling.setLastError(error.NoState, "No state available");
        return null;
    };
    
    return @ptrCast(*anyopaque, snapshot);
}

/// Get state as JSON from a snapshot
export fn plue_state_snapshot_to_json(snapshot: ?*anyopaque) [*:0]const u8 {
    if (snapshot == null) {
        error_handling.setLastError(error.InvalidParam, "Snapshot is null");
        return "";
    }
    
    const state_snapshot = @ptrCast(*types.StateSnapshot, @alignCast(@alignOf(types.StateSnapshot), snapshot));
    
    const json = state_snapshot.toJson() catch |err| {
        error_handling.setLastError(err, "Failed to convert state to JSON");
        return "";
    };
    
    // Return the JSON (owned by snapshot, caller must not free)
    return @ptrCast([*:0]const u8, json.ptr);
}

/// Free a state snapshot
export fn plue_state_free_snapshot(snapshot: ?*anyopaque) void {
    if (snapshot == null) return;
    
    const state_snapshot = @ptrCast(*types.StateSnapshot, @alignCast(@alignOf(types.StateSnapshot), snapshot));
    state_snapshot.release();
}

/// Get state changes since last snapshot
export fn plue_state_get_changes(last_snapshot: ?*anyopaque) [*c]u8 {
    const manager = state_manager orelse {
        error_handling.setLastError(error.NotInitialized, "State manager not initialized");
        return null;
    };
    
    const last = if (last_snapshot) |snap|
        @ptrCast(*types.StateSnapshot, @alignCast(@alignOf(types.StateSnapshot), snap))
    else
        null;
    
    const diff = manager.getChanges(last) catch |err| {
        error_handling.setLastError(err, "Failed to get state changes");
        return null;
    };
    
    if (diff == null) {
        return null;
    }
    
    // Convert diff to JSON
    const json_string = std.json.stringifyAlloc(
        manager.allocator,
        diff.?,
        .{},
    ) catch |err| {
        error_handling.setLastError(err, "Failed to serialize changes");
        return null;
    };
    
    return json_string.ptr;
}

/// Register for state change notifications
export fn plue_state_set_callback(
    callback: ?*const fn (?*anyopaque) callconv(.C) void,
    user_data: ?*anyopaque,
) void {
    if (callback == null) {
        error_handling.setLastError(error.InvalidParam, "Callback is null");
        return;
    }
    
    const manager = state_manager orelse {
        error_handling.setLastError(error.NotInitialized, "State manager not initialized");
        return;
    };
    
    manager.setCallback(.{
        .fn_ptr = callback,
        .user_data = user_data,
    }) catch |err| {
        error_handling.setLastError(err, "Failed to set callback");
    };
}

/// Clear state change callback
export fn plue_state_clear_callback() void {
    const manager = state_manager orelse {
        error_handling.setLastError(error.NotInitialized, "State manager not initialized");
        return;
    };
    
    manager.clearCallback();
}
```

### 4. State Cache (`src/state/cache.zig`)

Efficient state caching:

```zig
pub const StateCache = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap(CachedValue),
    max_size: usize = 100 * 1024 * 1024, // 100MB
    current_size: usize = 0,
    
    const CachedValue = struct {
        data: []const u8,
        timestamp: i64,
        hits: u32,
        size: usize,
    };
    
    /// Get cached value
    pub fn get(self: *StateCache, key: []const u8) ?[]const u8 {
        if (self.cache.getPtr(key)) |entry| {
            entry.hits += 1;
            return entry.data;
        }
        return null;
    }
    
    /// Put value in cache
    pub fn put(self: *StateCache, key: []const u8, value: []const u8) !void {
        const size = key.len + value.len + @sizeOf(CachedValue);
        
        // Evict if needed
        while (self.current_size + size > self.max_size) {
            try self.evictLRU();
        }
        
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        
        try self.cache.put(key_copy, .{
            .data = value_copy,
            .timestamp = std.time.milliTimestamp(),
            .hits = 0,
            .size = size,
        });
        
        self.current_size += size;
    }
    
    /// Evict least recently used
    fn evictLRU(self: *StateCache) !void {
        var oldest_key: ?[]const u8 = null;
        var oldest_time: i64 = std.math.maxInt(i64);
        
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.timestamp < oldest_time) {
                oldest_time = entry.value_ptr.timestamp;
                oldest_key = entry.key_ptr.*;
            }
        }
        
        if (oldest_key) |key| {
            if (self.cache.fetchRemove(key)) |entry| {
                self.allocator.free(entry.key);
                self.allocator.free(entry.value.data);
                self.current_size -= entry.value.size;
            }
        }
    }
};
```

### 5. State Persistence (`src/state/persistence.zig`)

Save and restore state:

```zig
pub const StatePersistence = struct {
    allocator: std.mem.Allocator,
    state_dir: []const u8,
    
    /// Save state to disk
    pub fn saveState(self: *StatePersistence, snapshot: *types.StateSnapshot) !void {
        const json = try snapshot.toJson();
        
        const filename = try std.fmt.allocPrint(
            self.allocator,
            "state_{d}.json",
            .{snapshot.state.metadata.timestamp},
        );
        defer self.allocator.free(filename);
        
        const path = try std.fs.path.join(self.allocator, &.{ self.state_dir, filename });
        defer self.allocator.free(path);
        
        try std.fs.cwd().writeFile(path, json);
    }
    
    /// Load most recent state
    pub fn loadState(self: *StatePersistence) !?types.AppState {
        var dir = try std.fs.openDirAbsolute(self.state_dir, .{ .iterate = true });
        defer dir.close();
        
        var newest_file: ?[]const u8 = null;
        var newest_time: i64 = 0;
        
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.startsWith(u8, entry.name, "state_")) continue;
            if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
            
            // Parse timestamp from filename
            const timestamp_str = entry.name[6..entry.name.len - 5];
            const timestamp = std.fmt.parseInt(i64, timestamp_str, 10) catch continue;
            
            if (timestamp > newest_time) {
                newest_time = timestamp;
                if (newest_file) |old| self.allocator.free(old);
                newest_file = try self.allocator.dupe(u8, entry.name);
            }
        }
        
        if (newest_file) |filename| {
            defer self.allocator.free(filename);
            
            const content = try dir.readFileAlloc(self.allocator, filename, 10 * 1024 * 1024);
            defer self.allocator.free(content);
            
            const parsed = try std.json.parseFromSlice(
                types.AppState,
                self.allocator,
                content,
                .{ .allocate = .alloc_always },
            );
            
            return parsed.value;
        }
        
        return null;
    }
    
    /// Clean old state files
    pub fn cleanOldStates(self: *StatePersistence, keep_count: usize) !void {
        // Implementation to remove old state files
        // ...
    }
};
```

### 6. State Events (`src/state/events.zig`)

Event system for state changes:

```zig
const event_bus = @import("../event/bus.zig");
const types = @import("types.zig");

pub const StateEvent = union(enum) {
    snapshot_created: struct {
        sequence: u64,
        hash: u64,
    },
    state_changed: struct {
        changes: []types.StateChange,
        from_sequence: u64,
        to_sequence: u64,
    },
    sync_error: struct {
        error: []const u8,
        retry_after_ms: u32,
    },
    sync_resumed: void,
};

pub fn emitStateEvent(event: StateEvent) !void {
    const bus = event_bus.getInstance();
    try bus.emit("state", event);
}
```

## Implementation Steps

### Step 1: Define State Types
1. Create `src/state/types.zig`
2. Define all state structures
3. Add snapshot management
4. Write type tests

### Step 2: Implement State Manager
1. Create `src/state/manager.zig`
2. Add synchronization logic
3. Implement diff calculation
4. Add callback support

### Step 3: Create FFI Functions
1. Create `src/state/ffi.zig`
2. Implement all exports
3. Handle thread safety
4. Test with C client

### Step 4: Add State Cache
1. Create `src/state/cache.zig`
2. Implement LRU eviction
3. Add size limits
4. Test cache performance

### Step 5: Implement Persistence
1. Create `src/state/persistence.zig`
2. Add save/load logic
3. Handle cleanup
4. Test persistence

### Step 6: Add Event System
1. Create `src/state/events.zig`
2. Emit state events
3. Support filtering
4. Test event delivery

## Testing Requirements

1. **Unit Tests** (>95% coverage):
   - State diffing
   - Snapshot management
   - Cache behavior
   - Persistence

2. **Integration Tests**:
   - Full sync cycles
   - Callback delivery
   - Error recovery
   - Performance

3. **Stress Tests**:
   - Rapid state changes
   - Large state sizes
   - Memory usage
   - Thread safety

## Example Usage (from C/Swift)

```c
// Get initial state
plue_state_snapshot_t snapshot = plue_state_get_snapshot();
if (snapshot) {
    const char* json = plue_state_snapshot_to_json(snapshot);
    printf("Initial state: %s\n", json);
}

// Set up change callback
void on_state_change(void* user_data) {
    // Get new snapshot
    plue_state_snapshot_t new_snap = plue_state_get_snapshot();
    
    // Get changes since last
    char* changes = plue_state_get_changes(snapshot);
    if (changes) {
        printf("State changes: %s\n", changes);
        plue_free_json(changes);
    }
    
    // Free old snapshot
    plue_state_free_snapshot(snapshot);
    snapshot = new_snap;
}

plue_state_set_callback(on_state_change, NULL);

// ... later cleanup
plue_state_clear_callback();
plue_state_free_snapshot(snapshot);
```

## State Update Flow

```
1. OpenCode State Change
   ↓
2. Sync Thread Detects (polling)
   ↓
3. Fetch Updated Data
   ↓
4. Calculate Diff
   ↓
5. Create New Snapshot
   ↓
6. Notify Callbacks
   ↓
7. Swift UI Updates
```

## Corner Cases and Implementation Details

Based on OpenCode's implementation, handle these critical scenarios:

### State Management Architecture
1. **App.state() Pattern**: Services register state with init and shutdown functions
2. **Per-Project State**: State stored in project-specific directories
3. **No Global State**: Each service manages its own state independently
4. **Event Bus Updates**: Real-time updates via SSE event stream
5. **Lazy Initialization**: Services initialized on first access

### Event Bus Integration
1. **Event Types**: session.*, message.*, provider.*, tool.*, etc.
2. **Event Format**: JSON objects with type and data fields
3. **Connection Management**: Auto-reconnect on SSE disconnect
4. **Event Ordering**: Events may arrive out of order
5. **Missed Events**: Must poll to catch up after reconnection

### Session State Specifics
1. **Session List**: Available via `/session` endpoint
2. **Message Count**: Must query `/session/{id}/messages` separately
3. **Active Session**: Not tracked by OpenCode - client responsibility
4. **Share State**: Sessions have optional share URLs
5. **Parent Sessions**: Hierarchical session structure supported

### Provider State Details
1. **Dynamic Loading**: Providers loaded based on env vars
2. **Model Count**: Must parse provider.models object
3. **Authentication**: Check via attempting model list
4. **Selected Model**: Track per-session, not globally
5. **Cost Updates**: OAuth providers set costs to 0

### Tool State Tracking
1. **Tool List**: Available via provider.tools() mapping
2. **Execution State**: Not tracked by OpenCode
3. **Permission State**: Tracked per-session by Permission service
4. **Tool Results**: Available in message parts
5. **Abort Handling**: Must track abort signals locally

### Memory Management Patterns
1. **Reference Counting**: Snapshots use atomic ref counts
2. **Lazy JSON**: Generate JSON representation on demand
3. **Deep Copy**: State snapshots must deep copy all data
4. **Cleanup Order**: Free nested allocations first
5. **Arena Allocators**: Consider for temporary state ops

### Diff Calculation Optimizations
1. **Hash Comparison**: Quick equality check via hashes
2. **Sequence Numbers**: Track order of state changes
3. **Partial Diffs**: Only include changed fields
4. **Batch Changes**: Group related changes together
5. **Change Coalescing**: Merge rapid successive changes

### Thread Safety Considerations
1. **Immutable Snapshots**: Never modify existing snapshots
2. **Mutex Protection**: Guard all shared state access
3. **Atomic Operations**: Use atomics for counters/flags
4. **Copy-on-Write**: Consider for large state objects
5. **Lock Ordering**: Prevent deadlocks with consistent order

### Performance Edge Cases
1. **Large Sessions**: 1000+ messages in a session
2. **Many Providers**: 10+ providers with many models
3. **Rapid Updates**: Multiple messages per second
4. **Memory Pressure**: State cache eviction needed
5. **Startup Time**: Initial state fetch can be slow

### Error Recovery Patterns
1. **Partial Failures**: Some endpoints may fail
2. **Stale Data**: Cached data may be outdated
3. **Network Issues**: Handle intermittent connectivity
4. **Invalid State**: Corrupted state files on disk
5. **Version Mismatch**: State schema changes

### UX Improvements
1. **Progressive Loading**: Show partial state quickly
2. **Optimistic Updates**: Update UI before confirmation
3. **Change Indicators**: Show what's updating
4. **Sync Status**: Display connection health
5. **Error Recovery**: Graceful degradation

### Potential Bugs to Watch Out For
1. **Memory Leaks**: Snapshots not released properly
2. **Infinite Loops**: Sync triggering more syncs
3. **Race Conditions**: Multiple sync threads
4. **Event Storms**: Too many events overwhelming UI
5. **Stale Callbacks**: Callbacks referencing freed memory
6. **Hash Collisions**: Different states same hash
7. **Time Skew**: Server/client time differences
8. **Zombie Threads**: Sync thread not stopping
9. **Cache Corruption**: Invalid data in cache
10. **Deadlocks**: Complex lock interactions

## Success Criteria

The implementation is complete when:
- [ ] State syncs via event bus with <100ms latency
- [ ] Polling fallback catches missed events
- [ ] Diffs only include actual changes
- [ ] Snapshots are truly immutable and thread-safe
- [ ] Reference counting prevents memory leaks
- [ ] Callbacks fire exactly once per change
- [ ] Memory usage scales with active data only
- [ ] State persists correctly per-project
- [ ] All tests pass with >95% coverage
- [ ] UI updates feel instant (<16ms)
- [ ] Handles 1000+ sessions gracefully
- [ ] Recovers from all error scenarios

## Git Workflow

Continue in the same worktree:
```bash
cd ../plue-server-management
```

Commit with conventional commits:
- `feat: define state types and snapshots`
- `feat: implement state synchronization`
- `feat: add state FFI functions`
- `feat: implement state caching`
- `feat: add state persistence`
- `test: add state sync tests`

The branch remains: `feat_add_opencode_server_management`