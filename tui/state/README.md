# State

Application state management for the TUI.

## Architecture

```
┌──────────────────────────────────────────────┐
│         AppState (app_state.zig)             │
│  Unified state container for entire app     │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ Sessions │  │Messages  │  │   Input  │  │
│  └──────────┘  └──────────┘  └──────────┘  │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │   UI     │  │  Tokens  │  │  Config  │  │
│  └──────────┘  └──────────┘  └──────────┘  │
└──────────────────────────────────────────────┘
         │              │              │
         ▼              ▼              ▼
    ┌────────┐  ┌─────────────┐  ┌──────────┐
    │Session │  │Conversation │  │ Approval │
    └────────┘  └─────────────┘  └──────────┘
```

## Files

| File | Purpose |
|------|---------|
| `app_state.zig` | Root state container, initialization |
| `session.zig` | Session metadata and configuration |
| `conversation.zig` | Message history for a session |
| `message.zig` | Individual message structure |
| `approval.zig` | Tool approval tracking and management |

## AppState Structure

```zig
pub const AppState = struct {
    // Configuration
    api_url: []const u8,
    working_directory: []const u8,

    // Connection
    connection: ConnectionState,
    last_error: ?[]const u8,

    // Sessions
    sessions: std.ArrayList(Session),
    current_session: ?*Session,
    conversations: std.StringHashMap(Conversation),

    // Input
    input_buffer: std.ArrayList(u8),
    input_cursor: usize,
    input_history: std.ArrayList([]const u8),
    history_index: ?usize,

    // UI
    mode: UiMode,
    scroll_offset: usize,
    selected_index: usize,

    // Tokens
    token_usage: TokenUsage,
};
```

## State Flow

```
User Action
    │
    ▼
Widget Event Handler
    │
    ▼
Modify AppState
    │
    ▼
Trigger Redraw
    │
    ▼
Widgets Read State
    │
    ▼
Render Updated UI
```

## Session Management

```zig
// Create session
const session = Session{
    .id = "abc123",
    .directory = "/path/to/repo",
    .model = "claude-sonnet-4",
    .effort = .medium,
};
try state.sessions.append(session);

// Set current session
state.current_session = &state.sessions.items[0];

// Get conversation for session
const conv = state.conversations.get(session.id);
```

## Conversation Management

```zig
pub const Conversation = struct {
    session_id: []const u8,
    messages: std.ArrayList(Message),

    pub fn addMessage(self: *Conversation, message: Message) !void {
        try self.messages.append(message);
    }

    pub fn clear(self: *Conversation) void {
        self.messages.clearRetainingCapacity();
    }
};
```

## Message Types

```zig
pub const Message = struct {
    role: Role,         // user | assistant | tool_result
    content: []const u8,
    timestamp: i64,
    tool_use: ?ToolUse,
};

pub const Role = enum {
    user,
    assistant,
    tool_result,
};
```

## Approval Management

```zig
pub const ApprovalManager = struct {
    pending: std.ArrayList(ApprovalRequest),

    pub fn addRequest(self: *ApprovalManager, req: ApprovalRequest) !void
    pub fn approve(self: *ApprovalManager, id: usize) void
    pub fn reject(self: *ApprovalManager, id: usize) void
};
```

## UI Modes

```zig
pub const UiMode = enum {
    chat,              // Normal chat
    session_picker,    // Selecting session
    model_picker,      // Selecting model
    effort_picker,     // Selecting effort
    help,              // Help overlay
    command_approval,  // Approving command
    file_approval,     // Approving file op
};
```

## Memory Management

All state is owned by `AppState` and cleaned up in `deinit()`:

```zig
pub fn deinit(self: *AppState) void {
    for (self.sessions.items) |*s| s.deinit();
    self.sessions.deinit();

    var it = self.conversations.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    self.conversations.deinit();

    // ... cleanup other resources
}
```
