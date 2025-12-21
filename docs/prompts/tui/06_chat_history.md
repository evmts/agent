# 06: Chat History Widget

## Goal

Implement the main chat history widget that displays messages, tool calls, and streaming content with proper formatting and scrolling.

## Context

- This is the primary content area showing the conversation
- Must handle: user messages, assistant responses, tool calls, streaming text
- Reference: `/Users/williamcory/plue/codex/codex-rs/tui/src/` (Rust implementation)
- Uses markdown renderer from prompt 09 (stub for now)

## Message Display Types

1. **User Message**: Blue prefix `> `, plain text
2. **Assistant Message**: Green prefix `⏺ `, markdown rendered
3. **Tool Call**: Cyan with icon, args, status, duration
4. **Streaming**: Animated text with cursor

## Tasks

### 1. Create Message Cell Types (src/widgets/cells.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Message = @import("../state/message.zig").Message;
const ToolCall = @import("../state/message.zig").ToolCall;

/// Represents a renderable item in chat history
pub const HistoryCell = union(enum) {
    user_message: UserMessageCell,
    assistant_message: AssistantMessageCell,
    tool_call: ToolCallCell,
    streaming: StreamingCell,
    system_message: SystemMessageCell,
    separator: SeparatorCell,

    pub fn height(self: HistoryCell, width: u16) u16 {
        return switch (self) {
            .user_message => |c| c.height(width),
            .assistant_message => |c| c.height(width),
            .tool_call => |c| c.height(width),
            .streaming => |c| c.height(width),
            .system_message => |c| c.height(width),
            .separator => 1,
        };
    }

    pub fn draw(self: *HistoryCell, surface: *vxfw.Surface, start_row: u16, width: u16) void {
        switch (self.*) {
            .user_message => |*c| c.draw(surface, start_row, width),
            .assistant_message => |*c| c.draw(surface, start_row, width),
            .tool_call => |*c| c.draw(surface, start_row, width),
            .streaming => |*c| c.draw(surface, start_row, width),
            .system_message => |*c| c.draw(surface, start_row, width),
            .separator => |*c| c.draw(surface, start_row, width),
        }
    }
};

pub const UserMessageCell = struct {
    content: []const u8,
    timestamp: i64,

    const PREFIX = "> ";
    const PREFIX_STYLE = vaxis.Cell.Style{ .fg = .{ .index = 12 }, .bold = true }; // Blue
    const TEXT_STYLE = vaxis.Cell.Style{ .fg = .{ .index = 7 } }; // White

    pub fn height(self: UserMessageCell, width: u16) u16 {
        return wrapHeight(self.content, width -| @as(u16, PREFIX.len));
    }

    pub fn draw(self: *UserMessageCell, surface: *vxfw.Surface, start_row: u16, width: u16) void {
        // Draw prefix
        for (PREFIX, 0..) |char, i| {
            surface.writeCell(@intCast(i), start_row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = PREFIX_STYLE,
            });
        }

        // Draw wrapped content
        drawWrappedText(surface, self.content, start_row, PREFIX.len, width, TEXT_STYLE);
    }
};

pub const AssistantMessageCell = struct {
    content: []const u8,
    tool_calls: []ToolCall,
    timestamp: i64,

    const PREFIX = "⏺ ";
    const PREFIX_STYLE = vaxis.Cell.Style{ .fg = .{ .index = 10 }, .bold = true }; // Green

    pub fn height(self: AssistantMessageCell, width: u16) u16 {
        var h = wrapHeight(self.content, width -| 2);
        for (self.tool_calls) |tc| {
            h += ToolCallCell.heightFor(tc, width);
        }
        return h;
    }

    pub fn draw(self: *AssistantMessageCell, surface: *vxfw.Surface, start_row: u16, width: u16) void {
        // Draw prefix
        surface.writeCell(0, start_row, .{
            .char = .{ .grapheme = "⏺", .width = 1 },
            .style = PREFIX_STYLE,
        });
        surface.writeCell(1, start_row, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = PREFIX_STYLE,
        });

        // Draw content (TODO: use markdown renderer)
        var row = start_row;
        row += drawWrappedText(surface, self.content, row, 2, width, .{ .fg = .{ .index = 7 } });

        // Draw tool calls
        for (self.tool_calls) |tc| {
            var tool_cell = ToolCallCell{
                .tool_call = tc,
            };
            tool_cell.draw(surface, row, width);
            row += tool_cell.height(width);
        }
    }
};

pub const ToolCallCell = struct {
    tool_call: ToolCall,

    const ICONS = std.ComptimeStringMap([]const u8, .{
        .{ "grep", "🔍" },
        .{ "readFile", "📄" },
        .{ "writeFile", "✏️" },
        .{ "multiedit", "📝" },
        .{ "webFetch", "🌐" },
        .{ "unifiedExec", "💻" },
        .{ "bash", "💻" },
        .{ "github", "🐙" },
    });

    pub fn height(self: ToolCallCell, width: u16) u16 {
        return heightFor(self.tool_call, width);
    }

    pub fn heightFor(tc: ToolCall, _: u16) u16 {
        var h: u16 = 1; // Tool name line
        if (tc.result) |_| {
            h += 1; // Result line
        }
        return h;
    }

    pub fn draw(self: *ToolCallCell, surface: *vxfw.Surface, start_row: u16, width: u16) void {
        const tc = self.tool_call;

        // Get icon
        const icon = ICONS.get(tc.name) orelse "🔧";

        // Status indicator
        const status_char: []const u8 = switch (tc.status) {
            .pending => "○",
            .running => "◐",
            .completed => "●",
            .failed => "✗",
            .declined => "⊘",
        };
        const status_color: vaxis.Color = switch (tc.status) {
            .pending => .{ .index = 8 },
            .running => .{ .index = 14 },
            .completed => .{ .index = 10 },
            .failed => .{ .index = 9 },
            .declined => .{ .index = 11 },
        };

        // Draw: [icon] [status] tool_name (duration)
        var col: u16 = 2;

        // Icon
        surface.writeCell(col, start_row, .{
            .char = .{ .grapheme = icon, .width = 2 },
            .style = .{ .fg = .{ .index = 14 } },
        });
        col += 2;

        // Status
        surface.writeCell(col, start_row, .{
            .char = .{ .grapheme = status_char, .width = 1 },
            .style = .{ .fg = status_color },
        });
        col += 2;

        // Tool name
        for (tc.name) |char| {
            if (col >= width) break;
            surface.writeCell(col, start_row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
            col += 1;
        }

        // Duration if completed
        if (tc.duration_ms()) |ms| {
            const duration_str = formatDuration(ms);
            col += 1;
            surface.writeCell(col, start_row, .{
                .char = .{ .grapheme = "(", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
            col += 1;
            for (duration_str) |char| {
                if (col >= width) break;
                surface.writeCell(col, start_row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
                col += 1;
            }
            surface.writeCell(col, start_row, .{
                .char = .{ .grapheme = ")", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Result preview if available
        if (tc.result) |result| {
            const preview = truncate(result.output, @intCast(width - 4));
            const result_style = vaxis.Cell.Style{
                .fg = if (result.is_error) .{ .index = 9 } else .{ .index = 8 },
                .dim = true,
            };

            col = 4;
            for (preview) |char| {
                if (col >= width) break;
                surface.writeCell(col, start_row + 1, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = result_style,
                });
                col += 1;
            }
        }
    }

    fn formatDuration(ms: u64) []const u8 {
        // Simple formatting - in real impl use proper buffer
        if (ms < 1000) return "< 1s";
        if (ms < 60000) return "< 1m";
        return "> 1m";
    }

    fn truncate(text: []const u8, max_len: usize) []const u8 {
        if (text.len <= max_len) return text;
        return text[0..@min(max_len, text.len)];
    }
};

pub const StreamingCell = struct {
    text_buffer: []const u8,
    cursor_visible: bool = true,

    const CURSOR = "▋";

    pub fn height(self: StreamingCell, width: u16) u16 {
        return wrapHeight(self.text_buffer, width -| 2) + 1;
    }

    pub fn draw(self: *StreamingCell, surface: *vxfw.Surface, start_row: u16, width: u16) void {
        // Draw prefix
        surface.writeCell(0, start_row, .{
            .char = .{ .grapheme = "⏺", .width = 1 },
            .style = .{ .fg = .{ .index = 10 } },
        });
        surface.writeCell(1, start_row, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = .{},
        });

        // Draw text
        const text_height = drawWrappedText(
            surface,
            self.text_buffer,
            start_row,
            2,
            width,
            .{ .fg = .{ .index = 7 } },
        );

        // Draw cursor at end
        if (self.cursor_visible) {
            const last_row = start_row + text_height - 1;
            const last_col = lastColumnOf(self.text_buffer, width -| 2) + 2;
            if (last_col < width) {
                surface.writeCell(last_col, last_row, .{
                    .char = .{ .grapheme = CURSOR, .width = 1 },
                    .style = .{ .fg = .{ .index = 10 } },
                });
            }
        }
    }

    fn lastColumnOf(text: []const u8, line_width: u16) u16 {
        // Find position in last line
        var col: u16 = 0;
        for (text) |char| {
            if (char == '\n') {
                col = 0;
            } else {
                col += 1;
                if (col >= line_width) col = 0;
            }
        }
        return col;
    }
};

pub const SystemMessageCell = struct {
    content: []const u8,

    const STYLE = vaxis.Cell.Style{ .fg = .{ .index = 11 }, .italic = true }; // Yellow

    pub fn height(self: SystemMessageCell, width: u16) u16 {
        return wrapHeight(self.content, width -| 2);
    }

    pub fn draw(self: *SystemMessageCell, surface: *vxfw.Surface, start_row: u16, width: u16) void {
        surface.writeCell(0, start_row, .{
            .char = .{ .grapheme = "*", .width = 1 },
            .style = STYLE,
        });
        surface.writeCell(1, start_row, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = STYLE,
        });
        drawWrappedText(surface, self.content, start_row, 2, width, STYLE);
    }
};

pub const SeparatorCell = struct {
    const STYLE = vaxis.Cell.Style{ .fg = .{ .index = 8 } };

    pub fn draw(_: *SeparatorCell, surface: *vxfw.Surface, row: u16, width: u16) void {
        for (0..width) |col| {
            surface.writeCell(@intCast(col), row, .{
                .char = .{ .grapheme = "─", .width = 1 },
                .style = STYLE,
            });
        }
    }
};

// Helper functions
fn wrapHeight(text: []const u8, line_width: u16) u16 {
    if (line_width == 0) return 1;
    var lines: u16 = 1;
    var col: u16 = 0;

    for (text) |char| {
        if (char == '\n') {
            lines += 1;
            col = 0;
        } else {
            col += 1;
            if (col >= line_width) {
                lines += 1;
                col = 0;
            }
        }
    }
    return lines;
}

fn drawWrappedText(
    surface: *vxfw.Surface,
    text: []const u8,
    start_row: u16,
    start_col: u16,
    max_width: u16,
    style: vaxis.Cell.Style,
) u16 {
    var row = start_row;
    var col = start_col;
    const line_width = max_width -| start_col;

    for (text) |char| {
        if (char == '\n') {
            row += 1;
            col = start_col;
            continue;
        }

        if (col >= max_width) {
            row += 1;
            col = start_col;
        }

        surface.writeCell(col, row, .{
            .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
            .style = style,
        });
        col += 1;
    }

    return row - start_row + 1;
}
```

### 2. Create Chat History Widget (src/widgets/chat_history.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const cells = @import("cells.zig");
const HistoryCell = cells.HistoryCell;
const Conversation = @import("../state/conversation.zig").Conversation;
const Message = @import("../state/message.zig").Message;

pub const ChatHistory = struct {
    allocator: std.mem.Allocator,
    conversation: *Conversation,
    rendered_cells: std.ArrayList(HistoryCell),
    needs_rebuild: bool = true,

    pub fn init(allocator: std.mem.Allocator, conversation: *Conversation) ChatHistory {
        return .{
            .allocator = allocator,
            .conversation = conversation,
            .rendered_cells = std.ArrayList(HistoryCell).init(allocator),
        };
    }

    pub fn deinit(self: *ChatHistory) void {
        self.rendered_cells.deinit();
    }

    pub fn widget(self: *ChatHistory) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = ChatHistory.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *ChatHistory = @ptrCast(@alignCast(ptr));

        // Rebuild cells if needed
        if (self.needs_rebuild) {
            try self.rebuildCells();
            self.needs_rebuild = false;
        }

        const width = ctx.max.width orelse 80;

        // Calculate total height
        var total_height: u16 = 0;
        for (self.rendered_cells.items) |cell| {
            total_height += cell.height(width);
        }

        // Add streaming cell if active
        var streaming_cell: ?HistoryCell = null;
        if (self.conversation.getStreamingText()) |text| {
            streaming_cell = .{ .streaming = .{ .text_buffer = text } };
            total_height += streaming_cell.?.height(width);
        }

        // Create surface
        const height = ctx.max.height orelse total_height;
        const actual_height = @max(total_height, height);
        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), .{
            .width = width,
            .height = actual_height,
        });

        // Draw cells
        var row: u16 = 0;
        for (self.rendered_cells.items) |*cell| {
            cell.draw(&surface, row, width);
            row += cell.height(width);
        }

        // Draw streaming
        if (streaming_cell) |*cell| {
            cell.draw(&surface, row, width);
        }

        return surface;
    }

    fn rebuildCells(self: *ChatHistory) !void {
        self.rendered_cells.clearRetainingCapacity();

        for (self.conversation.messages.items) |msg| {
            switch (msg.role) {
                .user => {
                    try self.rendered_cells.append(.{ .user_message = .{
                        .content = switch (msg.content) {
                            .text => |t| t,
                            .parts => "[complex content]", // TODO: handle parts
                        },
                        .timestamp = msg.timestamp,
                    } });
                },
                .assistant => {
                    try self.rendered_cells.append(.{ .assistant_message = .{
                        .content = switch (msg.content) {
                            .text => |t| t,
                            .parts => "[complex content]",
                        },
                        .tool_calls = msg.tool_calls.items,
                        .timestamp = msg.timestamp,
                    } });
                },
                .system => {
                    try self.rendered_cells.append(.{ .system_message = .{
                        .content = switch (msg.content) {
                            .text => |t| t,
                            .parts => "[system]",
                        },
                    } });
                },
            }

            // Add separator between messages
            try self.rendered_cells.append(.{ .separator = .{} });
        }
    }

    pub fn markDirty(self: *ChatHistory) void {
        self.needs_rebuild = true;
    }

    pub fn getContentHeight(self: *ChatHistory, width: u16) u16 {
        var height: u16 = 0;
        for (self.rendered_cells.items) |cell| {
            height += cell.height(width);
        }
        if (self.conversation.getStreamingText()) |text| {
            height += cells.StreamingCell{ .text_buffer = text }.height(width);
        }
        return height;
    }
};
```

### 3. Create Empty State Widget (src/widgets/empty_state.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const EmptyState = struct {
    title: []const u8 = "Welcome to Plue",
    subtitle: []const u8 = "Type a message to start chatting",
    hints: []const Hint = &.{
        .{ .key = "/help", .description = "Show available commands" },
        .{ .key = "/model", .description = "Change the AI model" },
        .{ .key = "/new", .description = "Create a new session" },
    },

    pub const Hint = struct {
        key: []const u8,
        description: []const u8,
    };

    pub fn widget(self: *EmptyState) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = EmptyState.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *EmptyState = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Calculate vertical center
        const content_height: u16 = 2 + @as(u16, @intCast(self.hints.len)) + 2;
        const start_row = (size.height -| content_height) / 2;

        // Draw title
        const title_col = (size.width -| @as(u16, @intCast(self.title.len))) / 2;
        for (self.title, 0..) |char, i| {
            surface.writeCell(@intCast(title_col + i), start_row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // Draw subtitle
        const sub_col = (size.width -| @as(u16, @intCast(self.subtitle.len))) / 2;
        for (self.subtitle, 0..) |char, i| {
            surface.writeCell(@intCast(sub_col + i), start_row + 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Draw hints
        var row = start_row + 3;
        for (self.hints) |hint| {
            const hint_text = hint.key ++ " - " ++ hint.description;
            const hint_col = (size.width -| @as(u16, @intCast(hint_text.len))) / 2;

            // Key part
            var col = hint_col;
            for (hint.key) |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 12 }, .bold = true },
                });
                col += 1;
            }

            // Separator
            for (" - ") |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
                col += 1;
            }

            // Description
            for (hint.description) |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 7 } },
                });
                col += 1;
            }

            row += 1;
        }

        return surface;
    }
};
```

## Acceptance Criteria

- [ ] User messages display with blue prefix
- [ ] Assistant messages display with green prefix
- [ ] Tool calls show icon, name, status, duration
- [ ] Streaming text shows with animated cursor
- [ ] System messages display with yellow italic
- [ ] Text properly wraps at terminal width
- [ ] Content height calculated correctly for scrolling
- [ ] Empty state shows when no messages
- [ ] Separators between messages

## Files to Create

1. `tui-zig/src/widgets/cells.zig`
2. `tui-zig/src/widgets/chat_history.zig`
3. `tui-zig/src/widgets/empty_state.zig`

## Next

Proceed to `07_input_composer.md` to implement the input composer.
