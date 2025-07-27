const std = @import("std");
const httpz = @import("httpz");
const server = @import("../server.zig");
const json = @import("../utils/json.zig");
const auth = @import("../utils/auth.zig");

const Context = server.Context;
const DataAccessObject = server.DataAccessObject;

pub fn createOrgHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const body = req.body() orelse {
        try json.writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        name: []const u8,
        description: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try json.writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const org_data = json_data.value;
    
    // Create organization as a user with type=organization
    const org = DataAccessObject.User{
        .id = 0,
        .name = org_data.name,
        .email = null,
        .password_hash = null,
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
            try json.writeError(res, allocator, 409, "Organization name already exists");
        } else {
            try json.writeError(res, allocator, 500, "Database error");
        }
        return;
    };
    
    // Get the created org to get its ID
    const created_org = ctx.dao.getUserByName(allocator, org_data.name) catch |err| {
        std.log.err("Failed to get created org: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 500, "Failed to retrieve created organization");
        return;
    };
    defer {
        allocator.free(created_org.name);
        if (created_org.email) |e| allocator.free(e);
        if (created_org.avatar) |a| allocator.free(a);
    }
    
    // Add the creator as owner
    ctx.dao.addUserToOrg(allocator, user_id, created_org.id, true) catch |err| {
        std.log.err("Failed to add user as org owner: {}", .{err});
        // Try to clean up the org
        ctx.dao.deleteUser(allocator, org_data.name) catch {};
        try json.writeError(res, allocator, 500, "Failed to set organization owner");
        return;
    };
    
    res.status = 201;
    try json.writeJson(res, allocator, .{
        .id = created_org.id,
        .name = created_org.name,
        .type = "organization",
    });
}

pub fn getOrgHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    // Get organization by name
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
    
    // Verify it's an organization
    if (org.type != .organization) {
        try json.writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    res.status = 200;
    try json.writeJson(res, allocator, .{
        .id = org.id,
        .name = org.name,
        .avatar = org.avatar,
        .description = org.email, // Using email field for description
        .created_unix = org.created_unix,
        .updated_unix = org.updated_unix,
    });
}

pub fn updateOrgHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    const body = req.body() orelse {
        try json.writeError(res, allocator, 400, "Missing request body");
        return;
    };
    
    // Parse JSON
    var json_data = std.json.parseFromSlice(struct {
        name: ?[]const u8 = null,
        description: ?[]const u8 = null,
        avatar: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try json.writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const update_data = json_data.value;
    
    // Get organization
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
    
    // Verify it's an organization
    if (org.type != .organization) {
        try json.writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Check if user is owner
    const is_owner = ctx.dao.isUserOrgOwner(allocator, user_id, org.id) catch |err| {
        std.log.err("Failed to check org ownership: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    
    if (!is_owner) {
        try json.writeError(res, allocator, 403, "Only organization owners can update organization");
        return;
    }
    
    // Update organization
    if (update_data.name) |new_name| {
        ctx.dao.updateUserName(allocator, org_name, new_name) catch |err| {
            std.log.err("Failed to update org name: {}", .{err});
            try json.writeError(res, allocator, 500, "Failed to update organization");
            return;
        };
    }
    
    // TODO: Update description (email) and avatar when DAO supports it
    
    res.status = 200;
    try json.writeJson(res, allocator, .{
        .message = "Organization updated successfully",
    });
}

pub fn deleteOrgHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    // Get organization
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
    
    // Verify it's an organization
    if (org.type != .organization) {
        try json.writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Check if user is owner
    const is_owner = ctx.dao.isUserOrgOwner(allocator, user_id, org.id) catch |err| {
        std.log.err("Failed to check org ownership: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    
    if (!is_owner) {
        try json.writeError(res, allocator, 403, "Only organization owners can delete organization");
        return;
    }
    
    // TODO: Check if org has repositories before deletion
    
    // Delete organization
    ctx.dao.deleteUser(allocator, org_name) catch |err| {
        std.log.err("Failed to delete organization: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to delete organization");
        return;
    };
    
    res.status = 204;
}

pub fn listOrgMembersHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    // Get organization
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
    
    // Verify it's an organization
    if (org.type != .organization) {
        try json.writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Get organization members
    const members = ctx.dao.getOrgUsers(allocator, org.id) catch |err| {
        std.log.err("Failed to get org members: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (members) |member| {
            allocator.free(member.user.name);
            if (member.user.email) |e| allocator.free(e);
            if (member.user.avatar) |a| allocator.free(a);
        }
        allocator.free(members);
    }
    
    // Build response
    var response_items = try allocator.alloc(@TypeOf(response_items[0]), members.len);
    defer allocator.free(response_items);
    
    for (members, 0..) |member, i| {
        response_items[i] = .{
            .id = member.user.id,
            .name = member.user.name,
            .email = member.user.email,
            .avatar = member.user.avatar,
            .is_owner = member.is_owner,
            .joined_unix = member.joined_unix,
        };
    }
    
    res.status = 200;
    try json.writeJson(res, allocator, response_items);
}

pub fn removeOrgMemberHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    const username = req.param("username") orelse {
        try json.writeError(res, allocator, 400, "Missing username parameter");
        return;
    };
    
    // Get organization
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
    
    // Verify it's an organization
    if (org.type != .organization) {
        try json.writeError(res, allocator, 404, "Organization not found");
        return;
    }
    
    // Check if user is owner
    const is_owner = ctx.dao.isUserOrgOwner(allocator, user_id, org.id) catch |err| {
        std.log.err("Failed to check org ownership: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    
    if (!is_owner) {
        try json.writeError(res, allocator, 403, "Only organization owners can remove members");
        return;
    }
    
    // Get user to remove
    const user_to_remove = ctx.dao.getUserByName(allocator, username) catch |err| {
        std.log.err("Failed to get user: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse {
        try json.writeError(res, allocator, 404, "User not found");
        return;
    };
    defer {
        allocator.free(user_to_remove.name);
        if (user_to_remove.email) |e| allocator.free(e);
        if (user_to_remove.avatar) |a| allocator.free(a);
    }
    
    // Prevent removing the last owner
    const owners = ctx.dao.getOrgOwners(allocator, org.id) catch |err| {
        std.log.err("Failed to get org owners: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    defer {
        for (owners) |owner| {
            allocator.free(owner.name);
            if (owner.email) |e| allocator.free(e);
            if (owner.avatar) |a| allocator.free(a);
        }
        allocator.free(owners);
    }
    
    if (owners.len == 1 and owners[0].id == user_to_remove.id) {
        try json.writeError(res, allocator, 400, "Cannot remove the last owner");
        return;
    }
    
    // Remove member
    ctx.dao.removeUserFromOrg(allocator, user_to_remove.id, org.id) catch |err| {
        std.log.err("Failed to remove member: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to remove member");
        return;
    };
    
    res.status = 204;
}

pub fn createOrgRepoHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
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
    
    // Get organization
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
    
    // Verify it's an organization
    if (org.type != .organization) {
        try json.writeError(res, allocator, 404, "Organization not found");
        return;
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
    
    // Validate repository name
    if (repo_req.name.len == 0 or repo_req.name.len > 255) {
        try json.writeError(res, allocator, 400, "Invalid repository name length");
        return;
    }
    
    // Check if repository already exists
    if (ctx.dao.getRepositoryByName(allocator, org.id, repo_req.name) catch null) |_| {
        try json.writeError(res, allocator, 409, "Repository already exists");
        return;
    }
    
    // Create repository
    const repo = DataAccessObject.Repository{
        .id = 0, // Will be set by database
        .owner_id = org.id,
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
    const created_repo = ctx.dao.getRepositoryByName(allocator, org.id, repo_req.name) catch |err| {
        std.log.err("Failed to fetch created repository: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    } orelse unreachable;
    defer {
        allocator.free(created_repo.name);
        if (created_repo.description) |d| allocator.free(d);
        allocator.free(created_repo.default_branch);
    }
    
    const response = .{
        .id = created_repo.id,
        .owner = .{
            .id = org.id,
            .name = org.name,
            .type = "organization",
        },
        .name = created_repo.name,
        .full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ org.name, created_repo.name }),
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

// Organization secrets handlers (part of Actions/CI)
pub fn listOrgSecretsHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    // Get organization
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
    
    // Check if user is owner
    const is_owner = ctx.dao.isUserOrgOwner(allocator, user_id, org.id) catch |err| {
        std.log.err("Failed to check org ownership: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    
    if (!is_owner) {
        try json.writeError(res, allocator, 403, "Only organization owners can view secrets");
        return;
    }
    
    // Get secrets
    const secrets = ctx.dao.getOrgSecrets(allocator, org.id) catch |err| {
        std.log.err("Failed to get org secrets: {}", .{err});
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

pub fn createOrgSecretHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
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
        visibility: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try json.writeError(res, allocator, 400, "Invalid JSON");
        return;
    };
    defer parsed.deinit();
    
    // Get organization
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
    
    // Check if user is owner
    const is_owner = ctx.dao.isUserOrgOwner(allocator, user_id, org.id) catch |err| {
        std.log.err("Failed to check org ownership: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    
    if (!is_owner) {
        try json.writeError(res, allocator, 403, "Only organization owners can create secrets");
        return;
    }
    
    // Create or update secret
    const secret = DataAccessObject.ActionSecret{
        .id = 0,
        .owner_id = org.id,
        .owner_type = .organization,
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

pub fn deleteOrgSecretHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    const secret_name = req.param("secretname") orelse {
        try json.writeError(res, allocator, 400, "Missing secretname parameter");
        return;
    };
    
    // Get organization
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
    
    // Check if user is owner
    const is_owner = ctx.dao.isUserOrgOwner(allocator, user_id, org.id) catch |err| {
        std.log.err("Failed to check org ownership: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    
    if (!is_owner) {
        try json.writeError(res, allocator, 403, "Only organization owners can delete secrets");
        return;
    }
    
    // Delete secret
    ctx.dao.deleteSecret(allocator, org.id, .organization, secret_name) catch |err| {
        std.log.err("Failed to delete secret: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to delete secret");
        return;
    };
    
    res.status = 204;
}

// Organization runners handlers
pub fn listOrgRunnersHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    // Get organization
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
    
    // Check if user is member
    const is_member = ctx.dao.isUserInOrg(allocator, user_id, org.id) catch |err| {
        std.log.err("Failed to check org membership: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    
    if (!is_member) {
        try json.writeError(res, allocator, 403, "You must be a member of the organization");
        return;
    }
    
    // Get runners
    const runners = ctx.dao.getOrgRunners(allocator, org.id) catch |err| {
        std.log.err("Failed to get org runners: {}", .{err});
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

pub fn getOrgRunnerTokenHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
        return;
    };
    
    // Get organization
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
    
    // Check if user is owner
    const is_owner = ctx.dao.isUserOrgOwner(allocator, user_id, org.id) catch |err| {
        std.log.err("Failed to check org ownership: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    
    if (!is_owner) {
        try json.writeError(res, allocator, 403, "Only organization owners can generate runner tokens");
        return;
    }
    
    // Generate token
    const token = ctx.dao.createRunnerToken(allocator, org.id, .organization) catch |err| {
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

pub fn deleteOrgRunnerHandler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = req.arena;
    
    // Authenticate the request
    const user_id = try auth.authMiddleware(ctx, req, res) orelse return;
    
    const org_name = req.param("org") orelse {
        try json.writeError(res, allocator, 400, "Missing org parameter");
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
    
    // Get organization
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
    
    // Check if user is owner
    const is_owner = ctx.dao.isUserOrgOwner(allocator, user_id, org.id) catch |err| {
        std.log.err("Failed to check org ownership: {}", .{err});
        try json.writeError(res, allocator, 500, "Database error");
        return;
    };
    
    if (!is_owner) {
        try json.writeError(res, allocator, 403, "Only organization owners can delete runners");
        return;
    }
    
    // Delete runner
    ctx.dao.deleteRunner(allocator, runner_id, org.id, .organization) catch |err| {
        std.log.err("Failed to delete runner: {}", .{err});
        try json.writeError(res, allocator, 500, "Failed to delete runner");
        return;
    };
    
    res.status = 204;
}

// Tests
test "organization handlers" {
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
    dao.deleteUser(allocator, "test_org_handler") catch {};
    dao.deleteUser(allocator, "test_user_org") catch {};
    
    // Create test user
    const test_user = DataAccessObject.User{
        .id = 0,
        .name = "test_user_org",
        .email = "test@example.com",
        .password_hash = "hashed",
        .is_admin = false,
        .type = .individual,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, test_user);
    
    const user = (try dao.getUserByName(allocator, "test_user_org")).?;
    defer {
        allocator.free(user.name);
        if (user.email) |e| allocator.free(e);
        if (user.avatar) |a| allocator.free(a);
    }
    
    // Test organization creation
    {
        const test_org = DataAccessObject.User{
            .id = 0,
            .name = "test_org_handler",
            .email = null,
            .password_hash = null,
            .is_admin = false,
            .type = .organization,
            .avatar = null,
            .created_unix = 0,
            .updated_unix = 0,
        };
        try dao.createUser(allocator, test_org);
        
        const org = (try dao.getUserByName(allocator, "test_org_handler")).?;
        defer {
            allocator.free(org.name);
            if (org.email) |e| allocator.free(e);
            if (org.avatar) |a| allocator.free(a);
        }
        
        // Add user as owner
        try dao.addUserToOrg(allocator, user.id, org.id, true);
        
        // Verify membership
        const is_member = try dao.isUserInOrg(allocator, user.id, org.id);
        try std.testing.expect(is_member);
        
        const is_owner = try dao.isUserOrgOwner(allocator, user.id, org.id);
        try std.testing.expect(is_owner);
    }
    
    // Clean up
    dao.deleteUser(allocator, "test_org_handler") catch {};
    dao.deleteUser(allocator, "test_user_org") catch {};
}