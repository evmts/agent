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
    router.post("/orgs", createOrgHandler, .{}); // Create organization
    router.get("/orgs/:org", getOrgHandler, .{}); // Get organization
    router.patch("/orgs/:org", updateOrgHandler, .{}); // Update organization
    router.delete("/orgs/:org", deleteOrgHandler, .{}); // Delete organization
    router.get("/orgs/:org/members", listOrgMembersHandler, .{}); // List org members
    router.delete("/orgs/:org/members/:username", removeOrgMemberHandler, .{}); // Remove member
    router.get("/user/orgs", listUserOrgsHandler, .{}); // List user's organizations
    router.post("/user/repos", createUserRepoHandler, .{}); // Create user repository
    router.post("/orgs/:org/repos", createOrgRepoHandler, .{}); // Create org repository
    router.get("/repos/:owner/:name", getRepoHandler, .{});
    router.patch("/repos/:owner/:name", updateRepoHandler, .{}); // Update repository
    router.delete("/repos/:owner/:name", deleteRepoHandler, .{}); // Delete repository
    router.post("/repos/:owner/:name/forks", forkRepoHandler, .{}); // Fork repository
    router.get("/repos/:owner/:name/branches", listBranchesHandler, .{}); // List branches
    router.get("/repos/:owner/:name/branches/:branch", getBranchHandler, .{}); // Get branch
    router.post("/repos/:owner/:name/branches", createBranchHandler, .{}); // Create branch
    router.delete("/repos/:owner/:name/branches/:branch", deleteBranchHandler, .{}); // Delete branch
    router.get("/repos/:owner/:name/issues", listIssuesHandler, .{}); // List issues
    router.post("/repos/:owner/:name/issues", createIssueHandler, .{});
    router.get("/repos/:owner/:name/issues/:index", getIssueHandler, .{});
    router.patch("/repos/:owner/:name/issues/:index", updateIssueHandler, .{}); // Update issue
    router.get("/repos/:owner/:name/issues/:index/comments", getCommentsHandler, .{}); // List comments
    router.post("/repos/:owner/:name/issues/:index/comments", createCommentHandler, .{}); // Add comment
    router.get("/repos/:owner/:name/labels", listLabelsHandler, .{}); // List labels
    router.post("/repos/:owner/:name/labels", createLabelHandler, .{}); // Create label
    router.patch("/repos/:owner/:name/labels/:id", updateLabelHandler, .{}); // Update label
    router.delete("/repos/:owner/:name/labels/:id", deleteLabelHandler, .{}); // Delete label
    router.post("/repos/:owner/:name/issues/:index/labels", addLabelsToIssueHandler, .{}); // Add labels to issue
    router.delete("/repos/:owner/:name/issues/:index/labels/:id", removeLabelFromIssueHandler, .{}); // Remove label from issue
    router.get("/repos/:owner/:name/pulls", listPullsHandler, .{}); // List pull requests
    router.post("/repos/:owner/:name/pulls", createPullHandler, .{}); // Create pull request
    router.get("/repos/:owner/:name/pulls/:index", getPullHandler, .{}); // Get pull request
    router.get("/repos/:owner/:name/pulls/:index/reviews", listReviewsHandler, .{}); // List reviews
    router.post("/repos/:owner/:name/pulls/:index/reviews", createReviewHandler, .{}); // Submit review
    router.post("/repos/:owner/:name/pulls/:index/merge", mergePullHandler, .{}); // Merge PR
    
    // Actions/CI endpoints
    router.get("/repos/:owner/:name/actions/runs", listRunsHandler, .{}); // List workflow runs
    router.get("/repos/:owner/:name/actions/runs/:run_id", getRunHandler, .{}); // Get workflow run
    router.get("/repos/:owner/:name/actions/runs/:run_id/jobs", listJobsHandler, .{}); // List jobs for run
    router.get("/repos/:owner/:name/actions/runs/:run_id/artifacts", listArtifactsHandler, .{}); // List artifacts for run
    router.get("/repos/:owner/:name/actions/artifacts/:artifact_id", getArtifactHandler, .{}); // Get artifact
    router.get("/orgs/:org/actions/secrets", listOrgSecretsHandler, .{}); // List org secrets
    router.put("/orgs/:org/actions/secrets/:secretname", createOrgSecretHandler, .{}); // Create/update org secret
    router.delete("/orgs/:org/actions/secrets/:secretname", deleteOrgSecretHandler, .{}); // Delete org secret
    router.get("/repos/:owner/:name/actions/secrets", listRepoSecretsHandler, .{}); // List repo secrets
    router.put("/repos/:owner/:name/actions/secrets/:secretname", createRepoSecretHandler, .{}); // Create/update repo secret
    router.delete("/repos/:owner/:name/actions/secrets/:secretname", deleteRepoSecretHandler, .{}); // Delete repo secret
    router.get("/orgs/:org/actions/runners", listOrgRunnersHandler, .{}); // List org runners
    router.get("/repos/:owner/:name/actions/runners", listRepoRunnersHandler, .{}); // List repo runners
    router.get("/orgs/:org/actions/runners/registration-token", getOrgRunnerTokenHandler, .{}); // Get org runner token
    router.get("/repos/:owner/:name/actions/runners/registration-token", getRepoRunnerTokenHandler, .{}); // Get repo runner token
    router.delete("/orgs/:org/actions/runners/:runner_id", deleteOrgRunnerHandler, .{}); // Delete org runner
    router.delete("/repos/:owner/:name/actions/runners/:runner_id", deleteRepoRunnerHandler, .{}); // Delete repo runner
    
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

// Organization handlers
fn createOrgHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        description: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const org_data = json_data.value;
    
    // Create organization as a user with type=organization
    const org = DataAccessObject.User{
        .id = 0,
        .name = org_data.name,
        .email = null,
        .passwd = null,
        .type = .organization,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    
    ctx.dao.createUser(allocator, org) catch |err| {
        std.log.err("Failed to create organization: {}", .{err});
        // Check if it's a duplicate name error
        if (err == error.DatabaseError) {
            try writeError(res, allocator, 409, "Organization name already exists");
        } else {
            try writeError(res, allocator, 500, "Database error");
        }
        return;
    };
    
    // Get the created org to get its ID
    const created_org = ctx.dao.getUserByName(allocator, org_data.name) catch |err| {
        std.log.err("Failed to get created org: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 500, "Failed to retrieve created organization");
        return;
    };
    defer {
        allocator.free(created_org.name);
        if (created_org.email) |e| allocator.free(e);
        if (created_org.passwd) |p| allocator.free(p);
        if (created_org.avatar) |a| allocator.free(a);
    }
    
    // Add the creator as owner
    ctx.dao.addUserToOrg(allocator, user_id, created_org.id, true) catch |err| {
        std.log.err("Failed to add user as org owner: {}", .{err});
        // Try to clean up the org
        ctx.dao.deleteUser(allocator, org_data.name) catch {};
        try writeError(res, allocator, 500, "Failed to set organization owner");
        return;
    };
    
    res.status = 201;
    try writeJson(res, allocator, .{
        .id = created_org.id,
        .name = created_org.name,
        .type = "organization",
    });
}

fn getOrgHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing organization name");
        return;
    };
    
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    if (org) |o| {
        defer {
            allocator.free(o.name);
            if (o.email) |e| allocator.free(e);
            if (o.passwd) |p| allocator.free(p);
            if (o.avatar) |a| allocator.free(a);
        }
        
        if (o.type != .organization) {
            try writeError(res, allocator, 404, "Organization not found");
            return;
        }
        
        res.status = 200;
        try writeJson(res, allocator, .{
            .id = o.id,
            .name = o.name,
            .avatar = o.avatar,
            .created_unix = o.created_unix,
        });
    } else {
        try writeError(res, allocator, 404, "Organization not found");
    }
}

fn updateOrgHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing organization name");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Get the organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.passwd) |p| allocator.free(p);
        if (org.avatar) |a| allocator.free(a);
    }
    
    if (org.type != .organization) {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Check if user is owner
    const members = ctx.dao.getOrgUsers(allocator, org.id) catch |err| {
        std.log.err("Failed to get org members: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer allocator.free(members);
    
    var is_owner = false;
    for (members) |member| {
        if (member.uid == user_id and member.is_owner) {
            is_owner = true;
            break;
        }
    }
    
    if (!is_owner) {
        try writeError(res, allocator, 403, "Only organization owners can update settings");
        return;
    }
    
    // Parse update data
    var json_data = std.json.parseFromSlice(struct {
        description: ?[]const u8 = null,
        avatar: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    // For now we only support updating avatar
    if (json_data.value.avatar) |avatar| {
        ctx.dao.updateUserAvatar(allocator, org.id, avatar) catch |err| {
            std.log.err("Failed to update org avatar: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
    }
    
    res.status = 200;
    try writeJson(res, allocator, .{ .message = "Organization updated successfully" });
}

fn deleteOrgHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing organization name");
        return;
    };
    
    // Get the organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.passwd) |p| allocator.free(p);
        if (org.avatar) |a| allocator.free(a);
    }
    
    if (org.type != .organization) {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Check if user is owner
    const members = ctx.dao.getOrgUsers(allocator, org.id) catch |err| {
        std.log.err("Failed to get org members: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer allocator.free(members);
    
    var is_owner = false;
    for (members) |member| {
        if (member.uid == user_id and member.is_owner) {
            is_owner = true;
            break;
        }
    }
    
    if (!is_owner) {
        try writeError(res, allocator, 403, "Only organization owners can delete the organization");
        return;
    }
    
    ctx.dao.deleteUser(allocator, org_name) catch |err| {
        std.log.err("Failed to delete organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{ .message = "Organization deleted successfully" });
}

fn listOrgMembersHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing organization name");
        return;
    };
    
    // Get the organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.passwd) |p| allocator.free(p);
        if (org.avatar) |a| allocator.free(a);
    }
    
    if (org.type != .organization) {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    const members = ctx.dao.getOrgUsers(allocator, org.id) catch |err| {
        std.log.err("Failed to get org members: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer allocator.free(members);
    
    // Get user details for each member
    var member_details = try allocator.alloc(struct {
        id: i64,
        name: []const u8,
        is_owner: bool,
    }, members.len);
    
    for (members, 0..) |member, i| {
        const user = ctx.dao.getUserById(allocator, member.uid) catch |err| {
            std.log.err("Failed to get member details: {}", .{err});
            continue;
        } orelse continue;
        
        member_details[i] = .{
            .id = user.id,
            .name = user.name,
            .is_owner = member.is_owner,
        };
    }
    
    res.status = 200;
    try writeJson(res, allocator, member_details);
}

fn removeOrgMemberHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing organization name");
        return;
    };
    
    const username = req.param("username") orelse {
        try writeError(res, allocator, 400, "Missing username");
        return;
    };
    
    // Get the organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.passwd) |p| allocator.free(p);
        if (org.avatar) |a| allocator.free(a);
    }
    
    if (org.type != .organization) {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Check if user is owner
    const members = ctx.dao.getOrgUsers(allocator, org.id) catch |err| {
        std.log.err("Failed to get org members: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer allocator.free(members);
    
    var is_owner = false;
    for (members) |member| {
        if (member.uid == user_id and member.is_owner) {
            is_owner = true;
            break;
        }
    }
    
    if (!is_owner) {
        try writeError(res, allocator, 403, "Only organization owners can remove members");
        return;
    }
    
    // Get the user to remove
    const user_to_remove = ctx.dao.getUserByName(allocator, username) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "User not found");
        return;
    };
    defer {
        allocator.free(user_to_remove.name);
        if (user_to_remove.email) |e| allocator.free(e);
        if (user_to_remove.passwd) |p| allocator.free(p);
        if (user_to_remove.avatar) |a| allocator.free(a);
    }
    
    ctx.dao.removeUserFromOrg(allocator, user_to_remove.id, org.id) catch |err| {
        std.log.err("Failed to remove member: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{ .message = "Member removed successfully" });
}

fn listUserOrgsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const user_orgs = ctx.dao.getUserOrganizations(allocator, user_id) catch |err| {
        std.log.err("Failed to get user organizations: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (user_orgs) |org| {
            allocator.free(org.org.name);
            if (org.org.email) |e| allocator.free(e);
            if (org.org.passwd) |p| allocator.free(p);
            if (org.org.avatar) |a| allocator.free(a);
        }
        allocator.free(user_orgs);
    }
    
    // Build response
    var response_orgs = try allocator.alloc(struct {
        id: i64,
        name: []const u8,
        avatar: ?[]const u8,
        is_owner: bool,
    }, user_orgs.len);
    
    for (user_orgs, 0..) |org, i| {
        response_orgs[i] = .{
            .id = org.org.id,
            .name = org.org.name,
            .avatar = org.org.avatar,
            .is_owner = org.is_owner,
        };
    }
    
    res.status = 200;
    try writeJson(res, allocator, response_orgs);
}

// Repository handlers
fn createUserRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
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
        description: ?[]const u8 = null,
        @"private": bool = false,
        default_branch: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const repo_data = json_data.value;
    
    const lower_name = try std.ascii.allocLowerString(allocator, repo_data.name);
    defer allocator.free(lower_name);
    
    const repo = DataAccessObject.Repository{
        .id = 0,
        .owner_id = user_id,
        .lower_name = lower_name,
        .name = repo_data.name,
        .description = repo_data.description,
        .default_branch = repo_data.default_branch orelse "main",
        .is_private = repo_data.@"private",
        .is_fork = false,
        .fork_id = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    
    const repo_id = ctx.dao.createRepository(allocator, repo) catch |err| {
        std.log.err("Failed to create repository: {}", .{err});
        // Check if it's a duplicate
        if (err == error.DatabaseError) {
            try writeError(res, allocator, 409, "Repository already exists");
        } else {
            try writeError(res, allocator, 500, "Database error");
        }
        return;
    };
    
    res.status = 201;
    try writeJson(res, allocator, .{
        .id = repo_id,
        .name = repo_data.name,
        .owner_id = user_id,
    });
}

fn createOrgRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing organization name");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Get the organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.passwd) |p| allocator.free(p);
        if (org.avatar) |a| allocator.free(a);
    }
    
    if (org.type != .organization) {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Check if user is member of org
    const members = ctx.dao.getOrgUsers(allocator, org.id) catch |err| {
        std.log.err("Failed to get org members: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer allocator.free(members);
    
    var is_member = false;
    for (members) |member| {
        if (member.uid == user_id) {
            is_member = true;
            break;
        }
    }
    
    if (!is_member) {
        try writeError(res, allocator, 403, "You must be a member of the organization");
        return;
    }
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        name: []const u8,
        description: ?[]const u8 = null,
        @"private": bool = false,
        default_branch: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const repo_data = json_data.value;
    
    const lower_name = try std.ascii.allocLowerString(allocator, repo_data.name);
    defer allocator.free(lower_name);
    
    const repo = DataAccessObject.Repository{
        .id = 0,
        .owner_id = org.id,
        .lower_name = lower_name,
        .name = repo_data.name,
        .description = repo_data.description,
        .default_branch = repo_data.default_branch orelse "main",
        .is_private = repo_data.@"private",
        .is_fork = false,
        .fork_id = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    
    const repo_id = ctx.dao.createRepository(allocator, repo) catch |err| {
        std.log.err("Failed to create repository: {}", .{err});
        if (err == error.DatabaseError) {
            try writeError(res, allocator, 409, "Repository already exists");
        } else {
            try writeError(res, allocator, 500, "Database error");
        }
        return;
    };
    
    res.status = 201;
    try writeJson(res, allocator, .{
        .id = repo_id,
        .name = repo_data.name,
        .owner_id = org.id,
    });
}

fn getRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner user
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    res.status = 200;
    try writeJson(res, allocator, .{
        .id = repo.id,
        .owner_id = repo.owner_id,
        .name = repo.name,
        .description = repo.description,
        .default_branch = repo.default_branch,
        .is_private = repo.is_private,
        .is_fork = repo.is_fork,
        .fork_id = repo.fork_id,
        .created_unix = repo.created_unix,
        .updated_unix = repo.updated_unix,
    });
}

fn updateRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Check permissions
    if (owner.type == .individual) {
        if (owner.id != user_id) {
            try writeError(res, allocator, 403, "Only repository owner can update settings");
            return;
        }
    } else {
        // For organizations, check if user is a member
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        var is_member = false;
        for (members) |member| {
            if (member.uid == user_id) {
                is_member = true;
                break;
            }
        }
        
        if (!is_member) {
            try writeError(res, allocator, 403, "Only organization members can update repositories");
            return;
        }
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Parse update data
    var json_data = std.json.parseFromSlice(struct {
        description: ?[]const u8 = null,
        @"private": ?bool = null,
        default_branch: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const update_data = json_data.value;
    
    // Update repository
    const updates = DataAccessObject.RepositoryUpdate{
        .description = update_data.description,
        .is_private = update_data.@"private",
        .default_branch = update_data.default_branch,
    };
    
    ctx.dao.updateRepository(allocator, repo.id, updates) catch |err| {
        std.log.err("Failed to update repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{ .message = "Repository updated successfully" });
}

fn deleteRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Check permissions
    if (owner.type == .individual) {
        if (owner.id != user_id) {
            try writeError(res, allocator, 403, "Only repository owner can delete repository");
            return;
        }
    } else {
        // For organizations, check if user is an owner
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        var is_owner = false;
        for (members) |member| {
            if (member.uid == user_id and member.is_owner) {
                is_owner = true;
                break;
            }
        }
        
        if (!is_owner) {
            try writeError(res, allocator, 403, "Only organization owners can delete repositories");
            return;
        }
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    ctx.dao.deleteRepository(allocator, repo.id) catch |err| {
        std.log.err("Failed to delete repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{ .message = "Repository deleted successfully" });
}

fn forkRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get source repository owner
    const source_owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(source_owner.name);
        if (source_owner.email) |e| allocator.free(e);
        if (source_owner.passwd) |p| allocator.free(p);
        if (source_owner.avatar) |a| allocator.free(a);
    }
    
    // Get source repository
    const source_repo = ctx.dao.getRepositoryByName(allocator, source_owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(source_repo.lower_name);
        allocator.free(source_repo.name);
        if (source_repo.description) |d| allocator.free(d);
        allocator.free(source_repo.default_branch);
    }
    
    // Create fork
    const fork_id = ctx.dao.forkRepository(allocator, source_repo.id, user_id, source_repo.name) catch |err| {
        std.log.err("Failed to fork repository: {}", .{err});
        if (err == error.DatabaseError) {
            try writeError(res, allocator, 409, "Fork already exists");
        } else {
            try writeError(res, allocator, 500, "Database error");
        }
        return;
    };
    
    res.status = 201;
    try writeJson(res, allocator, .{
        .id = fork_id,
        .name = source_repo.name,
        .owner_id = user_id,
        .fork_id = source_repo.id,
    });
}

// Branch handlers
fn listBranchesHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    const branches = ctx.dao.getBranches(allocator, repo.id) catch |err| {
        std.log.err("Failed to get branches: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (branches) |branch| {
            allocator.free(branch.name);
            if (branch.commit_id) |c| allocator.free(c);
        }
        allocator.free(branches);
    }
    
    // Build response
    var response_branches = try allocator.alloc(struct {
        name: []const u8,
        commit_id: ?[]const u8,
        is_protected: bool,
    }, branches.len);
    
    for (branches, 0..) |branch, i| {
        response_branches[i] = .{
            .name = branch.name,
            .commit_id = branch.commit_id,
            .is_protected = branch.is_protected,
        };
    }
    
    res.status = 200;
    try writeJson(res, allocator, response_branches);
}

fn getBranchHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const branch_name = req.param("branch") orelse {
        try writeError(res, allocator, 400, "Missing branch parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    const branch = ctx.dao.getBranchByName(allocator, repo.id, branch_name) catch |err| {
        std.log.err("Failed to get branch: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Branch not found");
        return;
    };
    defer {
        allocator.free(branch.name);
        if (branch.commit_id) |c| allocator.free(c);
    }
    
    res.status = 200;
    try writeJson(res, allocator, .{
        .name = branch.name,
        .commit_id = branch.commit_id,
        .is_protected = branch.is_protected,
    });
}

fn createBranchHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Check permissions
    var has_permission = false;
    if (owner.type == .individual) {
        has_permission = owner.id == user_id;
    } else {
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        for (members) |member| {
            if (member.uid == user_id) {
                has_permission = true;
                break;
            }
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to create branches");
        return;
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        branch: []const u8,
        source: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const branch_data = json_data.value;
    
    // For now, we'll create branch without actual git operations
    const new_branch = DataAccessObject.Branch{
        .id = 0,
        .repo_id = repo.id,
        .name = branch_data.branch,
        .commit_id = null, // Would be set from actual git
        .is_protected = false,
    };
    
    ctx.dao.createBranch(allocator, new_branch) catch |err| {
        std.log.err("Failed to create branch: {}", .{err});
        if (err == error.DatabaseError) {
            try writeError(res, allocator, 409, "Branch already exists");
        } else {
            try writeError(res, allocator, 500, "Database error");
        }
        return;
    };
    
    res.status = 201;
    try writeJson(res, allocator, .{
        .name = branch_data.branch,
        .is_protected = false,
    });
}

fn deleteBranchHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const branch_name = req.param("branch") orelse {
        try writeError(res, allocator, 400, "Missing branch parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Check permissions (same as create)
    var has_permission = false;
    if (owner.type == .individual) {
        has_permission = owner.id == user_id;
    } else {
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        for (members) |member| {
            if (member.uid == user_id) {
                has_permission = true;
                break;
            }
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to delete branches");
        return;
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check if branch is default branch
    if (std.mem.eql(u8, branch_name, repo.default_branch)) {
        try writeError(res, allocator, 400, "Cannot delete default branch");
        return;
    }
    
    // Check if branch is protected
    const branch = ctx.dao.getBranchByName(allocator, repo.id, branch_name) catch |err| {
        std.log.err("Failed to get branch: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Branch not found");
        return;
    };
    defer {
        allocator.free(branch.name);
        if (branch.commit_id) |c| allocator.free(c);
    }
    
    if (branch.is_protected) {
        try writeError(res, allocator, 403, "Cannot delete protected branch");
        return;
    }
    
    ctx.dao.deleteBranch(allocator, repo.id, branch_name) catch |err| {
        std.log.err("Failed to delete branch: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{ .message = "Branch deleted successfully" });
}

// Issue handlers
fn listIssuesHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Parse query parameters for filters
    const query_params = req.query() catch null;
    const state = if (query_params) |q| q.get("state") else null;
    const is_closed = if (state) |s| std.mem.eql(u8, s, "closed") else false;
    
    const filters = DataAccessObject.IssueFilters{
        .is_closed = is_closed,
        .is_pull = false,
        .assignee_id = null,
    };
    
    const issues = ctx.dao.listIssues(allocator, repo.id, filters) catch |err| {
        std.log.err("Failed to list issues: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (issues) |issue| {
            allocator.free(issue.title);
            if (issue.content) |c| allocator.free(c);
        }
        allocator.free(issues);
    }
    
    // Build JSON response
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("[");
    for (issues, 0..) |issue, i| {
        if (i > 0) try result.appendSlice(",");
        
        try std.json.stringify(.{
            .id = issue.id,
            .number = issue.index,
            .title = issue.title,
            .body = issue.content,
            .state = if (issue.is_closed) "closed" else "open",
            .created_at = issue.created_unix,
            .user = .{ .id = issue.poster_id },
            .assignee = if (issue.assignee_id) |aid| .{ .id = aid } else null,
        }, .{}, result.writer());
    }
    try result.appendSlice("]");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

fn createIssueHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        title: []const u8,
        body: ?[]const u8 = null,
        assignee: ?[]const u8 = null,
        labels: ?[]i64 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
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
        .poster_id = user_id,
        .title = issue_data.title,
        .content = issue_data.body,
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
    
    // Add labels if specified
    if (issue_data.labels) |labels| {
        for (labels) |label_id| {
            ctx.dao.addLabelToIssue(allocator, issue_id, label_id) catch |err| {
                std.log.err("Failed to add label to issue: {}", .{err});
                // Continue with other labels
            };
        }
    }
    
    // Get the created issue with index
    const created_issue = ctx.dao.getIssue(allocator, repo.?.id, issue.index) catch |err| {
        std.log.err("Failed to get created issue: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(created_issue.title);
        if (created_issue.content) |c| allocator.free(c);
    }
    
    res.status = 201;
    try writeJson(res, allocator, .{
        .id = issue_id,
        .number = created_issue.index,
        .title = created_issue.title,
        .body = created_issue.content,
        .state = "open",
        .user = .{ .id = created_issue.poster_id },
        .assignee = if (created_issue.assignee_id) |aid| .{ .id = aid } else null,
        .created_at = created_issue.created_unix,
    });
}

fn getIssueHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const index_str = req.param("index") orelse {
        try writeError(res, allocator, 400, "Missing index parameter");
        return;
    };
    
    const index = std.fmt.parseInt(i64, index_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid index");
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

fn updateIssueHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    _ = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const index_str = req.param("index") orelse {
        try writeError(res, allocator, 400, "Missing index parameter");
        return;
    };
    
    const index = std.fmt.parseInt(i64, index_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid index");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        title: ?[]const u8 = null,
        body: ?[]const u8 = null,
        state: ?[]const u8 = null,
        assignee: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const update_data = json_data.value;
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get the issue
    const issue = ctx.dao.getIssue(allocator, repo.id, index) catch |err| {
        std.log.err("Failed to get issue: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Issue not found");
        return;
    };
    defer {
        allocator.free(issue.title);
        if (issue.content) |c| allocator.free(c);
    }
    
    // Get assignee ID if specified
    var assignee_id: ?i64 = null;
    if (update_data.assignee) |assignee_name| {
        const assignee = ctx.dao.getUserByName(allocator, assignee_name) catch |err| {
            std.log.err("Failed to get assignee: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
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
    
    const is_closed = if (update_data.state) |state| std.mem.eql(u8, state, "closed") else null;
    
    const updates = DataAccessObject.IssueUpdate{
        .title = update_data.title,
        .content = update_data.body,
        .is_closed = is_closed,
        .assignee_id = assignee_id,
    };
    
    ctx.dao.updateIssue(allocator, issue.id, updates) catch |err| {
        std.log.err("Failed to update issue: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    // Get the updated issue
    const updated_issue = ctx.dao.getIssue(allocator, repo.id, index) catch |err| {
        std.log.err("Failed to get updated issue: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(updated_issue.title);
        if (updated_issue.content) |c| allocator.free(c);
    }
    
    res.status = 200;
    try writeJson(res, allocator, .{
        .id = updated_issue.id,
        .number = updated_issue.index,
        .title = updated_issue.title,
        .body = updated_issue.content,
        .state = if (updated_issue.is_closed) "closed" else "open",
        .user = .{ .id = updated_issue.poster_id },
        .assignee = if (updated_issue.assignee_id) |aid| .{ .id = aid } else null,
        .created_at = updated_issue.created_unix,
    });
}

fn createCommentHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const index_str = req.param("index") orelse {
        try writeError(res, allocator, 400, "Missing index parameter");
        return;
    };
    
    const index = std.fmt.parseInt(i64, index_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid index");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        body: []const u8,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const comment_data = json_data.value;
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get the issue
    const issue = ctx.dao.getIssue(allocator, repo.id, index) catch |err| {
        std.log.err("Failed to get issue: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Issue not found");
        return;
    };
    defer {
        allocator.free(issue.title);
        if (issue.content) |c| allocator.free(c);
    }
    
    const comment = DataAccessObject.Comment{
        .id = 0,
        .poster_id = user_id,
        .issue_id = issue.id,
        .review_id = null,
        .content = comment_data.body,
        .commit_id = null,
        .line = null,
        .created_unix = 0,
    };
    
    const comment_id = ctx.dao.createComment(allocator, comment) catch |err| {
        std.log.err("Failed to create comment: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 201;
    try writeJson(res, allocator, .{
        .id = comment_id,
        .body = comment_data.body,
        .user = .{ .id = user_id },
        .created_at = std.time.timestamp(),
    });
}

fn getCommentsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const index_str = req.param("index") orelse {
        try writeError(res, allocator, 400, "Missing index parameter");
        return;
    };
    
    const index = std.fmt.parseInt(i64, index_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid index");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get the issue
    const issue = ctx.dao.getIssue(allocator, repo.id, index) catch |err| {
        std.log.err("Failed to get issue: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Issue not found");
        return;
    };
    defer {
        allocator.free(issue.title);
        if (issue.content) |c| allocator.free(c);
    }
    
    const comments = ctx.dao.getComments(allocator, issue.id) catch |err| {
        std.log.err("Failed to get comments: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (comments) |comment| {
            allocator.free(comment.content);
            if (comment.commit_id) |cid| allocator.free(cid);
        }
        allocator.free(comments);
    }
    
    // Build JSON response
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("[");
    for (comments, 0..) |comment, i| {
        if (i > 0) try result.appendSlice(",");
        
        try std.json.stringify(.{
            .id = comment.id,
            .body = comment.content,
            .user = .{ .id = comment.poster_id },
            .created_at = comment.created_unix,
        }, .{}, result.writer());
    }
    try result.appendSlice("]");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

// Label handlers
fn listLabelsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    const labels = ctx.dao.getLabels(allocator, repo.id) catch |err| {
        std.log.err("Failed to get labels: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (labels) |label| {
            allocator.free(label.name);
            allocator.free(label.color);
        }
        allocator.free(labels);
    }
    
    // Build JSON response
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("[");
    for (labels, 0..) |label, i| {
        if (i > 0) try result.appendSlice(",");
        
        try std.json.stringify(.{
            .id = label.id,
            .name = label.name,
            .color = label.color,
        }, .{}, result.writer());
    }
    try result.appendSlice("]");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

fn createLabelHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        name: []const u8,
        color: []const u8,
        description: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const label_data = json_data.value;
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    var has_permission = false;
    if (owner.type == .individual) {
        has_permission = owner.id == user_id;
    } else {
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        for (members) |member| {
            if (member.uid == user_id) {
                has_permission = true;
                break;
            }
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to create labels");
        return;
    }
    
    const label = DataAccessObject.Label{
        .id = 0,
        .repo_id = repo.id,
        .name = label_data.name,
        .color = label_data.color,
    };
    
    const label_id = ctx.dao.createLabel(allocator, label) catch |err| {
        std.log.err("Failed to create label: {}", .{err});
        if (err == error.DatabaseError) {
            try writeError(res, allocator, 409, "Label already exists");
        } else {
            try writeError(res, allocator, 500, "Database error");
        }
        return;
    };
    
    res.status = 201;
    try writeJson(res, allocator, .{
        .id = label_id,
        .name = label_data.name,
        .color = label_data.color,
        .description = label_data.description,
    });
}

fn updateLabelHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const label_id_str = req.param("id") orelse {
        try writeError(res, allocator, 400, "Missing label id parameter");
        return;
    };
    
    const label_id = std.fmt.parseInt(i64, label_id_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid label id");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        name: ?[]const u8 = null,
        color: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const update_data = json_data.value;
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    var has_permission = false;
    if (owner.type == .individual) {
        has_permission = owner.id == user_id;
    } else {
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        for (members) |member| {
            if (member.uid == user_id) {
                has_permission = true;
                break;
            }
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to update labels");
        return;
    }
    
    ctx.dao.updateLabel(allocator, label_id, update_data.name, update_data.color) catch |err| {
        std.log.err("Failed to update label: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{ .message = "Label updated successfully" });
}

fn deleteLabelHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const label_id_str = req.param("id") orelse {
        try writeError(res, allocator, 400, "Missing label id parameter");
        return;
    };
    
    const label_id = std.fmt.parseInt(i64, label_id_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid label id");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    var has_permission = false;
    if (owner.type == .individual) {
        has_permission = owner.id == user_id;
    } else {
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        for (members) |member| {
            if (member.uid == user_id) {
                has_permission = true;
                break;
            }
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to delete labels");
        return;
    }
    
    ctx.dao.deleteLabel(allocator, label_id) catch |err| {
        std.log.err("Failed to delete label: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{ .message = "Label deleted successfully" });
}

fn addLabelsToIssueHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    _ = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const index_str = req.param("index") orelse {
        try writeError(res, allocator, 400, "Missing index parameter");
        return;
    };
    
    const index = std.fmt.parseInt(i64, index_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid index");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        labels: []i64,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const label_data = json_data.value;
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get the issue
    const issue = ctx.dao.getIssue(allocator, repo.id, index) catch |err| {
        std.log.err("Failed to get issue: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Issue not found");
        return;
    };
    defer {
        allocator.free(issue.title);
        if (issue.content) |c| allocator.free(c);
    }
    
    // Add labels
    for (label_data.labels) |label_id| {
        ctx.dao.addLabelToIssue(allocator, issue.id, label_id) catch |err| {
            std.log.err("Failed to add label to issue: {}", .{err});
            // Continue with other labels
        };
    }
    
    res.status = 200;
    try writeJson(res, allocator, .{ .message = "Labels added successfully" });
}

fn removeLabelFromIssueHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    _ = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const index_str = req.param("index") orelse {
        try writeError(res, allocator, 400, "Missing index parameter");
        return;
    };
    const label_id_str = req.param("id") orelse {
        try writeError(res, allocator, 400, "Missing label id parameter");
        return;
    };
    
    const index = std.fmt.parseInt(i64, index_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid index");
        return;
    };
    
    const label_id = std.fmt.parseInt(i64, label_id_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid label id");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get the issue
    const issue = ctx.dao.getIssue(allocator, repo.id, index) catch |err| {
        std.log.err("Failed to get issue: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Issue not found");
        return;
    };
    defer {
        allocator.free(issue.title);
        if (issue.content) |c| allocator.free(c);
    }
    
    ctx.dao.removeLabelFromIssue(allocator, issue.id, label_id) catch |err| {
        std.log.err("Failed to remove label from issue: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{ .message = "Label removed successfully" });
}

// Pull request handlers
fn listPullsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Parse query parameters for filters
    const query_params = req.query() catch null;
    const state = if (query_params) |q| q.get("state") else null;
    const is_closed = if (state) |s| std.mem.eql(u8, s, "closed") else false;
    
    const filters = DataAccessObject.IssueFilters{
        .is_closed = is_closed,
        .is_pull = true,
        .assignee_id = null,
    };
    
    const pulls = ctx.dao.listIssues(allocator, repo.id, filters) catch |err| {
        std.log.err("Failed to list pull requests: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (pulls) |pull| {
            allocator.free(pull.title);
            if (pull.content) |c| allocator.free(c);
        }
        allocator.free(pulls);
    }
    
    // Build JSON response
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("[");
    for (pulls, 0..) |pull, i| {
        if (i > 0) try result.appendSlice(",");
        
        try std.json.stringify(.{
            .id = pull.id,
            .number = pull.index,
            .title = pull.title,
            .body = pull.content,
            .state = if (pull.is_closed) "closed" else "open",
            .created_at = pull.created_unix,
            .user = .{ .id = pull.poster_id },
            .assignee = if (pull.assignee_id) |aid| .{ .id = aid } else null,
        }, .{}, result.writer());
    }
    try result.appendSlice("]");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

fn createPullHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        title: []const u8,
        body: ?[]const u8 = null,
        head: []const u8,
        base: []const u8,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const pr_data = json_data.value;
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    const pull = DataAccessObject.Issue{
        .id = 0,
        .repo_id = repo.id,
        .index = 0,
        .poster_id = user_id,
        .title = pr_data.title,
        .content = pr_data.body,
        .is_closed = false,
        .is_pull = true,
        .assignee_id = null,
        .created_unix = 0,
    };
    
    const pull_id = ctx.dao.createIssue(allocator, pull) catch |err| {
        std.log.err("Failed to create pull request: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    // Get the created pull request with index
    const created_pull = ctx.dao.getIssue(allocator, repo.id, pull.index) catch |err| {
        std.log.err("Failed to get created pull request: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(created_pull.title);
        if (created_pull.content) |c| allocator.free(c);
    }
    
    res.status = 201;
    try writeJson(res, allocator, .{
        .id = pull_id,
        .number = created_pull.index,
        .title = created_pull.title,
        .body = created_pull.content,
        .state = "open",
        .user = .{ .id = created_pull.poster_id },
        .created_at = created_pull.created_unix,
        .head = pr_data.head,
        .base = pr_data.base,
    });
}

fn getPullHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const index_str = req.param("index") orelse {
        try writeError(res, allocator, 400, "Missing index parameter");
        return;
    };
    
    const index = std.fmt.parseInt(i64, index_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid index");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get the pull request (stored as issue with is_pull=true)
    const pull = ctx.dao.getIssue(allocator, repo.id, index) catch |err| {
        std.log.err("Failed to get pull request: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Pull request not found");
        return;
    };
    defer {
        allocator.free(pull.title);
        if (pull.content) |c| allocator.free(c);
    }
    
    if (!pull.is_pull) {
        try writeError(res, allocator, 404, "Pull request not found");
        return;
    }
    
    res.status = 200;
    try writeJson(res, allocator, .{
        .id = pull.id,
        .number = pull.index,
        .title = pull.title,
        .body = pull.content,
        .state = if (pull.is_closed) "closed" else "open",
        .user = .{ .id = pull.poster_id },
        .assignee = if (pull.assignee_id) |aid| .{ .id = aid } else null,
        .created_at = pull.created_unix,
    });
}

fn listReviewsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const index_str = req.param("index") orelse {
        try writeError(res, allocator, 400, "Missing index parameter");
        return;
    };
    
    const index = std.fmt.parseInt(i64, index_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid index");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get the pull request
    const pull = ctx.dao.getIssue(allocator, repo.id, index) catch |err| {
        std.log.err("Failed to get pull request: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Pull request not found");
        return;
    };
    defer {
        allocator.free(pull.title);
        if (pull.content) |c| allocator.free(c);
    }
    
    if (!pull.is_pull) {
        try writeError(res, allocator, 404, "Pull request not found");
        return;
    }
    
    const reviews = ctx.dao.getReviews(allocator, pull.id) catch |err| {
        std.log.err("Failed to get reviews: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (reviews) |review| {
            if (review.commit_id) |cid| allocator.free(cid);
        }
        allocator.free(reviews);
    }
    
    // Build JSON response
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("[");
    for (reviews, 0..) |review, i| {
        if (i > 0) try result.appendSlice(",");
        
        const review_type = switch (review.type) {
            .approve => "APPROVE",
            .reject => "REQUEST_CHANGES",
            .comment => "COMMENT",
        };
        
        try std.json.stringify(.{
            .id = review.id,
            .user = .{ .id = review.reviewer_id },
            .state = review_type,
            .commit_id = review.commit_id,
        }, .{}, result.writer());
    }
    try result.appendSlice("]");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

fn createReviewHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const index_str = req.param("index") orelse {
        try writeError(res, allocator, 400, "Missing index parameter");
        return;
    };
    
    const index = std.fmt.parseInt(i64, index_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid index");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        body: ?[]const u8 = null,
        event: []const u8,
        commit_id: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const review_data = json_data.value;
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get the pull request
    const pull = ctx.dao.getIssue(allocator, repo.id, index) catch |err| {
        std.log.err("Failed to get pull request: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Pull request not found");
        return;
    };
    defer {
        allocator.free(pull.title);
        if (pull.content) |c| allocator.free(c);
    }
    
    if (!pull.is_pull) {
        try writeError(res, allocator, 404, "Pull request not found");
        return;
    }
    
    // Map event to review type
    const review_type = if (std.mem.eql(u8, review_data.event, "APPROVE"))
        DataAccessObject.ReviewType.approve
    else if (std.mem.eql(u8, review_data.event, "COMMENT"))
        DataAccessObject.ReviewType.comment
    else if (std.mem.eql(u8, review_data.event, "REQUEST_CHANGES"))
        DataAccessObject.ReviewType.reject
    else
        DataAccessObject.ReviewType.comment; // Default to comment
    
    const review = DataAccessObject.Review{
        .id = 0,
        .type = review_type,
        .reviewer_id = user_id,
        .issue_id = pull.id,
        .commit_id = review_data.commit_id,
    };
    
    const review_id = ctx.dao.createReview(allocator, review) catch |err| {
        std.log.err("Failed to create review: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    // If there's a comment body, create a comment associated with the review
    if (review_data.body) |comment_body| {
        const comment = DataAccessObject.Comment{
            .id = 0,
            .poster_id = user_id,
            .issue_id = pull.id,
            .review_id = review_id,
            .content = comment_body,
            .commit_id = review_data.commit_id,
            .line = null,
            .created_unix = 0,
        };
        
        _ = ctx.dao.createComment(allocator, comment) catch |err| {
            std.log.err("Failed to create review comment: {}", .{err});
            // Continue anyway
        };
    }
    
    res.status = 201;
    try writeJson(res, allocator, .{
        .id = review_id,
        .user = .{ .id = user_id },
        .state = review_data.event,
        .body = review_data.body,
        .commit_id = review_data.commit_id,
    });
}

fn mergePullHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const index_str = req.param("index") orelse {
        try writeError(res, allocator, 400, "Missing index parameter");
        return;
    };
    
    const index = std.fmt.parseInt(i64, index_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid index");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    var has_permission = false;
    if (owner.type == .individual) {
        has_permission = owner.id == user_id;
    } else {
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        for (members) |member| {
            if (member.uid == user_id) {
                has_permission = true;
                break;
            }
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to merge pull requests");
        return;
    }
    
    // Get the pull request
    const pull = ctx.dao.getIssue(allocator, repo.id, index) catch |err| {
        std.log.err("Failed to get pull request: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Pull request not found");
        return;
    };
    defer {
        allocator.free(pull.title);
        if (pull.content) |c| allocator.free(c);
    }
    
    if (!pull.is_pull) {
        try writeError(res, allocator, 404, "Pull request not found");
        return;
    }
    
    if (pull.is_closed) {
        try writeError(res, allocator, 422, "Pull request is already closed");
        return;
    }
    
    // For now, just close the pull request (actual git merge would happen here)
    const updates = DataAccessObject.IssueUpdate{
        .title = null,
        .content = null,
        .is_closed = true,
        .assignee_id = null,
    };
    
    ctx.dao.updateIssue(allocator, pull.id, updates) catch |err| {
        std.log.err("Failed to close pull request: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{
        .merged = true,
        .message = "Pull request merged successfully",
    });
}

// Actions/CI handlers
fn listRunsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    const runs = ctx.dao.getActionRuns(allocator, repo.id) catch |err| {
        std.log.err("Failed to get action runs: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (runs) |run| {
            allocator.free(run.workflow_id);
            allocator.free(run.commit_sha);
            allocator.free(run.trigger_event);
        }
        allocator.free(runs);
    }
    
    // Build JSON response
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("{\"workflow_runs\":[");
    for (runs, 0..) |run, i| {
        if (i > 0) try result.appendSlice(",");
        
        const status_str = switch (run.status) {
            .queued => "queued",
            .in_progress => "in_progress",
            .success => "completed",
            .failure => "completed",
        };
        
        const conclusion = switch (run.status) {
            .success => "success",
            .failure => "failure",
            else => null,
        };
        
        try std.json.stringify(.{
            .id = run.id,
            .workflow_id = run.workflow_id,
            .status = status_str,
            .conclusion = conclusion,
            .head_sha = run.commit_sha,
            .event = run.trigger_event,
            .created_at = run.created_unix,
        }, .{}, result.writer());
    }
    try result.appendSlice("]}");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

fn getRunHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const run_id_str = req.param("run_id") orelse {
        try writeError(res, allocator, 400, "Missing run_id parameter");
        return;
    };
    
    const run_id = std.fmt.parseInt(i64, run_id_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid run_id");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    const run = ctx.dao.getActionRunById(allocator, run_id) catch |err| {
        std.log.err("Failed to get action run: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Run not found");
        return;
    };
    defer {
        allocator.free(run.workflow_id);
        allocator.free(run.commit_sha);
        allocator.free(run.trigger_event);
    }
    
    // Verify the run belongs to this repo
    if (run.repo_id != repo.id) {
        try writeError(res, allocator, 404, "Run not found");
        return;
    }
    
    const status_str = switch (run.status) {
        .queued => "queued",
        .in_progress => "in_progress",
        .success => "completed",
        .failure => "completed",
    };
    
    const conclusion = switch (run.status) {
        .success => "success",
        .failure => "failure",
        else => null,
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{
        .id = run.id,
        .workflow_id = run.workflow_id,
        .status = status_str,
        .conclusion = conclusion,
        .head_sha = run.commit_sha,
        .event = run.trigger_event,
        .created_at = run.created_unix,
    });
}

fn listJobsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    _ = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    _ = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const run_id_str = req.param("run_id") orelse {
        try writeError(res, allocator, 400, "Missing run_id parameter");
        return;
    };
    
    const run_id = std.fmt.parseInt(i64, run_id_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid run_id");
        return;
    };
    
    const jobs = ctx.dao.getActionJobs(allocator, run_id) catch |err| {
        std.log.err("Failed to get action jobs: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (jobs) |job| {
            allocator.free(job.name);
            allocator.free(job.runs_on);
            if (job.log) |log| allocator.free(log);
        }
        allocator.free(jobs);
    }
    
    // Build JSON response
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("{\"jobs\":[");
    for (jobs, 0..) |job, i| {
        if (i > 0) try result.appendSlice(",");
        
        const status_str = switch (job.status) {
            .queued => "queued",
            .in_progress => "in_progress",
            .success => "completed",
            .failure => "completed",
        };
        
        const conclusion = switch (job.status) {
            .success => "success",
            .failure => "failure",
            else => null,
        };
        
        try std.json.stringify(.{
            .id = job.id,
            .run_id = job.run_id,
            .name = job.name,
            .status = status_str,
            .conclusion = conclusion,
            .started_at = job.started,
            .completed_at = job.stopped,
        }, .{}, result.writer());
    }
    try result.appendSlice("]}");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

fn listArtifactsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const run_id_str = req.param("run_id") orelse {
        try writeError(res, allocator, 400, "Missing run_id parameter");
        return;
    };
    
    const run_id = std.fmt.parseInt(i64, run_id_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid run_id");
        return;
    };
    
    // Get all jobs for this run
    const jobs = ctx.dao.getActionJobs(allocator, run_id) catch |err| {
        std.log.err("Failed to get action jobs: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (jobs) |job| {
            allocator.free(job.name);
            allocator.free(job.runs_on);
            if (job.log) |log| allocator.free(log);
        }
        allocator.free(jobs);
    }
    
    // Get artifacts for all jobs
    var all_artifacts = std.ArrayList(DataAccessObject.ActionArtifact).init(allocator);
    defer {
        for (all_artifacts.items) |artifact| {
            allocator.free(artifact.name);
            allocator.free(artifact.path);
        }
        all_artifacts.deinit();
    }
    
    for (jobs) |job| {
        const artifacts = ctx.dao.getActionArtifacts(allocator, job.id) catch |err| {
            std.log.err("Failed to get artifacts for job {}: {}", .{ job.id, err });
            continue;
        };
        defer allocator.free(artifacts);
        
        for (artifacts) |artifact| {
            try all_artifacts.append(artifact);
        }
    }
    
    // Build JSON response
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("{\"artifacts\":[");
    for (all_artifacts.items, 0..) |artifact, i| {
        if (i > 0) try result.appendSlice(",");
        
        try std.json.stringify(.{
            .id = artifact.id,
            .name = artifact.name,
            .size_in_bytes = artifact.file_size,
            .archive_download_url = try std.fmt.allocPrint(allocator, "/repos/{s}/{s}/actions/artifacts/{}", .{ owner_name, repo_name, artifact.id }),
        }, .{}, result.writer());
    }
    try result.appendSlice("]}");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

fn getArtifactHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const artifact_id_str = req.param("artifact_id") orelse {
        try writeError(res, allocator, 400, "Missing artifact_id parameter");
        return;
    };
    
    const artifact_id = std.fmt.parseInt(i64, artifact_id_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid artifact_id");
        return;
    };
    
    const artifact = ctx.dao.getActionArtifactById(allocator, artifact_id) catch |err| {
        std.log.err("Failed to get artifact: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Artifact not found");
        return;
    };
    defer {
        allocator.free(artifact.name);
        allocator.free(artifact.path);
    }
    
    res.status = 200;
    try writeJson(res, allocator, .{
        .id = artifact.id,
        .name = artifact.name,
        .size_in_bytes = artifact.file_size,
        .archive_download_url = try std.fmt.allocPrint(allocator, "/repos/{s}/{s}/actions/artifacts/{}", .{ owner_name, repo_name, artifact.id }),
    });
}

fn listOrgSecretsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    // Get organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.passwd) |p| allocator.free(p);
        if (org.avatar) |a| allocator.free(a);
    }
    
    if (org.type != .organization) {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    const secrets = ctx.dao.getActionSecrets(allocator, org.id, 0) catch |err| {
        std.log.err("Failed to get secrets: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (secrets) |secret| {
            allocator.free(secret.name);
            allocator.free(secret.data);
        }
        allocator.free(secrets);
    }
    
    // Build JSON response (don't expose actual secret data)
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("{\"secrets\":[");
    for (secrets, 0..) |secret, i| {
        if (i > 0) try result.appendSlice(",");
        
        try std.json.stringify(.{
            .name = secret.name,
            .created_at = std.time.timestamp(),
            .updated_at = std.time.timestamp(),
        }, .{}, result.writer());
    }
    try result.appendSlice("]}");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

fn createOrgSecretHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    const secret_name = req.param("secretname") orelse {
        try writeError(res, allocator, 400, "Missing secretname parameter");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        encrypted_value: []const u8,
        visibility: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const secret_data = json_data.value;
    
    // Get organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.passwd) |p| allocator.free(p);
        if (org.avatar) |a| allocator.free(a);
    }
    
    if (org.type != .organization) {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Check permissions
    const members = ctx.dao.getOrgUsers(allocator, org.id) catch |err| {
        std.log.err("Failed to get org members: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer allocator.free(members);
    
    var has_permission = false;
    for (members) |member| {
        if (member.uid == user_id and member.is_owner) {
            has_permission = true;
            break;
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to manage organization secrets");
        return;
    }
    
    const secret = DataAccessObject.ActionSecret{
        .id = 0,
        .owner_id = org.id,
        .repo_id = 0,
        .name = secret_name,
        .data = secret_data.encrypted_value,
    };
    
    ctx.dao.createActionSecret(allocator, secret) catch |err| {
        std.log.err("Failed to create secret: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 201;
    res.body = "";
}

fn deleteOrgSecretHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    const secret_name = req.param("secretname") orelse {
        try writeError(res, allocator, 400, "Missing secretname parameter");
        return;
    };
    
    // Get organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.passwd) |p| allocator.free(p);
        if (org.avatar) |a| allocator.free(a);
    }
    
    if (org.type != .organization) {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Check permissions
    const members = ctx.dao.getOrgUsers(allocator, org.id) catch |err| {
        std.log.err("Failed to get org members: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer allocator.free(members);
    
    var has_permission = false;
    for (members) |member| {
        if (member.uid == user_id and member.is_owner) {
            has_permission = true;
            break;
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to manage organization secrets");
        return;
    }
    
    ctx.dao.deleteActionSecret(allocator, org.id, 0, secret_name) catch |err| {
        std.log.err("Failed to delete secret: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 204;
    res.body = "";
}

fn listRepoSecretsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    const secrets = ctx.dao.getActionSecrets(allocator, 0, repo.id) catch |err| {
        std.log.err("Failed to get secrets: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (secrets) |secret| {
            allocator.free(secret.name);
            allocator.free(secret.data);
        }
        allocator.free(secrets);
    }
    
    // Build JSON response (don't expose actual secret data)
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("{\"secrets\":[");
    for (secrets, 0..) |secret, i| {
        if (i > 0) try result.appendSlice(",");
        
        try std.json.stringify(.{
            .name = secret.name,
            .created_at = std.time.timestamp(),
            .updated_at = std.time.timestamp(),
        }, .{}, result.writer());
    }
    try result.appendSlice("]}");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

fn createRepoSecretHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const secret_name = req.param("secretname") orelse {
        try writeError(res, allocator, 400, "Missing secretname parameter");
        return;
    };
    
    const body = req.body() orelse {
        try writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        encrypted_value: []const u8,
        visibility: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const secret_data = json_data.value;
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    var has_permission = false;
    if (owner.type == .individual) {
        has_permission = owner.id == user_id;
    } else {
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        for (members) |member| {
            if (member.uid == user_id) {
                has_permission = true;
                break;
            }
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to manage repository secrets");
        return;
    }
    
    const secret = DataAccessObject.ActionSecret{
        .id = 0,
        .owner_id = 0,
        .repo_id = repo.id,
        .name = secret_name,
        .data = secret_data.encrypted_value,
    };
    
    ctx.dao.createActionSecret(allocator, secret) catch |err| {
        std.log.err("Failed to create secret: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 201;
    res.body = "";
}

fn deleteRepoSecretHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const secret_name = req.param("secretname") orelse {
        try writeError(res, allocator, 400, "Missing secretname parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    var has_permission = false;
    if (owner.type == .individual) {
        has_permission = owner.id == user_id;
    } else {
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        for (members) |member| {
            if (member.uid == user_id) {
                has_permission = true;
                break;
            }
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to manage repository secrets");
        return;
    }
    
    ctx.dao.deleteActionSecret(allocator, 0, repo.id, secret_name) catch |err| {
        std.log.err("Failed to delete secret: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 204;
    res.body = "";
}

fn listOrgRunnersHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    // Get organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.passwd) |p| allocator.free(p);
        if (org.avatar) |a| allocator.free(a);
    }
    
    if (org.type != .organization) {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    const runners = ctx.dao.getRunners(allocator, org.id, 0) catch |err| {
        std.log.err("Failed to get runners: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (runners) |runner| {
            allocator.free(runner.uuid);
            allocator.free(runner.name);
            allocator.free(runner.token_hash);
            if (runner.labels) |labels| allocator.free(labels);
            allocator.free(runner.status);
        }
        allocator.free(runners);
    }
    
    // Build JSON response
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("{\"runners\":[");
    for (runners, 0..) |runner, i| {
        if (i > 0) try result.appendSlice(",");
        
        try std.json.stringify(.{
            .id = runner.id,
            .name = runner.name,
            .status = runner.status,
            .labels = runner.labels,
        }, .{}, result.writer());
    }
    try result.appendSlice("]}");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

fn listRepoRunnersHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    const runners = ctx.dao.getRunners(allocator, 0, repo.id) catch |err| {
        std.log.err("Failed to get runners: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (runners) |runner| {
            allocator.free(runner.uuid);
            allocator.free(runner.name);
            allocator.free(runner.token_hash);
            if (runner.labels) |labels| allocator.free(labels);
            allocator.free(runner.status);
        }
        allocator.free(runners);
    }
    
    // Build JSON response
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("{\"runners\":[");
    for (runners, 0..) |runner, i| {
        if (i > 0) try result.appendSlice(",");
        
        try std.json.stringify(.{
            .id = runner.id,
            .name = runner.name,
            .status = runner.status,
            .labels = runner.labels,
        }, .{}, result.writer());
    }
    try result.appendSlice("]}");
    
    res.status = 200;
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, result.items);
}

fn getOrgRunnerTokenHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    // Get organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.passwd) |p| allocator.free(p);
        if (org.avatar) |a| allocator.free(a);
    }
    
    if (org.type != .organization) {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Check permissions
    const members = ctx.dao.getOrgUsers(allocator, org.id) catch |err| {
        std.log.err("Failed to get org members: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer allocator.free(members);
    
    var has_permission = false;
    for (members) |member| {
        if (member.uid == user_id and member.is_owner) {
            has_permission = true;
            break;
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to manage organization runners");
        return;
    }
    
    // Generate a random token
    const rand = std.crypto.random;
    var token: [32]u8 = undefined;
    rand.bytes(&token);
    
    // Convert to hex string
    var token_hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&token_hex, "{x}", .{std.fmt.fmtSliceHexLower(&token)}) catch unreachable;
    
    // Hash the token for storage
    var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&token_hex, &hash, .{});
    
    var hash_hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hash_hex, "{x}", .{std.fmt.fmtSliceHexLower(&hash)}) catch unreachable;
    
    // Store the token hash
    ctx.dao.createRunnerToken(allocator, &hash_hex, org.id, 0) catch |err| {
        std.log.err("Failed to create runner token: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{
        .token = &token_hex,
        .expires_at = std.time.timestamp() + (60 * 60), // 1 hour
    });
}

fn getRepoRunnerTokenHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    var has_permission = false;
    if (owner.type == .individual) {
        has_permission = owner.id == user_id;
    } else {
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        for (members) |member| {
            if (member.uid == user_id) {
                has_permission = true;
                break;
            }
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to manage repository runners");
        return;
    }
    
    // Generate a random token
    const rand = std.crypto.random;
    var token: [32]u8 = undefined;
    rand.bytes(&token);
    
    // Convert to hex string
    var token_hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&token_hex, "{x}", .{std.fmt.fmtSliceHexLower(&token)}) catch unreachable;
    
    // Hash the token for storage
    var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&token_hex, &hash, .{});
    
    var hash_hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hash_hex, "{x}", .{std.fmt.fmtSliceHexLower(&hash)}) catch unreachable;
    
    // Store the token hash
    ctx.dao.createRunnerToken(allocator, &hash_hex, 0, repo.id) catch |err| {
        std.log.err("Failed to create runner token: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 200;
    try writeJson(res, allocator, .{
        .token = &token_hex,
        .expires_at = std.time.timestamp() + (60 * 60), // 1 hour
    });
}

fn deleteOrgRunnerHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    const runner_id_str = req.param("runner_id") orelse {
        try writeError(res, allocator, 400, "Missing runner_id parameter");
        return;
    };
    
    const runner_id = std.fmt.parseInt(i64, runner_id_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid runner_id");
        return;
    };
    
    // Get organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.passwd) |p| allocator.free(p);
        if (org.avatar) |a| allocator.free(a);
    }
    
    if (org.type != .organization) {
        try writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Check permissions
    const members = ctx.dao.getOrgUsers(allocator, org.id) catch |err| {
        std.log.err("Failed to get org members: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    defer allocator.free(members);
    
    var has_permission = false;
    for (members) |member| {
        if (member.uid == user_id and member.is_owner) {
            has_permission = true;
            break;
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to manage organization runners");
        return;
    }
    
    ctx.dao.deleteRunner(allocator, runner_id) catch |err| {
        std.log.err("Failed to delete runner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 204;
    res.body = "";
}

fn deleteRepoRunnerHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const runner_id_str = req.param("runner_id") orelse {
        try writeError(res, allocator, 400, "Missing runner_id parameter");
        return;
    };
    
    const runner_id = std.fmt.parseInt(i64, runner_id_str, 10) catch {
        try writeError(res, allocator, 400, "Invalid runner_id");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.passwd) |p| allocator.free(p);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.lower_name);
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    var has_permission = false;
    if (owner.type == .individual) {
        has_permission = owner.id == user_id;
    } else {
        const members = ctx.dao.getOrgUsers(allocator, owner.id) catch |err| {
            std.log.err("Failed to get org members: {}", .{err});
            try writeError(res, allocator, 500, "Database error");
            return;
        };
        defer allocator.free(members);
        
        for (members) |member| {
            if (member.uid == user_id) {
                has_permission = true;
                break;
            }
        }
    }
    
    if (!has_permission) {
        try writeError(res, allocator, 403, "You don't have permission to manage repository runners");
        return;
    }
    
    ctx.dao.deleteRunner(allocator, runner_id) catch |err| {
        std.log.err("Failed to delete runner: {}", .{err});
        try writeError(res, allocator, 500, "Database error");
        return;
    };
    
    res.status = 204;
    res.body = "";
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

test "user API endpoints" {
    const allocator = std.testing.allocator;
    
    // Initialize test database
    const test_db_url = std.posix.getenv("TEST_DATABASE_URL") orelse "postgresql://plue:plue_password@localhost:5432/plue";
    var dao = DataAccessObject.init(test_db_url) catch |err| switch (err) {
        error.ConnectionRefused => {
            std.log.warn("Database not available for testing, skipping", .{});
            return;
        },
        else => return err,
    };
    defer dao.deinit();
    
    // Clean up test data
    dao.deleteUser(allocator, "test_api_user") catch {};
    dao.deleteAuthToken(allocator, "test_token_123") catch {};
    
    // Create test user
    const test_user = DataAccessObject.User{
        .id = 0,
        .name = "test_api_user",
        .email = "api@test.com",
        .passwd = "hashed_password",
        .type = .individual,
        .is_admin = false,
        .avatar = "https://example.com/avatar.png",
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, test_user);
    
    // Get created user
    const created_user = try dao.getUserByName(allocator, "test_api_user") orelse unreachable;
    defer {
        allocator.free(created_user.name);
        if (created_user.email) |e| allocator.free(e);
        if (created_user.passwd) |p| allocator.free(p);
        if (created_user.avatar) |a| allocator.free(a);
    }
    
    // Create auth token
    const auth_token = try dao.createAuthToken(allocator, created_user.id);
    defer allocator.free(auth_token.token);
    
    // Test GET /user endpoint - should get authenticated user
    {
        const user = try dao.getUserById(allocator, created_user.id);
        try std.testing.expect(user != null);
        if (user) |u| {
            try std.testing.expectEqualStrings("test_api_user", u.name);
            try std.testing.expectEqualStrings("api@test.com", u.email.?);
            allocator.free(u.name);
            if (u.email) |e| allocator.free(e);
            if (u.passwd) |p| allocator.free(p);
            if (u.avatar) |a| allocator.free(a);
        }
    }
    
    // Test public profile endpoint
    {
        const user = try dao.getUserByName(allocator, "test_api_user");
        try std.testing.expect(user != null);
        if (user) |u| {
            try std.testing.expectEqualStrings("test_api_user", u.name);
            // Public profile should still have email
            try std.testing.expect(u.email != null);
            allocator.free(u.name);
            if (u.email) |e| allocator.free(e);
            if (u.passwd) |p| allocator.free(p);
            if (u.avatar) |a| allocator.free(a);
        }
    }
    
    // Clean up
    dao.deleteAuthToken(allocator, auth_token.token) catch {};
    dao.deleteUser(allocator, "test_api_user") catch {};
}

test "SSH key API endpoints" {
    const allocator = std.testing.allocator;
    
    const test_db_url = std.posix.getenv("TEST_DATABASE_URL") orelse "postgresql://plue:plue_password@localhost:5432/plue";
    var dao = DataAccessObject.init(test_db_url) catch |err| switch (err) {
        error.ConnectionRefused => {
            std.log.warn("Database not available for testing, skipping", .{});
            return;
        },
        else => return err,
    };
    defer dao.deinit();
    
    // Clean up test data
    dao.deleteUser(allocator, "test_ssh_user") catch {};
    
    // Create test user
    const test_user = DataAccessObject.User{
        .id = 0,
        .name = "test_ssh_user",
        .email = "ssh@test.com",
        .passwd = null,
        .type = .individual,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, test_user);
    
    const user = try dao.getUserByName(allocator, "test_ssh_user") orelse unreachable;
    defer {
        allocator.free(user.name);
        if (user.email) |e| allocator.free(e);
        if (user.passwd) |p| allocator.free(p);
        if (user.avatar) |a| allocator.free(a);
    }
    
    // Test adding SSH key
    const test_key = DataAccessObject.PublicKey{
        .id = 0,
        .owner_id = user.id,
        .name = "Test Key",
        .content = "ssh-rsa AAAAB3NzaC1yc2EA... test@example.com",
        .fingerprint = "SHA256:test_fingerprint_12345",
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.addPublicKey(allocator, test_key);
    
    // Test listing SSH keys
    const keys = try dao.getUserPublicKeys(allocator, user.id);
    defer {
        for (keys) |key| {
            allocator.free(key.name);
            allocator.free(key.content);
            allocator.free(key.fingerprint);
        }
        allocator.free(keys);
    }
    
    try std.testing.expectEqual(@as(usize, 1), keys.len);
    try std.testing.expectEqualStrings("Test Key", keys[0].name);
    
    // Test deleting SSH key
    try dao.deletePublicKey(allocator, keys[0].id);
    
    const keys_after_delete = try dao.getUserPublicKeys(allocator, user.id);
    defer allocator.free(keys_after_delete);
    try std.testing.expectEqual(@as(usize, 0), keys_after_delete.len);
    
    // Clean up
    dao.deleteUser(allocator, "test_ssh_user") catch {};
}

test "organization API endpoints" {
    const allocator = std.testing.allocator;
    
    const test_db_url = std.posix.getenv("TEST_DATABASE_URL") orelse "postgresql://plue:plue_password@localhost:5432/plue";
    var dao = DataAccessObject.init(test_db_url) catch |err| switch (err) {
        error.ConnectionRefused => {
            std.log.warn("Database not available for testing, skipping", .{});
            return;
        },
        else => return err,
    };
    defer dao.deinit();
    
    // Clean up test data
    dao.deleteUser(allocator, "test_org_owner") catch {};
    dao.deleteUser(allocator, "test_org_member") catch {};
    dao.deleteUser(allocator, "test_organization") catch {};
    
    // Create owner user
    const owner = DataAccessObject.User{
        .id = 0,
        .name = "test_org_owner",
        .email = "owner@test.com",
        .passwd = null,
        .type = .individual,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, owner);
    
    const owner_user = try dao.getUserByName(allocator, "test_org_owner") orelse unreachable;
    defer {
        allocator.free(owner_user.name);
        if (owner_user.email) |e| allocator.free(e);
        if (owner_user.passwd) |p| allocator.free(p);
        if (owner_user.avatar) |a| allocator.free(a);
    }
    
    // Test creating organization
    const org = DataAccessObject.User{
        .id = 0,
        .name = "test_organization",
        .email = null,
        .passwd = null,
        .type = .organization,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, org);
    
    const created_org = try dao.getUserByName(allocator, "test_organization") orelse unreachable;
    defer {
        allocator.free(created_org.name);
        if (created_org.email) |e| allocator.free(e);
        if (created_org.passwd) |p| allocator.free(p);
        if (created_org.avatar) |a| allocator.free(a);
    }
    
    try std.testing.expectEqual(DataAccessObject.UserType.organization, created_org.type);
    
    // Add owner to organization
    try dao.addUserToOrg(allocator, owner_user.id, created_org.id, true);
    
    // Create member user
    const member = DataAccessObject.User{
        .id = 0,
        .name = "test_org_member",
        .email = "member@test.com",
        .passwd = null,
        .type = .individual,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, member);
    
    const member_user = try dao.getUserByName(allocator, "test_org_member") orelse unreachable;
    defer {
        allocator.free(member_user.name);
        if (member_user.email) |e| allocator.free(e);
        if (member_user.passwd) |p| allocator.free(p);
        if (member_user.avatar) |a| allocator.free(a);
    }
    
    // Add member to organization
    try dao.addUserToOrg(allocator, member_user.id, created_org.id, false);
    
    // Test listing organization members
    const members = try dao.getOrgUsers(allocator, created_org.id);
    defer allocator.free(members);
    
    try std.testing.expectEqual(@as(usize, 2), members.len);
    
    // Test user organizations
    const owner_orgs = try dao.getUserOrganizations(allocator, owner_user.id);
    defer {
        for (owner_orgs) |user_org| {
            allocator.free(user_org.org.name);
            if (user_org.org.email) |e| allocator.free(e);
            if (user_org.org.passwd) |p| allocator.free(p);
            if (user_org.org.avatar) |a| allocator.free(a);
        }
        allocator.free(owner_orgs);
    }
    
    try std.testing.expectEqual(@as(usize, 1), owner_orgs.len);
    try std.testing.expectEqualStrings("test_organization", owner_orgs[0].org.name);
    try std.testing.expectEqual(true, owner_orgs[0].is_owner);
    
    // Test removing member
    try dao.removeUserFromOrg(allocator, member_user.id, created_org.id);
    
    const members_after = try dao.getOrgUsers(allocator, created_org.id);
    defer allocator.free(members_after);
    try std.testing.expectEqual(@as(usize, 1), members_after.len);
    
    // Test updating organization avatar
    try dao.updateUserAvatar(allocator, created_org.id, "https://example.com/org-avatar.png");
    
    const updated_org = try dao.getUserById(allocator, created_org.id) orelse unreachable;
    defer {
        allocator.free(updated_org.name);
        if (updated_org.email) |e| allocator.free(e);
        if (updated_org.passwd) |p| allocator.free(p);
        if (updated_org.avatar) |a| allocator.free(a);
    }
    
    try std.testing.expect(updated_org.avatar != null);
    try std.testing.expectEqualStrings("https://example.com/org-avatar.png", updated_org.avatar.?);
    
    // Clean up
    dao.deleteUser(allocator, "test_org_owner") catch {};
    dao.deleteUser(allocator, "test_org_member") catch {};
    dao.deleteUser(allocator, "test_organization") catch {};
}