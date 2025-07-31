const std = @import("std");
const zap = @import("zap");
const json = @import("json.zig");

pub fn authMiddleware(r: zap.Request, ctx: anytype, allocator: std.mem.Allocator) !?i64 {
    const auth_header = r.getHeader("authorization") orelse {
        try json.writeError(r, allocator, .unauthorized, "Missing authorization header");
        return null;
    };
    
    if (!std.mem.startsWith(u8, auth_header, "token ")) {
        try json.writeError(r, allocator, .unauthorized, "Invalid authorization format");
        return null;
    }
    
    const token = auth_header[6..];
    const auth_token = try ctx.dao.getAuthToken(allocator, token) orelse {
        try json.writeError(r, allocator, .unauthorized, "Invalid token");
        return null;
    };
    defer allocator.free(auth_token.token);
    
    return auth_token.user_id;
}

pub const AuthResult = struct {
    user_id: i64,
    
    pub fn deinit(self: *AuthResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub fn authenticateRequest(r: zap.Request, allocator: std.mem.Allocator) !AuthResult {
    const auth_header = r.getHeader("authorization") orelse {
        return error.Unauthorized;
    };
    
    if (!std.mem.startsWith(u8, auth_header, "token ")) {
        return error.Unauthorized;
    }
    
    // Simple mock authentication - in real implementation would validate token
    _ = allocator;
    return AuthResult{
        .user_id = 1, // Mock user ID
    };
}