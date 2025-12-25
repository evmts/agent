# Widgets

Reusable UI components built on libvaxis for the TUI.

## Architecture

All widgets follow the vxfw pattern:

```zig
pub const Widget = struct {
    // Widget state
    state: *AppState,

    pub fn widget(self: *Widget) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = handleEvent,
            .drawFn = draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        // Handle key presses, focus, etc
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        // Render to surface
    }
};
```

## Core Widgets

| Widget | Purpose |
|--------|---------|
| `composer.zig` | Message input box with syntax highlighting |
| `chat_history.zig` | Scrollable message history display |
| `tool_card.zig` | Tool use visualization (Bash, Edit, etc) |
| `command_approval.zig` | Approve/reject command execution |
| `file_approval.zig` | Approve/reject file operations |

## Layout Widgets

| Widget | Purpose |
|--------|---------|
| `layout.zig` | Flexible box layout (horizontal/vertical) |
| `border.zig` | Bordered container with title |
| `modal.zig` | Overlay modal dialog |
| `scroll_view.zig` | Scrollable content area |

## Picker Widgets

| Widget | Purpose |
|--------|---------|
| `model_picker.zig` | Select Claude model |
| `effort_picker.zig` | Select reasoning effort level |
| `session_list.zig` | Select active session |

## Utility Widgets

| Widget | Purpose |
|--------|---------|
| `autocomplete.zig` | Command/file autocomplete dropdown |
| `help_view.zig` | Command help overlay |
| `empty_state.zig` | Placeholder for empty screens |
| `exec_output.zig` | Command execution output display |
| `cells.zig` | Cell manipulation utilities |

## Widget Communication

Widgets interact via shared `AppState`:

```
┌──────────────────┐
│   Composer       │───┐
└──────────────────┘   │
                       │
┌──────────────────┐   │    ┌──────────────┐
│  ChatHistory     │───┼───▶│  AppState    │
└──────────────────┘   │    │              │
                       │    │ - sessions   │
┌──────────────────┐   │    │ - messages   │
│   ToolCard       │───┘    │ - input      │
└──────────────────┘        │ - mode       │
                            └──────────────┘
```

## Styling

Widgets use vaxis styling:

```zig
const STYLE = vaxis.Cell.Style{
    .fg = .{ .index = 12 },  // Color index
    .bg = .{ .index = 0 },   // Background
    .bold = true,            // Formatting
    .italic = false,
    .reverse = false,
};
```

## Event Flow

```
User Input
    │
    ▼
┌─────────────────┐
│  app.zig        │  Main event handler
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Focused Widget │  Widget-specific handler
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  AppState       │  Update state
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Redraw         │  Trigger repaint
└─────────────────┘
```

## Testing

Widgets have unit tests in `tests/`:

```bash
zig build test:tui
```

Example tests:
- `composer_test.zig`: Input handling, cursor movement
- `cells_test.zig`: Cell manipulation
- `layout_test.zig`: Box model calculations
