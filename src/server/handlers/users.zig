const std = @import("std");
const zap = @import("zap");
const server = @import("../server.zig");
const json = @import("../utils/json.zig");
const auth = @import("../utils/auth.zig");

const Context = server.Context;

pub fn getCurrentUserHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Get user by ID
    const user = ctx.dao.getUserById(allocator, user_id) catch |err| {
        std.log.err("Failed to get user by ID: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "User not found");
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
    
    try json.writeJson(r, allocator, response);
}

pub fn getUsersHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const users = ctx.dao.listUsers(allocator) catch |err| {
        std.log.err("Failed to list users: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
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
    const ResponseItem = struct {
        id: i64,
        name: []const u8,
        email: ?[]const u8,
        type: []const u8,
        is_admin: bool,
        avatar: ?[]const u8,
        created_unix: i64,
        updated_unix: i64,
    };
    var response_items = try allocator.alloc(ResponseItem, users.len);
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
    
    try json.writeJson(r, allocator, response_items);
}

pub fn createUserHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Parse request body
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreateUserRequest = struct {
        name: []const u8,
        email: ?[]const u8 = null,
        password: []const u8,
        is_admin: bool = false,
    };
    
    const parsed = std.json.parseFromSlice(CreateUserRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    
    const request = parsed.value;
    
    // Create user
    const user_id = ctx.dao.createUser(request.name, request.email, request.password, request.is_admin) catch |err| {
        std.log.err("Failed to create user: {}", .{err});
        if (err == error.UniqueViolation) {
            try json.writeError(r, allocator, .conflict, "User already exists");
        } else {
            try json.writeError(r, allocator, .internal_server_error, "Database error");
        }
        return;
    };
    
    // Get created user
    const user = ctx.dao.getUserById(allocator, user_id) catch |err| {
        std.log.err("Failed to get created user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse unreachable;
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
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, response);
}

pub fn getUserHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract username from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/users/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    const username = path[prefix.len..];
    
    // Get user by name
    const user = ctx.dao.getUserByName(allocator, username) catch |err| {
        std.log.err("Failed to get user by name: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "User not found");
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
    
    try json.writeJson(r, allocator, response);
}

pub fn updateUserHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract username from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/users/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    const username = path[prefix.len..];
    
    // Parse request body
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const UpdateUserRequest = struct {
        email: ?[]const u8 = null,
        avatar: ?[]const u8 = null,
    };
    
    const parsed = std.json.parseFromSlice(UpdateUserRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    
    const request = parsed.value;
    
    // Get user to update
    const user = ctx.dao.getUserByName(allocator, username) catch |err| {
        std.log.err("Failed to get user by name: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "User not found");
        return;
    };
    defer {
        allocator.free(user.name);
        if (user.email) |e| allocator.free(e);
        if (user.avatar) |a| allocator.free(a);
    }
    
    // Update user
    ctx.dao.updateUser(user.id, request.email, request.avatar) catch |err| {
        std.log.err("Failed to update user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    };
    
    // Get updated user
    const updated_user = ctx.dao.getUserById(allocator, user.id) catch |err| {
        std.log.err("Failed to get updated user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
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
    
    try json.writeJson(r, allocator, response);
}

pub fn deleteUserHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract username from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/users/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    const username = path[prefix.len..];
    
    // Get user to delete
    const user = ctx.dao.getUserByName(allocator, username) catch |err| {
        std.log.err("Failed to get user by name: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "User not found");
        return;
    };
    defer {
        allocator.free(user.name);
        if (user.email) |e| allocator.free(e);
        if (user.avatar) |a| allocator.free(a);
    }
    
    // Delete user
    ctx.dao.deleteUser(user.id) catch |err| {
        std.log.err("Failed to delete user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    };
    
    r.setStatus(.no_content);
}

// SSH Key handlers
pub fn createSSHKeyHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Parse request body
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreateSSHKeyRequest = struct {
        title: []const u8,
        key: []const u8,
    };
    
    const parsed = std.json.parseFromSlice(CreateSSHKeyRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    
    const request = parsed.value;
    
    // Create SSH key
    const key_id = ctx.dao.createSSHKey(user_id, request.title, request.key) catch |err| {
        std.log.err("Failed to create SSH key: {}", .{err});
        if (err == error.UniqueViolation) {
            try json.writeError(r, allocator, .conflict, "SSH key already exists");
        } else {
            try json.writeError(r, allocator, .internal_server_error, "Database error");
        }
        return;
    };
    
    const response = .{
        .id = key_id,
        .title = request.title,
        .key = request.key,
        .created_unix = std.time.timestamp(),
    };
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, response);
}

pub fn listSSHKeysHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const keys = ctx.dao.listSSHKeys(allocator, user_id) catch |err| {
        std.log.err("Failed to list SSH keys: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    };
    defer {
        for (keys) |key| {
            allocator.free(key.title);
            allocator.free(key.key);
        }
        allocator.free(keys);
    }
    
    // Build response array
    const ResponseItem = struct {
        id: i64,
        title: []const u8,
        key: []const u8,
        created_unix: i64,
    };
    var response_items = try allocator.alloc(ResponseItem, keys.len);
    defer allocator.free(response_items);
    
    for (keys, 0..) |key, i| {
        response_items[i] = .{
            .id = key.id,
            .title = key.title,
            .key = key.key,
            .created_unix = key.created_unix,
        };
    }
    
    try json.writeJson(r, allocator, response_items);
}

pub fn deleteSSHKeyHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Extract key ID from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/user/keys/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    const key_id_str = path[prefix.len..];
    const key_id = std.fmt.parseInt(i64, key_id_str, 10) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid key ID");
        return;
    };
    
    // Delete SSH key
    ctx.dao.deleteSSHKey(user_id, key_id) catch |err| {
        std.log.err("Failed to delete SSH key: {}", .{err});
        if (err == error.NotFound) {
            try json.writeError(r, allocator, .not_found, "SSH key not found");
        } else {
            try json.writeError(r, allocator, .internal_server_error, "Database error");
        }
        return;
    };
    
    r.setStatus(.no_content);
}

// Organization membership handlers
pub fn listUserOrgsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const orgs = ctx.dao.listUserOrganizations(allocator, user_id) catch |err| {
        std.log.err("Failed to list user organizations: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    };
    defer {
        for (orgs) |org| {
            allocator.free(org.name);
            if (org.description) |d| allocator.free(d);
            if (org.website) |w| allocator.free(w);
            if (org.location) |l| allocator.free(l);
            if (org.avatar) |a| allocator.free(a);
        }
        allocator.free(orgs);
    }
    
    // Build response array
    const ResponseItem = struct {
        id: i64,
        name: []const u8,
        description: ?[]const u8,
        website: ?[]const u8,
        location: ?[]const u8,
        avatar: ?[]const u8,
        created_unix: i64,
        updated_unix: i64,
    };
    var response_items = try allocator.alloc(ResponseItem, orgs.len);
    defer allocator.free(response_items);
    
    for (orgs, 0..) |org, i| {
        response_items[i] = .{
            .id = org.id,
            .name = org.name,
            .description = org.description,
            .website = org.website,
            .location = org.location,
            .avatar = org.avatar,
            .created_unix = org.created_unix,
            .updated_unix = org.updated_unix,
        };
    }
    
    try json.writeJson(r, allocator, response_items);
}

// Repository creation handler
pub fn createUserRepoHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Parse request body
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreateRepoRequest = struct {
        name: []const u8,
        description: ?[]const u8 = null,
        is_private: bool = false,
        auto_init: bool = false,
        gitignore: ?[]const u8 = null,
        license: ?[]const u8 = null,
    };
    
    const parsed = std.json.parseFromSlice(CreateRepoRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    
    const request = parsed.value;
    
    // Create repository
    const repo_id = ctx.dao.createRepository(
        user_id,
        null, // org_id
        request.name,
        request.description,
        request.is_private,
    ) catch |err| {
        std.log.err("Failed to create repository: {}", .{err});
        if (err == error.UniqueViolation) {
            try json.writeError(r, allocator, .conflict, "Repository already exists");
        } else {
            try json.writeError(r, allocator, .internal_server_error, "Database error");
        }
        return;
    };
    
    // Get created repository
    const repo = ctx.dao.getRepositoryById(allocator, repo_id) catch |err| {
        std.log.err("Failed to get created repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        if (repo.default_branch) |b| allocator.free(b);
        if (repo.website) |w| allocator.free(w);
    }
    
    // Get owner details
    const user = ctx.dao.getUserById(allocator, user_id) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(user.name);
        if (user.email) |e| allocator.free(e);
        if (user.avatar) |a| allocator.free(a);
    }
    
    const response = .{
        .id = repo.id,
        .owner = .{
            .id = user.id,
            .name = user.name,
            .type = @tagName(user.type),
        },
        .name = repo.name,
        .full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ user.name, repo.name }),
        .description = repo.description,
        .is_private = repo.is_private,
        .is_fork = repo.is_fork,
        .created_unix = repo.created_unix,
        .updated_unix = repo.updated_unix,
    };
    defer allocator.free(response.full_name);
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, response);
}