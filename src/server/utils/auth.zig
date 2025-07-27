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