const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const ReasoningEffort = @import("../state/session.zig").ReasoningEffort;

/// Widget for selecting reasoning effort level
pub const EffortPicker = struct {
    selected_index: usize = 2, // Default to medium
    current_effort: ?ReasoningEffort = null,
    on_select: ?*const fn (ReasoningEffort) void = null,

    const EffortInfo = struct {
        value: ReasoningEffort,
        name: []const u8,
        description: []const u8,
    };

    const EFFORTS = [_]EffortInfo{
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

    fn handleEvent(userdata: ?*anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) void {
        const self: *EffortPicker = @ptrCast(@alignCast(userdata orelse return));

        switch (event) {
            .key_press => |key| {
                if (key.codepoint == vaxis.Key.up or key.codepoint == vaxis.Key.left or key.codepoint == 'h') {
                    if (self.selected_index > 0) self.selected_index -= 1;
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.down or key.codepoint == vaxis.Key.right or key.codepoint == 'l') {
                    if (self.selected_index < EFFORTS.len - 1) self.selected_index += 1;
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.enter) {
                    if (self.on_select) |cb| {
                        cb(EFFORTS[self.selected_index].value);
                    }
                    ctx.request_redraw = true;
                } else if (key.codepoint >= '1' and key.codepoint <= '4') {
                    const idx: usize = @intCast(key.codepoint - '1');
                    if (idx < EFFORTS.len) {
                        self.selected_index = idx;
                        if (self.on_select) |cb| {
                            cb(EFFORTS[idx].value);
                        }
                    }
                    ctx.request_redraw = true;
                }
            },
            else => {},
        }
    }

    fn draw(userdata: ?*anyopaque, ctx: vxfw.DrawContext) vxfw.DrawResult {
        const self: *EffortPicker = @ptrCast(@alignCast(userdata orelse return .{ .surface = null }));
        const width: u31 = @intCast(ctx.max.width orelse 60);
        const height: u31 = @intCast(ctx.max.height orelse 10);

        var surface = vxfw.Surface.init(ctx.arena, self.widget(), width, height) catch return .{ .surface = null };

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
        const slider_width = width -| 4;
        const segment_width = slider_width / @as(u16, EFFORTS.len);

        // Draw track
        for (0..slider_width) |col| {
            surface.writeCell(@as(u16, @intCast(col)) + 2, slider_row, .{
                .char = .{ .grapheme = "-", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Draw segments and labels
        for (EFFORTS, 0..) |effort, i| {
            const x: u16 = 2 + @as(u16, @intCast(i)) * segment_width;
            const is_selected = i == self.selected_index;
            const is_current = if (self.current_effort) |ce| ce == effort.value else false;

            // Marker
            const marker: []const u8 = if (is_selected) "O" else "o";
            const marker_color: vaxis.Color = if (is_selected)
                .{ .index = 14 }
            else if (is_current)
                .{ .index = 10 }
            else
                .{ .index = 8 };

            surface.writeCell(x, slider_row, .{
                .char = .{ .grapheme = marker, .width = 1 },
                .style = .{ .fg = marker_color, .bold = is_selected },
            });

            // Label
            const label_offset = @as(u16, @intCast(effort.name.len / 2));
            const label_x = if (x > label_offset) x - label_offset else 0;
            for (effort.name, 0..) |char, j| {
                if (label_x + j >= width -| 2) break;
                surface.writeCell(label_x + @as(u16, @intCast(j)), slider_row + 1, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = if (is_selected) .{ .index = 15 } else .{ .index = 7 } },
                });
            }
        }

        // Selected description
        const desc = EFFORTS[self.selected_index].description;
        const desc_row = slider_row + 3;
        for (desc, 0..) |char, i| {
            if (i >= width -| 4) break;
            surface.writeCell(@as(u16, @intCast(i)) + 2, desc_row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Hints
        const hints = "1-4 or arrows  Enter confirm";
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
