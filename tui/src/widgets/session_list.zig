const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Session = @import("../state/session.zig").Session;

/// Widget for displaying and selecting sessions
pub const SessionList = struct {
    allocator: std.mem.Allocator,
    sessions: []const Session,
    current_session_id: ?[]const u8 = null,
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    on_select: ?*const fn ([]const u8) void = null,
    on_new: ?*const fn () void = null,
    show_create_option: bool = true,

    pub fn init(allocator: std.mem.Allocator) SessionList {
        return .{
            .allocator = allocator,
            .sessions = &.{},
        };
    }

    pub fn widget(self: *SessionList) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = SessionList.handleEvent,
            .drawFn = SessionList.draw,
        };
    }

    fn handleEvent(userdata: ?*anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) void {
        const self: *SessionList = @ptrCast(@alignCast(userdata orelse return));

        switch (event) {
            .key_press => |key| {
                const total_items = self.getTotalItems();

                if (key.codepoint == vaxis.Key.up or key.codepoint == 'k') {
                    if (self.selected_index > 0) {
                        self.selected_index -= 1;
                        self.ensureVisible(10);
                    }
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.down or key.codepoint == 'j') {
                    if (self.selected_index < total_items -| 1) {
                        self.selected_index += 1;
                        self.ensureVisible(10);
                    }
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.enter) {
                    self.selectCurrent();
                    ctx.request_redraw = true;
                } else if (key.codepoint == 'n') {
                    if (self.on_new) |cb| cb();
                    ctx.request_redraw = true;
                }
            },
            .mouse => |mouse| {
                if (mouse.type == .press and mouse.button == .left) {
                    const clicked_index = self.scroll_offset + @as(usize, @intCast(mouse.row / 2));
                    if (clicked_index < self.getTotalItems()) {
                        self.selected_index = clicked_index;
                        self.selectCurrent();
                    }
                    ctx.request_redraw = true;
                }
            },
            else => {},
        }
    }

    fn draw(userdata: ?*anyopaque, ctx: vxfw.DrawContext) vxfw.DrawResult {
        const self: *SessionList = @ptrCast(@alignCast(userdata orelse return .{ .surface = null }));
        const width: u31 = @intCast(ctx.max.width orelse 40);
        const height: u31 = @intCast(ctx.max.height orelse 20);

        var surface = vxfw.Surface.init(ctx.arena, self.widget(), width, height) catch return .{ .surface = null };

        // Title
        const title = "Sessions";
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(i + 1), 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // Separator
        for (0..width) |col| {
            surface.writeCell(@intCast(col), 1, .{
                .char = .{ .grapheme = "-", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Sessions
        var row: u16 = 2;
        const visible_rows = (height -| 4) / 2;
        var idx: usize = self.scroll_offset;

        // New session option
        if (self.show_create_option and idx == 0) {
            const is_selected = self.selected_index == 0;
            self.drawItem(&surface, row, @intCast(width), is_selected, .{
                .icon = "+",
                .title = "New Session",
                .subtitle = "Start a fresh conversation",
                .is_current = false,
            });
            row += 2;
            idx += 1;
        }

        // Existing sessions
        while (row < visible_rows * 2 + 2 and idx -| 1 < self.sessions.len) {
            const session_idx = idx -| 1;
            if (session_idx >= self.sessions.len) break;

            const session = &self.sessions[session_idx];
            const is_selected = self.selected_index == idx;
            const is_current = if (self.current_session_id) |cs|
                std.mem.eql(u8, cs, session.id)
            else
                false;

            self.drawItem(&surface, row, @intCast(width), is_selected, .{
                .icon = if (is_current) "*" else "o",
                .title = session.title orelse session.id,
                .subtitle = self.formatSessionMeta(session),
                .is_current = is_current,
            });

            row += 2;
            idx += 1;
        }

        // Scroll indicators
        if (self.scroll_offset > 0) {
            surface.writeCell(@intCast(width -| 1), 2, .{
                .char = .{ .grapheme = "^", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }
        if (idx < self.getTotalItems()) {
            surface.writeCell(@intCast(width -| 1), @intCast(height -| 2), .{
                .char = .{ .grapheme = "v", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Hints
        const hints = "j/k nav  Enter sel  n new";
        for (hints, 0..) |char, i| {
            if (i >= width) break;
            surface.writeCell(@intCast(i), @intCast(height -| 1), .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        return .{ .surface = surface };
    }

    const ItemDisplay = struct {
        icon: []const u8,
        title: []const u8,
        subtitle: []const u8,
        is_current: bool,
    };

    fn drawItem(self: *SessionList, surface: *vxfw.Surface, row: u16, width: u16, is_selected: bool, item: ItemDisplay) void {
        _ = self;

        // Fill background if selected
        if (is_selected) {
            for (0..width) |col| {
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

        // Icon
        const icon_color: vaxis.Color = if (item.is_current)
            .{ .index = 10 }
        else
            .{ .index = 14 };
        surface.writeCell(col, row, .{
            .char = .{ .grapheme = item.icon, .width = 1 },
            .style = .{ .fg = icon_color, .bg = if (is_selected) .{ .index = 8 } else .default },
        });
        col += 2;

        // Title
        for (item.title) |char| {
            if (col >= width -| 2) break;
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 15 }, .bold = is_selected, .bg = if (is_selected) .{ .index = 8 } else .default },
            });
            col += 1;
        }

        // Subtitle
        col = 3;
        for (item.subtitle) |char| {
            if (col >= width -| 2) break;
            surface.writeCell(col, row + 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 }, .bg = if (is_selected) .{ .index = 8 } else .default },
            });
            col += 1;
        }
    }

    fn formatSessionMeta(self: *SessionList, session: *const Session) []const u8 {
        _ = self;
        const effort = session.reasoning_effort.toString();
        return effort;
    }

    fn getTotalItems(self: *SessionList) usize {
        const session_count = self.sessions.len;
        return if (self.show_create_option) session_count + 1 else session_count;
    }

    fn ensureVisible(self: *SessionList, visible_rows: usize) void {
        if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        } else if (self.selected_index >= self.scroll_offset + visible_rows) {
            self.scroll_offset = self.selected_index -| visible_rows + 1;
        }
    }

    fn selectCurrent(self: *SessionList) void {
        if (self.show_create_option and self.selected_index == 0) {
            if (self.on_new) |cb| cb();
        } else {
            const idx = if (self.show_create_option) self.selected_index -| 1 else self.selected_index;
            if (idx < self.sessions.len) {
                if (self.on_select) |cb| {
                    cb(self.sessions[idx].id);
                }
            }
        }
    }
};
