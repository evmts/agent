# 08: Header & Status Bar Widgets

## Goal

Implement the header bar (session info) and status bar (tokens, status, hints) widgets.

## Context

- Header shows: session name/id, model, connection status, directory
- Status bar shows: streaming status, token usage, keyboard hints
- Reference: codex TUI footer and header components

## Tasks

### 1. Create Header Widget (src/widgets/header.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const AppState = @import("../state/app_state.zig").AppState;
const Session = @import("../state/session_manager.zig").Session;

pub const Header = struct {
    state: *AppState,

    pub fn widget(self: *Header) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = Header.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *Header = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Fill background
        const bg_style = vaxis.Cell.Style{ .bg = .{ .index = 0 } };
        for (0..size.width) |col| {
            surface.writeCell(@intCast(col), 0, .{
                .char = .{ .grapheme = " ", .width = 1 },
                .style = bg_style,
            });
        }

        var col: u16 = 0;

        // Draw logo/name
        const logo = "⚡ Plue";
        for (logo) |char| {
            if (col >= size.width) break;
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = if (col == 0) "⚡" else &[_]u8{char}, .width = if (col == 0) 2 else 1 },
                .style = .{ .fg = .{ .index = 14 }, .bold = true },
            });
            col += if (col == 0) 2 else 1;
        }
        col += 1;

        // Draw separator
        surface.writeCell(col, 0, .{
            .char = .{ .grapheme = "│", .width = 1 },
            .style = .{ .fg = .{ .index = 8 } },
        });
        col += 2;

        // Draw session info
        if (self.state.currentSession()) |session| {
            // Session title or ID
            const title = session.title orelse session.id;
            const title_max = @min(title.len, 20);
            for (title[0..title_max]) |char| {
                if (col >= size.width - 30) break;
                surface.writeCell(col, 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 7 } },
                });
                col += 1;
            }
            if (title.len > 20) {
                for ("...") |char| {
                    surface.writeCell(col, 0, .{
                        .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                        .style = .{ .fg = .{ .index = 8 } },
                    });
                    col += 1;
                }
            }
            col += 1;

            // Separator
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = "│", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
            col += 2;

            // Model name (short form)
            const model_short = getShortModelName(session.model);
            for (model_short) |char| {
                if (col >= size.width - 15) break;
                surface.writeCell(col, 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 13 } },
                });
                col += 1;
            }
        } else {
            const no_session = "No session";
            for (no_session) |char| {
                surface.writeCell(col, 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 }, .italic = true },
                });
                col += 1;
            }
        }

        // Draw connection status (right-aligned)
        const status = self.getConnectionStatus();
        const status_col = size.width -| @as(u16, @intCast(status.text.len + 2));

        // Status icon
        surface.writeCell(status_col, 0, .{
            .char = .{ .grapheme = status.icon, .width = 1 },
            .style = .{ .fg = status.color },
        });

        // Status text
        for (status.text, 0..) |char, i| {
            surface.writeCell(@intCast(status_col + 1 + i), 0, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = status.color },
            });
        }

        return surface;
    }

    const ConnectionStatus = struct {
        icon: []const u8,
        text: []const u8,
        color: vaxis.Color,
    };

    fn getConnectionStatus(self: *Header) ConnectionStatus {
        return switch (self.state.connection) {
            .disconnected => .{
                .icon = "○",
                .text = "Disconnected",
                .color = .{ .index = 8 },
            },
            .connecting => .{
                .icon = "◐",
                .text = "Connecting...",
                .color = .{ .index = 11 },
            },
            .connected => .{
                .icon = "●",
                .text = "Connected",
                .color = .{ .index = 10 },
            },
            .reconnecting => .{
                .icon = "◐",
                .text = "Reconnecting...",
                .color = .{ .index = 11 },
            },
            .error => .{
                .icon = "✗",
                .text = "Error",
                .color = .{ .index = 9 },
            },
        };
    }

    fn getShortModelName(model: []const u8) []const u8 {
        if (std.mem.indexOf(u8, model, "sonnet-4")) |_| return "sonnet-4";
        if (std.mem.indexOf(u8, model, "opus-4")) |_| return "opus-4";
        if (std.mem.indexOf(u8, model, "sonnet")) |_| return "sonnet-3.5";
        if (std.mem.indexOf(u8, model, "haiku")) |_| return "haiku-3.5";
        if (model.len > 15) return model[0..15];
        return model;
    }
};
```

### 2. Create Status Bar Widget (src/widgets/status_bar.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const AppState = @import("../state/app_state.zig").AppState;

pub const StatusBar = struct {
    state: *AppState,
    spinner_frame: usize = 0,

    const SPINNER_FRAMES = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };

    pub fn widget(self: *StatusBar) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = StatusBar.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *StatusBar = @ptrCast(@alignCast(ptr));
        const size = ctx.max.size();

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);

        // Fill background
        const bg_style = vaxis.Cell.Style{ .bg = .{ .index = 0 }, .fg = .{ .index = 8 } };
        for (0..size.width) |col| {
            surface.writeCell(@intCast(col), 0, .{
                .char = .{ .grapheme = " ", .width = 1 },
                .style = bg_style,
            });
        }

        var col: u16 = 0;

        // Draw streaming status if active
        if (self.state.isStreaming()) {
            // Spinner
            const frame = SPINNER_FRAMES[self.spinner_frame % SPINNER_FRAMES.len];
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = frame, .width = 1 },
                .style = .{ .fg = .{ .index = 14 } },
            });
            col += 2;

            // Status text
            const status_text = "Generating...";
            for (status_text) |char| {
                surface.writeCell(col, 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 14 } },
                });
                col += 1;
            }

            self.spinner_frame += 1;
        }

        // Draw token usage (right side)
        const usage = self.state.token_usage;
        if (usage.total() > 0) {
            const token_text = self.formatTokens(usage, ctx.arena) catch "tokens: --";
            const token_col = size.width -| @as(u16, @intCast(token_text.len + 1));

            for (token_text, 0..) |char, i| {
                surface.writeCell(@intCast(token_col + i), 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
            }
        }

        // Draw error message if present
        if (self.state.last_error) |err| {
            col = 0;
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = "✗", .width = 1 },
                .style = .{ .fg = .{ .index = 9 } },
            });
            col += 2;

            const err_max = @min(err.len, size.width - 20);
            for (err[0..err_max]) |char| {
                surface.writeCell(col, 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 9 } },
                });
                col += 1;
            }
        }

        return surface;
    }

    fn formatTokens(self: *StatusBar, usage: AppState.TokenUsage, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return std.fmt.allocPrint(allocator, "↓{d} ↑{d} = {d}", .{
            usage.input,
            usage.output,
            usage.total(),
        });
    }

    pub fn tick(self: *StatusBar) void {
        if (self.state.isStreaming()) {
            self.spinner_frame += 1;
        }
    }
};
```

### 3. Create Progress Indicator (src/widgets/progress.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const ProgressIndicator = struct {
    progress: f32 = 0, // 0.0 to 1.0
    label: ?[]const u8 = null,
    style: Style = .bar,
    width: u16 = 20,

    pub const Style = enum {
        bar,      // [████░░░░░░]
        spinner,  // ⠋ Loading...
        dots,     // Loading...
    };

    pub fn widget(self: *ProgressIndicator) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = ProgressIndicator.draw,
        };
    }

    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
        const self: *ProgressIndicator = @ptrCast(@alignCast(ptr));

        const height: u16 = 1;
        const width = self.width;

        var surface = try vxfw.Surface.init(ctx.arena, self.widget(), .{
            .width = width,
            .height = height,
        });

        switch (self.style) {
            .bar => self.drawBar(&surface, width),
            .spinner => self.drawSpinner(&surface, width),
            .dots => self.drawDots(&surface, width),
        }

        return surface;
    }

    fn drawBar(self: *ProgressIndicator, surface: *vxfw.Surface, width: u16) void {
        const bar_width = width -| 2; // Account for brackets
        const filled = @as(u16, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * self.progress));

        // Opening bracket
        surface.writeCell(0, 0, .{
            .char = .{ .grapheme = "[", .width = 1 },
            .style = .{ .fg = .{ .index = 8 } },
        });

        // Progress
        var col: u16 = 1;
        while (col < filled + 1) : (col += 1) {
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = "█", .width = 1 },
                .style = .{ .fg = .{ .index = 10 } },
            });
        }
        while (col < bar_width + 1) : (col += 1) {
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = "░", .width = 1 },
                .style = .{ .fg = .{ .index = 8 } },
            });
        }

        // Closing bracket
        surface.writeCell(width - 1, 0, .{
            .char = .{ .grapheme = "]", .width = 1 },
            .style = .{ .fg = .{ .index = 8 } },
        });
    }

    fn drawSpinner(self: *ProgressIndicator, surface: *vxfw.Surface, _: u16) void {
        const frames = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
        const frame_idx = @as(usize, @intFromFloat(self.progress * 10)) % frames.len;

        surface.writeCell(0, 0, .{
            .char = .{ .grapheme = frames[frame_idx], .width = 1 },
            .style = .{ .fg = .{ .index = 14 } },
        });

        if (self.label) |label| {
            var col: u16 = 2;
            for (label) |char| {
                surface.writeCell(col, 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 7 } },
                });
                col += 1;
            }
        }
    }

    fn drawDots(self: *ProgressIndicator, surface: *vxfw.Surface, _: u16) void {
        const dot_count = @as(usize, @intFromFloat(self.progress * 3)) + 1;
        const dots = switch (dot_count) {
            1 => ".",
            2 => "..",
            else => "...",
        };

        if (self.label) |label| {
            var col: u16 = 0;
            for (label) |char| {
                surface.writeCell(col, 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 7 } },
                });
                col += 1;
            }
            for (dots) |char| {
                surface.writeCell(col, 0, .{
                    .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
                col += 1;
            }
        }
    }
};
```

## Acceptance Criteria

- [ ] Header shows logo, session title, model name
- [ ] Header shows connection status with icon
- [ ] Status bar shows spinner when streaming
- [ ] Status bar shows token usage
- [ ] Status bar shows error messages
- [ ] Model name abbreviated to short form
- [ ] Session title truncated with ellipsis if too long
- [ ] Progress indicator supports bar, spinner, dots styles

## Files to Create

1. `tui-zig/src/widgets/header.zig`
2. `tui-zig/src/widgets/status_bar.zig`
3. `tui-zig/src/widgets/progress.zig`

## Next

Proceed to `09_markdown_renderer.md` for markdown rendering.
