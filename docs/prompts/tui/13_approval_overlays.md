# 13: Approval Overlays

## Goal

Implement approval overlays for command execution and file changes, allowing users to approve, decline, or modify agent actions.

## Context

- Agent actions may require user approval before execution
- Need overlays for: command approval, file change approval, batch approval
- Reference: codex approval system, `/Users/williamcory/plue/codex/` patterns

## Tasks

### 1. Create Approval State (src/state/approval.zig)

```zig
const std = @import("std");

pub const ApprovalRequest = struct {
    id: []const u8,
    request_type: Type,
    description: []const u8,
    details: Details,
    timestamp: i64,

    pub const Type = enum {
        command_execution,
        file_write,
        file_delete,
        batch,
    };

    pub const Details = union(enum) {
        command: CommandDetails,
        file_change: FileChangeDetails,
        batch: BatchDetails,
    };

    pub const CommandDetails = struct {
        command: []const u8,
        working_dir: ?[]const u8 = null,
        risk_level: RiskLevel = .medium,
    };

    pub const FileChangeDetails = struct {
        path: []const u8,
        operation: Operation,
        diff: ?[]const u8 = null,

        pub const Operation = enum {
            create,
            modify,
            delete,
        };
    };

    pub const BatchDetails = struct {
        items: []ApprovalRequest,
        summary: []const u8,
    };

    pub const RiskLevel = enum {
        low,      // Read-only operations
        medium,   // Local modifications
        high,     // System changes, network access
        critical, // Destructive operations
    };
};

pub const ApprovalResponse = struct {
    request_id: []const u8,
    decision: Decision,
    scope: Scope = .once,
    modified_command: ?[]const u8 = null,

    pub const Decision = enum {
        approve,
        decline,
        modify,
    };

    pub const Scope = enum {
        once,           // This instance only
        session,        // All similar in this session
        always,         // Remember for future
    };
};

pub const ApprovalManager = struct {
    allocator: std.mem.Allocator,
    pending_requests: std.ArrayList(ApprovalRequest),
    session_approvals: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) ApprovalManager {
        return .{
            .allocator = allocator,
            .pending_requests = std.ArrayList(ApprovalRequest).init(allocator),
            .session_approvals = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *ApprovalManager) void {
        self.pending_requests.deinit();
        self.session_approvals.deinit();
    }

    pub fn addRequest(self: *ApprovalManager, request: ApprovalRequest) !void {
        // Check if already approved for session
        if (self.session_approvals.contains(request.id)) {
            return; // Auto-approve
        }
        try self.pending_requests.append(request);
    }

    pub fn getCurrentRequest(self: *ApprovalManager) ?*ApprovalRequest {
        if (self.pending_requests.items.len > 0) {
            return &self.pending_requests.items[0];
        }
        return null;
    }

    pub fn respond(self: *ApprovalManager, response: ApprovalResponse) !void {
        // Find and remove request
        for (self.pending_requests.items, 0..) |req, i| {
            if (std.mem.eql(u8, req.id, response.request_id)) {
                _ = self.pending_requests.orderedRemove(i);

                // Handle session approval
                if (response.decision == .approve and response.scope == .session) {
                    try self.session_approvals.put(response.request_id, {});
                }
                break;
            }
        }
    }

    pub fn hasPending(self: *ApprovalManager) bool {
        return self.pending_requests.items.len > 0;
    }
};
```

### 2. Create Command Approval Overlay (src/widgets/command_approval.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const ApprovalRequest = @import("../state/approval.zig").ApprovalRequest;
const ApprovalResponse = @import("../state/approval.zig").ApprovalResponse;
const Modal = @import("modal.zig").Modal;
const Border = @import("border.zig").Border;

pub const CommandApproval = struct {
    allocator: std.mem.Allocator,
    request: *const ApprovalRequest,
    selected_option: usize = 0,
    on_respond: *const fn (ApprovalResponse) void,
    edit_mode: bool = false,
    edit_buffer: std.ArrayList(u8),

    const OPTIONS = [_]Option{
        .{ .key = "y", .label = "Yes, run it", .decision = .approve, .scope = .once },
        .{ .key = "s", .label = "Yes, for this session", .decision = .approve, .scope = .session },
        .{ .key = "e", .label = "Edit command", .decision = .modify, .scope = .once },
        .{ .key = "n", .label = "No, skip", .decision = .decline, .scope = .once },
    };

    const Option = struct {
        key: []const u8,
        label: []const u8,
        decision: ApprovalResponse.Decision,
        scope: ApprovalResponse.Scope,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        request: *const ApprovalRequest,
        on_respond: *const fn (ApprovalResponse) void,
    ) CommandApproval {
        return .{
            .allocator = allocator,
            .request = request,
            .on_respond = on_respond,
            .edit_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *CommandApproval) void {
        self.edit_buffer.deinit();
    }

    pub fn widget(self: *CommandApproval) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = CommandApproval.handleEvent,
            .drawFn = CommandApproval.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *CommandApproval = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                if (self.edit_mode) {
                    try self.handleEditMode(ctx, key);
                } else {
                    try self.handleNormalMode(ctx, key);
                }
            },
            else => {},
        }
    }

    fn handleNormalMode(self: *CommandApproval, ctx: *vxfw.EventContext, key: vaxis.Key) !void {
        // Quick keys
        if (key.matches('y', .{})) {
            self.respond(.approve, .once, null);
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches('s', .{})) {
            self.respond(.approve, .session, null);
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches('n', .{}) or key.matches(vaxis.Key.escape, .{})) {
            self.respond(.decline, .once, null);
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches('e', .{})) {
            self.enterEditMode();
            ctx.consumeAndRedraw();
            return;
        }

        // Arrow navigation
        if (key.matches(vaxis.Key.up, .{})) {
            if (self.selected_option > 0) self.selected_option -= 1;
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.down, .{})) {
            if (self.selected_option < OPTIONS.len - 1) self.selected_option += 1;
            ctx.consumeAndRedraw();
        } else if (key.matches(vaxis.Key.enter, .{})) {
            const opt = OPTIONS[self.selected_option];
            if (opt.decision == .modify) {
                self.enterEditMode();
            } else {
                self.respond(opt.decision, opt.scope, null);
            }
            ctx.consumeAndRedraw();
        }
    }

    fn handleEditMode(self: *CommandApproval, ctx: *vxfw.EventContext, key: vaxis.Key) !void {
        if (key.matches(vaxis.Key.escape, .{})) {
            self.edit_mode = false;
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches(vaxis.Key.enter, .{})) {
            if (self.edit_buffer.items.len > 0) {
                self.respond(.modify, .once, self.edit_buffer.items);
            }
            ctx.consumeAndRedraw();
            return;
        }
        if (key.matches(vaxis.Key.backspace, .{})) {
            if (self.edit_buffer.items.len > 0) {
                _ = self.edit_buffer.pop();
            }
            ctx.consumeAndRedraw();
            return;
        }
        if (key.text) |text| {
            try self.edit_buffer.appendSlice(text);
            ctx.consumeAndRedraw();
        }
    }

    fn enterEditMode(self: *CommandApproval) void {
        self.edit_mode = true;
        self.edit_buffer.clearRetainingCapacity();

        // Pre-fill with original command
        switch (self.request.details) {
            .command => |cmd| {
                self.edit_buffer.appendSlice(cmd.command) catch {};
            },
            else => {},
        }
    }

    fn respond(self: *CommandApproval, decision: ApprovalResponse.Decision, scope: ApprovalResponse.Scope, modified: ?[]const u8) void {
        self.on_respond(.{
            .request_id = self.request.id,
            .decision = decision,
            .scope = scope,
            .modified_command = modified,
        });
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *CommandApproval = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        const modal_width: u16 = @min(70, size.width -| 4);
        const modal_height: u16 = if (self.edit_mode) 15 else 12;
        const x = (size.width -| modal_width) / 2;
        const y = (size.height -| modal_height) / 2;

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Dim background
        for (0..size.height) |row| {
            for (0..size.width) |col| {
                surface.writeCell(@intCast(col), @intCast(row), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{ .bg = .{ .rgb = .{ 0, 0, 0 } }, .dim = true },
                });
            }
        }

        // Draw modal content
        try self.drawModalContent(&surface, x, y, modal_width, modal_height);

        return surface;
    }

    fn drawModalContent(self: *CommandApproval, surface: *vxfw.Surface, x: u16, y: u16, width: u16, height: u16) !void {
        // Border
        self.drawBorder(surface, x, y, width, height);

        // Title
        const title = "Run this command?";
        const title_x = x + (width -| @as(u16, @intCast(title.len))) / 2;
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(title_x + i), y + 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // Risk level indicator
        const risk_level = switch (self.request.details) {
            .command => |cmd| cmd.risk_level,
            else => .medium,
        };
        const risk_text = switch (risk_level) {
            .low => "Low Risk",
            .medium => "Medium Risk",
            .high => "High Risk",
            .critical => "CRITICAL",
        };
        const risk_color: vaxis.Color = switch (risk_level) {
            .low => .{ .index = 10 },
            .medium => .{ .index = 11 },
            .high => .{ .index = 9 },
            .critical => .{ .index = 9 },
        };

        const risk_x = x + width - @as(u16, @intCast(risk_text.len)) - 2;
        for (risk_text, 0..) |char, i| {
            surface.writeCell(@intCast(risk_x + i), y + 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = risk_color, .bold = risk_level == .critical },
            });
        }

        // Command display
        var row = y + 3;
        self.drawText(surface, "$ ", x + 2, row, .{ .fg = .{ .index = 10 } });

        const command = switch (self.request.details) {
            .command => |cmd| cmd.command,
            else => "",
        };
        self.drawText(surface, command, x + 4, row, .{ .fg = .{ .index = 15 } });

        // Working directory
        row += 2;
        const working_dir = switch (self.request.details) {
            .command => |cmd| cmd.working_dir,
            else => null,
        };
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
            surface.writeCell(@intCast(x + 4 + self.edit_buffer.items.len), row, .{
                .char = .{ .grapheme = "▋", .width = 1 },
                .style = .{ .fg = .{ .index = 10 } },
            });
            row += 2;
            self.drawText(surface, "Enter to confirm, Esc to cancel", x + 2, row, .{ .fg = .{ .index = 8 } });
        } else {
            // Options
            for (OPTIONS, 0..) |opt, i| {
                const is_selected = i == self.selected_option;
                const prefix = if (is_selected) "▶ " else "  ";
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
                self.drawText(surface, opt.key, x + 5, row, key_style);
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
        surface.writeCell(x, y, .{ .char = .{ .grapheme = "╭", .width = 1 }, .style = style });
        surface.writeCell(x + width - 1, y, .{ .char = .{ .grapheme = "╮", .width = 1 }, .style = style });
        surface.writeCell(x, y + height - 1, .{ .char = .{ .grapheme = "╰", .width = 1 }, .style = style });
        surface.writeCell(x + width - 1, y + height - 1, .{ .char = .{ .grapheme = "╯", .width = 1 }, .style = style });

        // Horizontal
        for (1..width - 1) |col| {
            surface.writeCell(@intCast(x + col), y, .{ .char = .{ .grapheme = "─", .width = 1 }, .style = style });
            surface.writeCell(@intCast(x + col), y + height - 1, .{ .char = .{ .grapheme = "─", .width = 1 }, .style = style });
        }

        // Vertical
        for (1..height - 1) |row| {
            surface.writeCell(x, @intCast(y + row), .{ .char = .{ .grapheme = "│", .width = 1 }, .style = style });
            surface.writeCell(x + width - 1, @intCast(y + row), .{ .char = .{ .grapheme = "│", .width = 1 }, .style = style });
        }

        // Fill background
        for (1..height - 1) |row| {
            for (1..width - 1) |col| {
                surface.writeCell(@intCast(x + col), @intCast(y + row), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{ .bg = .{ .index = 0 } },
                });
            }
        }
    }

    fn drawText(self: *CommandApproval, surface: *vxfw.Surface, text: []const u8, x: u16, y: u16, style: vaxis.Cell.Style) void {
        _ = self;
        for (text, 0..) |char, i| {
            surface.writeCell(@intCast(x + i), y, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = style,
            });
        }
    }
};
```

### 3. Create File Change Approval (src/widgets/file_approval.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const ApprovalRequest = @import("../state/approval.zig").ApprovalRequest;
const ApprovalResponse = @import("../state/approval.zig").ApprovalResponse;
const DiffView = @import("diff_view.zig").DiffView;

pub const FileApproval = struct {
    allocator: std.mem.Allocator,
    request: *const ApprovalRequest,
    diff_view: ?DiffView = null,
    selected_option: usize = 0,
    on_respond: *const fn (ApprovalResponse) void,

    const OPTIONS = [_]struct { key: []const u8, label: []const u8, decision: ApprovalResponse.Decision }{
        .{ .key = "y", .label = "Yes, apply changes", .decision = .approve },
        .{ .key = "n", .label = "No, skip", .decision = .decline },
    };

    pub fn init(
        allocator: std.mem.Allocator,
        request: *const ApprovalRequest,
        on_respond: *const fn (ApprovalResponse) void,
    ) !FileApproval {
        var self = FileApproval{
            .allocator = allocator,
            .request = request,
            .on_respond = on_respond,
        };

        // Initialize diff view if we have a diff
        switch (request.details) {
            .file_change => |fc| {
                if (fc.diff) |diff_text| {
                    self.diff_view = DiffView.init(allocator);
                    try self.diff_view.?.setDiff(diff_text);
                }
            },
            else => {},
        }

        return self;
    }

    pub fn widget(self: *FileApproval) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = FileApproval.handleEvent,
            .drawFn = FileApproval.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *FileApproval = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                if (key.matches('y', .{})) {
                    self.respond(.approve);
                    ctx.consumeAndRedraw();
                } else if (key.matches('n', .{}) or key.matches(vaxis.Key.escape, .{})) {
                    self.respond(.decline);
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.up, .{})) {
                    if (self.selected_option > 0) self.selected_option -= 1;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.down, .{})) {
                    if (self.selected_option < OPTIONS.len - 1) self.selected_option += 1;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    self.respond(OPTIONS[self.selected_option].decision);
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn respond(self: *FileApproval, decision: ApprovalResponse.Decision) void {
        self.on_respond(.{
            .request_id = self.request.id,
            .decision = decision,
            .scope = .once,
        });
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *FileApproval = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Header
        const title = "Apply these changes?";
        for (title, 0..) |char, i| {
            surface.writeCell(@intCast(i + 2), 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
        }

        // File path
        const path = switch (self.request.details) {
            .file_change => |fc| fc.path,
            else => "unknown",
        };
        for (path, 0..) |char, i| {
            if (i >= size.width - 4) break;
            surface.writeCell(@intCast(i + 2), 1, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .index = 12 } },
            });
        }

        // Diff view
        if (self.diff_view) |*dv| {
            const diff_surface = try dv.widget().draw(ctx.withConstraints(
                .{ .width = size.width, .height = size.height -| 6 },
                .{ .width = size.width, .height = size.height -| 6 },
            ));

            // Copy diff surface to main
            for (0..diff_surface.size.height) |row| {
                for (0..diff_surface.size.width) |col| {
                    if (diff_surface.getCell(@intCast(col), @intCast(row))) |cell| {
                        surface.writeCell(@intCast(col), @intCast(row + 3), cell);
                    }
                }
            }
        }

        // Options at bottom
        const options_row = size.height - 2;
        var col: u16 = 2;
        for (OPTIONS, 0..) |opt, i| {
            const is_selected = i == self.selected_option;
            const style = if (is_selected)
                vaxis.Cell.Style{ .fg = .{ .index = 0 }, .bg = .{ .index = 14 } }
            else
                vaxis.Cell.Style{ .fg = .{ .index = 7 } };

            surface.writeCell(col, options_row, .{
                .char = .{ .grapheme = "[", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
            col += 1;
            for (opt.key) |char| {
                surface.writeCell(col, options_row, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = style,
                });
                col += 1;
            }
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

        return surface;
    }
};
```

## Acceptance Criteria

- [ ] Command approval shows command, working dir, risk level
- [ ] Keyboard shortcuts (y/n/e/s) work
- [ ] Arrow key navigation between options
- [ ] Edit mode allows modifying command
- [ ] Session-level approval option works
- [ ] File approval shows diff preview
- [ ] Modal appears centered with dimmed background
- [ ] ESC closes without action
- [ ] Approval manager tracks pending requests

## Files to Create

1. `tui-zig/src/state/approval.zig`
2. `tui-zig/src/widgets/command_approval.zig`
3. `tui-zig/src/widgets/file_approval.zig`

## Next

Proceed to `14_session_management.md` for session UI components.
