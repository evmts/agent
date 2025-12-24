const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const App = @import("app.zig").App;
const AppState = @import("state/app_state.zig").AppState;
const PlueClient = @import("client/client.zig").PlueClient;
const EventQueue = @import("client/sse.zig").EventQueue;

const version = "0.1.0";
const default_api_url = "http://localhost:4000";

/// CLI configuration
const Config = struct {
    api_url: []const u8 = default_api_url,
};

fn printHelp() void {
    std.debug.print(
        \\Plue TUI - Terminal UI for Plue
        \\
        \\Usage: plue-tui [OPTIONS]
        \\
        \\Options:
        \\  --api-url <URL>    API server URL (default: http://localhost:4000)
        \\  --help             Show this help message
        \\  --version          Show version information
        \\
        \\Controls:
        \\  Ctrl+C             Exit the application (or abort streaming)
        \\  Ctrl+L             Clear screen
        \\  Enter              Send message
        \\  Up/Down            Navigate history
        \\
        \\Slash Commands:
        \\  /new               Create new session
        \\  /sessions          List sessions
        \\  /model             Select model
        \\  /clear             Clear conversation
        \\  /help              Show help
        \\  /quit              Exit
        \\
        \\
    , .{});
}

fn printVersion() void {
    std.debug.print("plue-tui version {s}\n", .{version});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse CLI arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = Config{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--version")) {
            printVersion();
            return;
        } else if (std.mem.eql(u8, arg, "--api-url")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --api-url requires a URL argument\n", .{});
                std.process.exit(1);
            }
            config.api_url = args[i];
        } else {
            std.debug.print("Error: Unknown argument '{s}'\n", .{arg});
            std.debug.print("Use --help for usage information\n", .{});
            std.process.exit(1);
        }
    }

    // Initialize state
    var state = try AppState.init(allocator, config.api_url);
    defer state.deinit();

    // Initialize client
    var client = PlueClient.init(allocator, config.api_url);
    defer client.deinit();

    // Initialize event queue
    var event_queue = EventQueue.init(allocator);
    defer event_queue.deinit();

    // Initialize vxfw app
    var vx_app = try vxfw.App.init(allocator);
    defer vx_app.deinit();

    // Create main app widget
    var app = App.init(allocator, &state, &client, &event_queue);
    defer app.deinit();

    // Run the TUI
    try vx_app.run(app.widget(), .{});
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
