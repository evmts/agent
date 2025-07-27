const std = @import("std");
const httpz = @import("httpz");
const server = @import("../server.zig");
const json = @import("../utils/json.zig");
const auth = @import("../utils/auth.zig");

const Context = server.Context;

pub fn getCurrentUserHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    // Get user by ID
    const user = ctx.dao.getUserById(allocator, user_id) catch |err| {
        std.log.err("Failed to get user by ID: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "User not found");
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
    try json.writeJson(res, allocator, response);
}

pub fn getUsersHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    const users = ctx.dao.listUsers(allocator) catch |err| {
        std.log.err("Failed to list users: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (users) |user| {
            allocator.free(user.name);
            if (user.email) |e| allocator.free(e);
            if (user.avatar) |a| allocator.free(a);
        }
        allocator.free(users);
    }
    
    // Build response array
    var response_items = try allocator.alloc(@TypeOf(response_items[0]), users.len);
    defer allocator.free(response_items);
    
    for (users, 0..) |user, i| {
        response_items[i] = .{
            .id = user.id,
            .name = user.name,
            .email = user.email,
            .type = @tagName(user.type),
            .is_admin = user.is_admin,
            .avatar = user.avatar,
            .created_unix = user.created_unix,
            .updated_unix = user.updated_unix,
        };
    }
    
    res.status = 200;
    try json.writeJson(res, allocator, response_items);
}

pub fn createUserHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Parse request body
    const body = req.body() orelse {
        try json.writeError(res, allocator, 400, "Request body required");
        return;
    };
    
    const CreateUserRequest = struct {
        name: []const u8,
        email: ?[]const u8 = null,
        password: []const u8,
        is_admin: bool = false,
    };
    
    const parsed = std.json.parseFromSlice(CreateUserRequest, allocator, body, .{}) catch |err| {
        std.log.err("Failed to parse request body: {}", .{err});
        try json.writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    const create_req = parsed.value;
    
    // Validate input
    if (create_req.name.len == 0 or create_req.name.len > 255) {
        try json.writeError(res, allocator, 400, "Invalid name length");
        return;
    }
    
    if (create_req.password.len < 6) {
        try json.writeError(res, allocator, 400, "Password must be at least 6 characters");
        return;
    }
    
    // Check if user already exists
    if (ctx.dao.getUserByName(allocator, create_req.name) catch null) |_| {
        try json.writeError(res, allocator, 409, "User already exists");
        return;
    }
    
    // Create user
    const user = server.DataAccessObject.User{
        .id = 0, // Will be set by database
        .name = create_req.name,
        .email = create_req.email,
        .password_hash = create_req.password, // TODO: Hash password
        .is_admin = create_req.is_admin,
        .type = .individual,
        .avatar = null,
        .created_unix = 0, // Will be set by createUser
        .updated_unix = 0, // Will be set by createUser
    };
    
    ctx.dao.createUser(allocator, user) catch |err| {
        std.log.err("Failed to create user: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to create user");
        return;
    };
    
    // Return created user
    const created_user = ctx.dao.getUserByName(allocator, create_req.name) catch |err| {
        std.log.err("Failed to fetch created user: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(created_user.name);
        if (created_user.email) |e| allocator.free(e);
        if (created_user.avatar) |a| allocator.free(a);
    }
    
    const response = .{
        .id = created_user.id,
        .name = created_user.name,
        .email = created_user.email,
        .type = @tagName(created_user.type),
        .is_admin = created_user.is_admin,
        .created_unix = created_user.created_unix,
    };
    
    res.status = 201;
    try json.writeJson(res, allocator, response);
}

pub fn getUserHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Name parameter required");
        return;
    };
    
    const user = ctx.dao.getUserByName(allocator, name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "User not found");
        return;
    };
    defer {
        allocator.free(user.name);
        if (user.email) |e| allocator.free(e);
        if (user.avatar) |a| allocator.free(a);
    }
    
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
    try json.writeJson(res, allocator, response);
}

pub fn updateUserHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Name parameter required");
        return;
    };
    
    // Parse request body
    const body = req.body() orelse {
        try json.writeError(res, allocator, 400, "Request body required");
        return;
    };
    
    const UpdateUserRequest = struct {
        name: ?[]const u8 = null,
        email: ?[]const u8 = null,
        avatar: ?[]const u8 = null,
    };
    
    const parsed = std.json.parseFromSlice(UpdateUserRequest, allocator, body, .{}) catch |err| {
        std.log.err("Failed to parse request body: {}", .{err});
        try json.writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    const update_req = parsed.value;
    
    // Check if user exists
    const existing_user = ctx.dao.getUserByName(allocator, name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "User not found");
        return;
    };
    defer {
        allocator.free(existing_user.name);
        if (existing_user.email) |e| allocator.free(e);
        if (existing_user.avatar) |a| allocator.free(a);
    }
    
    // Update user fields
    if (update_req.name) |new_name| {
        ctx.dao.updateUserName(allocator, name, new_name) catch |err| {
            std.log.err("Failed to update user name: {}", .{err});
            try json.writeError(res, allocator, 500, "Failed to update user");
            return;
        };
    }
    
    // TODO: Add update methods for email and avatar when available in DAO
    
    // Return updated user
    const updated_name = update_req.name orelse name;
    const updated_user = ctx.dao.getUserByName(allocator, updated_name) catch |err| {
        std.log.err("Failed to fetch updated user: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(updated_user.name);
        if (updated_user.email) |e| allocator.free(e);
        if (updated_user.avatar) |a| allocator.free(a);
    }
    
    const response = .{
        .id = updated_user.id,
        .name = updated_user.name,
        .email = updated_user.email,
        .type = @tagName(updated_user.type),
        .is_admin = updated_user.is_admin,
        .avatar = updated_user.avatar,
        .created_unix = updated_user.created_unix,
        .updated_unix = updated_user.updated_unix,
    };
    
    res.status = 200;
    try json.writeJson(res, allocator, response);
}

pub fn deleteUserHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Name parameter required");
        return;
    };
    
    ctx.dao.deleteUser(allocator, name) catch |err| switch (err) {
        error.UserNotFound => {
            try json.writeError(res, allocator, 404, "User not found");
            return;
        },
        else => {
            std.log.err("Failed to delete user: {}", .{err});
            try json.writeError(res, allocator, 500, "Failed to delete user");
            return;
        },
    };
    
    res.status = 204;
}

pub fn createSSHKeyHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    // Parse request body
    const body = req.body() orelse {
        try json.writeError(res, allocator, 400, "Request body required");
        return;
    };
    
    const CreateSSHKeyRequest = struct {
        name: []const u8,
        key: []const u8,
    };
    
    const parsed = std.json.parseFromSlice(CreateSSHKeyRequest, allocator, body, .{}) catch |err| {
        std.log.err("Failed to parse request body: {}", .{err});
        try json.writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    const key_req = parsed.value;
    
    // Validate SSH key format
    if (!std.mem.startsWith(u8, key_req.key, "ssh-rsa ") and 
        !std.mem.startsWith(u8, key_req.key, "ssh-ed25519 ") and
        !std.mem.startsWith(u8, key_req.key, "ecdsa-sha2-")) {
        try json.writeError(res, allocator, 400, "Invalid SSH key format");
        return;
    }
    
    // Create the SSH key
    const key_id = ctx.dao.addPublicKey(allocator, user_id, key_req.name, key_req.key) catch |err| {
        std.log.err("Failed to add SSH key: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to add SSH key");
        return;
    };
    
    const response = .{
        .id = key_id,
        .name = key_req.name,
        .key = key_req.key,
        .created_unix = std.time.timestamp(),
    };
    
    res.status = 201;
    try json.writeJson(res, allocator, response);
}

pub fn listSSHKeysHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const keys = ctx.dao.getUserPublicKeys(allocator, user_id) catch |err| {
        std.log.err("Failed to list SSH keys: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (keys) |key| {
            allocator.free(key.name);
            allocator.free(key.key);
        }
        allocator.free(keys);
    }
    
    // Build response array
    var response_items = try allocator.alloc(@TypeOf(response_items[0]), keys.len);
    defer allocator.free(response_items);
    
    for (keys, 0..) |key, i| {
        response_items[i] = .{
            .id = key.id,
            .name = key.name,
            .key = key.key,
            .created_unix = key.created_unix,
        };
    }
    
    res.status = 200;
    try json.writeJson(res, allocator, response_items);
}

pub fn deleteSSHKeyHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const key_id_str = req.param("id") orelse {
        try json.writeError(res, allocator, 400, "Key ID parameter required");
        return;
    };
    
    const key_id = std.fmt.parseInt(i64, key_id_str, 10) catch {
        try json.writeError(res, allocator, 400, "Invalid key ID");
        return;
    };
    
    // Verify the key belongs to the user
    const keys = ctx.dao.getUserPublicKeys(allocator, user_id) catch |err| {
        std.log.err("Failed to list SSH keys: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (keys) |key| {
            allocator.free(key.name);
            allocator.free(key.key);
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
        try json.writeError(res, allocator, 404, "SSH key not found");
        return;
    }
    
    // TODO: Add deletePublicKey method to DAO
    // ctx.dao.deletePublicKey(allocator, key_id) catch |err| {
    //     std.log.err("Failed to delete SSH key: {}", .{err});
    //     try json.writeError(res, allocator, 500, "Failed to delete SSH key");
    //     return;
    // };
    
    res.status = 204;
}

pub fn listUserOrgsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    // Get organizations for user
    const orgs = ctx.dao.getUserOrganizations(allocator, user_id) catch |err| {
        std.log.err("Failed to list user organizations: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (orgs) |org| {
            allocator.free(org.name);
            if (org.email) |e| allocator.free(e);
            if (org.avatar) |a| allocator.free(a);
        }
        allocator.free(orgs);
    }
    
    // Build response array
    var response_items = try allocator.alloc(@TypeOf(response_items[0]), orgs.len);
    defer allocator.free(response_items);
    
    for (orgs, 0..) |org, i| {
        response_items[i] = .{
            .id = org.id,
            .name = org.name,
            .description = org.email, // Using email field as description for orgs
            .avatar = org.avatar,
            .created_unix = org.created_unix,
        };
    }
    
    res.status = 200;
    try json.writeJson(res, allocator, response_items);
}

pub fn createUserRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    // Parse request body
    const body = req.body() orelse {
        try json.writeError(res, allocator, 400, "Request body required");
        return;
    };
    
    const CreateRepoRequest = struct {
        name: []const u8,
        description: ?[]const u8 = null,
        private: bool = false,
        default_branch: []const u8 = "main",
    };
    
    const parsed = std.json.parseFromSlice(CreateRepoRequest, allocator, body, .{}) catch |err| {
        std.log.err("Failed to parse request body: {}", .{err});
        try json.writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    const repo_req = parsed.value;
    
    // Validate repository name
    if (repo_req.name.len == 0 or repo_req.name.len > 255) {
        try json.writeError(res, allocator, 400, "Invalid repository name length");
        return;
    }
    
    // Check if repository already exists
    if (ctx.dao.getRepositoryByName(allocator, user_id, repo_req.name) catch null) |_| {
        try json.writeError(res, allocator, 409, "Repository already exists");
        return;
    }
    
    // Create repository
    const repo = server.DataAccessObject.Repository{
        .id = 0, // Will be set by database
        .owner_id = user_id,
        .name = repo_req.name,
        .description = repo_req.description,
        .is_private = repo_req.private,
        .default_branch = repo_req.default_branch,
        .created_unix = 0, // Will be set by createRepository
        .updated_unix = 0, // Will be set by createRepository
    };
    
    ctx.dao.createRepository(allocator, repo) catch |err| {
        std.log.err("Failed to create repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to create repository");
        return;
    };
    
    // Get created repository
    const created_repo = ctx.dao.getRepositoryByName(allocator, user_id, repo_req.name) catch |err| {
        std.log.err("Failed to fetch created repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(created_repo.name);
        if (created_repo.description) |d| allocator.free(d);
        allocator.free(created_repo.default_branch);
    }
    
    // Get owner info
    const owner = ctx.dao.getUserById(allocator, user_id) catch |err| {
        std.log.err("Failed to get owner info: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const response = .{
        .id = created_repo.id,
        .owner = .{
            .id = owner.id,
            .name = owner.name,
            .type = @tagName(owner.type),
        },
        .name = created_repo.name,
        .full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ owner.name, created_repo.name }),
        .description = created_repo.description,
        .private = created_repo.is_private,
        .default_branch = created_repo.default_branch,
        .created_at = try std.fmt.allocPrint(allocator, "{d}", .{created_repo.created_unix}),
        .updated_at = try std.fmt.allocPrint(allocator, "{d}", .{created_repo.updated_unix}),
    };
    defer {
        allocator.free(response.full_name);
        allocator.free(response.created_at);
        allocator.free(response.updated_at);
    }
    
    res.status = 201;
    try json.writeJson(res, allocator, response);
}

// Tests
test "user handlers" {
    const allocator = std.testing.allocator;
    
    // Initialize test database
    const test_db_url = std.posix.getenv("TEST_DATABASE_URL") orelse "postgresql://plue:plue_password@localhost:5432/plue";
    var dao = server.DataAccessObject.init(test_db_url) catch |err| switch (err) {
        error.ConnectionRefused => {
            std.log.warn("Database not available for testing, skipping", .{});
            return;
        },
        else => return err,
    };
    defer dao.deinit();
    
    // Clean up test data
    dao.deleteUser(allocator, "test_user_handler") catch {};
    
    // Test user creation and retrieval
    {
        const test_user = server.DataAccessObject.User{
            .id = 0,
            .name = "test_user_handler",
            .email = "test@example.com",
            .password_hash = "hashed_password",
            .is_admin = false,
            .type = .individual,
            .avatar = null,
            .created_unix = 0,
            .updated_unix = 0,
        };
        
        try dao.createUser(allocator, test_user);
        
        const retrieved = try dao.getUserByName(allocator, "test_user_handler");
        try std.testing.expect(retrieved != null);
        if (retrieved) |user| {
            defer {
                allocator.free(user.name);
                if (user.email) |e| allocator.free(e);
                if (user.avatar) |a| allocator.free(a);
            }
            try std.testing.expectEqualStrings("test_user_handler", user.name);
            try std.testing.expectEqualStrings("test@example.com", user.email.?);
        }
    }
    
    // Clean up
    dao.deleteUser(allocator, "test_user_handler") catch {};
}