const std = @import("std");
const log = std.log.scoped(.ssh_database_auth);
const auth = @import("auth.zig");
const dao_module = @import("../database/dao.zig");

// Database-backed SSH key lookup for production use
pub const SshKeyDatabase = struct {
    dao: *dao_module,
    
    pub fn init(dao: *dao_module) SshKeyDatabase {
        return SshKeyDatabase{
            .dao = dao,
        };
    }
    
    pub fn deinit(self: *SshKeyDatabase) void {
        _ = self;
        // DAO is managed elsewhere, nothing to clean up here
    }
    
    pub const KeyLookupResult = struct {
        user_id: u32,
        key_id: []const u8,
    };
    
    pub fn lookupUserKey(self: *const SshKeyDatabase, allocator: std.mem.Allocator, username: []const u8, ssh_key_content: []const u8) !?KeyLookupResult {
        // First, get the user by username
        const user = self.dao.getUserByName(allocator, username) catch |err| {
            log.err("Database error looking up user '{s}': {}", .{username, err});
            return err;
        } orelse {
            log.warn("SSH authentication failed: user '{s}' not found", .{username});
            return null;
        };
        defer {
            allocator.free(user.name);
            if (user.email) |e| allocator.free(e);
            if (user.passwd) |p| allocator.free(p);
            if (user.avatar) |a| allocator.free(a);
        }
        
        // Get all public keys for the user
        const user_keys = self.dao.getUserPublicKeys(allocator, user.id) catch |err| {
            log.err("Database error getting public keys for user '{}': {}", .{user.id, err});
            return err;
        };
        defer {
            for (user_keys) |key| {
                allocator.free(key.name);
                allocator.free(key.content);
                allocator.free(key.fingerprint);
            }
            allocator.free(user_keys);
        }
        
        // Compare the provided SSH key content with stored keys
        for (user_keys) |key| {
            if (std.mem.eql(u8, key.content, ssh_key_content)) {
                // Found a matching key - create result with owned memory
                const key_id_str = try std.fmt.allocPrint(allocator, "{d}", .{key.id});
                
                return KeyLookupResult{
                    .user_id = @intCast(user.id),
                    .key_id = key_id_str,
                };
            }
        }
        
        log.warn("SSH authentication failed: no matching key found for user '{s}'", .{username});
        return null;
    }
    
    pub fn lookupUserById(self: *const SshKeyDatabase, allocator: std.mem.Allocator, user_id: u32) !?[]const u8 {
        const user = self.dao.getUserById(allocator, @intCast(user_id)) catch |err| {
            log.err("Database error looking up user ID {}: {}", .{user_id, err});
            return err;
        } orelse {
            log.warn("User ID {} not found", .{user_id});
            return null;
        };
        defer {
            if (user.email) |e| allocator.free(e);
            if (user.passwd) |p| allocator.free(p);
            if (user.avatar) |a| allocator.free(a);
        }
        
        // Return owned copy of username
        return try allocator.dupe(u8, user.name);
    }
};

// Type alias and helper function for database authenticator
pub const DatabaseSshAuthenticator = auth.SshAuthenticatorGeneric(SshKeyDatabase);

pub fn createDatabaseAuthenticator(dao: *dao_module) DatabaseSshAuthenticator {
    return DatabaseSshAuthenticator.init(SshKeyDatabase.init(dao));
}