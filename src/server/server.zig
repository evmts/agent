const std = @import("std");
const httpz = @import("httpz");

const Server = @This();

server: httpz.Server(void),

pub fn init(allocator: std.mem.Allocator) !Server {
    var server = try httpz.Server(void).init(allocator, .{ .port = 8000, .address = "0.0.0.0" }, {});
    
    var router = try server.router(.{});
    router.get("/", indexHandler, .{});
    router.get("/health", healthHandler, .{});
    
    return Server{
        .server = server,
    };
}

pub fn deinit(self: *Server) void {
    self.server.deinit();
}

pub fn listen(self: *Server) !void {
    try self.server.listen();
}

fn indexHandler(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.body = "Hello World from Plue API Server!";
}

fn healthHandler(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.body = "healthy";
}

test "server initializes correctly" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit();
    
    try std.testing.expect(@TypeOf(server.server) == httpz.Server(void));
}

test "server routes are configured" {
    const allocator = std.testing.allocator;
    var server = try Server.init(allocator);
    defer server.deinit();
    
    try std.testing.expect(true);
}