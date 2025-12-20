//! Plue Grep CLI - Command-line interface for testing
//!
//! Usage: plue-grep [options] <pattern> [path]

const std = @import("std");
const lib = @import("lib.zig");

const SearchOptions = lib.SearchOptions;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    var pattern: ?[]const u8 = null;
    var path: []const u8 = ".";
    var options = SearchOptions{};

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--ignore-case")) {
            options.case_insensitive = true;
        } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--max-count")) {
            if (args.next()) |val| {
                options.max_results = std.fmt.parseInt(u32, val, 10) catch 0;
            }
        } else if (std.mem.eql(u8, arg, "-g") or std.mem.eql(u8, arg, "--glob")) {
            if (args.next()) |val| {
                options.glob = val;
            }
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--all")) {
            options.skip_hidden = false;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return;
        } else if (pattern == null) {
            pattern = arg;
        } else {
            path = arg;
        }
    }

    if (pattern == null) {
        std.debug.print("Error: No pattern specified\n\n", .{});
        printHelp();
        std.process.exit(1);
    }

    // Perform search
    var result = try lib.searchLiteral(allocator, path, pattern.?, options);
    defer result.deinit();

    // Print results
    if (result.matches.items.len == 0) {
        std.debug.print("No matches found\n", .{});
        return;
    }

    std.debug.print("Found {d} match{s}", .{
        result.matches.items.len,
        if (result.matches.items.len != 1) "es" else "",
    });

    if (result.truncated) {
        std.debug.print(" (truncated)", .{});
    }
    std.debug.print("\n\n", .{});

    var current_file: []const u8 = "";
    for (result.matches.items) |match| {
        if (!std.mem.eql(u8, current_file, match.path)) {
            if (current_file.len > 0) std.debug.print("\n", .{});
            current_file = match.path;
            std.debug.print("\x1b[35m{s}\x1b[0m:\n", .{match.path});
        }
        std.debug.print("  \x1b[32m{d}\x1b[0m: {s}\n", .{ match.line_number, match.line });
    }

    // Print errors if any
    if (result.errors.items.len > 0) {
        std.debug.print("\nErrors:\n", .{});
        for (result.errors.items) |err| {
            std.debug.print("  {s}\n", .{err});
        }
    }
}

fn printHelp() void {
    const help =
        \\plue-grep - Fast text search
        \\
        \\Usage: plue-grep [options] <pattern> [path]
        \\
        \\Arguments:
        \\  <pattern>    Text pattern to search for
        \\  [path]       Directory or file to search (default: .)
        \\
        \\Options:
        \\  -i, --ignore-case    Case-insensitive search
        \\  -n, --max-count N    Maximum number of results
        \\  -g, --glob PATTERN   File glob pattern (e.g., "*.zig")
        \\  -a, --all            Include hidden files
        \\  -h, --help           Show this help
        \\
        \\Examples:
        \\  plue-grep "TODO" src/
        \\  plue-grep -i "error" --glob "*.zig" .
        \\  plue-grep -n 10 "import" .
        \\
    ;
    std.debug.print("{s}", .{help});
}
