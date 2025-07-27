const std = @import("std");
const httpz = @import("httpz");
const server = @import("../server.zig");

const Context = server.Context;

pub fn indexHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.body = "Hello World from Plue API Server!";
}

pub fn healthHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.body = "healthy";
}