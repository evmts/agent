const std = @import("std");
const httpz = @import("httpz");
const server = @import("../server.zig");
const json = @import("../utils/json.zig");
const auth = @import("../utils/auth.zig");

const Context = server.Context;
const DataAccessObject = server.DataAccessObject;

pub fn getRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const owner_name = req.param("owner") orelse {
        try json.writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner user
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    res.status = 200;
    try json.writeJson(res, allocator, .{
        .id = repo.id,
        .owner = .{
            .id = owner.id,
            .name = owner.name,
            .type = @tagName(owner.type),
        },
        .name = repo.name,
        .full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ owner.name, repo.name }),
        .description = repo.description,
        .private = repo.is_private,
        .fork = repo.is_fork,
        .fork_id = repo.fork_id,
        .default_branch = repo.default_branch,
        .created_at = try std.fmt.allocPrint(allocator, "{d}", .{repo.created_unix}),
        .updated_at = try std.fmt.allocPrint(allocator, "{d}", .{repo.updated_unix}),
    });
}

pub fn updateRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try json.writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    const body = req.body() orelse {
        try json.writeError(res, allocator, 400, "Request body required");
        return;
    };
    
    // Parse update request
    const parsed = std.json.parseFromSlice(struct {
        name: ?[]const u8 = null,
        description: ?[]const u8 = null,
        private: ?bool = null,
        default_branch: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try json.writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    const update_data = parsed.value;
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Check permissions
    if (owner.type == .individual) {
        if (owner.id != user_id) {
            try json.writeError(res, allocator, 403, "You don't have permission to update this repository");
            return;
        }
    } else { // organization
        const is_member = ctx.dao.isUserInOrg(allocator, user_id, owner.id) catch |err| {
            std.log.err("Failed to check org membership: {}", .{err});
            try json.writeError(res, allocator, 500, "Database error");
            return;
        };
        
        if (!is_member) {
            try json.writeError(res, allocator, 403, "You must be a member of the organization");
            return;
        }
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Update repository fields
    // TODO: Add updateRepository method to DAO to handle all updates at once
    if (update_data.name) |new_name| {
        ctx.dao.updateRepositoryName(allocator, repo.id, new_name) catch |err| {
            std.log.err("Failed to update repo name: {}", .{err});
            try json.writeError(res, allocator, 500, "Failed to update repository");
            return;
        };
    }
    
    res.status = 200;
    try json.writeJson(res, allocator, .{
        .message = "Repository updated successfully",
    });
}

pub fn deleteRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try json.writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Check permissions
    if (owner.type == .individual) {
        if (owner.id != user_id) {
            try json.writeError(res, allocator, 403, "You don't have permission to delete this repository");
            return;
        }
    } else { // organization
        const is_owner = ctx.dao.isUserOrgOwner(allocator, user_id, owner.id) catch |err| {
            std.log.err("Failed to check org ownership: {}", .{err});
            try json.writeError(res, allocator, 500, "Database error");
            return;
        };
        
        if (!is_owner) {
            try json.writeError(res, allocator, 403, "Only organization owners can delete repositories");
            return;
        }
    }
    
    // Get repository to verify it exists
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Delete repository
    ctx.dao.deleteRepository(allocator, repo.id) catch |err| {
        std.log.err("Failed to delete repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to delete repository");
        return;
    };
    
    res.status = 204;
}

pub fn forkRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try json.writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Parse request body for fork destination
    const body = req.body() orelse "{}";
    const parsed = std.json.parseFromSlice(struct {
        organization: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try json.writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    
    // Get source repository owner
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get source repository
    const source_repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(source_repo.name);
        if (source_repo.description) |d| allocator.free(d);
        allocator.free(source_repo.default_branch);
    }
    
    // Determine fork owner (user or organization)
    var fork_owner_id = user_id;
    if (parsed.value.organization) |org_name| {
        const org = ctx.dao.getUserByName(allocator, org_name) catch |err| {
            std.log.err("Failed to get organization: {}", .{err});
            try json.writeError(res, allocator, 500, "Database error");
            return;
        } orelse {
            try json.writeError(res, allocator, 404, "Organization not found");
            return;
        };
        defer {
            allocator.free(org.name);
            if (org.email) |e| allocator.free(e);
            if (org.avatar) |a| allocator.free(a);
        }
        
        // Check if user is member of org
        const is_member = ctx.dao.isUserInOrg(allocator, user_id, org.id) catch |err| {
            std.log.err("Failed to check org membership: {}", .{err});
            try json.writeError(res, allocator, 500, "Database error");
            return;
        };
        
        if (!is_member) {
            try json.writeError(res, allocator, 403, "You must be a member of the organization");
            return;
        }
        
        fork_owner_id = org.id;
    }
    
    // Check if fork already exists
    if (ctx.dao.getRepositoryByName(allocator, fork_owner_id, source_repo.name) catch null) |_| {
        try json.writeError(res, allocator, 409, "Repository already exists");
        return;
    }
    
    // Create fork
    const fork = DataAccessObject.Repository{
        .id = 0,
        .owner_id = fork_owner_id,
        .name = source_repo.name,
        .description = source_repo.description,
        .is_private = source_repo.is_private,
        .is_fork = true,
        .fork_id = source_repo.id,
        .default_branch = source_repo.default_branch,
        .created_unix = 0,
        .updated_unix = 0,
    };
    
    ctx.dao.createRepository(allocator, fork) catch |err| {
        std.log.err("Failed to create fork: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to create fork");
        return;
    };
    
    // Get created fork
    const created_fork = ctx.dao.getRepositoryByName(allocator, fork_owner_id, source_repo.name) catch |err| {
        std.log.err("Failed to fetch created fork: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(created_fork.name);
        if (created_fork.description) |d| allocator.free(d);
        allocator.free(created_fork.default_branch);
    }
    
    // Get fork owner info
    const fork_owner = ctx.dao.getUserById(allocator, fork_owner_id) catch |err| {
        std.log.err("Failed to get fork owner: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(fork_owner.name);
        if (fork_owner.email) |e| allocator.free(e);
        if (fork_owner.avatar) |a| allocator.free(a);
    }
    
    const response = .{
        .id = created_fork.id,
        .owner = .{
            .id = fork_owner.id,
            .name = fork_owner.name,
            .type = @tagName(fork_owner.type),
        },
        .name = created_fork.name,
        .full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ fork_owner.name, created_fork.name }),
        .description = created_fork.description,
        .private = created_fork.is_private,
        .fork = true,
        .parent = .{
            .id = source_repo.id,
            .owner = .{
                .id = owner.id,
                .name = owner.name,
                .type = @tagName(owner.type),
            },
            .name = source_repo.name,
            .full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ owner.name, source_repo.name }),
        },
        .default_branch = created_fork.default_branch,
        .created_at = try std.fmt.allocPrint(allocator, "{d}", .{created_fork.created_unix}),
        .updated_at = try std.fmt.allocPrint(allocator, "{d}", .{created_fork.updated_unix}),
    };
    defer {
        allocator.free(response.full_name);
        allocator.free(response.parent.full_name);
        allocator.free(response.created_at);
        allocator.free(response.updated_at);
    }
    
    res.status = 202;
    try json.writeJson(res, allocator, response);
}

// Repository secrets handlers (part of Actions/CI)
pub fn listRepoSecretsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try json.writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner and verify permissions
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    const has_permission = if (owner.type == .individual)
        owner.id == user_id
    else
        ctx.dao.isUserInOrg(allocator, user_id, owner.id) catch false;
    
    if (!has_permission) {
        try json.writeError(res, allocator, 403, "You don't have permission to view repository secrets");
        return;
    }
    
    // Get secrets
    const secrets = ctx.dao.getRepoSecrets(allocator, repo.id) catch |err| {
        std.log.err("Failed to get repo secrets: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (secrets) |secret| {
            allocator.free(secret.name);
        }
        allocator.free(secrets);
    }
    
    // Build response
    var response_items = try allocator.alloc(@TypeOf(response_items[0]), secrets.len);
    defer allocator.free(response_items);
    
    for (secrets, 0..) |secret, i| {
        response_items[i] = .{
            .name = secret.name,
            .created_at = try std.fmt.allocPrint(allocator, "{d}", .{secret.created_unix}),
            .updated_at = try std.fmt.allocPrint(allocator, "{d}", .{secret.updated_unix}),
        };
        defer allocator.free(response_items[i].created_at);
        defer allocator.free(response_items[i].updated_at);
    }
    
    res.status = 200;
    try json.writeJson(res, allocator, .{
        .total_count = secrets.len,
        .secrets = response_items,
    });
}

pub fn createRepoSecretHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try json.writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const secret_name = req.param("secretname") orelse {
        try json.writeError(res, allocator, 400, "Missing secretname parameter");
        return;
    };
    
    const body = req.body() orelse {
        try json.writeError(res, allocator, 400, "Request body required");
        return;
    };
    
    // Parse request
    const parsed = std.json.parseFromSlice(struct {
        encrypted_value: []const u8,
    }, allocator, body, .{}) catch {
        try json.writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    
    // Get owner and verify permissions
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    const has_permission = if (owner.type == .individual)
        owner.id == user_id
    else
        ctx.dao.isUserInOrg(allocator, user_id, owner.id) catch false;
    
    if (!has_permission) {
        try json.writeError(res, allocator, 403, "You don't have permission to create repository secrets");
        return;
    }
    
    // Create or update secret
    const secret = DataAccessObject.ActionSecret{
        .id = 0,
        .owner_id = repo.id,
        .owner_type = .repository,
        .name = secret_name,
        .encrypted_value = parsed.value.encrypted_value,
        .created_unix = 0,
        .updated_unix = 0,
    };
    
    const created = ctx.dao.createOrUpdateSecret(allocator, secret) catch |err| {
        std.log.err("Failed to create/update secret: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to create secret");
        return;
    };
    
    res.status = if (created) 201 else 204;
}

pub fn deleteRepoSecretHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try json.writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const secret_name = req.param("secretname") orelse {
        try json.writeError(res, allocator, 400, "Missing secretname parameter");
        return;
    };
    
    // Get owner and verify permissions
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    const has_permission = if (owner.type == .individual)
        owner.id == user_id
    else
        ctx.dao.isUserInOrg(allocator, user_id, owner.id) catch false;
    
    if (!has_permission) {
        try json.writeError(res, allocator, 403, "You don't have permission to delete repository secrets");
        return;
    }
    
    // Delete secret
    ctx.dao.deleteSecret(allocator, repo.id, .repository, secret_name) catch |err| {
        std.log.err("Failed to delete secret: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to delete secret");
        return;
    };
    
    res.status = 204;
}

// Repository runners handlers
pub fn listRepoRunnersHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try json.writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner and verify permissions
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    const has_permission = if (owner.type == .individual)
        owner.id == user_id
    else
        ctx.dao.isUserInOrg(allocator, user_id, owner.id) catch false;
    
    if (!has_permission) {
        try json.writeError(res, allocator, 403, "You don't have permission to view repository runners");
        return;
    }
    
    // Get runners
    const runners = ctx.dao.getRepoRunners(allocator, repo.id) catch |err| {
        std.log.err("Failed to get repo runners: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (runners) |runner| {
            allocator.free(runner.name);
            allocator.free(runner.os);
            allocator.free(runner.status);
        }
        allocator.free(runners);
    }
    
    // Build response
    var response_items = try allocator.alloc(@TypeOf(response_items[0]), runners.len);
    defer allocator.free(response_items);
    
    for (runners, 0..) |runner, i| {
        response_items[i] = .{
            .id = runner.id,
            .name = runner.name,
            .os = runner.os,
            .status = runner.status,
            .busy = runner.busy,
            .labels = &[_][]const u8{}, // TODO: Add runner labels
        };
    }
    
    res.status = 200;
    try json.writeJson(res, allocator, .{
        .total_count = runners.len,
        .runners = response_items,
    });
}

pub fn getRepoRunnerTokenHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try json.writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    
    // Get owner and verify permissions
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    const has_permission = if (owner.type == .individual)
        owner.id == user_id
    else
        ctx.dao.isUserInOrg(allocator, user_id, owner.id) catch false;
    
    if (!has_permission) {
        try json.writeError(res, allocator, 403, "You don't have permission to generate runner tokens");
        return;
    }
    
    // Generate token
    const token = ctx.dao.createRunnerToken(allocator, repo.id, .repository) catch |err| {
        std.log.err("Failed to create runner token: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to create token");
        return;
    };
    defer allocator.free(token.token);
    
    res.status = 201;
    try json.writeJson(res, allocator, .{
        .token = token.token,
        .expires_at = try std.fmt.allocPrint(allocator, "{d}", .{token.expires_unix}),
    });
}

pub fn deleteRepoRunnerHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const owner_name = req.param("owner") orelse {
        try json.writeError(res, allocator, 400, "Missing owner parameter");
        return;
    };
    const repo_name = req.param("name") orelse {
        try json.writeError(res, allocator, 400, "Missing name parameter");
        return;
    };
    const runner_id_str = req.param("runner_id") orelse {
        try json.writeError(res, allocator, 400, "Missing runner_id parameter");
        return;
    };
    
    const runner_id = std.fmt.parseInt(i64, runner_id_str, 10) catch {
        try json.writeError(res, allocator, 400, "Invalid runner ID");
        return;
    };
    
    // Get owner and verify permissions
    const owner = ctx.dao.getUserByName(allocator, owner_name) catch |err| {
        std.log.err("Failed to get owner: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Owner not found");
        return;
    };
    defer {
        allocator.free(owner.name);
        if (owner.email) |e| allocator.free(e);
        if (owner.avatar) |a| allocator.free(a);
    }
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, owner.id, repo_name) catch |err| {
        std.log.err("Failed to get repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check permissions
    const has_permission = if (owner.type == .individual)
        owner.id == user_id
    else
        ctx.dao.isUserInOrg(allocator, user_id, owner.id) catch false;
    
    if (!has_permission) {
        try json.writeError(res, allocator, 403, "You don't have permission to delete repository runners");
        return;
    }
    
    // Delete runner
    ctx.dao.deleteRunner(allocator, runner_id, repo.id, .repository) catch |err| {
        std.log.err("Failed to delete runner: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to delete runner");
        return;
    };
    
    res.status = 204;
}

// Tests
test "repository handlers" {
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
    dao.deleteUser(allocator, "test_repo_owner") catch {};
    
    // Create test user
    const test_user = DataAccessObject.User{
        .id = 0,
        .name = "test_repo_owner",
        .email = "repo@test.com",
        .password_hash = "hashed",
        .is_admin = false,
        .type = .individual,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, test_user);
    
    const user = (try dao.getUserByName(allocator, "test_repo_owner")).?;
    defer {
        allocator.free(user.name);
        if (user.email) |e| allocator.free(e);
        if (user.avatar) |a| allocator.free(a);
    }
    
    // Test repository creation and operations
    {
        const test_repo = DataAccessObject.Repository{
            .id = 0,
            .owner_id = user.id,
            .name = "test-repo",
            .description = "Test repository",
            .is_private = false,
            .is_fork = false,
            .fork_id = null,
            .default_branch = "main",
            .created_unix = 0,
            .updated_unix = 0,
        };
        try dao.createRepository(allocator, test_repo);
        
        const repo = (try dao.getRepositoryByName(allocator, user.id, "test-repo")).?;
        defer {
            allocator.free(repo.name);
            if (repo.description) |d| allocator.free(d);
            allocator.free(repo.default_branch);
        }
        
        try std.testing.expectEqualStrings("test-repo", repo.name);
        try std.testing.expectEqualStrings("Test repository", repo.description.?);
        try std.testing.expect(!repo.is_private);
        try std.testing.expect(!repo.is_fork);
    }
    
    // Clean up
    dao.deleteUser(allocator, "test_repo_owner") catch {};
}