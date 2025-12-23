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
                .file => "F",
                .skill => "*",
                .model => "M",
                .text => " ",
            };

            surface.writeCell(0, @intCast(i), .{
                .char = .{ .grapheme = icon, .width = 1 },
                .style = style,
            });

            // Draw label
            const start_col: u16 = 2;
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
