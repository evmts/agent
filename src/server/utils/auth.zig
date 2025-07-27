const std = @import("std");
const httpz = @import("httpz");
const json = @import("json.zig");

pub fn authMiddleware(ctx: anytype, req: *httpz.Request, res: *httpz.Response) !?i64 {
    const auth_header = req.header("authorization") orelse {
        try json.writeError(res, req.arena, 401, "Missing authorization header");
        return null;
    };
    
    if (!std.mem.startsWith(u8, auth_header, "token ")) {
        try json.writeError(res, req.arena, 401, "Invalid authorization format");
        return null;
    }
    
    const token = auth_header[6..];
    const auth_token = try ctx.dao.getAuthToken(req.arena, token) orelse {
        try json.writeError(res, req.arena, 401, "Invalid token");
        return null;
    };
    defer req.arena.free(auth_token.token);
    
    return auth_token.user_id;
}