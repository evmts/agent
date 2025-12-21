# 14: Session Management UI

## Goal

Implement session list, session picker, and session switching UI components.

## Context

- Users can have multiple sessions
- Need UI to: list sessions, create new, switch between, view details
- Reference: `/Users/williamcory/plue/tui/src/index.ts` session handling

## Tasks

### 1. Create Session List Widget (src/widgets/session_list.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Session = @import("../state/session_manager.zig").Session;
const SessionManager = @import("../state/session_manager.zig").SessionManager;

pub const SessionList = struct {
    allocator: std.mem.Allocator,
    session_manager: *SessionManager,
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    on_select: ?*const fn (*Session) void = null,
    on_new: ?*const fn () void = null,
    show_create_option: bool = true,

    pub fn widget(self: *SessionList) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = SessionList.handleEvent,
            .drawFn = SessionList.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *SessionList = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                const total_items = self.getTotalItems();

                if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) {
                    if (self.selected_index > 0) {
                        self.selected_index -= 1;
                        self.ensureVisible();
                    }
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) {
                    if (self.selected_index < total_items - 1) {
                        self.selected_index += 1;
                        self.ensureVisible();
                    }
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    self.selectCurrent();
                    ctx.consumeAndRedraw();
                } else if (key.matches('n', .{})) {
                    if (self.on_new) |cb| cb();
                    ctx.consumeAndRedraw();
                }
            },
            .mouse => |mouse| {
                if (mouse.type == .press and mouse.button == .left) {
                    const clicked_index = self.scroll_offset + @as(usize, @intCast(mouse.row));
                    if (clicked_index < self.getTotalItems()) {
                        self.selected_index = clicked_index;
                        self.selectCurrent();
                    }
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *SessionList = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Title
        const title = "Sessions";
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(i + 1), 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // Separator
        for (0..size.width) |col| {
            surface.writeCell(@intCast(col), 1, .{
                .char = .{ .grapheme = "─", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Sessions
        var row: u16 = 2;
        const visible_rows = size.height -| 4;
        var idx = self.scroll_offset;

        // New session option
        if (self.show_create_option and idx == 0) {
            const is_selected = self.selected_index == 0;
            self.drawItem(&surface, row, size.width, is_selected, .{
                .icon = "+",
                .title = "New Session",
                .subtitle = "Start a fresh conversation",
                .is_new = true,
            });
            row += 2;
            idx += 1;
        }

        // Existing sessions
        const sessions = self.session_manager.sessions.items;
        while (row < visible_rows + 2 and idx - 1 < sessions.len) {
            const session = &sessions[idx - 1];
            const is_selected = self.selected_index == idx;
            const is_current = if (self.session_manager.current_session) |cs|
                std.mem.eql(u8, cs.id, session.id)
            else
                false;

            self.drawItem(&surface, row, size.width, is_selected, .{
                .icon = if (is_current) "●" else "○",
                .title = session.title orelse session.id,
                .subtitle = self.formatSessionMeta(session, ctx.arena),
                .is_new = false,
            });

            row += 2;
            idx += 1;
        }

        // Scroll indicators
        if (self.scroll_offset > 0) {
            surface.writeCell(size.width - 1, 2, .{
                .char = .{ .grapheme = "▲", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }
        if (idx < self.getTotalItems()) {
            surface.writeCell(size.width - 1, size.height - 2, .{
                .char = .{ .grapheme = "▼", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Hints
        const hints = "↑↓ navigate  Enter select  n new";
        for (hints, 0..) |char, i| {
            if (i >= size.width) break;
            surface.writeCell(@intCast(i), size.height - 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        return surface;
    }

    const ItemDisplay = struct {
        icon: []const u8,
        title: []const u8,
        subtitle: []const u8,
        is_new: bool,
    };

    fn drawItem(self: *SessionList, surface: *vxfw.Surface, row: u16, width: u16, is_selected: bool, item: ItemDisplay) void {
        _ = self;

        const bg_style: vaxis.Cell.Style = if (is_selected)
            .{ .bg = .{ .index = 8 } }
        else
            .{};

        // Fill background if selected
        if (is_selected) {
            for (0..width) |col| {
                surface.writeCell(@intCast(col), row, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = bg_style,
                });
                surface.writeCell(@intCast(col), row + 1, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = bg_style,
                });
            }
        }

        var col: u16 = 1;

        // Icon
        const icon_color: vaxis.Color = if (item.is_new)
            .{ .index = 10 }
        else
            .{ .index = 14 };
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = item.icon, .width = 1 },
            .style = .{ .fg = icon_color, .bg = bg_style.bg },
        });
        col += 2;

        // Title
        for (item.title) |char| {
            if (col >= width - 2) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 15 }, .bold = is_selected, .bg = bg_style.bg },
            });
            col += 1;
        }

        // Subtitle
        col = 3;
        for (item.subtitle) |char| {
            if (col >= width - 2) break;
            surface.writeCell(col, row + 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 }, .bg = bg_style.bg },
            });
            col += 1;
        }
    }

    fn formatSessionMeta(self: *SessionList, session: *const Session, allocator: std.mem.Allocator) []const u8 {
        _ = self;
        const model_short = getShortModelName(session.model);
        const effort = session.reasoning_effort.toString();
        return std.fmt.allocPrint(allocator, "{s} • {s}", .{ model_short, effort }) catch "...";
    }

    fn getShortModelName(model: []const u8) []const u8 {
        if (std.mem.indexOf(u8, model, "sonnet-4")) |_| return "sonnet-4";
        if (std.mem.indexOf(u8, model, "opus-4")) |_| return "opus-4";
        if (std.mem.indexOf(u8, model, "sonnet")) |_| return "sonnet";
        if (std.mem.indexOf(u8, model, "haiku")) |_| return "haiku";
        return model;
    }

    fn getTotalItems(self: *SessionList) usize {
        const session_count = self.session_manager.sessions.items.len;
        return if (self.show_create_option) session_count + 1 else session_count;
    }

    fn ensureVisible(self: *SessionList) void {
        // Simple visibility check - adjust scroll if needed
        const visible_rows = 10; // Approximate
        if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        } else if (self.selected_index >= self.scroll_offset + visible_rows) {
            self.scroll_offset = self.selected_index - visible_rows + 1;
        }
    }

    fn selectCurrent(self: *SessionList) void {
        if (self.show_create_option and self.selected_index == 0) {
            if (self.on_new) |cb| cb();
        } else {
            const idx = if (self.show_create_option) self.selected_index - 1 else self.selected_index;
            if (idx < self.session_manager.sessions.items.len) {
                if (self.on_select) |cb| {
                    cb(&self.session_manager.sessions.items[idx]);
                }
            }
        }
    }
};
```

### 2. Create Model Picker (src/widgets/model_picker.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const ModelPicker = struct {
    allocator: std.mem.Allocator,
    models: []const Model,
    selected_index: usize = 0,
    current_model: ?[]const u8 = null,
    on_select: ?*const fn ([]const u8) void = null,

    pub const Model = struct {
        id: []const u8,
        name: []const u8,
        description: []const u8,
    };

    pub const DEFAULT_MODELS = [_]Model{
        .{
            .id = "claude-sonnet-4-20250514",
            .name = "Claude Sonnet 4",
            .description = "Fast and capable, best for most tasks",
        },
        .{
            .id = "claude-opus-4-20250514",
            .name = "Claude Opus 4",
            .description = "Most powerful, best for complex reasoning",
        },
        .{
            .id = "claude-3-5-sonnet-20241022",
            .name = "Claude 3.5 Sonnet",
            .description = "Previous generation, very capable",
        },
        .{
            .id = "claude-3-5-haiku-20241022",
            .name = "Claude 3.5 Haiku",
            .description = "Fastest, best for quick tasks",
        },
    };

    pub fn init(allocator: std.mem.Allocator) ModelPicker {
        return .{
            .allocator = allocator,
            .models = &DEFAULT_MODELS,
        };
    }

    pub fn widget(self: *ModelPicker) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = ModelPicker.handleEvent,
            .drawFn = ModelPicker.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *ModelPicker = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.up, .{})) {
                    if (self.selected_index > 0) self.selected_index -= 1;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.down, .{})) {
                    if (self.selected_index < self.models.len - 1) self.selected_index += 1;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    if (self.on_select) |cb| {
                        cb(self.models[self.selected_index].id);
                    }
                    ctx.consumeAndRedraw();
                } else if (key.matches('1', .{})) {
                    self.selectByIndex(0);
                    ctx.consumeAndRedraw();
                } else if (key.matches('2', .{})) {
                    self.selectByIndex(1);
                    ctx.consumeAndRedraw();
                } else if (key.matches('3', .{})) {
                    self.selectByIndex(2);
                    ctx.consumeAndRedraw();
                } else if (key.matches('4', .{})) {
                    self.selectByIndex(3);
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn selectByIndex(self: *ModelPicker, idx: usize) void {
        if (idx < self.models.len) {
            self.selected_index = idx;
            if (self.on_select) |cb| {
                cb(self.models[idx].id);
            }
        }
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *ModelPicker = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Title
        const title = "Select Model";
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(i + 1), 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // Models
        var row: u16 = 2;
        for (self.models, 0..) |model, i| {
            const is_selected = i == self.selected_index;
            const is_current = if (self.current_model) |cm|
                std.mem.eql(u8, cm, model.id)
            else
                false;

            // Background for selected
            if (is_selected) {
                for (0..size.width) |col| {
                    surface.writeCell(@intCast(col), row, .{
                        .char = .{ .grapheme = " ", .width = 1 },
                        .style = .{ .bg = .{ .index = 8 } },
                    });
                    surface.writeCell(@intCast(col), row + 1, .{
                        .char = .{ .grapheme = " ", .width = 1 },
                        .style = .{ .bg = .{ .index = 8 } },
                    });
                }
            }

            var col: u16 = 1;

            // Number shortcut
            const num = std.fmt.allocPrint(ctx.arena, "{d}.", .{i + 1}) catch "";
            for (num) |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 14 }, .bg = if (is_selected) .{ .index = 8 } else .default },
                });
                col += 1;
            }
            col += 1;

            // Current indicator
            const indicator = if (is_current) "●" else "○";
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = indicator, .width = 1 },
                .style = .{ .fg = if (is_current) .{ .index = 10 } else .{ .index = 8 }, .bg = if (is_selected) .{ .index = 8 } else .default },
            });
            col += 2;

            // Model name
            for (model.name) |char| {
                if (col >= size.width - 2) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 15 }, .bold = is_selected, .bg = if (is_selected) .{ .index = 8 } else .default },
                });
                col += 1;
            }

            // Description
            col = 6;
            for (model.description) |char| {
                if (col >= size.width - 2) break;
                surface.writeCell(col, row + 1, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 }, .bg = if (is_selected) .{ .index = 8 } else .default },
                });
                col += 1;
            }

            row += 3;
        }

        // Hints
        const hints = "1-4 quick select  ↑↓ navigate  Enter confirm";
        for (hints, 0..) |char, i| {
            if (i >= size.width) break;
            surface.writeCell(@intCast(i), size.height - 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        return surface;
    }
};
```

### 3. Create Reasoning Effort Picker (src/widgets/effort_picker.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const ReasoningEffort = @import("../state/session_manager.zig").Session.ReasoningEffort;

pub const EffortPicker = struct {
    selected_index: usize = 2, // Default to medium
    current_effort: ?ReasoningEffort = null,
    on_select: ?*const fn (ReasoningEffort) void = null,

    const EFFORTS = [_]struct {
        value: ReasoningEffort,
        name: []const u8,
        description: []const u8,
    }{
        .{ .value = .minimal, .name = "Minimal", .description = "Fastest responses, minimal thinking" },
        .{ .value = .low, .name = "Low", .description = "Quick responses with light reasoning" },
        .{ .value = .medium, .name = "Medium", .description = "Balanced speed and thoroughness" },
        .{ .value = .high, .name = "High", .description = "Thorough reasoning, slower responses" },
    };

    pub fn widget(self: *EffortPicker) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = EffortPicker.handleEvent,
            .drawFn = EffortPicker.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *EffortPicker = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.up, .{}) or key.matches(vaxis.Key.left, .{})) {
                    if (self.selected_index > 0) self.selected_index -= 1;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.down, .{}) or key.matches(vaxis.Key.right, .{})) {
                    if (self.selected_index < EFFORTS.len - 1) self.selected_index += 1;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    if (self.on_select) |cb| {
                        cb(EFFORTS[self.selected_index].value);
                    }
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *EffortPicker = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Title
        const title = "Reasoning Effort";
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(i + 1), 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // Slider visualization
        const slider_row: u16 = 2;
        const slider_width = size.width -| 4;
        const segment_width = slider_width / @as(u16, @intCast(EFFORTS.len));

        // Draw track
        for (0..slider_width) |col| {
            surface.writeCell(@intCast(col + 2), slider_row, .{
                .char = .{ .grapheme = "─", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Draw segments and labels
        for (EFFORTS, 0..) |effort, i| {
            const x = 2 + @as(u16, @intCast(i)) * segment_width;
            const is_selected = i == self.selected_index;
            const is_current = if (self.current_effort) |ce| ce == effort.value else false;

            // Marker
            const marker = if (is_selected) "●" else "○";
            surface.writeCell(x, slider_row, .{
                .char = .{ .grapheme = marker, .width = 1 },
                .style = .{ .fg = if (is_selected) .{ .index = 14 } else if (is_current) .{ .index = 10 } else .{ .index = 8 } },
            });

            // Label
            const label_x = x -| @as(u16, @intCast(effort.name.len / 2));
            for (effort.name, 0..) |char, j| {
                if (label_x + j >= size.width - 2) break;
                surface.writeCell(@intCast(label_x + j), slider_row + 1, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = if (is_selected) .{ .index = 15 } else .{ .index = 7 } },
                });
            }
        }

        // Selected description
        const desc = EFFORTS[self.selected_index].description;
        const desc_row = slider_row + 3;
        for (desc, 0..) |char, i| {
            if (i >= size.width - 4) break;
            surface.writeCell(@intCast(i + 2), desc_row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        return surface;
    }
};
```

## Acceptance Criteria

- [ ] Session list shows all sessions with metadata
- [ ] New session option at top of list
- [ ] Current session marked with filled circle
- [ ] Arrow key navigation works
- [ ] Enter selects session
- [ ] 'n' creates new session
- [ ] Model picker shows all models with descriptions
- [ ] Number shortcuts (1-4) for quick selection
- [ ] Current model marked
- [ ] Effort picker shows slider-style UI
- [ ] Effort descriptions shown

## Files to Create

1. `tui-zig/src/widgets/session_list.zig`
2. `tui-zig/src/widgets/model_picker.zig`
3. `tui-zig/src/widgets/effort_picker.zig`

## Next

Proceed to `15_slash_commands.md` for command handling.
