const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

/// Widget for selecting Claude model
pub const ModelPicker = struct {
    allocator: std.mem.Allocator,
    selected_index: usize = 0,
    current_model: ?[]const u8 = null,
    on_select: ?*const fn ([]const u8) void = null,

    pub const Model = struct {
        id: []const u8,
        name: []const u8,
        description: []const u8,
    };

    pub const MODELS = [_]Model{
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
        };
    }

    pub fn widget(self: *ModelPicker) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = ModelPicker.handleEvent,
            .drawFn = ModelPicker.draw,
        };
    }

    fn handleEvent(userdata: ?*anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) void {
        const self: *ModelPicker = @ptrCast(@alignCast(userdata orelse return));

        switch (event) {
            .key_press => |key| {
                if (key.codepoint == vaxis.Key.up or key.codepoint == 'k') {
                    if (self.selected_index > 0) self.selected_index -= 1;
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.down or key.codepoint == 'j') {
                    if (self.selected_index < MODELS.len - 1) self.selected_index += 1;
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.enter) {
                    if (self.on_select) |cb| {
                        cb(MODELS[self.selected_index].id);
                    }
                    ctx.request_redraw = true;
                } else if (key.codepoint >= '1' and key.codepoint <= '4') {
                    self.selectByIndex(@intCast(key.codepoint - '1'));
                    ctx.request_redraw = true;
                }
            },
            else => {},
        }
    }

    fn selectByIndex(self: *ModelPicker, idx: usize) void {
        if (idx < MODELS.len) {
            self.selected_index = idx;
            if (self.on_select) |cb| {
                cb(MODELS[idx].id);
            }
        }
    }

    fn draw(userdata: ?*anyopaque, ctx: vxfw.DrawContext) vxfw.DrawResult {
        const self: *ModelPicker = @ptrCast(@alignCast(userdata orelse return .{ .surface = null }));
        const width: u31 = @intCast(ctx.max.width orelse 60);
        const height: u31 = @intCast(ctx.max.height orelse 16);

        var surface = vxfw.Surface.init(ctx.arena, self.widget(), width, height) catch return .{ .surface = null };

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
        for (MODELS, 0..) |model, i| {
            const is_selected = i == self.selected_index;
            const is_current = if (self.current_model) |cm|
                std.mem.eql(u8, cm, model.id)
            else
                false;

            // Background for selected
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

            // Number shortcut
            var num_buf: [4]u8 = undefined;
            const num = std.fmt.bufPrint(&num_buf, "{d}.", .{i + 1}) catch "?.";
            for (num) |char| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 14 }, .bg = if (is_selected) .{ .index = 8 } else .default },
                });
                col += 1;
            }
            col += 1;

            // Current indicator
            const indicator: []const u8 = if (is_current) "*" else "o";
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = indicator, .width = 1 },
                .style = .{ .fg = if (is_current) .{ .index = 10 } else .{ .index = 8 }, .bg = if (is_selected) .{ .index = 8 } else .default },
            });
            col += 2;

            // Model name
            for (model.name) |char| {
                if (col >= width -| 2) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 15 }, .bold = is_selected, .bg = if (is_selected) .{ .index = 8 } else .default },
                });
                col += 1;
            }

            // Description
            col = 6;
            for (model.description) |char| {
                if (col >= width -| 2) break;
                surface.writeCell(col, row + 1, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 }, .bg = if (is_selected) .{ .index = 8 } else .default },
                });
                col += 1;
            }

            row += 3;
        }

        // Hints
        const hints = "1-4 quick  j/k nav  Enter confirm";
        for (hints, 0..) |char, i| {
            if (i >= width) break;
            surface.writeCell(@intCast(i), @intCast(height -| 1), .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        return .{ .surface = surface };
    }
};
