const std = @import("std");
const httpz = @import("httpz");
const DataAccessObject = @import("../database/dao.zig");

const Server = @This();

const Context = struct {
    dao: *DataAccessObject,
};

server: httpz.Server(*Context),
context: *Context,

pub fn init(allocator: std.mem.Allocator, dao: *DataAccessObject) !Server {
    const context = try allocator.create(Context);
    context.* = Context{ .dao = dao };
    
    var server = try httpz.Server(*Context).init(allocator, .{ .port = 8000, .address = "0.0.0.0" }, context);
    
    var router = try server.router(.{});
    router.get("/", indexHandler, .{});
    router.get("/health", healthHandler, .{});
    router.get("/users", getUsersHandler, .{});
    router.post("/users", createUserHandler, .{});
    router.get("/users/:name", getUserHandler, .{});
    router.put("/users/:name", updateUserHandler, .{});
    router.delete("/users/:name", deleteUserHandler, .{});
    
    return Server{
        .server = server,
        .context = context,
    };
}

pub fn deinit(self: *Server, allocator: std.mem.Allocator) void {
    allocator.destroy(self.context);
    self.server.deinit();
}

pub fn listen(self: *Server) !void {
    try self.server.listen();
}

fn indexHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.body = "Hello World from Plue API Server!";
}

fn healthHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.body = "healthy";
}

fn getUsersHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const users = ctx.dao.listUsers(allocator) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to list users: {}", .{err});
        return;
    };
    defer {
        for (users) |user| {
            allocator.free(user.name);
        }
        allocator.free(users);
    }
    
    // Build JSON response
    var json_builder = std.ArrayList(u8).init(allocator);
    
    try json_builder.appendSlice("[");
    for (users, 0..) |user, i| {
        if (i > 0) try json_builder.appendSlice(",");
        try json_builder.writer().print("{{\"id\":{},\"name\":\"{s}\"}}", .{ user.id, user.name });
    }
    try json_builder.appendSlice("]");
    
    res.content_type = .JSON;
    res.status = 200;
    // Use allocator.dupe to ensure the memory stays valid
    res.body = try allocator.dupe(u8, json_builder.items);
    json_builder.deinit();
}

fn createUserHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const body = req.body() orelse {
        res.status = 400;
        res.body = "Missing request body";
        return;
    };
    
    // Simple JSON parsing for {"name": "username"}
    const name_start = std.mem.indexOf(u8, body, "\"name\"") orelse {
        res.status = 400;
        res.body = "Invalid JSON: missing name field";
        return;
    };
    
    // Find the colon after "name"
    const colon_pos = std.mem.indexOfPos(u8, body, name_start + 6, ":") orelse {
        res.status = 400;
        res.body = "Invalid JSON: missing colon after name";
        return;
    };
    
    // Find the opening quote of the value (skip whitespace)
    var quote_pos = colon_pos + 1;
    while (quote_pos < body.len and (body[quote_pos] == ' ' or body[quote_pos] == '\t')) : (quote_pos += 1) {}
    
    if (quote_pos >= body.len or body[quote_pos] != '"') {
        res.status = 400;
        res.body = "Invalid JSON: missing opening quote for value";
        return;
    }
    
    const name_value_start = quote_pos + 1;
    const name_end = std.mem.indexOfPos(u8, body, name_value_start, "\"") orelse {
        res.status = 400;
        res.body = "Invalid JSON: unterminated name field";
        return;
    };
    
    const name = body[name_value_start..name_end];
    
    ctx.dao.createUser(allocator, name) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to create user: {}", .{err});
        return;
    };
    
    res.status = 201;
    res.body = "User created";
}

fn getUserHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const name = req.param("name") orelse {
        res.status = 400;
        res.body = "Missing name parameter";
        return;
    };
    
    const user = ctx.dao.getUserByName(allocator, name) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to get user: {}", .{err});
        return;
    };
    
    if (user) |u| {
        defer allocator.free(u.name);
        
        var json_builder = std.ArrayList(u8).init(allocator);
        
        try json_builder.writer().print("{{\"id\":{},\"name\":\"{s}\"}}", .{ u.id, u.name });
        
        res.content_type = .JSON;
        res.status = 200;
        res.body = try allocator.dupe(u8, json_builder.items);
        json_builder.deinit();
    } else {
        res.status = 404;
        res.body = "User not found";
    }
}

fn updateUserHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const old_name = req.param("name") orelse {
        res.status = 400;
        res.body = "Missing name parameter";
        return;
    };
    
    const body = req.body() orelse {
        res.status = 400;
        res.body = "Missing request body";
        return;
    };
    
    // Simple JSON parsing for {"name": "new_username"}
    const name_start = std.mem.indexOf(u8, body, "\"name\"") orelse {
        res.status = 400;
        res.body = "Invalid JSON: missing name field";
        return;
    };
    
    // Find the colon after "name"
    const colon_pos = std.mem.indexOfPos(u8, body, name_start + 6, ":") orelse {
        res.status = 400;
        res.body = "Invalid JSON: missing colon after name";
        return;
    };
    
    // Find the opening quote of the value (skip whitespace)
    var quote_pos = colon_pos + 1;
    while (quote_pos < body.len and (body[quote_pos] == ' ' or body[quote_pos] == '\t')) : (quote_pos += 1) {}
    
    if (quote_pos >= body.len or body[quote_pos] != '"') {
        res.status = 400;
        res.body = "Invalid JSON: missing opening quote for value";
        return;
    }
    
    const name_value_start = quote_pos + 1;
    const name_end = std.mem.indexOfPos(u8, body, name_value_start, "\"") orelse {
        res.status = 400;
        res.body = "Invalid JSON: unterminated name field";
        return;
    };
    
    const new_name = body[name_value_start..name_end];
    
    ctx.dao.updateUserName(allocator, old_name, new_name) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to update user: {}", .{err});
        return;
    };
    
    res.status = 200;
    res.body = "User updated";
}

fn deleteUserHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const name = req.param("name") orelse {
        res.status = 400;
        res.body = "Missing name parameter";
        return;
    };
    
    ctx.dao.deleteUser(allocator, name) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to delete user: {}", .{err});
        return;
    };
    
    res.status = 200;
    res.body = "User deleted";
}

test "server initializes correctly" {
    const allocator = std.testing.allocator;
    
    // Create a mock DAO for testing
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available for testing, skipping server test", .{});
        return;
    };
    defer dao.deinit();
    
    var server = try Server.init(allocator, &dao);
    defer server.deinit(allocator);
    
    try std.testing.expect(@TypeOf(server.server) == httpz.Server(*Context));
}

test "server routes are configured" {
    const allocator = std.testing.allocator;
    
    // Create a mock DAO for testing
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available for testing, skipping server test", .{});
        return;
    };
    defer dao.deinit();
    
    var server = try Server.init(allocator, &dao);
    defer server.deinit(allocator);
    
    try std.testing.expect(true);
}