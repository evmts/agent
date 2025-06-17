# Neovim RPC Integration Plan

## Overview
This document outlines the implementation plan for completing the Neovim RPC integration in Plue, building on the mock foundation already in place.

## Current State
- ✅ Mock `NvimClient` structure in place
- ✅ Event system refactored to support `vim_state_updated` events
- ✅ VimState includes `nvim_client` field
- ✅ Build system configured to include nvim_client module

## Implementation Steps

### Phase 1: Add Msgpack Dependency
1. Add zig-msgpack or similar library to build.zig
2. Configure module imports properly
3. Test basic msgpack serialization/deserialization

### Phase 2: Socket Connection
1. Implement Unix domain socket connection in `NvimClient.init()`
2. Handle connection errors gracefully
3. Add connection state management

### Phase 3: RPC Protocol Implementation
1. Implement request/response handling
2. Add request ID management for concurrent requests
3. Handle notifications from Neovim

### Phase 4: Core API Methods
Priority methods to implement:
- `nvim_buf_get_lines` - Get buffer content
- `nvim_win_get_cursor` - Get cursor position
- `nvim_get_mode` - Get current mode
- `nvim_buf_set_lines` - Set buffer content (for agent operations)
- `nvim_command` - Execute Ex commands
- `nvim_input` - Send key input

### Phase 5: State Synchronization
1. Set up autocmd listeners in Neovim for state changes
2. Handle notifications for:
   - Buffer changes
   - Cursor movements
   - Mode changes
3. Trigger `vim_state_updated` events appropriately

### Phase 6: Terminal Integration
1. Modify terminal.zig to launch nvim with `--listen` flag
2. Ensure socket path is properly communicated
3. Handle nvim process lifecycle

## Technical Considerations

### Msgpack-RPC Format
Neovim uses msgpack-rpc with the following message types:
- Request: `[0, msgid, method, params]`
- Response: `[1, msgid, error, result]`
- Notification: `[2, method, params]`

### Error Handling
- Connection failures
- RPC errors
- Timeout handling
- Graceful degradation if Neovim is not available

### Performance
- Use buffered I/O for socket communication
- Implement request batching where appropriate
- Cache frequently accessed state

## Example Implementation Structure

```zig
const std = @import("std");
const msgpack = @import("msgpack");

pub const NvimClient = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    next_request_id: u32,
    pending_requests: std.AutoHashMap(u32, PendingRequest),
    
    const PendingRequest = struct {
        method: []const u8,
        callback: ?fn(result: msgpack.Value) void,
    };
    
    pub fn init(allocator: std.mem.Allocator, socket_path: []const u8) !*NvimClient {
        const stream = try std.net.connectUnixSocket(socket_path);
        const self = try allocator.create(NvimClient);
        self.* = .{
            .allocator = allocator,
            .stream = stream,
            .next_request_id = 1,
            .pending_requests = std.AutoHashMap(u32, PendingRequest).init(allocator),
        };
        
        // Start notification handler thread
        const thread = try std.Thread.spawn(.{}, notificationHandler, .{self});
        thread.detach();
        
        return self;
    }
    
    fn sendRequest(self: *NvimClient, method: []const u8, params: anytype) !u32 {
        const msgid = self.next_request_id;
        self.next_request_id += 1;
        
        const request = .{ 0, msgid, method, params };
        try msgpack.encode(request, self.stream.writer());
        
        return msgid;
    }
    
    fn notificationHandler(self: *NvimClient) void {
        while (true) {
            const msg = msgpack.decode(self.stream.reader()) catch break;
            // Handle responses and notifications
            // Trigger vim_state_updated events as needed
        }
    }
};
```

## Testing Plan
1. Unit tests for msgpack serialization
2. Integration tests with a test Neovim instance
3. Performance benchmarks for RPC overhead
4. Stress tests with rapid state changes

## Success Criteria
- [ ] Can connect to Neovim via Unix socket
- [ ] Can retrieve and display buffer content
- [ ] Cursor position updates in real-time
- [ ] Mode changes reflect immediately in UI
- [ ] No noticeable lag in normal editing operations
- [ ] Graceful handling of Neovim crashes/restarts