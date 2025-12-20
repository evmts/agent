//! Plue Native App - Zig Implementation
//!
//! Launches the Astro frontend in a native WebUI window.
//! This is a Zig replacement for native/app.ts.
//!
//! Usage:
//!   # Start Astro dev server first
//!   bun run dev
//!
//!   # Then run this app
//!   zig build run
//!
//! Options:
//!   --width <px>     Window width (default: 1400)
//!   --height <px>    Window height (default: 900)
//!   --port <port>    Astro dev server port (default: 5173)
//!   --no-wait        Don't wait for server to be ready
//!   --webview        Use WebView instead of browser

const std = @import("std");
const webui = @import("webui");

const DEFAULT_WIDTH: u32 = 1400;
const DEFAULT_HEIGHT: u32 = 900;
const DEFAULT_PORT: u16 = 5173;
const MAX_WAIT_ATTEMPTS: u32 = 30;

const AppConfig = struct {
    width: u32 = DEFAULT_WIDTH,
    height: u32 = DEFAULT_HEIGHT,
    port: u16 = DEFAULT_PORT,
    wait_for_server: bool = true,
    use_webview: bool = false,
};

const plue_icon =
    \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
    \\  <rect width="100" height="100" fill="#1a1a1a"/>
    \\  <text x="50" y="70" font-size="60" text-anchor="middle" fill="#fff">P</text>
    \\</svg>
;

fn parseArgs(allocator: std.mem.Allocator) !AppConfig {
    var config = AppConfig{};
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--width")) {
            if (args.next()) |val| {
                config.width = std.fmt.parseInt(u32, val, 10) catch DEFAULT_WIDTH;
            }
        } else if (std.mem.eql(u8, arg, "--height")) {
            if (args.next()) |val| {
                config.height = std.fmt.parseInt(u32, val, 10) catch DEFAULT_HEIGHT;
            }
        } else if (std.mem.eql(u8, arg, "--port")) {
            if (args.next()) |val| {
                config.port = std.fmt.parseInt(u16, val, 10) catch DEFAULT_PORT;
            }
        } else if (std.mem.eql(u8, arg, "--no-wait")) {
            config.wait_for_server = false;
        } else if (std.mem.eql(u8, arg, "--webview") or std.mem.eql(u8, arg, "-w")) {
            config.use_webview = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            std.process.exit(0);
        }
    }

    return config;
}

fn printHelp() void {
    const help =
        \\Plue Native App (Zig)
        \\
        \\Usage: plue [options]
        \\
        \\Options:
        \\  --width <px>     Window width (default: 1400)
        \\  --height <px>    Window height (default: 900)
        \\  --port <port>    Astro dev server port (default: 5173)
        \\  --no-wait        Don't wait for server to be ready
        \\  -w, --webview    Use WebView instead of browser
        \\  -h, --help       Show this help message
        \\
        \\Make sure the Astro dev server is running:
        \\  bun run dev
        \\
    ;
    std.debug.print("{s}", .{help});
}

fn waitForServer(allocator: std.mem.Allocator, port: u16) !bool {
    var url_buf: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "localhost:{d}", .{port});

    std.debug.print("Waiting for http://{s} to be ready...\n", .{url});

    var attempt: u32 = 0;
    while (attempt < MAX_WAIT_ATTEMPTS) : (attempt += 1) {
        // Try to connect
        const stream = std.net.tcpConnectToHost(allocator, "localhost", port) catch {
            std.Thread.sleep(1 * std.time.ns_per_s);
            continue;
        };
        stream.close();

        std.debug.print("Server at http://{s} is ready!\n", .{url});
        return true;
    }

    std.debug.print("Server at http://{s} failed to start after {d} seconds\n", .{ url, MAX_WAIT_ATTEMPTS });
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const config = try parseArgs(allocator);

    // Wait for dev server if requested
    if (config.wait_for_server) {
        const ready = try waitForServer(allocator, config.port);
        if (!ready) {
            std.debug.print("Failed to connect to Astro dev server.\n", .{});
            std.debug.print("Make sure the server is running: bun run dev\n", .{});
            std.process.exit(1);
        }
    }

    // Build the URL (with null terminator)
    var url_buf: [64:0]u8 = undefined;
    const url_len = (std.fmt.bufPrint(&url_buf, "http://localhost:{d}", .{config.port}) catch unreachable).len;
    url_buf[url_len] = 0;
    const url: [:0]const u8 = url_buf[0..url_len :0];

    std.debug.print("Creating native window...\n", .{});

    // Create the window
    var win = webui.newWindow();

    // Configure window
    win.setSize(config.width, config.height);
    win.setIcon(plue_icon, "image/svg+xml");

    // Show the window
    if (config.use_webview) {
        win.showWv(url) catch {
            std.debug.print("Failed to open WebView window\n", .{});
            std.process.exit(1);
        };
    } else {
        win.show(url) catch {
            std.debug.print("Failed to open browser window\n", .{});
            std.process.exit(1);
        };
    }

    std.debug.print("Plue is running at {s}\n", .{url});
    std.debug.print("Close the browser window to exit.\n", .{});

    // Wait for window to close
    webui.wait();

    std.debug.print("Window closed. Goodbye!\n", .{});

    // Cleanup
    webui.clean();
}
