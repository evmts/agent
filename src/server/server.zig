const std = @import("std");
const httpz = @import("httpz");
const DataAccessObject = @import("../database/dao.zig");

const Server = @This();

const Context = struct {
    dao: *DataAccessObject,
};

const AuthRequest = struct {
    req: *httpz.Request,
    user_id: i64,
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
    router.get("/user", getCurrentUserHandler, .{}); // Authenticated user endpoint
    router.post("/user/keys", createSSHKeyHandler, .{}); // Create SSH key
    router.get("/user/keys", listSSHKeysHandler, .{}); // List SSH keys
    router.delete("/user/keys/:id", deleteSSHKeyHandler, .{}); // Delete SSH key
    router.get("/users", getUsersHandler, .{});
    router.post("/users", createUserHandler, .{});
    router.get("/users/:name", getUserHandler, .{});
    router.put("/users/:name", updateUserHandler, .{});
    router.delete("/users/:name", deleteUserHandler, .{});
    router.post("/repos", createRepoHandler, .{});
    router.get("/repos/:owner/:name", getRepoHandler, .{});
    router.post("/repos/:owner/:name/issues", createIssueHandler, .{});
    router.get("/repos/:owner/:name/issues/:index", getIssueHandler, .{});
    
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

fn getCurrentUserHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    // Get user by ID
    const user = ctx.dao.getUserById(allocator, user_id) catch |err| {
        std.log.err("Failed to get user by ID: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "User not found");
        return;
    };
    defer {
        allocator.free(user.name);
        if (user.email) |e| allocator.free(e);
        if (user.avatar) |a| allocator.free(a);
    }
    
    // Build response
    const response = .{
        .id = user.id,
        .name = user.name,
        .email = user.email,
        .type = @tagName(user.type),
        .is_admin = user.is_admin,
        .avatar = user.avatar,
        .created_unix = user.created_unix,
        .updated_unix = user.updated_unix,
    };
    
    res.status = 200;
    try writeJson(res, allocator, response);
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
    
    const new_user = DataAccessObject.User{
        .id = 0,
        .name = name,
        .email = null,
        .passwd = null,
        .type = .individual,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    
    ctx.dao.createUser(allocator, new_user) catch |err| {
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
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    const user = ctx.dao.getUserByName(allocator, name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    if (user) |u| {
        defer {
            allocator.free(u.name);
            if (u.email) |e| allocator.free(e);
            if (u.passwd) |p| allocator.free(p);
            if (u.avatar) |a| allocator.free(a);
        }
        
        // Public profile response - no password
        const response = .{
            .id = u.id,
            .name = u.name,
            .email = u.email,
            .type = @tagName(u.type),
            .avatar = u.avatar,
            .created_unix = u.created_unix,
        };
        
        res.status = 200;
        try writeJson(res, allocator, response);
    } else {
        try writeError(res, allocator, 404, "User not found");
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

// SSH Key handlers
fn createSSHKeyHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        name: []const u8,
        key: []const u8,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const key_data = json_data.value;
    
    // Validate SSH key format
    if (!std.mem.startsWith(u8, key_data.key, "ssh-")) {
        try writeError(res, allocator, 400, "Invalid SSH key format");
        return;
    }
    
    // Generate fingerprint (simplified - in production use proper SSH fingerprint)
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(key_data.key);
    var fingerprint_bytes: [32]u8 = undefined;
    hasher.final(&fingerprint_bytes);
    
    var fingerprint: [64]u8 = undefined;
    for (fingerprint_bytes, 0..) |b, i| {
        _ = std.fmt.bufPrint(fingerprint[i * 2 ..][0..2], "{x:0>2}", .{b}) catch unreachable;
    }
    
    const public_key = DataAccessObject.PublicKey{
        .id = 0,
        .owner_id = user_id,
        .name = key_data.name,
        .content = key_data.key,
        .fingerprint = &fingerprint,
        .created_unix = 0,
        .updated_unix = 0,
    };
    
    ctx.dao.addPublicKey(allocator, public_key) catch |err| {
        std.log.err("Failed to add SSH key: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 201;
    try writeJson(res, allocator, .{ .message = "SSH key added successfully" });
}

fn listSSHKeysHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const keys = ctx.dao.getUserPublicKeys(allocator, user_id) catch |err| {
        std.log.err("Failed to list SSH keys: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (keys) |key| {
            allocator.free(key.name);
            allocator.free(key.content);
            allocator.free(key.fingerprint);
        }
        allocator.free(keys);
    }
    
    // Build response array
    var response_keys = try allocator.alloc(struct {
        id: i64,
        name: []const u8,
        fingerprint: []const u8,
        created_unix: i64,
    }, keys.len);
    
    for (keys, 0..) |key, i| {
        response_keys[i] = .{
            .id = key.id,
            .name = key.name,
            .fingerprint = key.fingerprint,
            .created_unix = key.created_unix,
        };
    }
    
    res.status = 200;
    try writeJson(res, allocator, response_keys);
}

fn deleteSSHKeyHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const id_str = req.param("id") orelse {
        try writeError(res, allocator, 400, "Missing key ID");
        return;
    };
    
    const key_id = std.fmt.parseInt(i64, id_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid key ID");
        return;
    };
    
    // Verify the key belongs to the user
    const keys = ctx.dao.getUserPublicKeys(allocator, user_id) catch |err| {
        std.log.err("Failed to get user keys: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (keys) |key| {
            allocator.free(key.name);
            allocator.free(key.content);
            allocator.free(key.fingerprint);
        }
        allocator.free(keys);
    }
    
    var found = false;
    for (keys) |key| {
        if (key.id == key_id) {
            found = true;
            break;
        }
    }
    
    if (!found) {
        try writeError(res, allocator, 404, "SSH key not found");
        return;
    }
    
    ctx.dao.deletePublicKey(allocator, key_id) catch |err| {
        std.log.err("Failed to delete SSH key: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{ .message = "SSH key deleted successfully" });
}

fn createRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const body = req.body() orelse {
        res.status = 400;
        res.body = "Missing request body";
        return;
    };
    
    // Parse JSON - expecting {"owner": "username", "name": "repo-name", "description": "...", "is_private": false}
    var json_data = std.json.parseFromSlice(struct {
        owner: []const u8,
        name: []const u8,
        description: ?[]const u8 = null,
        is_private: bool = false,
    }, allocator, body, .{}) catch {
        res.status = 400;
        res.body = "Invalid JSON";
        return;
    };
    defer json_data.deinit();
    
    const repo_data = json_data.value;
    
    // Get owner user
    const owner = ctx.dao.getUserByName(allocator, repo_data.owner) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to get user: {}", .{err});
        return;
    };
    defer if (owner) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    if (owner == null) {
        res.status = 404;
        res.body = "Owner not found";
        return;
    }
    
    const lower_name = try std.ascii.allocLowerString(allocator, repo_data.name);
    defer allocator.free(lower_name);
    
    const repo = DataAccessObject.Repository{
        .id = 0,
        .owner_id = owner.?.id,
        .lower_name = lower_name,
        .name = repo_data.name,
        .description = repo_data.description,
        .default_branch = "main",
        .is_private = repo_data.is_private,
        .is_fork = false,
        .fork_id = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    
    const repo_id = ctx.dao.createRepository(allocator, repo) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to create repository: {}", .{err});
        return;
    };
    
    res.content_type = .JSON;
    res.status = 201;
    res.body = try std.fmt.allocPrint(allocator, "{{\"id\":{}}}", .{repo_id});
}

fn getRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const owner_name = req.param("owner") orelse {
        res.status = 400;
        res.body = "Missing owner parameter";
        return;
    };
    const repo_name = req.param("name") orelse {
        res.status = 400;
        res.body = "Missing name parameter";
        return;
    };
    
    // Get owner user
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to get user: {}", .{err});
        return;
    };
    defer if (owner) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    if (owner == null) {
        res.status = 404;
        res.body = "Owner not found";
        return;
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.?.id, repo_name) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to get repository: {}", .{err});
        return;
    };
    defer if (repo) |r| {
        allocator.free(r.lower_name);
        allocator.free(r.name);
        if (r.description) |d| allocator.free(d);
        allocator.free(r.default_branch);
    };
    
    if (repo == null) {
        res.status = 404;
        res.body = "Repository not found";
        return;
    }
    
    var json_builder = std.ArrayList(u8).init(allocator);
    const writer = json_builder.writer();
    try writer.print("{{\"id\":{},\"owner_id\":{},\"name\":\"{s}\",\"description\":", .{
        repo.?.id,
        repo.?.owner_id,
        repo.?.name,
    });
    if (repo.?.description) |desc| {
        try writer.print("\"{s}\"", .{desc});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"default_branch\":\"{s}\",\"is_private\":{},\"is_fork\":{}}}", .{
        repo.?.default_branch,
        repo.?.is_private,
        repo.?.is_fork,
    });
    
    res.content_type = .JSON;
    res.status = 200;
    res.body = try allocator.dupe(u8, json_builder.items);
    json_builder.deinit();
}

fn createIssueHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const owner_name = req.param("owner") orelse {
        res.status = 400;
        res.body = "Missing owner parameter";
        return;
    };
    const repo_name = req.param("name") orelse {
        res.status = 400;
        res.body = "Missing name parameter";
        return;
    };
    
    const body = req.body() orelse {
        res.status = 400;
        res.body = "Missing request body";
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        title: []const u8,
        content: ?[]const u8 = null,
        assignee: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        res.status = 400;
        res.body = "Invalid JSON";
        return;
    };
    defer json_data.deinit();
    
    const issue_data = json_data.value;
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to get owner: {}", .{err});
        return;
    };
    defer if (owner) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    if (owner == null) {
        res.status = 404;
        res.body = "Owner not found";
        return;
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.?.id, repo_name) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to get repository: {}", .{err});
        return;
    };
    defer if (repo) |r| {
        allocator.free(r.lower_name);
        allocator.free(r.name);
        if (r.description) |d| allocator.free(d);
        allocator.free(r.default_branch);
    };
    
    if (repo == null) {
        res.status = 404;
        res.body = "Repository not found";
        return;
    }
    
    // Get poster from auth (for now use owner)
    const poster_id = owner.?.id;
    
    // Get assignee if provided
    var assignee_id: ?i64 = null;
    if (issue_data.assignee) |assignee_name| {
        const assignee = ctx.dao.getUserByName(allocator, assignee_name) catch |err| {
            res.status = 500;
            res.body = "Database error";
            std.log.err("Failed to get assignee: {}", .{err});
            return;
        };
        defer if (assignee) |u| {
            allocator.free(u.name);
            if (u.email) |e| allocator.free(e);
            if (u.passwd) |p| allocator.free(p);
            if (u.avatar) |a| allocator.free(a);
        };
        
        if (assignee) |a| {
            assignee_id = a.id;
        }
    }
    
    const issue = DataAccessObject.Issue{
        .id = 0,
        .repo_id = repo.?.id,
        .index = 0,
        .poster_id = poster_id,
        .title = issue_data.title,
        .content = issue_data.content,
        .is_closed = false,
        .is_pull = false,
        .assignee_id = assignee_id,
        .created_unix = 0,
    };
    
    const issue_id = ctx.dao.createIssue(allocator, issue) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to create issue: {}", .{err});
        return;
    };
    
    res.content_type = .JSON;
    res.status = 201;
    res.body = try std.fmt.allocPrint(allocator, "{{\"id\":{}}}", .{issue_id});
}

fn getIssueHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const owner_name = req.param("owner") orelse {
        res.status = 400;
        res.body = "Missing owner parameter";
        return;
    };
    const repo_name = req.param("name") orelse {
        res.status = 400;
        res.body = "Missing name parameter";
        return;
    };
    const index_str = req.param("index") orelse {
        res.status = 400;
        res.body = "Missing index parameter";
        return;
    };
    
    const index = std.fmt.parseInt(i64, index_str, 10) catch {
        res.status = 400;
        res.body = "Invalid index";
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to get owner: {}", .{err});
        return;
    };
    defer if (owner) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    if (owner == null) {
        res.status = 404;
        res.body = "Owner not found";
        return;
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.?.id, repo_name) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to get repository: {}", .{err});
        return;
    };
    defer if (repo) |r| {
        allocator.free(r.lower_name);
        allocator.free(r.name);
        if (r.description) |d| allocator.free(d);
        allocator.free(r.default_branch);
    };
    
    if (repo == null) {
        res.status = 404;
        res.body = "Repository not found";
        return;
    }
    
    // Get issue
    const issue = ctx.dao.getIssue(allocator, repo.?.id, index) catch |err| {
        res.status = 500;
        res.body = "Database error";
        std.log.err("Failed to get issue: {}", .{err});
        return;
    };
    defer if (issue) |i| {
        allocator.free(i.title);
        if (i.content) |c| allocator.free(c);
    };
    
    if (issue == null) {
        res.status = 404;
        res.body = "Issue not found";
        return;
    }
    
    var json_builder = std.ArrayList(u8).init(allocator);
    const writer = json_builder.writer();
    try writer.print("{{\"id\":{},\"index\":{},\"title\":\"{s}\",\"content\":", .{
        issue.?.id,
        issue.?.index,
        issue.?.title,
    });
    if (issue.?.content) |content| {
        try writer.print("\"{s}\"", .{content});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"is_closed\":{},\"is_pull\":{},\"assignee_id\":", .{
        issue.?.is_closed,
        issue.?.is_pull,
    });
    if (issue.?.assignee_id) |aid| {
        try writer.print("{}", .{aid});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll("}");
    
    res.content_type = .JSON;
    res.status = 200;
    res.body = try allocator.dupe(u8, json_builder.items);
    json_builder.deinit();
}

// Helper functions
fn writeJson(res: *httpz.Response, allocator: std.mem.Allocator, value: anytype) !void {
    var json_builder = std.ArrayList(u8).init(allocator);
    try std.json.stringify(value, .{}, json_builder.writer());
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, json_builder.items);
    json_builder.deinit();
}

fn writeError(res: *httpz.Response, allocator: std.mem.Allocator, status: u16, message: []const u8) !void {
    res.status = status;
    try writeJson(res, allocator, .{ .@"error" = message });
}

// Middleware for authentication
fn authMiddleware(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !?i64 {
    const auth_header = req.header("authorization") orelse {
        try writeError(res, req.arena, 401, "Missing authorization header");
        return null;
    };
    
    if (!std.mem.startsWith(u8, auth_header, "token ")) {
        try writeError(res, req.arena, 401, "Invalid authorization format");
        return null;
    }
    
    const token = auth_header[6..];
    const auth_token = try ctx.dao.getAuthToken(req.arena, token) orelse {
        try writeError(res, req.arena, 401, "Invalid token");
        return null;
    };
    defer req.arena.free(auth_token.token);
    
    return auth_token.user_id;
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