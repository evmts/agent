const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const cells = @import("cells.zig");
const HistoryCell = cells.HistoryCell;
const Conversation = @import("../state/conversation.zig").Conversation;
const Message = @import("../state/message.zig").Message;

pub const ChatHistory = struct {
    allocator: std.mem.Allocator,
    conversation: *Conversation,
    rendered_cells: std.ArrayList(HistoryCell),
    needs_rebuild: bool = true,
    last_message_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, conversation: *Conversation) ChatHistory {
        return .{
            .allocator = allocator,
            .conversation = conversation,
            .rendered_cells = std.ArrayList(HistoryCell).init(allocator),
        };
    }

    pub fn deinit(self: *ChatHistory) void {
        self.rendered_cells.deinit();
    }

    pub fn widget(self: *ChatHistory) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = ChatHistory.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *ChatHistory = @ptrCast(@alignCast(ptr));

        // Check if we need to rebuild (message count changed)
        if (self.conversation.messages.items.len != self.last_message_count) {
            self.needs_rebuild = true;
            self.last_message_count = self.conversation.messages.items.len;
        }

        // Rebuild cells if needed
        if (self.needs_rebuild) {
            try self.rebuildCells();
            self.needs_rebuild = false;
        }

        const width = ctx.max.width orelse 80;

        // Calculate total height
        var total_height: u16 = 0;
        for (self.rendered_cells.items) |cell| {
            total_height += cell.height(width);
        }

        // Add streaming cell if active
        var streaming_cell: ?HistoryCell = null;
        if (self.conversation.getStreamingText()) |text| {
            streaming_cell = .{ .streaming = .{ .text_buffer = text } };
            total_height += streaming_cell.?.height(width);
        }

        // Create surface
        const height = ctx.max.height orelse total_height;
        const actual_height = @max(total_height, height);
        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), .{
            .width = width,
            .height = actual_height,
        });

        // Draw cells
        var row: u16 = 0;
        for (self.rendered_cells.items) |*cell| {
            cell.draw(&surface, row, width);
            row += cell.height(width);
        }

        // Draw streaming
        if (streaming_cell) |*cell| {
            cell.draw(&surface, row, width);
        }

        return surface;
    }

    fn rebuildCells(self: *ChatHistory) !void {
        self.rendered_cells.clearRetainingCapacity();

        for (self.conversation.messages.items) |msg| {
            switch (msg.role) {
                .user => {
                    try self.rendered_cells.append(.{ .user_message = .{
                        .content = switch (msg.content) {
                            .text => |t| t,
                            .parts => "[complex content]", // TODO: handle parts
                        },
                        .timestamp = msg.timestamp,
                    } });
                },
                .assistant => {
                    try self.rendered_cells.append(.{ .assistant_message = .{
                        .content = switch (msg.content) {
                            .text => |t| t,
                            .parts => "[complex content]",
                        },
                        .tool_calls = msg.tool_calls.items,
                        .timestamp = msg.timestamp,
                    } });
                },
                .system => {
                    try self.rendered_cells.append(.{ .system_message = .{
                        .content = switch (msg.content) {
                            .text => |t| t,
                            .parts => "[system]",
                        },
                    } });
                },
            }

            // Add separator between messages
            try self.rendered_cells.append(.{ .separator = .{} });
        }
    }

    pub fn markDirty(self: *ChatHistory) void {
        self.needs_rebuild = true;
    }

    pub fn getContentHeight(self: *ChatHistory, width: u16) u16 {
        var height: u16 = 0;
        for (self.rendered_cells.items) |cell| {
            height += cell.height(width);
        }
        if (self.conversation.getStreamingText()) |text| {
            height += cells.StreamingCell{ .text_buffer = text }.height(width);
        }
        return height;
    }
};
