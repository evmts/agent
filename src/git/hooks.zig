const std = @import("std");
const testing = std.testing;

// Git reference update from post-receive hook
pub const RefUpdate = struct {
    old_sha: []const u8,
    new_sha: []const u8,
    ref_name: []const u8,
    ref_type: RefType,
    
    pub const RefType = enum {
        branch,
        tag,
        unknown,
        
        pub fn fromRefName(ref_name: []const u8) RefType {
            if (std.mem.startsWith(u8, ref_name, "refs/heads/")) return .branch;
            if (std.mem.startsWith(u8, ref_name, "refs/tags/")) return .tag;
            return .unknown;
        }
    };
    
    pub fn deinit(self: RefUpdate, allocator: std.mem.Allocator) void {
        allocator.free(self.old_sha);
        allocator.free(self.new_sha);
        allocator.free(self.ref_name);
    }
    
    pub fn isCreation(self: RefUpdate) bool {
        return std.mem.eql(u8, self.old_sha, "0000000000000000000000000000000000000000");
    }
    
    pub fn isDeletion(self: RefUpdate) bool {
        return std.mem.eql(u8, self.new_sha, "0000000000000000000000000000000000000000");
    }
    
    pub fn getBranchName(self: RefUpdate) ?[]const u8 {
        if (self.ref_type == .branch and std.mem.startsWith(u8, self.ref_name, "refs/heads/")) {
            return self.ref_name[11..]; // Remove "refs/heads/"
        }
        return null;
    }
    
    pub fn getTagName(self: RefUpdate) ?[]const u8 {
        if (self.ref_type == .tag and std.mem.startsWith(u8, self.ref_name, "refs/tags/")) {
            return self.ref_name[10..]; // Remove "refs/tags/"
        }
        return null;
    }
};