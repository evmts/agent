const std = @import("std");
const zap = @import("zap");
const server = @import("../server.zig");
const json = @import("../utils/json.zig");
const auth = @import("../utils/auth.zig");

const Context = server.Context;
const DataAccessObject = server.DataAccessObject;

pub fn getRepoHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract owner and repo name from path
    const path = r.path orelse return error.NoPath;
    // Handle path like "/repos/{owner}/{name}"
    const prefix = "/repos/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const path_parts = path[prefix.len..];
    const slash_pos = std.mem.indexOf(u8, path_parts, "/") orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    
    const owner_name = path_parts[0..slash_pos];
    const repo_name = path_parts[slash_pos + 1..];
    
    // Get owner user
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    const response = .{
        .id = repo.id,
        .owner = .{
            .id = owner.id,
            .login = owner.name,
            .type = @tagName(owner.type),
        },
        .name = repo.name,
        .full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ owner.name, repo.name }),
        .description = repo.description,
        .private = repo.is_private,
        .fork = repo.is_fork,
        .created_at = repo.created_unix,
        .updated_at = repo.updated_unix,
        .default_branch = repo.default_branch,
        .size = repo.size,
        .language = repo.language,
    };
    defer allocator.free(response.full_name);
    
    try json.writeJson(r, allocator, response);
}

pub fn updateRepoHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to update repo
    
    // Extract owner and repo name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/repos/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const path_parts = path[prefix.len..];
    const slash_pos = std.mem.indexOf(u8, path_parts, "/") orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    
    const owner_name = path_parts[0..slash_pos];
    const repo_name = path_parts[slash_pos + 1..];
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        description: ?[]const u8 = null,
        website: ?[]const u8 = null,
        private: ?bool = null,
        default_branch: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository to verify it exists
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // TODO: Actually update the repository in database
    
    const response = .{
        .id = repo.id,
        .owner = .{
            .id = owner.id,
            .login = owner.name,
            .type = @tagName(owner.type),
        },
        .name = repo.name,
        .full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ owner.name, repo.name }),
        .description = json_data.value.description orelse repo.description,
        .private = json_data.value.private orelse repo.is_private,
        .fork = repo.is_fork,
        .created_at = repo.created_unix,
        .updated_at = std.time.timestamp(),
        .default_branch = json_data.value.default_branch orelse repo.default_branch,
    };
    defer allocator.free(response.full_name);
    
    try json.writeJson(r, allocator, response);
}

pub fn deleteRepoHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to delete repo
    
    // Extract owner and repo name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/repos/";
    if (!std.mem.startsWith(u8, path, prefix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const path_parts = path[prefix.len..];
    const slash_pos = std.mem.indexOf(u8, path_parts, "/") orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    
    const owner_name = path_parts[0..slash_pos];
    const repo_name = path_parts[slash_pos + 1..];
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository to verify it exists
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Delete the repository
    ctx.dao.deleteRepository(repo.id) catch |err| {
        std.log.err("Failed to delete repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Failed to delete repository");
        return;
    };
    
    r.setStatus(.no_content);
}

pub fn forkRepoHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Extract owner and repo name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/repos/";
    const suffix = "/forks";
    
    if (!std.mem.startsWith(u8, path, prefix) or !std.mem.endsWith(u8, path, suffix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const path_middle = path[prefix.len .. path.len - suffix.len];
    const slash_pos = std.mem.indexOf(u8, path_middle, "/") orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    
    const owner_name = path_middle[0..slash_pos];
    const repo_name = path_middle[slash_pos + 1..];
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository to fork
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get forking user
    const forking_user = ctx.dao.getUserById(allocator, user_id) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(forking_user.name);
        if (forking_user.email) |e| allocator.free(e);
        if (forking_user.avatar) |a| allocator.free(a);
    }
    
    // TODO: Actually create the fork
    
    const response = .{
        .id = 999, // TODO: Get actual fork ID
        .owner = .{
            .id = forking_user.id,
            .login = forking_user.name,
            .type = @tagName(forking_user.type),
        },
        .name = repo.name,
        .full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ forking_user.name, repo.name }),
        .description = repo.description,
        .private = repo.is_private,
        .fork = true,
        .parent = .{
            .id = repo.id,
            .owner = .{
                .id = owner.id,
                .login = owner.name,
                .type = @tagName(owner.type),
            },
            .name = repo.name,
            .full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ owner.name, repo.name }),
        },
        .created_at = std.time.timestamp(),
        .updated_at = std.time.timestamp(),
    };
    defer allocator.free(response.full_name);
    defer allocator.free(response.parent.full_name);
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, response);
}

// Actions/CI secrets handlers for repositories
pub fn listRepoSecretsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to view repo secrets
    
    // Extract owner and repo name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/repos/";
    const suffix = "/actions/secrets";
    
    if (!std.mem.startsWith(u8, path, prefix) or !std.mem.endsWith(u8, path, suffix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const path_middle = path[prefix.len .. path.len - suffix.len];
    const slash_pos = std.mem.indexOf(u8, path_middle, "/") orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    
    const owner_name = path_middle[0..slash_pos];
    const repo_name = path_middle[slash_pos + 1..];
    _ = owner_name;
    _ = repo_name;
    
    // TODO: Fetch actual secrets from database
    const response = .{
        .total_count = 0,
        .secrets = [_]struct{}{},
    };
    
    try json.writeJson(r, allocator, response);
}

pub fn createRepoSecretHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to create repo secrets
    
    // Extract owner, repo name and secret name from path
    const path = r.path orelse return error.NoPath;
    // Handle path like "/repos/{owner}/{name}/actions/secrets/{secretname}"
    const prefix = "/repos/";
    const middle = "/actions/secrets/";
    
    // Find the repo part
    const path_after_prefix = path[prefix.len..];
    const middle_pos = std.mem.indexOf(u8, path_after_prefix, middle) orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    };
    
    const repo_path = path_after_prefix[0..middle_pos];
    const slash_pos = std.mem.indexOf(u8, repo_path, "/") orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    
    const owner_name = repo_path[0..slash_pos];
    const repo_name = repo_path[slash_pos + 1..];
    const secret_name = path_after_prefix[middle_pos + middle.len..];
    
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
    _ = owner_name;
    _ = repo_name;
    _ = secret_name;
    _ = json_data.value;
    
    r.setStatus(.created);
}

pub fn deleteRepoSecretHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to delete repo secrets
    
    // Extract owner, repo name and secret name from path
    const path = r.path orelse return error.NoPath;
    // Handle path like "/repos/{owner}/{name}/actions/secrets/{secretname}"
    const prefix = "/repos/";
    const middle = "/actions/secrets/";
    
    // Find the repo part
    const path_after_prefix = path[prefix.len..];
    const middle_pos = std.mem.indexOf(u8, path_after_prefix, middle) orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    };
    
    const repo_path = path_after_prefix[0..middle_pos];
    const slash_pos = std.mem.indexOf(u8, repo_path, "/") orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    
    const owner_name = repo_path[0..slash_pos];
    const repo_name = repo_path[slash_pos + 1..];
    const secret_name = path_after_prefix[middle_pos + middle.len..];
    
    // TODO: Actually delete the secret
    _ = owner_name;
    _ = repo_name;
    _ = secret_name;
    
    r.setStatus(.no_content);
}

// Actions/CI runners handlers for repositories
pub fn listRepoRunnersHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to view repo runners
    
    // Extract owner and repo name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/repos/";
    const suffix = "/actions/runners";
    
    if (!std.mem.startsWith(u8, path, prefix) or !std.mem.endsWith(u8, path, suffix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const path_middle = path[prefix.len .. path.len - suffix.len];
    const slash_pos = std.mem.indexOf(u8, path_middle, "/") orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    
    const owner_name = path_middle[0..slash_pos];
    const repo_name = path_middle[slash_pos + 1..];
    _ = owner_name;
    _ = repo_name;
    
    // TODO: Fetch actual runners from database
    const response = .{
        .total_count = 0,
        .runners = [_]struct{}{},
    };
    
    try json.writeJson(r, allocator, response);
}

pub fn getRepoRunnerTokenHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to get runner tokens
    
    // Extract owner and repo name from path
    const path = r.path orelse return error.NoPath;
    const prefix = "/repos/";
    const suffix = "/actions/runners/registration-token";
    
    if (!std.mem.startsWith(u8, path, prefix) or !std.mem.endsWith(u8, path, suffix)) {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    }
    
    const path_middle = path[prefix.len .. path.len - suffix.len];
    const slash_pos = std.mem.indexOf(u8, path_middle, "/") orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    
    const owner_name = path_middle[0..slash_pos];
    const repo_name = path_middle[slash_pos + 1..];
    _ = owner_name;
    _ = repo_name;
    
    // TODO: Generate actual registration token
    const response = .{
        .token = "FAKE_REPO_RUNNER_TOKEN",
        .expires_at = std.time.timestamp() + 3600, // 1 hour from now
    };
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, response);
}

pub fn deleteRepoRunnerHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    _ = user_id; // TODO: Check if user has permission to delete runners
    
    // Extract owner, repo name and runner ID from path
    const path = r.path orelse return error.NoPath;
    // Handle path like "/repos/{owner}/{name}/actions/runners/{runner_id}"
    const prefix = "/repos/";
    const middle = "/actions/runners/";
    
    // Find the repo part
    const path_after_prefix = path[prefix.len..];
    const middle_pos = std.mem.indexOf(u8, path_after_prefix, middle) orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path");
        return;
    };
    
    const repo_path = path_after_prefix[0..middle_pos];
    const slash_pos = std.mem.indexOf(u8, repo_path, "/") orelse {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    
    const owner_name = repo_path[0..slash_pos];
    const repo_name = repo_path[slash_pos + 1..];
    const runner_id_str = path_after_prefix[middle_pos + middle.len..];
    
    const runner_id = std.fmt.parseInt(i64, runner_id_str, 10) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid runner ID");
        return;
    };
    
    // TODO: Actually delete the runner
    _ = owner_name;
    _ = repo_name;
    _ = runner_id;
    
    r.setStatus(.no_content);
}