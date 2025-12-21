const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Message = @import("../state/message.zig").Message;
const ToolCall = @import("../state/message.zig").ToolCall;
const wrap = @import("../utils/wrap.zig");

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
        const available_width = width -| @as(u16, @intCast(PREFIX.len));
        return wrap.wrapHeight(self.content, available_width);
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
    const PREFIX_WIDTH: u16 = 2;
    const PREFIX_STYLE = vaxis.Cell.Style{ .fg = .{ .index = 10 }, .bold = true }; // Green

    pub fn height(self: AssistantMessageCell, width: u16) u16 {
        var h = wrap.wrapHeight(self.content, width -| PREFIX_WIDTH);
        for (self.tool_calls) |tc| {
            h += ToolCallCell.heightFor(tc, width);
        }
        return h;
    }

    pub fn draw(self: *AssistantMessageCell, surface: *vxfw.Surface, start_row: u16, width: u16) void {
        // Draw prefix (emoji + space)
        surface.writeCell(0, start_row, .{
            .char = .{ .grapheme = "⏺", .width = 1 },
            .style = PREFIX_STYLE,
        });
        surface.writeCell(1, start_row, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = PREFIX_STYLE,
        });

        // Draw content
        var row = start_row;
        const content_height = drawWrappedText(surface, self.content, row, PREFIX_WIDTH, width, .{ .fg = .{ .index = 7 } });
        row += content_height;

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

    const ICONS = std.StaticStringMap([]const u8).initComptime(.{
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
            .pending => "⏳",
            .running => "▶",
            .completed => "✓",
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

        // Draw: [indent] [icon] [status] tool_name (duration)
        var col: u16 = 2;

        // Icon (emojis are width 2)
        surface.writeCell(col, start_row, .{
            .char = .{ .grapheme = icon, .width = 2 },
            .style = .{ .fg = .{ .index = 14 } },
        });
        col += 2;

        // Space
        surface.writeCell(col, start_row, .{
            .char = .{ .grapheme = " ", .width = 1 },
            .style = .{},
        });
        col += 1;

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
            var duration_buf: [32]u8 = undefined;
            const duration_str = formatDuration(&duration_buf, ms);

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
            if (col < width) {
                surface.writeCell(col, start_row, .{
                    .char = .{ .grapheme = ")", .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
            }
        }

        // Result preview if available
        if (tc.result) |result| {
            const max_preview_len = if (width > 4) width - 4 else 0;
            const preview = truncate(result.output, max_preview_len);
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

    fn formatDuration(buf: []u8, ms: u64) []const u8 {
        if (ms < 1000) {
            return std.fmt.bufPrint(buf, "{d}ms", .{ms}) catch "?ms";
        }
        const seconds = ms / 1000;
        if (seconds < 60) {
            return std.fmt.bufPrint(buf, "{d}s", .{seconds}) catch "?s";
        }
        const minutes = seconds / 60;
        const remainder_seconds = seconds % 60;
        return std.fmt.bufPrint(buf, "{d}m{d}s", .{ minutes, remainder_seconds }) catch "?m";
    }

    fn truncate(text: []const u8, max_len: u16) []const u8 {
        if (text.len <= max_len) return text;
        return text[0..@min(max_len, text.len)];
    }
};

pub const StreamingCell = struct {
    text_buffer: []const u8,
    cursor_visible: bool = true,

    const CURSOR = "▋";

    pub fn height(self: StreamingCell, width: u16) u16 {
        return wrap.wrapHeight(self.text_buffer, width -| 2) + 1;
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
            const last_row = start_row + text_height -| 1;
            const last_col = wrap.lastColumnOf(self.text_buffer, width -| 2) + 2;
            if (last_col < width) {
                surface.writeCell(last_col, last_row, .{
                    .char = .{ .grapheme = CURSOR, .width = 1 },
                    .style = .{ .fg = .{ .index = 10 } },
                });
            }
        }
    }
};

pub const SystemMessageCell = struct {
    content: []const u8,

    const STYLE = vaxis.Cell.Style{ .fg = .{ .index = 11 }, .italic = true }; // Yellow

    pub fn height(self: SystemMessageCell, width: u16) u16 {
        return wrap.wrapHeight(self.content, width -| 2);
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
        _ = drawWrappedText(surface, self.content, start_row, 2, width, STYLE);
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

/// Draw wrapped text and return the number of rows used
fn drawWrappedText(
    surface: *vxfw.Surface,
    text: []const u8,
    start_row: u16,
    start_col: u16,
    max_width: u16,
    style: vaxis.Cell.Style,
) u16 {
    if (text.len == 0) return 0;

    var row = start_row;
    var col = start_col;
    const line_width = max_width -| start_col;

    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];

        if (c == '\n') {
            row += 1;
            col = start_col;
            i += 1;
            continue;
        }

        // Get character length
        const char_len = utf8CharLen(c) catch 1;
        const grapheme_width = if (c < 128) 1 else 2;

        // Wrap if needed
        if (col + grapheme_width > max_width) {
            row += 1;
            col = start_col;
        }

        // Draw character
        const char_slice = text[i .. i + char_len];
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = char_slice, .width = @intCast(grapheme_width) },
            .style = style,
        });

        col += grapheme_width;
        i += char_len;
    }

    return row - start_row + 1;
}

fn utf8CharLen(first_byte: u8) !usize {
    if (first_byte < 0x80) return 1;
    if ((first_byte & 0xE0) == 0xC0) return 2;
    if ((first_byte & 0xF0) == 0xE0) return 3;
    if ((first_byte & 0xF8) == 0xF0) return 4;
    return error.InvalidUtf8;
}
