const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const approval = @import("../state/approval.zig");
const ApprovalRequest = approval.ApprovalRequest;
const ApprovalResponse = approval.ApprovalResponse;
const Decision = approval.Decision;
const FileOperation = approval.FileOperation;

/// Widget for approving file changes
pub const FileApproval = struct {
    allocator: std.mem.Allocator,
    request: *const ApprovalRequest,
    selected_option: usize = 0,
    scroll_offset: u16 = 0,
    on_respond: ?*const fn (ApprovalResponse) void = null,

    const Option = struct {
        key: u8,
        label: []const u8,
        decision: Decision,
    };

    const OPTIONS = [_]Option{
        .{ .key = 'y', .label = "Yes, apply changes", .decision = .approve },
        .{ .key = 'n', .label = "No, skip", .decision = .decline },
    };

    pub fn init(
        allocator: std.mem.Allocator,
        request: *const ApprovalRequest,
    ) FileApproval {
        return .{
            .allocator = allocator,
            .request = request,
        };
    }

    pub fn widget(self: *FileApproval) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = FileApproval.handleEvent,
            .drawFn = FileApproval.draw,
        };
    }

    fn handleEvent(userdata: ?*anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) void {
        const self: *FileApproval = @ptrCast(@alignCast(userdata orelse return));

        switch (event) {
            .key_press => |key| {
                if (key.codepoint == 'y') {
                    self.respond(.approve);
                    ctx.request_redraw = true;
                } else if (key.codepoint == 'n' or key.codepoint == vaxis.Key.escape) {
                    self.respond(.decline);
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.up or key.codepoint == 'k') {
                    if (self.scroll_offset > 0) self.scroll_offset -= 1;
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.down or key.codepoint == 'j') {
                    self.scroll_offset += 1;
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.left) {
                    if (self.selected_option > 0) self.selected_option -= 1;
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.right) {
                    if (self.selected_option < OPTIONS.len - 1) self.selected_option += 1;
                    ctx.request_redraw = true;
                } else if (key.codepoint == vaxis.Key.enter) {
                    self.respond(OPTIONS[self.selected_option].decision);
                    ctx.request_redraw = true;
                }
            },
            else => {},
        }
    }

    fn respond(self: *FileApproval, decision: Decision) void {
        if (self.on_respond) |cb| {
            cb(.{
                .request_id = self.request.id,
                .decision = decision,
                .scope = .once,
            });
        }
    }

    fn draw(userdata: ?*anyopaque, ctx: vxfw.DrawContext) vxfw.DrawResult {
        const self: *FileApproval = @ptrCast(@alignCast(userdata orelse return .{ .surface = null }));
        const width: u31 = @intCast(ctx.max.width orelse 80);
        const height: u31 = @intCast(ctx.max.height orelse 24);

        var surface = vxfw.Surface.init(ctx.arena, self.widget(), width, height) catch return .{ .surface = null };

        // Header
        const title = "Apply these changes?";
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(i + 2), 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // File path and operation
        const file_change = self.request.file_change;
        const path = if (file_change) |fc| fc.path else "unknown";
        const operation = if (file_change) |fc| fc.operation else FileOperation.modify;

        const op_str: []const u8 = switch (operation) {
            .create => "[NEW] ",
            .modify => "[MOD] ",
            .delete => "[DEL] ",
        };
        const op_color: vaxis.Color = switch (operation) {
            .create => .{ .index = 10 },
            .modify => .{ .index = 11 },
            .delete => .{ .index = 9 },
        };

        var col: u16 = 2;
        for (op_str) |char| {
            surface.writeCell(col, 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = op_color, .bold = true },
            });
            col += 1;
        }

        for (path) |char| {
            if (col >= width - 2) break;
            surface.writeCell(col, 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 12 } },
            });
            col += 1;
        }

        // Separator
        for (0..width) |c| {
            surface.writeCell(@intCast(c), 2, .{
                .char = .{ .grapheme = "-", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Diff view
        if (file_change) |fc| {
            if (fc.diff) |diff| {
                self.drawDiff(&surface, diff, 3, @intCast(width), @intCast(height -| 4));
            }
        }

        // Options at bottom
        const options_row: u16 = @intCast(height -| 1);
        col = 2;
        for (OPTIONS, 0..) |opt, i| {
            const is_selected = i == self.selected_option;
            const style: vaxis.Cell.Style = if (is_selected)
                .{ .fg = .{ .index = 0 }, .bg = .{ .index = 14 } }
            else
                .{ .fg = .{ .index = 7 } };

            surface.writeCell(col, options_row, .{
                .char = .{ .grapheme = "[", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
            col += 1;
            surface.writeCell(col, options_row, .{
                .char = .{ .grapheme = &[_]u8{opt.key}, .width = 1 },
                .style = style,
            });
            col += 1;
            surface.writeCell(col, options_row, .{
                .char = .{ .grapheme = "]", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
            col += 1;
            for (opt.label) |char| {
                surface.writeCell(col, options_row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = style,
                });
                col += 1;
            }
            col += 4;
        }

        // Scroll hint
        const hint = "j/k to scroll";
        const hint_x = width -| @as(u16, @intCast(hint.len)) - 2;
        for (hint, 0..) |char, i| {
            surface.writeCell(hint_x + @as(u16, @intCast(i)), options_row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        return .{ .surface = surface };
    }

    fn drawDiff(self: *FileApproval, surface: *vxfw.Surface, diff: []const u8, start_row: u16, width: u16, max_rows: u16) void {
        var row = start_row;
        var line_start: usize = 0;
        var line_num: u16 = 0;

        for (diff, 0..) |char, i| {
            if (char == '\n' or i == diff.len - 1) {
                // Skip lines before scroll offset
                if (line_num < self.scroll_offset) {
                    line_num += 1;
                    line_start = i + 1;
                    continue;
                }

                if (row >= start_row + max_rows) break;

                const line_end = if (char == '\n') i else i + 1;
                const line = diff[line_start..line_end];

                // Determine line style
                const style: vaxis.Cell.Style = if (line.len > 0)
                    switch (line[0]) {
                        '+' => .{ .fg = .{ .index = 10 } },
                        '-' => .{ .fg = .{ .index = 9 } },
                        '@' => .{ .fg = .{ .index = 14 } },
                        else => .{ .fg = .{ .index = 7 } },
                    }
                else
                    .{ .fg = .{ .index = 7 } };

                // Draw line
                for (line, 0..) |c, j| {
                    if (j >= width) break;
                    surface.writeCell(@intCast(j), row, .{
                        .char = .{ .grapheme = &[_]u8{c}, .width = 1 },
                        .style = style,
                    });
                }

                row += 1;
                line_num += 1;
                line_start = i + 1;
            }
        }
    }
};
