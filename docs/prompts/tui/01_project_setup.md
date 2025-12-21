# 01: Project Setup & Build Integration

## Goal

Set up the Zig TUI project structure, integrate libvaxis as a dependency, and configure the build system.

## Context

- libvaxis is already cloned at `/Users/williamcory/plue/libvaxis/`
- The root `build.zig` manages all project builds
- The new TUI should be at `/Users/williamcory/plue/tui-zig/`

## Tasks

### 1. Create Project Structure

```bash
mkdir -p tui-zig/src/{client,state,widgets,render,utils}
```

Create initial files:
- `tui-zig/src/main.zig` - Entry point
- `tui-zig/build.zig` - Build configuration
- `tui-zig/build.zig.zon` - Dependencies

### 2. Configure build.zig.zon

```zig
.{
    .name = "plue-tui",
    .version = "0.1.0",
    .dependencies = .{
        .vaxis = .{
            .path = "../libvaxis",
        },
    },
    .paths = .{"."},
}
```

### 3. Configure build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get libvaxis dependency
    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "plue-tui",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add vaxis module
    exe.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the TUI");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
}
```

### 4. Create Minimal main.zig

```zig
const std = @import("std");
const vaxis = @import("vaxis");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Parse CLI arguments
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    // TODO: Parse --api-url, --help, --version

    // Initialize vxfw app
    var app = try vaxis.vxfw.App.init(alloc);
    defer app.deinit();

    // Create root widget (placeholder)
    var root = PlaceholderWidget{};

    try app.run(root.widget(), .{});
}

const PlaceholderWidget = struct {
    pub fn widget(self: *PlaceholderWidget) vaxis.vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = draw,
        };
    }

    fn draw(_: *anyopaque, ctx: vaxis.vxfw.DrawContext) !vaxis.vxfw.Surface {
        const size = ctx.max.size();
        var surface = try vaxis.vxfw.Surface.init(ctx.arena, .{
            .userdata = null,
            .drawFn = undefined,
        }, size);

        // Draw "Hello Plue TUI"
        const text = "Hello Plue TUI - Press Ctrl+C to exit";
        const col = (size.width -| @as(u16, @intCast(text.len))) / 2;
        const row = size.height / 2;

        for (text, 0..) |char, i| {
            surface.writeCell(@intCast(col + i), row, .{
                .char = .{ .grapheme = &[_]u8{char}, .width = 1 },
                .style = .{ .fg = .{ .rgb = .{ 0, 255, 128 } } },
            });
        }

        return surface;
    }
};
```

### 5. Integrate with Root build.zig

Add to the root `/Users/williamcory/plue/build.zig`:

```zig
// TUI build step
const tui_step = b.step("tui", "Build Zig TUI");
// ... add dependency on tui-zig/build.zig
```

### 6. Test the Build

```bash
cd tui-zig
zig build run
```

Should display "Hello Plue TUI" centered in the terminal.

## Acceptance Criteria

- [ ] Project structure created at `tui-zig/`
- [ ] libvaxis successfully imported
- [ ] `zig build` compiles without errors
- [ ] `zig build run` displays placeholder UI
- [ ] `zig build test` runs (even if no tests yet)
- [ ] Integration with root build.zig works

## Files to Create

1. `tui-zig/build.zig.zon`
2. `tui-zig/build.zig`
3. `tui-zig/src/main.zig`

## Next

Proceed to `02_core_app_structure.md` to implement the main App widget and state management.
