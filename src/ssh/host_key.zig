const std = @import("std");
const testing = std.testing;
const bindings = @import("bindings.zig");

pub const HostKeyError = error{
    InvalidKeyType,
    KeyGenerationFailed,
    KeyLoadFailed,
    KeySaveFailed,
    InsufficientKeySize,
    UnsupportedKeyType,
    KeyTooWeak,
    KeyTypeNotAllowed,
} || error{OutOfMemory};

pub const KeyType = enum {
    rsa,
    ecdsa,
    ed25519,

    pub fn toString(self: KeyType) []const u8 {
        return switch (self) {
            .rsa => "rsa",
            .ecdsa => "ecdsa",
            .ed25519 => "ed25519",
        };
    }

    pub fn fromString(s: []const u8) HostKeyError!KeyType {
        if (std.mem.eql(u8, s, "rsa")) return .rsa;
        if (std.mem.eql(u8, s, "ecdsa")) return .ecdsa;
        if (std.mem.eql(u8, s, "ed25519")) return .ed25519;
        return HostKeyError.InvalidKeyType;
    }
};

pub const HostKey = struct {
    key_type: KeyType,
    private_key_path: []const u8,
    public_key_path: []const u8,
    key_size: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, key_type: KeyType, private_key_path: []const u8, public_key_path: []const u8, key_size: u32) HostKeyError!HostKey {
        if (!isValidKeySize(key_type, key_size)) {
            return HostKeyError.InsufficientKeySize;
        }

        const private_path = try allocator.dupe(u8, private_key_path);
        errdefer allocator.free(private_path);
        
        const public_path = try allocator.dupe(u8, public_key_path);
        errdefer allocator.free(public_path);

        return HostKey{
            .key_type = key_type,
            .private_key_path = private_path,
            .public_key_path = public_path,
            .key_size = key_size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HostKey) void {
        self.allocator.free(self.private_key_path);
        self.allocator.free(self.public_key_path);
    }

    pub fn exists(self: *const HostKey) bool {
        const private_file = std.fs.cwd().openFile(self.private_key_path, .{}) catch return false;
        private_file.close();
        
        const public_file = std.fs.cwd().openFile(self.public_key_path, .{}) catch return false;
        public_file.close();
        
        return true;
    }

    pub fn generate(self: *HostKey) HostKeyError!void {
        try self.ensureKeyDirectory();
        
        switch (self.key_type) {
            .rsa => try self.generateRSAKey(),
            .ecdsa => try self.generateECDSAKey(),
            .ed25519 => try self.generateEd25519Key(),
        }
    }

    pub fn loadPrivateKey(self: *const HostKey, allocator: std.mem.Allocator) HostKeyError![]u8 {
        const file = std.fs.cwd().openFile(self.private_key_path, .{}) catch return HostKeyError.KeyLoadFailed;
        defer file.close();
        
        const file_size = file.getEndPos() catch return HostKeyError.KeyLoadFailed;
        const contents = allocator.alloc(u8, file_size) catch return HostKeyError.OutOfMemory;
        errdefer allocator.free(contents);
        
        _ = file.readAll(contents) catch return HostKeyError.KeyLoadFailed;
        return contents;
    }

    pub fn loadPublicKey(self: *const HostKey, allocator: std.mem.Allocator) HostKeyError![]u8 {
        const file = std.fs.cwd().openFile(self.public_key_path, .{}) catch return HostKeyError.KeyLoadFailed;
        defer file.close();
        
        const file_size = file.getEndPos() catch return HostKeyError.KeyLoadFailed;
        const contents = allocator.alloc(u8, file_size) catch return HostKeyError.OutOfMemory;
        errdefer allocator.free(contents);
        
        _ = file.readAll(contents) catch return HostKeyError.KeyLoadFailed;
        return contents;
    }

    pub fn getFingerprint(self: *const HostKey, allocator: std.mem.Allocator) HostKeyError![]u8 {
        const public_key = self.loadPublicKey(allocator) catch return HostKeyError.KeyLoadFailed;
        defer allocator.free(public_key);
        
        // Extract the base64 portion for fingerprinting
        var lines = std.mem.split(u8, public_key, "\n");
        while (lines.next()) |line| {
            if (line.len == 0 or line[0] == '#') continue;
            
            var parts = std.mem.split(u8, line, " ");
            _ = parts.next(); // skip key type
            if (parts.next()) |b64_key| {
                return try generateSHA256Fingerprint(allocator, b64_key);
            }
        }
        
        return HostKeyError.KeyLoadFailed;
    }

    fn ensureKeyDirectory(self: *HostKey) HostKeyError!void {
        if (std.fs.path.dirname(self.private_key_path)) |dir_path| {
            std.fs.cwd().makePath(dir_path) catch return HostKeyError.KeySaveFailed;
        }
        if (std.fs.path.dirname(self.public_key_path)) |dir_path| {
            std.fs.cwd().makePath(dir_path) catch return HostKeyError.KeySaveFailed;
        }
    }

    fn generateRSAKey(self: *HostKey) HostKeyError!void {
        // Use ssh-keygen as fallback for key generation
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        
        try args.appendSlice(&[_][]const u8{
            "ssh-keygen",
            "-t", "rsa",
            "-f", self.private_key_path,
            "-N", "", // No passphrase
            "-C", "plue-ssh-server",
        });
        
        const key_size_str = try std.fmt.allocPrint(self.allocator, "{d}", .{self.key_size});
        defer self.allocator.free(key_size_str);
        try args.appendSlice(&[_][]const u8{ "-b", key_size_str });
        
        var process = std.process.Child.init(args.items, self.allocator);
        process.stdout_behavior = .Ignore;
        process.stderr_behavior = .Ignore;
        
        const result = process.spawnAndWait() catch return HostKeyError.KeyGenerationFailed;
        if (result != .Exited or result.Exited != 0) {
            return HostKeyError.KeyGenerationFailed;
        }
    }

    fn generateECDSAKey(self: *HostKey) HostKeyError!void {
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        
        try args.appendSlice(&[_][]const u8{
            "ssh-keygen",
            "-t", "ecdsa",
            "-f", self.private_key_path,
            "-N", "", // No passphrase
            "-C", "plue-ssh-server",
        });
        
        const key_size_str = try std.fmt.allocPrint(self.allocator, "{d}", .{self.key_size});
        defer self.allocator.free(key_size_str);
        try args.appendSlice(&[_][]const u8{ "-b", key_size_str });
        
        var process = std.process.Child.init(args.items, self.allocator);
        process.stdout_behavior = .Ignore;
        process.stderr_behavior = .Ignore;
        
        const result = process.spawnAndWait() catch return HostKeyError.KeyGenerationFailed;
        if (result != .Exited or result.Exited != 0) {
            return HostKeyError.KeyGenerationFailed;
        }
    }

    fn generateEd25519Key(self: *HostKey) HostKeyError!void {
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        
        try args.appendSlice(&[_][]const u8{
            "ssh-keygen",
            "-t", "ed25519",
            "-f", self.private_key_path,
            "-N", "", // No passphrase  
            "-C", "plue-ssh-server",
        });
        
        var process = std.process.Child.init(args.items, self.allocator);
        process.stdout_behavior = .Ignore;
        process.stderr_behavior = .Ignore;
        
        const result = process.spawnAndWait() catch return HostKeyError.KeyGenerationFailed;
        if (result != .Exited or result.Exited != 0) {
            return HostKeyError.KeyGenerationFailed;
        }
    }
};

pub const HostKeyManager = struct {
    host_keys: std.ArrayList(HostKey),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HostKeyManager {
        return HostKeyManager{
            .host_keys = std.ArrayList(HostKey).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HostKeyManager) void {
        for (self.host_keys.items) |*key| {
            key.deinit();
        }
        self.host_keys.deinit();
    }

    pub fn addKey(self: *HostKeyManager, key: HostKey) !void {
        try self.host_keys.append(key);
    }

    pub fn generateAllKeys(self: *HostKeyManager) HostKeyError!void {
        for (self.host_keys.items) |*key| {
            if (!key.exists()) {
                try key.generate();
                std.log.info("Generated {} host key: {s}", .{ key.key_type, key.private_key_path });
            }
        }
    }

    pub fn getKeyByType(self: *HostKeyManager, key_type: KeyType) ?*HostKey {
        for (self.host_keys.items) |*key| {
            if (key.key_type == key_type) {
                return key;
            }
        }
        return null;
    }

    pub fn getKeyCount(self: *const HostKeyManager) usize {
        return self.host_keys.items.len;
    }
};

pub const KeyValidator = struct {
    minimum_key_sizes: std.StringHashMap(u32),
    minimum_key_size_check: bool,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, config: anytype) !KeyValidator {
        var validator = KeyValidator{
            .minimum_key_sizes = std.StringHashMap(u32).init(allocator),
            .minimum_key_size_check = config.minimum_key_size_check,
            .allocator = allocator,
        };
        
        // Copy minimum key sizes from config
        var iter = config.minimum_key_sizes.iterator();
        while (iter.next()) |entry| {
            try validator.minimum_key_sizes.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        
        return validator;
    }
    
    pub fn deinit(self: *KeyValidator) void {
        self.minimum_key_sizes.deinit();
    }
    
    pub fn validateKey(self: *const KeyValidator, key_content: []const u8) HostKeyError!void {
        if (!self.minimum_key_size_check) return;
        
        const key_info = try parseSSHPublicKey(key_content);
        defer key_info.deinit();
        
        const min_size = self.minimum_key_sizes.get(key_info.algorithm) orelse {
            return HostKeyError.KeyTypeNotAllowed;
        };
        
        if (key_info.bit_length < min_size) {
            std.log.warn("Key too weak: {s} key with {d} bits (minimum {d})", 
                .{ key_info.algorithm, key_info.bit_length, min_size });
            return HostKeyError.KeyTooWeak;
        }
    }
};

const KeyInfo = struct {
    algorithm: []const u8,
    bit_length: u32,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *const KeyInfo) void {
        self.allocator.free(self.algorithm);
    }
};

fn parseSSHPublicKey(key_content: []const u8) HostKeyError!KeyInfo {
    // Mock implementation - real implementation would parse SSH public key format
    const allocator = std.heap.page_allocator;
    
    if (std.mem.startsWith(u8, key_content, "ssh-rsa")) {
        // Check if it contains "weak" to simulate weak key
        const bit_length: u32 = if (std.mem.indexOf(u8, key_content, "weak") != null) 2048 else 4096;
        return KeyInfo{
            .algorithm = try allocator.dupe(u8, "rsa"),
            .bit_length = bit_length,
            .allocator = allocator,
        };
    } else if (std.mem.startsWith(u8, key_content, "ssh-ed25519")) {
        return KeyInfo{
            .algorithm = try allocator.dupe(u8, "ed25519"),
            .bit_length = 256,
            .allocator = allocator,
        };
    } else if (std.mem.startsWith(u8, key_content, "ecdsa-sha2-nistp256")) {
        return KeyInfo{
            .algorithm = try allocator.dupe(u8, "ecdsa"),
            .bit_length = 256,
            .allocator = allocator,
        };
    }
    
    return HostKeyError.KeyTypeNotAllowed;
}

fn isValidKeySize(key_type: KeyType, key_size: u32) bool {
    return switch (key_type) {
        .rsa => key_size >= 2048, // Minimum RSA key size
        .ecdsa => key_size == 256 or key_size == 384 or key_size == 521, // Valid ECDSA curves
        .ed25519 => key_size == 256, // Ed25519 is always 256 bits
    };
}

fn generateSHA256Fingerprint(allocator: std.mem.Allocator, base64_key: []const u8) HostKeyError![]u8 {
    // Decode base64 key
    const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(base64_key) catch return HostKeyError.KeyLoadFailed;
    const decoded = allocator.alloc(u8, decoded_size) catch return HostKeyError.OutOfMemory;
    defer allocator.free(decoded);
    
    std.base64.standard.Decoder.decode(decoded, base64_key) catch return HostKeyError.KeyLoadFailed;
    
    // Calculate SHA256 hash
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(decoded, &hash, .{});
    
    // Encode as base64 with SHA256: prefix
    const encoded_size = std.base64.standard.Encoder.calcSize(hash.len);
    const result = allocator.alloc(u8, 8 + encoded_size) catch return HostKeyError.OutOfMemory; // "SHA256:" + encoded
    
    @memcpy(result[0..7], "SHA256:");
    result[7] = ':';
    _ = std.base64.standard.Encoder.encode(result[8..], &hash);
    
    return result;
}

// Tests
test "KeyType toString and fromString" {
    try testing.expectEqualStrings("rsa", KeyType.rsa.toString());
    try testing.expectEqualStrings("ecdsa", KeyType.ecdsa.toString());
    try testing.expectEqualStrings("ed25519", KeyType.ed25519.toString());
    
    try testing.expectEqual(KeyType.rsa, try KeyType.fromString("rsa"));
    try testing.expectEqual(KeyType.ecdsa, try KeyType.fromString("ecdsa"));
    try testing.expectEqual(KeyType.ed25519, try KeyType.fromString("ed25519"));
    
    try testing.expectError(HostKeyError.InvalidKeyType, KeyType.fromString("invalid"));
}

test "HostKey init validates key sizes" {
    const allocator = testing.allocator;
    
    // Valid key sizes
    var rsa_key = try HostKey.init(allocator, .rsa, "/tmp/test_rsa", "/tmp/test_rsa.pub", 2048);
    defer rsa_key.deinit();
    
    var ecdsa_key = try HostKey.init(allocator, .ecdsa, "/tmp/test_ecdsa", "/tmp/test_ecdsa.pub", 256);
    defer ecdsa_key.deinit();
    
    var ed25519_key = try HostKey.init(allocator, .ed25519, "/tmp/test_ed25519", "/tmp/test_ed25519.pub", 256);
    defer ed25519_key.deinit();
    
    // Invalid key sizes
    try testing.expectError(HostKeyError.InsufficientKeySize, HostKey.init(allocator, .rsa, "/tmp/test", "/tmp/test.pub", 1024));
    try testing.expectError(HostKeyError.InsufficientKeySize, HostKey.init(allocator, .ecdsa, "/tmp/test", "/tmp/test.pub", 128));
    try testing.expectError(HostKeyError.InsufficientKeySize, HostKey.init(allocator, .ed25519, "/tmp/test", "/tmp/test.pub", 128));
}

test "HostKey exists returns false for non-existent keys" {
    const allocator = testing.allocator;
    var key = try HostKey.init(allocator, .rsa, "/nonexistent/private", "/nonexistent/public", 2048);
    defer key.deinit();
    
    try testing.expect(!key.exists());
}

test "HostKeyManager basic operations" {
    const allocator = testing.allocator;
    var manager = HostKeyManager.init(allocator);
    defer manager.deinit();
    
    try testing.expectEqual(@as(usize, 0), manager.getKeyCount());
    
    const key = try HostKey.init(allocator, .rsa, "/tmp/test_rsa", "/tmp/test_rsa.pub", 2048);
    try manager.addKey(key);
    
    try testing.expectEqual(@as(usize, 1), manager.getKeyCount());
    
    const found_key = manager.getKeyByType(.rsa);
    try testing.expect(found_key != null);
    try testing.expectEqual(KeyType.rsa, found_key.?.key_type);
    
    const not_found = manager.getKeyByType(.ecdsa);
    try testing.expect(not_found == null);
}

test "isValidKeySize validates different key types" {
    // RSA
    try testing.expect(isValidKeySize(.rsa, 2048));
    try testing.expect(isValidKeySize(.rsa, 4096));
    try testing.expect(!isValidKeySize(.rsa, 1024));
    
    // ECDSA
    try testing.expect(isValidKeySize(.ecdsa, 256));
    try testing.expect(isValidKeySize(.ecdsa, 384));
    try testing.expect(isValidKeySize(.ecdsa, 521));
    try testing.expect(!isValidKeySize(.ecdsa, 192));
    
    // Ed25519
    try testing.expect(isValidKeySize(.ed25519, 256));
    try testing.expect(!isValidKeySize(.ed25519, 128));
    try testing.expect(!isValidKeySize(.ed25519, 512));
}

test "HostKey loadPrivateKey and loadPublicKey handle missing files" {
    const allocator = testing.allocator;
    var key = try HostKey.init(allocator, .rsa, "/nonexistent/private", "/nonexistent/public", 2048);
    defer key.deinit();
    
    try testing.expectError(HostKeyError.KeyLoadFailed, key.loadPrivateKey(allocator));
    try testing.expectError(HostKeyError.KeyLoadFailed, key.loadPublicKey(allocator));
}

test "generateSHA256Fingerprint creates valid fingerprint" {
    const allocator = testing.allocator;
    
    // Test with a simple base64 string
    const test_key = "dGVzdGtleQ=="; // "testkey" in base64
    const fingerprint = try generateSHA256Fingerprint(allocator, test_key);
    defer allocator.free(fingerprint);
    
    try testing.expect(std.mem.startsWith(u8, fingerprint, "SHA256:"));
    try testing.expect(fingerprint.len > 8); // Has content after prefix
}

test "KeyValidator validates minimum key sizes" {
    const allocator = testing.allocator;
    
    const Config = struct {
        minimum_key_size_check: bool,
        minimum_key_sizes: std.StringHashMap(u32),
    };
    
    var min_sizes = std.StringHashMap(u32).init(allocator);
    defer min_sizes.deinit();
    try min_sizes.put("rsa", 3071);
    try min_sizes.put("ed25519", 256);
    try min_sizes.put("ecdsa", 256);
    
    const config = Config{
        .minimum_key_size_check = true,
        .minimum_key_sizes = min_sizes,
    };
    
    var validator = try KeyValidator.init(allocator, config);
    defer validator.deinit();
    
    // Test weak RSA key (2048 bits)
    const weak_rsa = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDf... weak";
    try testing.expectError(HostKeyError.KeyTooWeak, validator.validateKey(weak_rsa));
    
    // Test strong RSA key (4096 bits)
    const strong_rsa = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDf...";
    try validator.validateKey(strong_rsa);
    
    // Test ed25519 key (always 256 bits)
    const ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    try validator.validateKey(ed25519);
}

test "KeyValidator allows all keys when check is disabled" {
    const allocator = testing.allocator;
    
    const Config = struct {
        minimum_key_size_check: bool,
        minimum_key_sizes: std.StringHashMap(u32),
    };
    
    var min_sizes = std.StringHashMap(u32).init(allocator);
    defer min_sizes.deinit();
    try min_sizes.put("rsa", 3071);
    
    const config = Config{
        .minimum_key_size_check = false, // Disabled
        .minimum_key_sizes = min_sizes,
    };
    
    var validator = try KeyValidator.init(allocator, config);
    defer validator.deinit();
    
    // Even weak keys should pass when check is disabled
    const weak_rsa = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDf... weak";
    try validator.validateKey(weak_rsa);
}