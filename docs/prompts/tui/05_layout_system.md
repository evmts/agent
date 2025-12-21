# 05: Layout System & Widget Composition

## Goal

Implement a flexible layout system for composing the main TUI interface with proper sizing, scrolling, and widget composition.

## Context

- libvaxis vxfw uses a constraint-based layout system similar to Flutter
- Main layout: Header | Chat (scrollable) | Status | Composer
- Modals overlay the main content
- Reference: `/Users/williamcory/plue/libvaxis/src/vxfw/` (framework source)

## Layout Architecture

```
┌──────────────────────────────────────────────────────────┐
│ Header (1 line) - Session info, model, connection        │
├──────────────────────────────────────────────────────────┤
│                                                          │
│ Chat History (flexible height, scrollable)               │
│   - User messages                                        │
│   - Assistant responses                                  │
│   - Tool calls                                           │
│   - Streaming content                                    │
│                                                          │
├──────────────────────────────────────────────────────────┤
│ Status Bar (1 line) - Tokens, status, hints             │
├──────────────────────────────────────────────────────────┤
│ Composer (3+ lines) - Multi-line input                   │
│ > |                                                      │
└──────────────────────────────────────────────────────────┘

Overlay (centered, modal):
┌─────────────────────────┐
│ Title                   │
├─────────────────────────┤
│ List items              │
│ > Selected              │
│   Option 2              │
│   Option 3              │
├─────────────────────────┤
│ Hints: ↑↓ navigate      │
└─────────────────────────┘
```

## Tasks

### 1. Create Base Layout Widget (src/widgets/layout.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

/// Vertical stack layout that allocates space to children
pub const VStack = struct {
    children: []Child,
    spacing: u16 = 0,

    pub const Child = struct {
        widget: vxfw.Widget,
        height: Height,

        pub const Height = union(enum) {
            fixed: u16,
            flex: u16, // flex weight
            fill,      // take remaining space
        };
    };

    pub fn widget(self: *VStack) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = VStack.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *VStack = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        // Calculate fixed heights and flex totals
        var fixed_height: u16 = 0;
        var flex_total: u16 = 0;
        var fill_count: u16 = 0;

        for (self.children) |child| {
            switch (child.height) {
                .fixed => |h| fixed_height += h,
                .flex => |w| flex_total += w,
                .fill => fill_count += 1,
            }
        }

        // Add spacing
        if (self.children.len > 1) {
            fixed_height += @intCast((self.children.len - 1) * self.spacing);
        }

        const remaining = size.height -| fixed_height;
        const flex_unit = if (flex_total > 0) remaining / flex_total else 0;
        const fill_height = if (fill_count > 0)
            (remaining - flex_unit * flex_total) / fill_count
        else
            0;

        // Draw children
        var surfaces = try ctx.arena.alloc(vxfw.SubSurface, self.children.len);
        var y: u16 = 0;

        for (self.children, 0..) |child, i| {
            const child_height: u16 = switch (child.height) {
                .fixed => |h| h,
                .flex => |w| flex_unit * w,
                .fill => fill_height,
            };

            const child_ctx = ctx.withConstraints(
                .{ .width = size.width, .height = child_height },
                .{ .width = size.width, .height = child_height },
            );

            surfaces[i] = .{
                .origin = .{ .row = y, .col = 0 },
                .surface = try child.widget.draw(child_ctx),
            };

            y += child_height + self.spacing;
        }

        return .{
            .size = size,
            .widget = self.widget(),
            .buffer = &.{},
            .children = surfaces,
        };
    }
};

/// Horizontal stack layout
pub const HStack = struct {
    children: []Child,
    spacing: u16 = 0,

    pub const Child = struct {
        widget: vxfw.Widget,
        width: Width,

        pub const Width = union(enum) {
            fixed: u16,
            flex: u16,
            fill,
        };
    };

    pub fn widget(self: *HStack) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = HStack.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *HStack = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var fixed_width: u16 = 0;
        var flex_total: u16 = 0;
        var fill_count: u16 = 0;

        for (self.children) |child| {
            switch (child.width) {
                .fixed => |w| fixed_width += w,
                .flex => |w| flex_total += w,
                .fill => fill_count += 1,
            }
        }

        if (self.children.len > 1) {
            fixed_width += @intCast((self.children.len - 1) * self.spacing);
        }

        const remaining = size.width -| fixed_width;
        const flex_unit = if (flex_total > 0) remaining / flex_total else 0;
        const fill_width = if (fill_count > 0)
            (remaining - flex_unit * flex_total) / fill_count
        else
            0;

        var surfaces = try ctx.arena.alloc(vxfw.SubSurface, self.children.len);
        var x: u16 = 0;

        for (self.children, 0..) |child, i| {
            const child_width: u16 = switch (child.width) {
                .fixed => |w| w,
                .flex => |w| flex_unit * w,
                .fill => fill_width,
            };

            const child_ctx = ctx.withConstraints(
                .{ .width = child_width, .height = size.height },
                .{ .width = child_width, .height = size.height },
            );

            surfaces[i] = .{
                .origin = .{ .row = 0, .col = x },
                .surface = try child.widget.draw(child_ctx),
            };

            x += child_width + self.spacing;
        }

        return .{
            .size = size,
            .widget = self.widget(),
            .buffer = &.{},
            .children = surfaces,
        };
    }
};
```

### 2. Create Scrollable Container (src/widgets/scroll_view.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const ScrollView = struct {
    content: vxfw.Widget,
    scroll_offset: *usize,
    content_height: usize = 0,
    show_scrollbar: bool = true,

    pub fn widget(self: *ScrollView) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = ScrollView.handleEvent,
            .drawFn = ScrollView.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *ScrollView = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.page_up, .{})) {
                    self.scrollUp(10);
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.page_down, .{})) {
                    self.scrollDown(10);
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.home, .{})) {
                    self.scroll_offset.* = 0;
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.end, .{})) {
                    self.scrollToEnd();
                    ctx.consumeAndRedraw();
                }
            },
            .mouse => |mouse| {
                switch (mouse.button) {
                    .wheel_up => {
                        self.scrollUp(3);
                        ctx.consumeAndRedraw();
                    },
                    .wheel_down => {
                        self.scrollDown(3);
                        ctx.consumeAndRedraw();
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *ScrollView = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        // Calculate content width (leave room for scrollbar)
        const content_width = if (self.show_scrollbar) size.width -| 1 else size.width;

        // Draw content with unlimited height to measure
        const content_ctx = ctx.withConstraints(
            .{ .width = content_width, .height = 0 },
            .{ .width = content_width, .height = null }, // unlimited height
        );

        const content_surface = try self.content.draw(content_ctx);
        self.content_height = content_surface.size.height;

        // Clamp scroll offset
        const max_scroll = if (self.content_height > size.height)
            self.content_height - size.height
        else
            0;
        if (self.scroll_offset.* > max_scroll) {
            self.scroll_offset.* = max_scroll;
        }

        // Create viewport surface
        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Copy visible portion of content
        const visible_start = self.scroll_offset.*;
        const visible_end = @min(visible_start + size.height, self.content_height);

        for (visible_start..visible_end) |src_row| {
            const dst_row = src_row - visible_start;
            for (0..content_width) |col| {
                if (content_surface.getCell(@intCast(col), @intCast(src_row))) |cell| {
                    surface.writeCell(@intCast(col), @intCast(dst_row), cell);
                }
            }
        }

        // Draw scrollbar
        if (self.show_scrollbar and self.content_height > size.height) {
            self.drawScrollbar(&surface, size);
        }

        return surface;
    }

    fn drawScrollbar(self: *ScrollView, surface: *vxfw.Surface, size: vxfw.Size) void {
        const col = size.width - 1;

        // Calculate thumb position and size
        const thumb_height = @max(1, size.height * size.height / @as(u16, @intCast(self.content_height)));
        const scroll_range = self.content_height - size.height;
        const thumb_pos = if (scroll_range > 0)
            self.scroll_offset.* * (size.height - thumb_height) / scroll_range
        else
            0;

        // Draw track
        for (0..size.height) |row| {
            const is_thumb = row >= thumb_pos and row < thumb_pos + thumb_height;
            surface.writeCell(col, @intCast(row), .{
                .char = .{ .grapheme = if (is_thumb) "█" else "░", .width = 1 },
                .style = .{ .fg = .{ .index = if (is_thumb) 7 else 8 } },
            });
        }
    }

    fn scrollUp(self: *ScrollView, lines: usize) void {
        if (self.scroll_offset.* >= lines) {
            self.scroll_offset.* -= lines;
        } else {
            self.scroll_offset.* = 0;
        }
    }

    fn scrollDown(self: *ScrollView, lines: usize) void {
        self.scroll_offset.* += lines;
        // Clamping happens in draw
    }

    fn scrollToEnd(self: *ScrollView) void {
        self.scroll_offset.* = std.math.maxInt(usize);
        // Will be clamped in draw
    }

    pub fn ensureVisible(self: *ScrollView, row: usize, viewport_height: usize) void {
        if (row < self.scroll_offset.*) {
            self.scroll_offset.* = row;
        } else if (row >= self.scroll_offset.* + viewport_height) {
            self.scroll_offset.* = row - viewport_height + 1;
        }
    }
};
```

### 3. Create Border Widget (src/widgets/border.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const Border = struct {
    child: vxfw.Widget,
    title: ?[]const u8 = null,
    style: Style = .single,
    color: vaxis.Color = .default,

    pub const Style = enum {
        none,
        single,
        double,
        rounded,
        heavy,
    };

    const Glyphs = struct {
        top_left: []const u8,
        top_right: []const u8,
        bottom_left: []const u8,
        bottom_right: []const u8,
        horizontal: []const u8,
        vertical: []const u8,
    };

    const glyphs = struct {
        const single: Glyphs = .{
            .top_left = "┌",
            .top_right = "┐",
            .bottom_left = "└",
            .bottom_right = "┘",
            .horizontal = "─",
            .vertical = "│",
        };
        const double: Glyphs = .{
            .top_left = "╔",
            .top_right = "╗",
            .bottom_left = "╚",
            .bottom_right = "╝",
            .horizontal = "═",
            .vertical = "║",
        };
        const rounded: Glyphs = .{
            .top_left = "╭",
            .top_right = "╮",
            .bottom_left = "╰",
            .bottom_right = "╯",
            .horizontal = "─",
            .vertical = "│",
        };
        const heavy: Glyphs = .{
            .top_left = "┏",
            .top_right = "┓",
            .bottom_left = "┗",
            .bottom_right = "┛",
            .horizontal = "━",
            .vertical = "┃",
        };
    };

    pub fn widget(self: *Border) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = Border.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *Border = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        if (self.style == .none) {
            return try self.child.draw(ctx);
        }

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        const g = switch (self.style) {
            .single => glyphs.single,
            .double => glyphs.double,
            .rounded => glyphs.rounded,
            .heavy => glyphs.heavy,
            .none => unreachable,
        };

        const style = vaxis.Cell.Style{ .fg = self.color };

        // Draw corners
        surface.writeCell(0, 0, .{
            .char = .{ .grapheme = g.top_left, .width = 1 },
            .style = style,
        });
        surface.writeCell(size.width - 1, 0, .{
            .char = .{ .grapheme = g.top_right, .width = 1 },
            .style = style,
        });
        surface.writeCell(0, size.height - 1, .{
            .char = .{ .grapheme = g.bottom_left, .width = 1 },
            .style = style,
        });
        surface.writeCell(size.width - 1, size.height - 1, .{
            .char = .{ .grapheme = g.bottom_right, .width = 1 },
            .style = style,
        });

        // Draw horizontal lines
        for (1..size.width - 1) |col| {
            surface.writeCell(@intCast(col), 0, .{
                .char = .{ .grapheme = g.horizontal, .width = 1 },
                .style = style,
            });
            surface.writeCell(@intCast(col), size.height - 1, .{
                .char = .{ .grapheme = g.horizontal, .width = 1 },
                .style = style,
            });
        }

        // Draw vertical lines
        for (1..size.height - 1) |row| {
            surface.writeCell(0, @intCast(row), .{
                .char = .{ .grapheme = g.vertical, .width = 1 },
                .style = style,
            });
            surface.writeCell(size.width - 1, @intCast(row), .{
                .char = .{ .grapheme = g.horizontal, .width = 1 },
                .style = style,
            });
        }

        // Draw title
        if (self.title) |title| {
            const title_start = 2;
            for (title, 0..) |char, i| {
                if (title_start + i >= size.width - 2) break;
                surface.writeCell(@intCast(title_start + i), 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = self.color, .bold = true },
                });
            }
        }

        // Draw child in inner area
        const inner_ctx = ctx.withConstraints(
            .{ .width = size.width -| 2, .height = size.height -| 2 },
            .{ .width = size.width -| 2, .height = size.height -| 2 },
        );

        const child_surface = try self.child.draw(inner_ctx);

        const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
        children[0] = .{
            .origin = .{ .row = 1, .col = 1 },
            .surface = child_surface,
        };

        return .{
            .size = size,
            .widget = self.widget(),
            .buffer = surface.buffer,
            .children = children,
        };
    }
};
```

### 4. Create Modal Overlay (src/widgets/modal.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const Border = @import("border.zig").Border;

pub const Modal = struct {
    content: vxfw.Widget,
    title: []const u8,
    width: Width = .{ .percentage = 60 },
    height: Height = .{ .percentage = 60 },
    on_close: ?*const fn () void = null,

    pub const Width = union(enum) {
        fixed: u16,
        percentage: u8,
    };

    pub const Height = union(enum) {
        fixed: u16,
        percentage: u8,
    };

    pub fn widget(self: *Modal) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Modal.handleEvent,
            .drawFn = Modal.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *Modal = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.escape, .{})) {
                    if (self.on_close) |close| {
                        close();
                    }
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *Modal = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        // Calculate modal size
        const modal_width: u16 = switch (self.width) {
            .fixed => |w| @min(w, size.width),
            .percentage => |p| size.width * p / 100,
        };
        const modal_height: u16 = switch (self.height) {
            .fixed => |h| @min(h, size.height),
            .percentage => |p| size.height * p / 100,
        };

        // Calculate position (centered)
        const x = (size.width -| modal_width) / 2;
        const y = (size.height -| modal_height) / 2;

        // Create surface with dimmed background
        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Draw dim background
        const dim_style = vaxis.Cell.Style{ .bg = .{ .rgb = .{ 0, 0, 0 } }, .dim = true };
        for (0..size.height) |row| {
            for (0..size.width) |col| {
                surface.writeCell(@intCast(col), @intCast(row), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = dim_style,
                });
            }
        }

        // Draw modal content with border
        var border = Border{
            .child = self.content,
            .title = self.title,
            .style = .rounded,
            .color = .{ .index = 14 }, // Cyan
        };

        const modal_ctx = ctx.withConstraints(
            .{ .width = modal_width, .height = modal_height },
            .{ .width = modal_width, .height = modal_height },
        );

        const modal_surface = try border.widget().draw(modal_ctx);

        const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
        children[0] = .{
            .origin = .{ .row = y, .col = x },
            .surface = modal_surface,
        };

        return .{
            .size = size,
            .widget = self.widget(),
            .buffer = surface.buffer,
            .children = children,
        };
    }
};
```

### 5. Create Main Layout (src/widgets/main_layout.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const VStack = @import("layout.zig").VStack;
const ScrollView = @import("scroll_view.zig").ScrollView;
const Modal = @import("modal.zig").Modal;

const AppState = @import("../state/app_state.zig").AppState;

pub const MainLayout = struct {
    state: *AppState,

    // Child widgets (to be created in later prompts)
    header: vxfw.Widget,
    chat_history: vxfw.Widget,
    status_bar: vxfw.Widget,
    composer: vxfw.Widget,

    // Overlay
    active_modal: ?Modal = null,

    // Internal
    scroll_offset: usize = 0,
    scroll_view: ?ScrollView = null,
    vstack: ?VStack = null,

    pub fn widget(self: *MainLayout) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = MainLayout.handleEvent,
            .drawFn = MainLayout.draw,
        };
    }

    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *MainLayout = @ptrCast(@alignCast(ptr));

        // If modal is active, delegate to modal first
        if (self.active_modal != null) {
            // Modal handles ESC to close
            switch (event) {
                .key_press => |key| {
                    if (key.matches(vaxis.Key.escape, .{})) {
                        self.active_modal = null;
                        self.state.mode = .chat;
                        ctx.consumeAndRedraw();
                        return;
                    }
                },
                else => {},
            }
        }

        // Scroll handling
        if (self.scroll_view) |*sv| {
            try sv.widget().eventHandler.?(sv, ctx, event);
        }
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *MainLayout = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        // Layout configuration
        const header_height: u16 = 1;
        const status_height: u16 = 1;
        const composer_height: u16 = 3;

        // Create scroll view for chat
        self.scroll_view = ScrollView{
            .content = self.chat_history,
            .scroll_offset = &self.scroll_offset,
            .show_scrollbar = true,
        };

        // Build VStack layout
        var children = [_]VStack.Child{
            .{ .widget = self.header, .height = .{ .fixed = header_height } },
            .{ .widget = self.scroll_view.?.widget(), .height = .fill },
            .{ .widget = self.status_bar, .height = .{ .fixed = status_height } },
            .{ .widget = self.composer, .height = .{ .fixed = composer_height } },
        };

        self.vstack = VStack{
            .children = &children,
            .spacing = 0,
        };

        var main_surface = try self.vstack.?.widget().draw(ctx);

        // Add modal overlay if active
        if (self.active_modal) |*modal| {
            const modal_surface = try modal.widget().draw(ctx);

            // Composite modal over main
            const combined = try ctx.arena.alloc(vxfw.SubSurface, 2);
            combined[0] = .{
                .origin = .{ .row = 0, .col = 0 },
                .surface = main_surface,
            };
            combined[1] = .{
                .origin = .{ .row = 0, .col = 0 },
                .surface = modal_surface,
            };

            return .{
                .size = size,
                .widget = self.widget(),
                .buffer = &.{},
                .children = combined,
            };
        }

        return main_surface;
    }

    pub fn showModal(self: *MainLayout, title: []const u8, content: vxfw.Widget) void {
        self.active_modal = Modal{
            .content = content,
            .title = title,
        };
    }

    pub fn closeModal(self: *MainLayout) void {
        self.active_modal = null;
    }

    pub fn scrollToBottom(self: *MainLayout) void {
        self.scroll_offset = std.math.maxInt(usize);
    }
};
```

## Acceptance Criteria

- [ ] VStack properly allocates space with fixed/flex/fill
- [ ] HStack properly allocates horizontal space
- [ ] ScrollView handles scrolling with keyboard and mouse
- [ ] ScrollView shows scrollbar when content overflows
- [ ] Border widget draws correct glyphs
- [ ] Modal overlay centers and dims background
- [ ] MainLayout composes header/chat/status/composer
- [ ] Modal can be shown/hidden over main content

## Files to Create

1. `tui-zig/src/widgets/layout.zig`
2. `tui-zig/src/widgets/scroll_view.zig`
3. `tui-zig/src/widgets/border.zig`
4. `tui-zig/src/widgets/modal.zig`
5. `tui-zig/src/widgets/main_layout.zig`

## Next

Proceed to `06_chat_history.md` to implement the chat history widget.
