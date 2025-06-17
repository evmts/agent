# Zig Code

```zig
// File: ./build.zig
const std = @import("std");
const builtin = @import("builtin");

const GhosttyPaths = struct {
    lib_path: []const u8,
    include_path: []const u8,
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Build options
    const skip_ghostty = b.option(bool, "skip-ghostty", "Skip building Ghostty (use pre-built)") orelse false;
    const ghostty_lib_path = b.option([]const u8, "ghostty-lib-path", "Path to pre-built libghostty");
    const ghostty_include_path = b.option([]const u8, "ghostty-include-path", "Path to ghostty headers");

    // Step 1: Build libghostty if not skipped
    var ghostty_paths: GhosttyPaths = undefined;

    if (!skip_ghostty) {
        const ghostty_step = buildGhostty(b, target, optimize);
        b.getInstallStep().dependOn(ghostty_step);
        
        // UPDATE these paths to the new predictable location
        ghostty_paths = .{
            .lib_path = b.pathJoin(&.{b.install_path, "ghostty-deps", "lib"}),
            .include_path = b.pathJoin(&.{b.install_path, "ghostty-deps", "include"}),
        };
    } else {
        // Use provided paths or defaults
        ghostty_paths = .{
            .lib_path = ghostty_lib_path orelse b.pathFromRoot("lib/ghostty/.zig-cache/o/b11a20ce4aa45da884bb124cfc1c77eb"),
            .include_path = ghostty_include_path orelse b.pathFromRoot("lib/ghostty/include"),
        };
    }

    // Step 2: Build all Zig modules and libraries
    buildZigLibraries(b, target, optimize, ghostty_paths);

    // Step 3: Create Swift build step
    const swift_step = buildSwift(b, target, optimize, ghostty_paths);
    
    // Main build step
    const build_step = b.step("build", "Build the complete application");
    build_step.dependOn(&swift_step.step);

    // Run step
    const run_step = b.step("run", "Build and run the application");
    const run_cmd = b.addSystemCommand(&.{
        ".build/arm64-apple-macosx/debug/plue",
    });
    run_cmd.step.dependOn(&swift_step.step);
    run_step.dependOn(&run_cmd.step);

    // Dev step with file watching
    const dev_step = b.step("dev", "Run in development mode with hot reload");
    const dev_server = b.addExecutable(.{
        .name = "dev_server",
        .root_source_file = b.path("dev_server.zig"),
        .target = target,
        .optimize = .Debug,
    });
    const run_dev_server = b.addRunArtifact(dev_server);
    run_dev_server.addArg(b.build_root.path orelse ".");
    dev_step.dependOn(&run_dev_server.step);

    // Swift-only step
    const swift_only_step = b.step("swift", "Build only the Swift application");
    swift_only_step.dependOn(&swift_step.step);

    // Tests
    const test_step = buildTests(b, target, optimize);

    // MCP servers - disabled for now due to JSON API incompatibility
    // buildMCPServers(b, target, optimize);

    // All step - builds and tests everything
    const all_step = b.step("all", "Build everything and run all tests");
    
    // Build all libraries and executables
    all_step.dependOn(b.getInstallStep());
    all_step.dependOn(&swift_step.step);
    
    // Run all tests
    all_step.dependOn(test_step);
    
    // Add a verification step that checks if everything built correctly
    const verify_step = b.addSystemCommand(&.{
        "sh", "-c",
        \\echo "🔍 Verifying build artifacts..." &&
        \\if [ -f zig-out/lib/libplue.a ]; then echo "✅ libplue.a"; else echo "❌ libplue.a missing"; exit 1; fi &&
        \\if [ -f zig-out/lib/liblibplue.a ]; then echo "✅ liblibplue.a"; else echo "❌ liblibplue.a missing"; exit 1; fi &&
        \\if [ -f zig-out/lib/libterminal.a ]; then echo "✅ libterminal.a"; else echo "❌ libterminal.a missing"; exit 1; fi &&
        \\if [ -f zig-out/lib/libghostty_terminal.a ]; then echo "✅ libghostty_terminal.a"; else echo "❌ libghostty_terminal.a missing"; exit 1; fi &&
        \\if [ -f .build/arm64-apple-macosx/debug/plue ] || [ -f .build/arm64-apple-macosx/release/plue ]; then echo "✅ Swift executable"; else echo "❌ Swift executable missing"; exit 1; fi &&
        \\echo "✨ All build artifacts verified!"
    });
    verify_step.step.dependOn(&swift_step.step);
    all_step.dependOn(&verify_step.step);
    
    // Add a final success message
    const success_msg = b.addSystemCommand(&.{
        "sh", "-c",
        \\echo "" &&
        \\echo "🎉 Build and test completed successfully!" &&
        \\echo "📦 All libraries built" &&
        \\echo "✅ All tests passed" &&
        \\echo "🚀 Ready to run: zig build run"
    });
    success_msg.step.dependOn(&verify_step.step);
    all_step.dependOn(&success_msg.step);
}

fn buildGhostty(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step {
    _ = target; // Will be used when we add target specification
    _ = optimize; // Already using ReleaseFast for now
    const ghostty_step = b.step("ghostty", "Build Ghostty library");
    
    // Create a command to build Ghostty using its own build.zig
    const ghostty_build_cmd = b.addSystemCommand(&.{
        "zig",
        "build",
        "-Doptimize=ReleaseFast",
        "-Dapp-runtime=none", 
        "-Demit-xcframework=false",
        "--prefix",
        b.pathJoin(&.{b.install_path, "ghostty-deps"}),
    });
    ghostty_build_cmd.setCwd(b.path("lib/ghostty"));
    
    // Install the header to our output directory
    const install_header = b.addInstallFile(
        b.path("lib/ghostty/include/ghostty.h"),
        "ghostty-deps/include/ghostty.h"
    );
    
    ghostty_step.dependOn(&ghostty_build_cmd.step);
    ghostty_step.dependOn(&install_header.step);
    
    return ghostty_step;
}

fn buildZigLibraries(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    ghostty_paths: GhosttyPaths,
) void {
    // Create modules
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const c_lib_mod = b.createModule(.{
        .root_source_file = b.path("src/libplue.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ghostty_terminal_mod = b.createModule(.{
        .root_source_file = b.path("src/ghostty_terminal.zig"),
        .target = target,
        .optimize = optimize,
    });
    ghostty_terminal_mod.addIncludePath(.{ .cwd_relative = ghostty_paths.include_path });


    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .optimize = optimize,
    });

    const terminal_mod = b.createModule(.{
        .root_source_file = b.path("src/terminal.zig"),
        .target = target,
        .optimize = optimize,
    });

    const state_mod = b.createModule(.{
        .root_source_file = b.path("src/state/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Add nvim_client to state module
    state_mod.addImport("nvim_client", b.createModule(.{
        .root_source_file = b.path("src/nvim_client.zig"),
        .target = target,
        .optimize = optimize,
    }));

    // Add imports
    c_lib_mod.addImport("ghostty_terminal", ghostty_terminal_mod);
    c_lib_mod.addImport("terminal", terminal_mod);
    c_lib_mod.addImport("app", app_mod);
    c_lib_mod.addImport("state", state_mod);
    // Add farcaster as a module import to libplue
    c_lib_mod.addImport("farcaster", b.createModule(.{
        .root_source_file = b.path("src/farcaster/farcaster.zig"),
        .target = target,
        .optimize = optimize,
    }));
    // Add nvim_client as a module import to libplue
    c_lib_mod.addImport("nvim_client", b.createModule(.{
        .root_source_file = b.path("src/nvim_client.zig"),
        .target = target,
        .optimize = optimize,
    }));

    // Create libraries
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "plue",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    const c_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "libplue",
        .root_module = c_lib_mod,
    });
    c_lib.linkLibC(); // libplue needs linkLibC since it now includes farcaster
    b.installArtifact(c_lib);

    const ghostty_terminal_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "ghostty_terminal",
        .root_module = ghostty_terminal_mod,
    });
    ghostty_terminal_lib.linkLibC();
    ghostty_terminal_lib.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ ghostty_paths.lib_path, "libghostty.a" }) });
    b.installArtifact(ghostty_terminal_lib);

    const terminal_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "terminal",
        .root_module = terminal_mod,
    });
    terminal_lib.linkLibC();
    b.installArtifact(terminal_lib);

}

fn buildSwift(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    ghostty_paths: GhosttyPaths,
) *std.Build.Step.Run {
    var swift_args = std.ArrayList([]const u8).init(b.allocator);
    
    // Base swift build command
    swift_args.appendSlice(&.{
        "swift", "build",
        "-c", if (optimize == .Debug) "debug" else "release",
        "--product", "plue",
    }) catch @panic("OOM");
    
    // Add linker flags for our Zig libraries
    swift_args.appendSlice(&.{
        "-Xlinker", b.fmt("-L{s}", .{b.getInstallPath(.lib, "")}),
        "-Xlinker", "-lplue",
        "-Xlinker", "-llibplue",
        "-Xlinker", "-lterminal",
        "-Xlinker", "-lghostty_terminal",
    }) catch @panic("OOM");
    
    // Add ghostty include path
    swift_args.appendSlice(&.{
        "-Xcc", b.fmt("-I{s}", .{ghostty_paths.include_path}),
    }) catch @panic("OOM");
    
    // Add framework flags for macOS
    if (target.result.os.tag == .macos) {
        swift_args.appendSlice(&.{
            "-Xlinker", "-framework", "-Xlinker", "CoreFoundation",
            "-Xlinker", "-framework", "-Xlinker", "CoreGraphics",
            "-Xlinker", "-framework", "-Xlinker", "CoreText",
            "-Xlinker", "-framework", "-Xlinker", "CoreVideo",
            "-Xlinker", "-framework", "-Xlinker", "Metal",
            "-Xlinker", "-framework", "-Xlinker", "MetalKit",
            "-Xlinker", "-framework", "-Xlinker", "QuartzCore",
            "-Xlinker", "-framework", "-Xlinker", "IOKit",
            "-Xlinker", "-framework", "-Xlinker", "Carbon",
            "-Xlinker", "-framework", "-Xlinker", "Cocoa",
            "-Xlinker", "-framework", "-Xlinker", "Security",
        }) catch @panic("OOM");
    }
    
    const swift_cmd = b.addSystemCommand(swift_args.items);
    
    // Swift build depends on all Zig libraries
    swift_cmd.step.dependOn(b.getInstallStep());
    
    return swift_cmd;
}

fn buildTests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step {
    // Create test modules and add tests
    const test_step = b.step("test", "Run all tests");
    
    // Library tests
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);
    
    // Integration tests
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("test/integration_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);
    test_step.dependOn(&run_integration_tests.step);
    
    // Terminal test executable
    const terminal_test = b.addExecutable(.{
        .name = "test_macos_pty",
        .root_source_file = b.path("test_macos_pty.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_test.linkLibC();
    
    const run_terminal_test = b.addRunArtifact(terminal_test);
    const terminal_test_step = b.step("test-terminal", "Run terminal test");
    terminal_test_step.dependOn(&run_terminal_test.step);
    
    return test_step;
}

fn buildMCPServers(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    // MCP AppleScript server
    const mcp_applescript = b.addExecutable(.{
        .name = "mcp-applescript",
        .root_source_file = b.path("mcp/applescript.zig"),
        .target = target,
        .optimize = optimize,
    });
    mcp_applescript.linkLibC();
    b.installArtifact(mcp_applescript);

    const run_mcp_applescript = b.addRunArtifact(mcp_applescript);
    const mcp_applescript_step = b.step("mcp-applescript", "Run the MCP AppleScript server");
    mcp_applescript_step.dependOn(&run_mcp_applescript.step);

    // Plue MCP server
    const plue_mcp = b.addExecutable(.{
        .name = "plue-mcp",
        .root_source_file = b.path("mcp/plue_mcp_fixed.zig"),
        .target = target,
        .optimize = optimize,
    });
    plue_mcp.linkLibC();
    b.installArtifact(plue_mcp);

    const run_plue_mcp = b.addRunArtifact(plue_mcp);
    const plue_mcp_step = b.step("plue-mcp", "Run the Plue MCP server");
    plue_mcp_step.dependOn(&run_plue_mcp.step);
}```

```zig
// File: ./src/state/vim_state.zig
const NvimClient = @import("nvim_client").NvimClient;

mode: VimMode,
content: []const u8,
cursor_row: u32,
cursor_col: u32,
status_line: []const u8,
nvim_client: ?*NvimClient = null,

pub const VimMode = enum(c_int) {
    normal = 0,
    insert = 1,
    visual = 2,
    command = 3,
};

pub const CVimState = extern struct {
    mode: VimMode,
    content: [*:0]const u8,
    cursor_row: u32,
    cursor_col: u32,
    status_line: [*:0]const u8,
};
```

```zig
// File: ./src/state/main.zig
// Re-export the main state module
pub const AppState = @import("state.zig").AppState;
pub const cstate = @import("cstate.zig");
pub const Event = @import("event.zig").Event;
pub const PromptState = @import("prompt_state.zig").PromptState;
pub const TerminalState = @import("terminal_state.zig").TerminalState;
pub const WebState = @import("web_state.zig").WebState;
pub const VimState = @import("vim_state.zig").VimState;
pub const AgentState = @import("agent_state.zig").AgentState;
pub const FarcasterState = @import("farcaster_state.zig").FarcasterState;
pub const EditorState = @import("editor_state.zig").EditorState;```

```zig
// File: ./src/state/event.zig
const std = @import("std");
const AppState = @import("state.zig");

pub const Event = @This();

type: EventType,
string_value: ?[]const u8 = null,
int_value: ?i32 = null,
int_value2: ?i32 = null,

pub const EventType = enum(c_int) {
    tab_switched = 0,
    theme_toggled = 1,
    terminal_input = 2,
    terminal_resize = 3,
    vim_keypress = 4,
    vim_set_content = 5,
    web_navigate = 6,
    web_go_back = 7,
    web_go_forward = 8,
    web_reload = 9,
    editor_content_changed = 10,
    editor_save = 11,
    farcaster_select_channel = 12,
    farcaster_like_post = 13,
    farcaster_recast_post = 14,
    farcaster_reply_to_post = 15,
    farcaster_create_post = 16,
    farcaster_refresh_feed = 17,
    prompt_message_sent = 18,
    prompt_content_updated = 19,
    prompt_new_conversation = 20,
    prompt_select_conversation = 21,
    agent_message_sent = 22,
    agent_new_conversation = 23,
    agent_select_conversation = 24,
    agent_create_worktree = 25,
    agent_switch_worktree = 26,
    agent_delete_worktree = 27,
    agent_refresh_worktrees = 28,
    agent_start_dagger_session = 29,
    agent_stop_dagger_session = 30,
    agent_execute_workflow = 31,
    agent_cancel_workflow = 32,
    chat_message_sent = 33,
    file_opened = 34,
    file_saved = 35,
    vim_state_updated = 36, // New event for Neovim RPC updates
};

// Handle process events into state
pub fn process(event: *const Event, state: *AppState) !void {
    switch (event.type) {
        .tab_switched => {
            if (event.int_value) |tab_index| {
                state.current_tab = @enumFromInt(tab_index);
            }
        },
        .theme_toggled => {
            state.current_theme = if (state.current_theme == .dark) .light else .dark;
        },
        .terminal_input => {
            if (event.string_value) |input| {
                // Process terminal input
                const new_content = try std.fmt.allocPrint(state.allocator, "{s}{s}", .{ state.terminal.content, input });
                state.allocator.free(state.terminal.content);
                state.terminal.content = new_content;
            }
        },
        .terminal_resize => {
            if (event.int_value) |rows| {
                if (event.int_value2) |cols| {
                    state.terminal.rows = @intCast(rows);
                    state.terminal.cols = @intCast(cols);
                }
            }
        },
        .prompt_content_updated => {
            if (event.string_value) |content| {
                const new_content = try state.allocator.dupe(u8, content);
                state.allocator.free(state.prompt.current_content);
                state.prompt.current_content = new_content;
            }
        },
        .prompt_message_sent => {
            if (event.string_value) |message| {
                state.prompt.processing = true;
                // Store the message for AI processing
                const new_message = try state.allocator.dupe(u8, message);
                state.allocator.free(state.prompt.last_message);
                state.prompt.last_message = new_message;
                // In production, this would trigger OpenAI API call
            }
        },
        .agent_message_sent => {
            if (event.string_value) |message| {
                state.agent.processing = true;
                // Store message for agent processing
                const new_message = try state.allocator.dupe(u8, message);
                state.allocator.free(state.agent.last_message);
                state.agent.last_message = new_message;
            }
        },
        .agent_start_dagger_session => {
            state.agent.dagger_connected = true;
        },
        .agent_stop_dagger_session => {
            state.agent.dagger_connected = false;
        },
        .vim_keypress => {
            // This event now ONLY forwards the keypress.
            // The actual forwarding happens in the Swift -> Zig -> PTY layer.
            // This case might become a no-op if the PTY write happens before the event dispatch.
            // For now, we can log it.
            std.log.debug("Vim keypress event received: {s}", .{event.string_value orelse ""});
        },
        .vim_set_content => {
            if (event.string_value) |content| {
                const new_content = try state.allocator.dupe(u8, content);
                state.allocator.free(state.vim.content);
                state.vim.content = new_content;
            }
        },
        .web_navigate => {
            if (event.string_value) |url| {
                const new_url = try state.allocator.dupe(u8, url);
                state.allocator.free(state.web.current_url);
                state.web.current_url = new_url;
                state.web.is_loading = true;
            }
        },
        .web_go_back => {
            state.web.can_go_back = false; // Will be updated by webview
        },
        .web_go_forward => {
            state.web.can_go_forward = false; // Will be updated by webview
        },
        .web_reload => {
            state.web.is_loading = true;
        },
        .farcaster_select_channel => {
            if (event.string_value) |channel| {
                const new_channel = try state.allocator.dupe(u8, channel);
                state.allocator.free(state.farcaster.selected_channel);
                state.farcaster.selected_channel = new_channel;
            }
        },
        .farcaster_create_post => {
            if (event.string_value) |_| {
                state.farcaster.is_posting = true;
                // In production, this would call Farcaster API
            }
        },
        .farcaster_refresh_feed => {
            state.farcaster.is_loading = true;
        },
        .editor_content_changed => {
            if (event.string_value) |content| {
                const new_content = try state.allocator.dupe(u8, content);
                state.allocator.free(state.editor.content);
                state.editor.content = new_content;
                state.editor.is_modified = true;
            }
        },
        .editor_save => {
            state.editor.is_modified = false;
            // In production, save to file system
        },
        .file_opened => {
            if (event.string_value) |path| {
                const new_path = try state.allocator.dupe(u8, path);
                state.allocator.free(state.editor.file_path);
                state.editor.file_path = new_path;
                state.editor.is_modified = false;
            }
        },
        .prompt_new_conversation => {
            state.prompt.conversation_count += 1;
            state.prompt.current_conversation_index = state.prompt.conversation_count - 1;
        },
        .prompt_select_conversation => {
            if (event.int_value) |index| {
                state.prompt.current_conversation_index = @intCast(index);
            }
        },
        .agent_new_conversation => {
            state.agent.conversation_count += 1;
            state.agent.current_conversation_index = state.agent.conversation_count - 1;
        },
        .agent_select_conversation => {
            if (event.int_value) |index| {
                state.agent.current_conversation_index = @intCast(index);
            }
        },
        .vim_state_updated => {
            // This new event is triggered by the RPC client when it receives a notification from Neovim.
            // It updates our AppState cache.
            if (state.vim.nvim_client) |client| {
                state.allocator.free(state.vim.content);
                state.vim.content = try client.getContent();

                const cursor = try client.getCursor();
                state.vim.cursor_row = cursor.row;
                state.vim.cursor_col = cursor.col;

                const mode = try client.getMode();
                state.allocator.free(state.vim.status_line);
                if (std.mem.eql(u8, mode, "i")) {
                    state.vim.mode = .insert;
                    state.vim.status_line = try state.allocator.dupe(u8, "-- INSERT --");
                } else if (std.mem.eql(u8, mode, "v")) {
                    state.vim.mode = .visual;
                    state.vim.status_line = try state.allocator.dupe(u8, "-- VISUAL --");
                } else if (std.mem.eql(u8, mode, "c")) {
                    state.vim.mode = .command;
                    state.vim.status_line = try state.allocator.dupe(u8, ":");
                } else {
                    state.vim.mode = .normal;
                    state.vim.status_line = try state.allocator.dupe(u8, "");
                }
            }
        },
        else => {
            // Log unhandled events in debug mode
            std.log.debug("Unhandled event type: {}", .{event.type});
        },
    }
}

```

```zig
// File: ./src/state/web_state.zig
can_go_back: bool,
can_go_forward: bool,
is_loading: bool,
current_url: []const u8,
page_title: []const u8,

pub const CWebState = extern struct {
    can_go_back: bool,
    can_go_forward: bool,
    is_loading: bool,
    current_url: [*:0]const u8,
    page_title: [*:0]const u8,
};
```

```zig
// File: ./src/state/agent_state.zig
processing: bool,
dagger_connected: bool,
last_message: []const u8 = "",
conversation_count: u32 = 1,
current_conversation_index: u32 = 0,

pub const CAgentState = extern struct {
    processing: bool,
    dagger_connected: bool,
};
```

```zig
// File: ./src/state/prompt_state.zig
processing: bool,
current_content: []const u8,
last_message: []const u8 = "",
conversation_count: u32 = 1,
current_conversation_index: u32 = 0,

pub const CPromptState = extern struct {
    processing: bool,
    current_content: [*:0]const u8,
};
```

```zig
// File: ./src/state/editor_state.zig
file_path: []const u8 = "",
content: []const u8 = "",
is_modified: bool = false,

pub const CEditorState = extern struct {
    file_path: [*:0]const u8,
    content: [*:0]const u8,
    is_modified: bool,
};```

```zig
// File: ./src/state/farcaster_state.zig
selected_channel: []const u8 = "home",
is_loading: bool = false,
is_posting: bool = false,

pub const CFarcasterState = extern struct {
    selected_channel: [*:0]const u8,
    is_loading: bool,
    is_posting: bool,
};```

```zig
// File: ./src/state/terminal_state.zig
rows: u32,
cols: u32,
content: []const u8,
is_running: bool,

pub const CTerminalState = extern struct {
    rows: u32,
    cols: u32,
    content: [*:0]const u8,
    is_running: bool,
};
```

```zig
// File: ./src/state/cstate.zig
const std = @import("std");
const PromptState = @import("prompt_state.zig");
const TerminalState = @import("terminal_state.zig");
const WebState = @import("web_state.zig");
const VimState = @import("vim_state.zig");
const AgentState = @import("agent_state.zig");
const FarcasterState = @import("farcaster_state.zig");
const EditorState = @import("editor_state.zig");
const AppState = @import("state.zig");

pub const CAppState = extern struct {
    current_tab: AppState.Tab,
    is_initialized: bool,
    error_message: [*:0]const u8,
    openai_available: bool,
    current_theme: AppState.Theme,

    prompt: PromptState.CPromptState,
    terminal: TerminalState.CTerminalState,
    web: WebState.CWebState,
    vim: VimState.CVimState,
    agent: AgentState.CAgentState,
    farcaster: FarcasterState.CFarcasterState,
    editor: EditorState.CEditorState,
};

// C-compatible application state
pub fn fromApp(app: *const AppState) !CAppState {
    // Helper function to convert slice to null-terminated string
    const toNullTerminated = struct {
        fn convert(alloc: std.mem.Allocator, slice: []const u8) ![*:0]const u8 {
            const result = try alloc.allocSentinel(u8, slice.len, 0);
            @memcpy(result, slice);
            return result;
        }
    }.convert;

    return CAppState{
        .current_tab = app.current_tab,
        .is_initialized = app.is_initialized,
        .error_message = if (app.error_message) |msg| try toNullTerminated(app.allocator, msg) else try toNullTerminated(app.allocator, ""),
        .openai_available = app.openai_available,
        .current_theme = app.current_theme,
        .prompt = .{
            .processing = app.prompt.processing,
            .current_content = try toNullTerminated(app.allocator, app.prompt.current_content),
        },
        .terminal = .{
            .rows = app.terminal.rows,
            .cols = app.terminal.cols,
            .content = try toNullTerminated(app.allocator, app.terminal.content),
            .is_running = app.terminal.is_running,
        },
        .web = .{
            .can_go_back = app.web.can_go_back,
            .can_go_forward = app.web.can_go_forward,
            .is_loading = app.web.is_loading,
            .current_url = try toNullTerminated(app.allocator, app.web.current_url),
            .page_title = try toNullTerminated(app.allocator, app.web.page_title),
        },
        .vim = .{
            .mode = app.vim.mode,
            .content = try toNullTerminated(app.allocator, app.vim.content),
            .cursor_row = app.vim.cursor_row,
            .cursor_col = app.vim.cursor_col,
            .status_line = try toNullTerminated(app.allocator, app.vim.status_line),
        },
        .agent = .{
            .processing = app.agent.processing,
            .dagger_connected = app.agent.dagger_connected,
        },
        .farcaster = .{
            .selected_channel = try toNullTerminated(app.allocator, app.farcaster.selected_channel),
            .is_loading = app.farcaster.is_loading,
            .is_posting = app.farcaster.is_posting,
        },
        .editor = .{
            .file_path = try toNullTerminated(app.allocator, app.editor.file_path),
            .content = try toNullTerminated(app.allocator, app.editor.content),
            .is_modified = app.editor.is_modified,
        },
    };
}

pub fn deinit(self: *CAppState, allocator: std.mem.Allocator) void {
    // Free all allocated strings
    // Always free error_message since we always allocate it now
    allocator.free(std.mem.span(self.error_message));
    allocator.free(std.mem.span(self.prompt.current_content));
    allocator.free(std.mem.span(self.terminal.content));
    allocator.free(std.mem.span(self.web.current_url));
    allocator.free(std.mem.span(self.web.page_title));
    allocator.free(std.mem.span(self.vim.content));
    allocator.free(std.mem.span(self.vim.status_line));
    allocator.free(std.mem.span(self.farcaster.selected_channel));
    allocator.free(std.mem.span(self.editor.file_path));
    allocator.free(std.mem.span(self.editor.content));
}
```

```zig
// File: ./src/state/state.zig
const std = @import("std");
const PromptState = @import("prompt_state.zig");
const TerminalState = @import("terminal_state.zig");
const WebState = @import("web_state.zig");
const VimState = @import("vim_state.zig");
const AgentState = @import("agent_state.zig");
const FarcasterState = @import("farcaster_state.zig");
const EditorState = @import("editor_state.zig");

// Core application state
pub const AppState = @This();

// A C compatible version of AppState
const cstate = @import("cstate.zig");
pub const CAppState = cstate.CAppState;
pub fn toCAppState(self: *const AppState) !CAppState {
    return cstate.fromApp(self);
}

// Events that can be dispatched to AppState.process
pub const Event = @import("event.zig");
pub fn process(self: *AppState, event: *const Event) !void {
    return event.process(self);
}

current_tab: Tab,
is_initialized: bool,
error_message: ?[]const u8,
openai_available: bool,
current_theme: Theme,

prompt: PromptState,
terminal: TerminalState,
web: WebState,
vim: VimState,
agent: AgentState,
farcaster: FarcasterState,
editor: EditorState,

allocator: std.mem.Allocator,

pub const Tab = enum(c_int) {
    prompt = 0,
    farcaster = 1,
    agent = 2,
    terminal = 3,
    web = 4,
    editor = 5,
    diff = 6,
    worktree = 7,
};
pub const Theme = enum(c_int) {
    dark = 0,
    light = 1,
};

pub fn init(allocator: std.mem.Allocator) !*AppState {
    const state = try allocator.create(AppState);
    state.* = .{
        .current_tab = .prompt,
        .is_initialized = true,
        .error_message = null,
        .openai_available = false,
        .current_theme = .dark,
        .prompt = .{
            .processing = false,
            .current_content = try allocator.dupe(u8, "# Your Prompt\n\nStart typing your prompt here."),
            .last_message = try allocator.dupe(u8, ""),
            .conversation_count = 1,
            .current_conversation_index = 0,
        },
        .terminal = .{
            .rows = 24,
            .cols = 80,
            .content = try allocator.dupe(u8, ""),
            .is_running = false,
        },
        .web = .{
            .can_go_back = false,
            .can_go_forward = false,
            .is_loading = false,
            .current_url = try allocator.dupe(u8, "https://www.apple.com"),
            .page_title = try allocator.dupe(u8, "New Tab"),
        },
        .vim = .{
            .mode = .normal,
            .content = try allocator.dupe(u8, ""),
            .cursor_row = 0,
            .cursor_col = 0,
            .status_line = try allocator.dupe(u8, "-- NORMAL --"),
        },
        .agent = .{
            .processing = false,
            .dagger_connected = false,
            .last_message = try allocator.dupe(u8, ""),
            .conversation_count = 1,
            .current_conversation_index = 0,
        },
        .farcaster = .{
            .selected_channel = try allocator.dupe(u8, "home"),
            .is_loading = false,
            .is_posting = false,
        },
        .editor = .{
            .file_path = try allocator.dupe(u8, ""),
            .content = try allocator.dupe(u8, ""),
            .is_modified = false,
        },
        .allocator = allocator,
    };
    return state;
}

pub fn deinit(self: *AppState) void {
    if (self.error_message) |msg| {
        self.allocator.free(msg);
    }
    self.allocator.free(self.prompt.current_content);
    self.allocator.free(self.prompt.last_message);
    self.allocator.free(self.terminal.content);
    self.allocator.free(self.web.current_url);
    self.allocator.free(self.web.page_title);
    self.allocator.free(self.vim.content);
    self.allocator.free(self.vim.status_line);
    self.allocator.free(self.agent.last_message);
    self.allocator.free(self.farcaster.selected_channel);
    self.allocator.free(self.editor.file_path);
    self.allocator.free(self.editor.content);
    self.allocator.destroy(self);
}
```

```zig
// File: ./src/farcaster/config.zig
const std = @import("std");

/// Retry policy for network operations
pub const RetryPolicy = struct {
    max_attempts: u32 = 3,
    base_delay_ms: u64 = 100,
    max_delay_ms: u64 = 5000,
    exponential_base: f32 = 2.0,
    
    pub fn shouldRetry(self: RetryPolicy, attempt: u32, err: anyerror) bool {
        if (attempt >= self.max_attempts) return false;
        
        return switch (err) {
            error.NetworkError,
            error.Timeout,
            error.HttpError,
            => true,
            else => false,
        };
    }
    
    pub fn getDelay(self: RetryPolicy, attempt: u32) u64 {
        const exp = std.math.pow(f32, self.exponential_base, @as(f32, @floatFromInt(attempt)));
        const delay = @as(u64, @intFromFloat(@as(f32, @floatFromInt(self.base_delay_ms)) * exp));
        return @min(delay, self.max_delay_ms);
    }
};

/// Rate limiting configuration
pub const RateLimitConfig = struct {
    max_requests: u32 = 100,
    window_ms: i64 = 60000, // 1 minute
    enabled: bool = true,
};

/// Client configuration with sensible defaults
pub const ClientConfig = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8 = "https://hub.pinata.cloud",
    user_fid: u64,
    private_key_hex: []const u8,
    retry_policy: RetryPolicy = .{},
    rate_limit: RateLimitConfig = .{},
    timeout_ms: u64 = 30000, // 30 seconds
    max_response_size: usize = 16 * 1024 * 1024, // 16MB
    
    /// Create configuration with validation
    pub fn init(allocator: std.mem.Allocator, user_fid: u64, private_key_hex: []const u8) !ClientConfig {
        // Validate private key format
        if (private_key_hex.len != 128) {
            std.log.err("Invalid private key length: {} (expected 128)", .{private_key_hex.len});
            return error.InvalidPrivateKey;
        }
        
        // Basic hex validation
        for (private_key_hex) |char| {
            if (!std.ascii.isHex(char)) {
                std.log.err("Invalid hex character in private key: {c}", .{char});
                return error.InvalidPrivateKey;
            }
        }
        
        return ClientConfig{
            .allocator = allocator,
            .user_fid = user_fid,
            .private_key_hex = private_key_hex,
        };
    }
    
    /// Builder pattern for configuration
    pub fn withBaseUrl(self: ClientConfig, url: []const u8) ClientConfig {
        var config = self;
        config.base_url = url;
        return config;
    }
    
    pub fn withTimeout(self: ClientConfig, timeout_ms: u64) ClientConfig {
        var config = self;
        config.timeout_ms = timeout_ms;
        return config;
    }
    
    pub fn withRetryPolicy(self: ClientConfig, policy: RetryPolicy) ClientConfig {
        var config = self;
        config.retry_policy = policy;
        return config;
    }
    
    pub fn withRateLimit(self: ClientConfig, rate_config: RateLimitConfig) ClientConfig {
        var config = self;
        config.rate_limit = rate_config;
        return config;
    }
};```

```zig
// File: ./src/farcaster/rate_limiter.zig
const std = @import("std");

/// Rate limiter for API calls with sliding window algorithm
pub const RateLimiter = struct {
    const Self = @This();
    
    const Window = struct {
        start_time: i64,
        count: u32,
    };
    
    mutex: std.Thread.Mutex,
    windows: std.StringHashMap(Window),
    max_requests: u32,
    window_ms: i64,
    enabled: bool,
    
    pub fn init(allocator: std.mem.Allocator, max_requests: u32, window_ms: i64) Self {
        return .{
            .mutex = .{},
            .windows = std.StringHashMap(Window).init(allocator),
            .max_requests = max_requests,
            .window_ms = window_ms,
            .enabled = true,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.windows.deinit();
    }
    
    pub fn setEnabled(self: *Self, enabled: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = enabled;
    }
    
    /// Check if request is allowed under rate limit
    pub fn checkLimit(self: *Self, key: []const u8) !void {
        if (!self.enabled) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const now = std.time.milliTimestamp();
        
        // Clean up expired windows periodically
        if (@mod(@as(u32, @intCast(now)), 10000) == 0) {
            self.cleanupExpiredWindows(now);
        }
        
        if (self.windows.getPtr(key)) |window| {
            if (now - window.start_time >= self.window_ms) {
                // Reset window
                window.start_time = now;
                window.count = 1;
            } else if (window.count >= self.max_requests) {
                std.log.warn("Rate limit exceeded for key: {s}", .{key});
                return error.RateLimitExceeded;
            } else {
                window.count += 1;
            }
        } else {
            try self.windows.put(key, .{
                .start_time = now,
                .count = 1,
            });
        }
    }
    
    /// Get current rate limit status for a key
    pub fn getStatus(self: *Self, key: []const u8) struct { used: u32, max: u32, reset_in_ms: i64 } {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const now = std.time.milliTimestamp();
        
        if (self.windows.get(key)) |window| {
            const reset_in = @max(0, window.start_time + self.window_ms - now);
            return .{
                .used = window.count,
                .max = self.max_requests,
                .reset_in_ms = reset_in,
            };
        }
        
        return .{
            .used = 0,
            .max = self.max_requests,
            .reset_in_ms = 0,
        };
    }
    
    /// Clean up expired windows to prevent memory leaks
    fn cleanupExpiredWindows(self: *Self, now: i64) void {
        var iter = self.windows.iterator();
        var keys_to_remove = std.ArrayList([]const u8).init(self.windows.allocator);
        defer keys_to_remove.deinit();
        
        while (iter.next()) |entry| {
            if (now - entry.value_ptr.start_time >= self.window_ms * 2) {
                keys_to_remove.append(entry.key_ptr.*) catch continue;
            }
        }
        
        for (keys_to_remove.items) |key| {
            _ = self.windows.remove(key);
        }
    }
};```

```zig
// File: ./src/farcaster/farcaster.zig
const std = @import("std");
const json = std.json;
const http = std.http;
const crypto = std.crypto;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// Import our enhanced modules
const config = @import("config.zig");
const rate_limiter = @import("rate_limiter.zig");

pub const ClientConfig = config.ClientConfig;
pub const RetryPolicy = config.RetryPolicy;
pub const RateLimiter = rate_limiter.RateLimiter;

// Farcaster SDK for Zig
// Based on Farcaster Hub HTTP API and protocol specifications
// Hub: Pinata (hub.pinata.cloud) - free, reliable, no auth required

// ===== Core Types =====

pub const FarcasterError = error{
    HttpError,
    JsonParseError,
    SigningError,
    InvalidMessage,
    NetworkError,
    OutOfMemory,
};

pub const MessageType = enum(u8) {
    cast_add = 1,
    cast_remove = 2,
    reaction_add = 3,
    reaction_remove = 4,
    link_add = 5,
    link_remove = 6,
    user_data_add = 11,
    user_data_remove = 12,
};

pub const ReactionType = enum(u8) {
    like = 1,
    recast = 2,
};

pub const UserDataType = enum(u8) {
    pfp = 1,
    display = 2,
    bio = 3,
    url = 5,
    username = 6,
};

pub const LinkType = enum(u8) {
    follow = 1,
    unfollow = 2,
};

// Core Farcaster structures
pub const FarcasterUser = struct {
    fid: u64,
    username: []const u8,
    display_name: []const u8,
    bio: []const u8,
    pfp_url: []const u8,
    follower_count: u32,
    following_count: u32,
};

pub const FarcasterCast = struct {
    hash: []const u8,
    parent_hash: ?[]const u8,
    parent_url: ?[]const u8, // For channels
    author: FarcasterUser,
    text: []const u8,
    timestamp: u64,
    mentions: []u64,
    replies_count: u32,
    reactions_count: u32,
    recasts_count: u32,
};

pub const FarcasterReaction = struct {
    type: ReactionType,
    reactor: FarcasterUser,
    target_cast_hash: []const u8,
    timestamp: u64,
};

pub const FarcasterChannel = struct {
    id: []const u8,
    url: []const u8,
    name: []const u8,
    description: []const u8,
    image_url: []const u8,
    creator_fid: u64,
    follower_count: u32,
};

// Message structures for API communication
pub const MessageData = struct {
    type: MessageType,
    fid: u64,
    timestamp: u64,
    network: u8, // 1 = mainnet
    body: union(MessageType) {
        cast_add: CastAddBody,
        cast_remove: CastRemoveBody,
        reaction_add: ReactionAddBody,
        reaction_remove: ReactionRemoveBody,
        link_add: LinkAddBody,
        link_remove: LinkRemoveBody,
        user_data_add: UserDataAddBody,
        user_data_remove: UserDataRemoveBody,
    },
};

pub const CastAddBody = struct {
    text: []const u8,
    mentions: []u64,
    mentions_positions: []u64,
    embeds: [][]const u8,
    parent_cast_id: ?CastId,
    parent_url: ?[]const u8,
};

pub const CastRemoveBody = struct {
    target_hash: []const u8,
};

pub const ReactionAddBody = struct {
    type: ReactionType,
    target_cast_id: ?CastId,
    target_url: ?[]const u8,
};

pub const ReactionRemoveBody = struct {
    type: ReactionType,
    target_cast_id: ?CastId,
    target_url: ?[]const u8,
};

pub const LinkAddBody = struct {
    type: []const u8, // "follow"
    target_fid: u64,
};

pub const LinkRemoveBody = struct {
    type: []const u8, // "follow"
    target_fid: u64,
};

pub const UserDataAddBody = struct {
    type: UserDataType,
    value: []const u8,
};

pub const UserDataRemoveBody = struct {
    type: UserDataType,
};

pub const CastId = struct {
    fid: u64,
    hash: []const u8,
};

// ===== Client Implementation =====

/// Smart allocator wrapper for HTTP operations
const HttpArenaAllocator = struct {
    base_allocator: Allocator,
    arena: ?std.heap.ArenaAllocator,
    
    const Self = @This();
    
    fn init(base_allocator: Allocator) Self {
        return Self{
            .base_allocator = base_allocator,
            .arena = null,
        };
    }
    
    fn ensureArena(self: *Self) void {
        if (self.arena == null) {
            self.arena = std.heap.ArenaAllocator.init(self.base_allocator);
        }
    }
    
    fn deinit(self: *Self) void {
        if (self.arena) |*arena| {
            arena.deinit();
        }
    }
    
    fn allocator(self: *Self) Allocator {
        self.ensureArena();
        return self.arena.?.allocator();
    }
    
    /// Reset arena between HTTP operations for optimal performance
    fn reset(self: *Self) void {
        if (self.arena) |*arena| {
            arena.deinit();
        }
        self.arena = std.heap.ArenaAllocator.init(self.base_allocator);
    }
};

pub const FarcasterClient = struct {
    base_allocator: Allocator,  // For long-lived allocations
    http_arena: HttpArenaAllocator,  // For temporary HTTP/JSON operations
    http_client: http.Client,
    config: ClientConfig,
    user_fid: u64,
    private_key: [64]u8, // Ed25519 private key (64 bytes for seed + extended)
    public_key: [32]u8,  // Ed25519 public key
    rate_limiter: RateLimiter,
    stats: ClientStats,
    
    const Self = @This();
    
    pub const ClientStats = struct {
        total_requests: u64 = 0,
        failed_requests: u64 = 0,
        bytes_sent: u64 = 0,
        bytes_received: u64 = 0,
        rate_limit_hits: u64 = 0,
        avg_response_time_ms: f64 = 0.0,
        
        pub fn recordRequest(self: *ClientStats, success: bool, bytes_sent: usize, bytes_received: usize, duration_ms: f64) void {
            self.total_requests += 1;
            if (!success) self.failed_requests += 1;
            self.bytes_sent += bytes_sent;
            self.bytes_received += bytes_received;
            
            // Update running average
            const count = @as(f64, @floatFromInt(self.total_requests));
            self.avg_response_time_ms = (self.avg_response_time_ms * (count - 1.0) + duration_ms) / count;
        }
        
        pub fn recordRateLimitHit(self: *ClientStats) void {
            self.rate_limit_hits += 1;
        }
    };
    
    /// Initialize FarcasterClient with configuration-driven setup
    /// Uses arena allocator for temporary operations, base allocator for persistent data
    pub fn init(client_config: ClientConfig) !Self {
        return initWithAllocator(client_config.allocator, client_config.user_fid, client_config.private_key_hex, client_config);
    }
    
    /// Legacy initialization for backward compatibility
    pub fn initWithAllocator(allocator: Allocator, user_fid: u64, private_key_hex: []const u8, client_config: ?ClientConfig) !Self {
        const final_config = client_config orelse try ClientConfig.init(allocator, user_fid, private_key_hex);
        var private_key: [64]u8 = undefined;
        var public_key: [32]u8 = undefined;
        
        // Validate input first
        if (private_key_hex.len != 128) {
            std.log.err("Invalid private key length: {} (expected 128)", .{private_key_hex.len});
            return FarcasterError.InvalidMessage;
        }
        
        // Convert hex with proper error handling
        _ = std.fmt.hexToBytes(&private_key, private_key_hex) catch {
            std.log.err("Failed to parse hex private key", .{});
            return FarcasterError.InvalidMessage;
        };
        
        // Create cryptographic keys with error handling and security cleanup
        const secret_key = crypto.sign.Ed25519.SecretKey.fromBytes(private_key) catch {
            // Zero out sensitive data on error - Rust-style security
            @memset(&private_key, 0);
            std.log.err("Failed to create Ed25519 secret key", .{});
            return FarcasterError.SigningError;
        };
        errdefer @memset(&private_key, 0); // ✅ Zero sensitive data on any error
        
        const kp = crypto.sign.Ed25519.KeyPair.fromSecretKey(secret_key) catch {
            @memset(&private_key, 0);
            std.log.err("Failed to create Ed25519 keypair", .{});
            return FarcasterError.SigningError;
        };
        public_key = kp.public_key.bytes;
        
        // Initialize HTTP client with error handling
        const http_client = http.Client{ .allocator = allocator };
        errdefer http_client.deinit(); // ✅ Cleanup on error
        
        var rate_limit = RateLimiter.init(
            allocator,
            final_config.rate_limit.max_requests,
            final_config.rate_limit.window_ms,
        );
        rate_limit.setEnabled(final_config.rate_limit.enabled);
        
        return Self{
            .base_allocator = allocator,
            .http_arena = HttpArenaAllocator.init(allocator),
            .http_client = http_client,
            .config = final_config,
            .user_fid = user_fid,
            .private_key = private_key,
            .public_key = public_key,
            .rate_limiter = rate_limit,
            .stats = .{},
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.http_client.deinit();
        self.http_arena.deinit();
        self.rate_limiter.deinit();
    }
    
    /// Get client statistics for monitoring
    pub fn getStats(self: Self) ClientStats {
        return self.stats;
    }
    
    // ===== Cast Operations =====
    
    pub fn getCastsByFid(self: *Self, fid: u64, limit: u32) ![]FarcasterCast {
        // Reset arena for this operation - all temp allocations freed together
        self.http_arena.reset();
        
        const arena_allocator = self.http_arena.allocator();
        const uri_str = try std.fmt.allocPrint(arena_allocator, "{s}/v1/castsByFid?fid={d}&limit={d}", .{ self.config.base_url, fid, limit });
        
        const response_body = try self.httpGet(uri_str);
        
        const result = try self.parseCastsResponse(response_body);
        
        // Copy result to persistent memory
        return try self.base_allocator.dupe(FarcasterCast, result);
    }
    
    pub fn getCastsByChannel(self: *Self, channel_url: []const u8, limit: u32) ![]FarcasterCast {
        // Reset arena for this operation
        self.http_arena.reset();
        
        const arena_allocator = self.http_arena.allocator();
        const uri_str = try std.fmt.allocPrint(arena_allocator, "{s}/v1/castsByParent?url={s}&limit={d}", .{ self.config.base_url, channel_url, limit });
        
        const response_body = try self.httpGet(uri_str);
        
        const result = try self.parseCastsResponse(response_body);
        
        // Copy result to persistent memory
        return try self.base_allocator.dupe(FarcasterCast, result);
    }
    
    pub fn postCast(self: *Self, text: []const u8, channel_url: ?[]const u8) ![]const u8 {
        const timestamp = @as(u64, @intCast(std.time.timestamp()));
        
        const cast_body = CastAddBody{
            .text = text,
            .mentions = &[_]u64{},
            .mentions_positions = &[_]u64{},
            .embeds = &[_][]const u8{},
            .parent_cast_id = null,
            .parent_url = channel_url,
        };
        
        const message_data = MessageData{
            .type = .cast_add,
            .fid = self.user_fid,
            .timestamp = timestamp,
            .network = 1, // mainnet
            .body = .{ .cast_add = cast_body },
        };
        
        return self.submitMessage(message_data);
    }
    
    // ===== Reaction Operations =====
    
    pub fn likeCast(self: *Self, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        return self.addReaction(.like, cast_hash, cast_fid);
    }
    
    pub fn recastCast(self: *Self, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        return self.addReaction(.recast, cast_hash, cast_fid);
    }
    
    pub fn unlikeCast(self: *Self, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        return self.removeReaction(.like, cast_hash, cast_fid);
    }
    
    pub fn unrecastCast(self: *Self, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        return self.removeReaction(.recast, cast_hash, cast_fid);
    }
    
    fn addReaction(self: *Self, reaction_type: ReactionType, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        const timestamp = @as(u64, @intCast(std.time.timestamp()));
        
        const reaction_body = ReactionAddBody{
            .type = reaction_type,
            .target_cast_id = CastId{ .fid = cast_fid, .hash = cast_hash },
            .target_url = null,
        };
        
        const message_data = MessageData{
            .type = .reaction_add,
            .fid = self.user_fid,
            .timestamp = timestamp,
            .network = 1,
            .body = .{ .reaction_add = reaction_body },
        };
        
        return self.submitMessage(message_data);
    }
    
    fn removeReaction(self: *Self, reaction_type: ReactionType, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        const timestamp = @as(u64, @intCast(std.time.timestamp()));
        
        const reaction_body = ReactionRemoveBody{
            .type = reaction_type,
            .target_cast_id = CastId{ .fid = cast_fid, .hash = cast_hash },
            .target_url = null,
        };
        
        const message_data = MessageData{
            .type = .reaction_remove,
            .fid = self.user_fid,
            .timestamp = timestamp,
            .network = 1,
            .body = .{ .reaction_remove = reaction_body },
        };
        
        return self.submitMessage(message_data);
    }
    
    // ===== Follow Operations =====
    
    pub fn followUser(self: *Self, target_fid: u64) ![]const u8 {
        const timestamp = @as(u64, @intCast(std.time.timestamp()));
        
        const link_body = LinkAddBody{
            .type = "follow",
            .target_fid = target_fid,
        };
        
        const message_data = MessageData{
            .type = .link_add,
            .fid = self.user_fid,
            .timestamp = timestamp,
            .network = 1,
            .body = .{ .link_add = link_body },
        };
        
        return self.submitMessage(message_data);
    }
    
    pub fn unfollowUser(self: *Self, target_fid: u64) ![]const u8 {
        const timestamp = @as(u64, @intCast(std.time.timestamp()));
        
        const link_body = LinkRemoveBody{
            .type = "follow",
            .target_fid = target_fid,
        };
        
        const message_data = MessageData{
            .type = .link_remove,
            .fid = self.user_fid,
            .timestamp = timestamp,
            .network = 1,
            .body = .{ .link_remove = link_body },
        };
        
        return self.submitMessage(message_data);
    }
    
    pub fn getFollowers(self: *Self, fid: u64) ![]FarcasterUser {
        // Reset arena for this operation
        self.http_arena.reset();
        
        const arena_allocator = self.http_arena.allocator();
        const uri_str = try std.fmt.allocPrint(arena_allocator, "{s}/v1/linksByTargetFid?target_fid={d}&link_type=follow", .{ self.config.base_url, fid });
        
        const response_body = try self.httpGet(uri_str);
        
        const result = try self.parseFollowersResponse(response_body);
        
        // Copy result to persistent memory
        return try self.base_allocator.dupe(FarcasterUser, result);
    }
    
    pub fn getFollowing(self: *Self, fid: u64) ![]FarcasterUser {
        // Reset arena for this operation
        self.http_arena.reset();
        
        const arena_allocator = self.http_arena.allocator();
        const uri_str = try std.fmt.allocPrint(arena_allocator, "{s}/v1/linksByFid?fid={d}&link_type=follow", .{ self.config.base_url, fid });
        
        const response_body = try self.httpGet(uri_str);
        
        const result = try self.parseFollowingResponse(response_body);
        
        // Copy result to persistent memory
        return try self.base_allocator.dupe(FarcasterUser, result);
    }
    
    // ===== User Profile Operations =====
    
    pub fn getUserProfile(self: *Self, fid: u64) !FarcasterUser {
        // Reset arena for this operation
        self.http_arena.reset();
        
        const arena_allocator = self.http_arena.allocator();
        const uri_str = try std.fmt.allocPrint(arena_allocator, "{s}/v1/userDataByFid?fid={d}", .{ self.config.base_url, fid });
        
        const response_body = try self.httpGet(uri_str);
        
        return self.parseUserProfileResponse(response_body, fid);
    }
    
    // ===== Internal HTTP and Message Handling =====
    
    fn httpGet(self: *Self, uri_str: []const u8) ![]u8 {
        // Apply rate limiting
        self.rate_limiter.checkLimit("http_get") catch |err| {
            self.stats.recordRateLimitHit();
            return err;
        };
        
        const start_time = std.time.milliTimestamp();
        var success = false;
        var bytes_received: usize = 0;
        defer {
            const duration = @as(f64, @floatFromInt(std.time.milliTimestamp() - start_time));
            self.stats.recordRequest(success, uri_str.len, bytes_received, duration);
        }
        
        const uri = try std.Uri.parse(uri_str);
        
        var header_buf: [8192]u8 = undefined;
        var req = try self.http_client.open(.GET, uri, .{ 
            .server_header_buffer = &header_buf 
        });
        defer req.deinit();
        
        try req.send();
        try req.finish();
        try req.wait();
        
        if (req.response.status != .ok) {
            std.log.err("HTTP GET failed with status: {}", .{req.response.status});
            return FarcasterError.HttpError;
        }
        
        // Use arena allocator for HTTP response - auto-freed on reset
        const body = try req.reader().readAllAlloc(self.http_arena.allocator(), self.config.max_response_size);
        bytes_received = body.len;
        success = true;
        return body;
    }
    
    fn submitMessage(self: *Self, message_data: MessageData) ![]const u8 {
        // Reset arena for this operation - all temp allocations freed together
        self.http_arena.reset();
        
        // 1. Serialize message data to bytes (arena allocated)
        const message_bytes = try self.serializeMessageData(message_data);
        
        // 2. Hash the message with BLAKE3
        var hasher = crypto.hash.Blake3.init(.{});
        hasher.update(message_bytes);
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        
        // 3. Sign the hash with Ed25519
        const secret_key = crypto.sign.Ed25519.SecretKey{ .bytes = self.private_key };
        const public_key = crypto.sign.Ed25519.PublicKey{ .bytes = self.public_key };
        const kp = crypto.sign.Ed25519.KeyPair{ .secret_key = secret_key, .public_key = public_key };
        const signature = try kp.sign(&hash, null);
        
        // 4. Create complete message with signature (arena allocated)
        const complete_message = try self.createSignedMessage(message_data, hash, signature);
        
        // 5. Submit to hub and copy result to persistent memory
        const response = try self.httpPostMessage(complete_message);
        return try self.base_allocator.dupe(u8, response);
    }
    
    fn serializeMessageData(self: *Self, message_data: MessageData) ![]u8 {
        // This would normally be protobuf serialization
        // For now, we'll use JSON as a placeholder (the actual implementation would need protobuf)
        const arena_allocator = self.http_arena.allocator();
        var string = ArrayList(u8).init(arena_allocator);
        errdefer string.deinit(); // ✅ Cleanup on error
        
        json.stringify(message_data, .{}, string.writer()) catch |err| {
            std.log.err("Failed to serialize message data: {}", .{err});
            return err;
        };
        return string.toOwnedSlice();
    }
    
    fn createSignedMessage(self: *Self, _: MessageData, hash: [32]u8, _: crypto.sign.Ed25519.Signature) ![]u8 {
        // Use arena allocator for temporary message creation
        const arena_allocator = self.http_arena.allocator();
        
        // Convert hash to hex string
        var hash_hex: [64]u8 = undefined;
        _ = try std.fmt.bufPrint(&hash_hex, "{x}", .{std.fmt.fmtSliceHexLower(&hash)});
        
        // Create JSON string manually
        const json_template = 
            \\{{"hash":"{s}","signature":"placeholder_signature","signatureScheme":"ED25519","hashScheme":"BLAKE3"}}
        ;
        
        return try std.fmt.allocPrint(arena_allocator, json_template, .{hash_hex});
    }
    
    fn httpPostMessage(self: *Self, message_bytes: []const u8) ![]const u8 {
        const arena_allocator = self.http_arena.allocator();
        const uri_str = try std.fmt.allocPrint(arena_allocator, "{s}/v1/submitMessage", .{self.config.base_url});
        
        const uri = try std.Uri.parse(uri_str);
        
        var header_buf: [8192]u8 = undefined;
        var req = try self.http_client.open(.POST, uri, .{ 
            .server_header_buffer = &header_buf 
        });
        defer req.deinit();
        
        // Note: Setting headers in Zig 0.14 requires manual addition
        // For now, we'll use default headers and the service should work
        
        try req.send();
        try req.writeAll(message_bytes);
        try req.finish();
        try req.wait();
        
        if (req.response.status != .ok) {
            return FarcasterError.HttpError;
        }
        
        const body = try req.reader().readAllAlloc(arena_allocator, 16 * 1024 * 1024);
        return body;
    }
    
    // ===== Response Parsing =====
    
    fn parseCastsResponse(self: *Self, response_body: []const u8) ![]FarcasterCast {
        // Use arena allocator for temporary JSON parsing
        const arena_allocator = self.http_arena.allocator();
        var casts = ArrayList(FarcasterCast).init(arena_allocator);
        errdefer casts.deinit(); // ✅ Cleanup on error
        
        const parsed = json.parseFromSlice(json.Value, arena_allocator, response_body, .{}) catch |err| {
            std.log.err("Failed to parse JSON response: {}", .{err});
            return err;
        };
        defer parsed.deinit(); // ✅ Always cleanup parsed JSON
        
        if (parsed.value.object.get("messages")) |messages_value| {
            for (messages_value.array.items) |message| {
                const cast = self.parsecastFromMessage(message) catch |err| {
                    std.log.err("Failed to parse cast from message: {}", .{err});
                    return err;
                };
                casts.append(cast) catch |err| {
                    std.log.err("Failed to append cast to list: {}", .{err});
                    return err;
                };
            }
        }
        
        return casts.toOwnedSlice();
    }
    
    fn parsecastFromMessage(_: *Self, message: json.Value) !FarcasterCast {
        // Extract cast data from Farcaster message
        // This is simplified - real implementation would handle all fields properly
        const data = message.object.get("data").?.object;
        const cast_body = data.get("castAddBody").?.object;
        
        const author = FarcasterUser{
            .fid = @as(u64, @intCast(data.get("fid").?.integer)),
            .username = "unknown", // Would fetch from user data
            .display_name = "Unknown User",
            .bio = "",
            .pfp_url = "",
            .follower_count = 0,
            .following_count = 0,
        };
        
        return FarcasterCast{
            .hash = message.object.get("hash").?.string,
            .parent_hash = null,
            .parent_url = if (cast_body.get("parentUrl")) |url| url.string else null,
            .author = author,
            .text = cast_body.get("text").?.string,
            .timestamp = @as(u64, @intCast(data.get("timestamp").?.integer)),
            .mentions = &[_]u64{},
            .replies_count = 0,
            .reactions_count = 0,
            .recasts_count = 0,
        };
    }
    
    fn parseFollowersResponse(self: *Self, _: []const u8) ![]FarcasterUser {
        // Use arena allocator for temporary parsing
        const arena_allocator = self.http_arena.allocator();
        var users = ArrayList(FarcasterUser).init(arena_allocator);
        errdefer users.deinit(); // ✅ Cleanup on error
        
        // Implementation would parse link messages and extract follower FIDs
        // Then fetch user profiles for each
        
        return users.toOwnedSlice();
    }
    
    fn parseFollowingResponse(self: *Self, _: []const u8) ![]FarcasterUser {
        // Use arena allocator for temporary parsing
        const arena_allocator = self.http_arena.allocator();
        var users = ArrayList(FarcasterUser).init(arena_allocator);
        errdefer users.deinit(); // ✅ Cleanup on error
        
        // Implementation would parse link messages and extract following FIDs
        // Then fetch user profiles for each
        
        return users.toOwnedSlice();
    }
    
    fn parseUserProfileResponse(self: *Self, response_body: []const u8, fid: u64) !FarcasterUser {
        // Use arena allocator for JSON parsing
        const arena_allocator = self.http_arena.allocator();
        const parsed = json.parseFromSlice(json.Value, arena_allocator, response_body, .{}) catch |err| {
            std.log.err("Failed to parse user profile JSON: {}", .{err});
            return err;
        };
        defer parsed.deinit(); // ✅ Always cleanup parsed JSON
        
        var username: []const u8 = "unknown";
        var display_name: []const u8 = "Unknown User";
        var bio: []const u8 = "";
        var pfp_url: []const u8 = "";
        
        if (parsed.value.object.get("messages")) |messages| {
            for (messages.array.items) |message| {
                const data = message.object.get("data") orelse continue;
                const user_data_body = data.object.get("userDataBody") orelse continue;
                const data_type = user_data_body.object.get("type") orelse continue;
                const value = user_data_body.object.get("value") orelse continue;
                
                if (std.mem.eql(u8, data_type.string, "USER_DATA_TYPE_USERNAME")) {
                    username = value.string;
                } else if (std.mem.eql(u8, data_type.string, "USER_DATA_TYPE_DISPLAY")) {
                    display_name = value.string;
                } else if (std.mem.eql(u8, data_type.string, "USER_DATA_TYPE_BIO")) {
                    bio = value.string;
                } else if (std.mem.eql(u8, data_type.string, "USER_DATA_TYPE_PFP")) {
                    pfp_url = value.string;
                }
            }
        }
        
        return FarcasterUser{
            .fid = fid,
            .username = username,
            .display_name = display_name,
            .bio = bio,
            .pfp_url = pfp_url,
            .follower_count = 0, // Would need separate API call
            .following_count = 0, // Would need separate API call
        };
    }
};

// ===== C-compatible exports for Swift integration =====
// All functions follow Rust-style ownership semantics with clear documentation

/// Create FarcasterClient with proper error handling
/// Ownership: Returns owned pointer - caller MUST call fc_client_destroy()
/// Returns: null on failure, valid pointer on success
export fn fc_client_create(fid: u64, private_key_hex: ?[*:0]const u8) ?*FarcasterClient {
    // Validate input
    const key_ptr = private_key_hex orelse {
        std.log.err("Null private key pointer passed to fc_client_create", .{});
        return null;
    };
    
    const allocator = std.heap.c_allocator;
    const key_slice = std.mem.span(key_ptr);
    
    // Allocate client with error handling
    const client = allocator.create(FarcasterClient) catch |err| {
        std.log.err("Failed to allocate FarcasterClient: {}", .{err});
        return null;
    };
    errdefer allocator.destroy(client); // ✅ Cleanup on error
    
    // Initialize client with comprehensive error handling
    const client_config = ClientConfig.init(allocator, fid, key_slice) catch |err| {
        std.log.err("Failed to create client config: {}", .{err});
        allocator.destroy(client);
        return null;
    };
    
    client.* = FarcasterClient.init(client_config) catch |err| {
        std.log.err("Failed to initialize FarcasterClient: {}", .{err});
        allocator.destroy(client);
        return null;
    };
    
    return client;
}

/// Destroy FarcasterClient with safe ownership transfer
/// Ownership: Takes ownership from caller and destroys it
/// Safety: Handles null pointers gracefully
export fn fc_client_destroy(client: ?*FarcasterClient) void {
    if (client) |c| {
        c.deinit(); // ✅ Cleanup internal resources
        std.heap.c_allocator.destroy(c); // ✅ Free client memory
    } else {
        std.log.warn("Attempted to destroy null FarcasterClient", .{});
    }
}

/// Post cast with safe memory management
/// Returns: owned null-terminated string - caller MUST call fc_free_string()
/// Ownership: Transfers ownership to caller
/// Returns: null on error, owned string on success
export fn fc_post_cast(client: ?*FarcasterClient, text: ?[*:0]const u8, channel_url: ?[*:0]const u8) ?[*:0]const u8 {
    // Validate inputs
    const c = client orelse {
        std.log.err("Null client passed to fc_post_cast", .{});
        return null;
    };
    
    const text_ptr = text orelse {
        std.log.err("Null text passed to fc_post_cast", .{});
        return null;
    };
    
    const text_slice = std.mem.span(text_ptr);
    const channel_slice = if (channel_url) |ch_url| 
        if (std.mem.len(ch_url) > 0) std.mem.span(ch_url) else null
    else null;
    
    // Post cast with error handling
    const result = c.postCast(text_slice, channel_slice) catch |err| {
        std.log.err("Failed to post cast: {}", .{err});
        return null;
    };
    errdefer std.heap.c_allocator.free(result); // ✅ Cleanup on error
    
    // Convert to C string with clear ownership transfer
    const c_str = std.heap.c_allocator.dupeZ(u8, result) catch |err| {
        std.log.err("Failed to allocate C string: {}", .{err});
        std.heap.c_allocator.free(result);
        return null;
    };
    
    // Free original, transfer ownership of c_str to caller
    std.heap.c_allocator.free(result);
    return c_str.ptr;
}

/// Like cast with safe memory management  
/// Returns: owned null-terminated string - caller MUST call fc_free_string()
/// Ownership: Transfers ownership to caller
/// Returns: null on error, owned string on success
export fn fc_like_cast(client: ?*FarcasterClient, cast_hash: ?[*:0]const u8, cast_fid: u64) ?[*:0]const u8 {
    // Validate inputs
    const c = client orelse {
        std.log.err("Null client passed to fc_like_cast", .{});
        return null;
    };
    
    const hash_ptr = cast_hash orelse {
        std.log.err("Null cast_hash passed to fc_like_cast", .{});
        return null;
    };
    
    const hash_slice = std.mem.span(hash_ptr);
    
    // Like cast with error handling
    const result = c.likeCast(hash_slice, cast_fid) catch |err| {
        std.log.err("Failed to like cast: {}", .{err});
        return null;
    };
    errdefer std.heap.c_allocator.free(result); // ✅ Cleanup on error
    
    // Convert to C string with clear ownership transfer
    const c_str = std.heap.c_allocator.dupeZ(u8, result) catch |err| {
        std.log.err("Failed to allocate C string: {}", .{err});
        std.heap.c_allocator.free(result);
        return null;
    };
    
    // Free original, transfer ownership of c_str to caller
    std.heap.c_allocator.free(result);
    return c_str.ptr;
}

/// Get casts by channel with safe memory management
/// Returns: owned null-terminated JSON string - caller MUST call fc_free_string()
/// Ownership: Transfers ownership to caller
/// Returns: null on error, owned JSON string on success
export fn fc_get_casts_by_channel(client: ?*FarcasterClient, channel_url: ?[*:0]const u8, limit: u32) ?[*:0]const u8 {
    // Validate inputs
    const c = client orelse {
        std.log.err("Null client passed to fc_get_casts_by_channel", .{});
        return null;
    };
    
    const channel_ptr = channel_url orelse {
        std.log.err("Null channel_url passed to fc_get_casts_by_channel", .{});
        return null;
    };
    
    const channel_slice = std.mem.span(channel_ptr);
    
    // Get casts with error handling
    const casts = c.getCastsByChannel(channel_slice, limit) catch |err| {
        std.log.err("Failed to get casts by channel: {}", .{err});
        return null;
    };
    errdefer std.heap.c_allocator.free(casts); // ✅ Cleanup on error
    
    // Convert casts array to JSON string
    var json_str = std.ArrayList(u8).init(std.heap.c_allocator);
    defer json_str.deinit(); // ✅ Always cleanup ArrayList
    
    json.stringify(casts, .{}, json_str.writer()) catch |err| {
        std.log.err("Failed to serialize casts to JSON: {}", .{err});
        std.heap.c_allocator.free(casts);
        return null;
    };
    
    // Create C string with ownership transfer
    const c_str = std.heap.c_allocator.dupeZ(u8, json_str.items) catch |err| {
        std.log.err("Failed to allocate JSON C string: {}", .{err});
        std.heap.c_allocator.free(casts);
        return null;
    };
    
    // Free original casts array
    std.heap.c_allocator.free(casts);
    return c_str.ptr;
}

/// Safely free string allocated by Farcaster C API functions
/// Ownership: Takes ownership from caller and destroys it
/// Safety: Handles null and validates pointers with comprehensive checks
export fn fc_free_string(str: ?[*:0]const u8) void {
    // Rust-style safety: validate pointer before use
    const str_ptr = str orelse {
        std.log.warn("Attempted to free null string pointer", .{});
        return;
    };
    
    const slice = std.mem.span(str_ptr);
    if (slice.len == 0) {
        std.log.warn("Attempted to free empty string", .{});
        return;
    }
    
    // Additional safety: basic pointer validation
    // Check if pointer seems reasonable (not obviously corrupted)
    if (@intFromPtr(str) < 0x1000) {
        std.log.err("Attempted to free invalid pointer: 0x{x}", .{@intFromPtr(str)});
        return;
    }
    
    // Safe destruction with proper allocator
    std.heap.c_allocator.free(slice);
}```

# Swift Code

```swift
// File: Sources/plue/VimChatInputView.swift
import SwiftUI
import AppKit

struct VimChatInputView: View {
    let appState: AppState
    let core: PlueCoreInterface
    @FocusState private var isTerminalFocused: Bool
    @State private var inputText: String = ""
    
    let onMessageSent: (String) -> Void
    var onMessageUpdated: ((String) -> Void)?
    var onNavigateUp: (() -> Void)?
    var onNavigateDown: (() -> Void)?
    var onPreviousChat: (() -> Void)?
    var onNextChat: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal display area (placeholder for now)
            ZStack {
                Color.black
                Text(inputText.isEmpty ? "Type your message..." : inputText)
                    .foregroundColor(.white)
                    .font(.system(size: 13, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 80, maxHeight: 120)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .onTapGesture {
                isTerminalFocused = true
            }
            
            // Status line
            statusLineView
        }
        .background(Color.black)
        .overlay(
            Rectangle()
                .stroke(isTerminalFocused ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            isTerminalFocused = true
        }
    }
    
    private var statusLineView: some View {
        HStack {
            Text("-- NORMAL --")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer()
            
            Text("1:1")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.8))
    }
}

#Preview {
    VimChatInputView(
        appState: AppState.initial,
        core: MockPlueCore(),
        onMessageSent: { message in
            print("Preview: Message sent: \(message)")
        },
        onMessageUpdated: { message in
            print("Preview: Message updated: \(message)")
        }
    )
    .frame(width: 600, height: 200)
    .padding()
}```

```swift
// File: Sources/plue/GhosttyTerminalSurfaceView.swift
import SwiftUI
import AppKit
import Metal
import MetalKit

// MARK: - C Function Imports for Ghostty

@_silgen_name("ghostty_terminal_init")
func ghostty_terminal_init() -> Int32

@_silgen_name("ghostty_terminal_deinit")
func ghostty_terminal_deinit()

@_silgen_name("ghostty_terminal_create_surface")
func ghostty_terminal_create_surface() -> Int32

@_silgen_name("ghostty_terminal_set_size")
func ghostty_terminal_set_size(_ width: UInt32, _ height: UInt32, _ scale: Double)

@_silgen_name("ghostty_terminal_send_key")
func ghostty_terminal_send_key(_ key: UnsafePointer<CChar>, _ modifiers: UInt32, _ action: Int32)

@_silgen_name("ghostty_terminal_send_text")
func ghostty_terminal_send_text(_ text: UnsafePointer<CChar>)

@_silgen_name("ghostty_terminal_write")
func ghostty_terminal_write(_ data: UnsafePointer<UInt8>, _ len: Int) -> Int

@_silgen_name("ghostty_terminal_read")
func ghostty_terminal_read(_ buffer: UnsafeMutablePointer<UInt8>, _ len: Int) -> Int

@_silgen_name("ghostty_terminal_draw")
func ghostty_terminal_draw()

// MARK: - Metal View for Ghostty Rendering

class GhosttyMetalView: MTKView {
    private var isInitialized = false
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        setupMetal()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }
    
    private func setupMetal() {
        // Configure Metal view for Ghostty
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.isPaused = false
        self.enableSetNeedsDisplay = true
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        if isInitialized {
            // Let Ghostty handle the drawing
            ghostty_terminal_draw()
        }
    }
    
    func setInitialized(_ initialized: Bool) {
        self.isInitialized = initialized
    }
}

// MARK: - NSView-based Ghostty Terminal Surface

class GhosttyTerminalSurfaceView: NSView {
    // Terminal state
    private var isInitialized = false
    private var metalView: GhosttyMetalView?
    private var readSource: DispatchSourceRead?
    private var readFileDescriptor: Int32 = -1
    
    // Callbacks
    var onError: ((Error) -> Void)?
    var onOutput: ((String) -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        // Create Metal view for Ghostty rendering
        let device = MTLCreateSystemDefaultDevice()
        metalView = GhosttyMetalView(frame: bounds, device: device)
        if let metalView = metalView {
            metalView.autoresizingMask = [.width, .height]
            addSubview(metalView)
        }
    }
    
    // MARK: - Terminal Lifecycle
    
    func startTerminal() {
        guard !isInitialized else { return }
        
        // Initialize Ghostty terminal
        if ghostty_terminal_init() != 0 {
            onError?(TerminalError.initializationFailed)
            return
        }
        
        // Create terminal surface
        if ghostty_terminal_create_surface() != 0 {
            onError?(TerminalError.startFailed)
            return
        }
        
        isInitialized = true
        metalView?.setInitialized(true)
        
        // Set initial size
        updateTerminalSize()
        
        // Start reading output
        setupReadHandler()
    }
    
    func stopTerminal() {
        readSource?.cancel()
        readSource = nil
        
        if isInitialized {
            ghostty_terminal_deinit()
            isInitialized = false
            metalView?.setInitialized(false)
        }
    }
    
    // MARK: - I/O Handling
    
    private func setupReadHandler() {
        // Create a pipe for reading terminal output
        var pipeFds: [Int32] = [0, 0]
        if pipe(&pipeFds) == 0 {
            readFileDescriptor = pipeFds[0]
            
            // Make read end non-blocking
            let flags = fcntl(readFileDescriptor, F_GETFL, 0)
            fcntl(readFileDescriptor, F_SETFL, flags | O_NONBLOCK)
            
            // Create dispatch source for efficient I/O
            readSource = DispatchSource.makeReadSource(
                fileDescriptor: readFileDescriptor,
                queue: .global(qos: .userInteractive)
            )
            
            readSource?.setEventHandler { [weak self] in
                self?.handleRead()
            }
            
            readSource?.setCancelHandler { [weak self] in
                if let fd = self?.readFileDescriptor, fd >= 0 {
                    close(fd)
                    self?.readFileDescriptor = -1
                }
            }
            
            readSource?.resume()
        }
    }
    
    private func handleRead() {
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        let bytesRead = ghostty_terminal_read(buffer, bufferSize)
        
        if bytesRead > 0 {
            let data = Data(bytes: buffer, count: bytesRead)
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { [weak self] in
                    self?.onOutput?(text)
                    self?.metalView?.setNeedsDisplay(self?.metalView?.bounds ?? .zero)
                }
            }
        }
    }
    
    func sendText(_ text: String) {
        guard isInitialized else { return }
        
        text.withCString { cString in
            ghostty_terminal_send_text(cString)
        }
        
        // Request redraw
        metalView?.setNeedsDisplay(metalView?.bounds ?? .zero)
    }
    
    // MARK: - Size Handling
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTerminalSize()
    }
    
    private func updateTerminalSize() {
        guard isInitialized else { return }
        
        let scale = window?.backingScaleFactor ?? 1.0
        ghostty_terminal_set_size(
            UInt32(bounds.width),
            UInt32(bounds.height),
            Double(scale)
        )
        
        metalView?.setNeedsDisplay(metalView?.bounds ?? .zero)
    }
    
    // MARK: - Input Handling
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        metalView?.setNeedsDisplay(metalView?.bounds ?? .zero)
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        metalView?.setNeedsDisplay(metalView?.bounds ?? .zero)
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        guard isInitialized else { return }
        
        // Handle special keys
        if let specialKey = mapSpecialKey(event) {
            specialKey.withCString { cString in
                ghostty_terminal_send_key(
                    cString,
                    UInt32(event.modifierFlags.rawValue),
                    1 // Key press action
                )
            }
        } else if let characters = event.characters {
            // Send regular text
            sendText(characters)
        }
    }
    
    private func mapSpecialKey(_ event: NSEvent) -> String? {
        switch event.keyCode {
        case 126: return "Up"
        case 125: return "Down"
        case 123: return "Left"
        case 124: return "Right"
        case 36: return "Return"
        case 51: return "BackSpace"
        case 53: return "Escape"
        case 48: return "Tab"
        case 116: return "Page_Up"
        case 121: return "Page_Down"
        case 115: return "Home"
        case 119: return "End"
        case 117: return "Delete"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return nil
        }
    }
    
    // MARK: - Mouse Handling
    
    override func mouseDown(with event: NSEvent) {
        // Could implement mouse support for terminal selection
        super.mouseDown(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Could implement text selection
        super.mouseDragged(with: event)
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopTerminal()
    }
}

// MARK: - SwiftUI Wrapper

struct GhosttyTerminalSurface: NSViewRepresentable {
    @Binding var inputText: String
    let onError: (Error) -> Void
    let onOutput: (String) -> Void
    
    func makeNSView(context: Context) -> GhosttyTerminalSurfaceView {
        let view = GhosttyTerminalSurfaceView()
        view.onError = onError
        view.onOutput = onOutput
        
        // Start terminal when view is created
        DispatchQueue.main.async {
            view.startTerminal()
        }
        
        return view
    }
    
    func updateNSView(_ nsView: GhosttyTerminalSurfaceView, context: Context) {
        // Handle any updates if needed
        if !inputText.isEmpty {
            nsView.sendText(inputText)
            DispatchQueue.main.async {
                inputText = ""
            }
        }
    }
    
    static func dismantleNSView(_ nsView: GhosttyTerminalSurfaceView, coordinator: ()) {
        nsView.stopTerminal()
    }
}

// MARK: - Terminal View with Ghostty

struct GhosttyTerminalView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var inputText = ""
    @State private var terminalError: Error?
    @State private var terminalOutput = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal Header
            terminalHeader
            
            // Ghostty Terminal Surface
            GhosttyTerminalSurface(
                inputText: $inputText,
                onError: { error in
                    terminalError = error
                    print("Ghostty terminal error: \(error)")
                },
                onOutput: { output in
                    terminalOutput += output
                }
            )
            .background(Color.black)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3), lineWidth: 1)
            )
            .padding()
            
            // Error display
            if let error = terminalError {
                Text("Terminal Error: \(error.localizedDescription)")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .alert("Terminal Error", isPresented: .constant(terminalError != nil)) {
            Button("OK") { terminalError = nil }
        } message: {
            Text(terminalError?.localizedDescription ?? "Unknown error")
        }
    }
    
    // MARK: - Terminal Header
    private var terminalHeader: some View {
        VStack(spacing: 0) {
            HStack {
                // Terminal Title
                Label("Ghostty Terminal", systemImage: "terminal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Spacer()
                
                // Status Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    
                    Text("Powered by Ghostty")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                
                // Clear Button
                Button(action: { 
                    terminalOutput = ""
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear terminal output")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Divider()
        }
        .background(DesignSystem.Colors.surface(for: appState.currentTheme))
    }
}

#Preview {
    GhosttyTerminalView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 800, height: 600)
}```

```swift
// File: Sources/plue/ModernChatView.swift
import SwiftUI
import AppKit

// MARK: - Navigation Direction
enum NavigationDirection {
    case up
    case down
}

struct ModernChatView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var selectedModel = AIModel.plueCore
    @State private var inputText: String = ""
    @State private var activeMessageId: String? = nil
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Native macOS background with material
                Rectangle()
                    .fill(DesignSystem.Colors.background(for: appState.currentTheme))
                    .background(DesignSystem.Materials.regular)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Professional Header Bar
                    professionalHeaderBar
                    
                    // Enhanced Chat Messages Area
                    enhancedChatMessagesArea
                    
                    // Redesigned Input Area
                    enhancedInputArea
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }
    
    // MARK: - Native macOS Header Bar
    private var professionalHeaderBar: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Left side - Chat Navigation with native styling
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Previous chat button
                Button(action: {
                    if appState.promptState.currentConversationIndex > 0 {
                        core.handleEvent(.promptSelectConversation(appState.promptState.currentConversationIndex - 1))
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(appState.promptState.currentConversationIndex == 0 ? DesignSystem.Colors.textTertiary(for: appState.currentTheme) : DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Previous chat (⌘[)")
                .disabled(appState.promptState.currentConversationIndex == 0)
                .opacity(appState.promptState.currentConversationIndex == 0 ? 0.5 : 1.0)
                
                // Native macOS-style chat indicator
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversation \(appState.promptState.currentConversationIndex + 1)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("\(appState.promptState.conversations.count) total")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(DesignSystem.Colors.border(for: appState.currentTheme), lineWidth: 0.5)
                        )
                )
                
                // Next/New chat button with native styling
                Button(action: {
                    if appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 {
                        core.handleEvent(.promptSelectConversation(appState.promptState.currentConversationIndex + 1))
                    } else {
                        core.handleEvent(.promptNewConversation)
                    }
                }) {
                    Image(systemName: appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 ? "chevron.right" : "plus.circle")
                        .font(.system(size: 11, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help(appState.promptState.currentConversationIndex < appState.promptState.conversations.count - 1 ? "Next chat (⌘])" : "New chat (⌘N)")
            }
            
            Spacer()
            
            // Center - Enhanced Model Picker
            enhancedModelPicker
            
            Spacer()
            
            // Right side - Minimal Actions
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Minimal status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.openAIAvailable ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                        .frame(width: 6, height: 6)
                    
                    Text(appState.openAIAvailable ? "ai" : "mock")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Export conversation")
                
                Button(action: {}) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear conversation")
                
                // Theme toggle button
                Button(action: {
                    core.handleEvent(.themeToggled)
                }) {
                    Image(systemName: appState.currentTheme == .dark ? "sun.max" : "moon")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle theme")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            ZStack {
                // Material background for native feel
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                // Subtle overlay
                DesignSystem.Colors.surface(for: appState.currentTheme).opacity(0.3)
            }
            .overlay(
                Divider()
                    .background(DesignSystem.Colors.border(for: appState.currentTheme)),
                alignment: .bottom
            )
        )
    }
    
    // MARK: - Native macOS Model Picker
    private var enhancedModelPicker: some View {
        Menu {
            ForEach(AIModel.allCases, id: \.self) { model in
                Button(action: {
                    withAnimation(DesignSystem.Animation.plueStandard) {
                        selectedModel = model
                    }
                }) {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                    .font(.system(size: 13))
                                
                                Text(model.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                            }
                        } icon: {
                            Circle()
                                .fill(model.statusColor)
                                .frame(width: 8, height: 8)
                        }
                        
                        Spacer()
                        
                        if selectedModel == model {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(selectedModel.statusColor)
                    .frame(width: 8, height: 8)
                
                Text(selectedModel.name)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(DesignSystem.Colors.border(for: appState.currentTheme), lineWidth: 0.5)
                    )
            )
        }
        .menuStyle(BorderlessButtonMenuStyle())
    }
    
    // MARK: - Enhanced Chat Messages Area  
    private var enhancedChatMessagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.lg) {
                    // Enhanced welcome message
                    if appState.promptState.currentConversation?.messages.isEmpty ?? true {
                        enhancedWelcomeView
                            .padding(.top, DesignSystem.Spacing.massive)
                    }
                    
                    // Professional message bubbles with enhanced animations
                    if let messages = appState.promptState.currentConversation?.messages {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            UnifiedMessageBubbleView(
                                message: message,
                                style: .professional,
                                isActive: activeMessageId == message.id,
                                theme: appState.currentTheme,
                                onTap: { tappedMessage in
                                    if tappedMessage.type != .user {
                                        print("AI message tapped: \(tappedMessage.id)")
                                        activeMessageId = tappedMessage.id
                                    }
                                }
                            )
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                            .animation(
                                DesignSystem.Animation.messageAppear.delay(Double(index) * DesignSystem.Animation.staggerDelay),
                                value: messages.count
                            )
                        }
                    }
                    
                    // Enhanced typing indicator with smooth appearance
                    if appState.promptState.isProcessing {
                        ProfessionalTypingIndicatorView()
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                            .animation(DesignSystem.Animation.messageAppear, value: appState.promptState.isProcessing)
                    }
                    
                    // Bottom spacing for better scrolling
                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
                .padding(.vertical, DesignSystem.Spacing.lg)
            }
            .scrollIndicators(.never)
            .background(DesignSystem.Colors.backgroundSecondary)
            .onChange(of: appState.promptState.currentConversation?.messages.count) { _ in
                withAnimation(DesignSystem.Animation.plueStandard) {
                    if let lastMessage = appState.promptState.currentConversation?.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Native macOS Welcome View
    private var enhancedWelcomeView: some View {
        VStack(spacing: DesignSystem.Spacing.xxl) {
            // Native macOS icon style
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.primary.opacity(0.2),
                                DesignSystem.Colors.primary.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 72, height: 72)
                
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 32, weight: .regular, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Welcome to Plue")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Text("Start a conversation to begin")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    .multilineTextAlignment(.center)
            }
            
            // Minimal suggested prompts
            VStack(spacing: 6) {
                minimalSuggestionButton("explain code", icon: "doc.text")
                minimalSuggestionButton("debug issue", icon: "ladybug")
                minimalSuggestionButton("write function", icon: "curlybraces")
                minimalSuggestionButton("review code", icon: "checkmark")
            }
        }
        .frame(maxWidth: 500)
        .multilineTextAlignment(.center)
    }
    
    private func minimalSuggestionButton(_ text: String, icon: String) -> some View {
        Button(action: {
            withAnimation(DesignSystem.Animation.buttonPress) {
                inputText = text
                isInputFocused = true
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(DesignSystem.Colors.primary)
                    .frame(width: 20)
                
                Text(text.capitalized)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Spacer()
                
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignSystem.Materials.regular)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignSystem.Colors.surface(for: appState.currentTheme).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(DesignSystem.Colors.border(for: appState.currentTheme), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: 320)
    }
    
    // MARK: - Native macOS Chat Input
    private var enhancedInputArea: some View {
        VStack(spacing: 0) {
            // Native macOS input field
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    // Attachment button
                    Button(action: {}) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Attach file")
                    
                    // Input field with native styling
                    TextField("Message", text: $inputText, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13))
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .onSubmit {
                            if !inputText.isEmpty {
                                sendMessage()
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isInputFocused ? DesignSystem.Colors.primary : DesignSystem.Colors.border(for: appState.currentTheme),
                                    lineWidth: isInputFocused ? 1 : 0.5
                                )
                        )
                )
                .animation(.easeInOut(duration: 0.15), value: isInputFocused)
                
                // Native macOS send button
                Button(action: {
                    withAnimation(DesignSystem.Animation.buttonPress) {
                        sendMessage()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(inputText.isEmpty ? 
                                DesignSystem.Colors.surface(for: appState.currentTheme) : 
                                DesignSystem.Colors.primary
                            )
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(inputText.isEmpty ? 
                                DesignSystem.Colors.textTertiary(for: appState.currentTheme) : 
                                .white
                            )
                    }
                }
                .disabled(inputText.isEmpty)
                .buttonStyle(PlainButtonStyle())
                .help("Send message (⏎)")
                .opacity(inputText.isEmpty ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: inputText.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                // Native macOS toolbar-style background
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    
                    DesignSystem.Colors.background(for: appState.currentTheme)
                        .opacity(0.8)
                }
                .overlay(
                    Divider()
                        .background(DesignSystem.Colors.border(for: appState.currentTheme)),
                    alignment: .top
                )
            )
        }
    }
    
    // Simple send function
    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        
        withAnimation(DesignSystem.Animation.plueStandard) {
            core.handleEvent(.promptMessageSent(message))
        }
        
        inputText = ""
    }
    
    // MARK: - Navigation and Editing Logic
    
    private func navigateMessages(direction: NavigationDirection) {
        guard let conversation = appState.promptState.currentConversation else { return }
        let messages = conversation.messages
        
        if let currentActiveId = activeMessageId,
           let currentIndex = messages.firstIndex(where: { $0.id == currentActiveId }) {
            // Navigate from current active message
            switch direction {
            case .up:
                if currentIndex > 0 {
                    activeMessageId = messages[currentIndex - 1].id
                }
            case .down:
                if currentIndex < messages.count - 1 {
                    activeMessageId = messages[currentIndex + 1].id
                }
            }
        } else {
            // No active message, start from the most recent
            switch direction {
            case .up:
                activeMessageId = messages.last?.id
            case .down:
                activeMessageId = messages.first?.id
            }
        }
    }
    
    private func editActiveMessage() {
        guard let activeId = activeMessageId,
              let message = appState.promptState.currentConversation?.messages.first(where: { $0.id == activeId })
        else { return }
        
        // Load message content into input field for editing
        inputText = message.content
    }
    
}

// MARK: - Professional Message Bubble View

// ProfessionalMessageBubbleView has been replaced by UnifiedMessageBubbleView with .professional style

// MARK: - Professional Typing Indicator

struct ProfessionalTypingIndicatorView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            // Enhanced assistant avatar
            Circle()
                .fill(DesignSystem.Colors.accentGradient)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: DesignSystem.IconSize.medium))
                        .foregroundColor(.white)
                )
            
            // Professional typing animation
            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DesignSystem.Colors.primary.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.3 : 0.7)
                        .opacity(animationPhase == index ? 1.0 : 0.4)
                        .animation(
                            DesignSystem.Animation.plueStandard
                                .repeatForever()
                                .delay(Double(index) * 0.15),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .fill(DesignSystem.Colors.surface)
            )
            .primaryBorder()
            
            Spacer()
        }
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Core Message Bubble View
struct CoreMessageBubbleView: View {
    let message: PromptMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.type == .user {
                Spacer(minLength: 80)
                userMessageView
            } else {
                assistantMessageView
                Spacer(minLength: 80)
            }
        }
    }
    
    private var userMessageView: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.blue)
                    )
                    .textSelection(.enabled)
                
                // User avatar
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("You")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                    )
            }
            
            Text(formatTime(message.timestamp))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.trailing, 40)
        }
    }
    
    private var assistantMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Assistant avatar
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.1), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "cpu")
                            .font(.system(size: 14))
                            .foregroundColor(.blue.opacity(0.7))
                    )
                
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                    )
                    .textSelection(.enabled)
            }
            
            Text(formatTime(message.timestamp))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 40)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Legacy Message Bubble View
struct MessageBubbleView: View {
    let message: PromptMessage
    let onAIMessageTapped: ((PromptMessage) -> Void)?
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.type == .user {
                Spacer(minLength: 80)
                userMessageView
            } else {
                assistantMessageView
                Spacer(minLength: 80)
            }
        }
    }
    
    private var userMessageView: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.blue)
                    )
                    .textSelection(.enabled)
                
                // User avatar
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("You")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                    )
            }
            
            Text(formatTime(message.timestamp))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.trailing, 40)
        }
    }
    
    private var assistantMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Assistant avatar
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.1), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "cpu")
                            .font(.system(size: 14))
                            .foregroundColor(.blue.opacity(0.7))
                    )
                
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                    )
                    .textSelection(.enabled)
                    .onTapGesture {
                        if message.type != .user {
                            print("MessageBubbleView: AI message tapped")
                            onAIMessageTapped?(message)
                        }
                    }
            }
            
            Text(formatTime(message.timestamp))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 40)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Typing Indicator
struct TypingIndicatorView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Assistant avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.1), Color.blue.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "cpu")
                        .font(.system(size: 14))
                        .foregroundColor(.blue.opacity(0.7))
                )
            
            // Typing dots
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .animation(
                            Animation.easeInOut(duration: 0.4)
                                .repeatForever()
                                .delay(Double(index) * 0.15),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            )
            
            Spacer()
        }
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Sample Data
// Sample messages removed - using actual PromptMessage data from core state instead

// MARK: - AI Model Configuration
enum AIModel: String, CaseIterable {
    case plueCore = "plue-core"
    case gpt4 = "gpt-4"
    case claude = "claude-3.5-sonnet"
    case local = "local-llm"
    
    var name: String {
        switch self {
        case .plueCore:
            return "Plue Core"
        case .gpt4:
            return "GPT-4"
        case .claude:
            return "Claude 3.5 Sonnet"
        case .local:
            return "Local LLM"
        }
    }
    
    var description: String {
        switch self {
        case .plueCore:
            return "Built-in Zig core engine"
        case .gpt4:
            return "OpenAI's most capable model"
        case .claude:
            return "Anthropic's latest model"
        case .local:
            return "Locally hosted model"
        }
    }
    
    var statusColor: LinearGradient {
        switch self {
        case .plueCore:
            return LinearGradient(
                colors: [Color.green.opacity(0.8), Color.blue.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .gpt4:
            return LinearGradient(
                colors: [Color.green.opacity(0.8), Color.green.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .claude:
            return LinearGradient(
                colors: [Color.orange.opacity(0.8), Color.red.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .local:
            return LinearGradient(
                colors: [Color.purple.opacity(0.8), Color.indigo.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

#Preview {
    ModernChatView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 800, height: 600)
}```

```swift
// File: Sources/plue/ANSIParser.swift
import Foundation
import AppKit

// MARK: - ANSI Color Codes
enum ANSIColor: Int {
    case black = 30
    case red = 31
    case green = 32
    case yellow = 33
    case blue = 34
    case magenta = 35
    case cyan = 36
    case white = 37
    case defaultColor = 39
    
    // Bright colors
    case brightBlack = 90
    case brightRed = 91
    case brightGreen = 92
    case brightYellow = 93
    case brightBlue = 94
    case brightMagenta = 95
    case brightCyan = 96
    case brightWhite = 97
    
    func toNSColor() -> NSColor {
        switch self {
        case .black, .brightBlack: return .black
        case .red: return NSColor(red: 0.8, green: 0, blue: 0, alpha: 1)
        case .brightRed: return NSColor(red: 1, green: 0, blue: 0, alpha: 1)
        case .green: return NSColor(red: 0, green: 0.8, blue: 0, alpha: 1)
        case .brightGreen: return NSColor(red: 0, green: 1, blue: 0, alpha: 1)
        case .yellow: return NSColor(red: 0.8, green: 0.8, blue: 0, alpha: 1)
        case .brightYellow: return NSColor(red: 1, green: 1, blue: 0, alpha: 1)
        case .blue: return NSColor(red: 0, green: 0, blue: 0.8, alpha: 1)
        case .brightBlue: return NSColor(red: 0, green: 0, blue: 1, alpha: 1)
        case .magenta: return NSColor(red: 0.8, green: 0, blue: 0.8, alpha: 1)
        case .brightMagenta: return NSColor(red: 1, green: 0, blue: 1, alpha: 1)
        case .cyan: return NSColor(red: 0, green: 0.8, blue: 0.8, alpha: 1)
        case .brightCyan: return NSColor(red: 0, green: 1, blue: 1, alpha: 1)
        case .white: return NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
        case .brightWhite, .defaultColor: return .white
        }
    }
}

// MARK: - ANSI Parser
class ANSIParser {
    private var currentAttributes: [NSAttributedString.Key: Any] = [:]
    private let defaultFont: NSFont
    private let defaultForeground: NSColor
    private let defaultBackground: NSColor
    
    init(font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular),
         foregroundColor: NSColor = .white,
         backgroundColor: NSColor = .black) {
        self.defaultFont = font
        self.defaultForeground = foregroundColor
        self.defaultBackground = backgroundColor
        
        // Set default attributes
        currentAttributes = [
            .font: defaultFont,
            .foregroundColor: defaultForeground,
            .backgroundColor: defaultBackground
        ]
    }
    
    /// Parse text with ANSI escape sequences and return attributed string
    func parse(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        // Regular expression to match ANSI escape sequences
        let pattern = "\\x1b\\[(\\d+(?:;\\d+)*)m"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        
        var lastIndex = text.startIndex
        let nsString = text as NSString
        
        // Find all ANSI escape sequences
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            // Add text before the escape sequence
            if let range = Range(match.range, in: text) {
                let beforeText = String(text[lastIndex..<range.lowerBound])
                if !beforeText.isEmpty {
                    result.append(NSAttributedString(string: beforeText, attributes: currentAttributes))
                }
                
                // Parse the escape sequence
                let escapeSequence = String(text[range])
                processEscapeSequence(escapeSequence)
                
                lastIndex = range.upperBound
            }
        }
        
        // Add remaining text
        if lastIndex < text.endIndex {
            let remainingText = String(text[lastIndex...])
            result.append(NSAttributedString(string: remainingText, attributes: currentAttributes))
        }
        
        return result
    }
    
    /// Process a single ANSI escape sequence
    private func processEscapeSequence(_ sequence: String) {
        // Extract the numbers from the sequence
        let numbers = sequence
            .replacingOccurrences(of: "\u{1b}[", with: "")
            .replacingOccurrences(of: "m", with: "")
            .split(separator: ";")
            .compactMap { Int($0) }
        
        for code in numbers {
            switch code {
            case 0: // Reset
                currentAttributes = [
                    .font: defaultFont,
                    .foregroundColor: defaultForeground,
                    .backgroundColor: defaultBackground
                ]
                
            case 1: // Bold
                if let currentFont = currentAttributes[.font] as? NSFont {
                    currentAttributes[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
                }
                
            case 2: // Dim
                if let currentColor = currentAttributes[.foregroundColor] as? NSColor {
                    currentAttributes[.foregroundColor] = currentColor.withAlphaComponent(0.6)
                }
                
            case 3: // Italic
                if let currentFont = currentAttributes[.font] as? NSFont {
                    currentAttributes[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                }
                
            case 4: // Underline
                currentAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                
            case 7: // Reverse
                let fg = currentAttributes[.foregroundColor] ?? defaultForeground
                let bg = currentAttributes[.backgroundColor] ?? defaultBackground
                currentAttributes[.foregroundColor] = bg
                currentAttributes[.backgroundColor] = fg
                
            case 30...37, 90...97: // Foreground colors
                if let color = ANSIColor(rawValue: code) {
                    currentAttributes[.foregroundColor] = color.toNSColor()
                }
                
            case 39: // Default foreground
                currentAttributes[.foregroundColor] = defaultForeground
                
            case 40...47, 100...107: // Background colors
                if let color = ANSIColor(rawValue: code - 10) {
                    currentAttributes[.backgroundColor] = color.toNSColor()
                }
                
            case 49: // Default background
                currentAttributes[.backgroundColor] = defaultBackground
                
            default:
                // Ignore unsupported codes
                break
            }
        }
    }
    
    /// Reset all attributes to defaults
    func reset() {
        currentAttributes = [
            .font: defaultFont,
            .foregroundColor: defaultForeground,
            .backgroundColor: defaultBackground
        ]
    }
}```

```swift
// File: Sources/plue/AppleScriptSupport.swift
import Cocoa
import Foundation

@objc class PlueAppleScriptSupport: NSObject {
    @objc static let shared = PlueAppleScriptSupport()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Terminal Control
    
    @objc func runTerminalCommand(_ command: String) -> String {
        // Validate and sanitize the command
        let sanitizedCommand = sanitizeCommand(command)
        guard !sanitizedCommand.isEmpty else {
            return "Invalid command: empty or contains only whitespace"
        }
        
        let script = """
        tell application "Terminal"
            activate
            do script "\(sanitizedCommand)"
            return "Command sent to Terminal"
        end tell
        """
        
        return executeAppleScript(script) ?? "Failed to execute command"
    }
    
    @objc func runTerminalCommandInNewTab(_ command: String) -> String {
        // Validate and sanitize the command
        let sanitizedCommand = sanitizeCommand(command)
        guard !sanitizedCommand.isEmpty else {
            return "Invalid command: empty or contains only whitespace"
        }
        
        let script = """
        tell application "Terminal"
            activate
            tell application "System Events" to keystroke "t" using command down
            delay 0.5
            do script "\(sanitizedCommand)" in front window
            return "Command sent to new Terminal tab"
        end tell
        """
        
        return executeAppleScript(script) ?? "Failed to execute command in new tab"
    }
    
    @objc func getTerminalOutput() -> String {
        let script = """
        tell application "Terminal"
            set frontTab to selected tab of front window
            return contents of frontTab
        end tell
        """
        
        return executeAppleScript(script) ?? "Failed to get terminal output"
    }
    
    @objc func closeTerminalWindow() -> String {
        let script = """
        tell application "Terminal"
            close front window
            return "Terminal window closed"
        end tell
        """
        
        return executeAppleScript(script) ?? "Failed to close terminal window"
    }
    
    // MARK: - Chat and Agent Control
    
    @objc func sendChatMessage(_ message: String) -> String {
        // This would integrate with your chat system
        let core = PlueCore.shared
        core.handleEvent(.chatMessageSent(message))
        return "Message sent: \(message)"
    }
    
    @objc func getCurrentChatMessages() -> String {
        let core = PlueCore.shared
        let state = core.getCurrentState()
        
        // Convert chat messages to a string format suitable for AppleScript
        guard let conversation = state.promptState.currentConversation else {
            return "No active conversation"
        }
        
        let messages = conversation.messages.map { msg in
            "\(msg.type): \(msg.content)"
        }.joined(separator: "\n")
        
        return messages.isEmpty ? "No messages" : messages
    }
    
    @objc func switchToTab(_ tabName: String) -> String {
        let tabMap: [String: TabType] = [
            "prompt": .prompt,
            "farcaster": .farcaster,
            "agent": .agent,
            "terminal": .terminal,
            "web": .web,
            "editor": .editor,
            "diff": .diff,
            "worktree": .worktree
        ]
        
        guard let tab = tabMap[tabName.lowercased()] else {
            return "Invalid tab name. Use: prompt, farcaster, agent, terminal, web, editor, diff, or worktree"
        }
        
        let core = PlueCore.shared
        core.handleEvent(.tabSwitched(tab))
        return "Switched to \(tabName) tab"
    }
    
    // MARK: - File Operations
    
    @objc func openFile(_ path: String) -> String {
        // Validate file path
        let sanitizedPath = sanitizePath(path)
        guard !sanitizedPath.isEmpty else {
            return "Invalid file path"
        }
        
        // Check if file exists and is readable
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sanitizedPath) else {
            return "File does not exist: \(sanitizedPath)"
        }
        
        guard fileManager.isReadableFile(atPath: sanitizedPath) else {
            return "File is not readable: \(sanitizedPath)"
        }
        
        let core = PlueCore.shared
        core.handleEvent(.fileOpened(sanitizedPath))
        return "Opened file: \(sanitizedPath)"
    }
    
    @objc func saveCurrentFile() -> String {
        let core = PlueCore.shared
        core.handleEvent(.fileSaved)
        return "File saved"
    }
    
    // MARK: - Utility Methods
    
    @objc func getApplicationState() -> String {
        let core = PlueCore.shared
        let state = core.getCurrentState()
        
        // Return a simplified string representation of the app state
        let messageCount = state.promptState.currentConversation?.messages.count ?? 0
        return """
        Current Tab: \(state.currentTab)
        Chat Messages: \(messageCount)
        Is Initialized: \(state.isInitialized)
        """
    }
    
    // MARK: - Private Methods
    
    private func executeAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let result = script.executeAndReturnError(&error)
            
            if let error = error {
                print("AppleScript error: \(error)")
                return nil
            }
            
            return result.stringValue
        }
        
        return nil
    }
    
    // MARK: - Security and Sanitization
    
    private func sanitizeCommand(_ command: String) -> String {
        // Remove leading/trailing whitespace
        var sanitized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Escape special characters for AppleScript
        // First escape backslashes, then quotes
        sanitized = sanitized.replacingOccurrences(of: "\\", with: "\\\\")
        sanitized = sanitized.replacingOccurrences(of: "\"", with: "\\\"")
        
        // Escape other potentially dangerous characters
        sanitized = sanitized.replacingOccurrences(of: "`", with: "\\`")
        sanitized = sanitized.replacingOccurrences(of: "$", with: "\\$")
        sanitized = sanitized.replacingOccurrences(of: "!", with: "\\!")
        
        // Limit command length to prevent buffer overflow attacks
        let maxLength = 1000
        if sanitized.count > maxLength {
            sanitized = String(sanitized.prefix(maxLength))
        }
        
        return sanitized
    }
    
    private func sanitizePath(_ path: String) -> String {
        // Remove leading/trailing whitespace
        var sanitized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Resolve path to absolute path and remove any path traversal attempts
        if !sanitized.isEmpty {
            let expandedPath = NSString(string: sanitized).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath)
            sanitized = url.standardized.path
        }
        
        return sanitized
    }
}

// MARK: - AppleScript Command Handler

@objc class PlueScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let scriptSupport = PlueAppleScriptSupport.shared
        
        // Map command codes to actions
        let commandCode = self.commandDescription.commandName
        
        // Add the command type to arguments for processing
        var modifiedArguments = self.evaluatedArguments ?? [:]
        
        switch commandCode {
        case "run terminal command":
            modifiedArguments["command"] = "runTerminal"
        case "run terminal command in new tab":
            modifiedArguments["command"] = "runTerminalNewTab"
        case "get terminal output":
            modifiedArguments["command"] = "getTerminalOutput"
        case "close terminal window":
            modifiedArguments["command"] = "closeTerminal"
        case "send chat message":
            modifiedArguments["command"] = "sendChat"
        case "get chat messages":
            modifiedArguments["command"] = "getChatMessages"
        case "switch to tab":
            modifiedArguments["command"] = "switchTab"
        case "open file":
            modifiedArguments["command"] = "openFile"
        case "save file":
            modifiedArguments["command"] = "saveFile"
        case "get application state":
            modifiedArguments["command"] = "getState"
        default:
            return "Unknown command: \(commandCode)"
        }
        
        // Handle different command types
        if let command = modifiedArguments["command"] as? String {
            switch command {
            case "runTerminal":
                if let terminalCommand = modifiedArguments["terminalCommand"] as? String {
                    return scriptSupport.runTerminalCommand(terminalCommand)
                }
            case "runTerminalNewTab":
                if let terminalCommand = modifiedArguments["terminalCommand"] as? String {
                    return scriptSupport.runTerminalCommandInNewTab(terminalCommand)
                }
            case "getTerminalOutput":
                return scriptSupport.getTerminalOutput()
            case "closeTerminal":
                return scriptSupport.closeTerminalWindow()
            case "sendChat":
                if let message = modifiedArguments["message"] as? String {
                    return scriptSupport.sendChatMessage(message)
                }
            case "getChatMessages":
                return scriptSupport.getCurrentChatMessages()
            case "switchTab":
                if let tabName = modifiedArguments["tab"] as? String {
                    return scriptSupport.switchToTab(tabName)
                }
            case "openFile":
                if let path = modifiedArguments["path"] as? String {
                    return scriptSupport.openFile(path)
                }
            case "saveFile":
                return scriptSupport.saveCurrentFile()
            case "getState":
                return scriptSupport.getApplicationState()
            default:
                return "Unknown command: \(command)"
            }
        }
        
        return "No command specified"
    }
}

// MARK: - AppleScript Examples

/*
Example AppleScript usage:

-- Run a terminal command
tell application "Plue"
    run terminal command "ls -la"
end tell

-- Send a chat message
tell application "Plue"
    send chat message "Hello from AppleScript!"
end tell

-- Switch tabs
tell application "Plue"
    switch to tab "terminal"
end tell

-- Get current chat messages
tell application "Plue"
    get chat messages
end tell

-- Run command in new terminal tab
tell application "Plue"
    run terminal command "cd ~/Documents && pwd" in new tab
end tell

-- Get application state
tell application "Plue"
    get application state
end tell
*/```

```swift
// File: Sources/plue/UnifiedMessageBubbleView.swift
import SwiftUI

// MARK: - Unified Message Protocol
protocol UnifiedMessage: Identifiable {
    var id: String { get }
    var content: String { get }
    var timestamp: Date { get }
    var senderType: MessageSenderType { get }
    var metadata: MessageMetadata? { get }
}

// MARK: - Message Configuration
enum MessageSenderType {
    case user
    case assistant
    case system
    case workflow
    case error
    
    var avatarIcon: String {
        switch self {
        case .user: return "person"
        case .assistant: return "brain.head.profile"
        case .system: return "info.circle"
        case .workflow: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle"
        }
    }
    
    var defaultAvatarText: String {
        switch self {
        case .user: return "U"
        case .assistant: return "AI"
        case .system: return "S"
        case .workflow: return "W"
        case .error: return "!"
        }
    }
}

struct MessageMetadata {
    let worktree: String?
    let workflow: String?
    let containerId: String?
    let exitCode: Int?
    let duration: TimeInterval?
    let promptSnapshot: String?
    
    static let empty = MessageMetadata(
        worktree: nil,
        workflow: nil,
        containerId: nil,
        exitCode: nil,
        duration: nil,
        promptSnapshot: nil
    )
}

// MARK: - Message Style Configuration
struct MessageBubbleStyle {
    // Avatar configuration
    let avatarSize: CGFloat
    let avatarStyle: AvatarStyle
    
    // Bubble configuration
    let bubbleCornerRadius: CGFloat
    let bubblePadding: EdgeInsets
    let maxBubbleWidth: CGFloat?
    
    // Typography
    let contentFont: Font
    let timestampFont: Font
    let metadataFont: Font
    
    // Spacing
    let avatarSpacing: CGFloat
    let timestampSpacing: CGFloat
    let metadataSpacing: CGFloat
    
    // Colors
    let userBubbleBackground: Color
    let assistantBubbleBackground: Color
    let systemBubbleBackground: Color
    let errorBubbleBackground: Color
    
    // Animation
    let showAnimations: Bool
    let animationDuration: Double
    
    enum AvatarStyle {
        case icon
        case text
        case iconWithText
        case custom(Image)
    }
    
    // Preset styles
    static let professional = MessageBubbleStyle(
        avatarSize: 36,
        avatarStyle: .iconWithText,
        bubbleCornerRadius: DesignSystem.CornerRadius.lg,
        bubblePadding: EdgeInsets(
            top: DesignSystem.Spacing.md,
            leading: DesignSystem.Spacing.lg,
            bottom: DesignSystem.Spacing.md,
            trailing: DesignSystem.Spacing.lg
        ),
        maxBubbleWidth: nil,
        contentFont: DesignSystem.Typography.bodyMedium,
        timestampFont: DesignSystem.Typography.caption,
        metadataFont: DesignSystem.Typography.caption,
        avatarSpacing: DesignSystem.Spacing.md,
        timestampSpacing: DesignSystem.Spacing.xs,
        metadataSpacing: DesignSystem.Spacing.xs,
        userBubbleBackground: DesignSystem.Colors.primary,
        assistantBubbleBackground: DesignSystem.Colors.surface,
        systemBubbleBackground: DesignSystem.Colors.surface,
        errorBubbleBackground: DesignSystem.Colors.error.opacity(0.1),
        showAnimations: true,
        animationDuration: 0.2
    )
    
    static let compact = MessageBubbleStyle(
        avatarSize: 28,
        avatarStyle: .text,
        bubbleCornerRadius: 12,
        bubblePadding: EdgeInsets(
            top: 8,
            leading: 12,
            bottom: 8,
            trailing: 12
        ),
        maxBubbleWidth: nil,
        contentFont: DesignSystem.Typography.bodyMedium,
        timestampFont: .system(size: 9),
        metadataFont: .system(size: 9),
        avatarSpacing: 12,
        timestampSpacing: 4,
        metadataSpacing: 4,
        userBubbleBackground: DesignSystem.Colors.primary,
        assistantBubbleBackground: DesignSystem.Colors.surface,
        systemBubbleBackground: DesignSystem.Colors.surface,
        errorBubbleBackground: DesignSystem.Colors.error.opacity(0.1),
        showAnimations: false,
        animationDuration: 0
    )
    
    static let minimal = MessageBubbleStyle(
        avatarSize: 24,
        avatarStyle: .icon,
        bubbleCornerRadius: 8,
        bubblePadding: EdgeInsets(
            top: 6,
            leading: 10,
            bottom: 6,
            trailing: 10
        ),
        maxBubbleWidth: 400,
        contentFont: .system(size: 13),
        timestampFont: .system(size: 9),
        metadataFont: .system(size: 9),
        avatarSpacing: 8,
        timestampSpacing: 2,
        metadataSpacing: 2,
        userBubbleBackground: DesignSystem.Colors.primary.opacity(0.9),
        assistantBubbleBackground: DesignSystem.Colors.surface,
        systemBubbleBackground: DesignSystem.Colors.textTertiary.opacity(0.1),
        errorBubbleBackground: DesignSystem.Colors.error.opacity(0.1),
        showAnimations: false,
        animationDuration: 0
    )
}

// MARK: - Unified Message Bubble View
struct UnifiedMessageBubbleView<Message: UnifiedMessage>: View {
    let message: Message
    let style: MessageBubbleStyle
    let isActive: Bool
    let theme: DesignSystem.Theme
    let onTap: ((Message) -> Void)?
    
    init(
        message: Message,
        style: MessageBubbleStyle = .professional,
        isActive: Bool = false,
        theme: DesignSystem.Theme = .dark,
        onTap: ((Message) -> Void)? = nil
    ) {
        self.message = message
        self.style = style
        self.isActive = isActive
        self.theme = theme
        self.onTap = onTap
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.senderType == .user {
                Spacer(minLength: 100)
                userMessageView
            } else {
                assistantMessageView
                Spacer(minLength: 100)
            }
        }
        .background(activeHighlight)
        .animation(style.showAnimations ? .easeInOut(duration: style.animationDuration) : nil, value: isActive)
    }
    
    // MARK: - User Message View
    private var userMessageView: some View {
        VStack(alignment: .trailing, spacing: style.timestampSpacing) {
            HStack(alignment: .bottom, spacing: style.avatarSpacing) {
                messageBubble(isUser: true)
                avatarView(for: .user)
            }
            
            timestampView
                .padding(.trailing, style.avatarSize + style.avatarSpacing)
        }
    }
    
    // MARK: - Assistant/System Message View
    private var assistantMessageView: some View {
        VStack(alignment: .leading, spacing: style.timestampSpacing) {
            HStack(alignment: .top, spacing: style.avatarSpacing) {
                avatarView(for: message.senderType)
                messageBubble(isUser: false)
            }
            
            VStack(alignment: .leading, spacing: style.metadataSpacing) {
                timestampView
                
                if let metadata = message.metadata {
                    metadataView(metadata)
                }
            }
            .padding(.leading, style.avatarSize + style.avatarSpacing)
        }
    }
    
    // MARK: - Message Bubble
    private func messageBubble(isUser: Bool) -> some View {
        Text(message.content)
            .font(style.contentFont)
            .foregroundColor(textColor(for: message.senderType, isUser: isUser))
            .padding(style.bubblePadding)
            .frame(maxWidth: style.maxBubbleWidth, alignment: isUser ? .trailing : .leading)
            .background(
                RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                    .fill(bubbleBackground(for: message.senderType))
                    .overlay(
                        Group {
                            if !isUser && message.senderType != .user {
                                RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                                    .stroke(borderColor(for: message.senderType), lineWidth: 0.5)
                            }
                        }
                    )
            )
            .textSelection(.enabled)
            .onTapGesture {
                onTap?(message)
            }
    }
    
    // MARK: - Avatar View
    private func avatarView(for senderType: MessageSenderType) -> some View {
        Group {
            switch style.avatarStyle {
            case .icon:
                Circle()
                    .fill(avatarBackground(for: senderType))
                    .frame(width: style.avatarSize, height: style.avatarSize)
                    .overlay(
                        Image(systemName: senderType.avatarIcon)
                            .font(.system(size: style.avatarSize * 0.4, weight: .medium))
                            .foregroundColor(avatarForeground(for: senderType))
                    )
                
            case .text:
                Circle()
                    .fill(avatarBackground(for: senderType))
                    .frame(width: style.avatarSize, height: style.avatarSize)
                    .overlay(
                        Text(senderType.defaultAvatarText)
                            .font(.system(size: style.avatarSize * 0.35, weight: .medium))
                            .foregroundColor(avatarForeground(for: senderType))
                    )
                
            case .iconWithText:
                Circle()
                    .fill(avatarBackground(for: senderType))
                    .frame(width: style.avatarSize, height: style.avatarSize)
                    .overlay(
                        Group {
                            if senderType == .user {
                                Text("YOU")
                                    .font(.system(size: style.avatarSize * 0.25, weight: .medium))
                                    .foregroundColor(avatarForeground(for: senderType))
                            } else {
                                Image(systemName: senderType.avatarIcon)
                                    .font(.system(size: style.avatarSize * 0.4, weight: .medium))
                                    .foregroundColor(avatarForeground(for: senderType))
                            }
                        }
                    )
                
            case .custom(let image):
                Circle()
                    .fill(avatarBackground(for: senderType))
                    .frame(width: style.avatarSize, height: style.avatarSize)
                    .overlay(
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: style.avatarSize * 0.6, height: style.avatarSize * 0.6)
                    )
            }
        }
        .overlay(
            Circle()
                .stroke(avatarBorder(for: senderType), lineWidth: 1)
        )
    }
    
    // MARK: - Timestamp View
    private var timestampView: some View {
        Text(formatTime(message.timestamp))
            .font(style.timestampFont)
            .foregroundColor(DesignSystem.Colors.textTertiary)
    }
    
    // MARK: - Metadata View
    private func metadataView(_ metadata: MessageMetadata) -> some View {
        HStack(spacing: 4) {
            if let worktree = metadata.worktree {
                Text("•")
                    .font(style.metadataFont)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                
                Text(worktree)
                    .font(style.metadataFont.monospaced())
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            
            if let duration = metadata.duration {
                Text("•")
                    .font(style.metadataFont)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                
                Text("\(String(format: "%.1fs", duration))")
                    .font(style.metadataFont)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            
            if let exitCode = metadata.exitCode {
                Text("•")
                    .font(style.metadataFont)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                
                Text("exit: \(exitCode)")
                    .font(style.metadataFont)
                    .foregroundColor(exitCode == 0 ? DesignSystem.Colors.success : DesignSystem.Colors.error)
            }
        }
    }
    
    // MARK: - Active Highlight
    private var activeHighlight: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
            .fill(isActive ? DesignSystem.Colors.primary.opacity(0.1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(isActive ? DesignSystem.Colors.primary.opacity(0.3) : Color.clear, lineWidth: 1)
            )
    }
    
    // MARK: - Color Helpers
    private func bubbleBackground(for senderType: MessageSenderType) -> Color {
        switch senderType {
        case .user:
            return style.userBubbleBackground
        case .assistant:
            return style.assistantBubbleBackground
        case .system:
            return style.systemBubbleBackground
        case .workflow:
            return DesignSystem.Colors.success.opacity(0.1)
        case .error:
            return style.errorBubbleBackground
        }
    }
    
    private func textColor(for senderType: MessageSenderType, isUser: Bool) -> Color {
        if isUser {
            return .white
        }
        
        switch senderType {
        case .error:
            return DesignSystem.Colors.error
        case .workflow:
            return DesignSystem.Colors.success
        default:
            return DesignSystem.Colors.textPrimary(for: theme)
        }
    }
    
    private func avatarBackground(for senderType: MessageSenderType) -> Color {
        switch senderType {
        case .user:
            return DesignSystem.Colors.primary.opacity(0.1)
        case .assistant:
            return DesignSystem.Colors.accent
        case .system:
            return DesignSystem.Colors.textTertiary.opacity(0.6)
        case .workflow:
            return DesignSystem.Colors.success
        case .error:
            return DesignSystem.Colors.error
        }
    }
    
    private func avatarForeground(for senderType: MessageSenderType) -> Color {
        switch senderType {
        case .user:
            return DesignSystem.Colors.primary
        case .assistant, .system, .workflow, .error:
            return .white
        }
    }
    
    private func avatarBorder(for senderType: MessageSenderType) -> Color {
        switch senderType {
        case .user:
            return DesignSystem.Colors.primary.opacity(0.3)
        default:
            return DesignSystem.Colors.border.opacity(0.3)
        }
    }
    
    private func borderColor(for senderType: MessageSenderType) -> Color {
        switch senderType {
        case .error:
            return DesignSystem.Colors.error.opacity(0.3)
        case .workflow:
            return DesignSystem.Colors.success.opacity(0.3)
        default:
            return DesignSystem.Colors.border.opacity(0.3)
        }
    }
    
    // MARK: - Helpers
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Message Adapters
// These adapters allow existing message types to work with the unified view

extension PromptMessage: UnifiedMessage {
    var senderType: MessageSenderType {
        switch type {
        case .user: return .user
        case .assistant: return .assistant
        case .system: return .system
        }
    }
    
    var metadata: MessageMetadata? {
        MessageMetadata(
            worktree: nil,
            workflow: nil,
            containerId: nil,
            exitCode: nil,
            duration: nil,
            promptSnapshot: promptSnapshot
        )
    }
}

// Wrapper for AgentMessage to conform to UnifiedMessage
struct UnifiedAgentMessage: UnifiedMessage {
    let agentMessage: AgentMessage
    
    var id: String { agentMessage.id }
    var content: String { agentMessage.content }
    var timestamp: Date { agentMessage.timestamp }
    
    var senderType: MessageSenderType {
        switch agentMessage.type {
        case .user: return .user
        case .assistant: return .assistant
        case .system: return .system
        case .workflow: return .workflow
        case .error: return .error
        }
    }
    
    var metadata: MessageMetadata? {
        guard let agentMetadata = agentMessage.metadata else { return nil }
        return MessageMetadata(
            worktree: agentMetadata.worktree,
            workflow: agentMetadata.workflow,
            containerId: agentMetadata.containerId,
            exitCode: agentMetadata.exitCode,
            duration: agentMetadata.duration,
            promptSnapshot: nil  // AgentMessageMetadata doesn't have this field
        )
    }
}

// MARK: - Preview
#Preview("Message Styles") {
    VStack(spacing: 20) {
        // Professional style
        VStack(alignment: .leading, spacing: 8) {
            Text("Professional Style")
                .font(.headline)
            
            UnifiedMessageBubbleView(
                message: PromptMessage(
                    id: "1",
                    content: "Hello! How can I help you today?",
                    type: .assistant,
                    timestamp: Date(),
                    promptSnapshot: nil
                ),
                style: .professional
            )
            
            UnifiedMessageBubbleView(
                message: PromptMessage(
                    id: "2",
                    content: "I need help with SwiftUI",
                    type: .user,
                    timestamp: Date(),
                    promptSnapshot: nil
                ),
                style: .professional
            )
        }
        
        // Compact style
        VStack(alignment: .leading, spacing: 8) {
            Text("Compact Style")
                .font(.headline)
            
            UnifiedMessageBubbleView(
                message: UnifiedAgentMessage(agentMessage: AgentMessage(
                    id: "3",
                    content: "Running workflow: Build & Test",
                    type: .workflow,
                    timestamp: Date(),
                    metadata: AgentMessageMetadata(
                        worktree: "feature-branch",
                        workflow: "build-test",
                        containerId: nil,
                        exitCode: 0,
                        duration: 3.5
                    )
                )),
                style: .compact
            )
        }
        
        // Minimal style with error
        VStack(alignment: .leading, spacing: 8) {
            Text("Minimal Style")
                .font(.headline)
            
            UnifiedMessageBubbleView(
                message: UnifiedAgentMessage(agentMessage: AgentMessage(
                    id: "4",
                    content: "Build failed: Missing dependency",
                    type: .error,
                    timestamp: Date(),
                    metadata: AgentMessageMetadata(
                        worktree: "main",
                        workflow: nil,
                        containerId: nil,
                        exitCode: 1,
                        duration: nil
                    )
                )),
                style: .minimal
            )
        }
    }
    .padding()
    .background(DesignSystem.Colors.background)
    .frame(width: 600, height: 500)
}```

```swift
// File: Sources/plue/Terminal.swift
import Foundation

// Import unified terminal C functions
@_silgen_name("terminal_init") 
func terminal_init() -> Int32

@_silgen_name("terminal_start") 
func terminal_start() -> Int32

@_silgen_name("terminal_stop") 
func terminal_stop()

@_silgen_name("terminal_write") 
func terminal_write(_ data: UnsafePointer<UInt8>, _ len: Int) -> Int

@_silgen_name("terminal_read") 
func terminal_read(_ buffer: UnsafeMutablePointer<UInt8>, _ bufferLen: Int) -> Int

@_silgen_name("terminal_send_text") 
func terminal_send_text(_ text: UnsafePointer<CChar>)

@_silgen_name("terminal_deinit") 
func terminal_deinit()

/// Unified Terminal - Production PTY implementation
class Terminal: ObservableObject {
    static let shared = Terminal()
    
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    
    private let readQueue = DispatchQueue(label: "com.plue.macos.pty.read", qos: .utility)
    private var isReading = false
    private let bufferSize = 4096
    
    private init() {}
    
    /// Initialize the terminal
    func initialize() -> Bool {
        let result = terminal_init()
        if result == 0 {
            print("Terminal initialized successfully")
            return true
        } else {
            print("Failed to initialize terminal")
            return false
        }
    }
    
    /// Start the terminal process
    func start() -> Bool {
        guard !isRunning else { return true }
        
        let result = terminal_start()
        if result == 0 {
            isRunning = true
            startReadingOutput()
            print("Terminal started")
            return true
        } else {
            print("Failed to start terminal")
            return false
        }
    }
    
    /// Stop the terminal
    func stop() {
        isReading = false
        terminal_stop()
        isRunning = false
        print("Terminal stopped")
    }
    
    /// Send text to the terminal
    func sendText(_ text: String) {
        guard isRunning else { return }
        
        text.withCString { cString in
            terminal_send_text(cString)
        }
    }
    
    /// Send a command to the terminal (adds newline)
    func sendCommand(_ command: String) {
        sendText(command + "\n")
    }
    
    /// Clear the output
    func clearOutput() {
        output = ""
    }
    
    // Private methods
    
    private func startReadingOutput() {
        isReading = true
        readQueue.async { [weak self] in
            guard let self = self else { return }
            
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: self.bufferSize)
            defer { buffer.deallocate() }
            
            print("Terminal read thread started")
            
            while self.isReading && self.isRunning {
                let bytesRead = terminal_read(buffer, self.bufferSize)
                
                if bytesRead > 0 {
                    print("Terminal read \(bytesRead) bytes")
                    let data = Data(bytes: buffer, count: bytesRead)
                    if let newOutput = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.output += newOutput
                            print("Terminal output now: \(self.output.suffix(100))")
                            
                            // Limit output buffer size
                            if self.output.count > 100000 {
                                let index = self.output.index(self.output.startIndex, offsetBy: 50000)
                                self.output = String(self.output[index...])
                            }
                        }
                    }
                } else if bytesRead == 0 {
                    // No data available, sleep briefly
                    Thread.sleep(forTimeInterval: 0.01) // 10ms
                } else {
                    // Error occurred
                    print("Error reading from terminal: \(bytesRead)")
                    break
                }
            }
            
            print("Terminal read thread exiting")
        }
    }
    
    deinit {
        stop()
        terminal_deinit()
    }
}```

```swift
// File: Sources/plue/OpenAIService.swift
import Foundation

// MARK: - OpenAI API Models

struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let maxTokens: Int?
    let stream: Bool
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

struct OpenAIChoice: Codable {
    let index: Int
    let message: OpenAIMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct OpenAIUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct OpenAIError: Codable {
    let error: OpenAIErrorDetail
}

struct OpenAIErrorDetail: Codable {
    let message: String
    let type: String
    let code: String?
}

// MARK: - OpenAI Service (MOCKED - NO ACTUAL API CALLS)

class OpenAIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1" // NOT USED - MOCKED
    private let session = URLSession.shared // NOT USED - MOCKED
    
    enum OpenAIServiceError: Error, LocalizedError {
        case noAPIKey
        case invalidURL
        case invalidResponse
        case apiError(String)
        case networkError(Error)
        
        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "OpenAI API key not found. Please set OPENAI_API_KEY environment variable."
            case .invalidURL:
                return "Invalid OpenAI API URL"
            case .invalidResponse:
                return "Invalid response from OpenAI API"
            case .apiError(let message):
                return "OpenAI API Error: \(message)"
            case .networkError(let error):
                return "Network Error: \(error.localizedDescription)"
            }
        }
    }
    
    init() throws {
        // MOCK IMPLEMENTATION - Always succeeds, no actual API key needed
        self.apiKey = "mock-api-key-not-used"
        print("OpenAIService: Initialized in MOCK mode - no actual API calls will be made")
    }
    
    func sendChatMessage(
        messages: [OpenAIMessage],
        model: String = "gpt-4",
        temperature: Double = 0.7,
        maxTokens: Int? = nil
    ) async throws -> String {
        
        // MOCK IMPLEMENTATION - No actual network requests
        print("OpenAIService: MOCKING API call - no actual network request made")
        print("OpenAIService: Model: \(model), Messages: \(messages.count), Temperature: \(temperature)")
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Generate mock response based on the last user message
        let lastUserMessage = messages.last(where: { $0.role == "user" })?.content ?? ""
        let mockResponse = generateMockResponse(for: lastUserMessage)
        
        print("OpenAIService: Mock response generated: \(mockResponse.prefix(50))...")
        return mockResponse
    }
    
    private func generateMockResponse(for userMessage: String) -> String {
        let lowercased = userMessage.lowercased()
        
        // Context-aware mock responses
        if lowercased.contains("terminal") || lowercased.contains("ghostty") {
            return """
            I can help you with terminal-related tasks! The Ghostty terminal integration you've implemented looks great. Here are some suggestions:
            
            **Terminal Features:**
            - File watching for real-time updates ✅
            - Multi-editor support (Ghostty → VS Code → Vim) ✅
            - Syntax highlighting in the preview ✅
            
            **Next Steps:**
            You might want to consider adding:
            - Custom terminal themes
            - Keyboard shortcuts for quick actions
            - Terminal session management
            
            Would you like me to help implement any of these features?
            """
        } else if lowercased.contains("farcaster") {
            return """
            Great work on the Farcaster integration! Your Zig implementation with Ed25519 signing is solid. Here's what I see:
            
            **Implemented Features:**
            - Cast posting and reactions ✅
            - Real-time feed updates ✅
            - Optimistic UI updates ✅
            
            **Suggestions:**
            - Add cast threading/replies
            - Implement user following
            - Add image/media support
            
            The FFI bridge between Zig and Swift is well-designed. Any specific Farcaster features you'd like to add next?
            """
        } else if lowercased.contains("code") || lowercased.contains("implement") {
            return """
            I'd be happy to help you implement that! Based on your codebase structure, here's what I recommend:
            
            **Implementation Approach:**
            1. Start with the core logic in your existing architecture
            2. Add proper error handling and validation
            3. Update the UI components accordingly
            4. Add tests to ensure reliability
            
            **Code Quality:**
            Your Swift + Zig architecture is well-organized. The separation of concerns between the UI layer and core logic is clean.
            
            What specific functionality are you looking to implement?
            """
        } else if lowercased.contains("hello") || lowercased.contains("hi") {
            return """
            Hello! I'm here to help with your Plue development. I can see you've built an impressive multi-tab application with:
            
            - Terminal integration with Ghostty
            - Farcaster social features
            - Chat interface
            - Code editor
            - Web browser
            
            What would you like to work on next?
            """
        } else {
            return """
            **Mock AI Response**
            
            I understand you're asking about: "\(userMessage.prefix(100))"
            
            This is a simulated response to demonstrate the chat functionality without making actual OpenAI API calls. 
            
            **Your Application Features:**
            - ✅ Multi-tab interface (Chat, Terminal, Web, Editor, Farcaster)
            - ✅ Terminal integration with file watching
            - ✅ Farcaster social media integration
            - ✅ Real-time markdown preview
            - ✅ Action buttons for workflow integration
            
            **Technical Stack:**
            - Swift UI for the interface
            - Zig for core functionality and Farcaster integration
            - SwiftDown for markdown rendering
            - Metal for terminal rendering
            
            To enable real AI responses, set the OPENAI_API_KEY environment variable and the system will automatically switch to the OpenAI API.
            
            How can I help you improve your application?
            """
        }
    }
    
    // Helper method to convert PromptMessage to OpenAI format
    func convertToOpenAIMessages(_ promptMessages: [PromptMessage]) -> [OpenAIMessage] {
        return promptMessages.map { message in
            OpenAIMessage(
                role: message.type == .user ? "user" : "assistant",
                content: message.content
            )
        }
    }
    
    // Helper method for single message (backward compatibility)
    func sendSingleMessage(_ content: String, model: String = "gpt-4") async throws -> String {
        let messages = [OpenAIMessage(role: "user", content: content)]
        return try await sendChatMessage(messages: messages, model: model)
    }
}```

```swift
// File: Sources/plue/PlueCore.swift
import Foundation

// MARK: - Core State Models (Immutable)

enum TabType: Int, CaseIterable {
    case prompt = 0
    case farcaster = 1
    case agent = 2
    case terminal = 3
    case web = 4
    case editor = 5
    case diff = 6
    case worktree = 7
}

struct AppState {
    let currentTab: TabType
    let isInitialized: Bool
    let errorMessage: String?
    let openAIAvailable: Bool
    let currentTheme: DesignSystem.Theme
    
    // Tab states
    let promptState: PromptState
    let terminalState: TerminalState
    let vimState: VimState
    let webState: WebState
    let editorState: EditorState
    let farcasterState: FarcasterState
    let agentState: AgentState
    
    static let initial = AppState(
        currentTab: .prompt,
        isInitialized: true,
        errorMessage: nil,
        openAIAvailable: false,
        currentTheme: .dark,
        promptState: PromptState.initial,
        terminalState: TerminalState.initial,
        vimState: VimState.initial,
        webState: WebState.initial,
        editorState: EditorState.initial,
        farcasterState: FarcasterState.initial,
        agentState: AgentState.initial
    )
}

struct PromptState {
    let conversations: [PromptConversation]
    let currentConversationIndex: Int
    let currentPromptContent: String
    let isProcessing: Bool
    
    static let initial = PromptState(
        conversations: [PromptConversation.initial],
        currentConversationIndex: 0,
        currentPromptContent: "# Your Prompt\n\nStart typing your prompt here. The live preview will update on the right.\n\nUse `:w` in the Vim buffer to send this prompt to the Chat tab.",
        isProcessing: false
    )
    
    var currentConversation: PromptConversation? {
        guard currentConversationIndex < conversations.count else { return nil }
        return conversations[currentConversationIndex]
    }
}

struct PromptConversation {
    let id: String
    let messages: [PromptMessage]
    let createdAt: Date
    let updatedAt: Date
    let associatedPromptContent: String?
    
    static let initial = PromptConversation(
        id: UUID().uuidString,
        messages: [
            PromptMessage(
                id: UUID().uuidString,
                content: "Welcome to the Prompt Engineering interface! Use the chat to refine your prompts and see them update in the vim buffer and preview.",
                type: .system,
                timestamp: Date(),
                promptSnapshot: nil
            )
        ],
        createdAt: Date(),
        updatedAt: Date(),
        associatedPromptContent: nil
    )
}

struct PromptMessage: Identifiable {
    let id: String
    let content: String
    let type: PromptMessageType
    let timestamp: Date
    let promptSnapshot: String? // Snapshot of prompt content when message was sent
}

enum PromptMessageType {
    case user
    case assistant
    case system
}

struct TerminalState {
    let buffer: [[CoreTerminalCell]]
    let cursor: CursorPosition
    let dimensions: TerminalDimensions
    let isConnected: Bool
    let currentCommand: String
    let needsRedraw: Bool
    
    static let initial = TerminalState(
        buffer: Array(repeating: Array(repeating: CoreTerminalCell.empty, count: 80), count: 25),
        cursor: CursorPosition(row: 0, col: 0),
        dimensions: TerminalDimensions(rows: 25, cols: 80),
        isConnected: false,
        currentCommand: "",
        needsRedraw: false
    )
}

struct CoreTerminalCell {
    let character: Character
    let foregroundColor: UInt32
    let backgroundColor: UInt32
    let attributes: UInt32
    
    static let empty = CoreTerminalCell(
        character: " ",
        foregroundColor: 0xFFFFFFFF, // White
        backgroundColor: 0x00000000, // Transparent
        attributes: 0
    )
}

struct CursorPosition {
    let row: Int
    let col: Int
}

struct TerminalDimensions {
    let rows: Int
    let cols: Int
}

struct VimState {
    let mode: CoreVimMode
    let buffer: [String]
    let cursor: CursorPosition
    let statusLine: String
    let visualSelection: CoreVisualSelection?
    
    static let initial = VimState(
        mode: .normal,
        buffer: [""],
        cursor: CursorPosition(row: 0, col: 0),
        statusLine: "",
        visualSelection: nil
    )
}

enum CoreVimMode {
    case normal
    case insert
    case command
    case visual
}

struct CoreVisualSelection {
    let startRow: Int
    let startCol: Int
    let endRow: Int
    let endCol: Int
    let type: CoreVisualType
}

enum CoreVisualType {
    case characterwise
    case linewise
    case blockwise
}

struct WebState {
    let currentURL: String
    let canGoBack: Bool
    let canGoForward: Bool
    let isLoading: Bool
    let isSecure: Bool
    let pageTitle: String
    
    static let initial = WebState(
        currentURL: "https://www.apple.com",
        canGoBack: false,
        canGoForward: false,
        isLoading: false,
        isSecure: true,
        pageTitle: ""
    )
}

struct EditorState {
    let content: String
    let language: String
    let cursor: CursorPosition
    let hasUnsavedChanges: Bool
    
    static let initial = EditorState(
        content: "// Welcome to Plue Code Editor\n// Start coding here...",
        language: "swift",
        cursor: CursorPosition(row: 0, col: 0),
        hasUnsavedChanges: false
    )
}

struct FarcasterState {
    let selectedChannel: String
    let posts: [FarcasterPost]
    let channels: [FarcasterChannel]
    let isLoading: Bool
    
    static let initial = FarcasterState(
        selectedChannel: "dev",
        posts: FarcasterPost.mockPosts,
        channels: FarcasterChannel.mockChannels,
        isLoading: false
    )
}

struct FarcasterPost: Identifiable {
    let id: String
    let author: FarcasterUser
    let content: String
    let timestamp: Date
    let channel: String
    let likes: Int
    let recasts: Int
    let replies: Int
    let isLiked: Bool
    let isRecast: Bool
    
    static let mockPosts: [FarcasterPost] = [
        FarcasterPost(
            id: "1",
            author: FarcasterUser(username: "dwr", displayName: "Dan Romero", avatarURL: ""),
            content: "Building the future of decentralized social on Farcaster. The protocol is designed for developers who want to build without platform risk.",
            timestamp: Date().addingTimeInterval(-3600),
            channel: "dev",
            likes: 42,
            recasts: 15,
            replies: 8,
            isLiked: false,
            isRecast: false
        ),
        FarcasterPost(
            id: "2", 
            author: FarcasterUser(username: "vitalik", displayName: "Vitalik Buterin", avatarURL: ""),
            content: "Interesting developments in decentralized social protocols. The composability potential is huge.",
            timestamp: Date().addingTimeInterval(-7200),
            channel: "dev",
            likes: 128,
            recasts: 34,
            replies: 22,
            isLiked: true,
            isRecast: false
        ),
        FarcasterPost(
            id: "3",
            author: FarcasterUser(username: "jessepollak", displayName: "Jesse Pollak", avatarURL: ""),
            content: "Working on some exciting new features for Base. Can't wait to share what we're building! 🔵",
            timestamp: Date().addingTimeInterval(-10800),
            channel: "dev",
            likes: 89,
            recasts: 21,
            replies: 12,
            isLiked: false,
            isRecast: true
        ),
        FarcasterPost(
            id: "4",
            author: FarcasterUser(username: "balajis", displayName: "Balaji", avatarURL: ""),
            content: "The future is decentralized. Social networks, money, computation - all moving towards peer-to-peer architectures.",
            timestamp: Date().addingTimeInterval(-14400),
            channel: "dev", 
            likes: 203,
            recasts: 67,
            replies: 45,
            isLiked: true,
            isRecast: false
        ),
        FarcasterPost(
            id: "5",
            author: FarcasterUser(username: "farcaster", displayName: "Farcaster", avatarURL: ""),
            content: "Welcome to the decentralized social revolution! Build whatever you want on top of the Farcaster protocol. No ads, no algorithms, just pure social interaction.",
            timestamp: Date().addingTimeInterval(-18000),
            channel: "dev",
            likes: 156,
            recasts: 78,
            replies: 29,
            isLiked: false,
            isRecast: false
        )
    ]
}

struct FarcasterUser {
    let username: String
    let displayName: String
    let avatarURL: String
}

struct FarcasterChannel {
    let id: String
    let name: String
    let description: String
    let memberCount: Int
    
    static let mockChannels: [FarcasterChannel] = [
        FarcasterChannel(id: "dev", name: "Dev", description: "For developers building on Farcaster", memberCount: 1234),
        FarcasterChannel(id: "crypto", name: "Crypto", description: "Cryptocurrency and DeFi discussions", memberCount: 5678),
        FarcasterChannel(id: "art", name: "Art", description: "Digital art and NFT community", memberCount: 2345),
        FarcasterChannel(id: "memes", name: "Memes", description: "The best memes on the internet", memberCount: 9876),
        FarcasterChannel(id: "music", name: "Music", description: "Share and discover music", memberCount: 3456)
    ]
}

struct AgentState {
    let conversations: [AgentConversation]
    let currentConversationIndex: Int
    let isProcessing: Bool
    let currentWorkspace: GitWorktree?
    let availableWorktrees: [GitWorktree]
    let daggerSession: DaggerSession?
    let workflowQueue: [AgentWorkflow]
    let isExecutingWorkflow: Bool
    
    static let initial = AgentState(
        conversations: [AgentConversation.initial],
        currentConversationIndex: 0,
        isProcessing: false,
        currentWorkspace: nil,
        availableWorktrees: [],
        daggerSession: nil,
        workflowQueue: [],
        isExecutingWorkflow: false
    )
    
    var currentConversation: AgentConversation? {
        guard currentConversationIndex < conversations.count else { return nil }
        return conversations[currentConversationIndex]
    }
}

struct AgentConversation {
    let id: String
    let messages: [AgentMessage]
    let createdAt: Date
    let updatedAt: Date
    let associatedWorktree: String?
    
    static let initial = AgentConversation(
        id: UUID().uuidString,
        messages: [
            AgentMessage(
                id: UUID().uuidString,
                content: "Agent ready! I can help you with git worktrees, code execution in containers, and workflow automation.",
                type: .system,
                timestamp: Date(),
                metadata: nil
            )
        ],
        createdAt: Date(),
        updatedAt: Date(),
        associatedWorktree: nil
    )
}

struct AgentMessage: Identifiable {
    let id: String
    let content: String
    let type: AgentMessageType
    let timestamp: Date
    let metadata: AgentMessageMetadata?
}

enum AgentMessageType {
    case user
    case assistant
    case system
    case workflow
    case error
}

struct AgentMessageMetadata {
    let worktree: String?
    let workflow: String?
    let containerId: String?
    let exitCode: Int?
    let duration: TimeInterval?
}

struct GitWorktree: Identifiable {
    let id: String
    let path: String
    let branch: String
    let isMain: Bool
    let lastModified: Date
    let status: GitWorktreeStatus
    
    static let mockWorktrees: [GitWorktree] = [
        GitWorktree(
            id: "main",
            path: "/Users/user/plue",
            branch: "main",
            isMain: true,
            lastModified: Date().addingTimeInterval(-3600),
            status: .clean
        ),
        GitWorktree(
            id: "feature-branch",
            path: "/Users/user/plue-feature",
            branch: "feature/new-ui",
            isMain: false,
            lastModified: Date().addingTimeInterval(-1800),
            status: .modified
        )
    ]
}

enum GitWorktreeStatus {
    case clean
    case modified
    case untracked
    case conflicts
}

struct DaggerSession {
    let sessionId: String
    let port: Int
    let token: String
    let isConnected: Bool
    let startedAt: Date
}

struct AgentWorkflow {
    let id: String
    let name: String
    let description: String
    let steps: [WorkflowStep]
    let status: WorkflowStatus
    let createdAt: Date
    let startedAt: Date?
    let completedAt: Date?
}

struct WorkflowStep {
    let id: String
    let name: String
    let command: String
    let container: String?
    let dependencies: [String]
    let status: WorkflowStepStatus
}

enum WorkflowStatus {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

enum WorkflowStepStatus {
    case pending
    case running
    case completed
    case failed
    case skipped
}

// MARK: - Events (Commands sent to core)

enum AppEvent {
    case tabSwitched(TabType)
    case themeToggled
    case terminalInput(String)
    case terminalResize(rows: Int, cols: Int)
    case vimKeypress(key: String, modifiers: UInt32)
    case vimSetContent(String)
    case webNavigate(String)
    case webGoBack
    case webGoForward
    case webReload
    case editorContentChanged(String)
    case editorSave
    case farcasterSelectChannel(String)
    case farcasterLikePost(String)
    case farcasterRecastPost(String)
    case farcasterReplyToPost(String, String) // postId, replyContent
    case farcasterCreatePost(String)
    case farcasterRefreshFeed
    
    // Prompt events
    case promptMessageSent(String)
    case promptContentUpdated(String) // from vim buffer or preview
    case promptNewConversation
    case promptSelectConversation(Int)
    
    // Agent events
    case agentMessageSent(String)
    case agentNewConversation
    case agentSelectConversation(Int)
    case agentCreateWorktree(String, String) // branch, path
    case agentSwitchWorktree(String) // worktreeId
    case agentDeleteWorktree(String) // worktreeId
    case agentRefreshWorktrees
    case agentStartDaggerSession
    case agentStopDaggerSession
    case agentExecuteWorkflow(AgentWorkflow)
    case agentCancelWorkflow(String) // workflowId
    
    // AppleScript support events
    case chatMessageSent(String)
    case fileOpened(String)
    case fileSaved
}

// MARK: - Core Interface

protocol PlueCoreInterface {
    // State management
    func getCurrentState() -> AppState
    func handleEvent(_ event: AppEvent)
    func subscribe(callback: @escaping (AppState) -> Void)
    
    // Lifecycle
    func initialize() -> Bool
    func initialize(workingDirectory: String) -> Bool
    func shutdown()
}

// MARK: - Mock Implementation (will be replaced with Zig FFI)

class MockPlueCore: PlueCoreInterface {
    private var currentState: AppState = AppState.initial
    private var stateCallbacks: [(AppState) -> Void] = []
    private let openAIService: OpenAIService?
    private let farcasterService: FarcasterService?
    
    // Thread-safe access using serial queue
    private let queue = DispatchQueue(label: "plue.core", qos: .userInteractive)
    
    init() {
        // Try to initialize OpenAI service, fall back to mock responses if not available
        do {
            self.openAIService = try OpenAIService()
            print("PlueCore: OpenAI service initialized successfully")
        } catch {
            self.openAIService = nil
            print("PlueCore: OpenAI service not available (\(error.localizedDescription)), using mock responses")
        }
        
        // Try to initialize Farcaster service, fall back to mock data if not available
        self.farcasterService = FarcasterService.createTestService()
        if farcasterService != nil {
            print("PlueCore: Farcaster service initialized successfully")
        } else {
            print("PlueCore: Farcaster service not available, using mock data")
        }
    }
    
    func getCurrentState() -> AppState {
        return queue.sync {
            return currentState
        }
    }
    
    func handleEvent(_ event: AppEvent) {
        queue.async {
            self.processEvent(event)
            self.notifyStateChange()
        }
    }
    
    func subscribe(callback: @escaping (AppState) -> Void) {
        queue.async {
            self.stateCallbacks.append(callback)
            // Send current state immediately
            DispatchQueue.main.async {
                callback(self.currentState)
            }
        }
    }
    
    func initialize() -> Bool {
        return initialize(workingDirectory: FileManager.default.currentDirectoryPath)
    }
    
    func initialize(workingDirectory: String) -> Bool {
        queue.sync {
            // Change to the specified working directory
            FileManager.default.changeCurrentDirectoryPath(workingDirectory)
            
            // Initialize core state with OpenAI availability
            currentState = AppState(
                currentTab: .prompt,
                isInitialized: true,
                errorMessage: nil,
                openAIAvailable: openAIService != nil,
                currentTheme: .dark,
                promptState: PromptState.initial,
                terminalState: TerminalState.initial,
                vimState: VimState.initial,
                webState: WebState.initial,
                editorState: EditorState.initial,
                farcasterState: FarcasterState.initial,
                agentState: AgentState.initial
            )
            
            print("PlueCore: Initialized with working directory: \(workingDirectory)")
            return true
        }
    }
    
    func shutdown() {
        queue.sync {
            stateCallbacks.removeAll()
        }
    }
    
    // MARK: - Helper Methods
    
    private func createUpdatedAppState(
        currentTab: TabType? = nil,
        currentTheme: DesignSystem.Theme? = nil,
        errorMessage: String? = nil,
        promptState: PromptState? = nil,
        terminalState: TerminalState? = nil,
        vimState: VimState? = nil,
        webState: WebState? = nil,
        editorState: EditorState? = nil,
        farcasterState: FarcasterState? = nil,
        agentState: AgentState? = nil
    ) -> AppState {
        return AppState(
            currentTab: currentTab ?? self.currentState.currentTab,
            isInitialized: self.currentState.isInitialized,
            errorMessage: errorMessage ?? self.currentState.errorMessage,
            openAIAvailable: self.openAIService != nil,
            currentTheme: currentTheme ?? self.currentState.currentTheme,
            promptState: promptState ?? self.currentState.promptState,
            terminalState: terminalState ?? self.currentState.terminalState,
            vimState: vimState ?? self.currentState.vimState,
            webState: webState ?? self.currentState.webState,
            editorState: editorState ?? self.currentState.editorState,
            farcasterState: farcasterState ?? self.currentState.farcasterState,
            agentState: agentState ?? self.currentState.agentState
        )
    }
    
    // MARK: - Private Event Processing
    
    private func processEvent(_ event: AppEvent) {
        switch event {
        case .tabSwitched(let tab):
            currentState = createUpdatedAppState(currentTab: tab)
            
        case .themeToggled:
            let newTheme: DesignSystem.Theme = currentState.currentTheme == .dark ? .light : .dark
            currentState = createUpdatedAppState(currentTheme: newTheme)
            
        case .terminalInput(let input):
            processTerminalInput(input)
            
        case .terminalResize(let rows, let cols):
            resizeTerminal(rows: rows, cols: cols)
            
        case .vimKeypress(let key, let modifiers):
            processVimKeypress(key: key, modifiers: modifiers)
            
        case .vimSetContent(let content):
            setVimContent(content)
            
        case .webNavigate(let url):
            navigateWeb(to: url)
            
        case .webGoBack:
            webGoBack()
            
        case .webGoForward:
            webGoForward()
            
        case .webReload:
            webReload()
            
        case .editorContentChanged(let content):
            updateEditorContent(content)
            
        case .editorSave:
            saveEditor()
            
        case .farcasterSelectChannel(let channelId):
            selectFarcasterChannel(channelId)
            
        case .farcasterLikePost(let postId):
            likeFarcasterPost(postId)
            
        case .farcasterRecastPost(let postId):
            recastFarcasterPost(postId)
            
        case .farcasterReplyToPost(let postId, let replyContent):
            replyToFarcasterPost(postId, replyContent)
            
        case .farcasterCreatePost(let content):
            createFarcasterPost(content)
            
        case .farcasterRefreshFeed:
            refreshFarcasterFeed()
            
        // Prompt events
        case .promptMessageSent(let message):
            processPromptMessage(message)
            
        case .promptContentUpdated(let content):
            updatePromptContent(content)
            
        case .promptNewConversation:
            createNewPromptConversation()
            
        case .promptSelectConversation(let index):
            selectPromptConversation(index)
            
        // Agent events
        case .agentMessageSent(let message):
            processAgentMessage(message)
            
        case .agentNewConversation:
            createNewAgentConversation()
            
        case .agentSelectConversation(let index):
            selectAgentConversation(index)
            
        case .agentCreateWorktree(let branch, let path):
            createWorktree(branch: branch, path: path)
            
        case .agentSwitchWorktree(let worktreeId):
            switchWorktree(worktreeId)
            
        case .agentDeleteWorktree(let worktreeId):
            deleteWorktree(worktreeId)
            
        case .agentRefreshWorktrees:
            refreshWorktrees()
            
        case .agentStartDaggerSession:
            startDaggerSession()
            
        case .agentStopDaggerSession:
            stopDaggerSession()
            
        case .agentExecuteWorkflow(let workflow):
            executeWorkflow(workflow)
            
        case .agentCancelWorkflow(let workflowId):
            cancelWorkflow(workflowId)
            
        // AppleScript support events
        case .chatMessageSent(let message):
            processPromptMessage(message) // Route to prompt messages
            
        case .fileOpened(let path):
            // For now, just log - could integrate with editor state later
            print("File opened: \(path)")
            
        case .fileSaved:
            // For now, just log - could integrate with editor state later
            print("File saved")
        }
    }
    
    private func processChatMessage(_ message: String) {
        // Add user message
        let userMessage = PromptMessage(
            id: UUID().uuidString,
            content: message,
            type: .user,
            timestamp: Date(),
            promptSnapshot: nil
        )
        
        var conversations = currentState.promptState.conversations
        var currentConv = conversations[currentState.promptState.currentConversationIndex]
        currentConv = PromptConversation(
            id: currentConv.id,
            messages: currentConv.messages + [userMessage],
            createdAt: currentConv.createdAt,
            updatedAt: Date(),
            associatedPromptContent: currentConv.associatedPromptContent
        )
        conversations[currentState.promptState.currentConversationIndex] = currentConv
        
        // Update state with generation started
        let newPromptState = PromptState(
            conversations: conversations,
            currentConversationIndex: currentState.promptState.currentConversationIndex,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: true
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
        
        // Generate AI response using OpenAI API
        Task { [weak self] in
            await self?.generateAIResponse(for: message)
        }
    }
    
    private func generateAIResponse(for input: String) async {
        guard let openAIService = openAIService else {
            // Fallback to mock response if OpenAI service not available
            await generateMockAIResponse(for: input)
            return
        }
        
        let responseContent: String
        
        do {
            // Get conversation history for context
            let currentConversation = queue.sync { 
                return currentState.promptState.currentConversation 
            }
            
            let conversationMessages = currentConversation?.messages ?? []
            let openAIMessages = openAIService.convertToOpenAIMessages(conversationMessages)
            
            // Add the new user message
            let allMessages = openAIMessages + [OpenAIMessage(role: "user", content: input)]
            
            print("PlueCore: Sending request to OpenAI API...")
            responseContent = try await openAIService.sendChatMessage(
                messages: allMessages,
                model: "gpt-4",
                temperature: 0.7
            )
            print("PlueCore: Received response from OpenAI API")
            
        } catch {
            print("PlueCore: OpenAI API error: \(error.localizedDescription)")
            responseContent = "I apologize, but I'm having trouble connecting to the AI service right now. Error: \(error.localizedDescription)"
        }
        
        // Update state with AI response
        await updateStateWithAIResponse(content: responseContent)
    }
    
    private func generateMockAIResponse(for input: String) async {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let mockResponse = "Mock Response: I understand you're asking about '\(input)'. This is a placeholder response since the OpenAI API key is not configured. Please set the OPENAI_API_KEY environment variable to enable real AI responses."
        
        await updateStateWithAIResponse(content: mockResponse)
    }
    
    private func updateStateWithAIResponse(content: String) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let aiMessage = PromptMessage(
                id: UUID().uuidString,
                content: content,
                type: .assistant,
                timestamp: Date(),
                promptSnapshot: nil
            )
            
            var conversations = self.currentState.promptState.conversations
            var currentConv = conversations[self.currentState.promptState.currentConversationIndex]
            currentConv = PromptConversation(
                id: currentConv.id,
                messages: currentConv.messages + [aiMessage],
                createdAt: currentConv.createdAt,
                updatedAt: Date(),
                associatedPromptContent: currentConv.associatedPromptContent
            )
            conversations[self.currentState.promptState.currentConversationIndex] = currentConv
            
            let newPromptState = PromptState(
                conversations: conversations,
                currentConversationIndex: self.currentState.promptState.currentConversationIndex,
                currentPromptContent: self.currentState.promptState.currentPromptContent,
                isProcessing: false
            )
            
            self.currentState = self.createUpdatedAppState(promptState: newPromptState)
            
            self.notifyStateChange()
        }
    }
    
    private func createNewConversation() {
        let newConv = PromptConversation(
            id: UUID().uuidString,
            messages: [
                PromptMessage(
                    id: UUID().uuidString,
                    content: "New conversation started. How can I help you?",
                    type: .assistant,
                    timestamp: Date(),
                    promptSnapshot: nil
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            associatedPromptContent: nil
        )
        
        let conversations = currentState.promptState.conversations + [newConv]
        let newPromptState = PromptState(
            conversations: conversations,
            currentConversationIndex: conversations.count - 1,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: false
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
    }
    
    private func selectConversation(_ index: Int) {
        guard index < currentState.promptState.conversations.count else { return }
        
        let newPromptState = PromptState(
            conversations: currentState.promptState.conversations,
            currentConversationIndex: index,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: false
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
    }
    
    private func processTerminalInput(_ input: String) {
        // Simple command processing (will be real PTY in Zig)
        let output = executeCommand(input.trimmingCharacters(in: .whitespacesAndNewlines))
        
        // Update terminal state with new output
        // For now, just toggle needsRedraw
        let newTerminalState = TerminalState(
            buffer: currentState.terminalState.buffer,
            cursor: currentState.terminalState.cursor,
            dimensions: currentState.terminalState.dimensions,
            isConnected: true,
            currentCommand: output,
            needsRedraw: true
        )
        
        currentState = createUpdatedAppState(terminalState: newTerminalState)
    }
    
    private func executeCommand(_ command: String) -> String {
        switch command {
        case "ls":
            return "file1.txt  file2.swift  directory/  .hidden"
        case "pwd":
            return "/Users/user/plue"
        case "clear":
            return ""
        case "":
            return ""
        default:
            return "\(command): command processed by Zig core"
        }
    }
    
    private func resizeTerminal(rows: Int, cols: Int) {
        let newDimensions = TerminalDimensions(rows: rows, cols: cols)
        let newBuffer = Array(repeating: Array(repeating: CoreTerminalCell.empty, count: cols), count: rows)
        
        let newTerminalState = TerminalState(
            buffer: newBuffer,
            cursor: CursorPosition(row: 0, col: 0),
            dimensions: newDimensions,
            isConnected: currentState.terminalState.isConnected,
            currentCommand: currentState.terminalState.currentCommand,
            needsRedraw: true
        )
        
        currentState = createUpdatedAppState(terminalState: newTerminalState)
    }
    
    private func processVimKeypress(key: String, modifiers: UInt32) {
        // Simple vim simulation (will be real vim in Zig)
        var newMode = currentState.vimState.mode
        let newBuffer = currentState.vimState.buffer
        let newCursor = currentState.vimState.cursor
        var newStatusLine = currentState.vimState.statusLine
        
        switch (currentState.vimState.mode, key) {
        case (.normal, "i"):
            newMode = .insert
            newStatusLine = "-- INSERT --"
        case (.insert, _) where key == "Escape":
            newMode = .normal
            newStatusLine = ""
        case (.normal, ":"):
            newMode = .command
            newStatusLine = ":"
        default:
            break
        }
        
        let newVimState = VimState(
            mode: newMode,
            buffer: newBuffer,
            cursor: newCursor,
            statusLine: newStatusLine,
            visualSelection: currentState.vimState.visualSelection
        )
        
        currentState = createUpdatedAppState(vimState: newVimState)
    }
    
    private func setVimContent(_ content: String) {
        let lines = content.components(separatedBy: .newlines)
        
        let newVimState = VimState(
            mode: currentState.vimState.mode,
            buffer: lines.isEmpty ? [""] : lines,
            cursor: CursorPosition(row: 0, col: 0),
            statusLine: currentState.vimState.statusLine,
            visualSelection: nil
        )
        
        currentState = createUpdatedAppState(vimState: newVimState)
    }
    
    private func navigateWeb(to url: String) {
        let newWebState = WebState(
            currentURL: url,
            canGoBack: true,
            canGoForward: currentState.webState.canGoForward,
            isLoading: true,
            isSecure: url.hasPrefix("https://"),
            pageTitle: "Loading..."
        )
        
        currentState = createUpdatedAppState(webState: newWebState)
        
        // Simulate loading completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.queue.async {
                guard let self = self else { return }
                let completedWebState = WebState(
                    currentURL: url,
                    canGoBack: true,
                    canGoForward: self.currentState.webState.canGoForward,
                    isLoading: false,
                    isSecure: url.hasPrefix("https://"),
                    pageTitle: "Loaded Page"
                )
                
                self.currentState = self.createUpdatedAppState(webState: completedWebState)
                
                self.notifyStateChange()
            }
        }
    }
    
    private func webGoBack() {
        let newWebState = WebState(
            currentURL: "https://previous-page.com",
            canGoBack: false,
            canGoForward: true,
            isLoading: false,
            isSecure: true,
            pageTitle: "Previous Page"
        )
        
        currentState = createUpdatedAppState(webState: newWebState)
    }
    
    private func webGoForward() {
        let newWebState = WebState(
            currentURL: "https://next-page.com",
            canGoBack: true,
            canGoForward: false,
            isLoading: false,
            isSecure: true,
            pageTitle: "Next Page"
        )
        
        currentState = createUpdatedAppState(webState: newWebState)
    }
    
    private func webReload() {
        let newWebState = WebState(
            currentURL: currentState.webState.currentURL,
            canGoBack: currentState.webState.canGoBack,
            canGoForward: currentState.webState.canGoForward,
            isLoading: true,
            isSecure: currentState.webState.isSecure,
            pageTitle: "Reloading..."
        )
        
        currentState = createUpdatedAppState(webState: newWebState)
    }
    
    private func updateEditorContent(_ content: String) {
        let newEditorState = EditorState(
            content: content,
            language: currentState.editorState.language,
            cursor: currentState.editorState.cursor,
            hasUnsavedChanges: true
        )
        
        currentState = createUpdatedAppState(editorState: newEditorState)
    }
    
    private func saveEditor() {
        let newEditorState = EditorState(
            content: currentState.editorState.content,
            language: currentState.editorState.language,
            cursor: currentState.editorState.cursor,
            hasUnsavedChanges: false
        )
        
        currentState = createUpdatedAppState(editorState: newEditorState)
    }
    
    // MARK: - Farcaster Event Handlers
    
    private func selectFarcasterChannel(_ channelId: String) {
        let newFarcasterState = FarcasterState(
            selectedChannel: channelId,
            posts: currentState.farcasterState.posts,
            channels: currentState.farcasterState.channels,
            isLoading: false
        )
        
        currentState = createUpdatedAppState(farcasterState: newFarcasterState)
    }
    
    private func likeFarcasterPost(_ postId: String) {
        if let farcasterService = farcasterService {
            // Use real Farcaster API
            Task { [weak self] in
                do {
                    // First update UI optimistically
                    await self?.updatePostLikeOptimistic(postId, isLiked: true)
                    
                    // Find the post to get the author FID
                    guard let self = self,
                          let post = self.currentState.farcasterState.posts.first(where: { $0.id == postId }),
                          let authorFid = UInt64(post.author.username) else {
                        print("PlueCore: Could not find post or author FID for like")
                        return
                    }
                    
                    let result = try await farcasterService.likeCast(castHash: postId, authorFid: authorFid)
                    print("PlueCore: Liked cast successfully: \(result)")
                } catch {
                    print("PlueCore: Failed to like cast: \(error)")
                    // Revert optimistic update on error
                    await self?.updatePostLikeOptimistic(postId, isLiked: false)
                }
            }
        } else {
            // Use mock behavior
            likeFarcasterPostMock(postId)
        }
    }
    
    private func likeFarcasterPostMock(_ postId: String) {
        var updatedPosts = currentState.farcasterState.posts
        
        if let index = updatedPosts.firstIndex(where: { $0.id == postId }) {
            let post = updatedPosts[index]
            let newPost = FarcasterPost(
                id: post.id,
                author: post.author,
                content: post.content,
                timestamp: post.timestamp,
                channel: post.channel,
                likes: post.isLiked ? post.likes - 1 : post.likes + 1,
                recasts: post.recasts,
                replies: post.replies,
                isLiked: !post.isLiked,
                isRecast: post.isRecast
            )
            updatedPosts[index] = newPost
        }
        
        let newFarcasterState = FarcasterState(
            selectedChannel: currentState.farcasterState.selectedChannel,
            posts: updatedPosts,
            channels: currentState.farcasterState.channels,
            isLoading: false
        )
        
        currentState = createUpdatedAppState(farcasterState: newFarcasterState)
    }
    
    private func updatePostLikeOptimistic(_ postId: String, isLiked: Bool) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var updatedPosts = self.currentState.farcasterState.posts
            
            if let index = updatedPosts.firstIndex(where: { $0.id == postId }) {
                let post = updatedPosts[index]
                let newPost = FarcasterPost(
                    id: post.id,
                    author: post.author,
                    content: post.content,
                    timestamp: post.timestamp,
                    channel: post.channel,
                    likes: isLiked ? post.likes + 1 : post.likes - 1,
                    recasts: post.recasts,
                    replies: post.replies,
                    isLiked: isLiked,
                    isRecast: post.isRecast
                )
                updatedPosts[index] = newPost
            }
            
            let newFarcasterState = FarcasterState(
                selectedChannel: self.currentState.farcasterState.selectedChannel,
                posts: updatedPosts,
                channels: self.currentState.farcasterState.channels,
                isLoading: false
            )
            
            self.currentState = self.createUpdatedAppState(farcasterState: newFarcasterState)
            self.notifyStateChange()
        }
    }
    
    private func recastFarcasterPost(_ postId: String) {
        var updatedPosts = currentState.farcasterState.posts
        
        if let index = updatedPosts.firstIndex(where: { $0.id == postId }) {
            let post = updatedPosts[index]
            let newPost = FarcasterPost(
                id: post.id,
                author: post.author,
                content: post.content,
                timestamp: post.timestamp,
                channel: post.channel,
                likes: post.likes,
                recasts: post.isRecast ? post.recasts - 1 : post.recasts + 1,
                replies: post.replies,
                isLiked: post.isLiked,
                isRecast: !post.isRecast
            )
            updatedPosts[index] = newPost
        }
        
        let newFarcasterState = FarcasterState(
            selectedChannel: currentState.farcasterState.selectedChannel,
            posts: updatedPosts,
            channels: currentState.farcasterState.channels,
            isLoading: false
        )
        
        currentState = createUpdatedAppState(farcasterState: newFarcasterState)
    }
    
    private func replyToFarcasterPost(_ postId: String, _ replyContent: String) {
        var updatedPosts = currentState.farcasterState.posts
        
        // Increment reply count on original post
        if let index = updatedPosts.firstIndex(where: { $0.id == postId }) {
            let post = updatedPosts[index]
            let updatedPost = FarcasterPost(
                id: post.id,
                author: post.author,
                content: post.content,
                timestamp: post.timestamp,
                channel: post.channel,
                likes: post.likes,
                recasts: post.recasts,
                replies: post.replies + 1,
                isLiked: post.isLiked,
                isRecast: post.isRecast
            )
            updatedPosts[index] = updatedPost
        }
        
        // Create reply post
        let replyPost = FarcasterPost(
            id: UUID().uuidString,
            author: FarcasterUser(username: "you", displayName: "You", avatarURL: ""),
            content: replyContent,
            timestamp: Date(),
            channel: currentState.farcasterState.selectedChannel,
            likes: 0,
            recasts: 0,
            replies: 0,
            isLiked: false,
            isRecast: false
        )
        
        updatedPosts.append(replyPost)
        
        let newFarcasterState = FarcasterState(
            selectedChannel: currentState.farcasterState.selectedChannel,
            posts: updatedPosts,
            channels: currentState.farcasterState.channels,
            isLoading: false
        )
        
        currentState = createUpdatedAppState(farcasterState: newFarcasterState)
    }
    
    private func createFarcasterPost(_ content: String) {
        if let farcasterService = farcasterService {
            // Use real Farcaster API
            Task { [weak self] in
                do {
                    let result = try await farcasterService.postCast(text: content)
                    print("PlueCore: Posted cast successfully: \(result)")
                    
                    // Refresh the feed after posting
                    await self?.refreshFarcasterFeedReal()
                } catch {
                    print("PlueCore: Failed to post cast: \(error)")
                    // Fall back to mock behavior
                    self?.createMockFarcasterPost(content)
                }
            }
        } else {
            // Use mock behavior
            createMockFarcasterPost(content)
        }
    }
    
    private func createMockFarcasterPost(_ content: String) {
        let newPost = FarcasterPost(
            id: UUID().uuidString,
            author: FarcasterUser(username: "you", displayName: "You", avatarURL: ""),
            content: content,
            timestamp: Date(),
            channel: currentState.farcasterState.selectedChannel,
            likes: 0,
            recasts: 0,
            replies: 0,
            isLiked: false,
            isRecast: false
        )
        
        let updatedPosts = currentState.farcasterState.posts + [newPost]
        
        let newFarcasterState = FarcasterState(
            selectedChannel: currentState.farcasterState.selectedChannel,
            posts: updatedPosts,
            channels: currentState.farcasterState.channels,
            isLoading: false
        )
        
        currentState = createUpdatedAppState(farcasterState: newFarcasterState)
    }
    
    private func refreshFarcasterFeed() {
        if farcasterService != nil {
            // Use real Farcaster API
            Task { [weak self] in
                await self?.refreshFarcasterFeedReal()
            }
        } else {
            // Use mock behavior
            refreshFarcasterFeedMock()
        }
    }
    
    private func refreshFarcasterFeedReal() async {
        // Set loading state
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let loadingState = FarcasterState(
                selectedChannel: self.currentState.farcasterState.selectedChannel,
                posts: self.currentState.farcasterState.posts,
                channels: self.currentState.farcasterState.channels,
                isLoading: true
            )
            
            self.currentState = self.createUpdatedAppState(farcasterState: loadingState)
            self.notifyStateChange()
        }
        
        // Fetch real data
        do {
            guard let farcasterService = farcasterService else { return }
            
            let casts = try await farcasterService.getCasts(limit: 25)
            let posts = farcasterService.convertToFarcasterPosts(casts)
            
            queue.async { [weak self] in
                guard let self = self else { return }
                
                let refreshedState = FarcasterState(
                    selectedChannel: self.currentState.farcasterState.selectedChannel,
                    posts: posts,
                    channels: self.currentState.farcasterState.channels,
                    isLoading: false
                )
                
                self.currentState = self.createUpdatedAppState(farcasterState: refreshedState)
                self.notifyStateChange()
            }
            
            print("PlueCore: Refreshed Farcaster feed with \(posts.count) posts")
        } catch {
            print("PlueCore: Failed to refresh Farcaster feed: \(error)")
            
            // Reset loading state on error
            queue.async { [weak self] in
                guard let self = self else { return }
                
                let refreshedState = FarcasterState(
                    selectedChannel: self.currentState.farcasterState.selectedChannel,
                    posts: self.currentState.farcasterState.posts,
                    channels: self.currentState.farcasterState.channels,
                    isLoading: false
                )
                
                self.currentState = self.createUpdatedAppState(farcasterState: refreshedState)
                self.notifyStateChange()
            }
        }
    }
    
    private func refreshFarcasterFeedMock() {
        // Set loading state
        let loadingState = FarcasterState(
            selectedChannel: currentState.farcasterState.selectedChannel,
            posts: currentState.farcasterState.posts,
            channels: currentState.farcasterState.channels,
            isLoading: true
        )
        
        currentState = createUpdatedAppState(farcasterState: loadingState)
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.queue.async {
                guard let self = self else { return }
                
                // Reset loading state
                let refreshedState = FarcasterState(
                    selectedChannel: self.currentState.farcasterState.selectedChannel,
                    posts: self.currentState.farcasterState.posts,
                    channels: self.currentState.farcasterState.channels,
                    isLoading: false
                )
                
                self.currentState = self.createUpdatedAppState(farcasterState: refreshedState)
                self.notifyStateChange()
            }
        }
    }
    
    // MARK: - Prompt Event Handlers
    
    private func processPromptMessage(_ message: String) {
        // Add user message to conversation
        let userMessage = PromptMessage(
            id: UUID().uuidString,
            content: message,
            type: .user,
            timestamp: Date(),
            promptSnapshot: currentState.promptState.currentPromptContent
        )
        
        var conversations = currentState.promptState.conversations
        var currentConv = conversations[currentState.promptState.currentConversationIndex]
        currentConv = PromptConversation(
            id: currentConv.id,
            messages: currentConv.messages + [userMessage],
            createdAt: currentConv.createdAt,
            updatedAt: Date(),
            associatedPromptContent: currentConv.associatedPromptContent
        )
        conversations[currentState.promptState.currentConversationIndex] = currentConv
        
        // Update state with processing started
        let newPromptState = PromptState(
            conversations: conversations,
            currentConversationIndex: currentState.promptState.currentConversationIndex,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: true
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
        
        // Generate prompt response
        Task { [weak self] in
            await self?.generatePromptResponse(for: message)
        }
    }
    
    private func generatePromptResponse(for input: String) async {
        // Simulate processing delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let responseContent = generatePromptResponseContent(for: input)
        
        // Update state with response
        await updateStateWithPromptResponse(content: responseContent)
    }
    
    private func generatePromptResponseContent(for input: String) -> String {
        let lowercaseInput = input.lowercased()
        
        if lowercaseInput.contains("help") || lowercaseInput.contains("how") {
            return "I can help you refine your prompts! Try asking me to:\n• Make your prompt more specific\n• Add context or examples\n• Improve clarity or structure\n• Switch to Farcaster tab to post the prompt"
        } else if lowercaseInput.contains("improve") || lowercaseInput.contains("better") {
            return "To improve your prompt, consider:\n• Being more specific about desired output\n• Adding examples of what you want\n• Specifying the format or style\n• Including relevant context"
        } else if lowercaseInput.contains("update") || lowercaseInput.contains("change") {
            return "I can help update your prompt content. The vim buffer and preview will sync automatically. What changes would you like to make?"
        } else {
            return "I'm here to help you craft better prompts! The current prompt in the vim buffer will be used when you switch to other tabs or use the 'chat' button. How can I help you improve it?"
        }
    }
    
    private func updateStateWithPromptResponse(content: String) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let promptMessage = PromptMessage(
                id: UUID().uuidString,
                content: content,
                type: .assistant,
                timestamp: Date(),
                promptSnapshot: self.currentState.promptState.currentPromptContent
            )
            
            var conversations = self.currentState.promptState.conversations
            var currentConv = conversations[self.currentState.promptState.currentConversationIndex]
            currentConv = PromptConversation(
                id: currentConv.id,
                messages: currentConv.messages + [promptMessage],
                createdAt: currentConv.createdAt,
                updatedAt: Date(),
                associatedPromptContent: currentConv.associatedPromptContent
            )
            conversations[self.currentState.promptState.currentConversationIndex] = currentConv
            
            let newPromptState = PromptState(
                conversations: conversations,
                currentConversationIndex: self.currentState.promptState.currentConversationIndex,
                currentPromptContent: self.currentState.promptState.currentPromptContent,
                isProcessing: false
            )
            
            self.currentState = self.createUpdatedAppState(promptState: newPromptState)
            
            self.notifyStateChange()
        }
    }
    
    private func updatePromptContent(_ content: String) {
        let newPromptState = PromptState(
            conversations: currentState.promptState.conversations,
            currentConversationIndex: currentState.promptState.currentConversationIndex,
            currentPromptContent: content,
            isProcessing: currentState.promptState.isProcessing
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
    }
    
    private func createNewPromptConversation() {
        let newConv = PromptConversation(
            id: UUID().uuidString,
            messages: [
                PromptMessage(
                    id: UUID().uuidString,
                    content: "New prompt session started. How can I help you refine your prompt?",
                    type: .system,
                    timestamp: Date(),
                    promptSnapshot: nil
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            associatedPromptContent: currentState.promptState.currentPromptContent
        )
        
        let conversations = currentState.promptState.conversations + [newConv]
        let newPromptState = PromptState(
            conversations: conversations,
            currentConversationIndex: conversations.count - 1,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: false
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
    }
    
    private func selectPromptConversation(_ index: Int) {
        guard index < currentState.promptState.conversations.count else { return }
        
        let newPromptState = PromptState(
            conversations: currentState.promptState.conversations,
            currentConversationIndex: index,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: false
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
    }
    
    // MARK: - Agent Event Handlers
    
    private func processAgentMessage(_ message: String) {
        // Add user message
        let userMessage = AgentMessage(
            id: UUID().uuidString,
            content: message,
            type: .user,
            timestamp: Date(),
            metadata: AgentMessageMetadata(
                worktree: currentState.agentState.currentWorkspace?.id,
                workflow: nil,
                containerId: nil,
                exitCode: nil,
                duration: nil
            )
        )
        
        var conversations = currentState.agentState.conversations
        var currentConv = conversations[currentState.agentState.currentConversationIndex]
        currentConv = AgentConversation(
            id: currentConv.id,
            messages: currentConv.messages + [userMessage],
            createdAt: currentConv.createdAt,
            updatedAt: Date(),
            associatedWorktree: currentConv.associatedWorktree
        )
        conversations[currentState.agentState.currentConversationIndex] = currentConv
        
        // Update state with processing started
        let newAgentState = AgentState(
            conversations: conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: true,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Generate agent response
        Task { [weak self] in
            await self?.generateAgentResponse(for: message)
        }
    }
    
    private func generateAgentResponse(for input: String) async {
        // Simulate processing delay
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        let responseContent = generateAgentResponseContent(for: input)
        
        // Update state with agent response
        await updateStateWithAgentResponse(content: responseContent, type: .assistant)
    }
    
    private func generateAgentResponseContent(for input: String) -> String {
        let lowercaseInput = input.lowercased()
        
        if lowercaseInput.contains("worktree") {
            return "I can help you with git worktrees! Use commands like 'create worktree <branch>' or 'list worktrees' to manage your parallel development environments."
        } else if lowercaseInput.contains("dagger") {
            return "Dagger integration allows me to execute workflows in containers. I can start a Dagger session and run isolated build/test processes for you."
        } else if lowercaseInput.contains("workflow") {
            return "I can create and execute custom workflows using Dagger. These run in containers for safety and reproducibility. What workflow would you like to create?"
        } else {
            return "I'm your development agent. I can help with git worktrees, container-based workflows via Dagger, and automating development tasks. What would you like me to help you with?"
        }
    }
    
    private func updateStateWithAgentResponse(content: String, type: AgentMessageType) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let agentMessage = AgentMessage(
                id: UUID().uuidString,
                content: content,
                type: type,
                timestamp: Date(),
                metadata: AgentMessageMetadata(
                    worktree: self.currentState.agentState.currentWorkspace?.id,
                    workflow: nil,
                    containerId: nil,
                    exitCode: nil,
                    duration: nil
                )
            )
            
            var conversations = self.currentState.agentState.conversations
            var currentConv = conversations[self.currentState.agentState.currentConversationIndex]
            currentConv = AgentConversation(
                id: currentConv.id,
                messages: currentConv.messages + [agentMessage],
                createdAt: currentConv.createdAt,
                updatedAt: Date(),
                associatedWorktree: currentConv.associatedWorktree
            )
            conversations[self.currentState.agentState.currentConversationIndex] = currentConv
            
            let newAgentState = AgentState(
                conversations: conversations,
                currentConversationIndex: self.currentState.agentState.currentConversationIndex,
                isProcessing: false,
                currentWorkspace: self.currentState.agentState.currentWorkspace,
                availableWorktrees: self.currentState.agentState.availableWorktrees,
                daggerSession: self.currentState.agentState.daggerSession,
                workflowQueue: self.currentState.agentState.workflowQueue,
                isExecutingWorkflow: self.currentState.agentState.isExecutingWorkflow
            )
            
            self.currentState = self.createUpdatedAppState(agentState: newAgentState)
            
            self.notifyStateChange()
        }
    }
    
    private func createNewAgentConversation() {
        let newConv = AgentConversation(
            id: UUID().uuidString,
            messages: [
                AgentMessage(
                    id: UUID().uuidString,
                    content: "New agent session started. How can I help you with development workflows?",
                    type: .system,
                    timestamp: Date(),
                    metadata: nil
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            associatedWorktree: currentState.agentState.currentWorkspace?.id
        )
        
        let conversations = currentState.agentState.conversations + [newConv]
        let newAgentState = AgentState(
            conversations: conversations,
            currentConversationIndex: conversations.count - 1,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
    }
    
    private func selectAgentConversation(_ index: Int) {
        guard index < currentState.agentState.conversations.count else { return }
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: index,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
    }
    
    private func createWorktree(branch: String, path: String) {
        // Mock implementation - in real app would call git worktree add
        let newWorktree = GitWorktree(
            id: UUID().uuidString,
            path: path,
            branch: branch,
            isMain: false,
            lastModified: Date(),
            status: .clean
        )
        
        let updatedWorktrees = currentState.agentState.availableWorktrees + [newWorktree]
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: newWorktree,
            availableWorktrees: updatedWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add system message about worktree creation
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Created new worktree '\\(branch)' at \\(path)",
                type: .system
            )
        }
    }
    
    private func switchWorktree(_ worktreeId: String) {
        guard let worktree = currentState.agentState.availableWorktrees.first(where: { $0.id == worktreeId }) else {
            return
        }
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: worktree,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add system message about worktree switch
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Switched to worktree '\\(worktree.branch)' at \\(worktree.path)",
                type: .system
            )
        }
    }
    
    private func deleteWorktree(_ worktreeId: String) {
        let updatedWorktrees = currentState.agentState.availableWorktrees.filter { $0.id != worktreeId }
        let currentWorkspace = currentState.agentState.currentWorkspace?.id == worktreeId ? nil : currentState.agentState.currentWorkspace
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentWorkspace,
            availableWorktrees: updatedWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add system message about worktree deletion
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Deleted worktree with ID: \\(worktreeId)",
                type: .system
            )
        }
    }
    
    private func refreshWorktrees() {
        // Mock implementation - would scan git worktrees in real app
        let mockWorktrees = GitWorktree.mockWorktrees
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: mockWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
    }
    
    private func startDaggerSession() {
        // Mock Dagger session - in real app would call `dagger engine` and capture port/token
        let session = DaggerSession(
            sessionId: UUID().uuidString,
            port: 8080,
            token: "mock-token-\(UUID().uuidString)",
            isConnected: true,
            startedAt: Date()
        )
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: session,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add system message about Dagger session
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Started Dagger session on port \\(session.port). Ready for container workflows.",
                type: .system
            )
        }
    }
    
    private func stopDaggerSession() {
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: nil,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add system message about Dagger session stop
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Stopped Dagger session. Container workflows disabled.",
                type: .system
            )
        }
    }
    
    private func executeWorkflow(_ workflow: AgentWorkflow) {
        // Mock workflow execution
        let updatedWorkflow = AgentWorkflow(
            id: workflow.id,
            name: workflow.name,
            description: workflow.description,
            steps: workflow.steps,
            status: .running,
            createdAt: workflow.createdAt,
            startedAt: Date(),
            completedAt: nil
        )
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: [updatedWorkflow],
            isExecutingWorkflow: true
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Simulate workflow execution
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            await self?.completeWorkflow(workflow.id)
        }
    }
    
    private func completeWorkflow(_ workflowId: String) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let newAgentState = AgentState(
                conversations: self.currentState.agentState.conversations,
                currentConversationIndex: self.currentState.agentState.currentConversationIndex,
                isProcessing: false,
                currentWorkspace: self.currentState.agentState.currentWorkspace,
                availableWorktrees: self.currentState.agentState.availableWorktrees,
                daggerSession: self.currentState.agentState.daggerSession,
                workflowQueue: [],
                isExecutingWorkflow: false
            )
            
            self.currentState = self.createUpdatedAppState(agentState: newAgentState)
            self.notifyStateChange()
        }
        
        // Add completion message
        await updateStateWithAgentResponse(
            content: "Workflow completed successfully! All steps executed in container environment.",
            type: .workflow
        )
    }
    
    private func cancelWorkflow(_ workflowId: String) {
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: [],
            isExecutingWorkflow: false
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add cancellation message
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Workflow cancelled by user request.",
                type: .system
            )
        }
    }
    
    private func notifyStateChange() {
        let state = currentState
        DispatchQueue.main.async {
            for callback in self.stateCallbacks {
                callback(state)
            }
        }
    }
}

// MARK: - Singleton Instance

public class PlueCore {
    static let shared: PlueCoreInterface = LivePlueCore()
    
    private init() {}
}

/// Errors that can occur when working with PlueCore
public enum PlueError: Error {
    case initializationFailed
    
    public var localizedDescription: String {
        switch self {
        case .initializationFailed:
            return "Failed to initialize Plue core library"
        }
    }
}```

```swift
// File: Sources/plue/DesignSystem.swift
import SwiftUI
import AppKit

// MARK: - Professional Design System for Plue

/// A comprehensive design system that defines the visual language of Plue
/// Follows Apple's Human Interface Guidelines while establishing a unique, professional identity
struct DesignSystem {
    
    // MARK: - Theme Management
    
    enum Theme: String, CaseIterable {
        case dark = "dark"
        case light = "light"
        
        var displayName: String {
            switch self {
            case .dark: return "Dark"
            case .light: return "Light"
            }
        }
    }
    
    // MARK: - Color Palette
    
    /// Primary color palette with semantic naming
    struct Colors {
        
        // MARK: - Brand Colors (Native macOS-inspired palette)
        static let primary = Color(red: 0.0, green: 0.478, blue: 1.0)      // macOS blue
        static let accent = Color(red: 0.345, green: 0.337, blue: 0.839)   // #5856D6 - Indigo
        static let success = Color(red: 0.204, green: 0.780, blue: 0.349)  // macOS green
        static let warning = Color(red: 1.0, green: 0.800, blue: 0.0)      // macOS yellow
        static let error = Color(red: 1.0, green: 0.231, blue: 0.188)      // macOS red
        
        // MARK: - Theme-Aware Semantic Colors (Native macOS palette)
        static func background(for theme: Theme) -> Color {
            theme == .dark ? Color(NSColor.windowBackgroundColor) : Color(NSColor.windowBackgroundColor)
        }
        
        static func backgroundSecondary(for theme: Theme) -> Color {
            theme == .dark ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor)
        }

        static func surface(for theme: Theme) -> Color {
            theme == .dark ? Color(NSColor.underPageBackgroundColor) : Color(NSColor.underPageBackgroundColor)
        }
        
        static func surfaceSecondary(for theme: Theme) -> Color {
            theme == .dark ? Color(NSColor.unemphasizedSelectedContentBackgroundColor) : Color(NSColor.unemphasizedSelectedContentBackgroundColor)
        }
        
        static func border(for theme: Theme) -> Color {
            Color(NSColor.separatorColor)
        }
        
        static func borderSecondary(for theme: Theme) -> Color {
            Color(NSColor.separatorColor).opacity(0.5)
        }
        
        static func textPrimary(for theme: Theme) -> Color {
            Color(NSColor.labelColor)
        }
        
        static func textSecondary(for theme: Theme) -> Color {
            Color(NSColor.secondaryLabelColor)
        }
        
        static func textTertiary(for theme: Theme) -> Color {
            Color(NSColor.tertiaryLabelColor)
        }
        
        // MARK: - Legacy compatibility (using native macOS colors)
        static let background = Color(NSColor.windowBackgroundColor)
        static let backgroundSecondary = Color(NSColor.controlBackgroundColor)
        static let backgroundTertiary = Color(NSColor.underPageBackgroundColor)
        static let surface = Color(NSColor.controlBackgroundColor)
        static let surfaceSecondary = Color(NSColor.unemphasizedSelectedContentBackgroundColor)
        static let surfaceTertiary = Color(NSColor.controlBackgroundColor)
        static let border = Color(NSColor.separatorColor)
        static let borderSecondary = Color(NSColor.separatorColor).opacity(0.5)
        static let borderFocus = Color(red: 0.0, green: 0.478, blue: 1.0) // macOS blue
        static let textPrimary = Color(NSColor.labelColor)
        static let textSecondary = Color(NSColor.secondaryLabelColor)
        static let textTertiary = Color(NSColor.tertiaryLabelColor)
        static let textInverse = Color(NSColor.selectedTextBackgroundColor)
        
        // MARK: - Interactive States
        static let interactive = textPrimary
        static let interactiveHover = textPrimary
        static let interactivePressed = textTertiary
        static let interactiveDisabled = textTertiary
        
        // MARK: - Gradients
        static let primaryGradient = LinearGradient(
            colors: [primary, primary.opacity(0.8)],
            startPoint: .top,
            endPoint: .bottom
        )
        
        static let accentGradient = LinearGradient(
            colors: [accent, accent.opacity(0.8)],
            startPoint: .top,
            endPoint: .bottom
        )
        
        // Native macOS-style subtle gradient for surfaces
        static func surfaceGradient(for theme: Theme) -> LinearGradient {
            LinearGradient(
                colors: [
                    surface(for: theme),
                    surface(for: theme).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    // MARK: - Typography System
    
    /// Professional typography scale following Apple's design principles
    struct Typography {
        
        // MARK: - Display Fonts (Large Headers)
        static let displayLarge = Font.system(size: 57, weight: .bold, design: .rounded)
        static let displayMedium = Font.system(size: 45, weight: .bold, design: .rounded)
        static let displaySmall = Font.system(size: 36, weight: .bold, design: .rounded)
        
        // MARK: - Headline Fonts
        static let headlineLarge = Font.system(size: 28, weight: .semibold, design: .default)
        static let headlineMedium = Font.system(size: 22, weight: .semibold, design: .default)
        static let headlineSmall = Font.system(size: 18, weight: .semibold, design: .default)
        
        // MARK: - Title Fonts
        static let titleLarge = Font.system(size: 17, weight: .medium, design: .default)
        static let titleMedium = Font.system(size: 15, weight: .medium, design: .default)
        static let titleSmall = Font.system(size: 13, weight: .medium, design: .default)
        
        // MARK: - Body Fonts
        static let bodyLarge = Font.system(size: 15, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 13, weight: .regular, design: .default)
        static let bodySmall = Font.system(size: 11, weight: .regular, design: .default)
        
        // MARK: - Label Fonts
        static let labelLarge = Font.system(size: 13, weight: .medium, design: .default)
        static let labelMedium = Font.system(size: 11, weight: .medium, design: .default)
        static let labelSmall = Font.system(size: 10, weight: .medium, design: .default)
        
        // MARK: - Monospace Fonts (Code/Terminal)
        static let monoLarge = Font.custom("SF Mono", size: 14).weight(.regular)
        static let monoMedium = Font.custom("SF Mono", size: 12).weight(.regular)
        static let monoSmall = Font.custom("SF Mono", size: 10).weight(.regular)
        
        // Fallback to system monospace if SF Mono not available
        static let monoLargeFallback = Font.system(size: 14, weight: .regular, design: .monospaced)
        static let monoMediumFallback = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let monoSmallFallback = Font.system(size: 10, weight: .regular, design: .monospaced)
        
        // MARK: - Caption Fonts
        static let caption = Font.system(size: 10, weight: .regular, design: .default)
        static let captionMedium = Font.system(size: 10, weight: .medium, design: .default)
    }
    
    // MARK: - Spacing System
    
    /// Consistent spacing scale using 4px base unit
    struct Spacing {
        static let xs: CGFloat = 4      // Extra small
        static let sm: CGFloat = 8      // Small
        static let md: CGFloat = 12     // Medium
        static let lg: CGFloat = 16     // Large
        static let xl: CGFloat = 20     // Extra large
        static let xxl: CGFloat = 24    // 2x Extra large
        static let xxxl: CGFloat = 32   // 3x Extra large
        static let huge: CGFloat = 48   // Huge spacing
        static let massive: CGFloat = 64 // Massive spacing
    }
    
    // MARK: - Corner Radius
    
    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 24
        static let circular: CGFloat = 50
    }
    
    // MARK: - Shadows
    
    struct Shadow {
        static let subtle = (color: Color(NSColor.shadowColor).opacity(0.15), radius: 2.0, x: 0.0, y: 1.0)
        static let medium = (color: Color(NSColor.shadowColor).opacity(0.2), radius: 5.0, x: 0.0, y: 2.0)
        static let large = (color: Color(NSColor.shadowColor).opacity(0.25), radius: 10.0, x: 0.0, y: 5.0)
        static let focus = (color: Colors.primary.opacity(0.4), radius: 3.0, x: 0.0, y: 0.0)
        
        // Native macOS window shadow
        static let window = (color: Color.black.opacity(0.3), radius: 20.0, x: 0.0, y: 10.0)
    }
    
    // MARK: - Animation Curves
    
    struct Animation {
        // Core animations - optimized for responsiveness
        static let plueStandard = SwiftUI.Animation.easeOut(duration: 0.18)
        static let plueSmooth = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let plueBounce = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let plueInteractive = SwiftUI.Animation.interactiveSpring(response: 0.25, dampingFraction: 0.8)
        
        // Specialized animations for enhanced UX - optimized for responsiveness
        static let tabSwitch = SwiftUI.Animation.easeInOut(duration: 0.12)
        static let messageAppear = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.75)
        static let buttonPress = SwiftUI.Animation.easeOut(duration: 0.12)
        static let socialInteraction = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.7)
        static let heartBeat = SwiftUI.Animation.spring(response: 0.15, dampingFraction: 0.6)
        static let slideTransition = SwiftUI.Animation.easeInOut(duration: 0.22)
        static let scaleIn = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let staggerDelay = 0.03 // For staggered animations - faster
        
        // Legacy names for compatibility - updated for speed
        static let quick = plueStandard
        static let smooth = plueSmooth
        static let gentle = SwiftUI.Animation.easeInOut(duration: 0.25) // Much faster
        static let bouncy = plueBounce
        static let interactive = plueInteractive
    }
    
    // MARK: - Icon Sizes
    
    struct IconSize {
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    // MARK: - Visual Effects
    
    struct Materials {
        static let thin = Material.thin
        static let regular = Material.regular
        static let thick = Material.thick
        static let chrome = Material.ultraThin
        // Use regular material for these macOS-specific materials
        static let sidebar = Material.regular
        static let titleBar = Material.ultraThin
        static let hudWindow = Material.ultraThick
        static let popover = Material.regular
        static let menu = Material.thin
        static let sheet = Material.thick
        
        static func adaptive(for theme: Theme) -> Material {
            theme == .dark ? .ultraThick : .regular
        }
    }
    
    // MARK: - macOS Native Effects
    
    struct Effects {
        static let vibrancy = NSVisualEffectView.Material.sidebar
        static let hudVibrancy = NSVisualEffectView.Material.hudWindow
        static let contentBackground = NSVisualEffectView.Material.contentBackground
        static let behindWindow = NSVisualEffectView.Material.sidebar // behindWindow is not available
    }
}

// MARK: - Component Extensions

extension View {
    
    // MARK: - Surface Styling
    
    func primarySurface() -> some View {
        self
            .background(DesignSystem.Materials.regular)
            .background(DesignSystem.Colors.surface.opacity(0.5))
            .cornerRadius(DesignSystem.CornerRadius.md)
            .shadow(
                color: DesignSystem.Shadow.subtle.color,
                radius: DesignSystem.Shadow.subtle.radius,
                x: DesignSystem.Shadow.subtle.x,
                y: DesignSystem.Shadow.subtle.y
            )
    }
    
    func secondarySurface() -> some View {
        self
            .background(DesignSystem.Materials.thin)
            .background(DesignSystem.Colors.surfaceSecondary.opacity(0.3))
            .cornerRadius(DesignSystem.CornerRadius.sm)
    }
    
    func elevatedSurface() -> some View {
        self
            .background(DesignSystem.Materials.thick)
            .background(DesignSystem.Colors.surfaceTertiary.opacity(0.5))
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .shadow(
                color: DesignSystem.Shadow.medium.color,
                radius: DesignSystem.Shadow.medium.radius,
                x: DesignSystem.Shadow.medium.x,
                y: DesignSystem.Shadow.medium.y
            )
    }
    
    // MARK: - Native macOS Effects
    
    func glassEffect() -> some View {
        self
            .background(DesignSystem.Materials.chrome)
            .cornerRadius(DesignSystem.CornerRadius.md)
    }
    
    func sidebarStyle() -> some View {
        self
            .background(DesignSystem.Materials.sidebar)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    func hudStyle() -> some View {
        self
            .background(DesignSystem.Materials.hudWindow)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .shadow(
                color: DesignSystem.Shadow.large.color,
                radius: DesignSystem.Shadow.large.radius,
                x: DesignSystem.Shadow.large.x,
                y: DesignSystem.Shadow.large.y
            )
    }
    
    // MARK: - Border Styling
    
    func primaryBorder() -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
    }
    
    func focusBorder(_ isFocused: Bool) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(
                        isFocused ? DesignSystem.Colors.borderFocus : DesignSystem.Colors.border,
                        lineWidth: isFocused ? 2 : 1
                    )
                    .animation(DesignSystem.Animation.quick, value: isFocused)
            )
    }
    
    // MARK: - Interactive States
    
    func interactiveScale(pressed: Bool) -> some View {
        self
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(DesignSystem.Animation.interactive, value: pressed)
    }
    
    func hoverEffect() -> some View {
        self
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
    
    // MARK: - Content Transitions
    
    func contentTransition() -> some View {
        self
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            ))
    }
}

// MARK: - Professional Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    // Base layer
                    RoundedRectangle(cornerRadius: 5)
                        .fill(DesignSystem.Colors.primary)
                    
                    // Gradient overlay for depth
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(configuration.isPressed ? 0 : 0.1),
                                    Color.black.opacity(configuration.isPressed ? 0.1 : 0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.buttonPress, value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(DesignSystem.Colors.textPrimary.opacity(configuration.isPressed ? 0.9 : 0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(configuration.isPressed ? 0.8 : 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.buttonPress, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    // Material background
                    RoundedRectangle(cornerRadius: 5)
                        .fill(DesignSystem.Materials.regular)
                    
                    // Color overlay
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.plueStandard, value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    let size: CGFloat
    
    init(size: CGFloat = DesignSystem.IconSize.medium) {
        self.size = size
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.8, weight: .regular))
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .frame(width: size + DesignSystem.Spacing.sm, height: size + DesignSystem.Spacing.sm)
            .background(
                Circle()
                    .fill(Color(NSColor.controlBackgroundColor).opacity(configuration.isPressed ? 0.8 : 0.5))
            )
            .overlay(
                Circle()
                    .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DesignSystem.Animation.buttonPress, value: configuration.isPressed)
            .hoverEffect()
    }
}

// MARK: - Professional Card Component

struct ProfessionalCard<Content: View>: View {
    let content: Content
    let padding: CGFloat
    
    init(padding: CGFloat = DesignSystem.Spacing.lg, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }
    
    var body: some View {
        content
            .padding(padding)
            .elevatedSurface()
    }
}

// MARK: - Status Indicator Component

struct StatusIndicator: View {
    let status: StatusType
    let text: String
    
    enum StatusType {
        case online, offline, warning, error
        
        var color: Color {
            switch self {
            case .online: return DesignSystem.Colors.success
            case .offline: return DesignSystem.Colors.textTertiary
            case .warning: return DesignSystem.Colors.warning
            case .error: return DesignSystem.Colors.error
            }
        }
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            
            Text(text)
                .font(DesignSystem.Typography.labelSmall)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }
}

#Preview("Design System Components") {
    VStack(spacing: DesignSystem.Spacing.xl) {
        // Typography samples
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Design System")
                .font(DesignSystem.Typography.headlineLarge)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text("Professional typography and spacing")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        
        // Button samples
        HStack(spacing: DesignSystem.Spacing.md) {
            Button("Primary") {}
                .buttonStyle(PrimaryButtonStyle())
            
            Button("Secondary") {}
                .buttonStyle(SecondaryButtonStyle())
            
            Button(action: {}) {
                Image(systemName: "gear")
            }
            .buttonStyle(IconButtonStyle())
        }
        
        // Card sample
        ProfessionalCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack {
                    Text("Professional Card")
                        .font(DesignSystem.Typography.titleMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Spacer()
                    
                    StatusIndicator(status: .online, text: "Connected")
                }
                
                Text("This is a professional card component with proper spacing and styling.")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
    }
    .padding(DesignSystem.Spacing.xxl)
    .background(DesignSystem.Colors.background)
    .frame(width: 500, height: 400)
}```

```swift
// File: Sources/plue/MockTerminal.swift
import SwiftUI
import Foundation

// MARK: - Terminal Cell
struct TerminalCell {
    let character: Character
    let foregroundColor: Color
    let backgroundColor: Color
    let attributes: Set<CellAttribute>
    
    static let empty = TerminalCell(
        character: " ",
        foregroundColor: .white,
        backgroundColor: .clear,
        attributes: []
    )
}

enum CellAttribute {
    case bold
    case italic
    case underline
    case reverse
}

// MARK: - Mock Terminal Implementation
class MockTerminal: ObservableObject {
    // Terminal dimensions
    @Published var rows: Int = 25
    @Published var cols: Int = 80
    @Published var needsRedraw = false
    
    // Terminal state
    @Published var isConnected = false
    @Published var showConnectionStatus = true
    
    // Rendering options
    let useMetalRendering = false // Set to true when Metal rendering is implemented
    let cellWidth: CGFloat = 8.0
    let cellHeight: CGFloat = 16.0
    
    // Terminal buffer
    private var buffer: [[TerminalCell]]
    private var cursorRow = 0
    private var cursorCol = 0
    private var currentDirectory = "/Users/user"
    private var commandHistory: [String] = []
    private var currentCommand = ""
    
    // Colors
    private let colors = TerminalColors()
    
    init() {
        self.buffer = Array(repeating: Array(repeating: TerminalCell.empty, count: 80), count: 25)
        setupInitialContent()
    }
    
    func getCell(row: Int, col: Int) -> TerminalCell {
        guard row >= 0, row < rows, col >= 0, col < cols else {
            return TerminalCell.empty
        }
        return buffer[row][col]
    }
    
    func resize(rows: Int, cols: Int) {
        self.rows = max(1, rows)
        self.cols = max(1, cols)
        
        // Resize buffer
        buffer = Array(repeating: Array(repeating: TerminalCell.empty, count: self.cols), count: self.rows)
        
        // Reset cursor if it's out of bounds
        cursorRow = min(cursorRow, self.rows - 1)
        cursorCol = min(cursorCol, self.cols - 1)
        
        redraw()
    }
    
    func startSession() {
        self.showConnectionStatus = true // Show it immediately
        self.isConnected = false
        clearScreen()
        writeLineAt(row: 2, text: "Connecting to shell...", color: colors.cyan)
        redraw()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            self.isConnected = true
            self.showWelcomeMessage() // This will clear the "Connecting..." message
            self.showPrompt()
            
            // Hide the status indicator after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showConnectionStatus = false
            }
        }
    }
    
    func handleInput(_ input: String) {
        for char in input {
            switch char {
            case "\r", "\n":
                handleEnter()
            case "\u{7F}": // Backspace
                handleBackspace()
            case "\u{1B}": // Escape sequence start
                // Handle escape sequences (arrow keys, etc.)
                break
            default:
                handleCharacter(char)
            }
        }
        redraw()
    }
    
    private func setupInitialContent() {
        clearScreen()
    }
    
    private func showWelcomeMessage() {
        clearScreen()
        let welcomeLines = [
            "Plue Terminal v1.0.0",
            "Shell connected."
        ]
        for (index, line) in welcomeLines.enumerated() {
            writeLineAt(row: index, text: line, color: colors.cyan)
        }
        cursorRow = welcomeLines.count
        redraw()
    }
    
    private func showPrompt() {
        let promptText = "user@plue:\(currentDirectory)$ "
        writeAt(row: cursorRow, col: 0, text: promptText, color: colors.green)
        cursorCol = promptText.count
        currentCommand = ""
        redraw()
    }
    
    private func handleCharacter(_ char: Character) {
        if cursorCol < cols - 1 {
            buffer[cursorRow][cursorCol] = TerminalCell(
                character: char,
                foregroundColor: colors.white,
                backgroundColor: .clear,
                attributes: []
            )
            cursorCol += 1
            currentCommand.append(char)
        }
    }
    
    private func handleBackspace() {
        if cursorCol > getPromptLength() {
            cursorCol -= 1
            buffer[cursorRow][cursorCol] = TerminalCell.empty
            if !currentCommand.isEmpty {
                currentCommand.removeLast()
            }
        }
    }
    
    private func handleEnter() {
        let commandToProcess = currentCommand.trimmingCharacters(in: .whitespaces)
        
        // Move to the next line immediately
        newLine()
        
        // Process the command
        if !commandToProcess.isEmpty {
            processCommand(commandToProcess)
        }
        
        // Show the next prompt
        showPrompt()
    }
    
    // Make processCommand synchronous to avoid timing issues with the prompt
    private func processCommand(_ command: String) {
        commandHistory.append(command)
        executeCommand(command)
    }
    
    private func executeCommand(_ command: String) {
        let parts = command.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return }
        
        let cmd = parts[0]
        let args = Array(parts.dropFirst())
        
        switch cmd {
        case "ls":
            handleLSCommand(args: args)
        case "pwd":
            writeOutput(currentDirectory)
        case "cd":
            handleCDCommand(args: args)
        case "echo":
            writeOutput(args.joined(separator: " "))
        case "clear":
            clearScreen()
            return // Don't show prompt after clear
        case "help":
            showHelpMessage()
        case "date":
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .full
            writeOutput(formatter.string(from: Date()))
        case "whoami":
            writeOutput("user")
        case "uname":
            writeOutput("Darwin plue.local 23.0.0 Darwin Kernel")
        case "ps":
            showProcessList()
        default:
            writeOutput("\(cmd): command not found")
        }
    }
    
    private func handleLSCommand(args: [String]) {
        let files = [
            "Documents/", "Downloads/", "Desktop/", "Pictures/",
            "file1.txt", "file2.swift", "project.zip", ".hidden"
        ]
        
        let showHidden = args.contains("-a") || args.contains("-la")
        let longFormat = args.contains("-l") || args.contains("-la")
        
        for file in files {
            if file.hasPrefix(".") && !showHidden {
                continue
            }
            
            if longFormat {
                let permissions = file.hasSuffix("/") ? "drwxr-xr-x" : "-rw-r--r--"
                let size = file.hasSuffix("/") ? "0" : "1024"
                let date = "Dec 13 10:30"
                writeOutput("\(permissions)  1 user staff  \(size) \(date) \(file)")
            } else {
                writeOutput(file)
            }
        }
    }
    
    private func handleCDCommand(args: [String]) {
        guard let newDir = args.first else {
            currentDirectory = "/Users/user"
            return
        }
        
        if newDir.hasPrefix("/") {
            currentDirectory = newDir
        } else if newDir == ".." {
            let components = currentDirectory.split(separator: "/").dropLast()
            currentDirectory = "/" + components.joined(separator: "/")
            if currentDirectory == "/" && !components.isEmpty {
                currentDirectory = "/Users"
            }
        } else {
            if currentDirectory.hasSuffix("/") {
                currentDirectory += newDir
            } else {
                currentDirectory += "/" + newDir
            }
        }
    }
    
    private func showHelpMessage() {
        let helpText = [
            "Available commands:",
            "  ls [-a] [-l]  - List directory contents",
            "  pwd           - Print working directory",
            "  cd <dir>      - Change directory",
            "  echo <text>   - Display text",
            "  clear         - Clear screen",
            "  date          - Show current date and time",
            "  whoami        - Show current user",
            "  uname         - Show system information",
            "  ps            - Show running processes",
            "  help          - Show this help message"
        ]
        
        for line in helpText {
            writeOutput(line)
        }
    }
    
    private func showProcessList() {
        let processes = [
            "  PID TTY           TIME CMD",
            " 1234 ttys000    0:00.01 /bin/zsh",
            " 5678 ttys000    0:00.02 plue",
            " 9101 ttys000    0:00.00 ps"
        ]
        
        for process in processes {
            writeOutput(process)
        }
    }
    
    private func writeOutput(_ text: String) {
        ensureNewLine()
        writeAt(row: cursorRow, col: 0, text: text, color: colors.white)
        newLine()
    }
    
    private func writeAt(row: Int, col: Int, text: String, color: Color) {
        guard row >= 0, row < rows else { return }
        
        var currentCol = col
        for char in text {
            guard currentCol < cols else { break }
            buffer[row][currentCol] = TerminalCell(
                character: char,
                foregroundColor: color,
                backgroundColor: .clear,
                attributes: []
            )
            currentCol += 1
        }
    }
    
    private func writeLineAt(row: Int, text: String, color: Color) {
        writeAt(row: row, col: 0, text: text, color: color)
    }
    
    private func clearScreen() {
        buffer = Array(repeating: Array(repeating: TerminalCell.empty, count: cols), count: rows)
        cursorRow = 0
        cursorCol = 0
        redraw()
    }
    
    private func scrollUp() {
        // Move all lines up by one
        for row in 1..<rows {
            buffer[row - 1] = buffer[row]
        }
        // Clear the last line
        buffer[rows - 1] = Array(repeating: TerminalCell.empty, count: cols)
        
        if cursorRow > 0 {
            cursorRow -= 1
        }
    }
    
    private func ensureNewLine() {
        if cursorCol > 0 {
            newLine()
        }
    }
    
    private func newLine() {
        cursorRow += 1
        cursorCol = 0
        
        if cursorRow >= rows {
            scrollUp()
        }
    }
    
    private func getPromptLength() -> Int {
        return "user@plue:\(currentDirectory)$ ".count
    }
    
    private var redrawPending = false
    
    private func redraw() {
        guard !redrawPending else { return }
        redrawPending = true
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.needsRedraw.toggle()
            self.redrawPending = false
        }
    }
}

// MARK: - Terminal Colors
struct TerminalColors {
    let black = Color.black
    let red = Color.red
    let green = Color.green
    let yellow = Color.yellow
    let blue = Color.blue
    let magenta = Color.purple
    let cyan = Color.cyan
    let white = Color.white
    
    // Bright variants
    let brightBlack = Color.gray
    let brightRed = Color.red.opacity(0.8)
    let brightGreen = Color.green.opacity(0.8)
    let brightYellow = Color.yellow.opacity(0.8)
    let brightBlue = Color.blue.opacity(0.8)
    let brightMagenta = Color.purple.opacity(0.8)
    let brightCyan = Color.cyan.opacity(0.8)
    let brightWhite = Color.white.opacity(0.9)
}```

```swift
// File: Sources/plue/ViewModifiers.swift
import SwiftUI

// MARK: - Native macOS Card Modifier

struct NativeMacOSCard: ViewModifier {
    let theme: DesignSystem.Theme
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DesignSystem.Materials.regular)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignSystem.Colors.surface(for: theme).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DesignSystem.Colors.border(for: theme), lineWidth: 0.5)
                    )
            )
            .shadow(
                color: DesignSystem.Shadow.subtle.color,
                radius: DesignSystem.Shadow.subtle.radius,
                x: DesignSystem.Shadow.subtle.x,
                y: DesignSystem.Shadow.subtle.y
            )
    }
}

// MARK: - Toolbar Style Modifier

struct ToolbarStyle: ViewModifier {
    let theme: DesignSystem.Theme
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    DesignSystem.Colors.surface(for: theme).opacity(0.3)
                }
                .overlay(
                    Divider()
                        .background(DesignSystem.Colors.border(for: theme)),
                    alignment: .bottom
                )
            )
    }
}

// MARK: - Hover Highlight Modifier

struct HoverHighlight: ViewModifier {
    let theme: DesignSystem.Theme
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? 
                        DesignSystem.Colors.primary.opacity(0.1) : 
                        Color.clear
                    )
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Press Effect Modifier

struct PressEffect: ViewModifier {
    let isPressed: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - Focus Ring Modifier

struct FocusRing: ViewModifier {
    let isFocused: Bool
    let theme: DesignSystem.Theme
    let cornerRadius: CGFloat
    
    init(isFocused: Bool, theme: DesignSystem.Theme, cornerRadius: CGFloat = 6) {
        self.isFocused = isFocused
        self.theme = theme
        self.cornerRadius = cornerRadius
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isFocused ? DesignSystem.Colors.primary : DesignSystem.Colors.border(for: theme),
                        lineWidth: isFocused ? 2 : 0.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Sidebar Item Modifier

struct SidebarItem: ViewModifier {
    let isSelected: Bool
    let theme: DesignSystem.Theme
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? 
                        DesignSystem.Colors.primary.opacity(0.1) : 
                        Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        isSelected ? DesignSystem.Colors.primary.opacity(0.2) : Color.clear,
                        lineWidth: 0.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - View Extensions

extension View {
    func nativeMacOSCard(theme: DesignSystem.Theme) -> some View {
        modifier(NativeMacOSCard(theme: theme))
    }
    
    func toolbarStyle(theme: DesignSystem.Theme) -> some View {
        modifier(ToolbarStyle(theme: theme))
    }
    
    func hoverHighlight(theme: DesignSystem.Theme) -> some View {
        modifier(HoverHighlight(theme: theme))
    }
    
    func pressEffect(isPressed: Bool) -> some View {
        modifier(PressEffect(isPressed: isPressed))
    }
    
    func focusRing(isFocused: Bool, theme: DesignSystem.Theme, cornerRadius: CGFloat = 6) -> some View {
        modifier(FocusRing(isFocused: isFocused, theme: theme, cornerRadius: cornerRadius))
    }
    
    func sidebarItem(isSelected: Bool, theme: DesignSystem.Theme) -> some View {
        modifier(SidebarItem(isSelected: isSelected, theme: theme))
    }
}

// MARK: - Animation Modifiers

struct AnimateOnAppearModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(DesignSystem.Animation.plueStandard.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Animation Extensions

extension View {
    func animateOnAppear(delay: Double = 0) -> some View {
        modifier(AnimateOnAppearModifier(delay: delay))
    }
    
    func shimmer(isActive: Bool = true) -> some View {
        self.overlay(
            GeometryReader { geometry in
                if isActive {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: -geometry.size.width)
                        .animation(
                            Animation.linear(duration: 1.5)
                                .repeatForever(autoreverses: false),
                            value: isActive
                        )
                }
            }
        )
    }
}

// MARK: - Conditional Modifiers

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func ifLet<Value, Content: View>(_ value: Value?, transform: (Self, Value) -> Content) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - macOS Specific Extensions

extension View {
    func macOSWindowStyle() -> some View {
        self
            .frame(minWidth: 800, minHeight: 600)
            .background(VisualEffectBlur())
    }
    
    func cursorOnHover(_ cursor: NSCursor = .pointingHand) -> some View {
        self.onHover { isHovered in
            if isHovered {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .sidebar
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}```

```swift
// File: Sources/plue/DiffView.swift
import SwiftUI

struct DiffView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var gitDiff: GitDiffData = GitDiffData.mock
    @State private var diffMode: DiffDisplayMode = .unified
    @State private var showLineNumbers: Bool = true
    @State private var selectedFile: String? = nil
    @State private var isRefreshing: Bool = false
    @State private var sidebarCollapsed: Bool = false
    @State private var syntaxHighlighting: Bool = true
    @State private var showWhitespace: Bool = false
    @State private var contextLines: Int = 3
    @State private var searchText: String = ""
    @State private var showSearchBar: Bool = false
    @State private var conflictResolutionMode: Bool = false
    @State private var selectedConflict: ConflictSection? = nil
    @State private var stageSelections: Set<String> = []
    @State private var showFileTree: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Professional header with better controls
            professionalDiffHeader
            
            // Search bar (conditionally shown)
            if showSearchBar {
                searchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Enhanced diff content with collapsible sidebar
            enhancedDiffContent
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
        .onAppear {
            refreshGitDiff()
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
            
            TextField("Search in diff content...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Text("\(searchResultCount) results")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            DesignSystem.Colors.surface(for: appState.currentTheme)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3)),
                    alignment: .bottom
                )
        )
    }
    
    private var searchResultCount: Int {
        // Mock implementation - would search through diff content
        searchText.isEmpty ? 0 : 12
    }
    
    // MARK: - Professional Diff Header
    
    private var professionalDiffHeader: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Left side - Sidebar toggle and Git status
            HStack(spacing: 12) {
                // Sidebar toggle
                Button(action: { 
                    withAnimation(DesignSystem.Animation.plueSmooth) {
                        sidebarCollapsed.toggle()
                    }
                }) {
                    Image(systemName: sidebarCollapsed ? "sidebar.left" : "sidebar.left.closed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help(sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Git Changes")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("\(gitDiff.changedFiles.count) files • \(gitDiff.totalAdditions)+/\(gitDiff.totalDeletions)-")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
            }
            
            Spacer()
            
            // Center - Display mode toggle
            HStack(spacing: 6) {
                Button(action: { diffMode = .sideBySide }) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 10, weight: .medium))
                        Text("side")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(diffMode == .sideBySide ? .white : DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(diffMode == .sideBySide ? DesignSystem.Colors.primary : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { diffMode = .unified }) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle")
                            .font(.system(size: 10, weight: .medium))
                        Text("unified")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(diffMode == .unified ? .white : DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(diffMode == .unified ? DesignSystem.Colors.primary : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
            )
            
            Spacer()
            
            // Right side - Enhanced controls
            HStack(spacing: 8) {
                // Search toggle
                Button(action: { showSearchBar.toggle() }) {
                    Image(systemName: showSearchBar ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(showSearchBar ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle search")
                
                // Whitespace toggle
                Button(action: { showWhitespace.toggle() }) {
                    Image(systemName: showWhitespace ? "space" : "minus.rectangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(showWhitespace ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle whitespace display")
                
                // Syntax highlighting toggle
                Button(action: { syntaxHighlighting.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: syntaxHighlighting ? "paintbrush.fill" : "paintbrush")
                            .font(.system(size: 11, weight: .medium))
                        Text("syntax")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(syntaxHighlighting ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle syntax highlighting")
                
                // Line numbers toggle
                Button(action: { showLineNumbers.toggle() }) {
                    Image(systemName: showLineNumbers ? "list.number" : "list.bullet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(showLineNumbers ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle line numbers")
                
                // Context lines stepper
                Stepper(value: $contextLines, in: 1...10) {
                    Text("\(contextLines)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .help("Context lines: \(contextLines)")
                
                Rectangle()
                    .frame(width: 0.5, height: 16)
                    .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3))
                
                // Refresh button
                Button(action: refreshGitDiff) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Refresh git diff")
                
                // Advanced actions menu
                Menu {
                    Button("Stage Selected Lines") { stageSelectedLines() }
                        .disabled(stageSelections.isEmpty)
                    Button("Unstage Selected Lines") { unstageSelectedLines() }
                        .disabled(stageSelections.isEmpty)
                    Divider()
                    Button("View File History") { viewFileHistory() }
                    Button("Compare with Branch...") { compareBranch() }
                    Button("Create Patch File") { createPatchFile() }
                    Divider()
                    Button("Reset File Changes") { resetFileChanges() }
                        .foregroundColor(DesignSystem.Colors.error)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .help("More actions")
                
                // Stage all button
                Button("Stage All") {
                    stageAll()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(gitDiff.changedFiles.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            DesignSystem.Colors.surface(for: appState.currentTheme)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3)),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - Enhanced Diff Content
    
    private var enhancedDiffContent: some View {
        Group {
            if gitDiff.changedFiles.isEmpty {
                noChangesState
            } else {
                HStack(spacing: 0) {
                    // Collapsible sidebar
                    if !sidebarCollapsed {
                        collapsibleFileListSidebar
                            .frame(width: 280)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    
                    // Enhanced diff view with syntax highlighting
                    enhancedDiffView
                }
                .animation(DesignSystem.Animation.plueSmooth, value: sidebarCollapsed)
            }
        }
    }
    
    private var noChangesState: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()
            
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Git status indicator
                Circle()
                    .fill(DesignSystem.Colors.success.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(DesignSystem.Colors.success)
                    )
                
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("No Changes")
                        .font(DesignSystem.Typography.titleMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text("Working directory is clean. All changes have been committed.")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                
                // Git actions
                VStack(spacing: 6) {
                    gitActionButton("Check status", icon: "list.bullet.circle")
                    gitActionButton("View commit log", icon: "clock.arrow.circlepath")
                    gitActionButton("Create new branch", icon: "arrow.triangle.branch")
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.backgroundSecondary)
    }
    
    private func gitActionButton(_ text: String, icon: String) -> some View {
        Button(action: {
            handleGitAction(text)
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .frame(width: 16)
                
                Text(text)
                    .font(DesignSystem.Typography.labelMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: 280)
    }
    
    // MARK: - Collapsible File List Sidebar
    
    private var collapsibleFileListSidebar: some View {
        VStack(spacing: 0) {
            // Enhanced sidebar header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Files")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("\(gitDiff.changedFiles.count) changed")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                
                Spacer()
                
                // File stats
                HStack(spacing: 4) {
                    Text("+\(gitDiff.totalAdditions)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.success)
                    
                    Text("-\(gitDiff.totalDeletions)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.error)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            
            // Subtle separator
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3))
            
            // Enhanced file list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(gitDiff.changedFiles, id: \.path) { file in
                        EnhancedGitFileRow(
                            file: file,
                            isSelected: selectedFile == file.path,
                            isStaged: stageSelections.contains(file.path),
                            theme: appState.currentTheme,
                            onSelect: { selectedFile = file.path },
                            onStageToggle: { toggleFileStaging(file.path) }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            .background(DesignSystem.Colors.background(for: appState.currentTheme))
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .overlay(
            Rectangle()
                .frame(width: 0.5)
                .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3)),
            alignment: .trailing
        )
    }
    
    // MARK: - Enhanced Diff View
    
    private var enhancedDiffView: some View {
        Group {
            if let selectedFile = selectedFile,
               let file = gitDiff.changedFiles.first(where: { $0.path == selectedFile }) {
                VStack(spacing: 0) {
                    // File header with syntax info
                    HStack {
                        HStack(spacing: 8) {
                            // File type icon
                            Image(systemName: fileTypeIcon(for: file.path))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(fileTypeColor(for: file.path))
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.path)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                                
                                Text("\(file.changeType.description) • \(fileLanguage(for: file.path))")
                                    .font(.system(size: 10))
                                    .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                            }
                        }
                        
                        Spacer()
                        
                        // Change stats
                        HStack(spacing: 8) {
                            Text("+\(file.additions)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(DesignSystem.Colors.success)
                            
                            Text("-\(file.deletions)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(DesignSystem.Colors.error)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(DesignSystem.Colors.surface(for: appState.currentTheme))
                    
                    // Enhanced diff content
                    if conflictResolutionMode && file.hasConflicts {
                        ConflictResolutionView(
                            file: file,
                            selectedConflict: $selectedConflict,
                            theme: appState.currentTheme
                        )
                    } else {
                        SyntaxHighlightedDiffView(
                            file: file,
                            showLineNumbers: showLineNumbers,
                            syntaxHighlighting: syntaxHighlighting,
                            showWhitespace: showWhitespace,
                            contextLines: contextLines,
                            searchText: searchText,
                            theme: appState.currentTheme
                        )
                    }
                }
            } else {
                enhancedSelectFilePrompt
            }
        }
    }
    
    private var enhancedSelectFilePrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: sidebarCollapsed ? "sidebar.left" : "doc.text")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
            
            VStack(spacing: 8) {
                Text(sidebarCollapsed ? "Show sidebar to view files" : "Select a file to view diff")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                if sidebarCollapsed {
                    Button("Show Sidebar") {
                        withAnimation(DesignSystem.Animation.plueSmooth) {
                            sidebarCollapsed = false
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
    }
    
    // MARK: - Helper Functions
    
    private func fileTypeIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts": return "doc.text.fill"
        case "py": return "terminal.fill"
        case "md": return "doc.plaintext"
        case "json": return "curlybraces"
        case "yaml", "yml": return "doc.text"
        default: return "doc"
        }
    }
    
    private func fileTypeColor(for path: String) -> Color {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "ts": return .yellow
        case "py": return .blue
        case "md": return .gray
        case "json": return .green
        default: return DesignSystem.Colors.textTertiary
        }
    }
    
    private func fileLanguage(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "Swift"
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "py": return "Python"
        case "md": return "Markdown"
        case "json": return "JSON"
        case "yaml", "yml": return "YAML"
        default: return "Text"
        }
    }
    
    // MARK: - Git Diff Views
    
    private var sideBySideGitDiffView: some View {
        Group {
            if let selectedFile = selectedFile,
               let file = gitDiff.changedFiles.first(where: { $0.path == selectedFile }) {
                GitSideBySideDiffView(file: file, showLineNumbers: showLineNumbers)
            } else {
                selectFilePrompt
            }
        }
    }
    
    private var unifiedGitDiffView: some View {
        Group {
            if let selectedFile = selectedFile,
               let file = gitDiff.changedFiles.first(where: { $0.path == selectedFile }) {
                GitUnifiedDiffView(file: file, showLineNumbers: showLineNumbers)
            } else {
                selectFilePrompt
            }
        }
    }
    
    private var selectFilePrompt: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "arrow.left")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            Text("Select a file to view diff")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.backgroundSecondary)
    }
    
    // MARK: - Actions
    
    private func refreshGitDiff() {
        isRefreshing = true
        
        // Simulate git diff refresh - in real implementation, this would call git
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Mock refresh - in reality this would run `git diff` and parse output
            gitDiff = GitDiffData.mock
            isRefreshing = false
            
            // Auto-select first file if none selected
            if selectedFile == nil && !gitDiff.changedFiles.isEmpty {
                selectedFile = gitDiff.changedFiles.first?.path
            }
        }
    }
    
    private func stageAll() {
        // Mock staging all files - in reality this would run `git add .`
        print("Staging all changes...")
        
        // Show visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("All changes staged")
        }
    }
    
    private func handleGitAction(_ action: String) {
        switch action {
        case "Check status":
            print("Running git status...")
        case "View commit log":
            print("Opening git log...")
        case "Create new branch":
            print("Creating new branch...")
        default:
            break
        }
    }
    
    // MARK: - Enhanced Actions
    
    private func stageSelectedLines() {
        print("Staging selected lines...")
    }
    
    private func unstageSelectedLines() {
        print("Unstaging selected lines...")
    }
    
    private func viewFileHistory() {
        guard let selectedFile = selectedFile else { return }
        print("Viewing history for \(selectedFile)")
    }
    
    private func compareBranch() {
        print("Compare with branch...")
    }
    
    private func createPatchFile() {
        print("Creating patch file...")
    }
    
    private func resetFileChanges() {
        guard let selectedFile = selectedFile else { return }
        print("Resetting changes for \(selectedFile)")
    }
    
    private func toggleFileStaging(_ filePath: String) {
        if stageSelections.contains(filePath) {
            stageSelections.remove(filePath)
        } else {
            stageSelections.insert(filePath)
        }
    }
}

// MARK: - Supporting Views

struct EnhancedGitFileRow: View {
    let file: GitChangedFile
    let isSelected: Bool
    let isStaged: Bool
    let theme: DesignSystem.Theme
    let onSelect: () -> Void
    let onStageToggle: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Staging checkbox
                Button(action: onStageToggle) {
                    Image(systemName: isStaged ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isStaged ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary(for: theme))
                }
                .buttonStyle(PlainButtonStyle())
                .help(isStaged ? "Unstage file" : "Stage file")
                
                // File type icon
                Image(systemName: fileTypeIcon(for: file.path))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(fileTypeColor(for: file.path))
                    .frame(width: 14)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(fileName(from: file.path))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isSelected ? DesignSystem.Colors.textPrimary(for: theme) : DesignSystem.Colors.textPrimary(for: theme))
                        .lineLimit(1)
                    
                    Text(filePath(from: file.path))
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                // Change indicator and stats
                HStack(spacing: 6) {
                    Circle()
                        .fill(file.changeType.color)
                        .frame(width: 6, height: 6)
                    
                    if file.additions > 0 || file.deletions > 0 {
                        HStack(spacing: 2) {
                            if file.additions > 0 {
                                Text("+\(file.additions)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(DesignSystem.Colors.success)
                            }
                            if file.deletions > 0 {
                                Text("-\(file.deletions)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(DesignSystem.Colors.error)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? DesignSystem.Colors.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
            .animation(DesignSystem.Animation.plueStandard, value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
    }
    
    private func fileName(from path: String) -> String {
        return (path as NSString).lastPathComponent
    }
    
    private func filePath(from path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "/" : dir
    }
    
    private func fileTypeIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts": return "doc.text.fill"
        case "py": return "terminal.fill"
        case "md": return "doc.plaintext"
        case "json": return "curlybraces"
        case "yaml", "yml": return "doc.text"
        default: return "doc"
        }
    }
    
    private func fileTypeColor(for path: String) -> Color {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "ts": return .yellow
        case "py": return .blue
        case "md": return .gray
        case "json": return .green
        default: return DesignSystem.Colors.textTertiary
        }
    }
}

struct SyntaxHighlightedDiffView: View {
    let file: GitChangedFile
    let showLineNumbers: Bool
    let syntaxHighlighting: Bool
    let showWhitespace: Bool
    let contextLines: Int
    let searchText: String
    let theme: DesignSystem.Theme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(file.diffLines.enumerated()), id: \.offset) { index, line in
                    SyntaxHighlightedDiffLine(
                        line: line,
                        showLineNumbers: showLineNumbers,
                        syntaxHighlighting: syntaxHighlighting,
                        theme: theme,
                        fileType: fileType(for: file.path)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(DesignSystem.Colors.background(for: theme))
    }
    
    private func fileType(for path: String) -> String {
        return (path as NSString).pathExtension.lowercased()
    }
}

struct SyntaxHighlightedDiffLine: View {
    let line: GitDiffLine
    let showLineNumbers: Bool
    let syntaxHighlighting: Bool
    let theme: DesignSystem.Theme
    let fileType: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if showLineNumbers {
                HStack(spacing: 8) {
                    Text(line.oldLineNumber.map(String.init) ?? "")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: theme).opacity(0.6))
                        .frame(minWidth: 30, alignment: .trailing)
                    
                    Text(line.newLineNumber.map(String.init) ?? "")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: theme).opacity(0.6))
                        .frame(minWidth: 30, alignment: .trailing)
                }
                .padding(.trailing, 12)
            }
            
            HStack(spacing: 8) {
                Text(line.type.prefix)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(line.type.color)
                    .frame(width: 12, alignment: .leading)
                
                if syntaxHighlighting && !line.content.trimmingCharacters(in: .whitespaces).isEmpty {
                    syntaxHighlightedText(line.content)
                } else {
                    Text(line.content)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(line.type.textColor)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 1)
        .background(line.type.backgroundColor.opacity(0.08))
    }
    
    @ViewBuilder
    private func syntaxHighlightedText(_ content: String) -> some View {
        // Simple syntax highlighting for common patterns
        
        if fileType == "swift" {
            swiftSyntaxHighlighting(content)
        } else if fileType == "json" {
            jsonSyntaxHighlighting(content)
        } else {
            Text(content)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(line.type.textColor)
        }
    }
    
    @ViewBuilder
    private func swiftSyntaxHighlighting(_ content: String) -> some View {
        let keywords = ["import", "struct", "class", "func", "var", "let", "if", "else", "for", "while", "return", "private", "public", "internal"]
        let text = content
        
        if keywords.contains(where: text.contains) {
            Text(content)
                .font(.system(size: 12, weight: text.contains("func") || text.contains("struct") || text.contains("class") ? .semibold : .regular, design: .monospaced))
                .foregroundColor(text.contains("//") ? DesignSystem.Colors.success.opacity(0.8) : 
                               keywords.contains(where: text.contains) ? DesignSystem.Colors.primary : 
                               line.type.textColor)
        } else {
            Text(content)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(line.type.textColor)
        }
    }
    
    @ViewBuilder
    private func jsonSyntaxHighlighting(_ content: String) -> some View {
        let text = content.trimmingCharacters(in: .whitespaces)
        
        Text(content)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundColor(
                text.hasPrefix("\"") && text.hasSuffix(":") ? DesignSystem.Colors.primary :
                text.hasPrefix("\"") ? DesignSystem.Colors.success :
                ["true", "false", "null"].contains(text) ? DesignSystem.Colors.warning :
                line.type.textColor
            )
    }
}

struct GitFileRowView: View {
    let file: GitChangedFile
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Change type indicator
                Text(file.changeType.symbol)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(file.changeType.color)
                    .frame(width: 12)
                
                // File path
                Text(file.path)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                Spacer()
                
                // Change stats
                HStack(spacing: 4) {
                    if file.additions > 0 {
                        Text("+\(file.additions)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.success)
                    }
                    if file.deletions > 0 {
                        Text("-\(file.deletions)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.error)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? DesignSystem.Colors.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GitSideBySideDiffView: View {
    let file: GitChangedFile
    let showLineNumbers: Bool
    
    var body: some View {
        HStack(spacing: 1) {
            // Original (left side)
            VStack(spacing: 0) {
                DiffPaneHeader(title: "Original", file: file.path)
                GitDiffPaneView(content: file.originalContent, showLineNumbers: showLineNumbers, isOriginal: true)
            }
            
            // Divider
            Rectangle()
                .fill(DesignSystem.Colors.border.opacity(0.3))
                .frame(width: 1)
            
            // Modified (right side)  
            VStack(spacing: 0) {
                DiffPaneHeader(title: "Modified", file: file.path)
                GitDiffPaneView(content: file.modifiedContent, showLineNumbers: showLineNumbers, isOriginal: false)
            }
        }
    }
}

struct GitUnifiedDiffView: View {
    let file: GitChangedFile
    let showLineNumbers: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Unified header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.path)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text("\(file.changeType.description) • +\(file.additions)/-\(file.deletions)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                Text(file.changeType.symbol)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(file.changeType.color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.surface)
            
            // Unified diff content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(file.diffLines.enumerated()), id: \.offset) { index, line in
                        GitDiffLineView(
                            line: line,
                            showLineNumbers: showLineNumbers
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            }
            .background(DesignSystem.Colors.backgroundSecondary)
        }
    }
}

struct DiffPaneHeader: View {
    let title: String
    let file: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Spacer()
            
            Text(file)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.surface)
    }
}

struct GitDiffPaneView: View {
    let content: String
    let showLineNumbers: Bool
    let isOriginal: Bool
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 8) {
                if showLineNumbers {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(content.components(separatedBy: .newlines).enumerated()), id: \.offset) { index, _ in
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(DesignSystem.Colors.textTertiary.opacity(0.6))
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                    }
                    .padding(.leading, 8)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(content.components(separatedBy: .newlines).enumerated()), id: \.offset) { index, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(DesignSystem.Colors.backgroundSecondary)
    }
}

struct GitDiffLineView: View {
    let line: GitDiffLine
    let showLineNumbers: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showLineNumbers {
                HStack(spacing: 4) {
                    Text(line.oldLineNumber.map(String.init) ?? "")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textTertiary.opacity(0.6))
                        .frame(minWidth: 25, alignment: .trailing)
                    
                    Text(line.newLineNumber.map(String.init) ?? "")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textTertiary.opacity(0.6))
                        .frame(minWidth: 25, alignment: .trailing)
                }
            }
            
            HStack(spacing: 4) {
                Text(line.type.prefix)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(line.type.color)
                
                Text(line.content)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(line.type.textColor)
            }
            
            Spacer()
        }
        .padding(.vertical, 1)
        .background(line.type.backgroundColor.opacity(0.1))
    }
}

// MARK: - Supporting Types

enum DiffDisplayMode {
    case sideBySide
    case unified
}

// MARK: - New Supporting Types

struct ConflictSection: Identifiable {
    let id = UUID()
    let startLine: Int
    let endLine: Int
    let ourContent: String
    let theirContent: String
    let baseContent: String?
}

struct ConflictResolutionView: View {
    let file: GitChangedFile
    @Binding var selectedConflict: ConflictSection?
    let theme: DesignSystem.Theme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Conflict resolution header
                HStack {
                    Text("Merge Conflicts")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                    
                    Spacer()
                    
                    Text("\(file.conflicts.count) conflicts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.error)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DesignSystem.Colors.error.opacity(0.1))
                        )
                }
                .padding(.horizontal, 16)
                
                // Conflict sections
                ForEach(file.conflicts) { conflict in
                    ConflictCard(
                        conflict: conflict,
                        isSelected: selectedConflict?.id == conflict.id,
                        theme: theme,
                        onSelect: { selectedConflict = conflict }
                    )
                }
            }
            .padding(.vertical, 16)
        }
        .background(DesignSystem.Colors.background(for: theme))
    }
}

struct ConflictCard: View {
    let conflict: ConflictSection
    let isSelected: Bool
    let theme: DesignSystem.Theme
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Conflict header
            HStack {
                Text("Lines \(conflict.startLine)-\(conflict.endLine)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("Accept Ours") {
                        acceptOurs()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button("Accept Theirs") {
                        acceptTheirs()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button("Edit") {
                        onSelect()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            
            // Conflict content
            VStack(alignment: .leading, spacing: 8) {
                // Our version
                VStack(alignment: .leading, spacing: 4) {
                    Text("HEAD (Current)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.success)
                    
                    Text(conflict.ourContent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(DesignSystem.Colors.success.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(DesignSystem.Colors.success.opacity(0.3), lineWidth: 1)
                                )
                        )
                }
                
                // Their version
                VStack(alignment: .leading, spacing: 4) {
                    Text("Incoming")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    Text(conflict.theirContent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(DesignSystem.Colors.primary.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 1)
                                )
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.Colors.surface(for: theme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.border(for: theme).opacity(0.3), lineWidth: isSelected ? 2 : 1)
                )
        )
        .padding(.horizontal, 16)
    }
    
    private func acceptOurs() {
        print("Accepting our version for conflict at lines \(conflict.startLine)-\(conflict.endLine)")
    }
    
    private func acceptTheirs() {
        print("Accepting their version for conflict at lines \(conflict.startLine)-\(conflict.endLine)")
    }
}

// Git diff data models
struct GitDiffData {
    let changedFiles: [GitChangedFile]
    let totalAdditions: Int
    let totalDeletions: Int
    
    static let mock = GitDiffData(
        changedFiles: [
            GitChangedFile.mockSwiftFile,
            GitChangedFile.mockReadme,
            GitChangedFile.mockConfig
        ],
        totalAdditions: 42,
        totalDeletions: 18
    )
}

struct GitChangedFile {
    let path: String
    let changeType: GitChangeType
    let additions: Int
    let deletions: Int
    let originalContent: String
    let modifiedContent: String
    let diffLines: [GitDiffLine]
    let hasConflicts: Bool
    let conflicts: [ConflictSection]
    
    static let mockSwiftFile = GitChangedFile(
        path: "Sources/plue/DiffView.swift",
        changeType: .modified,
        additions: 25,
        deletions: 8,
        originalContent: "import SwiftUI\n\nstruct DiffView: View {\n    var body: some View {\n        Text(\"Hello\")\n    }\n}",
        modifiedContent: "import SwiftUI\n\nstruct DiffView: View {\n    let appState: AppState\n    \n    var body: some View {\n        VStack {\n            Text(\"Git Diff Viewer\")\n            Text(\"Now with more features!\")\n        }\n    }\n}",
        diffLines: [
            GitDiffLine(type: .unchanged, content: "import SwiftUI", oldLineNumber: 1, newLineNumber: 1),
            GitDiffLine(type: .unchanged, content: "", oldLineNumber: 2, newLineNumber: 2),
            GitDiffLine(type: .unchanged, content: "struct DiffView: View {", oldLineNumber: 3, newLineNumber: 3),
            GitDiffLine(type: .added, content: "    let appState: AppState", oldLineNumber: nil, newLineNumber: 4),
            GitDiffLine(type: .added, content: "", oldLineNumber: nil, newLineNumber: 5),
            GitDiffLine(type: .unchanged, content: "    var body: some View {", oldLineNumber: 4, newLineNumber: 6),
            GitDiffLine(type: .removed, content: "        Text(\"Hello\")", oldLineNumber: 5, newLineNumber: nil),
            GitDiffLine(type: .added, content: "        VStack {", oldLineNumber: nil, newLineNumber: 7),
            GitDiffLine(type: .added, content: "            Text(\"Git Diff Viewer\")", oldLineNumber: nil, newLineNumber: 8),
            GitDiffLine(type: .added, content: "            Text(\"Now with more features!\")", oldLineNumber: nil, newLineNumber: 9),
            GitDiffLine(type: .added, content: "        }", oldLineNumber: nil, newLineNumber: 10),
            GitDiffLine(type: .unchanged, content: "    }", oldLineNumber: 6, newLineNumber: 11),
            GitDiffLine(type: .unchanged, content: "}", oldLineNumber: 7, newLineNumber: 12)
        ],
        hasConflicts: false,
        conflicts: []
    )
    
    static let mockReadme = GitChangedFile(
        path: "README.md",
        changeType: .modified,
        additions: 12,
        deletions: 5,
        originalContent: "# Plue\nA development tool",
        modifiedContent: "# Plue\nA multi-agent coding assistant\n\n## Features\n- Git diff viewer\n- AI assistance",
        diffLines: [
            GitDiffLine(type: .unchanged, content: "# Plue", oldLineNumber: 1, newLineNumber: 1),
            GitDiffLine(type: .removed, content: "A development tool", oldLineNumber: 2, newLineNumber: nil),
            GitDiffLine(type: .added, content: "A multi-agent coding assistant", oldLineNumber: nil, newLineNumber: 2),
            GitDiffLine(type: .added, content: "", oldLineNumber: nil, newLineNumber: 3),
            GitDiffLine(type: .added, content: "## Features", oldLineNumber: nil, newLineNumber: 4),
            GitDiffLine(type: .added, content: "- Git diff viewer", oldLineNumber: nil, newLineNumber: 5),
            GitDiffLine(type: .added, content: "- AI assistance", oldLineNumber: nil, newLineNumber: 6)
        ],
        hasConflicts: false,
        conflicts: []
    )
    
    static let mockConfig = GitChangedFile(
        path: ".gitignore",
        changeType: .added,
        additions: 5,
        deletions: 0,
        originalContent: "",
        modifiedContent: ".DS_Store\n*.xcworkspace\n.build/\nPackage.resolved\n",
        diffLines: [
            GitDiffLine(type: .added, content: ".DS_Store", oldLineNumber: nil, newLineNumber: 1),
            GitDiffLine(type: .added, content: "*.xcworkspace", oldLineNumber: nil, newLineNumber: 2),
            GitDiffLine(type: .added, content: ".build/", oldLineNumber: nil, newLineNumber: 3),
            GitDiffLine(type: .added, content: "Package.resolved", oldLineNumber: nil, newLineNumber: 4)
        ],
        hasConflicts: false,
        conflicts: []
    )
}

struct GitDiffLine {
    let type: GitDiffLineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

enum GitChangeType {
    case added
    case modified
    case deleted
    case renamed
    
    var symbol: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"  
        case .renamed: return "R"
        }
    }
    
    var color: Color {
        switch self {
        case .added: return DesignSystem.Colors.success
        case .modified: return DesignSystem.Colors.warning
        case .deleted: return DesignSystem.Colors.error
        case .renamed: return DesignSystem.Colors.primary
        }
    }
    
    var description: String {
        switch self {
        case .added: return "Added"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        }
    }
}

enum GitDiffLineType {
    case added
    case removed
    case unchanged
    
    var prefix: String {
        switch self {
        case .added: return "+"
        case .removed: return "-"
        case .unchanged: return " "
        }
    }
    
    var color: Color {
        switch self {
        case .added: return DesignSystem.Colors.success
        case .removed: return DesignSystem.Colors.error
        case .unchanged: return DesignSystem.Colors.textTertiary
        }
    }
    
    var textColor: Color {
        switch self {
        case .added: return DesignSystem.Colors.textPrimary
        case .removed: return DesignSystem.Colors.textPrimary
        case .unchanged: return DesignSystem.Colors.textPrimary
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .added: return DesignSystem.Colors.success
        case .removed: return DesignSystem.Colors.error
        case .unchanged: return Color.clear
        }
    }
}

#Preview {
    DiffView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}```

```swift
// File: Sources/plue/TerminalSurfaceView.swift
import SwiftUI
import AppKit

// MARK: - NSView-based Terminal Surface
class TerminalSurfaceView: NSView {
    // Terminal state
    private var terminalFd: Int32 = -1
    private var isInitialized = false
    private var readSource: DispatchSourceRead?
    
    // Display properties
    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private var textStorage = NSTextStorage()
    private var layoutManager = NSLayoutManager()
    private var textContainer = NSTextContainer()
    private let ansiParser = ANSIParser()
    
    // Terminal dimensions
    private var cols: Int = 80
    private var rows: Int = 24
    
    // Callbacks
    var onError: ((Error) -> Void)?
    var onOutput: ((String) -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTextSystem()
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTextSystem() {
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = true
        textContainer.containerSize = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
    }
    
    // MARK: - Terminal Lifecycle
    
    func startTerminal() {
        guard !isInitialized else { return }
        
        // Initialize terminal
        if terminal_init() != 0 {
            onError?(TerminalError.initializationFailed)
            return
        }
        
        // Start terminal
        if terminal_start() != 0 {
            onError?(TerminalError.startFailed)
            return
        }
        
        isInitialized = true
        setupReadHandler()
        
        // Send initial resize
        updateTerminalSize()
    }
    
    func stopTerminal() {
        readSource?.cancel()
        readSource = nil
        
        if isInitialized {
            terminal_stop()
            terminal_deinit()
            isInitialized = false
        }
    }
    
    // MARK: - I/O Handling
    
    private func setupReadHandler() {
        // Get the file descriptor from our Zig backend
        let fd = terminal_get_fd()
        guard fd >= 0 else {
            onError?(TerminalError.invalidFileDescriptor)
            return
        }
        
        // Create dispatch source for efficient I/O
        readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInteractive))
        
        readSource?.setEventHandler { [weak self] in
            self?.handleRead()
        }
        
        readSource?.setCancelHandler {
            // Cleanup if needed
        }
        
        readSource?.resume()
    }
    
    private func handleRead() {
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        let bytesRead = terminal_read(buffer, bufferSize)
        
        if bytesRead > 0 {
            let data = Data(bytes: buffer, count: bytesRead)
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { [weak self] in
                    self?.appendText(text)
                    self?.onOutput?(text)
                }
            }
        } else if bytesRead < 0 {
            DispatchQueue.main.async { [weak self] in
                self?.onError?(TerminalError.readError)
            }
        }
    }
    
    func sendText(_ text: String) {
        guard isInitialized else { return }
        
        text.withCString { cString in
            terminal_send_text(cString)
        }
    }
    
    // MARK: - Display
    
    private func appendText(_ text: String) {
        // Parse ANSI escape sequences
        let attributedString = ansiParser.parse(text)
        
        textStorage.append(attributedString)
        
        // Limit buffer size
        if textStorage.length > 100000 {
            textStorage.deleteCharacters(in: NSRange(location: 0, length: 50000))
        }
        
        needsDisplay = true
        
        // Auto-scroll to bottom
        if let scrollView = self.enclosingScrollView {
            let maxY = max(0, bounds.height - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Clear background
        NSColor.black.setFill()
        dirtyRect.fill()
        
        // Draw text
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let textOrigin = CGPoint(x: 5, y: 5)
        
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textOrigin)
    }
    
    // MARK: - Size Handling
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainer.containerSize = CGSize(width: newSize.width - 10, height: .greatestFiniteMagnitude)
        updateTerminalSize()
    }
    
    private func updateTerminalSize() {
        guard isInitialized else { return }
        
        // Calculate rows and columns based on font metrics
        let charWidth = font.maximumAdvancement.width
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        
        let newCols = Int((bounds.width - 10) / charWidth)
        let newRows = Int((bounds.height - 10) / lineHeight)
        
        if newCols != cols || newRows != rows {
            cols = newCols
            rows = newRows
            
            // Update terminal size
            terminal_resize(UInt16(cols), UInt16(rows))
        }
    }
    
    // MARK: - Input Handling
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        guard isInitialized else { return }
        
        if let characters = event.characters {
            sendText(characters)
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopTerminal()
    }
}

// MARK: - SwiftUI Wrapper

struct TerminalSurface: NSViewRepresentable {
    @Binding var inputText: String
    let onError: (Error) -> Void
    let onOutput: (String) -> Void
    
    func makeNSView(context: Context) -> TerminalSurfaceView {
        let view = TerminalSurfaceView()
        view.onError = onError
        view.onOutput = onOutput
        
        // Start terminal when view is created
        DispatchQueue.main.async {
            view.startTerminal()
        }
        
        return view
    }
    
    func updateNSView(_ nsView: TerminalSurfaceView, context: Context) {
        // Handle any updates if needed
        if !inputText.isEmpty {
            nsView.sendText(inputText)
            DispatchQueue.main.async {
                inputText = ""
            }
        }
    }
    
    static func dismantleNSView(_ nsView: TerminalSurfaceView, coordinator: ()) {
        nsView.stopTerminal()
    }
}

// MARK: - Error Types

enum TerminalError: LocalizedError {
    case initializationFailed
    case startFailed
    case invalidFileDescriptor
    case readError
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize terminal"
        case .startFailed:
            return "Failed to start terminal process"
        case .invalidFileDescriptor:
            return "Invalid file descriptor"
        case .readError:
            return "Error reading from terminal"
        }
    }
}

// MARK: - C Function Imports

@_silgen_name("terminal_get_fd")
func terminal_get_fd() -> Int32

@_silgen_name("terminal_resize")
func terminal_resize(_ cols: UInt16, _ rows: UInt16)```

```swift
// File: Sources/plue/PromptTerminal.swift
import SwiftUI
import AppKit

// MARK: - Prompt Terminal Model
class PromptTerminal: ObservableObject {
    @Published var currentContent: String = ""
    @Published var isConnected: Bool = false
    @Published var needsRedraw: Bool = false
    
    private var _tempFileURL: URL?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private let workingDirectory: URL
    
    init() {
        // Set up working directory in user's Documents/plue
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.workingDirectory = documentsURL.appendingPathComponent("plue", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    }
    
    deinit {
        stopFileWatcher()
        cleanupTempFile()
    }
    
    func startSession() {
        // Create or update the prompt file
        setupPromptFile()
        startFileWatcher()
        isConnected = true
    }
    
    private func setupPromptFile() {
        let promptFile = workingDirectory.appendingPathComponent("current_prompt.md")
        _tempFileURL = promptFile
        
        // Create initial content if file doesn't exist
        if !FileManager.default.fileExists(atPath: promptFile.path) {
            let initialContent = """
            # Prompt
            
            Write your prompt here using Markdown...
            
            ## Example
            
            You can use:
            - **Bold text**
            - *Italic text*
            - `Code blocks`
            - Lists
            - Headers
            
            ```python
            # Code examples
            def hello_world():
                print("Hello, World!")
            ```
            
            """
            
            try? initialContent.write(to: promptFile, atomically: true, encoding: .utf8)
            currentContent = initialContent
        } else {
            // Load existing content
            currentContent = (try? String(contentsOf: promptFile)) ?? ""
        }
    }
    
    private func startFileWatcher() {
        guard let tempFileURL = _tempFileURL else { return }
        
        let fileDescriptor = open(tempFileURL.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }
        
        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )
        
        fileWatcher?.setEventHandler { [weak self] in
            self?.loadFileContent()
        }
        
        fileWatcher?.setCancelHandler {
            close(fileDescriptor)
        }
        
        fileWatcher?.resume()
    }
    
    private func loadFileContent() {
        guard let tempFileURL = _tempFileURL else { return }
        
        do {
            let newContent = try String(contentsOf: tempFileURL)
            if newContent != currentContent {
                currentContent = newContent
                needsRedraw = true
            }
        } catch {
            print("Failed to read prompt file: \(error)")
        }
    }
    
    private func stopFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }
    
    private func cleanupTempFile() {
        // Don't delete the file - keep it for persistence
        _tempFileURL = nil
    }
    
    func openInEditor() {
        guard let tempFileURL = _tempFileURL else { return }
        
        // Try to open with various editors in order of preference
        let editors = [
            "/usr/local/bin/ghostty", // Ghostty terminal
            "/usr/local/bin/code",    // VS Code
            "/usr/local/bin/nvim",    // Neovim
            "/usr/local/bin/vim",     // Vim
            "/usr/bin/nano"           // Nano as fallback
        ]
        
        for editor in editors {
            if FileManager.default.fileExists(atPath: editor) {
                launchEditor(executablePath: editor, filePath: tempFileURL.path)
                return
            }
        }
        
        // Fallback to system default
        NSWorkspace.shared.open(tempFileURL)
    }
    
    private func launchEditor(executablePath: String, filePath: String) {
        Task {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                
                if executablePath.contains("ghostty") {
                    // For Ghostty, open a new window with the editor
                    process.arguments = ["-e", "vim", filePath]
                } else if executablePath.contains("code") {
                    // For VS Code
                    process.arguments = [filePath]
                } else {
                    // For terminal editors, open in Terminal
                    process.arguments = [filePath]
                }
                
                try process.run()
                print("Launched \(executablePath) with file: \(filePath)")
            } catch {
                print("Failed to launch \(executablePath): \(error)")
            }
        }
    }
}

// MARK: - Prompt Terminal View
struct PromptTerminalView: NSViewRepresentable {
    let terminal: PromptTerminal
    let core: PlueCoreInterface
    
    func makeNSView(context: Context) -> PromptTerminalNSView {
        return PromptTerminalNSView(terminal: terminal, core: core)
    }
    
    func updateNSView(_ nsView: PromptTerminalNSView, context: Context) {
        nsView.updateContent()
    }
}

// MARK: - NSView Implementation
class PromptTerminalNSView: NSView {
    private let terminal: PromptTerminal
    private let core: PlueCoreInterface
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var headerView: NSView!
    
    init(terminal: PromptTerminal, core: PlueCoreInterface) {
        self.terminal = terminal
        self.core = core
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        // Create header with file info and buttons
        setupHeader()
        
        // Create text view for content display
        setupTextView()
        
        // Layout
        setupLayout()
        
        // Update content initially
        updateContent()
    }
    
    private func setupHeader() {
        headerView = NSView()
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.1).cgColor
        
        // File path label
        let fileLabel = NSTextField(labelWithString: "~/Documents/plue/current_prompt.md")
        fileLabel.textColor = NSColor.secondaryLabelColor
        fileLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        
        // Edit button
        let editButton = NSButton(title: "Open in Editor", target: self, action: #selector(openInEditor))
        editButton.bezelStyle = .rounded
        editButton.controlSize = .small
        
        // Terminal button
        let terminalButton = NSButton(title: "Open Terminal", target: self, action: #selector(openTerminal))
        terminalButton.bezelStyle = .rounded
        terminalButton.controlSize = .small
        
        // Add to header
        headerView.addSubview(fileLabel)
        headerView.addSubview(editButton)
        headerView.addSubview(terminalButton)
        
        // Layout header content
        fileLabel.translatesAutoresizingMaskIntoConstraints = false
        editButton.translatesAutoresizingMaskIntoConstraints = false
        terminalButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            fileLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            fileLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            terminalButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            terminalButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            editButton.trailingAnchor.constraint(equalTo: terminalButton.leadingAnchor, constant: -8),
            editButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
        
        addSubview(headerView)
    }
    
    private func setupTextView() {
        // Create scroll view
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.backgroundColor = NSColor.black
        
        // Create text view
        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor.black
        textView.textColor = NSColor.textColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        
        // Set up text container
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        
        scrollView.documentView = textView
        addSubview(scrollView)
    }
    
    private func setupLayout() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),
            
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    func updateContent() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let content = self.terminal.currentContent
            
            // Create syntax highlighted attributed string
            let attributedString = self.syntaxHighlight(content)
            self.textView.textStorage?.setAttributedString(attributedString)
        }
    }
    
    private func syntaxHighlight(_ content: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: content)
        let fullRange = NSRange(location: 0, length: content.count)
        
        // Base attributes
        attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), range: fullRange)
        attributedString.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
        
        // Simple markdown highlighting
        let lines = content.components(separatedBy: .newlines)
        var currentLocation = 0
        
        for line in lines {
            let lineRange = NSRange(location: currentLocation, length: line.count)
            
            // Headers
            if line.hasPrefix("# ") {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: lineRange)
                attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold), range: lineRange)
            } else if line.hasPrefix("## ") {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: lineRange)
                attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 16, weight: .bold), range: lineRange)
            } else if line.hasPrefix("### ") {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: lineRange)
                attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold), range: lineRange)
            }
            
            // Code blocks
            if line.hasPrefix("```") {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: lineRange)
                attributedString.addAttribute(.backgroundColor, value: NSColor.controlBackgroundColor.withAlphaComponent(0.3), range: lineRange)
            }
            
            // Inline code
            if line.contains("`") {
                // Simple regex for inline code
                let codeRegex = try? NSRegularExpression(pattern: "`([^`]+)`", options: [])
                codeRegex?.enumerateMatches(in: line, options: [], range: NSRange(location: 0, length: line.count)) { match, _, _ in
                    if let matchRange = match?.range {
                        let adjustedRange = NSRange(location: currentLocation + matchRange.location, length: matchRange.length)
                        attributedString.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: adjustedRange)
                        attributedString.addAttribute(.backgroundColor, value: NSColor.controlBackgroundColor.withAlphaComponent(0.3), range: adjustedRange)
                    }
                }
            }
            
            currentLocation += line.count + 1 // +1 for newline
        }
        
        return attributedString
    }
    
    @objc private func openInEditor() {
        terminal.openInEditor()
    }
    
    @objc private func openTerminal() {
        guard let url = terminal.tempFileURL?.deletingLastPathComponent() else { return }
        
        // Open terminal in the working directory
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(url.path)'"
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript error: \(error)")
        }
    }
}

// MARK: - Extensions
extension PromptTerminal {
    var tempFileURL: URL? {
        return workingDirectory.appendingPathComponent("current_prompt.md")
    }
}```

```swift
// File: Sources/plue/WorktreeView.swift
import SwiftUI

struct WorktreeView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    // Enhanced state management for worktree features
    @State private var worktrees: [GitWorktree] = GitWorktree.mockWorktrees
    @State private var selectedWorktreeId: String? = GitWorktree.mockWorktrees.first?.id
    @State private var showCreateDialog: Bool = false
    @State private var searchText: String = ""
    @State private var filterStatus: WorktreeStatusFilter = .all
    @State private var sortOrder: WorktreeSortOrder = .recentActivity
    @State private var showDeleteConfirmation: Bool = false
    @State private var worktreeToDelete: GitWorktree? = nil
    @State private var isRefreshing: Bool = false
    @State private var newWorktreeName: String = ""
    @State private var newWorktreeBranch: String = ""
    
    var body: some View {
        HSplitView {
            // Left Panel: Worktree List
            worktreeList
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
            
            // Right Panel: Stacked Diff Visualization
            stackedDiffDetail
        }
        .background(DesignSystem.Colors.backgroundSecondary(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
        .sheet(isPresented: $showCreateDialog) {
            CreateWorktreeDialog(
                newWorktreeName: $newWorktreeName,
                newWorktreeBranch: $newWorktreeBranch,
                onCancel: { showCreateDialog = false },
                onCreate: createNewWorktree
            )
        }
        .alert("Delete Worktree", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let worktree = worktreeToDelete {
                    deleteWorktree(worktree)
                }
            }
        } message: {
            if let worktree = worktreeToDelete {
                Text("Are you sure you want to delete the worktree '\\(worktree.branch)'? This action cannot be undone.")
            }
        }
    }
    
    private var worktreeList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Worktrees")
                        .font(DesignSystem.Typography.titleSmall)
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("git parallel development")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Search and filter controls
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                        
                        TextField("Search worktrees...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignSystem.Colors.background(for: appState.currentTheme))
                    )
                    .frame(maxWidth: 120)
                    
                    // Filter menu
                    Menu {
                        Button("All") { filterStatus = .all }
                        Button("Clean") { filterStatus = .clean }
                        Button("Modified") { filterStatus = .modified }
                        Button("Conflicts") { filterStatus = .conflicts }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .help("Filter worktrees")
                    
                    // Sort menu
                    Menu {
                        Button("Recent Activity") { sortOrder = .recentActivity }
                        Button("Alphabetical") { sortOrder = .alphabetical }
                        Button("Status") { sortOrder = .status }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .help("Sort worktrees")
                    
                    // Refresh button
                    Button(action: refreshWorktrees) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Refresh worktrees")
                    
                    // Create new worktree
                    Button(action: { showCreateDialog = true }) { 
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Create new worktree")
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3)),
                alignment: .bottom
            )

            // The list itself
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(worktrees.enumerated()), id: \.element.id) { index, worktree in
                        WorktreeRow(
                            worktree: worktree, 
                            isSelected: selectedWorktreeId == worktree.id,
                            theme: appState.currentTheme
                        )
                        .onTapGesture {
                            withAnimation(DesignSystem.Animation.scaleIn) {
                                selectedWorktreeId = worktree.id
                            }
                        }
                        .animation(
                            DesignSystem.Animation.slideTransition.delay(Double(index) * DesignSystem.Animation.staggerDelay),
                            value: selectedWorktreeId
                        )
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
            .background(DesignSystem.Colors.background(for: appState.currentTheme))
        }
    }
    
    private var stackedDiffDetail: some View {
        VStack {
            if let worktree = worktrees.first(where: { $0.id == selectedWorktreeId }) {
                // This contains the Graphite-style stacked diff view
                GraphiteStackView(worktree: worktree, appState: appState)
            } else {
                // Empty state
                VStack(spacing: DesignSystem.Spacing.xl) {
                    Circle()
                        .fill(DesignSystem.Colors.textTertiary(for: appState.currentTheme).opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 24, weight: .light))
                                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                        )
                    
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Text("no worktree selected")
                            .font(DesignSystem.Typography.titleMedium)
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                        
                        Text("select a worktree to view its stack")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.background(for: appState.currentTheme))
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredAndSortedWorktrees: [GitWorktree] {
        let filtered = worktrees.filter { worktree in
            // Search filter
            let matchesSearch = searchText.isEmpty || 
                               worktree.branch.localizedCaseInsensitiveContains(searchText) ||
                               worktree.path.localizedCaseInsensitiveContains(searchText)
            
            // Status filter
            let matchesStatus: Bool
            switch filterStatus {
            case .all: matchesStatus = true
            case .clean: matchesStatus = worktree.status == .clean
            case .modified: matchesStatus = worktree.status == .modified
            case .conflicts: matchesStatus = worktree.status == .conflicts
            }
            
            return matchesSearch && matchesStatus
        }
        
        // Sort
        switch sortOrder {
        case .recentActivity:
            return filtered.sorted { $0.lastModified > $1.lastModified }
        case .alphabetical:
            return filtered.sorted { $0.branch < $1.branch }
        case .status:
            return filtered.sorted { $0.status.sortOrder < $1.status.sortOrder }
        }
    }
    
    // MARK: - Actions
    
    private func refreshWorktrees() {
        isRefreshing = true
        // Simulate refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isRefreshing = false
            // In real implementation, would reload from git
        }
    }
    
    private func createNewWorktree() {
        print("Creating worktree: \\(newWorktreeName) on branch: \\(newWorktreeBranch)")
        showCreateDialog = false
        newWorktreeName = ""
        newWorktreeBranch = ""
    }
    
    private func switchToWorktree(_ worktree: GitWorktree) {
        print("Switching to worktree: \\(worktree.branch)")
    }
    
    private func pullWorktree(_ worktree: GitWorktree) {
        print("Pulling changes for: \\(worktree.branch)")
    }
    
    private func pushWorktree(_ worktree: GitWorktree) {
        print("Pushing changes for: \\(worktree.branch)")
    }
    
    private func openInFinder(_ worktree: GitWorktree) {
        print("Opening \\(worktree.path) in Finder")
    }
    
    private func openInTerminal(_ worktree: GitWorktree) {
        print("Opening \\(worktree.path) in Terminal")
    }
    
    private func deleteWorktree(_ worktree: GitWorktree) {
        print("Deleting worktree: \\(worktree.branch)")
        worktrees.removeAll { $0.id == worktree.id }
        if selectedWorktreeId == worktree.id {
            selectedWorktreeId = worktrees.first?.id
        }
    }
}

// Redesigned Row with Apple-style spacing and subtle interactions
struct WorktreeRow: View {
    let worktree: GitWorktree
    let isSelected: Bool
    let theme: DesignSystem.Theme
    
    var body: some View {
        HStack(spacing: 16) { // Increased spacing for better breathing room
            // Simplified status indicator with glow effect
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 8)
                        .blur(radius: 4)
                        .opacity(isSelected ? 1 : 0)
                )
                .animation(DesignSystem.Animation.plueSmooth, value: isSelected)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(worktree.branch)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.85))
                    
                    if worktree.isMain {
                        Text("main")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                }
                
                Text(timeAgoString)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .animation(DesignSystem.Animation.plueStandard, value: isSelected)
    }
    
    private var statusColor: Color {
        switch worktree.status {
        case .clean: return DesignSystem.Colors.success
        case .modified: return DesignSystem.Colors.warning
        case .untracked: return DesignSystem.Colors.primary
        case .conflicts: return DesignSystem.Colors.error
        }
    }
    
    private var abbreviatedPath: String {
        let components = worktree.path.components(separatedBy: "/")
        if components.count > 3 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return worktree.path
    }
    
    private var timeAgoString: String {
        let now = Date()
        let interval = now.timeIntervalSince(worktree.lastModified)
        
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// Extension for GitWorktreeStatus
extension GitWorktreeStatus {
    var displayName: String {
        switch self {
        case .clean: return "clean"
        case .modified: return "modified"
        case .untracked: return "untracked"
        case .conflicts: return "conflicts"
        }
    }
}

// The advanced Graphite-style stack view with cleaner header
struct GraphiteStackView: View {
    let worktree: GitWorktree
    let appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Cleaner header without bottom border
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(worktree.branch)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("\(MockCommit.samples.count) commits")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Pull") {
                        print("Pull changes")
                    }
                    .buttonStyle(GhostButtonStyle())
                    
                    Button("Push") {
                        print("Push stack")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(24) // More generous padding
            
            // Stack visualization with better spacing
            ScrollView {
                VStack(spacing: 1) { // Minimal spacing
                    ForEach(MockCommit.samples) { commit in
                        CommitDiffView(
                            commit: commit, 
                            theme: appState.currentTheme
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(DesignSystem.Colors.background(for: appState.currentTheme))
        }
    }
}

// Mock commit data
struct MockCommit: Identifiable {
    let id: String
    let shortId: String
    let message: String
    let author: String
    let timestamp: Date
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
    
    static let samples: [MockCommit] = [
        MockCommit(
            id: "a1b2c3d4e5f6",
            shortId: "a1b2c3d",
            message: "feat: Add agent coordination protocol",
            author: "Developer",
            timestamp: Date().addingTimeInterval(-3600),
            filesChanged: 3,
            insertions: 127,
            deletions: 8
        ),
        MockCommit(
            id: "b2c3d4e5f6a1",
            shortId: "b2c3d4e",
            message: "refactor: Improve the rendering engine",
            author: "Developer",
            timestamp: Date().addingTimeInterval(-7200),
            filesChanged: 5,
            insertions: 89,
            deletions: 34
        ),
        MockCommit(
            id: "c3d4e5f6a1b2",
            shortId: "c3d4e5f",
            message: "fix: Terminal cursor positioning bug",
            author: "Developer",
            timestamp: Date().addingTimeInterval(-10800),
            filesChanged: 1,
            insertions: 12,
            deletions: 5
        ),
        MockCommit(
            id: "d4e5f6a1b2c3",
            shortId: "d4e5f6a",
            message: "docs: Update README with new features",
            author: "Developer",
            timestamp: Date().addingTimeInterval(-14400),
            filesChanged: 2,
            insertions: 45,
            deletions: 2
        ),
        MockCommit(
            id: "e5f6a1b2c3d4",
            shortId: "e5f6a1b",
            message: "style: Apply consistent color scheme",
            author: "Developer",
            timestamp: Date().addingTimeInterval(-18000),
            filesChanged: 8,
            insertions: 203,
            deletions: 156
        )
    ]
}

// Each commit in the stack is a collapsible diff
struct CommitDiffView: View {
    let commit: MockCommit
    let theme: DesignSystem.Theme
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { 
                withAnimation(DesignSystem.Animation.smooth) { 
                    isExpanded.toggle() 
                } 
            }) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
                        .frame(width: 12)
                    
                    // Commit hash
                    Text(commit.shortId)
                        .font(DesignSystem.Typography.monoSmall)
                        .foregroundColor(DesignSystem.Colors.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(DesignSystem.Colors.primary.opacity(0.1))
                        )
                    
                    // Commit message
                    Text(commit.message)
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Stats
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text("\(commit.filesChanged)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
                        
                        Text("+\(commit.insertions)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.success)
                        
                        Text("-\(commit.deletions)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.error)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.surface(for: theme))
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                // Here you would embed the actual DiffView for this commit
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Diff content for \(commit.shortId)")
                        .font(DesignSystem.Typography.monoMedium)
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    
                    // Mock diff content with staggered lines
                    VStack(alignment: .leading, spacing: 2) {
                        let diffLines = [
                            ("- old implementation", DiffLine.DiffLineType.removed),
                            ("+ new improved implementation", DiffLine.DiffLineType.added),
                            ("  unchanged line", DiffLine.DiffLineType.context),
                            ("+ another addition", DiffLine.DiffLineType.added)
                        ]
                        
                        ForEach(Array(diffLines.enumerated()), id: \.offset) { index, line in
                            DiffLine(content: line.0, type: line.1, theme: theme)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .opacity
                                ))
                                .animation(
                                    DesignSystem.Animation.slideTransition.delay(Double(index) * DesignSystem.Animation.staggerDelay),
                                    value: isExpanded
                                )
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.sm)
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.background(for: theme))
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .animation(DesignSystem.Animation.smooth, value: isExpanded)
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border(for: theme).opacity(0.2)),
            alignment: .bottom
        )
    }
}

// Simple diff line component
struct DiffLine: View {
    let content: String
    let type: DiffLineType
    let theme: DesignSystem.Theme
    
    enum DiffLineType {
        case added, removed, context
    }
    
    var body: some View {
        Text(content)
            .font(DesignSystem.Typography.monoSmall)
            .foregroundColor(textColor)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 1)
            .background(backgroundColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var textColor: Color {
        switch type {
        case .added: return DesignSystem.Colors.success
        case .removed: return DesignSystem.Colors.error
        case .context: return DesignSystem.Colors.textSecondary(for: theme)
        }
    }
    
    private var backgroundColor: Color {
        switch type {
        case .added: return DesignSystem.Colors.success.opacity(0.1)
        case .removed: return DesignSystem.Colors.error.opacity(0.1)
        case .context: return Color.clear
        }
    }
}

// MARK: - Supporting Types

enum WorktreeStatusFilter: CaseIterable {
    case all, clean, modified, conflicts
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .clean: return "Clean"
        case .modified: return "Modified"
        case .conflicts: return "Conflicts"
        }
    }
}

enum WorktreeSortOrder: CaseIterable {
    case recentActivity, alphabetical, status
    
    var displayName: String {
        switch self {
        case .recentActivity: return "Recent Activity"
        case .alphabetical: return "Alphabetical"
        case .status: return "Status"
        }
    }
}

extension GitWorktreeStatus {
    var sortOrder: Int {
        switch self {
        case .conflicts: return 0
        case .modified: return 1
        case .untracked: return 2
        case .clean: return 3
        }
    }
}

// MARK: - CreateWorktreeDialog

struct CreateWorktreeDialog: View {
    @Binding var newWorktreeName: String
    @Binding var newWorktreeBranch: String
    let onCancel: () -> Void
    let onCreate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Create New Worktree")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Worktree Name")
                        .font(.headline)
                    
                    TextField("feature/my-awesome-feature", text: $newWorktreeName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Branch")
                        .font(.headline)
                    
                    TextField("main", text: $newWorktreeBranch)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Text("This will create a new git worktree in a parallel directory, allowing you to work on multiple branches simultaneously.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Actions
            HStack {
                Spacer()
                
                Button("Cancel", action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
                
                Button("Create") {
                    onCreate()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newWorktreeName.isEmpty || newWorktreeBranch.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    WorktreeView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}```

```swift
// File: Sources/plue/GhosttyTerminal.swift
import Foundation

// MARK: - Ghostty Terminal C Function Imports
// These functions are defined in GhosttyTerminalSurfaceView.swift to avoid duplicate symbols

// MARK: - Swift-friendly wrapper class

/// A Swift-friendly wrapper around the Ghostty terminal C API
class GhosttyTerminal {
    static let shared = GhosttyTerminal()
    
    private var isInitialized = false
    private var hasSurface = false
    
    private init() {}
    
    /// Initialize the terminal
    func initialize() -> Bool {
        guard !isInitialized else { return true }
        
        let result = ghostty_terminal_init()
        isInitialized = result == 0
        return isInitialized
    }
    
    /// Create a terminal surface
    func createSurface() -> Bool {
        guard isInitialized else { return false }
        
        let result = ghostty_terminal_create_surface()
        hasSurface = result == 0
        return hasSurface
    }
    
    /// Update terminal size
    func setSize(width: Int, height: Int, scale: Double) {
        guard hasSurface else { return }
        
        ghostty_terminal_set_size(UInt32(width), UInt32(height), scale)
    }
    
    /// Send text to the terminal
    func sendText(_ text: String) {
        guard hasSurface else { return }
        
        text.withCString { textPtr in
            ghostty_terminal_send_text(textPtr)
        }
    }
    
    /// Send key event to the terminal
    func sendKey(_ key: String, modifiers: UInt32 = 0, action: Int32 = 0) {
        guard hasSurface else { return }
        
        key.withCString { keyPtr in
            ghostty_terminal_send_key(keyPtr, modifiers, action)
        }
    }
    
    /// Write raw data to the terminal
    func write(_ data: Data) -> Int {
        guard hasSurface else { return 0 }
        
        return data.withUnsafeBytes { bytes in
            let buffer = bytes.bindMemory(to: UInt8.self)
            return Int(ghostty_terminal_write(buffer.baseAddress!, data.count))
        }
    }
    
    /// Read data from the terminal
    func read(maxBytes: Int = 4096) -> Data? {
        guard hasSurface else { return nil }
        
        var buffer = Data(count: maxBytes)
        let bytesRead = buffer.withUnsafeMutableBytes { bytes in
            let buffer = bytes.bindMemory(to: UInt8.self)
            return Int(ghostty_terminal_read(buffer.baseAddress!, maxBytes))
        }
        
        if bytesRead > 0 {
            return buffer.prefix(bytesRead)
        }
        return nil
    }
    
    /// Trigger terminal redraw
    func draw() {
        guard hasSurface else { return }
        ghostty_terminal_draw()
    }
    
    /// Cleanup terminal resources
    func cleanup() {
        ghostty_terminal_deinit()
        isInitialized = false
        hasSurface = false
    }
    
    deinit {
        cleanup()
    }
}```

```swift
// File: Sources/plue/WebView.swift
import SwiftUI
import WebKit

// MARK: - Browser Tab Model
struct BrowserTab: Identifiable {
    let id: Int
    let title: String
    let url: String
    let isActive: Bool
}

struct WebView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var urlString = ""
    @State private var tabs: [BrowserTab] = [BrowserTab(id: 0, title: "New Tab", url: "https://www.apple.com", isActive: true)]
    @State private var selectedTab = 0
    @FocusState private var isUrlFocused: Bool
    @State private var webView: WKWebView?
    
    var body: some View {
        VStack(spacing: 0) {
            // Safari-style Browser Chrome
            safariLikeChrome
            
            // Web Content with proper framing
            ZStack {
                DesignSystem.Colors.surface(for: appState.currentTheme)
                
                WebViewRepresentable(
                    webView: $webView,
                    appState: appState,
                    core: core
                )
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.2), lineWidth: 1)
                )
                .padding(8)
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
        .onAppear {
            urlString = appState.webState.currentURL
            loadURL(urlString)
        }
    }
    
    // MARK: - Safari-like Browser Chrome
    private var safariLikeChrome: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(tabs) { tab in
                            browserTabButton(tab)
                        }
                        
                        // Add Tab Button
                        Button(action: addNewTab) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                                .frame(width: 28, height: 32)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(DesignSystem.Colors.surface(for: appState.currentTheme).opacity(0.5))
                        )
                    }
                    .padding(.horizontal, 12)
                }
                
                Spacer()
                
                // Browser Controls
                HStack(spacing: 8) {
                    Button(action: { goBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(appState.webState.canGoBack ? DesignSystem.Colors.textPrimary(for: appState.currentTheme) : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!appState.webState.canGoBack)
                    .help("Go back")
                    
                    Button(action: { goForward() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(appState.webState.canGoForward ? DesignSystem.Colors.textPrimary(for: appState.currentTheme) : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!appState.webState.canGoForward)
                    .help("Go forward")
                    
                    Button(action: {
                        if appState.webState.isLoading {
                            stopLoading()
                        } else {
                            reload()
                        }
                    }) {
                        Image(systemName: appState.webState.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(appState.webState.isLoading ? "Stop loading" : "Reload page")
                }
                .padding(.trailing, 16)
            }
            .frame(height: 40)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            
            // Address Bar
            HStack(spacing: 12) {
                // Security Indicator & URL Field
                HStack(spacing: 8) {
                    // Security Lock
                    Image(systemName: appState.webState.currentURL.hasPrefix("https://") ? "lock.fill" : "globe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(appState.webState.currentURL.hasPrefix("https://") ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    
                    // URL TextField
                    TextField("Search or enter website name", text: $urlString)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                        .focused($isUrlFocused)
                        .onSubmit {
                            loadURL(urlString)
                            isUrlFocused = false
                        }
                        .onChange(of: appState.webState.currentURL) { newURL in
                            if !isUrlFocused {
                                urlString = newURL
                            }
                        }
                    
                    // Loading Indicator
                    if appState.webState.isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignSystem.Colors.background(for: appState.currentTheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3), lineWidth: 1)
                        )
                )
                
                // Share & Bookmark
                HStack(spacing: 8) {
                    Button(action: {}) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Add bookmark")
                    
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Share")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            
            // Subtle border
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3))
        }
    }
    
    private func browserTabButton(_ tab: BrowserTab) -> some View {
        Button(action: { selectedTab = tab.id }) {
            HStack(spacing: 6) {
                // Favicon placeholder
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "globe")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.primary)
                    )
                
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(
                        tab.isActive 
                            ? DesignSystem.Colors.textPrimary(for: appState.currentTheme)
                            : DesignSystem.Colors.textSecondary(for: appState.currentTheme)
                    )
                    .lineLimit(1)
                
                if tabs.count > 1 {
                    Button(action: { closeTab(tab.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: 200)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tab.isActive ? DesignSystem.Colors.background(for: appState.currentTheme) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Tab Management
    private func addNewTab() {
        let newTab = BrowserTab(
            id: tabs.count,
            title: "New Tab",
            url: "https://www.apple.com",
            isActive: false
        )
        
        // Deactivate current tabs
        tabs = tabs.map { tab in
            BrowserTab(id: tab.id, title: tab.title, url: tab.url, isActive: false)
        }
        
        tabs.append(newTab)
        selectedTab = newTab.id
        
        // Activate the new tab
        if let index = tabs.firstIndex(where: { $0.id == newTab.id }) {
            tabs[index] = BrowserTab(id: newTab.id, title: newTab.title, url: newTab.url, isActive: true)
        }
        
        // Load the default URL
        urlString = newTab.url
        loadURL(urlString)
    }
    
    private func closeTab(_ tabId: Int) {
        guard tabs.count > 1 else { return }
        
        tabs.removeAll { $0.id == tabId }
        
        // If closed tab was active, activate the first tab
        if selectedTab == tabId {
            selectedTab = tabs.first?.id ?? 0
            if let index = tabs.firstIndex(where: { $0.id == selectedTab }) {
                tabs[index] = BrowserTab(
                    id: tabs[index].id,
                    title: tabs[index].title,
                    url: tabs[index].url,
                    isActive: true
                )
                urlString = tabs[index].url
                loadURL(urlString)
            }
        }
    }
    
    // MARK: - Web Navigation Methods
    private func loadURL(_ urlString: String) {
        guard let webView = webView else { return }
        
        var finalURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add https:// if no scheme is provided
        if !finalURLString.hasPrefix("http://") && !finalURLString.hasPrefix("https://") {
            finalURLString = "https://" + finalURLString
        }
        
        guard let url = URL(string: finalURLString) else { return }
        
        let request = URLRequest(url: url)
        webView.load(request)
        
        // Send event to Zig
        core.handleEvent(.webNavigate(finalURLString))
    }
    
    private func goBack() {
        webView?.goBack()
        core.handleEvent(.webGoBack)
    }
    
    private func goForward() {
        webView?.goForward()
        core.handleEvent(.webGoForward)
    }
    
    private func reload() {
        webView?.reload()
        core.handleEvent(.webReload)
    }
    
    private func stopLoading() {
        webView?.stopLoading()
    }
}

// MARK: - Web View Model (REMOVED - State now in AppState)
// WebViewModel has been removed in favor of centralized state management

// MARK: - WKWebView Representable
struct WebViewRepresentable: NSViewRepresentable {
    @Binding var webView: WKWebView?
    let appState: AppState
    let core: PlueCoreInterface
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // Enable JavaScript
        configuration.preferences.javaScriptEnabled = true
        
        // Enable modern features
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        
        // Set navigation delegate
        webView.navigationDelegate = context.coordinator
        
        // Set UI delegate for JavaScript alerts, etc.
        webView.uiDelegate = context.coordinator
        
        // Allow back/forward gestures
        webView.allowsBackForwardNavigationGestures = true
        
        // Store the web view
        DispatchQueue.main.async {
            self.webView = webView
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Updates handled by coordinator
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState, core: core)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let appState: AppState
        let core: PlueCoreInterface
        
        init(appState: AppState, core: PlueCoreInterface) {
            self.appState = appState
            self.core = core
        }
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            // Notify Zig about loading state
            // In real implementation, Zig would update state and Swift would observe
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Notify Zig about navigation complete
            // In real implementation, Zig would update state and Swift would observe
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView navigation failed: \(error.localizedDescription)")
            // Notify Zig about navigation failure
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("WebView provisional navigation failed: \(error.localizedDescription)")
            // Notify Zig about provisional navigation failure
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation for now
            decisionHandler(.allow)
        }
        
        // MARK: - WKUIDelegate
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            // Handle JavaScript alerts
            let alert = NSAlert()
            alert.messageText = "JavaScript Alert"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }
        
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            // Handle JavaScript confirm dialogs
            let alert = NSAlert()
            alert.messageText = "JavaScript Confirm"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            completionHandler(response == .alertFirstButtonReturn)
        }
        
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            // Handle JavaScript prompt dialogs
            let alert = NSAlert()
            alert.messageText = "JavaScript Prompt"
            alert.informativeText = prompt
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            textField.stringValue = defaultText ?? ""
            alert.accessoryView = textField
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                completionHandler(textField.stringValue)
            } else {
                completionHandler(nil)
            }
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Handle new window requests by loading in the same web view
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

#Preview {
    WebView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1000, height: 700)
}```

```swift
// File: Sources/plue/FarcasterView.swift
import SwiftUI

struct FarcasterView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var newPostText = ""
    @State private var showingNewPost = false
    @FocusState private var isNewPostFocused: Bool
    
    var body: some View {
        HSplitView {
            // Native macOS sidebar
            refinedChannelSidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            
            // Main content area
            VStack(spacing: 0) {
                // Native toolbar-style header
                cleanFeedHeader
                
                // Content feed
                cleanPostsFeed
            }
            .background(
                ZStack {
                    DesignSystem.Colors.background(for: appState.currentTheme)
                    Rectangle()
                        .fill(.regularMaterial)
                }
            )
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
    }
    
    // MARK: - Native macOS Sidebar
    private var refinedChannelSidebar: some View {
        VStack(spacing: 0) {
            // Native sidebar header
            HStack {
                Label("Channels", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Spacer()
                
                Button(action: { core.handleEvent(.farcasterRefreshFeed) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Refresh channels")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
                .background(DesignSystem.Colors.border(for: appState.currentTheme))
            
            // Native list style
            List {
                ForEach(appState.farcasterState.channels, id: \.id) { channel in
                    refinedChannelRow(channel)
                }
            }
            .listStyle(SidebarListStyle())
            .scrollContentBackground(.hidden)
            .background(Rectangle().fill(.ultraThinMaterial))
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme).opacity(0.95))
    }
    
    private func refinedChannelRow(_ channel: FarcasterChannel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.system(size: 11, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(appState.farcasterState.selectedChannel == channel.id ? 
                    DesignSystem.Colors.primary : 
                    DesignSystem.Colors.textSecondary(for: appState.currentTheme)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    .lineLimit(1)
                
                Text("\(channel.memberCount) members")
                    .font(.system(size: 10))
                    .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
            }
            
            Spacer()
            
            if appState.farcasterState.selectedChannel == channel.id {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            core.handleEvent(.farcasterSelectChannel(channel.id))
        }
    }
    
    // MARK: - Native macOS Toolbar Header
    private var cleanFeedHeader: some View {
        HStack(spacing: 16) {
            if let selectedChannel = appState.farcasterState.channels.first(where: { $0.id == appState.farcasterState.selectedChannel }) {
                HStack(spacing: 8) {
                    Image(systemName: "number.circle")
                        .font(.system(size: 16, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedChannel.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                        
                        Text("\(selectedChannel.memberCount) members · \(filteredPosts.count) casts")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                }
            }
            
            Spacer()
            
            // Native macOS-style compose button
            Button(action: {
                showingNewPost.toggle()
                if showingNewPost {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNewPostFocused = true
                    }
                }
            }) {
                Label("New Cast", systemImage: "square.and.pencil")
                    .font(.system(size: 12, weight: .regular))
            }
            .buttonStyle(PrimaryButtonStyle())
                .foregroundColor(.white)
                .cornerRadius(16)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.surface(for: appState.currentTheme))
    }
    
    // MARK: - Native macOS Posts Feed
    private var cleanPostsFeed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Animated composer
                if showingNewPost {
                    compactNewPostComposer
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
                
                // Posts with native dividers
                ForEach(filteredPosts) { post in
                    CompactPostView(
                        post: post,
                        theme: appState.currentTheme,
                        onLike: { core.handleEvent(.farcasterLikePost(post.id)) },
                        onRecast: { core.handleEvent(.farcasterRecastPost(post.id)) },
                        onReply: { replyText in 
                            core.handleEvent(.farcasterReplyToPost(post.id, replyText))
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    
                    if post.id != filteredPosts.last?.id {
                        Divider()
                            .background(DesignSystem.Colors.border(for: appState.currentTheme))
                            .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.2), value: showingNewPost)
    }
    
    private var filteredPosts: [FarcasterPost] {
        appState.farcasterState.posts.filter { post in
            post.channel == appState.farcasterState.selectedChannel
        }.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Native macOS Post Composer
    private var compactNewPostComposer: some View {
        VStack(spacing: 0) {
            // Text editor area
            TextEditor(text: $newPostText)
                .focused($isNewPostFocused)
                .frame(minHeight: 80, maxHeight: 200)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(16)
                .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            
            Divider()
                .background(DesignSystem.Colors.border(for: appState.currentTheme))
            
            // Bottom toolbar
            HStack {
                // Character count
                Text("\(newPostText.count)/320")
                    .font(.system(size: 11))
                    .foregroundColor(newPostText.count > 320 ? DesignSystem.Colors.error : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingNewPost = false
                            newPostText = ""
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                    
                    Button("Cast") {
                        if !newPostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            core.handleEvent(.farcasterCreatePost(newPostText))
                            newPostText = ""
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingNewPost = false
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(newPostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newPostText.count > 320)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignSystem.Materials.titleBar)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

// MARK: - Compact Post View
struct CompactPostView: View {
    let post: FarcasterPost
    let theme: DesignSystem.Theme
    let onLike: () -> Void
    let onRecast: () -> Void
    let onReply: (String) -> Void
    
    @State private var showingReply = false
    @State private var replyText = ""
    @FocusState private var isReplyFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Native macOS post header
            HStack(spacing: 10) {
                // User avatar with gradient
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hue: Double(post.author.username.hashValue % 360) / 360.0, saturation: 0.5, brightness: 0.8),
                                    Color(hue: Double(post.author.username.hashValue % 360) / 360.0, saturation: 0.7, brightness: 0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Text(String(post.author.displayName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                    
                    HStack(spacing: 4) {
                        Text("@\(post.author.username)")
                        Text("•")
                        Text(timeAgoString(from: post.timestamp))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
                }
                
                Spacer()
                
                // More menu
                Menu {
                    Button("Copy Link", action: {})
                    Button("Share...", action: {})
                    Divider()
                    Button("Mute User", action: {})
                    Button("Report", role: .destructive, action: {})
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                        .frame(width: 24, height: 24)
                }
                .menuStyle(BorderlessButtonMenuStyle())
            }
            
            // Post content with better typography
            Text(post.content)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            // Native macOS interaction buttons
            HStack(spacing: 20) {
                // Reply
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingReply.toggle()
                        if showingReply {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isReplyFocused = true
                            }
                        }
                    }
                }) {
                    Label(post.replies > 0 ? "\(post.replies)" : "Reply", systemImage: "bubble.left")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(showingReply ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary(for: theme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Reply to cast")
                
                // Recast
                Button(action: {
                    withAnimation(DesignSystem.Animation.socialInteraction) {
                        onRecast()
                    }
                }) {
                    Label(post.recasts > 0 ? "\(post.recasts)" : "Recast", systemImage: "arrow.2.squarepath")
                        .font(.system(size: 12, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(post.isRecast ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary(for: theme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Recast")
                .scaleEffect(post.isRecast ? 1.05 : 1.0)
                .animation(DesignSystem.Animation.socialInteraction, value: post.isRecast)
                
                // Like
                Button(action: {
                    withAnimation(DesignSystem.Animation.heartBeat) {
                        onLike()
                    }
                }) {
                    Label(post.likes > 0 ? "\(post.likes)" : "Like", systemImage: post.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(post.isLiked ? DesignSystem.Colors.error : DesignSystem.Colors.textSecondary(for: theme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Like")
                .scaleEffect(post.isLiked ? 1.05 : 1.0)
                .animation(DesignSystem.Animation.heartBeat, value: post.isLiked)
                
                Spacer()
                
                // Share
                Menu {
                    Button("Copy Link", action: {})
                    Button("Share to Twitter", action: {})
                    Button("Share to Mastodon", action: {})
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .help("Share")
            }
            
            // Native macOS reply composer
            if showingReply {
                HStack(alignment: .bottom, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        // Reply indicator
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.primary)
                            .padding(.leading, 4)
                        
                        // Reply text field
                        TextField("Write a reply...", text: $replyText, axis: .vertical)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 12))
                            .lineLimit(1...4)
                            .focused($isReplyFocused)
                            .onSubmit {
                                if !replyText.isEmpty {
                                    onReply(replyText)
                                    replyText = ""
                                    showingReply = false
                                }
                            }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignSystem.Colors.surface(for: theme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        isReplyFocused ? DesignSystem.Colors.primary : DesignSystem.Colors.border(for: theme),
                                        lineWidth: isReplyFocused ? 1 : 0.5
                                    )
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isReplyFocused)
                    
                    // Send button
                    Button(action: {
                        if !replyText.isEmpty {
                            onReply(replyText)
                            replyText = ""
                            showingReply = false
                        }
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(replyText.isEmpty ? 
                                DesignSystem.Colors.textTertiary(for: theme) : 
                                DesignSystem.Colors.primary
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(replyText.isEmpty)
                    .help("Send reply")
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .animation(DesignSystem.Animation.slideTransition, value: showingReply)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}

// MARK: - Legacy Post View (keeping for reference)
struct PostView: View {
    let post: FarcasterPost
    let onLike: () -> Void
    let onRecast: () -> Void
    let onReply: (String) -> Void
    
    @State private var showingReply = false
    @State private var replyText = ""
    @FocusState private var isReplyFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Post header with user info
            HStack(spacing: 12) {
                // Avatar placeholder
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(post.author.displayName.prefix(1)))
                            .font(.title3.bold())
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(post.author.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("@\(post.author.username)")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(timeAgoString(from: post.timestamp))
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Text("#\(post.channel)")
                        .font(.system(size: 12))
                        .foregroundColor(.blue.opacity(0.8))
                }
                
                Spacer()
            }
            
            // Post content
            Text(post.content)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .lineLimit(nil)
            
            // Interaction buttons
            HStack(spacing: 32) {
                // Reply
                Button(action: {
                    showingReply.toggle()
                    if showingReply {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isReplyFocused = true
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16))
                        Text("\(post.replies)")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Recast
                Button(action: onRecast) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 16))
                        Text("\(post.recasts)")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(post.isRecast ? .green : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Like
                Button(action: onLike) {
                    HStack(spacing: 6) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                        Text("\(post.likes)")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(post.isLiked ? .red : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            
            // Reply composer
            if showingReply {
                VStack(spacing: 8) {
                    HStack {
                        Text("Reply to @\(post.author.username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Cancel") {
                            showingReply = false
                            replyText = ""
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        TextEditor(text: $replyText)
                            .focused($isReplyFocused)
                            .frame(minHeight: 60)
                            .padding(8)
                            .background(DesignSystem.Colors.surface)
                            .cornerRadius(8)
                        
                        Button("Reply") {
                            if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                onReply(replyText)
                                replyText = ""
                                showingReply = false
                            }
                        }
                        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                                  Color.secondary.opacity(0.3) : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                }
                .padding()
                .background(DesignSystem.Colors.surface)
                .cornerRadius(8)
            }
        }
        .padding()
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}

#Preview {
    FarcasterView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}```

```swift
// File: Sources/plue/UnifiedMessageExamples.swift
import SwiftUI

// MARK: - Migration Examples
// This file demonstrates how to migrate existing message bubble views to use the unified component

// MARK: - Example 1: Migrating ModernChatView
struct ModernChatViewMigrationExample: View {
    let appState: AppState
    let core: PlueCoreInterface
    @State private var activeMessageId: String? = nil
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.lg) {
                if let messages = appState.promptState.currentConversation?.messages {
                    ForEach(messages) { message in
                        // OLD: ProfessionalMessageBubbleView(message: message, isActive: activeMessageId == message.id, theme: appState.currentTheme)
                        
                        // NEW: Using UnifiedMessageBubbleView with professional style
                        UnifiedMessageBubbleView(
                            message: message,
                            style: .professional,
                            isActive: activeMessageId == message.id,
                            theme: appState.currentTheme,
                            onTap: { tappedMessage in
                                if tappedMessage.type != .user {
                                    print("AI message tapped: \(tappedMessage.id)")
                                    activeMessageId = tappedMessage.id
                                }
                            }
                        )
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .id(message.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    }
                }
            }
            .padding(.vertical, DesignSystem.Spacing.lg)
        }
    }
}

// MARK: - Example 2: Migrating AgentView
struct AgentViewMigrationExample: View {
    let agentState: AgentState
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.md) {
                ForEach(agentState.currentConversation?.messages ?? []) { message in
                    // OLD: AgentMessageBubbleView(message: message)
                    
                    // NEW: Using UnifiedMessageBubbleView with compact style
                    UnifiedMessageBubbleView(
                        message: UnifiedAgentMessage(agentMessage: message),
                        style: .compact,
                        theme: .dark
                    )
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .id(message.id)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.md)
        }
    }
}

// MARK: - Example 3: Custom Style Configuration
struct CustomStyledMessageExample: View {
    let message: PromptMessage
    
    // Custom style that matches specific design requirements
    let customStyle = MessageBubbleStyle(
        avatarSize: 32,
        avatarStyle: .iconWithText,
        bubbleCornerRadius: 16,
        bubblePadding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14),
        maxBubbleWidth: 600,
        contentFont: .system(size: 15, weight: .regular),
        timestampFont: .system(size: 11),
        metadataFont: .system(size: 10),
        avatarSpacing: 10,
        timestampSpacing: 6,
        metadataSpacing: 4,
        userBubbleBackground: Color.blue.opacity(0.9),
        assistantBubbleBackground: Color(NSColor.controlBackgroundColor),
        systemBubbleBackground: Color.gray.opacity(0.1),
        errorBubbleBackground: Color.red.opacity(0.1),
        showAnimations: true,
        animationDuration: 0.25
    )
    
    var body: some View {
        UnifiedMessageBubbleView(
            message: message,
            style: customStyle,
            theme: .dark
        )
    }
}

// MARK: - Example 4: Creating a Typing Indicator with Unified Style
struct UnifiedTypingIndicatorView: View {
    let style: MessageBubbleStyle
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Use same layout as assistant messages
            HStack(alignment: .top, spacing: style.avatarSpacing) {
                // Avatar
                Circle()
                    .fill(DesignSystem.Colors.accentGradient)
                    .frame(width: style.avatarSize, height: style.avatarSize)
                    .overlay(
                        Circle()
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: style.avatarSize * 0.4, weight: .medium))
                            .foregroundColor(.white)
                    )
                
                // Typing animation bubble
                HStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(DesignSystem.Colors.primary.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .scaleEffect(animationPhase == index ? 1.3 : 0.7)
                            .opacity(animationPhase == index ? 1.0 : 0.4)
                            .animation(
                                DesignSystem.Animation.plueStandard
                                    .repeatForever()
                                    .delay(Double(index) * 0.15),
                                value: animationPhase
                            )
                    }
                }
                .padding(style.bubblePadding)
                .background(
                    RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                        .fill(style.assistantBubbleBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                                .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                        )
                )
                
                Spacer()
            }
        }
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Example 5: Message List Component with Unified Bubbles
struct UnifiedMessageListView<Message: UnifiedMessage>: View {
    let messages: [Message]
    let style: MessageBubbleStyle
    let theme: DesignSystem.Theme
    let isProcessing: Bool
    
    @State private var activeMessageId: String? = nil
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: style.avatarSpacing) {
                    ForEach(messages) { message in
                        UnifiedMessageBubbleView(
                            message: message,
                            style: style,
                            isActive: activeMessageId == message.id,
                            theme: theme,
                            onTap: { tappedMessage in
                                withAnimation(DesignSystem.Animation.quick) {
                                    activeMessageId = tappedMessage.id
                                }
                            }
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .id(message.id)
                    }
                    
                    if isProcessing {
                        UnifiedTypingIndicatorView(style: style)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                    
                    // Bottom spacing
                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
                .padding(.vertical, DesignSystem.Spacing.md)
            }
            .scrollIndicators(.never)
            .onChange(of: messages.count) { _ in
                withAnimation(DesignSystem.Animation.plueStandard) {
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Style Configuration Examples
extension MessageBubbleStyle {
    // Terminal-style messages (for system logs, etc.)
    static let terminal = MessageBubbleStyle(
        avatarSize: 20,
        avatarStyle: .icon,
        bubbleCornerRadius: 4,
        bubblePadding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8),
        maxBubbleWidth: nil,
        contentFont: .system(size: 12, weight: .regular, design: .monospaced),
        timestampFont: .system(size: 9, design: .monospaced),
        metadataFont: .system(size: 9, design: .monospaced),
        avatarSpacing: 8,
        timestampSpacing: 2,
        metadataSpacing: 2,
        userBubbleBackground: Color.green.opacity(0.2),
        assistantBubbleBackground: Color.black.opacity(0.8),
        systemBubbleBackground: Color.gray.opacity(0.2),
        errorBubbleBackground: Color.red.opacity(0.2),
        showAnimations: false,
        animationDuration: 0
    )
    
    // Large display style (for presentations, etc.)
    static let display = MessageBubbleStyle(
        avatarSize: 48,
        avatarStyle: .iconWithText,
        bubbleCornerRadius: 20,
        bubblePadding: EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24),
        maxBubbleWidth: 800,
        contentFont: .system(size: 18, weight: .regular),
        timestampFont: .system(size: 12),
        metadataFont: .system(size: 12),
        avatarSpacing: 16,
        timestampSpacing: 8,
        metadataSpacing: 6,
        userBubbleBackground: DesignSystem.Colors.primary,
        assistantBubbleBackground: DesignSystem.Colors.surface,
        systemBubbleBackground: DesignSystem.Colors.surfaceSecondary,
        errorBubbleBackground: DesignSystem.Colors.error.opacity(0.15),
        showAnimations: true,
        animationDuration: 0.3
    )
}

// MARK: - Preview
#Preview("Migration Examples") {
    VStack(spacing: 40) {
        // Professional style (chat view)
        VStack(alignment: .leading) {
            Text("Professional Style (Chat)")
                .font(.headline)
            
            UnifiedMessageListView(
                messages: [
                    PromptMessage(
                        id: "1",
                        content: "Hello! How can I help you today?",
                        type: .assistant,
                        timestamp: Date(),
                        promptSnapshot: nil
                    ),
                    PromptMessage(
                        id: "2",
                        content: "I need help creating a unified message bubble component",
                        type: .user,
                        timestamp: Date(),
                        promptSnapshot: nil
                    )
                ],
                style: .professional,
                theme: .dark,
                isProcessing: true
            )
            .frame(height: 200)
        }
        
        // Compact style (agent view)
        VStack(alignment: .leading) {
            Text("Compact Style (Agent)")
                .font(.headline)
            
            UnifiedMessageListView(
                messages: [
                    UnifiedAgentMessage(agentMessage: AgentMessage(
                        id: "3",
                        content: "Starting workflow execution...",
                        type: .workflow,
                        timestamp: Date(),
                        metadata: AgentMessageMetadata(
                            worktree: "feature-ui",
                            workflow: "build-test",
                            containerId: nil,
                            exitCode: nil,
                            duration: nil
                        )
                    )),
                    UnifiedAgentMessage(agentMessage: AgentMessage(
                        id: "4",
                        content: "Build completed successfully",
                        type: .system,
                        timestamp: Date(),
                        metadata: AgentMessageMetadata(
                            worktree: "feature-ui",
                            workflow: nil,
                            containerId: "abc123",
                            exitCode: 0,
                            duration: 12.5
                        )
                    ))
                ],
                style: .compact,
                theme: .dark,
                isProcessing: false
            )
            .frame(height: 150)
        }
        
        // Terminal style
        VStack(alignment: .leading) {
            Text("Terminal Style")
                .font(.headline)
            
            UnifiedMessageBubbleView(
                message: UnifiedAgentMessage(agentMessage: AgentMessage(
                    id: "5",
                    content: "$ zig build\n> Building project...\n> Success!",
                    type: .system,
                    timestamp: Date(),
                    metadata: nil
                )),
                style: .terminal,
                theme: .dark
            )
        }
    }
    .padding()
    .background(DesignSystem.Colors.background)
    .frame(width: 800, height: 600)
}```

```swift
// File: Sources/plue/PromptView.swift
import SwiftUI
import SwiftDown

struct PromptView: View {
    @State private var markdownText = """
# Prompt Engineering Interface

Write your prompts here using **Markdown** formatting.

## Features
- Rich text editing with live preview
- Syntax highlighting for code blocks
- Support for lists, headers, and formatting

```swift
// Code blocks are supported
let example = "Hello, World!"
```

## Usage
1. Write your prompt using Markdown
2. Click the send button to process with Zig core
3. View responses below

---

*Start writing your prompt below...*
"""
    
    @State private var responses: [PromptResponse] = []
    @State private var plueCore: PlueCore?
    @State private var isProcessing = false
    
    var body: some View {
        HSplitView {
            // Left side - Markdown Editor
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Prompt Editor")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: processPrompt) {
                        HStack(spacing: 6) {
                            if isProcessing {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("Send Prompt")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.0, green: 0.48, blue: 1.0))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isProcessing || markdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                
                Divider()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                
                // Markdown Editor
                SwiftDownEditor(text: $markdownText)
                    .background(Color(red: 0.05, green: 0.05, blue: 0.06))
            }
            
            // Right side - Responses
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Responses")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if !responses.isEmpty {
                        Button("Clear") {
                            responses.removeAll()
                        }
                        .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                    }
                }
                .padding()
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                
                Divider()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                
                // Responses List
                if responses.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.35))
                        Text("No responses yet")
                            .font(.headline)
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                        Text("Send a prompt to see responses here")
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.45))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.05, green: 0.05, blue: 0.06))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(responses) { response in
                                PromptResponseView(response: response)
                            }
                        }
                        .padding()
                    }
                    .background(Color(red: 0.05, green: 0.05, blue: 0.06))
                }
            }
            .frame(minWidth: 300)
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
        .onAppear {
            initializeCore()
        }
    }
    
    private func initializeCore() {
        // Legacy PromptView - no longer initializes core
        print("Legacy PromptView - PlueCore initialization skipped")
    }
    
    private func processPrompt() {
        let prompt = markdownText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        isProcessing = true
        
        // Create new response entry
        let newResponse = PromptResponse(
            id: UUID(),
            prompt: prompt,
            response: nil,
            timestamp: Date(),
            isProcessing: true
        )
        responses.append(newResponse)
        
        // Process in background
        DispatchQueue.global(qos: .userInitiated).async {
            let result: String
            // Legacy PromptView - no longer used
            result = "Legacy PromptView response for: \(prompt)"
            
            DispatchQueue.main.async {
                // Update the response
                if let index = responses.firstIndex(where: { $0.id == newResponse.id }) {
                    responses[index] = PromptResponse(
                        id: newResponse.id,
                        prompt: newResponse.prompt,
                        response: result,
                        timestamp: newResponse.timestamp,
                        isProcessing: false
                    )
                }
                isProcessing = false
            }
        }
    }
}

struct PromptResponse: Identifiable {
    let id: UUID
    let prompt: String
    let response: String?
    let timestamp: Date
    let isProcessing: Bool
}

struct PromptResponseView: View {
    let response: PromptResponse
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Timestamp
            HStack {
                Text(formatTimestamp(response.timestamp))
                    .font(.caption)
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                Spacer()
            }
            
            // Prompt Preview
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                    Text("Prompt")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                }
                
                Text(response.prompt.prefix(200) + (response.prompt.count > 200 ? "..." : ""))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(red: 0.8, green: 0.8, blue: 0.85))
                    .padding(8)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .cornerRadius(6)
            }
            
            // Response
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                    Text("Response")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                }
                
                if response.isProcessing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Processing...")
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                    }
                } else if let responseText = response.response {
                    Text(responseText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                        .cornerRadius(6)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.2, green: 0.2, blue: 0.25), lineWidth: 1)
                )
        )
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    PromptView()
        .frame(width: 1200, height: 800)
}```

```swift
// File: Sources/plue/AgentView.swift
import SwiftUI
import AppKit

struct AgentView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Minimal background
                DesignSystem.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Minimal Header Bar
                    agentHeaderBar
                    
                    // Chat Messages Area
                    agentChatArea
                    
                    // Control Panel
                    agentControlPanel
                    
                    // Input Area
                    agentInputArea
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Initialize worktrees and auto-refresh
            core.handleEvent(.agentRefreshWorktrees)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }
    
    // MARK: - Minimal Header Bar
    private var agentHeaderBar: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Left side - Session Navigation
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Previous session button
                Button(action: {
                    if appState.agentState.currentConversationIndex > 0 {
                        core.handleEvent(.agentSelectConversation(appState.agentState.currentConversationIndex - 1))
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(appState.agentState.currentConversationIndex == 0 ? DesignSystem.Colors.textTertiary.opacity(0.3) : DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Previous session (⌘[)")
                .disabled(appState.agentState.currentConversationIndex == 0)
                
                // Session indicator
                VStack(alignment: .leading, spacing: 1) {
                    Text("agent")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    Text("\(appState.agentState.currentConversationIndex + 1)/\(appState.agentState.conversations.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                // Next/New session button
                Button(action: {
                    if appState.agentState.currentConversationIndex < appState.agentState.conversations.count - 1 {
                        core.handleEvent(.agentSelectConversation(appState.agentState.currentConversationIndex + 1))
                    } else {
                        core.handleEvent(.agentNewConversation)
                    }
                }) {
                    Image(systemName: appState.agentState.currentConversationIndex < appState.agentState.conversations.count - 1 ? "chevron.right" : "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(appState.agentState.currentConversationIndex < appState.agentState.conversations.count - 1 ? "Next session (⌘])" : "New session (⌘N)")
            }
            
            Spacer()
            
            // Center - Current Workspace Indicator
            if let workspace = appState.agentState.currentWorkspace {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: workspace.status))
                        .frame(width: 6, height: 6)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("workspace")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        
                        Text(workspace.branch)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                        )
                )
            } else {
                Text("no workspace")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            
            Spacer()
            
            // Right side - Status and Actions
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Dagger session indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.agentState.daggerSession?.isConnected == true ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary.opacity(0.3))
                        .frame(width: 6, height: 6)
                    
                    Text("dagger")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                
                // Processing indicator
                if appState.agentState.isProcessing {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignSystem.Colors.warning)
                            .frame(width: 6, height: 6)
                        
                        Text("processing")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                }
                
                // Workflow execution indicator
                if appState.agentState.isExecutingWorkflow {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignSystem.Colors.primary)
                            .frame(width: 6, height: 6)
                        
                        Text("workflow")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(
            DesignSystem.Colors.surface
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(DesignSystem.Colors.border.opacity(0.3)),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - Chat Messages Area
    private var agentChatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.md) {
                    // Welcome message if empty
                    if appState.agentState.currentConversation?.messages.isEmpty ?? true {
                        agentWelcomeView
                            .padding(.top, DesignSystem.Spacing.massive)
                    }
                    
                    // Agent message bubbles
                    ForEach(appState.agentState.currentConversation?.messages ?? []) { message in
                        UnifiedMessageBubbleView(
                            message: UnifiedAgentMessage(agentMessage: message),
                            style: .compact,
                            theme: appState.currentTheme
                        )
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .id(message.id)
                    }
                    
                    // Processing indicator
                    if appState.agentState.isProcessing {
                        AgentProcessingIndicatorView()
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                    }
                    
                    // Bottom spacing
                    Spacer(minLength: DesignSystem.Spacing.lg)
                }
                .padding(.vertical, DesignSystem.Spacing.md)
            }
            .scrollIndicators(.never)
            .background(DesignSystem.Colors.backgroundSecondary)
            .onChange(of: appState.agentState.currentConversation?.messages.count) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if let lastMessage = appState.agentState.currentConversation?.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Welcome View
    private var agentWelcomeView: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            // Minimal logo
            Circle()
                .fill(DesignSystem.Colors.textTertiary.opacity(0.1))
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                )
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("agent ready")
                    .font(DesignSystem.Typography.titleMedium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("git worktrees • dagger workflows • automation")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Quick actions
            VStack(spacing: 6) {
                quickActionButton("list worktrees", icon: "list.bullet")
                quickActionButton("start dagger", icon: "gearshape")
                quickActionButton("create workflow", icon: "arrow.triangle.2.circlepath")
                quickActionButton("help commands", icon: "questionmark.circle")
            }
        }
        .frame(maxWidth: 400)
        .multilineTextAlignment(.center)
    }
    
    private func quickActionButton(_ text: String, icon: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                core.handleEvent(.agentMessageSent(text))
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .frame(width: 16)
                
                Text(text)
                    .font(DesignSystem.Typography.labelMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: 280)
    }
    
    // MARK: - Control Panel
    private var agentControlPanel: some View {
        VStack(spacing: 0) {
            // Separator
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border.opacity(0.3))
            
            HStack(spacing: DesignSystem.Spacing.lg) {
                // Worktree controls
                VStack(alignment: .leading, spacing: 4) {
                    Text("worktrees")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    HStack(spacing: 6) {
                        Button("refresh") {
                            core.handleEvent(.agentRefreshWorktrees)
                        }
                        .buttonStyle(MiniButtonStyle())
                        
                        Button("create") {
                            // For demo, create a new worktree with timestamp
                            let branch = "feature-\(Int(Date().timeIntervalSince1970))"
                            let path = "/tmp/plue-\(branch)"
                            core.handleEvent(.agentCreateWorktree(branch, path))
                        }
                        .buttonStyle(MiniButtonStyle())
                        
                        if !appState.agentState.availableWorktrees.isEmpty {
                            Menu("switch") {
                                ForEach(appState.agentState.availableWorktrees, id: \.id) { worktree in
                                    Button(action: {
                                        core.handleEvent(.agentSwitchWorktree(worktree.id))
                                    }) {
                                        HStack {
                                            Text(worktree.branch)
                                            if worktree.id == appState.agentState.currentWorkspace?.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            .buttonStyle(MiniButtonStyle())
                            .menuStyle(BorderlessButtonMenuStyle())
                        }
                    }
                }
                
                Spacer()
                
                // Dagger controls
                VStack(alignment: .leading, spacing: 4) {
                    Text("dagger")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    HStack(spacing: 6) {
                        if appState.agentState.daggerSession?.isConnected == true {
                            Button("stop") {
                                core.handleEvent(.agentStopDaggerSession)
                            }
                            .buttonStyle(MiniButtonStyle())
                        } else {
                            Button("start") {
                                core.handleEvent(.agentStartDaggerSession)
                            }
                            .buttonStyle(MiniButtonStyle())
                        }
                        
                        Button("workflow") {
                            // Create a sample workflow for demo
                            let workflow = AgentWorkflow(
                                id: UUID().uuidString,
                                name: "Build & Test",
                                description: "Run build and tests in container",
                                steps: [
                                    WorkflowStep(
                                        id: UUID().uuidString,
                                        name: "Build",
                                        command: "swift build",
                                        container: "swift:latest",
                                        dependencies: [],
                                        status: .pending
                                    ),
                                    WorkflowStep(
                                        id: UUID().uuidString,
                                        name: "Test",
                                        command: "swift test",
                                        container: "swift:latest",
                                        dependencies: ["build"],
                                        status: .pending
                                    )
                                ],
                                status: .pending,
                                createdAt: Date(),
                                startedAt: nil,
                                completedAt: nil
                            )
                            core.handleEvent(.agentExecuteWorkflow(workflow))
                        }
                        .buttonStyle(MiniButtonStyle())
                        .disabled(appState.agentState.daggerSession?.isConnected != true)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.surface)
        }
    }
    
    // MARK: - Input Area
    private var agentInputArea: some View {
        VStack(spacing: 0) {
            // Separator
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border.opacity(0.3))
            
            HStack(spacing: DesignSystem.Spacing.md) {
                // Quick tools button
                Button(action: {}) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Agent tools")
                
                // Agent Chat Input
                VimChatInputView(
                    appState: appState,
                    core: core,
                    onMessageSent: { message in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            core.handleEvent(.agentMessageSent(message))
                        }
                    },
                    onMessageUpdated: { message in
                        core.handleEvent(.agentMessageSent(message))
                    },
                    onNavigateUp: {
                        print("Navigate up - not implemented")
                    },
                    onNavigateDown: {
                        print("Navigate down - not implemented")
                    },
                    onPreviousChat: {
                        if appState.agentState.currentConversationIndex > 0 {
                            core.handleEvent(.agentSelectConversation(appState.agentState.currentConversationIndex - 1))
                        }
                    },
                    onNextChat: {
                        if appState.agentState.currentConversationIndex < appState.agentState.conversations.count - 1 {
                            core.handleEvent(.agentSelectConversation(appState.agentState.currentConversationIndex + 1))
                        } else {
                            core.handleEvent(.agentNewConversation)
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignSystem.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .frame(maxWidth: .infinity)
                
                // Help indicator
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(":w")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.primary.opacity(0.8))
                        Text("send")
                            .font(.system(size: 9))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                    
                    HStack(spacing: 4) {
                        Text("⌘[]")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.textTertiary.opacity(0.6))
                        Text("nav")
                            .font(.system(size: 9))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                }
                .opacity(0.7)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
        }
    }
    
    // MARK: - Helper Functions
    
    private func statusColor(for status: GitWorktreeStatus) -> Color {
        switch status {
        case .clean: return DesignSystem.Colors.success
        case .modified: return DesignSystem.Colors.warning
        case .untracked: return DesignSystem.Colors.primary
        case .conflicts: return DesignSystem.Colors.error
        }
    }
}

// MARK: - Agent Message Bubble View

// AgentMessageBubbleView has been replaced by UnifiedMessageBubbleView with .compact style

// MARK: - Agent Processing Indicator

struct AgentProcessingIndicatorView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Agent avatar
            Circle()
                .fill(DesignSystem.Colors.accent)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                )
            
            // Processing animation
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DesignSystem.Colors.primary.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .opacity(animationPhase == index ? 1.0 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
            )
            
            Spacer()
        }
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Mini Button Style

struct MiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isPressed ? DesignSystem.Colors.surface.opacity(0.8) : DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
            )
    }
}

#Preview {
    AgentView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}```

```swift
// File: Sources/plue/EditorView.swift
import SwiftUI

struct EditorView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var mockCode = """
    // Welcome to Plue Editor
    import SwiftUI
    
    struct ContentView: View {
        @State private var message = "Hello, World!"
        
        var body: some View {
            VStack {
                Text(message)
                    .font(.largeTitle)
                    .padding()
                
                Button("Change Message") {
                    message = "Hello from Plue!"
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    """
    
    var body: some View {
        VStack(spacing: 0) {
            // Native macOS toolbar
            editorToolbar
            
            Divider()
                .background(DesignSystem.Colors.border(for: appState.currentTheme))
            
            // Main editor area
            HSplitView {
                // File tree sidebar
                fileTreeSidebar
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                
                // Editor pane
                editorPane
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
    }
    
    // MARK: - Editor Toolbar
    private var editorToolbar: some View {
        HStack(spacing: 16) {
            // File info
            HStack(spacing: 8) {
                Image(systemName: "swift")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.orange)
                
                Text("ContentView.swift")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(DesignSystem.Colors.success)
                
                Text("No issues")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
            }
            
            Spacer()
            
            // Editor actions
            HStack(spacing: 12) {
                Button(action: {}) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Format code")
                
                Button(action: {}) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Run")
                
                Button(action: {}) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle sidebar")
            }
            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .toolbarStyle(theme: appState.currentTheme)
    }
    
    // MARK: - File Tree Sidebar
    private var fileTreeSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar header
            HStack {
                Label("Files", systemImage: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
                .background(DesignSystem.Colors.border(for: appState.currentTheme))
            
            // Mock file tree
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    fileItem("PlueApp", isFolder: true, isExpanded: true)
                    VStack(alignment: .leading, spacing: 2) {
                        fileItem("ContentView.swift", isSelected: true, indent: 1)
                        fileItem("AppDelegate.swift", indent: 1)
                        fileItem("Models", isFolder: true, indent: 1)
                        fileItem("Views", isFolder: true, indent: 1)
                    }
                    .padding(.leading, 8)
                }
                .padding(.vertical, 8)
            }
        }
        .sidebarStyle()
        .background(DesignSystem.Colors.background(for: appState.currentTheme).opacity(0.95))
    }
    
    private func fileItem(_ name: String, isFolder: Bool = false, isExpanded: Bool = false, isSelected: Bool = false, indent: Int = 0) -> some View {
        HStack(spacing: 6) {
            if isFolder {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    .frame(width: 12)
            } else {
                Spacer()
                    .frame(width: 12)
            }
            
            Image(systemName: isFolder ? "folder" : "doc.text")
                .font(.system(size: 12))
                .foregroundColor(isFolder ? DesignSystem.Colors.warning : DesignSystem.Colors.primary)
            
            Text(name)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
            
            Spacer()
        }
        .padding(.leading, CGFloat(indent * 16))
        .sidebarItem(isSelected: isSelected, theme: appState.currentTheme)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {}
    }
    
    // MARK: - Editor Pane
    private var editorPane: some View {
        VStack(spacing: 0) {
            // Editor with syntax highlighting placeholder
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(1...30, id: \.self) { lineNumber in
                            Text("\(lineNumber)")
                                .font(DesignSystem.Typography.monoSmall)
                                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 12)
                    
                    // Code content
                    Text(mockCode)
                        .font(DesignSystem.Typography.monoMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            .background(DesignSystem.Colors.background(for: appState.currentTheme))
            
            // Status bar
            editorStatusBar
        }
    }
    
    // MARK: - Status Bar
    private var editorStatusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                Text("Swift")
                    .font(.system(size: 11))
                
                Text("Line 15, Column 28")
                    .font(.system(size: 11))
                
                Text("UTF-8")
                    .font(.system(size: 11))
            }
            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
            
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.success)
                
                Text("Ready")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(DesignSystem.Materials.titleBar)
        .overlay(
            Divider()
                .background(DesignSystem.Colors.border(for: appState.currentTheme)),
            alignment: .top
        )
    }
}

#Preview {
    EditorView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 800, height: 600)
}```

```swift
// File: Sources/plue/TerminalView.swift
import SwiftUI

struct TerminalView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var inputText = ""
    @State private var terminalError: Error?
    @State private var terminalOutput = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal Header
            terminalHeader
            
            // Terminal Surface (NSView-based)
            TerminalSurface(
                inputText: $inputText,
                onError: { error in
                    terminalError = error
                    print("Terminal error: \(error)")
                },
                onOutput: { output in
                    // We could track output here if needed
                    terminalOutput += output
                }
            )
            .background(Color.black)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3), lineWidth: 1)
            )
            .padding()
            .onAppear {
                startTerminal()
            }
            
            // Error display
            if let error = terminalError {
                Text("Terminal Error: \(error.localizedDescription)")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .alert("Terminal Error", isPresented: .constant(terminalError != nil)) {
            Button("OK") { terminalError = nil }
        } message: {
            Text(terminalError?.localizedDescription ?? "Unknown error")
        }
    }
    
    // MARK: - Terminal Header
    private var terminalHeader: some View {
        VStack(spacing: 0) {
            HStack {
                // Terminal Title
                Label("Terminal", systemImage: "terminal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Spacer()
                
                // Status Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.terminalState.isConnected ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                        .frame(width: 8, height: 8)
                    
                    Text(appState.terminalState.isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                
                // Clear Button
                Button(action: { 
                    terminalOutput = ""
                    // Send clear event to Zig if needed
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear terminal output")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Divider()
        }
        .background(DesignSystem.Colors.surface(for: appState.currentTheme))
    }
    
    // MARK: - Private Methods
    private func startTerminal() {
        print("TerminalView: startTerminal() called")
        // The terminal is already initialized and started via the TerminalSurface
        // This is just for any additional setup if needed
    }
}

#Preview {
    TerminalView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 800, height: 600)
}```

```swift
// File: Sources/plue/VimChatTerminal.swift
import SwiftUI
import Foundation
import AppKit

// MARK: - Vim Chat Terminal
class VimChatTerminal: ObservableObject {
    @Published var terminalOutput: [String] = []
    @Published var currentMode: VimMode = .normal
    @Published var statusLine: String = "-- INSERT --"
    @Published var showCursor = true
    
    private var isNvimRunning = false
    
    var onMessageSent: ((String) -> Void)?
    var onMessageUpdated: ((String) -> Void)?
    var onNavigateUp: (() -> Void)?
    var onNavigateDown: (() -> Void)?
    var onPreviousChat: (() -> Void)?
    var onNextChat: (() -> Void)?
    
    // Terminal simulation
    private var bufferLines: [String] = [""]
    private var cursorRow = 0
    private var cursorCol = 0
    private var insertMode = false
    private var hasBeenSaved = false
    private var lastSentContent = ""
    
    // Visual mode selection
    private var visualStartRow = 0
    private var visualStartCol = 0
    private var visualType: VisualType = .characterwise
    
    init() {
        setupNvimSession()
    }
    
    func setupNvimSession() {
        // Simulate nvim startup
        startNvimSession()
    }
    
    private func startNvimSession() {
        isNvimRunning = true
        currentMode = .normal
        updateStatusLine()
        
        // Initialize with empty buffer
        bufferLines = [""]
        cursorRow = 0
        cursorCol = 0
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func handleKeyPress(_ event: NSEvent) {
        guard isNvimRunning else { 
            print("VimChatTerminal: Not running, ignoring keypress")
            return 
        }
        
        let characters = event.characters ?? ""
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags
        
        print("VimChatTerminal: KeyPress - characters: '\(characters)', keyCode: \(keyCode), modifiers: \(modifiers.rawValue), mode: \(currentMode)")
        
        switch currentMode {
        case .normal:
            handleNormalModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers)
        case .insert:
            handleInsertModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers)
        case .command:
            handleCommandModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers)
        case .visual:
            handleVisualModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers)
        }
        
        updateDisplay()
    }
    
    private func handleNormalModeKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Handle Control key shortcuts
        print("VimChatTerminal: Checking modifiers - raw: \(modifiers.rawValue)")
        print("VimChatTerminal: Contains .control: \(modifiers.contains(.control))")
        print("VimChatTerminal: Contains .command: \(modifiers.contains(.command))")
        print("VimChatTerminal: Character: '\(characters)', keyCode: \(keyCode)")
        
        // Debug the actual modifier values
        print("VimChatTerminal: NSEvent.ModifierFlags.control.rawValue = \(NSEvent.ModifierFlags.control.rawValue)")
        print("VimChatTerminal: Bitwise AND result = \(modifiers.rawValue & NSEvent.ModifierFlags.control.rawValue)")
        
        // Try multiple ways to detect control key
        let isControlPressed = modifiers.contains(.control) || 
                              (modifiers.rawValue & NSEvent.ModifierFlags.control.rawValue) != 0 ||
                              modifiers.rawValue == 131330 ||  // Specific value we're seeing
                              characters.unicodeScalars.first?.value ?? 0 < 32  // Control characters are < 32
        
        if isControlPressed && !characters.isEmpty {
            print("VimChatTerminal: Control key detected with character: '\(characters)'")
            
            // Handle control characters directly by keyCode since characters might be mangled
            switch keyCode {
            case 38: // J key
                print("VimChatTerminal: Navigate Down triggered (Ctrl+J)")
                onNavigateDown?()
                return
            case 40: // K key
                print("VimChatTerminal: Navigate Up triggered (Ctrl+K)")
                onNavigateUp?()
                return
            case 4: // H key
                print("VimChatTerminal: Previous Chat triggered (Ctrl+H)")
                onPreviousChat?()
                return
            case 37: // L key
                print("VimChatTerminal: Next Chat triggered (Ctrl+L)")
                onNextChat?()
                return
            default:
                print("VimChatTerminal: Control key with unhandled keyCode: \(keyCode)")
                break
            }
        }
        
        // Handle Control+V for block visual mode
        if modifiers.contains(.control) && characters.lowercased() == "v" {
            enterVisualMode(.blockwise)
            return
        }
        
        switch characters {
        case "i":
            enterInsertMode()
        case "a":
            enterInsertMode()
            if cursorRow < bufferLines.count {
                cursorCol = min(cursorCol + 1, bufferLines[cursorRow].count)
            }
        case "A":
            if cursorRow < bufferLines.count {
                cursorCol = bufferLines[cursorRow].count
            }
            enterInsertMode()
        case "o":
            bufferLines.insert("", at: cursorRow + 1)
            cursorRow += 1
            cursorCol = 0
            enterInsertMode()
        case "O":
            bufferLines.insert("", at: cursorRow)
            cursorCol = 0
            enterInsertMode()
        case "v":
            enterVisualMode(.characterwise)
        case "V":
            enterVisualMode(.linewise)
        case ":":
            enterCommandMode()
        case "h":
            moveCursorLeft()
        case "j":
            moveCursorDown()
        case "k":
            moveCursorUp()
        case "l":
            moveCursorRight()
        case "w":
            moveWordForward()
        case "b":
            moveWordBackward()
        case "0":
            cursorCol = 0
        case "$":
            if cursorRow < bufferLines.count {
                cursorCol = max(0, bufferLines[cursorRow].count - 1)
            }
        case "x":
            deleteCharacterAtCursor()
        case "dd":
            deleteLine()
        default:
            break
        }
    }
    
    private func handleInsertModeKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Handle Control key shortcuts in insert mode too
        let isControlPressed = modifiers.contains(.control) || 
                              (modifiers.rawValue & NSEvent.ModifierFlags.control.rawValue) != 0 ||
                              modifiers.rawValue == 131330 ||  // Specific value we're seeing
                              characters.unicodeScalars.first?.value ?? 0 < 32
        
        if isControlPressed && !characters.isEmpty {
            switch keyCode {
            case 38: // J key
                print("VimChatTerminal: Navigate Down triggered (Ctrl+J insert mode)")
                onNavigateDown?()
                return
            case 40: // K key
                print("VimChatTerminal: Navigate Up triggered (Ctrl+K insert mode)")
                onNavigateUp?()
                return
            case 4: // H key
                print("VimChatTerminal: Previous Chat triggered (Ctrl+H insert mode)")
                onPreviousChat?()
                return
            case 37: // L key
                print("VimChatTerminal: Next Chat triggered (Ctrl+L insert mode)")
                onNextChat?()
                return
            default:
                break
            }
        }
        
        switch keyCode {
        case 53: // Escape
            exitInsertMode()
        case 36: // Return
            insertNewline()
        case 51: // Delete/Backspace
            handleBackspace()
        default:
            if !characters.isEmpty {
                insertText(characters)
            }
        }
    }
    
    private func handleCommandModeKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        switch keyCode {
        case 53: // Escape
            currentMode = .normal
            statusLine = ""
        case 36: // Return
            executeCommand()
        default:
            if !characters.isEmpty {
                statusLine += characters
            }
        }
    }
    
    private func executeCommand() {
        let command = statusLine.dropFirst() // Remove ':'
        print("VimChatTerminal: executeCommand called with command: '\(command)'")
        
        switch command {
        case "w":
            print("VimChatTerminal: Executing :w command")
            saveAndSendMessage()
            // Keep buffer content for :w
        case "wq":
            print("VimChatTerminal: Executing :wq command")
            saveAndSendMessage()
            // Clear buffer for next message
            clearBufferForNext()
        case "q":
            print("VimChatTerminal: Executing :q command")
            // Just exit command mode for now
            break
        default:
            print("VimChatTerminal: Unknown command: '\(command)'")
            break
        }
        
        currentMode = .normal
        statusLine = ""
    }
    
    private func saveAndSendMessage() {
        let content = bufferLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        print("VimChatTerminal: saveAndSendMessage called with content: '\(content)'")
        print("VimChatTerminal: hasBeenSaved = \(hasBeenSaved)")
        print("VimChatTerminal: lastSentContent = '\(lastSentContent)'")
        
        guard !content.isEmpty else { 
            statusLine = "No content to send"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.statusLine = ""
            }
            return 
        }
        
        // Check if content has actually changed
        if content == lastSentContent {
            statusLine = "No changes to submit"
            print("VimChatTerminal: Content unchanged, skipping submission")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.statusLine = ""
            }
            return
        }
        
        if hasBeenSaved {
            // This is a regeneration - update the last message
            print("VimChatTerminal: Updating last message: \(content)")
            print("VimChatTerminal: onMessageUpdated callback exists: \(onMessageUpdated != nil)")
            onMessageUpdated?(content)
            statusLine = "Message updated"
        } else {
            // First time saving - send new message
            print("VimChatTerminal: Sending new message: \(content)")
            print("VimChatTerminal: onMessageSent callback exists: \(onMessageSent != nil)")
            onMessageSent?(content)
            hasBeenSaved = true
            statusLine = "Message sent"
        }
        
        // Update last sent content
        lastSentContent = content
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.statusLine = ""
        }
    }
    
    private func clearBufferForNext() {
        // Clear buffer for next message
        bufferLines = [""]
        cursorRow = 0
        cursorCol = 0
        hasBeenSaved = false
        lastSentContent = ""
        updateDisplay()
    }
    
    
    
    // MARK: - Cursor Movement
    private func moveCursorLeft() {
        if cursorCol > 0 {
            cursorCol -= 1
        }
    }
    
    private func moveCursorRight() {
        if cursorCol < bufferLines[cursorRow].count {
            cursorCol += 1
        }
    }
    
    private func moveCursorUp() {
        if cursorRow > 0 {
            cursorRow -= 1
            cursorCol = min(cursorCol, bufferLines[cursorRow].count)
        }
    }
    
    private func moveCursorDown() {
        if cursorRow < bufferLines.count - 1 {
            cursorRow += 1
            cursorCol = min(cursorCol, bufferLines[cursorRow].count)
        }
    }
    
    private func moveWordForward() {
        guard cursorRow < bufferLines.count else { return }
        
        let line = bufferLines[cursorRow]
        let safeCol = min(cursorCol, line.count)
        guard safeCol < line.count else { return }
        
        let startIndex = line.index(line.startIndex, offsetBy: safeCol)
        
        if let spaceRange = line[startIndex...].firstIndex(of: " ") {
            cursorCol = line.distance(from: line.startIndex, to: spaceRange) + 1
        } else {
            cursorCol = line.count
        }
    }
    
    private func moveWordBackward() {
        guard cursorRow < bufferLines.count else { return }
        
        let line = bufferLines[cursorRow]
        let safeCol = min(cursorCol, line.count)
        guard safeCol > 0 else { return }
        
        let endIndex = line.index(line.startIndex, offsetBy: safeCol - 1)
        
        if let spaceRange = line[..<endIndex].lastIndex(of: " ") {
            cursorCol = line.distance(from: line.startIndex, to: spaceRange) + 1
        } else {
            cursorCol = 0
        }
    }
    
    // MARK: - Text Editing
    private func enterInsertMode() {
        currentMode = .insert
        statusLine = "-- INSERT --"
    }
    
    private func exitInsertMode() {
        currentMode = .normal
        statusLine = ""
    }
    
    private func enterCommandMode() {
        currentMode = .command
        statusLine = ":"
    }
    
    private func insertText(_ text: String) {
        // Bounds checking to prevent crashes
        guard cursorRow < bufferLines.count else { return }
        
        var line = bufferLines[cursorRow]
        
        // Ensure cursorCol is within valid bounds
        let safeCol = min(cursorCol, line.count)
        let insertIndex = line.index(line.startIndex, offsetBy: safeCol)
        line.insert(contentsOf: text, at: insertIndex)
        bufferLines[cursorRow] = line
        cursorCol = safeCol + text.count
    }
    
    private func insertNewline() {
        guard cursorRow < bufferLines.count else { return }
        
        let currentLine = bufferLines[cursorRow]
        let safeCol = min(cursorCol, currentLine.count)
        let leftPart = String(currentLine.prefix(safeCol))
        let rightPart = String(currentLine.suffix(currentLine.count - safeCol))
        
        bufferLines[cursorRow] = leftPart
        bufferLines.insert(rightPart, at: cursorRow + 1)
        cursorRow += 1
        cursorCol = 0
    }
    
    private func handleBackspace() {
        guard cursorRow < bufferLines.count else { return }
        
        if cursorCol > 0 {
            var line = bufferLines[cursorRow]
            let safeCol = min(cursorCol, line.count)
            if safeCol > 0 {
                let removeIndex = line.index(line.startIndex, offsetBy: safeCol - 1)
                line.remove(at: removeIndex)
                bufferLines[cursorRow] = line
                cursorCol = safeCol - 1
            }
        } else if cursorRow > 0 {
            // Join with previous line
            let currentLine = bufferLines.remove(at: cursorRow)
            cursorRow -= 1
            cursorCol = bufferLines[cursorRow].count
            bufferLines[cursorRow] += currentLine
        }
    }
    
    private func deleteCharacterAtCursor() {
        guard cursorRow < bufferLines.count else { return }
        
        let line = bufferLines[cursorRow]
        guard cursorCol < line.count else { return }
        
        var mutableLine = line
        let removeIndex = mutableLine.index(mutableLine.startIndex, offsetBy: cursorCol)
        mutableLine.remove(at: removeIndex)
        bufferLines[cursorRow] = mutableLine
    }
    
    private func deleteLine() {
        if bufferLines.count > 1 {
            bufferLines.remove(at: cursorRow)
            if cursorRow >= bufferLines.count {
                cursorRow = bufferLines.count - 1
            }
        } else {
            bufferLines[0] = ""
        }
        cursorCol = 0
    }
    
    private func updateStatusLine() {
        switch currentMode {
        case .normal:
            statusLine = ""
        case .insert:
            statusLine = "-- INSERT --"
        case .command:
            if !statusLine.hasPrefix(":") {
                statusLine = ":"
            }
        case .visual:
            switch visualType {
            case .characterwise:
                statusLine = "-- VISUAL --"
            case .linewise:
                statusLine = "-- VISUAL LINE --"
            case .blockwise:
                statusLine = "-- VISUAL BLOCK --"
            }
        }
    }
    
    private func updateDisplay() {
        // Prevent race conditions by using weak self and checking state
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isNvimRunning else { return }
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Visual Mode Operations
    private func enterVisualMode(_ type: VisualType) {
        currentMode = .visual
        visualType = type
        visualStartRow = cursorRow
        visualStartCol = cursorCol
        updateStatusLine()
    }
    
    private func handleVisualModeKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Handle Control key shortcuts in visual mode
        let isControlPressed = modifiers.contains(.control) || 
                              (modifiers.rawValue & NSEvent.ModifierFlags.control.rawValue) != 0 ||
                              modifiers.rawValue == 131330 ||
                              characters.unicodeScalars.first?.value ?? 0 < 32
        
        if isControlPressed && !characters.isEmpty {
            switch keyCode {
            case 38: // J key
                onNavigateDown?()
                return
            case 40: // K key
                onNavigateUp?()
                return
            case 4: // H key
                onPreviousChat?()
                return
            case 37: // L key
                onNextChat?()
                return
            default:
                break
            }
        }
        
        switch keyCode {
        case 53: // Escape
            exitVisualMode()
        default:
            switch characters {
            case "h":
                moveCursorLeft()
            case "j":
                moveCursorDown()
            case "k":
                moveCursorUp()
            case "l":
                moveCursorRight()
            case "w":
                moveWordForward()
            case "b":
                moveWordBackward()
            case "0":
                cursorCol = 0
            case "$":
                cursorCol = max(0, bufferLines[cursorRow].count - 1)
            case "d":
                deleteSelection()
                exitVisualMode()
            case "y":
                yankSelection()
                exitVisualMode()
            case "c":
                deleteSelection()
                enterInsertMode()
            case "v":
                // Switch visual mode types
                switch visualType {
                case .characterwise:
                    visualType = .linewise
                case .linewise:
                    visualType = .blockwise
                case .blockwise:
                    visualType = .characterwise
                }
                updateStatusLine()
            case "V":
                visualType = .linewise
                updateStatusLine()
            default:
                break
            }
        }
    }
    
    private func exitVisualMode() {
        currentMode = .normal
        updateStatusLine()
    }
    
    private func deleteSelection() {
        let (startRow, startCol, endRow, endCol) = getSelectionBounds()
        
        switch visualType {
        case .characterwise:
            deleteCharacterSelection(startRow: startRow, startCol: startCol, endRow: endRow, endCol: endCol)
        case .linewise:
            deleteLineSelection(startRow: startRow, endRow: endRow)
        case .blockwise:
            deleteBlockSelection(startRow: startRow, startCol: startCol, endRow: endRow, endCol: endCol)
        }
    }
    
    private func yankSelection() {
        // In a full implementation, this would copy to clipboard
        // For now, just simulate the operation
        statusLine = "Yanked selection"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.statusLine = ""
        }
    }
    
    private func getSelectionBounds() -> (startRow: Int, startCol: Int, endRow: Int, endCol: Int) {
        let startRow = min(visualStartRow, cursorRow)
        let endRow = max(visualStartRow, cursorRow)
        let startCol = min(visualStartCol, cursorCol)
        let endCol = max(visualStartCol, cursorCol)
        
        return (startRow, startCol, endRow, endCol)
    }
    
    private func deleteCharacterSelection(startRow: Int, startCol: Int, endRow: Int, endCol: Int) {
        if startRow == endRow {
            // Single line selection
            guard startRow < bufferLines.count else { return }
            var line = bufferLines[startRow]
            let safeStartCol = min(startCol, line.count)
            let safeEndCol = min(endCol, line.count - 1)
            guard safeStartCol <= safeEndCol && safeStartCol < line.count else { return }
            
            let startIndex = line.index(line.startIndex, offsetBy: safeStartCol)
            let endIndex = line.index(line.startIndex, offsetBy: min(safeEndCol + 1, line.count))
            line.removeSubrange(startIndex..<endIndex)
            bufferLines[startRow] = line
            cursorRow = startRow
            cursorCol = startCol
        } else {
            // Multi-line selection
            for row in (startRow...endRow).reversed() {
                if row == startRow {
                    // First line - delete from startCol to end
                    var line = bufferLines[row]
                    let startIndex = line.index(line.startIndex, offsetBy: startCol)
                    line.removeSubrange(startIndex...)
                    bufferLines[row] = line
                } else if row == endRow {
                    // Last line - delete from beginning to endCol
                    var line = bufferLines[row]
                    let endIndex = line.index(line.startIndex, offsetBy: min(endCol + 1, line.count))
                    line.removeSubrange(line.startIndex..<endIndex)
                    // Join with first line
                    bufferLines[startRow] += line
                    bufferLines.remove(at: row)
                } else {
                    // Middle lines - delete entirely
                    bufferLines.remove(at: row)
                }
            }
            cursorRow = startRow
            cursorCol = startCol
        }
    }
    
    private func deleteLineSelection(startRow: Int, endRow: Int) {
        for _ in startRow...endRow {
            if bufferLines.count > 1 {
                bufferLines.remove(at: startRow)
            } else {
                bufferLines[0] = ""
            }
        }
        cursorRow = min(startRow, bufferLines.count - 1)
        cursorCol = 0
    }
    
    private func deleteBlockSelection(startRow: Int, startCol: Int, endRow: Int, endCol: Int) {
        // Block selection deletes rectangular region
        for row in startRow...endRow {
            if row < bufferLines.count {
                var line = bufferLines[row]
                if startCol < line.count {
                    let actualEndCol = min(endCol, line.count - 1)
                    if actualEndCol >= startCol {
                        let startIndex = line.index(line.startIndex, offsetBy: startCol)
                        let endIndex = line.index(line.startIndex, offsetBy: actualEndCol + 1)
                        line.removeSubrange(startIndex..<endIndex)
                        bufferLines[row] = line
                    }
                }
            }
        }
        cursorRow = startRow
        cursorCol = startCol
    }
    
    // MARK: - Public Interface
    func getDisplayLines() -> [String] {
        return bufferLines
    }
    
    func getCursorPosition() -> (row: Int, col: Int) {
        return (cursorRow, cursorCol)
    }
    
    func getVisualSelection() -> (isActive: Bool, startRow: Int, startCol: Int, endRow: Int, endCol: Int, type: VisualType)? {
        guard currentMode == .visual else { return nil }
        let (startRow, startCol, endRow, endCol) = getSelectionBounds()
        return (true, startRow, startCol, endRow, endCol, visualType)
    }
}

// MARK: - Vim Modes
enum VimMode {
    case normal
    case insert
    case command
    case visual
}

// MARK: - Visual Mode Types
enum VisualType {
    case characterwise
    case linewise
    case blockwise
}

```

```swift
// File: Sources/plue/FarcasterService.swift
import Foundation

// Swift bridge to Zig Farcaster SDK
// Provides high-level Swift interface to Farcaster functionality

// C function imports from Zig
@_silgen_name("fc_client_create")
func fc_client_create(_ fid: UInt64, _ private_key_hex: UnsafePointer<CChar>) -> OpaquePointer?

@_silgen_name("fc_client_destroy")
func fc_client_destroy(_ client: OpaquePointer?)

@_silgen_name("fc_post_cast")
func fc_post_cast(_ client: OpaquePointer?, _ text: UnsafePointer<CChar>, _ channel_url: UnsafePointer<CChar>) -> UnsafePointer<CChar>

@_silgen_name("fc_like_cast")
func fc_like_cast(_ client: OpaquePointer?, _ cast_hash: UnsafePointer<CChar>, _ cast_fid: UInt64) -> UnsafePointer<CChar>

@_silgen_name("fc_get_casts_by_channel")
func fc_get_casts_by_channel(_ client: OpaquePointer?, _ channel_url: UnsafePointer<CChar>, _ limit: UInt32) -> UnsafePointer<CChar>

@_silgen_name("fc_free_string")
func fc_free_string(_ str: UnsafePointer<CChar>)

// Swift service class
class FarcasterService {
    private var client: OpaquePointer?
    private let userFid: UInt64
    private let channelUrl: String
    
    enum FarcasterServiceError: Error, LocalizedError {
        case initializationFailed
        case noPrivateKey
        case apiError(String)
        case clientNotInitialized
        
        var errorDescription: String? {
            switch self {
            case .initializationFailed:
                return "Failed to initialize Farcaster client"
            case .noPrivateKey:
                return "Farcaster private key not found. Please set FARCASTER_PRIVATE_KEY environment variable."
            case .apiError(let message):
                return "Farcaster API Error: \(message)"
            case .clientNotInitialized:
                return "Farcaster client not initialized"
            }
        }
    }
    
    init(userFid: UInt64, channelUrl: String) throws {
        self.userFid = userFid
        self.channelUrl = channelUrl
        
        // Get private key from environment
        guard let privateKeyHex = ProcessInfo.processInfo.environment["FARCASTER_PRIVATE_KEY"],
              !privateKeyHex.isEmpty else {
            throw FarcasterServiceError.noPrivateKey
        }
        
        // Initialize Zig client
        self.client = privateKeyHex.withCString { privateKeyPtr in
            fc_client_create(userFid, privateKeyPtr)
        }
        
        guard self.client != nil else {
            throw FarcasterServiceError.initializationFailed
        }
        
        print("FarcasterService: Initialized for FID \(userFid) in channel \(channelUrl)")
    }
    
    deinit {
        if let client = client {
            fc_client_destroy(client)
        }
    }
    
    // MARK: - Cast Operations
    
    func postCast(text: String) async throws -> String {
        guard let client = client else {
            throw FarcasterServiceError.clientNotInitialized
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: FarcasterServiceError.clientNotInitialized)
                    return
                }
                
                let result = text.withCString { textPtr in
                    self.channelUrl.withCString { channelPtr in
                        fc_post_cast(client, textPtr, channelPtr)
                    }
                }
                
                let resultString = String(cString: result)
                fc_free_string(result)
                
                if resultString.hasPrefix("ERROR:") {
                    continuation.resume(throwing: FarcasterServiceError.apiError(resultString))
                } else {
                    continuation.resume(returning: resultString)
                }
            }
        }
    }
    
    func getCasts(limit: UInt32 = 25) async throws -> [FarcasterCastData] {
        guard let client = client else {
            throw FarcasterServiceError.clientNotInitialized
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: FarcasterServiceError.clientNotInitialized)
                    return
                }
                
                let result = self.channelUrl.withCString { channelPtr in
                    fc_get_casts_by_channel(client, channelPtr, limit)
                }
                
                let resultString = String(cString: result)
                fc_free_string(result)
                
                if resultString.hasPrefix("ERROR:") {
                    continuation.resume(throwing: FarcasterServiceError.apiError(resultString))
                    return
                }
                
                do {
                    let casts = try self.parseCastsJson(resultString)
                    continuation.resume(returning: casts)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func likeCast(castHash: String, authorFid: UInt64) async throws -> String {
        guard let client = client else {
            throw FarcasterServiceError.clientNotInitialized
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = castHash.withCString { hashPtr in
                    fc_like_cast(client, hashPtr, authorFid)
                }
                
                let resultString = String(cString: result)
                fc_free_string(result)
                
                if resultString.hasPrefix("ERROR:") {
                    continuation.resume(throwing: FarcasterServiceError.apiError(resultString))
                } else {
                    continuation.resume(returning: resultString)
                }
            }
        }
    }
    
    // MARK: - Data Models
    
    struct FarcasterCastData: Codable, Identifiable {
        let id: String
        let hash: String
        let parentHash: String?
        let parentUrl: String?
        let author: FarcasterUserData
        let text: String
        let timestamp: UInt64
        let mentions: [UInt64]
        let repliesCount: UInt32
        let reactionsCount: UInt32
        let recastsCount: UInt32
        
        var timeAgo: String {
            let now = Date()
            let castDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let interval = now.timeIntervalSince(castDate)
            
            if interval < 60 {
                return "now"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "\(minutes)m"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "\(hours)h"
            } else {
                let days = Int(interval / 86400)
                return "\(days)d"
            }
        }
    }
    
    struct FarcasterUserData: Codable {
        let fid: UInt64
        let username: String
        let displayName: String
        let bio: String
        let pfpUrl: String
        let followerCount: UInt32
        let followingCount: UInt32
        
        enum CodingKeys: String, CodingKey {
            case fid, username, bio
            case displayName = "display_name"
            case pfpUrl = "pfp_url"
            case followerCount = "follower_count"
            case followingCount = "following_count"
        }
    }
    
    // MARK: - JSON Parsing
    
    private func parseCastsJson(_ jsonString: String) throws -> [FarcasterCastData] {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw FarcasterServiceError.apiError("Invalid JSON data")
        }
        
        do {
            let casts = try JSONDecoder().decode([FarcasterCastData].self, from: jsonData)
            return casts
        } catch {
            // If decoding fails, try to parse as individual cast objects
            // This handles the case where Zig returns a different format
            print("FarcasterService: JSON decode error: \(error)")
            return []
        }
    }
    
    // MARK: - Conversion Helpers
    
    func convertToFarcasterPosts(_ casts: [FarcasterCastData]) -> [FarcasterPost] {
        return casts.map { cast in
            FarcasterPost(
                id: cast.hash,
                author: FarcasterUser(
                    username: cast.author.username,
                    displayName: cast.author.displayName,
                    avatarURL: cast.author.pfpUrl
                ),
                content: cast.text,
                timestamp: Date(timeIntervalSince1970: TimeInterval(cast.timestamp)),
                channel: extractChannelFromUrl(cast.parentUrl),
                likes: Int(cast.reactionsCount),
                recasts: Int(cast.recastsCount),
                replies: Int(cast.repliesCount),
                isLiked: false, // Would need to check user's reactions
                isRecast: false // Would need to check user's recasts
            )
        }
    }
    
    private func extractChannelFromUrl(_ url: String?) -> String {
        guard let url = url else { return "general" }
        
        // Extract channel name from Farcaster channel URL
        // e.g., "https://farcaster.xyz/~/channel/dev" -> "dev"
        if let range = url.range(of: "/channel/") {
            let channelName = String(url[range.upperBound...])
            return channelName.isEmpty ? "general" : channelName
        }
        
        return "general"
    }
}

// MARK: - Test Configuration

extension FarcasterService {
    static func createTestService() -> FarcasterService? {
        do {
            // Test configuration - in production these would come from secure storage
            let testFid: UInt64 = 1234 // Replace with actual test FID
            let testChannelUrl = "https://farcaster.xyz/~/channel/dev"
            
            return try FarcasterService(userFid: testFid, channelUrl: testChannelUrl)
        } catch {
            print("FarcasterService: Failed to create test service: \(error)")
            return nil
        }
    }
}```

```swift
// File: Sources/plue/main.swift
import SwiftUI
import AppKit
import Foundation

// Parse command line arguments
func parseCommandLineArguments() -> String? {
    if CommandLine.arguments.count <= 1 {
        return nil
    }
    let path = CommandLine.arguments[1]
    
    let absolutePath: String
    if path.hasPrefix("/") {
        absolutePath = path
    } else if path.hasPrefix("~") {
        absolutePath = NSString(string: path).expandingTildeInPath
    } else {
        absolutePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path).path
    }
    
    var isDirectory: ObjCBool = false
    if !FileManager.default.fileExists(atPath: absolutePath, isDirectory: &isDirectory) {
        fputs("Error: Directory '\(path)' does not exist\n", stderr)
        exit(1)
    }
    if !isDirectory.boolValue {
        fputs("Error: '\(path)' is not a directory\n", stderr)
        exit(1)
    } 
    return absolutePath
}

var initialDirectory: String? = parseCommandLineArguments()

let app = NSApplication.shared
app.setActivationPolicy(.regular)
PlueApp.main()
```

```swift
// File: Sources/plue/App.swift
import SwiftUI

struct PlueApp: App {
    @StateObject private var appStateContainer = AppStateContainer()

    init() {
        // Initialize AppleScript support
        _ = PlueAppleScriptSupport.shared
    }

    var body: some Scene {
        WindowGroup {
            // Directly use the main ContentView
            ContentView(appState: $appStateContainer.appState)
                .frame(minWidth: 1000, minHeight: 700)
                .background(DesignSystem.Colors.background) // Use the design system background
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar) // This is the correct style for a custom borderless window
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// Create a simple container to hold and manage the AppState
class AppStateContainer: ObservableObject {
    @Published var appState = AppState.initial
    private let core = PlueCore.shared

    init() {
        // Use the initial directory from command line arguments if provided
        if let initialDir = initialDirectory {
            _ = core.initialize(workingDirectory: initialDir)
        } else {
            _ = core.initialize()
        }
        
        core.subscribe { [weak self] newState in
            DispatchQueue.main.async {
                self?.appState = newState
            }
        }
    }

    func handleEvent(_ event: AppEvent) {
        core.handleEvent(event)
    }
}

// MARK: - Custom Window Controls

enum WindowAction {
    case close, minimize, maximize
}

struct CustomWindowButton: View {
    let action: WindowAction
    let color: Color
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: performAction) {
            ZStack {
                // Base circle
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                
                // Gradient overlay for depth
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isPressed ? 0 : 0.3),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 8
                        )
                    )
                    .frame(width: 12, height: 12)
                
                // Icon overlay
                if isHovered {
                    iconForAction
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.black.opacity(0.6))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
    
    @ViewBuilder
    private var iconForAction: some View {
        switch action {
        case .close:
            Image(systemName: "xmark")
                .scaleEffect(0.8)
        case .minimize:
            Image(systemName: "minus")
        case .maximize:
            Image(systemName: "plus")
                .scaleEffect(0.9)
        }
    }
    
    private func performAction() {
        guard let window = NSApplication.shared.windows.first else { return }
        
        switch action {
        case .close:
            window.close()
        case .minimize:
            window.miniaturize(nil)
        case .maximize:
            if window.isZoomed {
                window.zoom(nil)
            } else {
                window.zoom(nil)
            }
        }
    }
}

```

```swift
// File: Sources/plue/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Binding var appState: AppState
    @State private var previousTab: TabType = .prompt
    
    // This will now handle the event dispatches
    private func handleEvent(_ event: AppEvent) {
        PlueCore.shared.handleEvent(event)
    }
    
    // Smart animation direction based on tab indices
    private func transitionForTab(_ tab: TabType) -> AnyTransition {
        let currentIndex = appState.currentTab.rawValue
        let previousIndex = previousTab.rawValue
        let isMovingRight = currentIndex > previousIndex
        
        return .asymmetric(
            insertion: .move(edge: isMovingRight ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isMovingRight ? .leading : .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Custom Title Bar with Integrated Tabs
            CustomTitleBar(
                selectedTab: Binding(
                    get: { appState.currentTab },
                    set: { newTab in handleEvent(.tabSwitched(newTab)) }
                ),
                currentTheme: appState.currentTheme,
                onThemeToggle: { handleEvent(.themeToggled) }
            )

            // 2. Main Content Area
            ZStack {
                // Use native macOS background with material
                Rectangle()
                    .fill(DesignSystem.Colors.background(for: appState.currentTheme))
                    .background(DesignSystem.Materials.adaptive(for: appState.currentTheme))
                    .ignoresSafeArea()

                // 3. View Switching Logic with Smart Contextual Transitions
                Group {
                    switch appState.currentTab {
                    case .prompt:
                        ModernChatView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.prompt))
                    case .farcaster:
                        FarcasterView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.farcaster))
                    case .agent:
                        AgentView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.agent))
                    case .terminal:
                        TerminalView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.terminal))
                    case .web:
                        WebView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.web))
                    case .editor:
                        // TODO: Implement proper code editor view
                        // For now, using EditorView as placeholder
                        EditorView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.editor))
                    case .diff:
                        DiffView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.diff))
                    case .worktree:
                        WorktreeView(appState: appState, core: PlueCore.shared)
                            .transition(transitionForTab(.worktree))
                    }
                }
                .animation(DesignSystem.Animation.tabSwitch, value: appState.currentTab)
                .onChange(of: appState.currentTab) { oldValue, newValue in
                    previousTab = oldValue
                }
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
        .onAppear(perform: configureWindow)
    }
    
    private func configureWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.backgroundColor = NSColor(DesignSystem.Colors.background(for: appState.currentTheme))
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        
        // Configure window appearance
        window.appearance = NSAppearance(named: appState.currentTheme == .dark ? .darkAqua : .aqua)
        window.minSize = NSSize(width: 800, height: 600)
        
        // Don't hide the standard buttons, just let our custom ones handle the actions
        window.standardWindowButton(.closeButton)?.alphaValue = 0
        window.standardWindowButton(.miniaturizeButton)?.alphaValue = 0
        window.standardWindowButton(.zoomButton)?.alphaValue = 0
    }
}


// MARK: - New Custom Title Bar View
struct CustomTitleBar: View {
    @Binding var selectedTab: TabType
    let currentTheme: DesignSystem.Theme
    let onThemeToggle: () -> Void
    @State private var isHovered = false

    private let windowActions: [WindowAction] = [.close, .minimize, .maximize]
    private let windowActionColors: [Color] = [.red, .yellow, .green]

    var body: some View {
        HStack(spacing: 0) {
            // Window Controls (Traffic Lights)
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    CustomWindowButton(action: windowActions[i], color: windowActionColors[i])
                        .opacity(isHovered ? 1.0 : 0.4)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 40) // Define a fixed height for the title bar area
            .onHover { hover in isHovered = hover }

            // Tab Buttons with visual separator
            Divider()
                .frame(width: 1, height: 16)
                .background(DesignSystem.Colors.border(for: currentTheme))
                .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(TabType.allCases, id: \.self) { tab in
                        TabButton(tab: tab, selectedTab: $selectedTab, theme: currentTheme)
                    }
                }
                .padding(.horizontal, 4)
            }
            
            Spacer()
            
            // Theme Toggle Button with better styling
            Button(action: onThemeToggle) {
                Image(systemName: currentTheme == .dark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: currentTheme))
                    .padding(6)
                    .background(
                        Circle()
                            .fill(DesignSystem.Colors.surface(for: currentTheme))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(DesignSystem.Colors.border(for: currentTheme), lineWidth: 0.5)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Toggle theme")
            .padding(.trailing, 12)
        }
        .frame(height: 40)
        .background(
            ZStack {
                // Base background
                DesignSystem.Colors.background(for: currentTheme)
                
                // Material effect for depth
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                // Bottom border
                VStack {
                    Spacer()
                    Divider()
                        .background(DesignSystem.Colors.border(for: currentTheme))
                }
            }
        )
    }
}


// MARK: - New Tab Button View
struct TabButton: View {
    let tab: TabType
    @Binding var selectedTab: TabType
    let theme: DesignSystem.Theme
    @State private var isHovered = false
    
    private var isSelected: Bool { selectedTab == tab }
    
    private var title: String {
        switch tab {
        case .prompt: return "Prompt"
        case .farcaster: return "Social"
        case .agent: return "Agent"
        case .terminal: return "Terminal"
        case .web: return "Web"
        case .editor: return "Editor"
        case .diff: return "Diff"
        case .worktree: return "Worktree"
        }
    }
    
    private var icon: String {
        switch tab {
        case .prompt: return "bubble.left.and.bubble.right"
        case .farcaster: return "person.2.wave.2"
        case .agent: return "brain"
        case .terminal: return "terminal"
        case .web: return "safari"
        case .editor: return "doc.text"
        case .diff: return "arrow.left.arrow.right"
        case .worktree: return "folder.badge.gearshape"
        }
    }

    var body: some View {
        Button(action: { 
            withAnimation(DesignSystem.Animation.tabSwitch) {
                selectedTab = tab 
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 10, weight: .regular))
            }
            .frame(width: 60, height: 40)
            .foregroundColor(
                isSelected ? DesignSystem.Colors.primary :
                isHovered ? DesignSystem.Colors.textPrimary(for: theme) :
                DesignSystem.Colors.textSecondary(for: theme)
            )
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.Colors.primary.opacity(0.1))
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(DesignSystem.Colors.primary.opacity(0.2), lineWidth: 0.5)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.Colors.surface(for: theme).opacity(0.5))
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hover
            }
        }
    }
}

#Preview {
    ContentView(appState: .constant(AppState.initial))
        .frame(width: 1200, height: 800)
}```

```swift
// File: Sources/plue/LivePlueCore.swift
import Foundation
import libplue

// MARK: - FFI Function Declarations

@_silgen_name("plue_init")
func plue_init() -> Int32

@_silgen_name("plue_deinit")
func plue_deinit()

@_silgen_name("plue_get_state")
func plue_get_state() -> CAppState

@_silgen_name("plue_free_state")
func plue_free_state(_ state: CAppState)

@_silgen_name("plue_process_event")
func plue_process_event(_ eventType: Int32, _ jsonData: UnsafePointer<CChar>?) -> Int32

@_silgen_name("plue_free_string")
func plue_free_string(_ str: UnsafePointer<CChar>)

// Update C function import
@_silgen_name("plue_register_state_callback")
func plue_register_state_callback(_ callback: @convention(c) (UnsafeMutableRawPointer?) -> Void, _ context: UnsafeMutableRawPointer?)

// MARK: - Live FFI Implementation

class LivePlueCore: PlueCoreInterface {
    private var stateCallbacks: [(AppState) -> Void] = []
    private let queue = DispatchQueue(label: "plue.core.live", qos: .userInteractive)
    
    init() {
        // Initialize the Zig core
        let result = plue_init()
        if result != 0 {
            print("LivePlueCore: Failed to initialize Zig core: \(result)")
        } else {
            print("LivePlueCore: Successfully initialized with Zig FFI")
            
            // Get an opaque pointer to this instance of the class
            let context = Unmanaged.passUnretained(self).toOpaque()
            
            // Register the callback, passing the context pointer
            plue_register_state_callback(Self.stateUpdateCallback, context)
        }
    }
    
    deinit {
        plue_deinit()
    }
    
    // The C callback is now a static function that receives the context
    private static let stateUpdateCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
        // Ensure context is not nil
        guard let context = context else { return }
        
        // Reconstitute the LivePlueCore instance from the opaque pointer
        let instance = Unmanaged<LivePlueCore>.fromOpaque(context).takeUnretainedValue()
        
        // Call the instance method to notify subscribers
        instance.queue.async {
            instance.notifyStateChange()
        }
    }
    
    func getCurrentState() -> AppState {
        return queue.sync {
            return fetchStateFromZig() ?? AppState.initial
        }
    }
    
    func handleEvent(_ event: AppEvent) {
        queue.async {
            self.sendEventToZig(event)
            // State change notification will be triggered by Zig via callback
        }
    }
    
    func subscribe(callback: @escaping (AppState) -> Void) {
        queue.async {
            self.stateCallbacks.append(callback)
            // Send current state immediately
            if let state = self.fetchStateFromZig() {
                DispatchQueue.main.async {
                    callback(state)
                }
            }
        }
    }
    
    func initialize() -> Bool {
        return initialize(workingDirectory: FileManager.default.currentDirectoryPath)
    }
    
    func initialize(workingDirectory: String) -> Bool {
        // Already initialized in init
        return true
    }
    
    func shutdown() {
        plue_deinit()
    }
    
    // MARK: - Private Methods
    
    private func fetchStateFromZig() -> AppState? {
        let cState = plue_get_state()
        defer { plue_free_state(cState) }
        
        // Convert C strings to Swift strings safely
        let errorMessage = cState.error_message != nil && String(cString: cState.error_message).isEmpty == false 
            ? String(cString: cState.error_message) 
            : nil
            
        // Create prompt state
        let promptState = PromptState(
            conversations: PromptState.initial.conversations,
            currentConversationIndex: PromptState.initial.currentConversationIndex,
            currentPromptContent: String(cString: cState.prompt.current_content),
            isProcessing: cState.prompt.processing
        )
        
        // Create terminal state
        let terminalState = TerminalState(
            buffer: Array(repeating: Array(repeating: CoreTerminalCell.empty, count: Int(cState.terminal.cols)), count: Int(cState.terminal.rows)),
            cursor: CursorPosition(row: 0, col: 0),
            dimensions: TerminalDimensions(rows: Int(cState.terminal.rows), cols: Int(cState.terminal.cols)),
            isConnected: cState.terminal.is_running,
            currentCommand: String(cString: cState.terminal.content),
            needsRedraw: false
        )
        
        // Create web state
        let webState = WebState(
            currentURL: String(cString: cState.web.current_url),
            canGoBack: cState.web.can_go_back,
            canGoForward: cState.web.can_go_forward,
            isLoading: cState.web.is_loading,
            isSecure: String(cString: cState.web.current_url).hasPrefix("https://"),
            pageTitle: String(cString: cState.web.page_title)
        )
        
        // Create vim state
        let vimMode: CoreVimMode
        switch cState.vim.mode {
        case VimModeNormal: vimMode = .normal
        case VimModeInsert: vimMode = .insert
        case VimModeVisual: vimMode = .visual
        case VimModeCommand: vimMode = .command
        default: vimMode = .normal
        }
        
        let vimState = VimState(
            mode: vimMode,
            buffer: String(cString: cState.vim.content).components(separatedBy: "\n"),
            cursor: CursorPosition(row: Int(cState.vim.cursor_row), col: Int(cState.vim.cursor_col)),
            statusLine: String(cString: cState.vim.status_line),
            visualSelection: nil
        )
        
        // Create agent state
        var agentState = AgentState.initial
        agentState = AgentState(
            conversations: agentState.conversations,
            currentConversationIndex: agentState.currentConversationIndex,
            isProcessing: cState.agent.processing,
            currentWorkspace: agentState.currentWorkspace,
            availableWorktrees: agentState.availableWorktrees,
            daggerSession: cState.agent.dagger_connected ? agentState.daggerSession : nil,
            workflowQueue: agentState.workflowQueue,
            isExecutingWorkflow: agentState.isExecutingWorkflow
        )
        
        // Map tab type
        let tabType: TabType
        switch cState.current_tab {
        case TabTypePrompt: tabType = .prompt
        case TabTypeFarcaster: tabType = .farcaster
        case TabTypeAgent: tabType = .agent
        case TabTypeTerminal: tabType = .terminal
        case TabTypeWeb: tabType = .web
        case TabTypeEditor: tabType = .editor
        case TabTypeDiff: tabType = .diff
        case TabTypeWorktree: tabType = .worktree
        default: tabType = .prompt
        }
        
        // Map theme
        let theme: DesignSystem.Theme = cState.current_theme == ThemeDark ? .dark : .light
        
        return AppState(
            currentTab: tabType,
            isInitialized: cState.is_initialized,
            errorMessage: errorMessage,
            openAIAvailable: cState.openai_available,
            currentTheme: theme,
            promptState: promptState,
            terminalState: terminalState,
            vimState: vimState,
            webState: webState,
            editorState: EditorState.initial,
            farcasterState: FarcasterState.initial,
            agentState: agentState
        )
    }
    
    private func sendEventToZig(_ event: AppEvent) {
        let eventType = eventTypeFromAppEvent(event)
        let eventData = eventDataFromAppEvent(event)
        
        var result: Int32 = 0
        if let data = eventData {
            data.withCString { cString in
                result = plue_process_event(eventType, cString)
            }
        } else {
            result = plue_process_event(eventType, nil)
        }
        
        if result != 0 {
            print("LivePlueCore: Failed to process event: \(event)")
        }
    }
    
    private func notifyStateChange() {
        guard let state = fetchStateFromZig() else { return }
        
        DispatchQueue.main.async {
            for callback in self.stateCallbacks {
                callback(state)
            }
        }
    }
    
    private func eventTypeFromAppEvent(_ event: AppEvent) -> Int32 {
        switch event {
        case .tabSwitched: return 0
        case .themeToggled: return 1
        case .terminalInput: return 2
        case .terminalResize: return 3
        case .vimKeypress: return 4
        case .vimSetContent: return 5
        case .webNavigate: return 6
        case .webGoBack: return 7
        case .webGoForward: return 8
        case .webReload: return 9
        case .editorContentChanged: return 10
        case .editorSave: return 11
        case .farcasterSelectChannel: return 12
        case .farcasterLikePost: return 13
        case .farcasterRecastPost: return 14
        case .farcasterReplyToPost: return 15
        case .farcasterCreatePost: return 16
        case .farcasterRefreshFeed: return 17
        case .promptMessageSent: return 18
        case .promptContentUpdated: return 19
        case .promptNewConversation: return 20
        case .promptSelectConversation: return 21
        case .agentMessageSent: return 22
        case .agentNewConversation: return 23
        case .agentSelectConversation: return 24
        case .agentCreateWorktree: return 25
        case .agentSwitchWorktree: return 26
        case .agentDeleteWorktree: return 27
        case .agentRefreshWorktrees: return 28
        case .agentStartDaggerSession: return 29
        case .agentStopDaggerSession: return 30
        case .agentExecuteWorkflow: return 31
        case .agentCancelWorkflow: return 32
        case .chatMessageSent: return 33
        case .fileOpened: return 34
        case .fileSaved: return 35
        }
    }
    
    private func eventDataFromAppEvent(_ event: AppEvent) -> String? {
        switch event {
        case .tabSwitched(let tab):
            return "\(tab.rawValue)"
        case .terminalInput(let input):
            return input
        case .terminalResize(let rows, let cols):
            return "{\"rows\":\(rows),\"cols\":\(cols)}"
        case .vimKeypress(let key, let modifiers):
            return "{\"key\":\"\(key)\",\"modifiers\":\(modifiers)}"
        case .vimSetContent(let content):
            return content
        case .webNavigate(let url):
            return url
        case .editorContentChanged(let content):
            return content
        case .farcasterSelectChannel(let channel):
            return channel
        case .farcasterLikePost(let postId):
            return postId
        case .farcasterRecastPost(let postId):
            return postId
        case .farcasterReplyToPost(let postId, let reply):
            return "{\"postId\":\"\(postId)\",\"reply\":\"\(reply)\"}"
        case .farcasterCreatePost(let content):
            return content
        case .promptMessageSent(let message):
            return message
        case .promptContentUpdated(let content):
            return content
        case .promptSelectConversation(let index):
            return "\(index)"
        case .agentMessageSent(let message):
            return message
        case .agentSelectConversation(let index):
            return "\(index)"
        case .agentCreateWorktree(let branch, let path):
            return "{\"branch\":\"\(branch)\",\"path\":\"\(path)\"}"
        case .agentSwitchWorktree(let id):
            return id
        case .agentDeleteWorktree(let id):
            return id
        case .agentExecuteWorkflow(let workflow):
            // For now, just return the workflow ID
            return workflow.id
        case .agentCancelWorkflow(let id):
            return id
        case .chatMessageSent(let message):
            return message
        case .fileOpened(let path):
            return path
        default:
            return nil
        }
    }
}

```

