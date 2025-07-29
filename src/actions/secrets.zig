const std = @import("std");
const testing = std.testing;

// Secret management errors
pub const SecretError = error{
    SecretNotFound,
    InvalidEncryption,
    AccessDenied,
    WeakEncryptionKey,
    SecretTooLarge,
};

// Secret value with metadata
pub const Secret = struct {
    name: []const u8,
    value: []const u8,
    encrypted: bool = true,
    created_at: i64,
    accessed_at: ?i64 = null,
    access_count: u32 = 0,
    
    pub fn deinit(self: Secret, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

// Secret manager configuration
pub const SecretManagerConfig = struct {
    encryption_key: []const u8,
    max_secret_size: usize = 65536, // 64KB max
    enable_audit_logging: bool = true,
    mask_secrets_in_logs: bool = true,
};

// Mock encryption for testing - in real implementation use proper crypto
const MockEncryption = struct {
    pub fn encrypt(allocator: std.mem.Allocator, plaintext: []const u8, key: []const u8) ![]const u8 {
        _ = key;
        // Simple XOR "encryption" for testing
        const encrypted = try allocator.alloc(u8, plaintext.len);
        for (plaintext, 0..) |byte, i| {
            encrypted[i] = byte ^ 0x42; // XOR with constant
        }
        return encrypted;
    }
    
    pub fn decrypt(allocator: std.mem.Allocator, ciphertext: []const u8, key: []const u8) ![]const u8 {
        _ = key;
        // Simple XOR "decryption" for testing
        const decrypted = try allocator.alloc(u8, ciphertext.len);
        for (ciphertext, 0..) |byte, i| {
            decrypted[i] = byte ^ 0x42; // XOR with same constant
        }
        return decrypted;
    }
};

// Secret manager for secure secret injection and masking
pub const SecretManager = struct {
    allocator: std.mem.Allocator,
    config: SecretManagerConfig,
    secrets: std.StringHashMap(Secret),
    access_log: std.ArrayList(SecretAccessLog),
    
    const SecretAccessLog = struct {
        secret_name: []const u8,
        accessed_at: i64,
        context: []const u8, // job_id, step_name, etc.
    };
    
    pub fn init(allocator: std.mem.Allocator, config: SecretManagerConfig) !SecretManager {
        // Validate encryption key strength
        if (config.encryption_key.len < 32) {
            return SecretError.WeakEncryptionKey;
        }
        
        return SecretManager{
            .allocator = allocator,
            .config = SecretManagerConfig{
                .encryption_key = try allocator.dupe(u8, config.encryption_key),
                .max_secret_size = config.max_secret_size,
                .enable_audit_logging = config.enable_audit_logging,
                .mask_secrets_in_logs = config.mask_secrets_in_logs,
            },
            .secrets = std.StringHashMap(Secret).init(allocator),
            .access_log = std.ArrayList(SecretAccessLog).init(allocator),
        };
    }
    
    pub fn deinit(self: *SecretManager) void {
        self.allocator.free(self.config.encryption_key);
        
        // Clean up secrets
        var secrets_iter = self.secrets.iterator();
        while (secrets_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.secrets.deinit();
        
        // Clean up access log
        for (self.access_log.items) |log_entry| {
            self.allocator.free(log_entry.secret_name);
            self.allocator.free(log_entry.context);
        }
        self.access_log.deinit();
    }
    
    pub fn storeSecret(self: *SecretManager, name: []const u8, value: []const u8) !void {
        if (value.len > self.config.max_secret_size) {
            return SecretError.SecretTooLarge;
        }
        
        // Encrypt secret value
        const encrypted_value = try MockEncryption.encrypt(self.allocator, value, self.config.encryption_key);
        
        const secret = Secret{
            .name = try self.allocator.dupe(u8, name),
            .value = encrypted_value,
            .encrypted = true,
            .created_at = std.time.timestamp(),
        };
        
        const owned_name = try self.allocator.dupe(u8, name);
        try self.secrets.put(owned_name, secret);
    }
    
    pub fn getSecret(self: *SecretManager, name: []const u8, context: []const u8) ![]const u8 {
        var secret = self.secrets.getPtr(name) orelse {
            return SecretError.SecretNotFound;
        };
        
        // Decrypt secret value
        const decrypted_value = try MockEncryption.decrypt(self.allocator, secret.value, self.config.encryption_key);
        
        // Update access tracking
        secret.accessed_at = std.time.timestamp();
        secret.access_count += 1;
        
        // Log access if enabled
        if (self.config.enable_audit_logging) {
            try self.access_log.append(SecretAccessLog{
                .secret_name = try self.allocator.dupe(u8, name),
                .accessed_at = std.time.timestamp(),
                .context = try self.allocator.dupe(u8, context),
            });
        }
        
        return decrypted_value;
    }
    
    pub fn injectSecretsIntoEnvironment(
        self: *SecretManager,
        env: *std.StringHashMap([]const u8),
        secrets: std.StringHashMap([]const u8),
        context: []const u8,
    ) !void {
        var secrets_iter = secrets.iterator();
        while (secrets_iter.next()) |entry| {
            const secret_value = try self.getSecret(entry.value_ptr.*, context);
            try env.put(
                try self.allocator.dupe(u8, entry.key_ptr.*),
                secret_value,
            );
        }
    }
    
    pub fn maskSecretsInText(self: *SecretManager, text: []const u8) ![]const u8 {
        if (!self.config.mask_secrets_in_logs) {
            return try self.allocator.dupe(u8, text);
        }
        
        var masked_text = try self.allocator.dupe(u8, text);
        
        // Iterate through all secrets and mask their values
        var secrets_iter = self.secrets.iterator();
        while (secrets_iter.next()) |entry| {
            const secret = entry.value_ptr.*;
            
            // Decrypt secret to get plaintext for masking
            const plaintext = MockEncryption.decrypt(self.allocator, secret.value, self.config.encryption_key) catch continue;
            defer self.allocator.free(plaintext);
            
            // Only mask if secret is long enough to be meaningful
            if (plaintext.len >= 8) {
                // Replace all occurrences of secret with asterisks
                var search_pos: usize = 0;
                while (std.mem.indexOf(u8, masked_text[search_pos..], plaintext)) |pos| {
                    const abs_pos = search_pos + pos;
                    for (masked_text[abs_pos..abs_pos + plaintext.len]) |*byte| {
                        byte.* = '*';
                    }
                    search_pos = abs_pos + plaintext.len;
                }
            }
        }
        
        return masked_text;
    }
    
    pub fn getSecretNames(self: *SecretManager, allocator: std.mem.Allocator) ![][]const u8 {
        var names = std.ArrayList([]const u8).init(allocator);
        
        var secrets_iter = self.secrets.keyIterator();
        while (secrets_iter.next()) |name| {
            try names.append(try allocator.dupe(u8, name.*));
        }
        
        return names.toOwnedSlice();
    }
    
    pub fn removeSecret(self: *SecretManager, name: []const u8) !void {
        const removed = self.secrets.remove(name);
        if (removed) {
            self.allocator.free(removed.key);
            removed.value.deinit(self.allocator);
        } else {
            return SecretError.SecretNotFound;
        }
    }
    
    pub fn getAccessLog(self: *SecretManager, allocator: std.mem.Allocator) ![]SecretAccessLog {
        const log_copy = try allocator.alloc(SecretAccessLog, self.access_log.items.len);
        for (self.access_log.items, 0..) |log_entry, i| {
            log_copy[i] = SecretAccessLog{
                .secret_name = try allocator.dupe(u8, log_entry.secret_name),
                .accessed_at = log_entry.accessed_at,
                .context = try allocator.dupe(u8, log_entry.context),
            };
        }
        return log_copy;
    }
};

// Environment builder for secure execution
pub const ExecutionEnvironmentBuilder = struct {
    allocator: std.mem.Allocator,
    env: std.StringHashMap([]const u8),
    secret_manager: *SecretManager,
    context: []const u8,
    
    pub fn init(allocator: std.mem.Allocator, secret_manager: *SecretManager, context: []const u8) ExecutionEnvironmentBuilder {
        return ExecutionEnvironmentBuilder{
            .allocator = allocator,
            .env = std.StringHashMap([]const u8).init(allocator),
            .secret_manager = secret_manager,
            .context = context,
        };
    }
    
    pub fn deinit(self: *ExecutionEnvironmentBuilder) void {
        // Clean up environment variables (but not secrets - they're managed separately)
        var env_iter = self.env.iterator();
        while (env_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.env.deinit();
    }
    
    pub fn addEnvironmentVariable(self: *ExecutionEnvironmentBuilder, name: []const u8, value: []const u8) !void {
        try self.env.put(
            try self.allocator.dupe(u8, name),
            try self.allocator.dupe(u8, value)
        );
    }
    
    pub fn addSecret(self: *ExecutionEnvironmentBuilder, env_name: []const u8, secret_name: []const u8) !void {
        const secret_value = try self.secret_manager.getSecret(secret_name, self.context);
        try self.env.put(
            try self.allocator.dupe(u8, env_name),
            secret_value
        );
    }
    
    pub fn build(self: *ExecutionEnvironmentBuilder) !std.StringHashMap([]const u8) {
        // Return a copy of the environment
        var env_copy = std.StringHashMap([]const u8).init(self.allocator);
        
        var env_iter = self.env.iterator();
        while (env_iter.next()) |entry| {
            try env_copy.put(
                try self.allocator.dupe(u8, entry.key_ptr.*),
                try self.allocator.dupe(u8, entry.value_ptr.*)
            );
        }
        
        return env_copy;
    }
};

// Test encryption key for testing
const test_encryption_key = "this-is-a-very-secure-32-byte-key-for-testing-purposes-only!!";

// Tests for Phase 5: Secret Management and Security
test "secret manager stores and retrieves secrets securely" {
    const allocator = testing.allocator;
    
    var secret_manager = try SecretManager.init(allocator, .{
        .encryption_key = test_encryption_key,
        .enable_audit_logging = true,
    });
    defer secret_manager.deinit();
    
    // Store secrets
    try secret_manager.storeSecret("DATABASE_URL", "postgresql://user:secret@db:5432/app");
    try secret_manager.storeSecret("API_KEY", "super-secret-api-key-12345");
    
    // Retrieve secrets
    const db_url = try secret_manager.getSecret("DATABASE_URL", "job-123:step-connect");
    defer allocator.free(db_url);
    
    const api_key = try secret_manager.getSecret("API_KEY", "job-123:step-api-call");
    defer allocator.free(api_key);
    
    try testing.expectEqualStrings("postgresql://user:secret@db:5432/app", db_url);
    try testing.expectEqualStrings("super-secret-api-key-12345", api_key);
    
    // Verify audit logging
    const access_log = try secret_manager.getAccessLog(allocator);
    defer {
        for (access_log) |log_entry| {
            allocator.free(log_entry.secret_name);
            allocator.free(log_entry.context);
        }
        allocator.free(access_log);
    }
    
    try testing.expectEqual(@as(usize, 2), access_log.len);
    try testing.expectEqualStrings("DATABASE_URL", access_log[0].secret_name);
    try testing.expectEqualStrings("job-123:step-connect", access_log[0].context);
}

test "secret manager masks secrets in log output" {
    const allocator = testing.allocator;
    
    var secret_manager = try SecretManager.init(allocator, .{
        .encryption_key = test_encryption_key,
        .mask_secrets_in_logs = true,
    });
    defer secret_manager.deinit();
    
    // Store secrets
    try secret_manager.storeSecret("SECRET_TOKEN", "abc123def456");
    try secret_manager.storeSecret("PASSWORD", "mypassword123");
    
    // Test text with secrets
    const original_text = "Using token abc123def456 to authenticate with password mypassword123";
    
    const masked_text = try secret_manager.maskSecretsInText(original_text);
    defer allocator.free(masked_text);
    
    // Secrets should be masked
    try testing.expect(std.mem.indexOf(u8, masked_text, "abc123def456") == null);
    try testing.expect(std.mem.indexOf(u8, masked_text, "mypassword123") == null);
    try testing.expect(std.mem.indexOf(u8, masked_text, "***") != null);
}

test "execution environment builder creates secure environments" {
    const allocator = testing.allocator;
    
    var secret_manager = try SecretManager.init(allocator, .{
        .encryption_key = test_encryption_key,
        .enable_audit_logging = false,
    });
    defer secret_manager.deinit();
    
    // Store secrets
    try secret_manager.storeSecret("DB_PASSWORD", "super-secret-password");
    try secret_manager.storeSecret("API_TOKEN", "token-12345");
    
    var env_builder = ExecutionEnvironmentBuilder.init(allocator, &secret_manager, "job-456:step-build");
    defer env_builder.deinit();
    
    // Add regular environment variables
    try env_builder.addEnvironmentVariable("NODE_ENV", "production");
    try env_builder.addEnvironmentVariable("PORT", "3000");
    
    // Add secrets as environment variables
    try env_builder.addSecret("DATABASE_PASSWORD", "DB_PASSWORD");
    try env_builder.addSecret("AUTH_TOKEN", "API_TOKEN");
    
    // Build environment
    var env = try env_builder.build();
    defer {
        var env_iter = env.iterator();
        while (env_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env.deinit();
    }
    
    // Verify environment contains both regular vars and secrets
    try testing.expectEqualStrings("production", env.get("NODE_ENV").?);
    try testing.expectEqualStrings("3000", env.get("PORT").?);
    try testing.expectEqualStrings("super-secret-password", env.get("DATABASE_PASSWORD").?);
    try testing.expectEqualStrings("token-12345", env.get("AUTH_TOKEN").?);
    
    try testing.expectEqual(@as(usize, 4), env.count());
}

test "secret manager prevents access to non-existent secrets" {
    const allocator = testing.allocator;
    
    var secret_manager = try SecretManager.init(allocator, .{
        .encryption_key = test_encryption_key,
    });
    defer secret_manager.deinit();
    
    // Try to access non-existent secret
    const result = secret_manager.getSecret("NONEXISTENT_SECRET", "test-context");
    try testing.expectError(SecretError.SecretNotFound, result);
}

test "secret manager enforces encryption key strength" {
    const allocator = testing.allocator;
    
    // Try to create manager with weak key
    const weak_key = "short";
    const result = SecretManager.init(allocator, .{
        .encryption_key = weak_key,
    });
    
    try testing.expectError(SecretError.WeakEncryptionKey, result);
}

test "secret manager handles large secrets appropriately" {
    const allocator = testing.allocator;
    
    var secret_manager = try SecretManager.init(allocator, .{
        .encryption_key = test_encryption_key,
        .max_secret_size = 100, // Small limit for testing
    });
    defer secret_manager.deinit();
    
    // Create a large secret
    const large_secret = "x" ** 200; // 200 bytes, exceeds limit
    
    const result = secret_manager.storeSecret("LARGE_SECRET", large_secret);
    try testing.expectError(SecretError.SecretTooLarge, result);
}

test "secret manager tracks access count and timing" {
    const allocator = testing.allocator;
    
    var secret_manager = try SecretManager.init(allocator, .{
        .encryption_key = test_encryption_key,
        .enable_audit_logging = true,
    });
    defer secret_manager.deinit();
    
    try secret_manager.storeSecret("TEST_SECRET", "test-value");
    
    // Access secret multiple times
    {
        const value1 = try secret_manager.getSecret("TEST_SECRET", "context-1");
        defer allocator.free(value1);
    }
    {
        const value2 = try secret_manager.getSecret("TEST_SECRET", "context-2");
        defer allocator.free(value2);
    }
    {
        const value3 = try secret_manager.getSecret("TEST_SECRET", "context-3");
        defer allocator.free(value3);
    }
    
    // Check access tracking
    const secret = secret_manager.secrets.get("TEST_SECRET").?;
    try testing.expectEqual(@as(u32, 3), secret.access_count);
    try testing.expect(secret.accessed_at != null);
    try testing.expect(secret.accessed_at.? > secret.created_at);
    
    // Check audit log
    const access_log = try secret_manager.getAccessLog(allocator);
    defer {
        for (access_log) |log_entry| {
            allocator.free(log_entry.secret_name);
            allocator.free(log_entry.context);
        }
        allocator.free(access_log);
    }
    
    try testing.expectEqual(@as(usize, 3), access_log.len);
    try testing.expectEqualStrings("context-1", access_log[0].context);
    try testing.expectEqualStrings("context-2", access_log[1].context);
    try testing.expectEqualStrings("context-3", access_log[2].context);
}

test "secret manager can list and remove secrets" {
    const allocator = testing.allocator;
    
    var secret_manager = try SecretManager.init(allocator, .{
        .encryption_key = test_encryption_key,
    });
    defer secret_manager.deinit();
    
    // Store multiple secrets
    try secret_manager.storeSecret("SECRET_1", "value1");
    try secret_manager.storeSecret("SECRET_2", "value2");
    try secret_manager.storeSecret("SECRET_3", "value3");
    
    // List secrets
    const secret_names = try secret_manager.getSecretNames(allocator);
    defer {
        for (secret_names) |name| {
            allocator.free(name);
        }
        allocator.free(secret_names);
    }
    
    try testing.expectEqual(@as(usize, 3), secret_names.len);
    
    // Remove a secret
    try secret_manager.removeSecret("SECRET_2");
    
    // Verify it's gone
    const result = secret_manager.getSecret("SECRET_2", "test-context");
    try testing.expectError(SecretError.SecretNotFound, result);
    
    // But others remain
    const value1 = try secret_manager.getSecret("SECRET_1", "test-context");
    defer allocator.free(value1);
    try testing.expectEqualStrings("value1", value1);
}