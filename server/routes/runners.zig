//! Runner routes (deprecated)
//!
//! Legacy runner APIs are deprecated in the new workflow engine. Use the
//! /internal/* endpoints for runner pool operations instead.

const httpz = @import("httpz");
const Context = @import("../main.zig").Context;

fn respondDeprecated(res: *httpz.Response) !void {
    res.status = 410;
    res.content_type = .JSON;
    try res.writer().writeAll("{\"error\":\"Runner API deprecated; use /internal/* endpoints\"}");
}

/// POST /runners/register
pub fn register(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    _ = ctx;
    _ = req;
    try respondDeprecated(res);
}

/// POST /runners/heartbeat
pub fn heartbeat(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    _ = ctx;
    _ = req;
    try respondDeprecated(res);
}

/// GET /runners/tasks/fetch
pub fn fetchTask(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    _ = ctx;
    _ = req;
    try respondDeprecated(res);
}

/// POST /runners/tasks/:taskId/status
pub fn updateTaskStatus(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    _ = ctx;
    _ = req;
    try respondDeprecated(res);
}

/// POST /runners/tasks/:taskId/logs
pub fn appendLogs(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    _ = ctx;
    _ = req;
    try respondDeprecated(res);
}

// =============================================================================
// Tests
// =============================================================================

test "runner routes compile" {
    _ = register;
    _ = heartbeat;
    _ = fetchTask;
    _ = updateTaskStatus;
    _ = appendLogs;
}
