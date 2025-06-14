const std = @import("std");
const print = std.debug.print;

const FileWatcher = struct {
    allocator: std.mem.Allocator,
    project_root: []const u8,
    file_times: std.StringHashMap(i128),
    last_zig_build: i128,
    last_swift_build: i128,
    
    const Self = @This();
    
    fn init(allocator: std.mem.Allocator, project_root: []const u8) Self {
        return Self{
            .allocator = allocator,
            .project_root = project_root,
            .file_times = std.StringHashMap(i128).init(allocator),
            .last_zig_build = 0,
            .last_swift_build = 0,
        };
    }
    
    fn deinit(self: *Self) void {
        var iterator = self.file_times.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.file_times.deinit();
    }
    
    fn getFileModTime(_: *Self, file_path: []const u8) !i128 {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            if (err == error.FileNotFound) return 0;
            return err;
        };
        defer file.close();
        
        const stat = try file.stat();
        return stat.mtime;
    }
    
    fn scanDirectory(self: *Self, dir_path: []const u8, extension: []const u8) !bool {
        var has_changes = false;
        
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return false;
            return err;
        };
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .directory) {
                const sub_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer self.allocator.free(sub_path);
                
                const sub_changes = try self.scanDirectory(sub_path, extension);
                has_changes = has_changes or sub_changes;
            } else if (entry.kind == .file and std.mem.endsWith(u8, entry.name, extension)) {
                const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
                errdefer self.allocator.free(file_path);
                
                const current_mtime = try self.getFileModTime(file_path);
                const stored_path = try self.allocator.dupe(u8, file_path);
                errdefer self.allocator.free(stored_path);
                
                if (self.file_times.get(file_path)) |stored_mtime| {
                    self.allocator.free(file_path);
                    if (current_mtime > stored_mtime) {
                        try self.file_times.put(stored_path, current_mtime);
                        has_changes = true;
                        print("📝 Changed: {s}\n", .{stored_path});
                    }
                } else {
                    try self.file_times.put(stored_path, current_mtime);
                    has_changes = true;
                    print("➕ New: {s}\n", .{stored_path});
                }
            }
        }
        
        return has_changes;
    }
    
    fn checkForChanges(self: *Self) !struct { zig_changed: bool, swift_changed: bool } {
        const zig_changed = try self.scanDirectory("src", ".zig");
        const swift_changed = try self.scanDirectory("Sources", ".swift");
        
        return .{
            .zig_changed = zig_changed,
            .swift_changed = swift_changed,
        };
    }
    
    fn runZigBuild(self: *Self) !bool {
        print("🔨 Building Zig libraries...\n", .{});
        
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "zig", "build", "-Doptimize=Debug" },
            .cwd = self.project_root,
        }) catch |err| {
            print("❌ Zig build failed with error: {}\n", .{err});
            return false;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited == 0) {
            print("✅ Zig build completed successfully\n", .{});
            self.last_zig_build = std.time.nanoTimestamp();
            return true;
        } else {
            print("❌ Zig build failed:\n{s}\n", .{result.stderr});
            return false;
        }
    }
    
    fn runSwiftBuild(self: *Self) !bool {
        print("🍃 Building Swift application...\n", .{});
        
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "zig", "build", "swift" },
            .cwd = self.project_root,
        }) catch |err| {
            print("❌ Swift build failed with error: {}\n", .{err});
            return false;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited == 0) {
            print("✅ Swift build completed successfully\n", .{});
            self.last_swift_build = std.time.nanoTimestamp();
            return true;
        } else {
            print("❌ Swift build failed:\n{s}\n", .{result.stderr});
            return false;
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        print("Usage: dev_server <project_root>\n", .{});
        return;
    }
    
    const project_root = args[1];
    var watcher = FileWatcher.init(allocator, project_root);
    defer watcher.deinit();
    
    print("🚀 Plue Development Server Starting\n", .{});
    print("📁 Watching: {s}\n", .{project_root});
    print("👀 Monitoring .zig files in src/ and .swift files in Sources/\n", .{});
    print("⚡ Smart rebuilds: Zig changes → zig build, Swift changes → zig build swift\n", .{});
    print("🔄 Press Ctrl+C to stop\n\n", .{});
    
    // Initial build
    print("🔧 Initial build...\n", .{});
    _ = try watcher.runZigBuild();
    _ = try watcher.runSwiftBuild();
    print("\n📡 Watching for changes...\n\n", .{});
    
    // Watch loop
    while (true) {
        const changes = try watcher.checkForChanges();
        
        if (changes.zig_changed) {
            const success = try watcher.runZigBuild();
            if (success and changes.swift_changed) {
                // If Zig build succeeded and Swift also changed, rebuild Swift
                _ = try watcher.runSwiftBuild();
            }
        } else if (changes.swift_changed) {
            // Only Swift changed, just rebuild Swift
            _ = try watcher.runSwiftBuild();
        }
        
        // Sleep for 500ms to avoid excessive polling
        std.time.sleep(500 * std.time.ns_per_ms);
    }
}