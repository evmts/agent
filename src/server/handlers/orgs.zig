const std = @import("std");
const zap = @import("zap");
const server = @import("../server.zig");
const json = @import("../utils/json.zig");
const auth = @import("../utils/auth.zig");

const Context = server.Context;
const DataAccessObject = server.DataAccessObject;

pub fn createOrgHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Implement organization creation with proper permissions
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        name: []const u8,
        description: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
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
            try json.writeError(r, allocator, .conflict, "Organization name already exists");
        } else {
            try json.writeError(r, allocator, .internal_server_error, "Failed to create organization");
        }
        return;
    };
    
    // TODO: Add the creator as an owner of the organization
    
    const response = .{
        .name = org_data.name,
        .description = org_data.description,
    };
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, response);
}

pub fn getOrgHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract org name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/orgs/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    const org_name = path[prefix.len..];
    
    // Get organization by name  
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.avatar) |a| allocator.free(a);
    }
    
    // Verify it's an organization
    if (org.type != .organization) {
        try json.writeError(r, allocator, .not_found, "Organization not found");
        return;
    }
    
    const response = .{
        .id = org.id,
        .name = org.name,
        .avatar = org.avatar,
        .created_at = org.created_unix,
        .updated_at = org.updated_unix,
    };
    
    try json.writeJson(r, allocator, response);
}

pub fn updateOrgHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to update org
    
    // Extract org name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/orgs/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    const org_name = path[prefix.len..];
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        description: ?[]const u8 = null,
        website: ?[]const u8 = null,
        location: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    // Get organization to verify it exists
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.avatar) |a| allocator.free(a);
    }
    
    // Verify it's an organization
    if (org.type != .organization) {
        try json.writeError(r, allocator, .not_found, "Organization not found");
        return;
    }
    
    // TODO: Actually update the organization details in database
    
    const response = .{
        .id = org.id,
        .name = org.name,
        .avatar = org.avatar,
        .created_at = org.created_unix,
        .updated_at = std.time.timestamp(),
    };
    
    try json.writeJson(r, allocator, response);
}

pub fn deleteOrgHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to delete org
    
    // Extract org name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/orgs/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    const org_name = path[prefix.len..];
    
    // Get organization to verify it exists
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.avatar) |a| allocator.free(a);
    }
    
    // Verify it's an organization
    if (org.type != .organization) {
        try json.writeError(r, allocator, .not_found, "Organization not found");
        return;
    }
    
    // Delete the organization
    ctx.dao.deleteUser(allocator, org.name) catch |err| {
        std.log.err("Failed to delete organization: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Failed to delete organization");
        return;
    };
    
    r.setStatus(.no_content);
}

pub fn listOrgMembersHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract org name from path
    const path = r.path orelse return error.NoPath;
    // Handle path like "/orgs/{org}/members"
    const prefix = "/orgs/";
    const suffix = "/members";
    
    if (!std.mem.startsWith(u8, path, prefix) or !std.mem.endsWith(u8, path, suffix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const org_name = path[prefix.len .. path.len - suffix.len];
    
    // Get organization to verify it exists
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.avatar) |a| allocator.free(a);
    }
    
    // TODO: Actually fetch organization members from database
    // For now, return empty array
    const members = [_]struct{}{};
    
    try json.writeJson(r, allocator, members);
}

pub fn removeOrgMemberHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to remove members
    
    // Extract org name and username from path
    const path = r.path orelse return error.NoPath;
    // Handle path like "/orgs/{org}/members/{username}"
    const prefix = "/orgs/";
    const middle = "/members/";
    
    const org_end = std.mem.indexOf(u8, path[prefix.len..], middle) orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    };
    
    const org_name = path[prefix.len..][0..org_end];
    const username = path[prefix.len + org_end + middle.len..];
    
    // TODO: Actually remove member from organization
    _ = org_name;
    _ = username;
    
    r.setStatus(.no_content);
}

pub fn createOrgRepoHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to create repos for org
    
    // Extract org name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/orgs/";
    const suffix = "/repos";
    
    if (!std.mem.startsWith(u8, path, prefix) or !std.mem.endsWith(u8, path, suffix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const org_name = path[prefix.len .. path.len - suffix.len];
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        name: []const u8,
        description: ?[]const u8 = null,
        private: bool = false,
    }, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const repo_data = json_data.value;
    
    // Get organization
    const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
        std.log.err("Failed to get organization: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Organization not found");
        return;
    };
    defer {
        allocator.free(org.name);
        if (org.email) |e| allocator.free(e);
        if (org.avatar) |a| allocator.free(a);
    }
    
    // TODO: Actually create repository for organization
    
    const response = .{
        .id = 1, // TODO: Get actual ID
        .name = repo_data.name,
        .full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ org_name, repo_data.name }),
        .description = repo_data.description,
        .private = repo_data.private,
        .owner = .{
            .id = org.id,
            .login = org.name,
            .type = "Organization",
        },
        .created_at = std.time.timestamp(),
        .updated_at = std.time.timestamp(),
    };
    defer allocator.free(response.full_name);
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, response);
}

// Actions/CI secrets handlers
pub fn listOrgSecretsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to view org secrets
    
    // Extract org name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/orgs/";
    const suffix = "/actions/secrets";
    
    if (!std.mem.startsWith(u8, path, prefix) or !std.mem.endsWith(u8, path, suffix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const org_name = path[prefix.len .. path.len - suffix.len];
    _ = org_name;
    
    // TODO: Fetch actual secrets from database
    const response = .{
        .total_count = 0,
        .secrets = [_]struct{}{},
    };
    
    try json.writeJson(r, allocator, response);
}

pub fn createOrgSecretHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to create org secrets
    
    // Extract org name and secret name from path
    const path = r.path orelse return error.NoPath;
    // Handle path like "/orgs/{org}/actions/secrets/{secretname}"
    const prefix = "/orgs/";
    const middle = "/actions/secrets/";
    
    const org_end = std.mem.indexOf(u8, path[prefix.len..], middle) orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    };
    
    const org_name = path[prefix.len..][0..org_end];
    const secret_name = path[prefix.len + org_end + middle.len..];
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        encrypted_value: []const u8,
        key_id: []const u8,
    }, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    // TODO: Actually create/update the secret
    _ = org_name;
    _ = secret_name;
    _ = json_data.value;
    
    r.setStatus(.created);
}

pub fn deleteOrgSecretHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to delete org secrets
    
    // Extract org name and secret name from path
    const path = r.path orelse return error.NoPath;
    // Handle path like "/orgs/{org}/actions/secrets/{secretname}"
    const prefix = "/orgs/";
    const middle = "/actions/secrets/";
    
    const org_end = std.mem.indexOf(u8, path[prefix.len..], middle) orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    };
    
    const org_name = path[prefix.len..][0..org_end];
    const secret_name = path[prefix.len + org_end + middle.len..];
    
    // TODO: Actually delete the secret
    _ = org_name;
    _ = secret_name;
    
    r.setStatus(.no_content);
}

// Actions/CI runners handlers
pub fn listOrgRunnersHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to view org runners
    
    // Extract org name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/orgs/";
    const suffix = "/actions/runners";
    
    if (!std.mem.startsWith(u8, path, prefix) or !std.mem.endsWith(u8, path, suffix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const org_name = path[prefix.len .. path.len - suffix.len];
    _ = org_name;
    
    // TODO: Fetch actual runners from database
    const response = .{
        .total_count = 0,
        .runners = [_]struct{}{},
    };
    
    try json.writeJson(r, allocator, response);
}

pub fn getOrgRunnerTokenHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to get runner tokens
    
    // Extract org name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/orgs/";
    const suffix = "/actions/runners/registration-token";
    
    if (!std.mem.startsWith(u8, path, prefix) or !std.mem.endsWith(u8, path, suffix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const org_name = path[prefix.len .. path.len - suffix.len];
    _ = org_name;
    
    // TODO: Generate actual registration token
    const response = .{
        .token = "FAKE_RUNNER_TOKEN",
        .expires_at = std.time.timestamp() + 3600, // 1 hour from now
    };
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, response);
}

pub fn deleteOrgRunnerHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to delete runners
    
    // Extract org name and runner ID from path
    const path = r.path orelse return error.NoPath;
    // Handle path like "/orgs/{org}/actions/runners/{runner_id}"
    const prefix = "/orgs/";
    const middle = "/actions/runners/";
    
    const org_end = std.mem.indexOf(u8, path[prefix.len..], middle) orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    };
    
    const org_name = path[prefix.len..][0..org_end];
    const runner_id_str = path[prefix.len + org_end + middle.len..];
    
    const runner_id = std.fmt.parseInt(i64, runner_id_str, 10) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid runner ID");
        return;
    };
    
    // TODO: Actually delete the runner
    _ = org_name;
    _ = runner_id;
    
    r.setStatus(.no_content);
}