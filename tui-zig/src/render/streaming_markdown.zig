const std = @import("std");
const vaxis = @import("vaxis");
const MarkdownRenderer = @import("markdown.zig").MarkdownRenderer;
const Segment = @import("markdown.zig").Segment;

/// Handles streaming markdown by buffering incomplete elements
pub const StreamingMarkdown = struct {
    allocator: std.mem.Allocator,
    renderer: MarkdownRenderer,
    buffer: std.ArrayList(u8),
    rendered_segments: std.ArrayList(Segment),
    incomplete_line: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) StreamingMarkdown {
        return .{
            .allocator = allocator,
            .renderer = MarkdownRenderer.init(allocator),
            .buffer = std.ArrayList(u8).init(allocator),
            .rendered_segments = std.ArrayList(Segment).init(allocator),
            .incomplete_line = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *StreamingMarkdown) void {
        self.buffer.deinit();
        // Free segment text allocations
        for (self.rendered_segments.items) |seg| {
            self.allocator.free(seg.text);
            if (seg.link) |link| {
                self.allocator.free(link);
            }
        }
        self.rendered_segments.deinit();
        self.incomplete_line.deinit();
    }

    /// Append new text to the stream
    pub fn append(self: *StreamingMarkdown, text: []const u8) !void {
        try self.buffer.appendSlice(text);
        try self.processBuffer();
    }

    /// Get currently rendered segments
    pub fn getSegments(self: *StreamingMarkdown) []Segment {
        return self.rendered_segments.items;
    }

    /// Get the incomplete line buffer (for cursor positioning)
    pub fn getIncompleteLine(self: *StreamingMarkdown) []const u8 {
        return self.incomplete_line.items;
    }

    fn processBuffer(self: *StreamingMarkdown) !void {
        // Find complete lines (lines ending with \n)
        var last_newline: ?usize = null;
        for (self.buffer.items, 0..) |char, i| {
            if (char == '\n') last_newline = i;
        }

        if (last_newline) |nl| {
            // Process complete lines
            const complete = self.buffer.items[0 .. nl + 1];
            const segments = try self.renderer.render(complete);

            for (segments) |seg| {
                try self.rendered_segments.append(seg);
            }

            // Keep incomplete part
            self.incomplete_line.clearRetainingCapacity();
            if (nl + 1 < self.buffer.items.len) {
                try self.incomplete_line.appendSlice(self.buffer.items[nl + 1 ..]);
            }

            // Clear processed buffer
            try self.buffer.replaceRange(0, nl + 1, &.{});
        } else {
            // No complete lines, everything is incomplete
            self.incomplete_line.clearRetainingCapacity();
            try self.incomplete_line.appendSlice(self.buffer.items);
        }
    }

    /// Finalize streaming - process any remaining buffer
    pub fn finalize(self: *StreamingMarkdown) ![]Segment {
        if (self.buffer.items.len > 0) {
            const segments = try self.renderer.render(self.buffer.items);
            for (segments) |seg| {
                try self.rendered_segments.append(seg);
            }
            self.buffer.clearRetainingCapacity();
            self.incomplete_line.clearRetainingCapacity();
        }
        return self.rendered_segments.items;
    }

    pub fn clear(self: *StreamingMarkdown) void {
        self.buffer.clearRetainingCapacity();
        // Free old segments
        for (self.rendered_segments.items) |seg| {
            self.allocator.free(seg.text);
            if (seg.link) |link| {
                self.allocator.free(link);
            }
        }
        self.rendered_segments.clearRetainingCapacity();
        self.incomplete_line.clearRetainingCapacity();
    }
};

// Tests
test "streaming markdown - complete lines" {
    const testing = std.testing;
    var stream = StreamingMarkdown.init(testing.allocator);
    defer stream.deinit();

    try stream.append("# Header\n");
    const segments = stream.getSegments();

    try testing.expect(segments.len > 0);
    try testing.expect(segments[0].style.bold);
}

test "streaming markdown - incomplete line" {
    const testing = std.testing;
    var stream = StreamingMarkdown.init(testing.allocator);
    defer stream.deinit();

    try stream.append("This is ");
    const incomplete = stream.getIncompleteLine();
    try testing.expectEqualStrings("This is ", incomplete);

    try stream.append("**bold**");
    const incomplete2 = stream.getIncompleteLine();
    try testing.expectEqualStrings("This is **bold**", incomplete2);
}

test "streaming markdown - finalize" {
    const testing = std.testing;
    var stream = StreamingMarkdown.init(testing.allocator);
    defer stream.deinit();

    try stream.append("Incomplete text");
    const segments = try stream.finalize();

    try testing.expect(segments.len > 0);
}

test "streaming markdown - multiple appends" {
    const testing = std.testing;
    var stream = StreamingMarkdown.init(testing.allocator);
    defer stream.deinit();

    try stream.append("Line 1\n");
    try stream.append("Line 2\n");
    try stream.append("Line 3");

    const segments = stream.getSegments();
    try testing.expect(segments.len > 0);

    const incomplete = stream.getIncompleteLine();
    try testing.expectEqualStrings("Line 3", incomplete);
}

test "streaming markdown - clear" {
    const testing = std.testing;
    var stream = StreamingMarkdown.init(testing.allocator);
    defer stream.deinit();

    try stream.append("Some text\n");
    try testing.expect(stream.getSegments().len > 0);

    stream.clear();
    try testing.expect(stream.getSegments().len == 0);
    try testing.expect(stream.getIncompleteLine().len == 0);
}
