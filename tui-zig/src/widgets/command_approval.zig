const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const approval = @import("../state/approval.zig");
const ApprovalRequest = approval.ApprovalRequest;
const ApprovalResponse = approval.ApprovalResponse;
const Decision = approval.Decision;
const Scope = approval.Scope;
const RiskLevel = approval.RiskLevel;

/// Widget for approving command execution
pub const CommandApproval = struct {
    allocator: std.mem.Allocator,
    request: *const ApprovalRequest,
    selected_option: usize = 0,
    on_respond: ?*const fn (ApprovalResponse) void = null,
    edit_mode: bool = false,
    edit_buffer: std.ArrayList(u8),

    const Option = struct {
        key: u8,
        label: []const u8,
        decision: Decision,
        scope: Scope,
    };

    const OPTIONS = [_]Option{
        .{ .key = 'y', .label = "Yes, run it", .decision = .approve, .scope = .once },
        .{ .key = 's', .label = "Yes, for this session", .decision = .approve, .scope = .session },
        .{ .key = 'e', .label = "Edit command", .decision = .modify, .scope = .once },
        .{ .key = 'n', .label = "No, skip", .decision = .decline, .scope = .once },
    };

    pub fn init(
        allocator: std.mem.Allocator,
        request: *const ApprovalRequest,
    ) CommandApproval {
        return .{
            .allocator = allocator,
            .request = request,
            .edit_buffer = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *CommandApproval) void {
        self.edit_buffer.deinit(self.allocator);
    }

    pub fn widget(self: *CommandApproval) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = CommandApproval.handleEvent,
            .drawFn = CommandApproval.draw,
        };
    }

    fn handleEvent(userdata: ?*anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) void {
        const self: *CommandApproval = @ptrCast(@alignCast(userdata orelse return));

        switch (event) {
            .key_press => |key| {
                if (self.edit_mode) {
                    self.handleEditMode(ctx, key);
                } else {
                    self.handleNormalMode(ctx, key);
                }
            },
            else => {},
        }
    }

    fn handleNormalMode(self: *CommandApproval, ctx: *vxfw.EventContext, key: vaxis.Key) void {
        // Quick keys
        if (key.codepoint == 'y') {
            self.respond(.approve, .once, null);
            ctx.request_redraw = true;
            return;
        }
        if (key.codepoint == 's') {
            self.respond(.approve, .session, null);
            ctx.request_redraw = true;
            return;
        }
        if (key.codepoint == 'n' or key.codepoint == vaxis.Key.escape) {
            self.respond(.decline, .once, null);
            ctx.request_redraw = true;
            return;
        }
        if (key.codepoint == 'e') {
            self.enterEditMode();
            ctx.request_redraw = true;
            return;
        }

        // Arrow navigation
        if (key.codepoint == vaxis.Key.up) {
            if (self.selected_option > 0) self.selected_option -= 1;
            ctx.request_redraw = true;
        } else if (key.codepoint == vaxis.Key.down) {
            if (self.selected_option < OPTIONS.len - 1) self.selected_option += 1;
            ctx.request_redraw = true;
        } else if (key.codepoint == vaxis.Key.enter) {
            const opt = OPTIONS[self.selected_option];
            if (opt.decision == .modify) {
                self.enterEditMode();
            } else {
                self.respond(opt.decision, opt.scope, null);
            }
            ctx.request_redraw = true;
        }
    }

    fn handleEditMode(self: *CommandApproval, ctx: *vxfw.EventContext, key: vaxis.Key) void {
        if (key.codepoint == vaxis.Key.escape) {
            self.edit_mode = false;
            ctx.request_redraw = true;
            return;
        }
        if (key.codepoint == vaxis.Key.enter) {
            if (self.edit_buffer.items.len > 0) {
                self.respond(.modify, .once, self.edit_buffer.items);
            }
            ctx.request_redraw = true;
            return;
        }
        if (key.codepoint == vaxis.Key.backspace) {
            if (self.edit_buffer.items.len > 0) {
                _ = self.edit_buffer.pop();
            }
            ctx.request_redraw = true;
            return;
        }
        if (key.text) |text| {
            self.edit_buffer.appendSlice(self.allocator, text) catch {};
            ctx.request_redraw = true;
        }
    }

    fn enterEditMode(self: *CommandApproval) void {
        self.edit_mode = true;
        self.edit_buffer.clearRetainingCapacity();

        // Pre-fill with original command
        if (self.request.command) |cmd| {
            self.edit_buffer.appendSlice(self.allocator, cmd.command) catch {};
        }
    }

    fn respond(self: *CommandApproval, decision: Decision, scope: Scope, modified: ?[]const u8) void {
        if (self.on_respond) |cb| {
            cb(.{
                .request_id = self.request.id,
                .decision = decision,
                .scope = scope,
                .modified_command = modified,
            });
        }
    }

    fn draw(userdata: ?*anyopaque, ctx: vxfw.DrawContext) vxfw.DrawResult {
        const self: *CommandApproval = @ptrCast(@alignCast(userdata orelse return .{ .surface = null }));
        const screen_width: u31 = @intCast(ctx.max.width orelse 80);
        const screen_height: u31 = @intCast(ctx.max.height orelse 24);

        const modal_width: u31 = @min(70, screen_width -| 4);
        const modal_height: u31 = if (self.edit_mode) 15 else 12;
        const x: u16 = @intCast((screen_width -| modal_width) / 2);
        const y: u16 = @intCast((screen_height -| modal_height) / 2);

        var surface = vxfw.Surface.init(ctx.arena, self.widget(), screen_width, screen_height) catch return .{ .surface = null };

        // Dim background
        for (0..screen_height) |row| {
            for (0..screen_width) |col| {
                surface.writeCell(@intCast(col), @intCast(row), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{ .dim = true },
                });
            }
        }

        // Draw modal content
        self.drawModalContent(&surface, x, y, @intCast(modal_width), @intCast(modal_height));

        return .{ .surface = surface };
    }

    fn drawModalContent(self: *CommandApproval, surface: *vxfw.Surface, x: u16, y: u16, width: u16, height: u16) void {
        // Border and background
        self.drawBorder(surface, x, y, width, height);

        // Title
        const title = "Run this command?";
        const title_x = x + (width -| @as(u16, @intCast(title.len))) / 2;
        for (title, 0..) |char, i| {
            surface.writeCell(title_x + @as(u16, @intCast(i)), y + 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // Risk level indicator
        const risk_level = if (self.request.command) |cmd| cmd.risk_level else RiskLevel.medium;
        const risk_text = risk_level.toString();
        const risk_color: vaxis.Color = switch (risk_level) {
            .low => .{ .index = 10 },
            .medium => .{ .index = 11 },
            .high => .{ .index = 9 },
            .critical => .{ .index = 9 },
        };

        const risk_x = x + width -| @as(u16, @intCast(risk_text.len)) - 2;
        for (risk_text, 0..) |char, i| {
            surface.writeCell(risk_x + @as(u16, @intCast(i)), y + 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = risk_color, .bold = risk_level == .critical },
            });
        }

        // Command display
        var row = y + 3;
        self.drawText(surface, "$ ", x + 2, row, .{ .fg = .{ .index = 10 } });

        const command = if (self.request.command) |cmd| cmd.command else "";
        self.drawText(surface, command, x + 4, row, .{ .fg = .{ .index = 15 } });

        // Working directory
        row += 2;
        const working_dir = if (self.request.command) |cmd| cmd.working_dir else null;
        if (working_dir) |dir| {
            self.drawText(surface, "in ", x + 2, row, .{ .fg = .{ .index = 8 } });
            self.drawText(surface, dir, x + 5, row, .{ .fg = .{ .index = 8 } });
        }

        // Edit mode or options
        row += 2;
        if (self.edit_mode) {
            self.drawText(surface, "Edit command:", x + 2, row, .{ .fg = .{ .index = 14 } });
            row += 1;
            self.drawText(surface, "$ ", x + 2, row, .{ .fg = .{ .index = 10 } });
            self.drawText(surface, self.edit_buffer.items, x + 4, row, .{ .fg = .{ .index = 15 } });
            // Cursor
            surface.writeCell(x + 4 + @as(u16, @intCast(self.edit_buffer.items.len)), row, .{
                .char = .{ .grapheme = "|", .width = 1 },
                .style = .{ .fg = .{ .index = 10 } },
            });
            row += 2;
            self.drawText(surface, "Enter to confirm, Esc to cancel", x + 2, row, .{ .fg = .{ .index = 8 } });
        } else {
            // Options
            for (OPTIONS, 0..) |opt, i| {
                const is_selected = i == self.selected_option;
                const prefix: []const u8 = if (is_selected) "> " else "  ";
                const key_style = vaxis.Cell.Style{
                    .fg = .{ .index = 14 },
                    .bold = is_selected,
                    .reverse = is_selected,
                };
                const label_style = vaxis.Cell.Style{
                    .fg = if (is_selected) .{ .index = 15 } else .{ .index = 7 },
                };

                self.drawText(surface, prefix, x + 2, row, label_style);
                self.drawText(surface, "[", x + 4, row, .{ .fg = .{ .index = 8 } });
                surface.writeCell(x + 5, row, .{
                    .char = .{ .grapheme = &[_]u8{opt.key}, .width = 1 },
                    .style = key_style,
                });
                self.drawText(surface, "] ", x + 6, row, .{ .fg = .{ .index = 8 } });
                self.drawText(surface, opt.label, x + 8, row, label_style);

                row += 1;
            }
        }
    }

    fn drawBorder(self: *CommandApproval, surface: *vxfw.Surface, x: u16, y: u16, width: u16, height: u16) void {
        _ = self;
        const style = vaxis.Cell.Style{ .fg = .{ .index = 14 } };

        // Corners
        surface.writeCell(x, y, .{ .char = .{ .grapheme = "+", .width = 1 }, .style = style });
        surface.writeCell(x + width - 1, y, .{ .char = .{ .grapheme = "+", .width = 1 }, .style = style });
        surface.writeCell(x, y + height - 1, .{ .char = .{ .grapheme = "+", .width = 1 }, .style = style });
        surface.writeCell(x + width - 1, y + height - 1, .{ .char = .{ .grapheme = "+", .width = 1 }, .style = style });

        // Horizontal
        for (1..width - 1) |col| {
            surface.writeCell(x + @as(u16, @intCast(col)), y, .{ .char = .{ .grapheme = "-", .width = 1 }, .style = style });
            surface.writeCell(x + @as(u16, @intCast(col)), y + height - 1, .{ .char = .{ .grapheme = "-", .width = 1 }, .style = style });
        }

        // Vertical
        for (1..height - 1) |row| {
            surface.writeCell(x, y + @as(u16, @intCast(row)), .{ .char = .{ .grapheme = "|", .width = 1 }, .style = style });
            surface.writeCell(x + width - 1, y + @as(u16, @intCast(row)), .{ .char = .{ .grapheme = "|", .width = 1 }, .style = style });
        }

        // Fill background
        for (1..height - 1) |row| {
            for (1..width - 1) |col| {
                surface.writeCell(x + @as(u16, @intCast(col)), y + @as(u16, @intCast(row)), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{ .bg = .{ .index = 0 } },
                });
            }
        }
    }

    fn drawText(self: *CommandApproval, surface: *vxfw.Surface, text: []const u8, x: u16, y: u16, style: vaxis.Cell.Style) void {
        _ = self;
        for (text, 0..) |char, i| {
            surface.writeCell(x + @as(u16, @intCast(i)), y, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
        }
    }
};
