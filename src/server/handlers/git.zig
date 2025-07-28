const std = @import("std");
const zap = @import("zap");
const GitCommand = @import("../../git/command.zig").GitCommand;

// Context should be imported from server
pub const Context = struct {
    allocator: std.mem.Allocator,
    dao: *anyopaque, // Replace with actual DAO type when integrated
};

// Phase 8: Integration with Server - Tests First

test "handles git smart HTTP info/refs request" {
    const allocator = std.testing.allocator;

    // Create test repo directory
    const tmp_dir_name = try std.fmt.allocPrint(allocator, "git_handler_test_{d}", .{std.crypto.random.int(u32)});
    defer allocator.free(tmp_dir_name);
    
    try std.fs.cwd().makeDir(tmp_dir_name);
    defer std.fs.cwd().deleteTree(tmp_dir_name) catch {};

    // Initialize git repo
    var git_cmd = try GitCommand.init(allocator);
    defer git_cmd.deinit(allocator);

    const init_result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{"init", "--bare"},
        .cwd = tmp_dir_name,
    });
    defer init_result.deinit(allocator);

    // Test context
    var ctx = Context{
        .allocator = allocator,
        .dao = undefined,
    };

    // Mock request
    const MockRequest = struct {
        path: []const u8,
        query: []const u8,
        method: []const u8 = "GET",
        response_body: ?[]const u8 = null,
        response_status: u16 = 200,
        response_content_type: ?[]const u8 = null,

        pub fn getQuery(self: *@This()) ?[]const []const u8 {
            _ = self;
            return &[_][]const u8{"service=git-upload-pack"};
        }

        pub fn setStatus(self: *@This(), status: u16) void {
            self.response_status = status;
        }

        pub fn setContentType(self: *@This(), content_type: []const u8) void {
            self.response_content_type = content_type;
        }

        pub fn sendBody(self: *@This(), body: []const u8) !void {
            self.response_body = body;
        }

        pub fn getParam(self: *@This(), name: []const u8) ?[]const u8 {
            _ = name;
            return self.path;
        }
    };

    var req = MockRequest{
        .path = tmp_dir_name,
        .query = "service=git-upload-pack",
    };

    try gitInfoRefsHandler(@ptrCast(&req), &ctx);

    try std.testing.expectEqualStrings("application/x-git-upload-pack-advertisement", req.response_content_type.?);
    try std.testing.expect(req.response_status == 200);
}

// Handler implementations

pub fn gitSmartHttpHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    const path = try r.getPath();

    if (std.mem.endsWith(u8, path, "/info/refs")) {
        try gitInfoRefsHandler(r, ctx);
    } else if (std.mem.endsWith(u8, path, "/git-upload-pack")) {
        try gitUploadPackHandler(r, ctx);
    } else if (std.mem.endsWith(u8, path, "/git-receive-pack")) {
        try gitReceivePackHandler(r, ctx);
    } else {
        try r.setStatus(.not_found);
        try r.sendBody("Not Found");
    }
}

fn gitInfoRefsHandler(r: anytype, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get service type from query
    const query = r.getQuery();
    var service: ?[]const u8 = null;
    
    if (query) |q| {
        for (q) |param| {
            if (std.mem.startsWith(u8, param, "service=")) {
                service = param[8..];
                break;
            }
        }
    }

    if (service == null) {
        try r.setStatus(400);
        try r.sendBody("service parameter required");
        return;
    }

    // Get repository path
    const repo_path = r.getParam("repo") orelse {
        try r.setStatus(404);
        try r.sendBody("Repository not found");
        return;
    };

    // Validate service type
    const is_upload = std.mem.eql(u8, service.?, "git-upload-pack");
    const is_receive = std.mem.eql(u8, service.?, "git-receive-pack");
    
    if (!is_upload and !is_receive) {
        try r.setStatus(400);
        try r.sendBody("Invalid service");
        return;
    }

    // Set content type
    const content_type = if (is_upload)
        "application/x-git-upload-pack-advertisement"
    else
        "application/x-git-receive-pack-advertisement";
    
    try r.setContentType(content_type);

    // Execute git command
    var git_cmd = try GitCommand.init(allocator);
    defer git_cmd.deinit(allocator);

    const cmd_name = if (is_upload) "upload-pack" else "receive-pack";
    const result = try git_cmd.runWithOptions(allocator, .{
        .args = &.{ cmd_name, "--stateless-rpc", "--advertise-refs", repo_path },
    });
    defer result.deinit(allocator);

    if (result.exit_code != 0) {
        try r.setStatus(500);
        try r.sendBody("Git command failed");
        return;
    }

    // Format response with service header
    var response = std.ArrayList(u8).init(allocator);
    defer response.deinit();

    const service_line = try std.fmt.allocPrint(allocator, "# service={s}\n", .{service.?});
    defer allocator.free(service_line);

    const pkt_len = try std.fmt.allocPrint(allocator, "{x:0>4}", .{service_line.len + 4});
    defer allocator.free(pkt_len);

    try response.appendSlice(pkt_len);
    try response.appendSlice(service_line);
    try response.appendSlice("0000"); // Flush packet
    try response.appendSlice(result.stdout);

    try r.sendBody(response.items);
}

fn gitUploadPackHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get repository path
    const repo_path = r.getParam("repo") orelse {
        try r.setStatus(.not_found);
        try r.sendBody("Repository not found");
        return;
    };

    // Read request body
    const body = try r.getBody();
    
    // Set content type
    try r.setContentType("application/x-git-upload-pack-result");

    // Execute git command with protocol context
    var git_cmd = try GitCommand.init(allocator);
    defer git_cmd.deinit(allocator);

    const result = try git_cmd.runWithProtocolContext(allocator, .{
        .args = &.{ "upload-pack", "--stateless-rpc", repo_path },
        .stdin = body,
        .protocol_context = .{
            .pusher_id = "1", // TODO: Get from auth
            .pusher_name = "anonymous", // TODO: Get from auth
            .repo_username = "owner", // TODO: Parse from path
            .repo_name = "repo", // TODO: Parse from path
            .is_wiki = false,
        },
    });
    defer result.deinit(allocator);

    if (result.exit_code != 0) {
        try r.setStatus(.internal_server_error);
        try r.sendBody("Git command failed");
        return;
    }

    try r.sendBody(result.stdout);
}

fn gitReceivePackHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get repository path
    const repo_path = r.getParam("repo") orelse {
        try r.setStatus(.not_found);
        try r.sendBody("Repository not found");
        return;
    };

    // TODO: Check write permissions

    // Read request body
    const body = try r.getBody();
    
    // Set content type
    try r.setContentType("application/x-git-receive-pack-result");

    // Execute git command with protocol context
    var git_cmd = try GitCommand.init(allocator);
    defer git_cmd.deinit(allocator);

    const result = try git_cmd.runWithProtocolContext(allocator, .{
        .args = &.{ "receive-pack", "--stateless-rpc", repo_path },
        .stdin = body,
        .protocol_context = .{
            .pusher_id = "1", // TODO: Get from auth
            .pusher_name = "anonymous", // TODO: Get from auth
            .repo_username = "owner", // TODO: Parse from path
            .repo_name = "repo", // TODO: Parse from path
            .is_wiki = false,
        },
    });
    defer result.deinit(allocator);

    if (result.exit_code != 0) {
        try r.setStatus(.internal_server_error);
        try r.sendBody("Git command failed");
        return;
    }

    try r.sendBody(result.stdout);
}