//! Security Test Suite
//!
//! Tests server-side security controls including:
//! - SQL injection prevention
//! - Path traversal prevention
//! - Input validation
//! - Authentication/authorization
//! - Rate limiting
//! - Token validation

// Re-export all security test modules
pub const csrf_test = @import("csrf_test.zig");
pub const injection_test = @import("injection_test.zig");
pub const auth_test = @import("auth_test.zig");
pub const path_traversal_test = @import("path_traversal_test.zig");
pub const rate_limit_test = @import("rate_limit_test.zig");

// Run all security tests
test {
    @import("std").testing.refAllDecls(@This());
}
