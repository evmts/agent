# 07: Input Composer Widget

## Goal

Implement a multi-line input composer with cursor editing, history navigation, and slash command detection.

## Context

- Input area at the bottom of the screen
- Must support: multi-line editing, cursor movement, history, slash commands
- Reference: libvaxis `TextField` widget and codex input handling

## Features

- Multi-line text input
- Cursor movement (arrows, home, end)
- Backspace/delete
- History navigation (up/down arrows)
- Slash command highlighting
- File mention highlighting (@file)
- Placeholder text when empty

## Tasks

### 1. Create Composer Widget (src/widgets/composer.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const AppState = @import("../state/app_state.zig").AppState;

pub const Composer = struct {
    state: *AppState,
    focused: bool = true,
    placeholder: []const u8 = "Type a message...",

    const PROMPT = "> ";
    const PROMPT_STYLE = vaxis.Cell.Style{ .fg = .{ .index = 12 }, .bold = true };
    const TEXT_STYLE = vaxis.Cell.Style{ .fg = .{ .index = 7 } };
    const CURSOR_STYLE = vaxis.Cell.Style{ .reverse = true };
    const PLACEHOLDER_STYLE = vaxis.Cell.Style{ .fg = .{ .index = 8 }, .italic = true };
    const SLASH_STYLE = vaxis.Cell.Style{ .fg = .{ .index = 14 }, .bold = true };
    const MENTION_STYLE = vaxis.Cell.Style{ .fg = .{ .index = 13 } };

    pub fn widget(self: *Composer) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Composer.handleEvent,
            .drawFn = Composer.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *Composer = @ptrCast(@alignCast(ptr));

        if (!self.focused) return;

        switch (event) {
            .key_press => |key| {
                try self.handleKeyPress(ctx, key);
            },
            .focus_in => {
                self.focused = true;
                ctx.consumeAndRedraw();
            },
            .focus_out => {
                self.focused = false;
                ctx.consumeAndRedraw();
            },
            else => {},
        }
    }

    fn handleKeyPress(self: *Composer, ctx: *vxfw.EventContext, key: vaxis.Key) !void {
        // Navigation keys
        if (key.matches(vaxis.Key.left, .{})) {
            self.state.moveCursor(-1);
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches(vaxis.Key.right, .{})) {
            self.state.moveCursor(1);
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches(vaxis.Key.home, .{}) or key.matches('a', .{ .ctrl = true })) {
            self.state.input_cursor = 0;
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches(vaxis.Key.end, .{}) or key.matches('e', .{ .ctrl = true })) {
            self.state.input_cursor = self.state.input_buffer.items.len;
            ctx.consumeAndRedraw();
            return;
        }

        // History navigation
        if (key.matches(vaxis.Key.up, .{})) {
            self.state.navigateHistory(-1);
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches(vaxis.Key.down, .{})) {
            self.state.navigateHistory(1);
            ctx.consumeAndRedraw();
            return;
        }

        // Editing keys
        if (key.matches(vaxis.Key.backspace, .{})) {
            self.state.deleteBackward();
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches(vaxis.Key.delete, .{}) or key.matches('d', .{ .ctrl = true })) {
            self.state.deleteForward();
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches('w', .{ .ctrl = true })) {
            // Delete word backward
            self.deleteWordBackward();
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches('u', .{ .ctrl = true })) {
            // Delete to start of line
            self.deleteToStart();
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches('k', .{ .ctrl = true })) {
            // Delete to end of line
            self.deleteToEnd();
            ctx.consumeAndRedraw();
            return;
        }

        // Text input
        if (key.text) |text| {
            try self.state.insertText(text);
            ctx.consumeAndRedraw();
        }
    }

    fn deleteWordBackward(self: *Composer) void {
        const buf = self.state.input_buffer.items;
        var cursor = self.state.input_cursor;

        // Skip trailing spaces
        while (cursor > 0 and buf[cursor - 1] == ' ') {
            cursor -= 1;
            _ = self.state.input_buffer.orderedRemove(cursor);
        }

        // Delete until space or start
        while (cursor > 0 and buf[cursor - 1] != ' ') {
            cursor -= 1;
            _ = self.state.input_buffer.orderedRemove(cursor);
        }

        self.state.input_cursor = cursor;
    }

    fn deleteToStart(self: *Composer) void {
        while (self.state.input_cursor > 0) {
            self.state.input_cursor -= 1;
            _ = self.state.input_buffer.orderedRemove(self.state.input_cursor);
        }
    }

    fn deleteToEnd(self: *Composer) void {
        while (self.state.input_cursor < self.state.input_buffer.items.len) {
            _ = self.state.input_buffer.orderedRemove(self.state.input_cursor);
        }
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *Composer = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Draw separator line at top
        for (0..size.width) |col| {
            surface.writeCell(@intCast(col), 0, .{
                .char = .{ .grapheme = "─", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Draw prompt
        const start_row: u16 = 1;
        for (PROMPT, 0..) |char, i| {
            surface.writeCell(@intCast(i), start_row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = PROMPT_STYLE,
            });
        }

        const text_start: u16 = @intCast(PROMPT.len);
        const text_width = size.width -| text_start;
        const input = self.state.input_buffer.items;

        if (input.len == 0) {
            // Draw placeholder
            for (self.placeholder, 0..) |char, i| {
                if (text_start + i >= size.width) break;
                surface.writeCell(@intCast(text_start + i), start_row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = PLACEHOLDER_STYLE,
                });
            }

            // Draw cursor at start
            if (self.focused) {
                surface.writeCell(text_start, start_row, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = CURSOR_STYLE,
                });
            }
        } else {
            // Detect special content
            const is_slash_cmd = input.len > 0 and input[0] == '/';

            // Draw text with syntax highlighting
            var col = text_start;
            var row = start_row;

            for (input, 0..) |char, i| {
                // Handle wrapping
                if (col >= size.width) {
                    row += 1;
                    col = text_start;
                    if (row >= size.height) break;
                }

                // Determine style
                const style = blk: {
                    if (is_slash_cmd and i < self.getSlashCmdEnd(input)) {
                        break :blk SLASH_STYLE;
                    }
                    if (self.isInMention(input, i)) {
                        break :blk MENTION_STYLE;
                    }
                    break :blk TEXT_STYLE;
                };

                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = style,
                });
                col += 1;
            }

            // Draw cursor
            if (self.focused) {
                const cursor_pos = self.state.input_cursor;
                const cursor_row = start_row + @as(u16, @intCast(cursor_pos / text_width));
                const cursor_col = text_start + @as(u16, @intCast(cursor_pos % text_width));

                if (cursor_row < size.height) {
                    const cursor_char = if (cursor_pos < input.len)
                        &[_]u8{input[cursor_pos]}
                    else
                        " ";

                    surface.writeCell(cursor_col, cursor_row, .{
                        .char = .{ .grapheme = cursor_char, .width = 1 },
                        .style = CURSOR_STYLE,
                    });
                }
            }
        }

        // Draw keyboard hints at bottom
        if (size.height > 2) {
            const hints = self.getContextHints();
            var hint_col: u16 = 0;
            const hint_row = size.height - 1;

            for (hints) |hint| {
                if (hint_col >= size.width) break;

                // Key
                for (hint.key) |char| {
                    if (hint_col >= size.width) break;
                    surface.writeCell(hint_col, hint_row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = .{ .fg = .{ .index = 8 }, .bold = true },
                    });
                    hint_col += 1;
                }

                // Description
                for (hint.desc) |char| {
                    if (hint_col >= size.width) break;
                    surface.writeCell(hint_col, hint_row, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = .{ .fg = .{ .index = 8 } },
                    });
                    hint_col += 1;
                }

                hint_col += 2; // Spacing between hints
            }
        }

        return surface;
    }

    fn getSlashCmdEnd(self: *Composer, input: []const u8) usize {
        _ = self;
        if (input.len == 0 or input[0] != '/') return 0;

        for (input, 0..) |char, i| {
            if (char == ' ') return i;
        }
        return input.len;
    }

    fn isInMention(self: *Composer, input: []const u8, pos: usize) bool {
        _ = self;
        // Simple @mention detection
        var start: ?usize = null;

        for (input[0..pos + 1], 0..) |char, i| {
            if (char == '@') {
                start = i;
            } else if (char == ' ' or char == '\n') {
                start = null;
            }
        }

        return start != null;
    }

    const KeyHint = struct {
        key: []const u8,
        desc: []const u8,
    };

    fn getContextHints(self: *Composer) []const KeyHint {
        if (self.state.isStreaming()) {
            return &.{
                .{ .key = "Ctrl+C", .desc = " abort" },
            };
        }

        const input = self.state.input_buffer.items;
        if (input.len > 0 and input[0] == '/') {
            return &.{
                .{ .key = "Enter", .desc = " run command" },
                .{ .key = "Tab", .desc = " autocomplete" },
            };
        }

        return &.{
            .{ .key = "Enter", .desc = " send" },
            .{ .key = "/", .desc = " commands" },
            .{ .key = "@", .desc = " mention file" },
        };
    }

    pub fn clear(self: *Composer) void {
        self.state.clearInput();
    }

    pub fn getText(self: *Composer) []const u8 {
        return self.state.getInput();
    }

    pub fn isEmpty(self: *Composer) bool {
        return self.state.input_buffer.items.len == 0;
    }
};
```

### 2. Create Autocomplete Popup (src/widgets/autocomplete.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const Autocomplete = struct {
    suggestions: []const Suggestion,
    selected_index: usize = 0,
    visible: bool = false,
    anchor_col: u16 = 0,
    anchor_row: u16 = 0,

    pub const Suggestion = struct {
        label: []const u8,
        value: []const u8,
        description: ?[]const u8 = null,
        kind: Kind = .text,

        pub const Kind = enum {
            command,
            file,
            skill,
            model,
            text,
        };
    };

    pub fn widget(self: *Autocomplete) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Autocomplete.handleEvent,
            .drawFn = Autocomplete.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *Autocomplete = @ptrCast(@alignCast(ptr));

        if (!self.visible) return;

        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.up, .{})) {
                    if (self.selected_index > 0) {
                        self.selected_index -= 1;
                    } else {
                        self.selected_index = self.suggestions.len - 1;
                    }
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.down, .{})) {
                    self.selected_index = (self.selected_index + 1) % self.suggestions.len;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.tab, .{}) or key.matches(vaxis.Key.enter, .{})) {
                    // Accept suggestion
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.escape, .{})) {
                    self.visible = false;
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *Autocomplete = @ptrCast(@alignCast(ptr));

        if (!self.visible or self.suggestions.len == 0) {
            return try vxfw.Surface.init(ctx.arena, self.widget(), .{ .width = 0, .height = 0 });
        }

        // Calculate popup size
        var max_width: u16 = 0;
        for (self.suggestions) |s| {
            const width = @as(u16, @intCast(s.label.len + 4));
            if (width > max_width) max_width = width;
        }
        max_width = @min(max_width, 50);
        const height: u16 = @min(@as(u16, @intCast(self.suggestions.len)), 8);

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), .{
            .width = max_width,
            .height = height,
        });

        // Draw suggestions
        for (self.suggestions, 0..) |suggestion, i| {
            if (i >= height) break;

            const is_selected = i == self.selected_index;
            const style = if (is_selected)
                vaxis.Cell.Style{ .fg = .{ .index = 0 }, .bg = .{ .index = 14 } }
            else
                vaxis.Cell.Style{ .fg = .{ .index = 7 }, .bg = .{ .index = 0 } };

            // Draw icon based on kind
            const icon: []const u8 = switch (suggestion.kind) {
                .command => "/",
                .file => "📄",
                .skill => "⚡",
                .model => "🤖",
                .text => " ",
            };

            surface.writeCell(0, @intCast(i), .{
                .char = .{ .grapheme = icon, .width = if (suggestion.kind == .file or suggestion.kind == .skill or suggestion.kind == .model) 2 else 1 },
                .style = style,
            });

            // Draw label
            const start_col: u16 = if (suggestion.kind == .command) 1 else 2;
            for (suggestion.label, 0..) |char, j| {
                if (start_col + j >= max_width) break;
                surface.writeCell(@intCast(start_col + j), @intCast(i), .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = style,
                });
            }

            // Fill rest of line
            var col = start_col + @as(u16, @intCast(suggestion.label.len));
            while (col < max_width) : (col += 1) {
                surface.writeCell(col, @intCast(i), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = style,
                });
            }
        }

        return surface;
    }

    pub fn show(self: *Autocomplete, suggestions: []const Suggestion, anchor_col: u16, anchor_row: u16) void {
        self.suggestions = suggestions;
        self.selected_index = 0;
        self.anchor_col = anchor_col;
        self.anchor_row = anchor_row;
        self.visible = true;
    }

    pub fn hide(self: *Autocomplete) void {
        self.visible = false;
    }

    pub fn getSelected(self: *Autocomplete) ?Suggestion {
        if (!self.visible or self.suggestions.len == 0) return null;
        return self.suggestions[self.selected_index];
    }
};
```

## Acceptance Criteria

- [ ] Text input with cursor positioning
- [ ] Arrow key navigation (left, right)
- [ ] Home/End (or Ctrl+A/E) for line navigation
- [ ] Backspace and delete work correctly
- [ ] Ctrl+W deletes word backward
- [ ] Ctrl+U deletes to start of line
- [ ] Ctrl+K deletes to end of line
- [ ] Up/Down navigates input history
- [ ] Slash commands highlighted in cyan
- [ ] @mentions highlighted in magenta
- [ ] Placeholder text when empty
- [ ] Cursor visible and positioned correctly
- [ ] Keyboard hints shown at bottom
- [ ] Autocomplete popup shows suggestions

## Files to Create

1. `tui-zig/src/widgets/composer.zig`
2. `tui-zig/src/widgets/autocomplete.zig`

## Next

Proceed to `08_status_widgets.md` to implement header and status bar.
