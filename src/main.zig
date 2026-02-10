//! smithers-ctl: CLI entry point for the Smithers IDE.
const std = @import("std");
const smithers = @import("smithers");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Minimal CLI stub: create/destroy app and print usage.
    const app = try smithers.ZigApi.createWith(alloc, .{});
    defer smithers.ZigApi.destroy(app);

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len <= 1) {
        std.debug.print("smithers-ctl: stub CLI. Run \"help\" for more info.\n", .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "help")) {
        std.debug.print("Commands will be wired in future tickets.\n", .{});
    } else {
        std.debug.print("unknown command: {s}\n", .{args[1]});
    }
}

// Keep a tiny test to ensure binary links.
test "main compiles" {
    _ = smithers;
}
