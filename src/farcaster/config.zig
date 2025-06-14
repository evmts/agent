const std = @import("std");

/// Retry policy for network operations
pub const RetryPolicy = struct {
    max_attempts: u32 = 3,
    base_delay_ms: u64 = 100,
    max_delay_ms: u64 = 5000,
    exponential_base: f32 = 2.0,
    
    pub fn shouldRetry(self: RetryPolicy, attempt: u32, err: anyerror) bool {
        if (attempt >= self.max_attempts) return false;
        
        return switch (err) {
            error.NetworkError,
            error.Timeout,
            error.HttpError,
            => true,
            else => false,
        };
    }
    
    pub fn getDelay(self: RetryPolicy, attempt: u32) u64 {
        const exp = std.math.pow(f32, self.exponential_base, @as(f32, @floatFromInt(attempt)));
        const delay = @as(u64, @intFromFloat(@as(f32, @floatFromInt(self.base_delay_ms)) * exp));
        return @min(delay, self.max_delay_ms);
    }
};

/// Rate limiting configuration
pub const RateLimitConfig = struct {
    max_requests: u32 = 100,
    window_ms: i64 = 60000, // 1 minute
    enabled: bool = true,
};

/// Client configuration with sensible defaults
pub const ClientConfig = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8 = "https://hub.pinata.cloud",
    user_fid: u64,
    private_key_hex: []const u8,
    retry_policy: RetryPolicy = .{},
    rate_limit: RateLimitConfig = .{},
    timeout_ms: u64 = 30000, // 30 seconds
    max_response_size: usize = 16 * 1024 * 1024, // 16MB
    
    /// Create configuration with validation
    pub fn init(allocator: std.mem.Allocator, user_fid: u64, private_key_hex: []const u8) !ClientConfig {
        // Validate private key format
        if (private_key_hex.len != 128) {
            std.log.err("Invalid private key length: {} (expected 128)", .{private_key_hex.len});
            return error.InvalidPrivateKey;
        }
        
        // Basic hex validation
        for (private_key_hex) |char| {
            if (!std.ascii.isHex(char)) {
                std.log.err("Invalid hex character in private key: {c}", .{char});
                return error.InvalidPrivateKey;
            }
        }
        
        return ClientConfig{
            .allocator = allocator,
            .user_fid = user_fid,
            .private_key_hex = private_key_hex,
        };
    }
    
    /// Builder pattern for configuration
    pub fn withBaseUrl(self: ClientConfig, url: []const u8) ClientConfig {
        var config = self;
        config.base_url = url;
        return config;
    }
    
    pub fn withTimeout(self: ClientConfig, timeout_ms: u64) ClientConfig {
        var config = self;
        config.timeout_ms = timeout_ms;
        return config;
    }
    
    pub fn withRetryPolicy(self: ClientConfig, policy: RetryPolicy) ClientConfig {
        var config = self;
        config.retry_policy = policy;
        return config;
    }
    
    pub fn withRateLimit(self: ClientConfig, rate_config: RateLimitConfig) ClientConfig {
        var config = self;
        config.rate_limit = rate_config;
        return config;
    }
};