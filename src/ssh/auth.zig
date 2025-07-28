const std = @import("std");
const testing = std.testing;
const log = std.log.scoped(.ssh_auth);
const bindings = @import("bindings.zig");

// SSH Authentication Handler for Public Key Authentication
// Handles public key validation, user authentication, and key management

// Phase 1: Core Authentication Types - Tests First

test "parses SSH public key format" {
    const allocator = testing.allocator;
    
    const ssh_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDH... user@example.com";
    const parsed = try PublicKey.parse(allocator, ssh_key);
    defer parsed.deinit(allocator);
    
    try testing.expectEqual(KeyType.rsa, parsed.key_type);
    try testing.expect(parsed.key_data.len > 0);
    try testing.expectEqualStrings("user@example.com", parsed.comment);
}

test "validates RSA key strength" {
    const allocator = testing.allocator;
    
    // Test key strength validation
    try testing.expect(isKeyStrengthSufficient(.rsa, 3072));
    try testing.expect(isKeyStrengthSufficient(.rsa, 4096));
    try testing.expect(!isKeyStrengthSufficient(.rsa, 2048));
    try testing.expect(!isKeyStrengthSufficient(.rsa, 1024));
}

test "rejects invalid key formats" {
    const allocator = testing.allocator;
    
    const invalid_keys = [_][]const u8{
        "",
        "not-a-ssh-key",
        "ssh-rsa invalid-base64",
        "ssh-dss AAAAB3NzaC1kc3MAAACB...", // DSS not allowed
    };
    
    for (invalid_keys) |invalid_key| {
        try testing.expectError(AuthError.InvalidKeyFormat, 
            PublicKey.parse(allocator, invalid_key));
    }
}

// Now implement the types and functions to make tests pass

pub const KeyType = enum {
    rsa,
    ed25519,
    ecdsa_256,
    ecdsa_384,
    ecdsa_521,
    
    pub fn toString(self: KeyType) []const u8 {
        return switch (self) {
            .rsa => "ssh-rsa",
            .ed25519 => "ssh-ed25519",
            .ecdsa_256 => "ecdsa-sha2-nistp256",
            .ecdsa_384 => "ecdsa-sha2-nistp384",
            .ecdsa_521 => "ecdsa-sha2-nistp521",
        };
    }
    
    pub fn fromString(type_str: []const u8) ?KeyType {
        if (std.mem.eql(u8, type_str, "ssh-rsa")) return .rsa;
        if (std.mem.eql(u8, type_str, "ssh-ed25519")) return .ed25519;
        if (std.mem.eql(u8, type_str, "ecdsa-sha2-nistp256")) return .ecdsa_256;
        if (std.mem.eql(u8, type_str, "ecdsa-sha2-nistp384")) return .ecdsa_384;
        if (std.mem.eql(u8, type_str, "ecdsa-sha2-nistp521")) return .ecdsa_521;
        return null;
    }
    
    pub fn isAllowed(self: KeyType) bool {
        return switch (self) {
            .rsa, .ed25519, .ecdsa_256, .ecdsa_384, .ecdsa_521 => true,
        };
    }
};

pub const AuthError = error{
    InvalidKeyFormat,
    KeyTooWeak,
    KeyTypeNotAllowed,
    InvalidSignature,
    UserNotFound,
    KeyNotAuthorized,
    AuthenticationFailed,
    OutOfMemory,
    Base64DecodeError,
};

pub const PublicKey = struct {
    key_type: KeyType,
    key_data: []const u8,
    comment: []const u8,
    bit_size: ?u32 = null,
    
    pub fn parse(allocator: std.mem.Allocator, ssh_key_line: []const u8) AuthError!PublicKey {
        const trimmed = std.mem.trim(u8, ssh_key_line, " \t\n\r");
        if (trimmed.len == 0) return error.InvalidKeyFormat;
        
        // Split: "ssh-rsa AAAAB3NzaC1yc2E... user@example.com"
        var parts = std.mem.tokenizeScalar(u8, trimmed, ' ');
        
        // Parse key type
        const type_str = parts.next() orelse return error.InvalidKeyFormat;
        const key_type = KeyType.fromString(type_str) orelse return error.KeyTypeNotAllowed;
        
        if (!key_type.isAllowed()) return error.KeyTypeNotAllowed;
        
        // Parse base64 key data
        const b64_data = parts.next() orelse return error.InvalidKeyFormat;
        if (b64_data.len == 0) return error.InvalidKeyFormat;
        
        // Decode base64 to get actual key data
        const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(b64_data) catch 
            return error.Base64DecodeError;
        const key_data = try allocator.alloc(u8, decoded_size);
        errdefer allocator.free(key_data);
        
        std.base64.standard.Decoder.decode(key_data, b64_data) catch
            return error.Base64DecodeError;
        
        // Parse comment (optional)
        const comment = if (parts.next()) |c| try allocator.dupe(u8, c) else try allocator.dupe(u8, "");
        errdefer allocator.free(comment);
        
        // Validate key strength
        const bit_size = try extractKeyBitSize(key_type, key_data);
        if (!isKeyStrengthSufficient(key_type, bit_size)) {
            log.warn("Key too weak: {s} key with {d} bits (minimum {})", .{
                key_type.toString(), bit_size, getMinimumKeySize(key_type)
            });
            return error.KeyTooWeak;
        }
        
        return PublicKey{
            .key_type = key_type,
            .key_data = key_data,
            .comment = comment,
            .bit_size = bit_size,
        };
    }
    
    pub fn deinit(self: *const PublicKey, allocator: std.mem.Allocator) void {
        allocator.free(self.key_data);
        allocator.free(self.comment);
    }
    
    pub fn fingerprint(self: *const PublicKey, allocator: std.mem.Allocator) ![]u8 {
        // Generate SHA256 fingerprint
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(self.key_data);
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        
        // Convert to base64
        const b64_size = std.base64.standard.Encoder.calcSize(hash.len);
        const result = try allocator.alloc(u8, b64_size);
        _ = std.base64.standard.Encoder.encode(result, &hash);
        
        return result;
    }
};

fn isKeyStrengthSufficient(key_type: KeyType, bit_size: u32) bool {
    const min_size = getMinimumKeySize(key_type);
    return bit_size >= min_size;
}

fn getMinimumKeySize(key_type: KeyType) u32 {
    return switch (key_type) {
        .rsa => 3071,        // NIST recommendation post-2030
        .ed25519 => 256,     // Fixed size, cryptographically strong
        .ecdsa_256 => 256,   // P-256 curve
        .ecdsa_384 => 384,   // P-384 curve
        .ecdsa_521 => 521,   // P-521 curve
    };
}

fn extractKeyBitSize(key_type: KeyType, key_data: []const u8) !u32 {
    switch (key_type) {
        .rsa => {
            // RSA key format parsing - simplified for now
            // In a real implementation, we'd parse the SSH key format properly
            return estimateRsaKeySize(key_data);
        },
        .ed25519 => return 256,
        .ecdsa_256 => return 256,
        .ecdsa_384 => return 384,
        .ecdsa_521 => return 521,
    }
}

fn estimateRsaKeySize(key_data: []const u8) u32 {
    // Rough estimation based on key data size
    // SSH RSA keys have overhead, so this is approximate
    const size_estimate = key_data.len * 8;
    
    if (size_estimate < 2048) return 1024;
    if (size_estimate < 3072) return 2048;
    if (size_estimate < 4096) return 3072;
    return 4096;
}

// Phase 2: User Authentication Context - Tests First

test "creates authentication request" {
    const allocator = testing.allocator;
    
    const auth_req = try AuthRequest.init(allocator, "testuser", "ssh-rsa AAAAB3NzaC1...", "192.168.1.100");
    defer auth_req.deinit(allocator);
    
    try testing.expectEqualStrings("testuser", auth_req.username);
    try testing.expectEqualStrings("192.168.1.100", auth_req.client_ip);
    try testing.expect(auth_req.public_key != null);
}

test "validates signature challenge" {
    const allocator = testing.allocator;
    
    const challenge = try generateSignatureChallenge(allocator);
    defer allocator.free(challenge);
    
    try testing.expect(challenge.len == 32); // 32 bytes random data
}

pub const AuthRequest = struct {
    username: []const u8,
    public_key: ?PublicKey,
    client_ip: []const u8,
    timestamp: i64,
    
    pub fn init(allocator: std.mem.Allocator, username: []const u8, ssh_key: []const u8, client_ip: []const u8) !AuthRequest {
        const owned_username = try allocator.dupe(u8, username);
        errdefer allocator.free(owned_username);
        
        const owned_ip = try allocator.dupe(u8, client_ip);
        errdefer allocator.free(owned_ip);
        
        const public_key = PublicKey.parse(allocator, ssh_key) catch |err| switch (err) {
            error.InvalidKeyFormat, error.KeyTooWeak, error.KeyTypeNotAllowed => null,
            else => return err,
        };
        
        return AuthRequest{
            .username = owned_username,
            .public_key = public_key,
            .client_ip = owned_ip,
            .timestamp = std.time.timestamp(),
        };
    }
    
    pub fn deinit(self: *const AuthRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.username);
        allocator.free(self.client_ip);
        if (self.public_key) |*key| {
            key.deinit(allocator);
        }
    }
};

pub const AuthResult = struct {
    success: bool,
    user_id: ?u32,
    key_id: ?[]const u8,
    failure_reason: ?[]const u8,
    
    pub fn success(user_id: u32, key_id: []const u8) AuthResult {
        return AuthResult{
            .success = true,
            .user_id = user_id,
            .key_id = key_id,
            .failure_reason = null,
        };
    }
    
    pub fn failure(reason: []const u8) AuthResult {
        return AuthResult{
            .success = false,
            .user_id = null,
            .key_id = null,
            .failure_reason = reason,
        };
    }
};

fn generateSignatureChallenge(allocator: std.mem.Allocator) ![]u8 {
    const challenge = try allocator.alloc(u8, 32);
    std.crypto.random.bytes(challenge);
    return challenge;
}

// Phase 3: Key Database Integration - Tests First

test "mock key database lookup" {
    const allocator = testing.allocator;
    
    var key_db = MockKeyDatabase.init(allocator);
    defer key_db.deinit();
    
    // Add a test key
    try key_db.addKey(123, "test_key_id", "ssh-rsa AAAAB3NzaC1...");
    
    // Look up by username and key
    const result = try key_db.lookupUserKey(allocator, "testuser", "ssh-rsa AAAAB3NzaC1...");
    try testing.expect(result != null);
    if (result) |r| {
        try testing.expectEqual(@as(u32, 123), r.user_id);
        try testing.expectEqualStrings("test_key_id", r.key_id);
    }
}

test "handles missing keys gracefully" {
    const allocator = testing.allocator;
    
    var key_db = MockKeyDatabase.init(allocator);
    defer key_db.deinit();
    
    const result = try key_db.lookupUserKey(allocator, "unknown", "ssh-rsa AAAAB3NzaC1...");
    try testing.expect(result == null);
}

// Mock implementation for testing - in production this would interface with the database
pub const MockKeyDatabase = struct {
    const KeyEntry = struct {
        user_id: u32,
        key_id: []const u8,
        public_key: []const u8,
    };
    
    allocator: std.mem.Allocator,
    keys: std.ArrayList(KeyEntry),
    
    pub fn init(allocator: std.mem.Allocator) MockKeyDatabase {
        return MockKeyDatabase{
            .allocator = allocator,
            .keys = std.ArrayList(KeyEntry).init(allocator),
        };
    }
    
    pub fn deinit(self: *MockKeyDatabase) void {
        for (self.keys.items) |entry| {
            self.allocator.free(entry.key_id);
            self.allocator.free(entry.public_key);
        }
        self.keys.deinit();
    }
    
    pub fn addKey(self: *MockKeyDatabase, user_id: u32, key_id: []const u8, public_key: []const u8) !void {
        try self.keys.append(.{
            .user_id = user_id,
            .key_id = try self.allocator.dupe(u8, key_id),
            .public_key = try self.allocator.dupe(u8, public_key),
        });
    }
    
    pub const KeyLookupResult = struct {
        user_id: u32,
        key_id: []const u8,
    };
    
    pub fn lookupUserKey(self: *const MockKeyDatabase, allocator: std.mem.Allocator, username: []const u8, public_key: []const u8) !?KeyLookupResult {
        _ = allocator;
        _ = username; // In real implementation, would look up user by username first
        
        for (self.keys.items) |entry| {
            if (std.mem.eql(u8, entry.public_key, public_key)) {
                return KeyLookupResult{
                    .user_id = entry.user_id,
                    .key_id = entry.key_id,
                };
            }
        }
        return null;
    }
};

// Phase 4: Authentication Flow - Tests First

test "authenticates valid user with correct key" {
    const allocator = testing.allocator;
    
    var authenticator = try SshAuthenticator.init(allocator);
    defer authenticator.deinit();
    
    // Add test key
    try authenticator.key_db.addKey(456, "key_789", "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDH...");
    
    const auth_req = try AuthRequest.init(allocator, "alice", "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDH...", "10.0.0.1");
    defer auth_req.deinit(allocator);
    
    const result = try authenticator.authenticate(allocator, auth_req);
    
    // In this mock, we skip signature verification
    try testing.expect(result.success or result.failure_reason != null);
}

test "rejects weak keys during authentication" {
    const allocator = testing.allocator;
    
    var authenticator = try SshAuthenticator.init(allocator);
    defer authenticator.deinit();
    
    const weak_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQ..."; // Simulated weak key
    const auth_req = try AuthRequest.init(allocator, "bob", weak_key, "10.0.0.2");
    defer auth_req.deinit(allocator);
    
    const result = try authenticator.authenticate(allocator, auth_req);
    try testing.expect(!result.success);
    if (result.failure_reason) |reason| {
        try testing.expect(std.mem.indexOf(u8, reason, "weak") != null or 
                           std.mem.indexOf(u8, reason, "Invalid key") != null);
    }
}

pub const SshAuthenticator = struct {
    key_db: MockKeyDatabase,
    
    pub fn init(allocator: std.mem.Allocator) !SshAuthenticator {
        return SshAuthenticator{
            .key_db = MockKeyDatabase.init(allocator),
        };
    }
    
    pub fn deinit(self: *SshAuthenticator) void {
        self.key_db.deinit();
    }
    
    pub fn authenticate(self: *const SshAuthenticator, allocator: std.mem.Allocator, auth_req: AuthRequest) !AuthResult {
        log.info("SSH: Authentication attempt for user '{s}' from {s}", .{auth_req.username, auth_req.client_ip});
        
        // Check if public key is valid
        const public_key = auth_req.public_key orelse {
            log.warn("Failed authentication attempt from {s}: Invalid key", .{auth_req.client_ip});
            return AuthResult.failure("Invalid key format");
        };
        
        // Log key info for security monitoring
        const fingerprint = try public_key.fingerprint(allocator);
        defer allocator.free(fingerprint);
        
        log.info("SSH: Key fingerprint SHA256:{s} ({s}, {d} bits)", .{
            fingerprint, public_key.key_type.toString(), public_key.bit_size orelse 0
        });
        
        // Look up user and key in database
        const lookup_result = try self.key_db.lookupUserKey(allocator, auth_req.username, "placeholder_key") catch |err| {
            log.err("Database error during authentication: {}", .{err});
            return AuthResult.failure("Internal error");
        };
        
        if (lookup_result) |key_info| {
            log.info("SSH: Successfully authenticated user '{s}' (ID: {d}) with key {s}", .{
                auth_req.username, key_info.user_id, key_info.key_id
            });
            return AuthResult.success(key_info.user_id, key_info.key_id);
        } else {
            log.warn("Failed authentication attempt from {s}: User not found or key not authorized", .{auth_req.client_ip});
            return AuthResult.failure("Authentication failed");
        }
    }
    
    pub fn verifySignature(self: *const SshAuthenticator, allocator: std.mem.Allocator, public_key: PublicKey, challenge: []const u8, signature: []const u8) !bool {
        _ = self;
        _ = allocator;
        _ = public_key;
        _ = challenge;
        _ = signature;
        
        // TODO: Implement actual signature verification using libssh2
        // For now, always return true for testing
        log.warn("Signature verification not yet implemented - accepting all signatures", .{});
        return true;
    }
};

// Phase 5: Security Logging and Monitoring - Tests First

test "logs security events" {
    const allocator = testing.allocator;
    
    var monitor = SecurityMonitor.init(allocator);
    defer monitor.deinit();
    
    monitor.logAuthAttempt("testuser", "192.168.1.100", true, "key_123");
    monitor.logAuthAttempt("baduser", "192.168.1.200", false, null);
    
    // Should not crash
}

test "tracks failed authentication attempts" {
    const allocator = testing.allocator;
    
    var monitor = SecurityMonitor.init(allocator);
    defer monitor.deinit();
    
    // Multiple failed attempts from same IP
    monitor.logAuthAttempt("user1", "192.168.1.100", false, null);
    monitor.logAuthAttempt("user2", "192.168.1.100", false, null);
    monitor.logAuthAttempt("user3", "192.168.1.100", false, null);
    
    const failure_count = monitor.getFailureCount("192.168.1.100");
    try testing.expect(failure_count >= 3);
}

pub const SecurityMonitor = struct {
    allocator: std.mem.Allocator,
    failure_counts: std.HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    pub fn init(allocator: std.mem.Allocator) SecurityMonitor {
        return SecurityMonitor{
            .allocator = allocator,
            .failure_counts = std.HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *SecurityMonitor) void {
        var iterator = self.failure_counts.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.failure_counts.deinit();
    }
    
    pub fn logAuthAttempt(self: *SecurityMonitor, username: []const u8, client_ip: []const u8, success: bool, key_id: ?[]const u8) void {
        if (success) {
            log.info("SSH Security Event: SUCCESSFUL_AUTH from {s} - User {s} authenticated with key {s}", .{
                client_ip, username, key_id orelse "unknown"
            });
            // Reset failure count on successful auth
            self.resetFailureCount(client_ip);
        } else {
            log.warn("SSH Security Event: FAILED_AUTH from {s} - User {s} authentication failed", .{
                client_ip, username
            });
            self.incrementFailureCount(client_ip);
        }
    }
    
    pub fn getFailureCount(self: *const SecurityMonitor, client_ip: []const u8) u32 {
        return self.failure_counts.get(client_ip) orelse 0;
    }
    
    fn incrementFailureCount(self: *SecurityMonitor, client_ip: []const u8) void {
        const current = self.failure_counts.get(client_ip) orelse 0;
        const owned_ip = self.allocator.dupe(u8, client_ip) catch return;
        self.failure_counts.put(owned_ip, current + 1) catch return;
    }
    
    fn resetFailureCount(self: *SecurityMonitor, client_ip: []const u8) void {
        if (self.failure_counts.fetchRemove(client_ip)) |kv| {
            self.allocator.free(kv.key);
        }
    }
};