# Sub-Agent Prompts for TUI Implementation

Ready-to-dispatch prompts for each sub-agent. Copy and dispatch these.

---

## Phase 1A: Project Setup

```markdown
# Task: Project Setup & Build Configuration

## Context
You are setting up the Zig project structure for a TUI that will connect to an existing Plue server.

**Critical**:
- libvaxis is at `/Users/williamcory/plue/libvaxis/` - use as local dependency
- The TUI connects to an EXISTING server at `http://localhost:4000` - don't rebuild the server
- Spec: `/Users/williamcory/plue/docs/prompts/tui/01_project_setup.md`

## Your Task
Create the initial project structure at `/Users/williamcory/plue/tui-zig/`:

1. Create `build.zig.zon` with libvaxis as path dependency
2. Create `build.zig` with:
   - Main executable target
   - Test target
   - Run step
   - libvaxis module import
3. Create `src/main.zig` - minimal entry point that:
   - Parses CLI args (--api-url, --help, --version)
   - Initializes vxfw.App
   - Runs placeholder widget
   - Exits cleanly on Ctrl+C
4. Create directory structure:
   ```
   tui-zig/
   ├── build.zig
   ├── build.zig.zon
   └── src/
       ├── main.zig
       ├── client/
       ├── state/
       ├── widgets/
       ├── render/
       ├── commands/
       ├── utils/
       └── tests/
   ```

## Testing Requirements
- `zig build` must succeed
- `zig build run` must show placeholder and exit on Ctrl+C
- `zig build run -- --help` shows usage
- `zig build run -- --version` shows version

## Validation
- [ ] All directories created
- [ ] build.zig.zon has correct libvaxis path (`../libvaxis`)
- [ ] build.zig compiles
- [ ] main.zig runs
- [ ] vxfw imports work

## Report
End with Implementation Report covering: files created, decisions, challenges, test results.
```

---

## Phase 1B: Core Types & State

```markdown
# Task: Core Types and State Structures

## Context
You are defining the foundational types for the TUI state management.

**Critical**:
- These types will be used throughout the TUI
- Must match the EXISTING server API responses
- Spec: `/Users/williamcory/plue/docs/prompts/tui/02_core_app_structure.md` and `04_state_management.md`

## Your Task
Create type definitions at `/Users/williamcory/plue/tui-zig/src/`:

1. `types.zig` - Core enums and simple types:
   - `ConnectionState` (disconnected, connecting, connected, reconnecting, error)
   - `UiMode` (chat, model_select, session_select, file_search, approval, help)
   - `TokenUsage` (input, output, cached, total())

2. `state/message.zig` - Message types:
   - `Message` (id, role, content, timestamp, tool_calls)
   - `Message.Role` (user, assistant, system)
   - `Message.Content` (text or parts)
   - `ToolCall` (id, name, args, result, status, duration)
   - `ToolCall.Status` (pending, running, completed, failed, declined)
   - Include deinit methods for cleanup

3. `state/session.zig` - Session types:
   - `Session` (id, title, model, reasoning_effort, directory, created_at, updated_at)
   - `ReasoningEffort` (minimal, low, medium, high) with toString/fromString

4. `state/conversation.zig` - Conversation state:
   - `Conversation` struct with messages ArrayList
   - Streaming state (is_streaming, streaming buffer)
   - Methods: addUserMessage, startStreaming, appendStreamingText, finishStreaming, abortStreaming

5. `state/app_state.zig` - Unified app state:
   - All state in one place
   - Input buffer with cursor
   - History navigation
   - Error handling

## Testing Requirements
Create `tests/types_test.zig`:
- Test ReasoningEffort.fromString/toString
- Test TokenUsage.total()
- Test Message creation and deinit
- Test Conversation streaming lifecycle

## Validation
- [ ] All types compile
- [ ] Memory management correct (deinit frees everything)
- [ ] Tests pass
- [ ] No unused imports

## Report
End with Implementation Report covering: files created, decisions, challenges, test results.
```

---

## Phase 1C: SSE Client & Protocol

```markdown
# Task: SSE Client and Protocol Types

## Context
You are building the HTTP/SSE client to communicate with the EXISTING Plue server.

**Critical**:
- Server already exists at `http://localhost:4000`
- Server already sends SSE events - you just parse them
- Do NOT rebuild any server-side logic
- Spec: `/Users/williamcory/plue/docs/prompts/tui/03_sse_client.md`
- Reference server code: `/Users/williamcory/plue/server/src/routes/agent.zig`

## Your Task
Create client code at `/Users/williamcory/plue/tui-zig/src/client/`:

1. `protocol.zig` - Event types matching server:
   ```zig
   pub const StreamEvent = union(enum) {
       text: TextEvent,
       tool_call: ToolCallEvent,
       tool_result: ToolResultEvent,
       usage: UsageEvent,
       message_completed,
       error_event: ErrorEvent,
       done,
   };
   ```
   - Include `parse(allocator, json_str) !StreamEvent`
   - Handle all event types the server sends

2. `http.zig` - Simple HTTP client wrapper:
   - GET, POST, PATCH methods
   - Timeout handling
   - Response struct with status, body, isSuccess()

3. `sse.zig` - SSE streaming client:
   - Parse `data: {json}\n\n` format
   - Callback-based event delivery
   - Thread-safe event queue for async integration
   - Handle connection errors gracefully

4. `client.zig` - High-level API facade:
   - `healthCheck() !bool`
   - `createSession(directory, model) !Session`
   - `listSessions() ![]Session`
   - `sendMessage(session_id, message, callback) !void`
   - `abort(session_id) !void`
   - `undo(session_id, turns) !void`

## Testing Requirements
Create `tests/protocol_test.zig`:
- Test parsing each event type
- Test malformed JSON handling
- Test missing fields handling

Create `tests/sse_test.zig`:
- Test SSE line parsing
- Test event queue thread safety

## Validation
- [ ] Protocol parses all server event types
- [ ] HTTP client handles timeouts
- [ ] SSE parsing handles partial lines
- [ ] Thread-safe queue works
- [ ] Tests pass

## Report
End with Implementation Report. Pay special attention to: challenges with SSE parsing, thread safety decisions.
```

---

## Phase 2A: Main App Widget

```markdown
# Task: Main Application Widget

## Context
You are building the main App widget that orchestrates the entire TUI.

**Critical**:
- Uses vxfw high-level framework from libvaxis
- Integrates with state from Phase 1B and client from Phase 1C
- Spec: `/Users/williamcory/plue/docs/prompts/tui/02_core_app_structure.md`
- Reference: `/Users/williamcory/plue/libvaxis/examples/` for vxfw patterns

## Your Task
Create/modify at `/Users/williamcory/plue/tui-zig/src/`:

1. `app.zig` - Main App struct:
   - Holds AppState pointer
   - Holds PlueClient
   - Holds EventQueue for async SSE
   - Implements vxfw.Widget interface (widget(), draw, handleEvent)

2. Event handling:
   - `.init` - connect to server, load sessions
   - `.key_press` - route to appropriate handler based on mode
   - `.tick` - process SSE event queue, update streaming
   - Global shortcuts (Ctrl+C to quit/abort)

3. Mode-specific handlers:
   - `handleChatMode` - text input, Enter to send, history nav
   - `handleSelectMode` - arrow navigation, Enter to select
   - `handleApprovalMode` - y/n/e keys

4. Drawing:
   - Placeholder layout: Header | Chat | Status | Composer
   - For now, draw placeholders - real widgets come in Phase 3
   - Handle overlays when mode != chat

5. Update `main.zig`:
   - Initialize AppState
   - Initialize App with state
   - Run vxfw.App with App.widget()

## Testing Requirements
Create `tests/app_test.zig`:
- Test mode switching
- Test input buffer operations
- Test history navigation
- Test Ctrl+C handling

## Validation
- [ ] App initializes and displays
- [ ] Ctrl+C exits cleanly
- [ ] Text input works
- [ ] Mode switching works
- [ ] SSE events processed on tick

## Report
End with Implementation Report. Emphasize: vxfw integration challenges, event loop design.
```

---

## Phase 3A: Layout Widgets

```markdown
# Task: Layout Widget System

## Context
You are building the layout primitives for composing the UI.

**Critical**:
- Must work with vxfw constraint-based layout
- Spec: `/Users/williamcory/plue/docs/prompts/tui/05_layout_system.md`
- Reference: `/Users/williamcory/plue/libvaxis/src/vxfw/` for patterns

## Your Task
Create at `/Users/williamcory/plue/tui-zig/src/widgets/`:

1. `layout.zig` - Stack layouts:
   - `VStack` - vertical stack with fixed/flex/fill heights
   - `HStack` - horizontal stack with fixed/flex/fill widths
   - Proper constraint propagation to children

2. `scroll_view.zig` - Scrollable container:
   - Scroll offset tracking
   - Page up/down, Home/End handling
   - Mouse wheel support
   - Scrollbar rendering
   - `ensureVisible(row)` method

3. `border.zig` - Border decoration:
   - Single, double, rounded, heavy styles
   - Optional title
   - Proper inner content sizing

4. `modal.zig` - Modal overlay:
   - Centered positioning
   - Dimmed background
   - Width/height as fixed or percentage
   - ESC to close

5. `main_layout.zig` - Main app layout:
   - Composes: Header | ScrollView(Chat) | Status | Composer
   - Modal overlay support
   - Scroll-to-bottom on new messages

## Testing Requirements
Create `tests/layout_test.zig`:
- Test VStack height allocation
- Test HStack width allocation
- Test scroll offset clamping
- Test modal positioning

## Validation
- [ ] VStack/HStack allocate space correctly
- [ ] ScrollView scrolls and shows scrollbar
- [ ] Border draws all styles correctly
- [ ] Modal centers and dims background
- [ ] MainLayout composes correctly

## Report
End with Implementation Report. Emphasize: constraint calculation challenges, overflow handling.
```

---

## Phase 3B: Chat History Widget

```markdown
# Task: Chat History Display

## Context
You are building the scrollable chat history that displays messages.

**Critical**:
- Must handle streaming (partial messages)
- Must display tool calls inline
- Spec: `/Users/williamcory/plue/docs/prompts/tui/06_chat_history.md`

## Your Task
Create at `/Users/williamcory/plue/tui-zig/src/widgets/`:

1. `cells.zig` - Renderable chat cells:
   - `HistoryCell` union with all cell types
   - `UserMessageCell` - blue "> " prefix
   - `AssistantMessageCell` - green "⏺ " prefix
   - `ToolCallCell` - icon, name, status, duration
   - `StreamingCell` - with blinking cursor
   - `SystemMessageCell` - yellow italic
   - Each has: height(width), draw(surface, row, width)

2. `chat_history.zig` - Main chat widget:
   - Takes Conversation pointer
   - Rebuilds cells when conversation changes
   - Handles streaming text display
   - Calculates total content height
   - Provides getContentHeight for scroll calculation

3. `empty_state.zig` - Empty conversation display:
   - Welcome message
   - Hint shortcuts (/help, /model, /new)
   - Centered layout

4. Text wrapping utility in `utils/wrap.zig`:
   - Word wrap at width
   - Handle unicode grapheme clusters
   - Calculate wrapped height

## Testing Requirements
Create `tests/cells_test.zig`:
- Test cell height calculation
- Test text wrapping
- Test streaming cell cursor position

## Validation
- [ ] User messages display correctly
- [ ] Assistant messages display correctly
- [ ] Tool calls show icon and status
- [ ] Streaming shows cursor
- [ ] Text wraps at terminal width
- [ ] Empty state shows when no messages

## Report
End with Implementation Report. Emphasize: text wrapping challenges, unicode handling.
```

---

## Phase 3C: Input Composer

```markdown
# Task: Multi-line Input Composer

## Context
You are building the input area where users type messages and commands.

**Critical**:
- Must support cursor movement and editing
- Must detect slash commands and @mentions
- Spec: `/Users/williamcory/plue/docs/prompts/tui/07_input_composer.md`

## Your Task
Create at `/Users/williamcory/plue/tui-zig/src/widgets/`:

1. `composer.zig` - Input widget:
   - Takes AppState pointer for input buffer
   - Draws prompt "> "
   - Draws input text with cursor
   - Highlights slash commands (cyan)
   - Highlights @mentions (magenta)
   - Shows placeholder when empty
   - Shows context-aware keyboard hints

   Key handling:
   - Arrow keys for cursor movement
   - Home/End (or Ctrl+A/E)
   - Backspace/Delete
   - Ctrl+W (delete word)
   - Ctrl+U (delete to start)
   - Ctrl+K (delete to end)
   - Up/Down for history
   - Regular text input

2. `autocomplete.zig` - Autocomplete popup:
   - Shows suggestions list
   - Arrow navigation
   - Tab/Enter to accept
   - ESC to dismiss
   - Anchored to cursor position

## Testing Requirements
Create `tests/composer_test.zig`:
- Test cursor movement
- Test text deletion (word, line)
- Test slash command detection
- Test @mention detection
- Test history navigation

## Validation
- [ ] Cursor moves correctly
- [ ] Backspace/delete work
- [ ] Ctrl shortcuts work
- [ ] History navigation works
- [ ] Slash commands highlighted
- [ ] @mentions highlighted
- [ ] Placeholder shows when empty

## Report
End with Implementation Report. Emphasize: cursor positioning challenges, unicode handling.
```

---

## Review Agent Prompt (use after each phase)

```markdown
# Task: Review Phase [N] - [Phase Name]

## Context
Phase [N] implementation is complete. Validate ALL work before proceeding.

## Files to Review
[List all files from the phase]

## Review Protocol

### Step 1: Compilation
```bash
cd /Users/williamcory/plue/tui-zig
zig build
zig build test
```
Report output. FAIL if either fails.

### Step 2: Code Review
For EACH file:
- [ ] Proper Zig idioms (snake_case, error handling)
- [ ] Memory management (allocator usage, defer)
- [ ] No ignored errors (try/catch all)
- [ ] Minimal public API
- [ ] No dead code

### Step 3: Integration Check
- [ ] Imports resolve (no missing dependencies)
- [ ] Types compatible between modules
- [ ] Uses EXISTING server API, doesn't rebuild

### Step 4: Test Coverage
- [ ] Tests exist for public functions
- [ ] Edge cases covered
- [ ] Error paths tested

### Step 5: Spec Compliance
Compare to `/Users/williamcory/plue/docs/prompts/tui/[specs].md`:
- [ ] Required features implemented
- [ ] API matches spec

### Step 6: Polish
- [ ] No debug prints
- [ ] No unaddressed TODOs
- [ ] Consistent style

## Your Output

### Review Result: [PASS / FAIL / PASS WITH NOTES]

### Compilation
```
[output]
```

### Test Results
```
[output]
```

### Issues Found
| Severity | File | Issue | Action |
|----------|------|-------|--------|
| [HIGH/MED/LOW] | [file] | [issue] | [fix required?] |

### Fixes Applied
[List any fixes you made directly]

### Blocking Issues (if FAIL)
[What MUST be fixed before proceeding]

### Recommendations
[Suggestions for improvement]
```

---

## Quick Reference: Dispatch Order

```
PHASE 1 (parallel):
  - Dispatch: 1A, 1B, 1C simultaneously
  - Wait for all
  - Dispatch: Review 1
  - Wait for PASS

PHASE 2 (sequential):
  - Dispatch: 2A
  - Wait
  - Dispatch: Review 2
  - Wait for PASS

PHASE 3 (parallel):
  - Dispatch: 3A, 3B, 3C simultaneously
  - Wait for all
  - Dispatch: Review 3
  - Wait for PASS

PHASE 4 (parallel):
  - Dispatch: 4A (markdown), 4B (syntax), 4C (diff) simultaneously
  - Wait for all
  - Dispatch: Review 4
  - Wait for PASS

PHASE 5 (parallel):
  - Dispatch: 5A (tools), 5B (approval), 5C (sessions) simultaneously
  - Wait for all
  - Dispatch: Review 5
  - Wait for PASS

PHASE 6 (parallel):
  - Dispatch: 6A (commands), 6B (files) simultaneously
  - Wait for all
  - Dispatch: Review 6
  - Wait for PASS

PHASE 7 (sequential):
  - Dispatch: 7A (integration)
  - Wait
  - Dispatch: Final Review
  - Wait for PASS
  - DONE
```
