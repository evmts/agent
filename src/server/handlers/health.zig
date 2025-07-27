const std = @import("std");
const zap = @import("zap");
const server = @import("../server.zig");

const Context = server.Context;

pub fn indexHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    try r.sendBody("Hello World from Plue API Server!");
}

pub fn healthHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    try r.sendBody("healthy");
}