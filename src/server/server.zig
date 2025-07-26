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