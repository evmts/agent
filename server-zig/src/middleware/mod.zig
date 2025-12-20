//! Middleware module
//!
//! Re-exports all middleware for easy importing.

pub const auth = @import("auth.zig");
pub const rate_limit = @import("rate_limit.zig");
pub const cors = @import("cors.zig");
pub const security = @import("security.zig");
pub const body_limit = @import("body_limit.zig");
pub const logger = @import("logger.zig");

// Re-export commonly used types
pub const CorsConfig = cors.CorsConfig;
pub const SecurityConfig = security.SecurityConfig;
pub const BodyLimitConfig = body_limit.BodyLimitConfig;
pub const RateLimitConfig = rate_limit.RateLimitConfig;
pub const RateLimiter = rate_limit.RateLimiter;

// Re-export middleware functions
pub const authMiddleware = auth.authMiddleware;
pub const requireAuth = auth.requireAuth;
pub const requireActiveAccount = auth.requireActiveAccount;
pub const requireAdmin = auth.requireAdmin;
pub const corsMiddleware = cors.corsMiddleware;
pub const securityMiddleware = security.securityMiddleware;
pub const bodyLimitMiddleware = body_limit.bodyLimitMiddleware;
pub const loggerMiddleware = logger.simpleLoggerMiddleware;
pub const rateLimitMiddleware = rate_limit.rateLimitMiddleware;

// Re-export presets
pub const rate_limit_presets = rate_limit.presets;
pub const cors_default = cors.default_config;
pub const security_default = security.default_config;
pub const body_limit_default = body_limit.default_config;

test {
    @import("std").testing.refAllDecls(@This());
}
