# Implement Session Management Bridge

## Context

You are implementing the session management bridge that connects Plue's C FFI session API (as defined in PLUE_CORE_API.md) to OpenCode's HTTP session endpoints. This bridge is critical for maintaining session state consistency between the two systems.

### Project State

From previous tasks, you have:
- OpenCode server manager (`src/server/manager.zig`)
- HTTP client infrastructure (`src/http/client.zig`)
- OpenCode API client with session endpoints (`src/opencode/api.zig`)

Now you need to implement the session management functions exposed through Plue's C FFI.

### Session API Requirements (from PLUE_CORE_API.md)

```c
// Opaque session handle
typedef struct plue_session* plue_session_t;

// Create a new session
export fn plue_session_create(parent_id: [*:0]const u8) ?*anyopaque;

// Get session info as JSON
export fn plue_session_get_info(session: ?*anyopaque) [*c]u8;

// List all sessions as JSON array
export fn plue_session_list() [*c]u8;

// Update session title
export fn plue_session_update_title(session: ?*anyopaque, title: [*:0]const u8) c_int;

// Initialize session with provider and model
export fn plue_session_initialize(session: ?*anyopaque, provider_id: [*:0]const u8, model_id: [*:0]const u8) c_int;

// Delete a session and all associated data
export fn plue_session_delete(session: ?*anyopaque) c_int;

// Abort ongoing operations in a session
export fn plue_session_abort(session: ?*anyopaque) c_int;

// Create a shareable link for a session
export fn plue_session_create_share(session: ?*anyopaque) [*c]u8;

// Destroy session handle (does not delete session data)
export fn plue_session_destroy(session: ?*anyopaque) void;
```

### OpenCode Session Model

OpenCode sessions have the following structure:
```typescript
interface SessionInfo {
  id: string;              // Format: "session_TIMESTAMP"
  title?: string;          // User-provided title
  time: {
    created: number;       // Unix timestamp
    updated: number;       // Unix timestamp
  };
  parentId?: string;       // For branched sessions
  share?: {
    url: string;          // Shareable URL
    secret: string;       // Access secret
  };
}
```

## Requirements

### 1. Session Handle Management (`src/session/handle.zig`)

Create an opaque handle system for sessions:

```zig
const std = @import("std");
const opencode = @import("../opencode/api.zig");

/// Opaque session handle exposed to C
pub const SessionHandle = struct {
    /// Session ID in OpenCode
    id: []const u8,
    
    /// Cached session info
    info: ?opencode.SessionInfo,
    
    /// Last update timestamp for cache invalidation
    last_update: i64,
    
    /// Abort signal for ongoing operations
    abort_signal: std.atomic.Value(bool),
    
    /// Reference to the API client
    api: *opencode.OpenCodeApi,
    
    /// Allocator for this handle
    allocator: std.mem.Allocator,
    
    /// Initialize a new handle
    pub fn init(allocator: std.mem.Allocator, api: *opencode.OpenCodeApi, id: []const u8) !*SessionHandle {
        const handle = try allocator.create(SessionHandle);
        handle.* = .{
            .id = try allocator.dupe(u8, id),
            .info = null,
            .last_update = 0,
            .abort_signal = std.atomic.Value(bool).init(false),
            .api = api,
            .allocator = allocator,
        };
        return handle;
    }
    
    /// Refresh cached info if stale
    pub fn refreshInfo(self: *SessionHandle) !void {
        const now = std.time.milliTimestamp();
        if (self.info == null or now - self.last_update > 5000) { // 5 second cache
            self.info = try self.api.session.get(self.id);
            self.last_update = now;
        }
    }
    
    /// Signal abort for ongoing operations
    pub fn abort(self: *SessionHandle) void {
        self.abort_signal.store(true, .release);
    }
    
    /// Check if aborted
    pub fn isAborted(self: *const SessionHandle) bool {
        return self.abort_signal.load(.acquire);
    }
    
    /// Cleanup
    pub fn deinit(self: *SessionHandle) void {
        self.allocator.free(self.id);
        if (self.info) |info| {
            // Free any allocated info fields
        }
        self.allocator.destroy(self);
    }
};
```

### 2. Session Manager (`src/session/manager.zig`)

Manage all session handles and coordinate with OpenCode:

```zig
pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    api: *opencode.OpenCodeApi,
    handles: std.AutoHashMap([]const u8, *SessionHandle),
    mutex: std.Thread.Mutex,
    
    /// Global session manager instance
    var instance: ?SessionManager = null;
    
    /// Initialize the global session manager
    pub fn init(allocator: std.mem.Allocator, api: *opencode.OpenCodeApi) !void {
        instance = SessionManager{
            .allocator = allocator,
            .api = api,
            .handles = std.AutoHashMap([]const u8, *SessionHandle).init(allocator),
            .mutex = .{},
        };
    }
    
    /// Get the global instance
    pub fn getInstance() !*SessionManager {
        return &(instance orelse return error.NotInitialized);
    }
    
    /// Create a new session
    pub fn createSession(self: *SessionManager, parent_id: ?[]const u8) !*SessionHandle {
        // Call OpenCode API
        const session_info = try self.api.session.create(parent_id);
        
        // Create handle
        const handle = try SessionHandle.init(self.allocator, self.api, session_info.id);
        handle.info = session_info;
        handle.last_update = std.time.milliTimestamp();
        
        // Store handle
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.handles.put(try self.allocator.dupe(u8, session_info.id), handle);
        
        return handle;
    }
    
    /// Get existing handle or create from ID
    pub fn getHandle(self: *SessionManager, id: []const u8) !*SessionHandle {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.handles.get(id)) |handle| {
            return handle;
        }
        
        // Create handle for existing session
        const handle = try SessionHandle.init(self.allocator, self.api, id);
        try self.handles.put(try self.allocator.dupe(u8, id), handle);
        return handle;
    }
    
    /// Remove handle (does not delete session)
    pub fn removeHandle(self: *SessionManager, id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.handles.fetchRemove(id)) |entry| {
            self.allocator.free(entry.key);
            entry.value.deinit();
        }
    }
    
    /// Cleanup
    pub fn deinit(self: *SessionManager) void {
        var it = self.handles.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
        }
        self.handles.deinit();
    }
};
```

### 3. FFI Implementation (`src/session/ffi.zig`)

Implement the C FFI functions:

```zig
const std = @import("std");
const c = @cImport({});
const SessionHandle = @import("handle.zig").SessionHandle;
const SessionManager = @import("manager.zig").SessionManager;
const error_handling = @import("../error/handling.zig");

/// Create a new session
export fn plue_session_create(parent_id: [*:0]const u8) ?*anyopaque {
    const manager = SessionManager.getInstance() catch |err| {
        error_handling.setLastError(err, "Failed to get session manager");
        return null;
    };
    
    const parent_id_slice = if (parent_id == null) null else std.mem.span(parent_id);
    
    const handle = manager.createSession(parent_id_slice) catch |err| {
        error_handling.setLastError(err, "Failed to create session");
        return null;
    };
    
    return @ptrCast(*anyopaque, handle);
}

/// Get session info as JSON
export fn plue_session_get_info(session: ?*anyopaque) [*c]u8 {
    if (session == null) {
        error_handling.setLastError(error.InvalidParam, "Session handle is null");
        return null;
    }
    
    const handle = @ptrCast(*SessionHandle, @alignCast(@alignOf(SessionHandle), session));
    
    // Refresh info
    handle.refreshInfo() catch |err| {
        error_handling.setLastError(err, "Failed to refresh session info");
        return null;
    };
    
    // Convert to JSON
    const allocator = handle.allocator;
    const json_string = std.json.stringifyAlloc(allocator, handle.info.?, .{}) catch |err| {
        error_handling.setLastError(err, "Failed to serialize session info");
        return null;
    };
    
    // Convert to C string (caller must free)
    return json_string.ptr;
}

/// List all sessions as JSON array
export fn plue_session_list() [*c]u8 {
    const manager = SessionManager.getInstance() catch |err| {
        error_handling.setLastError(err, "Failed to get session manager");
        return null;
    };
    
    // Get sessions from OpenCode
    const sessions = manager.api.session.list() catch |err| {
        error_handling.setLastError(err, "Failed to list sessions");
        return null;
    };
    
    // Convert to JSON
    const json_string = std.json.stringifyAlloc(manager.allocator, sessions, .{}) catch |err| {
        error_handling.setLastError(err, "Failed to serialize sessions");
        return null;
    };
    
    return json_string.ptr;
}

/// Update session title
export fn plue_session_update_title(session: ?*anyopaque, title: [*:0]const u8) c_int {
    if (session == null or title == null) {
        error_handling.setLastError(error.InvalidParam, "Invalid parameters");
        return -1;
    }
    
    const handle = @ptrCast(*SessionHandle, @alignCast(@alignOf(SessionHandle), session));
    const title_slice = std.mem.span(title);
    
    // Update via OpenCode
    handle.api.session.updateTitle(handle.id, title_slice) catch |err| {
        error_handling.setLastError(err, "Failed to update title");
        return -1;
    };
    
    // Invalidate cache
    handle.info = null;
    
    return 0;
}

/// Delete a session and all associated data
export fn plue_session_delete(session: ?*anyopaque) c_int {
    if (session == null) {
        error_handling.setLastError(error.InvalidParam, "Session handle is null");
        return -1;
    }
    
    const handle = @ptrCast(*SessionHandle, @alignCast(@alignOf(SessionHandle), session));
    const manager = SessionManager.getInstance() catch |err| {
        error_handling.setLastError(err, "Failed to get session manager");
        return -1;
    };
    
    // Delete via OpenCode
    handle.api.session.delete(handle.id) catch |err| {
        error_handling.setLastError(err, "Failed to delete session");
        return -1;
    };
    
    // Remove handle
    manager.removeHandle(handle.id);
    
    return 0;
}

/// Abort ongoing operations in a session
export fn plue_session_abort(session: ?*anyopaque) c_int {
    if (session == null) {
        error_handling.setLastError(error.InvalidParam, "Session handle is null");
        return -1;
    }
    
    const handle = @ptrCast(*SessionHandle, @alignCast(@alignOf(SessionHandle), session));
    
    // Signal local abort
    handle.abort();
    
    // Call OpenCode abort endpoint
    _ = handle.api.session.abort(handle.id) catch |err| {
        error_handling.setLastError(err, "Failed to abort session");
        return -1;
    };
    
    return 0;
}

/// Create a shareable link for a session
export fn plue_session_create_share(session: ?*anyopaque) [*c]u8 {
    if (session == null) {
        error_handling.setLastError(error.InvalidParam, "Session handle is null");
        return null;
    }
    
    const handle = @ptrCast(*SessionHandle, @alignCast(@alignOf(SessionHandle), session));
    
    // TODO: Call OpenCode share endpoint when available
    // For now, return a mock response
    const share_info = .{
        .url = "https://plue.app/share/abc123",
        .secret = "secret123",
    };
    
    const json_string = std.json.stringifyAlloc(handle.allocator, share_info, .{}) catch |err| {
        error_handling.setLastError(err, "Failed to create share link");
        return null;
    };
    
    return json_string.ptr;
}

/// Destroy session handle (does not delete session data)
export fn plue_session_destroy(session: ?*anyopaque) void {
    if (session == null) return;
    
    const handle = @ptrCast(*SessionHandle, @alignCast(@alignOf(SessionHandle), session));
    const manager = SessionManager.getInstance() catch return;
    
    manager.removeHandle(handle.id);
}
```

### 4. Share Management (`src/session/share.zig`)

Handle session sharing functionality:

```zig
pub const ShareInfo = struct {
    url: []const u8,
    secret: []const u8,
    expires_at: ?i64 = null,
};

pub const ShareManager = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    shares: std.StringHashMap(ShareInfo),
    
    /// Generate share URL
    pub fn createShare(self: *ShareManager, session_id: []const u8) !ShareInfo {
        // Generate random secret
        var secret: [32]u8 = undefined;
        std.crypto.random.bytes(&secret);
        const secret_b64 = try std.base64.standard.Encoder.encode(self.allocator, &secret);
        
        // Create share URL
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/share/{s}",
            .{ self.base_url, secret_b64 },
        );
        
        const info = ShareInfo{
            .url = url,
            .secret = secret_b64,
            .expires_at = std.time.milliTimestamp() + (24 * 60 * 60 * 1000), // 24 hours
        };
        
        try self.shares.put(session_id, info);
        return info;
    }
    
    /// Validate share access
    pub fn validateShare(self: *ShareManager, session_id: []const u8, secret: []const u8) !bool {
        if (self.shares.get(session_id)) |info| {
            if (std.mem.eql(u8, info.secret, secret)) {
                if (info.expires_at) |expires| {
                    return std.time.milliTimestamp() < expires;
                }
                return true;
            }
        }
        return false;
    }
};
```

### 5. Session Synchronization (`src/session/sync.zig`)

Keep session state synchronized with OpenCode:

```zig
pub const SessionSync = struct {
    allocator: std.mem.Allocator,
    api: *opencode.OpenCodeApi,
    local_cache: std.StringHashMap(opencode.SessionInfo),
    sync_interval_ms: u32 = 30000, // 30 seconds
    sync_thread: ?std.Thread = null,
    running: std.atomic.Value(bool),
    
    /// Start sync thread
    pub fn start(self: *SessionSync) !void {
        self.running.store(true, .release);
        self.sync_thread = try std.Thread.spawn(.{}, syncLoop, .{self});
    }
    
    /// Sync loop
    fn syncLoop(self: *SessionSync) void {
        while (self.running.load(.acquire)) {
            self.syncSessions() catch |err| {
                std.log.err("Session sync failed: {}", .{err});
            };
            
            // Sleep with interrupt check
            const sleep_ms = self.sync_interval_ms;
            var elapsed: u32 = 0;
            while (elapsed < sleep_ms and self.running.load(.acquire)) {
                std.time.sleep(100 * std.time.ns_per_ms);
                elapsed += 100;
            }
        }
    }
    
    /// Sync sessions with OpenCode
    fn syncSessions(self: *SessionSync) !void {
        const remote_sessions = try self.api.session.list();
        
        // Update local cache
        for (remote_sessions) |session| {
            try self.local_cache.put(session.id, session);
        }
        
        // Remove deleted sessions
        var it = self.local_cache.iterator();
        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();
        
        while (it.next()) |entry| {
            var found = false;
            for (remote_sessions) |session| {
                if (std.mem.eql(u8, entry.key_ptr.*, session.id)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try to_remove.append(entry.key_ptr.*);
            }
        }
        
        for (to_remove.items) |id| {
            _ = self.local_cache.remove(id);
        }
    }
    
    /// Stop sync
    pub fn stop(self: *SessionSync) void {
        self.running.store(false, .release);
        if (self.sync_thread) |thread| {
            thread.join();
            self.sync_thread = null;
        }
    }
};
```

### 6. Session Events (`src/session/events.zig`)

Emit events for session changes:

```zig
const event_bus = @import("../event/bus.zig");

pub const SessionEvent = union(enum) {
    created: struct {
        id: []const u8,
        parent_id: ?[]const u8,
    },
    updated: struct {
        id: []const u8,
        title: ?[]const u8,
    },
    deleted: struct {
        id: []const u8,
    },
    shared: struct {
        id: []const u8,
        url: []const u8,
    },
};

/// Emit session event
pub fn emitEvent(event: SessionEvent) !void {
    const bus = event_bus.getInstance();
    try bus.emit("session", event);
}
```

## Implementation Steps

### Step 1: Create Handle System
1. Create `src/session/handle.zig`
2. Implement opaque handle management
3. Add abort signal support
4. Write handle lifecycle tests

### Step 2: Implement Session Manager
1. Create `src/session/manager.zig`
2. Add global instance management
3. Implement handle tracking
4. Add thread safety

### Step 3: Implement FFI Functions
1. Create `src/session/ffi.zig`
2. Implement all C exports
3. Add error handling
4. Test with C client

### Step 4: Add Share Management
1. Create `src/session/share.zig`
2. Implement URL generation
3. Add secret validation
4. Test share lifecycle

### Step 5: Implement Synchronization
1. Create `src/session/sync.zig`
2. Add background sync thread
3. Handle conflict resolution
4. Test sync reliability

### Step 6: Add Event Support
1. Create `src/session/events.zig`
2. Emit events for all operations
3. Integrate with event bus
4. Test event delivery

## Testing Requirements

1. **Unit Tests** (>95% coverage):
   - Handle lifecycle
   - Session operations
   - Share generation
   - Sync logic

2. **Integration Tests**:
   - Full session workflows
   - OpenCode communication
   - Error scenarios
   - Concurrent operations

3. **FFI Tests**:
   - C client compatibility
   - Memory management
   - Error propagation
   - Thread safety

## Example Usage (from C)

```c
// Create session
plue_session_t session = plue_session_create(NULL);
if (!session) {
    printf("Error: %s\n", plue_get_last_error());
    return;
}

// Get info
char* info_json = plue_session_get_info(session);
printf("Session info: %s\n", info_json);
plue_free_json(info_json);

// Update title
if (plue_session_update_title(session, "My Coding Session") != 0) {
    printf("Failed to update title\n");
}

// Create share link
char* share_json = plue_session_create_share(session);
printf("Share info: %s\n", share_json);
plue_free_json(share_json);

// Clean up
plue_session_destroy(session);
```

## Corner Cases and Implementation Details

Based on OpenCode's implementation, handle these critical scenarios:

### Session Storage Architecture
1. **Sessions Map**: All sessions stored in `sessions.json` as a single JSON map
2. **Message Storage**: Messages stored separately in `session/{id}/messages.json`
3. **Share Storage**: Share secrets stored in `session/share/{id}` directory
4. **Auto-Save**: OpenCode auto-saves on every change - no explicit save needed
5. **Version Tracking**: Each session stores the OpenCode version that created it

### Session Lifecycle Edge Cases
1. **ID Generation**: Uses `Identifier.create("session")` format with timestamp
2. **Title Default**: Always has a title, defaults to "Untitled" if not provided
3. **Parent Sessions**: parentID field exists but may not be fully implemented
4. **Auto-Share**: New sessions may auto-share based on flags/config
5. **Deletion Cascade**: Deleting session also removes messages and share data

### Share Management Specifics
1. **Share Creation**: Creates entry in Share service and stores locally
2. **URL Format**: Share URL comes from Share service, not generated locally
3. **Secret Storage**: Secrets stored separately from main session info
4. **Unshare**: Removes local share data but may not revoke remote access
5. **Share State**: Check `session.share` field for current share status

### Synchronization Challenges
1. **No Get Endpoint**: OpenCode has no `/session_get` - must use list and filter
2. **Event Bus**: Session updates broadcast via Bus.publish events
3. **Race Conditions**: Multiple clients may update same session
4. **Cache Invalidation**: 5-second cache may be too long for active sessions
5. **Partial Updates**: No partial update endpoints - must update entire object

### Abort Implementation Details
1. **Pending Map**: OpenCode tracks abort controllers in pending map
2. **Message Abort**: Aborting cancels in-progress AI responses
3. **Tool Abort**: Tool executions check abort signal periodically
4. **Cleanup**: Aborted operations should clean up partial state
5. **Status Indication**: No explicit "aborting" state in session info

### Error Handling Patterns
1. **Session Not Found**: List may not include very new sessions
2. **Concurrent Modifications**: Last-write-wins for conflicting updates
3. **Storage Errors**: File system errors should trigger retries
4. **Network Partitions**: Handle OpenCode server disconnections
5. **Invalid State**: Deleted sessions may still have handles

### UX Improvements
1. **Optimistic Updates**: Update UI before server confirms
2. **Progress Indication**: Show session operation progress
3. **Conflict Resolution**: Detect and merge concurrent edits
4. **Offline Support**: Queue operations when server unavailable
5. **Bulk Operations**: Batch multiple session operations

### Potential Bugs to Watch Out For
1. **Memory Leaks**: Ensure all session data is freed on handle destroy
2. **Thread Safety**: Mutex must protect all shared state access
3. **ID Collisions**: Timestamp-based IDs could collide in theory
4. **Encoding Issues**: Session titles may contain unicode
5. **Path Traversal**: Validate session IDs to prevent directory escape
6. **Event Order**: Events may arrive out of order during sync
7. **Zombie Handles**: Handles for deleted sessions must fail gracefully
8. **Cache Coherency**: Multiple handles for same session must sync
9. **Abort Propagation**: Local abort must reach OpenCode server
10. **Share Revocation**: Unshared sessions may still be accessible via old URLs

## Success Criteria

The implementation is complete when:
- [ ] All session FFI functions work correctly
- [ ] Session state stays synchronized with OpenCode via polling
- [ ] Handle management prevents memory leaks
- [ ] Share links work with proper secret validation
- [ ] Abort signals interrupt both local and remote operations
- [ ] Events fire for all state changes via Bus integration
- [ ] All tests pass with >95% coverage
- [ ] Thread safety is guaranteed with proper mutex usage
- [ ] Cache invalidation keeps data fresh
- [ ] Error messages provide actionable feedback

## Git Workflow

Continue in the same worktree:
```bash
cd ../plue-server-management
```

Commit with conventional commits:
- `feat: implement session handle management`
- `feat: add session manager with FFI`
- `feat: implement session sharing`
- `feat: add session synchronization`
- `feat: integrate session events`
- `test: add session bridge tests`

The branch remains: `feat_add_opencode_server_management`