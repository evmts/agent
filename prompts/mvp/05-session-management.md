# Implement Session Management API for Plue AI Editor

You are an AI agent executing a well-scoped task to build an AI editor in Zig. This task focuses on implementing the session management system that tracks conversations between users and AI agents, including persistence, branching, and state management.

## Context

<context>
<project_overview>
Plue is a multi-agent coding assistant where sessions are the core abstraction for conversations:
- Sessions contain the full message history between users and AI
- Sessions can be branched to explore different conversation paths
- Sessions are persisted to disk for resumption
- Sessions track metadata like title, creation time, and sharing status
- All session state is owned and managed by the Zig core
</project_overview>

<existing_infrastructure>
From previous implementations:
- Enhanced error handling system is available
- Comprehensive JSON utilities for serialization
- Basic FFI infrastructure exists in libplue.zig
- Global state management patterns are established
</existing_infrastructure>

<api_specification>
From PLUE_CORE_API.md, the session API includes:
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

// Delete a session and all associated data
export fn plue_session_delete(session: ?*anyopaque) c_int;

// Abort ongoing operations in a session
export fn plue_session_abort(session: ?*anyopaque) c_int;

// Create a shareable link for a session
export fn plue_session_create_share(session: ?*anyopaque) [*c]u8;

// Destroy session handle (does not delete session data)
export fn plue_session_destroy(session: ?*anyopaque) void;
```
</api_specification>

<reference_implementation>
OpenCode (in opencode/) has a mature session system:
- opencode/packages/opencode/src/session/index.ts - Core session logic
- Session ID format: session_TIMESTAMP (e.g., session_1704067200000)
- Sessions stored as JSON files in data directory
- Supports branching, auto-summarization, and sharing
- Integrates with storage layer for persistence
</reference_implementation>
</context>

## Task: Implement Session Management API

### Requirements

1. **Design session data structures** that support:
   - Unique session IDs with timestamp format
   - Parent-child relationships for branching
   - Metadata (title, creation time, last modified)
   - Sharing capabilities with secure URLs
   - Abort signals for cancellation

2. **Implement session lifecycle management**:
   - Creation with optional parent
   - Info retrieval and listing
   - Title updates
   - Deletion with cascade cleanup
   - Handle destruction vs deletion

3. **Add persistence layer**:
   - Save sessions to disk as JSON files
   - Atomic writes to prevent corruption
   - Efficient loading and caching
   - Directory structure organization

4. **Create sharing functionality**:
   - Generate secure share URLs
   - Track share metadata
   - Implement access control

### Detailed Steps

1. **Create src/session/session.zig with core types**:
   ```zig
   const std = @import("std");
   const json = @import("../json.zig");
   const error_handling = @import("../error.zig");
   
   pub const SessionId = []const u8;
   
   pub const Session = struct {
       id: SessionId,
       parent_id: ?SessionId,
       title: []const u8,
       created_at: i64,
       updated_at: i64,
       message_count: u32,
       is_aborted: bool,
       share_info: ?ShareInfo,
       
       // Opaque handle for FFI
       handle: *anyopaque,
       
       // Abort signal for cancellation
       abort_source: std.Thread.ResetEvent,
       
       pub fn init(allocator: Allocator, parent_id: ?SessionId) !Session {
           const timestamp = std.time.milliTimestamp();
           const id = try std.fmt.allocPrint(allocator, "session_{d}", .{timestamp});
           
           return Session{
               .id = id,
               .parent_id = if (parent_id) |p| try allocator.dupe(u8, p) else null,
               .title = try allocator.dupe(u8, "New Session"),
               .created_at = timestamp,
               .updated_at = timestamp,
               .message_count = 0,
               .is_aborted = false,
               .share_info = null,
               .abort_source = std.Thread.ResetEvent{},
           };
       }
       
       pub fn toJson(self: Session, allocator: Allocator) ![]u8 {
           // Convert to JSON info format
       }
   };
   
   pub const ShareInfo = struct {
       url: []const u8,
       secret: []const u8,
       created_at: i64,
       expires_at: ?i64,
   };
   ```

2. **Implement session manager for lifecycle operations**:
   ```zig
   pub const SessionManager = struct {
       allocator: Allocator,
       sessions: std.StringHashMap(*Session),
       storage_path: []const u8,
       mutex: std.Thread.Mutex,
       
       pub fn init(allocator: Allocator, storage_path: []const u8) !SessionManager {
           // Create storage directory if needed
           try std.fs.cwd().makePath(storage_path);
           
           var manager = SessionManager{
               .allocator = allocator,
               .sessions = std.StringHashMap(*Session).init(allocator),
               .storage_path = storage_path,
               .mutex = std.Thread.Mutex{},
           };
           
           // Load existing sessions from disk
           try manager.loadSessions();
           
           return manager;
       }
       
       pub fn createSession(self: *SessionManager, parent_id: ?SessionId) !*Session {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           // Validate parent exists if provided
           if (parent_id) |pid| {
               if (!self.sessions.contains(pid)) {
                   return error.NotFound;
               }
           }
           
           // Create new session
           const session = try self.allocator.create(Session);
           session.* = try Session.init(self.allocator, parent_id);
           
           // Add to manager
           try self.sessions.put(session.id, session);
           
           // Persist to disk
           try self.saveSession(session);
           
           return session;
       }
       
       pub fn getSession(self: *SessionManager, id: SessionId) !*Session {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           return self.sessions.get(id) orelse error.NotFound;
       }
       
       pub fn listSessions(self: *SessionManager, allocator: Allocator) ![]u8 {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           // Build JSON array of session info
           var array = std.ArrayList(json.Value).init(allocator);
           defer array.deinit();
           
           var iter = self.sessions.iterator();
           while (iter.next()) |entry| {
               const info = try entry.value_ptr.*.toJson(allocator);
               try array.append(try json.parse(allocator, info));
           }
           
           return json.stringify(allocator, array.items, .{});
       }
   };
   ```

3. **Add persistence layer with atomic writes**:
   ```zig
   fn saveSession(self: *SessionManager, session: *Session) !void {
       const file_path = try self.getSessionPath(session.id);
       
       // Serialize session to JSON
       const session_json = try session.toJson(self.allocator);
       defer self.allocator.free(session_json);
       
       // Atomic write: write to temp file then rename
       const temp_path = try std.fmt.allocPrint(
           self.allocator,
           "{s}.tmp",
           .{file_path}
       );
       defer self.allocator.free(temp_path);
       
       // Write to temp file
       const file = try std.fs.cwd().createFile(temp_path, .{});
       defer file.close();
       try file.writeAll(session_json);
       try file.sync();
       
       // Atomic rename
       try std.fs.cwd().rename(temp_path, file_path);
   }
   
   fn loadSessions(self: *SessionManager) !void {
       var dir = try std.fs.cwd().openIterableDir(self.storage_path, .{});
       defer dir.close();
       
       var iter = dir.iterate();
       while (try iter.next()) |entry| {
           if (entry.kind != .File) continue;
           if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
           
           const file_path = try std.fs.path.join(
               self.allocator,
               &.{ self.storage_path, entry.name }
           );
           defer self.allocator.free(file_path);
           
           // Load and parse session
           const content = try std.fs.cwd().readFileAlloc(
               self.allocator,
               file_path,
               1024 * 1024 // 1MB max
           );
           defer self.allocator.free(content);
           
           const session = try self.parseSession(content);
           try self.sessions.put(session.id, session);
       }
   }
   ```

4. **Implement session operations**:
   ```zig
   pub fn updateTitle(self: *SessionManager, session: *Session, title: []const u8) !void {
       self.mutex.lock();
       defer self.mutex.unlock();
       
       // Update title
       self.allocator.free(session.title);
       session.title = try self.allocator.dupe(u8, title);
       session.updated_at = std.time.milliTimestamp();
       
       // Persist changes
       try self.saveSession(session);
   }
   
   pub fn deleteSession(self: *SessionManager, session: *Session) !void {
       self.mutex.lock();
       defer self.mutex.unlock();
       
       // Remove from memory
       _ = self.sessions.remove(session.id);
       
       // Delete file
       const file_path = try self.getSessionPath(session.id);
       try std.fs.cwd().deleteFile(file_path);
       
       // Clean up messages and other associated data
       try self.deleteSessionData(session.id);
       
       // Free memory
       session.deinit(self.allocator);
       self.allocator.destroy(session);
   }
   
   pub fn abortSession(self: *SessionManager, session: *Session) !void {
       self.mutex.lock();
       defer self.mutex.unlock();
       
       // Set abort flag
       session.is_aborted = true;
       
       // Signal abort to any waiting operations
       session.abort_source.set();
       
       // Save state
       try self.saveSession(session);
   }
   ```

5. **Add sharing functionality**:
   ```zig
   pub fn createShare(self: *SessionManager, session: *Session) !ShareInfo {
       self.mutex.lock();
       defer self.mutex.unlock();
       
       // Generate secure random secret
       var secret_bytes: [32]u8 = undefined;
       std.crypto.random.bytes(&secret_bytes);
       const secret = try self.encodeBase64(secret_bytes);
       
       // Create share URL (placeholder - actual URL depends on deployment)
       const url = try std.fmt.allocPrint(
           self.allocator,
           "https://plue.app/share/{s}",
           .{secret}
       );
       
       const share_info = ShareInfo{
           .url = url,
           .secret = secret,
           .created_at = std.time.milliTimestamp(),
           .expires_at = null, // No expiration by default
       };
       
       // Update session
       session.share_info = share_info;
       session.updated_at = std.time.milliTimestamp();
       
       // Persist
       try self.saveSession(session);
       
       return share_info;
   }
   ```

6. **Implement FFI exports in libplue.zig**:
   ```zig
   // Global session manager instance
   var g_session_manager: ?*SessionManager = null;
   
   export fn plue_session_create(parent_id: [*:0]const u8) ?*anyopaque {
       const parent = if (parent_id[0] != 0)
           std.mem.span(parent_id)
       else
           null;
       
       const session = g_session_manager.?.createSession(parent) catch |err| {
           error_handling.setError(err, "Failed to create session", .{});
           return null;
       };
       
       return @ptrCast(*anyopaque, session);
   }
   
   export fn plue_session_get_info(session_ptr: ?*anyopaque) [*c]u8 {
       const session = @ptrCast(*Session, @alignCast(@alignOf(Session), session_ptr.?));
       
       const info = session.toJson(g_allocator) catch |err| {
           error_handling.setError(err, "Failed to get session info", .{});
           return null;
       };
       
       return info.ptr;
   }
   
   export fn plue_session_list() [*c]u8 {
       const list_json = g_session_manager.?.listSessions(g_allocator) catch |err| {
           error_handling.setError(err, "Failed to list sessions", .{});
           return null;
       };
       
       return list_json.ptr;
   }
   
   // ... implement other FFI functions
   ```

### Implementation Approach

Follow TDD methodology:

1. **Write comprehensive tests first**:
   - Test session creation and ID generation
   - Test parent-child relationships
   - Test persistence and loading
   - Test concurrent operations
   - Test abort functionality
   - Test sharing URL generation

2. **Implement incrementally**:
   - Basic session structure first
   - Add persistence layer
   - Implement manager operations
   - Add FFI exports
   - Integrate with existing system

3. **Commit after each milestone**:
   - Session types defined
   - Manager implemented
   - Persistence working
   - FFI exports complete
   - Tests passing

### Git Workflow

```bash
git worktree add worktrees/session-management -b feat/session-management
cd worktrees/session-management
```

Commits:
- `feat: define session data structures and types`
- `feat: implement session manager with lifecycle ops`
- `feat: add atomic session persistence layer`
- `feat: implement session abort functionality`
- `feat: add secure session sharing feature`
- `feat: export session FFI functions`
- `test: comprehensive session management tests`
- `refactor: integrate sessions with global state`

## Success Criteria

✅ **Task is complete when**:
1. Sessions can be created with unique timestamp IDs
2. Parent-child relationships work for branching
3. Sessions persist to disk atomically
4. All FFI functions work correctly from Swift
5. Concurrent operations are thread-safe
6. Abort signals propagate to operations
7. Sharing generates secure URLs
8. All tests pass with >95% coverage

## Technical Considerations

<zig_patterns>
- Use opaque pointers for FFI handles
- Implement proper cleanup in deinit methods
- Use arena allocators for temporary data
- Leverage Zig's error unions consistently
- Follow single ownership principles
</zig_patterns>

<persistence_requirements>
- Use atomic writes to prevent corruption
- Implement efficient loading with lazy parsing
- Organize files by date for easy management
- Support migration for format changes
- Handle disk space errors gracefully
</persistence_requirements>

<concurrency_considerations>
- Protect shared state with mutexes
- Use thread-local storage for errors
- Implement lock-free abort signaling
- Avoid deadlocks in nested operations
- Test with ThreadSanitizer
</concurrency_considerations>

Remember: Sessions are the core abstraction in Plue. Make them robust, efficient, and easy to work with. Many other components will depend on this foundation.