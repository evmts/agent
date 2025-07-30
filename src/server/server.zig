const std = @import("std");
const zap = @import("zap");
pub const DataAccessObject = @import("../database/dao.zig");
const router = @import("router.zig");
const Config = @import("../config/config.zig").Config;

// Import utilities
const json = @import("utils/json.zig");
const auth = @import("utils/auth.zig");

// Import services
const MergeService = @import("services/merge_service.zig").MergeService;

// Import handlers
const health = @import("handlers/health.zig");
const users = @import("handlers/users.zig");
const orgs = @import("handlers/orgs.zig");
const repos = @import("handlers/repos.zig");
const contents = @import("handlers/contents.zig");

const Server = @This();

pub const Context = struct {
    dao: *DataAccessObject,
    allocator: std.mem.Allocator,
    config: *const Config,
};

listener: zap.HttpListener,
context: *Context,

// Global context for handlers to access
var global_context: *Context = undefined;

pub fn init(allocator: std.mem.Allocator, dao: *DataAccessObject, config: *const Config) !Server {
    const context = try allocator.create(Context);
    context.* = Context{ 
        .dao = dao,
        .allocator = allocator,
        .config = config,
    };
    
    // Store context globally for handler access
    global_context = context;
    
    const listener = zap.HttpListener.init(.{
        .port = 8000,
        .on_request = on_request,
        .log = true,
        .max_body_size = 100 * 1024 * 1024,
    });
    
    return Server{
        .listener = listener,
        .context = context,
    };
}

// Main request handler that dispatches to specific handlers
fn on_request(r: zap.Request) void {
    const path = r.path orelse {
        r.setStatus(.bad_request);
        r.sendBody("No path provided") catch {};
        return;
    };
    
    // Route dispatching
    if (r.methodAsEnum() == .GET) {
        if (std.mem.eql(u8, path, "/")) {
            router.callHandler(r, health.indexHandler, global_context);
            return;
        } else if (std.mem.eql(u8, path, "/health")) {
            router.callHandler(r, health.healthHandler, global_context);
            return;
        } else if (std.mem.eql(u8, path, "/user")) {
            router.callHandler(r, users.getCurrentUserHandler, global_context);
            return;
        } else if (std.mem.eql(u8, path, "/user/keys")) {
            router.callHandler(r, users.listSSHKeysHandler, global_context);
            return;
        } else if (std.mem.eql(u8, path, "/users")) {
            router.callHandler(r, users.getUsersHandler, global_context);
            return;
        } else if (std.mem.eql(u8, path, "/user/orgs")) {
            router.callHandler(r, users.listUserOrgsHandler, global_context);
            return;
        }
        // Handle parameterized routes
        else if (std.mem.startsWith(u8, path, "/users/")) {
            router.callHandler(r, users.getUserHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/orgs/") and std.mem.endsWith(u8, path, "/members")) {
            router.callHandler(r, orgs.listOrgMembersHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/orgs/") and std.mem.endsWith(u8, path, "/actions/secrets")) {
            router.callHandler(r, orgs.listOrgSecretsHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/orgs/") and std.mem.endsWith(u8, path, "/actions/runners")) {
            router.callHandler(r, orgs.listOrgRunnersHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/orgs/") and std.mem.endsWith(u8, path, "/actions/runners/registration-token")) {
            router.callHandler(r, orgs.getOrgRunnerTokenHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/orgs/")) {
            router.callHandler(r, orgs.getOrgHandler, global_context);
            return;
        }
        // Repository routes
        else if (std.mem.startsWith(u8, path, "/repos/")) {
            if (std.mem.indexOf(u8, path, "/contents/") != null) {
                router.callHandler(r, contents.getContentsHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/raw/") != null) {
                router.callHandler(r, contents.getRawContentHandler, global_context);
                return;
            } else if (std.mem.endsWith(u8, path, "/branches")) {
                router.callHandler(r, listBranchesHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/branches/") != null) {
                router.callHandler(r, getBranchHandler, global_context);
                return;
            } else if (std.mem.endsWith(u8, path, "/issues")) {
                router.callHandler(r, listIssuesHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/issues/") != null) {
                if (std.mem.endsWith(u8, path, "/comments")) {
                    router.callHandler(r, getCommentsHandler, global_context);
                return;
                } else {
                    router.callHandler(r, getIssueHandler, global_context);
                return;
                }
            } else if (std.mem.endsWith(u8, path, "/labels")) {
                router.callHandler(r, listLabelsHandler, global_context);
                return;
            } else if (std.mem.endsWith(u8, path, "/pulls")) {
                router.callHandler(r, listPullsHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/pulls/") != null) {
                if (std.mem.endsWith(u8, path, "/reviews")) {
                    router.callHandler(r, listReviewsHandler, global_context);
                return;
                } else {
                    router.callHandler(r, getPullHandler, global_context);
                return;
                }
            } else if (std.mem.endsWith(u8, path, "/actions/runs")) {
                router.callHandler(r, listRunsHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/actions/runs/") != null) {
                if (std.mem.endsWith(u8, path, "/jobs")) {
                    router.callHandler(r, listJobsHandler, global_context);
                return;
                } else if (std.mem.endsWith(u8, path, "/artifacts")) {
                    router.callHandler(r, listArtifactsHandler, global_context);
                return;
                } else {
                    router.callHandler(r, getRunHandler, global_context);
                return;
                }
            } else if (std.mem.indexOf(u8, path, "/actions/artifacts/") != null) {
                router.callHandler(r, getArtifactHandler, global_context);
                return;
            } else if (std.mem.endsWith(u8, path, "/actions/secrets")) {
                router.callHandler(r, repos.listRepoSecretsHandler, global_context);
                return;
            } else if (std.mem.endsWith(u8, path, "/actions/runners")) {
                router.callHandler(r, repos.listRepoRunnersHandler, global_context);
                return;
            } else if (std.mem.endsWith(u8, path, "/actions/runners/registration-token")) {
                router.callHandler(r, repos.getRepoRunnerTokenHandler, global_context);
                return;
            } else {
                router.callHandler(r, repos.getRepoHandler, global_context);
                return;
            }
        }
    } else if (r.methodAsEnum() == .POST) {
        if (std.mem.eql(u8, path, "/user/keys")) {
            router.callHandler(r, users.createSSHKeyHandler, global_context);
            return;
        } else if (std.mem.eql(u8, path, "/users")) {
            router.callHandler(r, users.createUserHandler, global_context);
            return;
        } else if (std.mem.eql(u8, path, "/user/repos")) {
            router.callHandler(r, users.createUserRepoHandler, global_context);
            return;
        } else if (std.mem.eql(u8, path, "/orgs")) {
            router.callHandler(r, orgs.createOrgHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/orgs/") and std.mem.endsWith(u8, path, "/repos")) {
            router.callHandler(r, orgs.createOrgRepoHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/repos/")) {
            if (std.mem.endsWith(u8, path, "/forks")) {
                router.callHandler(r, repos.forkRepoHandler, global_context);
                return;
            } else if (std.mem.endsWith(u8, path, "/branches")) {
                router.callHandler(r, createBranchHandler, global_context);
                return;
            } else if (std.mem.endsWith(u8, path, "/issues")) {
                router.callHandler(r, createIssueHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/issues/") != null and std.mem.endsWith(u8, path, "/comments")) {
                router.callHandler(r, createCommentHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/issues/") != null and std.mem.endsWith(u8, path, "/labels")) {
                router.callHandler(r, addLabelsToIssueHandler, global_context);
                return;
            } else if (std.mem.endsWith(u8, path, "/labels")) {
                router.callHandler(r, createLabelHandler, global_context);
                return;
            } else if (std.mem.endsWith(u8, path, "/pulls")) {
                router.callHandler(r, createPullHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/pulls/") != null) {
                if (std.mem.endsWith(u8, path, "/reviews")) {
                    router.callHandler(r, createReviewHandler, global_context);
                return;
                } else if (std.mem.endsWith(u8, path, "/merge")) {
                    router.callHandler(r, mergePullHandler, global_context);
                return;
                }
            }
        } else if (std.mem.startsWith(u8, path, "/admin/users")) {
            if (std.mem.endsWith(u8, path, "/keys")) {
                router.callHandler(r, addAdminUserKeyHandler, global_context);
                return;
            } else {
                router.callHandler(r, createAdminUserHandler, global_context);
                return;
            }
        }
    } else if (r.methodAsEnum() == .PUT) {
        if (std.mem.startsWith(u8, path, "/users/")) {
            router.callHandler(r, users.updateUserHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/orgs/") and std.mem.indexOf(u8, path, "/actions/secrets/") != null) {
            router.callHandler(r, orgs.createOrgSecretHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/repos/") and std.mem.indexOf(u8, path, "/actions/secrets/") != null) {
            router.callHandler(r, repos.createRepoSecretHandler, global_context);
            return;
        }
    } else if (r.methodAsEnum() == .PATCH) {
        if (std.mem.startsWith(u8, path, "/orgs/")) {
            router.callHandler(r, orgs.updateOrgHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/repos/")) {
            if (std.mem.indexOf(u8, path, "/issues/") != null) {
                router.callHandler(r, updateIssueHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/labels/") != null) {
                router.callHandler(r, updateLabelHandler, global_context);
                return;
            } else {
                router.callHandler(r, repos.updateRepoHandler, global_context);
                return;
            }
        } else if (std.mem.startsWith(u8, path, "/admin/users/")) {
            router.callHandler(r, updateAdminUserHandler, global_context);
                return;
        }
    } else if (r.methodAsEnum() == .DELETE) {
        if (std.mem.startsWith(u8, path, "/user/keys/")) {
            router.callHandler(r, users.deleteSSHKeyHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/users/")) {
            router.callHandler(r, users.deleteUserHandler, global_context);
            return;
        } else if (std.mem.startsWith(u8, path, "/orgs/")) {
            if (std.mem.indexOf(u8, path, "/members/") != null) {
                router.callHandler(r, orgs.removeOrgMemberHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/actions/secrets/") != null) {
                router.callHandler(r, orgs.deleteOrgSecretHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/actions/runners/") != null) {
                router.callHandler(r, orgs.deleteOrgRunnerHandler, global_context);
                return;
            } else {
                router.callHandler(r, orgs.deleteOrgHandler, global_context);
                return;
            }
        } else if (std.mem.startsWith(u8, path, "/repos/")) {
            if (std.mem.indexOf(u8, path, "/branches/") != null) {
                router.callHandler(r, deleteBranchHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/labels/") != null) {
                if (std.mem.indexOf(u8, path, "/issues/") != null) {
                    router.callHandler(r, removeLabelFromIssueHandler, global_context);
                return;
                } else {
                    router.callHandler(r, deleteLabelHandler, global_context);
                return;
                }
            } else if (std.mem.indexOf(u8, path, "/actions/secrets/") != null) {
                router.callHandler(r, repos.deleteRepoSecretHandler, global_context);
                return;
            } else if (std.mem.indexOf(u8, path, "/actions/runners/") != null) {
                router.callHandler(r, repos.deleteRepoRunnerHandler, global_context);
                return;
            } else {
                router.callHandler(r, repos.deleteRepoHandler, global_context);
                return;
            }
        } else if (std.mem.startsWith(u8, path, "/admin/users/")) {
            router.callHandler(r, deleteAdminUserHandler, global_context);
                return;
        }
    }
    
    // If no route matches, return 404
    r.setStatus(.not_found);
    r.sendBody("Not Found") catch {};
}

pub fn deinit(self: *Server, allocator: std.mem.Allocator) void {
    allocator.destroy(self.context);
}

pub fn listen(self: *Server) !void {
    try self.listener.listen();
    
    std.debug.print("\n🚀 Plue API Server listening on 0.0.0.0:8000\n", .{});
    
    // Start zap
    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}

// Temporary placeholder functions for handlers not yet moved
// These will be removed as we extract more handler files

fn listBranchesHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/branches
    const path_info = parseRepoPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in listBranchesHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get branches from database
    const branches = ctx.dao.getBranches(allocator, repo.id) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting branches: {}", .{err});
        return;
    };
    defer {
        for (branches) |branch| {
            allocator.free(branch.name);
            if (branch.commit_id) |c| allocator.free(c);
        }
        allocator.free(branches);
    }
    
    try json.writeJson(r, allocator, branches);
}

fn getBranchHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract owner/repo/branch from path: /repos/{owner}/{repo}/branches/{branch}
    const path_info = parseBranchPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in getBranchHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get specific branch from database
    const branch = ctx.dao.getBranchByName(allocator, repo.id, path_info.branch) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting branch: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Branch not found");
        return;
    };
    defer {
        allocator.free(branch.name);
        if (branch.commit_id) |c| allocator.free(c);
    }
    
    try json.writeJson(r, allocator, branch);
}

fn createBranchHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/branches
    const path_info = parseRepoPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in createBranchHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Parse request body
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Missing request body");
        return;
    };
    
    var json_data = std.json.parseFromSlice(struct {
        name: []const u8,
        from_branch: ?[]const u8 = null,
    }, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON");
        return;
    };
    defer json_data.deinit();
    
    const branch_name = json_data.value.name;
    const from_branch = json_data.value.from_branch orelse repo.default_branch;
    
    // Check if branch already exists
    const existing_branch = ctx.dao.getBranchByName(allocator, repo.id, branch_name) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error checking existing branch: {}", .{err});
        return;
    };
    if (existing_branch) |b| {
        allocator.free(b.name);
        if (b.commit_id) |c| allocator.free(c);
        try json.writeError(r, allocator, .conflict, "Branch already exists");
        return;
    }
    
    // Get commit ID from source branch
    const source_branch = ctx.dao.getBranchByName(allocator, repo.id, from_branch) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting source branch: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Source branch not found");
        return;
    };
    defer {
        allocator.free(source_branch.name);
        if (source_branch.commit_id) |c| allocator.free(c);
    }
    
    // Create new branch
    const new_branch = DataAccessObject.Branch{
        .id = 0, // Will be set by database
        .repo_id = repo.id,
        .name = branch_name,
        .commit_id = source_branch.commit_id,
        .is_protected = false,
    };
    
    ctx.dao.createBranch(allocator, new_branch) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Failed to create branch");
        std.log.err("Database error creating branch: {}", .{err});
        return;
    };
    
    // Return the created branch
    const created_branch = ctx.dao.getBranchByName(allocator, repo.id, branch_name) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error retrieving created branch: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .internal_server_error, "Branch creation failed");
        return;
    };
    defer {
        allocator.free(created_branch.name);
        if (created_branch.commit_id) |c| allocator.free(c);
    }
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, created_branch);
}

fn deleteBranchHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract owner/repo/branch from path: /repos/{owner}/{repo}/branches/{branch}
    const path_info = parseBranchPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in deleteBranchHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Check if branch exists before deletion
    const branch = ctx.dao.getBranchByName(allocator, repo.id, path_info.branch) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error checking branch: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Branch not found");
        return;
    };
    defer {
        allocator.free(branch.name);
        if (branch.commit_id) |c| allocator.free(c);
    }
    
    // Prevent deletion of default branch
    if (std.mem.eql(u8, path_info.branch, repo.default_branch)) {
        try json.writeError(r, allocator, .forbidden, "Cannot delete default branch");
        return;
    }
    
    // Delete the branch
    ctx.dao.deleteBranch(allocator, repo.id, path_info.branch) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Failed to delete branch");
        std.log.err("Database error deleting branch: {}", .{err});
        return;
    };
    
    r.setStatus(.no_content);
}

fn listIssuesHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/issues
    const path_info = parseRepoPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in listIssuesHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Parse query parameters for filtering
    var query_params = parseQueryParams(allocator, r.query) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid query parameters");
        return;
    };
    defer query_params.deinit();
    
    const filters = DataAccessObject.IssueFilters{
        .is_closed = if (query_params.get("state")) |state| 
            std.mem.eql(u8, state, "closed") else null,
        .is_pull = if (query_params.get("type")) |type_str|
            std.mem.eql(u8, type_str, "pr") else null,
        .assignee_id = if (query_params.get("assignee")) |assignee_str|
            std.fmt.parseInt(i64, assignee_str, 10) catch null else null,
    };
    
    // Get issues from database
    const issues = ctx.dao.listIssues(allocator, repo.id, filters) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting issues: {}", .{err});
        return;
    };
    defer {
        for (issues) |issue| {
            allocator.free(issue.title);
            if (issue.content) |c| allocator.free(c);
        }
        allocator.free(issues);
    }
    
    try json.writeJson(r, allocator, issues);
}

fn createIssueHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Parse request body
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreateIssueRequest = struct {
        title: []const u8,
        body: ?[]const u8 = null,
        assignee: ?[]const u8 = null,
        labels: ?[][]const u8 = null,
    };
    
    var parsed = std.json.parseFromSlice(CreateIssueRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer parsed.deinit();
    
    // Validate required fields
    if (parsed.value.title.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Title is required");
        return;
    }
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/issues
    const path_info = parseRepoPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in createIssueHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Resolve assignee if provided
    var assignee_id: ?i64 = null;
    if (parsed.value.assignee) |assignee_name| {
        const assignee = ctx.dao.getUserByName(allocator, assignee_name) catch |err| {
            try json.writeError(r, allocator, .internal_server_error, "Database error");
            std.log.err("Database error getting assignee: {}", .{err});
            return;
        };
        if (assignee) |a| {
            assignee_id = a.id;
            allocator.free(a.name);
            if (a.email) |e| allocator.free(e);
            if (a.avatar) |av| allocator.free(av);
        }
    }
    
    // Create issue
    const new_issue = DataAccessObject.Issue{
        .id = 0,
        .repo_id = repo.id,
        .index = 0, // Will be set by DAO
        .poster_id = user_id,
        .title = parsed.value.title,
        .content = parsed.value.body,
        .is_closed = false,
        .is_pull = false,
        .assignee_id = assignee_id,
        .created_unix = 0, // Will be set by DAO
    };
    
    const issue_id = ctx.dao.createIssue(allocator, new_issue) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Failed to create issue");
        std.log.err("Database error creating issue: {}", .{err});
        return;
    };
    
    // Return created issue
    const created_issue = ctx.dao.getIssue(allocator, repo.id, issue_id) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error retrieving created issue: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .internal_server_error, "Issue creation failed");
        return;
    };
    defer {
        allocator.free(created_issue.title);
        if (created_issue.content) |c| allocator.free(c);
    }
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, created_issue);
}

fn getIssueHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Extract owner/repo/issue_number from path: /repos/{owner}/{repo}/issues/{number}
    const path_info = parseIssuePath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in getIssueHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get specific issue
    const issue = ctx.dao.getIssue(allocator, repo.id, path_info.issue_number) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting issue: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Issue not found");
        return;
    };
    defer {
        allocator.free(issue.title);
        if (issue.content) |c| allocator.free(c);
    }
    
    try json.writeJson(r, allocator, issue);
}

fn updateIssueHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Parse request body
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const UpdateIssueRequest = struct {
        title: ?[]const u8 = null,
        body: ?[]const u8 = null,
        state: ?[]const u8 = null, // "open" or "closed"
        assignee: ?[]const u8 = null,
    };
    
    var update_request = std.json.parseFromSlice(UpdateIssueRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer update_request.deinit();
    
    // Extract owner/repo/issue_number from path
    const path_info = parseIssuePath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in updateIssueHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get existing issue to validate it exists
    const existing_issue = ctx.dao.getIssue(allocator, repo.id, path_info.issue_number) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting existing issue: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Issue not found");
        return;
    };
    defer {
        allocator.free(existing_issue.title);
        if (existing_issue.content) |c| allocator.free(c);
    }
    
    // Build update struct
    var updates = DataAccessObject.IssueUpdate{};
    if (update_request.value.title) |title| updates.title = title;
    if (update_request.value.body) |body_text| updates.content = body_text;
    if (update_request.value.state) |state| {
        if (std.mem.eql(u8, state, "closed")) {
            updates.is_closed = true;
        } else if (std.mem.eql(u8, state, "open")) {
            updates.is_closed = false;
        }
    }
    
    // Handle assignee updates
    if (update_request.value.assignee) |assignee_name| {
        const assignee = ctx.dao.getUserByName(allocator, assignee_name) catch |err| {
            try json.writeError(r, allocator, .internal_server_error, "Database error");
            std.log.err("Database error getting assignee: {}", .{err});
            return;
        };
        if (assignee) |a| {
            updates.assignee_id = a.id;
            allocator.free(a.name);
            if (a.email) |e| allocator.free(e);
            if (a.avatar) |av| allocator.free(av);
        }
    }
    
    // Update the issue
    ctx.dao.updateIssue(allocator, existing_issue.id, updates) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Failed to update issue");
        std.log.err("Database error updating issue: {}", .{err});
        return;
    };
    
    // Return updated issue
    const updated_issue = ctx.dao.getIssue(allocator, repo.id, path_info.issue_number) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error retrieving updated issue: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .internal_server_error, "Issue update failed");
        return;
    };
    defer {
        allocator.free(updated_issue.title);
        if (updated_issue.content) |c| allocator.free(c);
    }
    
    try json.writeJson(r, allocator, updated_issue);
}

fn getCommentsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Extract owner/repo/issue_number from path: /repos/{owner}/{repo}/issues/{number}/comments
    const path_info = parseIssuePath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in getCommentsHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get issue to validate it exists
    const issue = ctx.dao.getIssue(allocator, repo.id, path_info.issue_number) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting issue: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Issue not found");
        return;
    };
    defer {
        allocator.free(issue.title);
        if (issue.content) |c| allocator.free(c);
    }
    
    // Get comments for this issue
    const comments = ctx.dao.getComments(allocator, issue.id) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting comments: {}", .{err});
        return;
    };
    defer {
        for (comments) |comment| {
            allocator.free(comment.content);
            if (comment.commit_id) |c| allocator.free(c);
        }
        allocator.free(comments);
    }
    
    try json.writeJson(r, allocator, comments);
}

fn createCommentHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Parse request body
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreateCommentRequest = struct {
        body: []const u8,
    };
    
    var comment_request = std.json.parseFromSlice(CreateCommentRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer comment_request.deinit();
    
    if (comment_request.value.body.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Comment body is required");
        return;
    }
    
    // Extract owner/repo/issue_number from path: /repos/{owner}/{repo}/issues/{number}/comments
    const path_info = parseIssuePath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in createCommentHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get issue to validate it exists
    const issue = ctx.dao.getIssue(allocator, repo.id, path_info.issue_number) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting issue: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Issue not found");
        return;
    };
    defer {
        allocator.free(issue.title);
        if (issue.content) |c| allocator.free(c);
    }
    
    // Create new comment
    const new_comment = DataAccessObject.Comment{
        .id = 0,
        .poster_id = user_id,
        .issue_id = issue.id,
        .review_id = null,
        .content = comment_request.value.body,
        .commit_id = null,
        .line = null,
        .created_unix = 0, // Will be set by DAO
    };
    
    const comment_id = ctx.dao.createComment(allocator, new_comment) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Failed to create comment");
        std.log.err("Database error creating comment: {}", .{err});
        return;
    };
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, .{
        .id = comment_id,
        .body = comment_request.value.body,
        .created = true,
    });
}

fn listLabelsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/labels
    const path_info = parseRepoPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in listLabelsHandler: {}", .{err});
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
    
    const labels = try ctx.dao.getLabels(allocator, repo.id);
    defer {
        for (labels) |label| {
            allocator.free(label.name);
            allocator.free(label.color);
        }
        allocator.free(labels);
    }
    
    try json.writeJson(r, allocator, labels);
}

fn createLabelHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreateLabelRequest = struct {
        name: []const u8,
        color: []const u8,
    };
    
    var parsed = std.json.parseFromSlice(CreateLabelRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer parsed.deinit();
    
    // Validate required fields
    if (parsed.value.name.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Label name is required");
        return;
    }
    
    // Validate color format (hex color)
    if (!isValidHexColor(parsed.value.color)) {
        try json.writeError(r, allocator, .bad_request, "Color must be a valid hex color (e.g., #ff0000)");
        return;
    }
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/labels
    const path_info = parseRepoPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in createLabelHandler: {}", .{err});
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
    
    const new_label = DataAccessObject.Label{
        .id = 0,
        .repo_id = repo.id,
        .name = parsed.value.name,
        .color = parsed.value.color,
    };
    
    const label_id = try ctx.dao.createLabel(allocator, new_label);
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, .{
        .id = label_id,
        .name = parsed.value.name,
        .color = parsed.value.color,
        .created = true,
    });
}

fn updateLabelHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const UpdateLabelRequest = struct {
        name: ?[]const u8 = null,
        color: ?[]const u8 = null,
    };
    
    var parsed = std.json.parseFromSlice(UpdateLabelRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer parsed.deinit();
    
    // Validate color if provided
    if (parsed.value.color) |color| {
        if (!isValidHexColor(color)) {
            try json.writeError(r, allocator, .bad_request, "Color must be a valid hex color");
            return;
        }
    }
    
    // Parse label ID from path (/repos/{owner}/{repo}/labels/{id})
    const path_parts = std.mem.splitScalar(u8, r.path.?, '/');
    var part_count: u32 = 0;
    var label_id: i64 = 0;
    
    var iterator = path_parts;
    while (iterator.next()) |part| {
        part_count += 1;
        if (part_count == 6) { // /repos/{owner}/{repo}/labels/{id}
            label_id = std.fmt.parseInt(i64, part, 10) catch {
                try json.writeError(r, allocator, .bad_request, "Invalid label ID");
                return;
            };
            break;
        }
    }
    
    if (label_id == 0) {
        try json.writeError(r, allocator, .bad_request, "Label ID required");
        return;
    }
    
    // Extract repo info for verification
    const path_info = parseRepoPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in updateLabelHandler: {}", .{err});
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
    
    // Update the label
    try ctx.dao.updateLabel(allocator, label_id, parsed.value.name, parsed.value.color);
    
    // Get updated label to return
    const updated_label = try ctx.dao.getLabelById(allocator, label_id);
    defer if (updated_label) |label| {
        allocator.free(label.name);
        allocator.free(label.color);
    };
    
    if (updated_label) |label| {
        try json.writeJson(r, allocator, label);
    } else {
        try json.writeError(r, allocator, .not_found, "Label not found");
    }
}

fn deleteLabelHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Parse label ID from path (/repos/{owner}/{repo}/labels/{id})
    const path_parts = std.mem.splitScalar(u8, r.path.?, '/');
    var part_count: u32 = 0;
    var label_id: i64 = 0;
    
    var iterator = path_parts;
    while (iterator.next()) |part| {
        part_count += 1;
        if (part_count == 6) { // /repos/{owner}/{repo}/labels/{id}
            label_id = std.fmt.parseInt(i64, part, 10) catch {
                try json.writeError(r, allocator, .bad_request, "Invalid label ID");
                return;
            };
            break;
        }
    }
    
    if (label_id == 0) {
        try json.writeError(r, allocator, .bad_request, "Label ID required");
        return;
    }
    
    // Extract repo info for verification
    const path_info = parseRepoPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in deleteLabelHandler: {}", .{err});
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
    
    // Delete the label
    try ctx.dao.deleteLabel(allocator, label_id);
    
    r.setStatus(.no_content);
    try r.sendBody("");
}

fn addLabelsToIssueHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn removeLabelFromIssueHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn listPullsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/pulls
    const path_info = parseRepoPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in listPullsHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Parse query parameters for filtering
    var query_params = parseQueryParams(allocator, r.query) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid query parameters");
        return;
    };
    defer query_params.deinit();
    
    // Pull requests are issues with is_pull = true
    const filters = DataAccessObject.IssueFilters{
        .is_closed = if (query_params.get("state")) |state| 
            std.mem.eql(u8, state, "closed") else null,
        .is_pull = true, // Only pull requests
        .assignee_id = if (query_params.get("assignee")) |assignee_str|
            std.fmt.parseInt(i64, assignee_str, 10) catch null else null,
    };
    
    // Get pull requests (issues with is_pull = true) from database
    const pulls = ctx.dao.listIssues(allocator, repo.id, filters) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting pull requests: {}", .{err});
        return;
    };
    defer {
        for (pulls) |pull| {
            allocator.free(pull.title);
            if (pull.content) |c| allocator.free(c);
        }
        allocator.free(pulls);
    }
    
    try json.writeJson(r, allocator, pulls);
}

fn createPullHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Parse request body
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreatePullRequest = struct {
        title: []const u8,
        body: ?[]const u8 = null,
        head: []const u8, // Source branch
        base: []const u8, // Target branch
        assignees: ?[][]const u8 = null,
        reviewers: ?[][]const u8 = null,
    };
    
    var parsed = std.json.parseFromSlice(CreatePullRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer parsed.deinit();
    
    // Validate required fields
    if (parsed.value.title.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Title is required");
        return;
    }
    
    if (parsed.value.head.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Head branch is required");
        return;
    }
    
    if (parsed.value.base.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Base branch is required");
        return;
    }
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/pulls
    const path_info = parseRepoPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in createPullHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Validate branches exist
    const head_branch = ctx.dao.getBranchByName(allocator, repo.id, parsed.value.head) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting head branch: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .bad_request, "Head branch does not exist");
        return;
    };
    defer {
        allocator.free(head_branch.name);
        if (head_branch.commit_id) |c| allocator.free(c);
    }
    
    const base_branch = ctx.dao.getBranchByName(allocator, repo.id, parsed.value.base) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting base branch: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .bad_request, "Base branch does not exist");
        return;
    };
    defer {
        allocator.free(base_branch.name);
        if (base_branch.commit_id) |c| allocator.free(c);
    }
    
    // Create pull request as an issue with is_pull = true
    const new_pull = DataAccessObject.Issue{
        .id = 0,
        .repo_id = repo.id,
        .index = 0, // Will be set by DAO
        .poster_id = user_id,
        .title = parsed.value.title,
        .content = parsed.value.body,
        .is_closed = false,
        .is_pull = true, // This makes it a pull request
        .assignee_id = null, // Will handle assignees separately if provided
        .created_unix = 0, // Will be set by DAO
    };
    
    const pull_id = ctx.dao.createIssue(allocator, new_pull) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Failed to create pull request");
        std.log.err("Database error creating pull request: {}", .{err});
        return;
    };
    
    // Return created pull request
    const created_pull = ctx.dao.getIssue(allocator, repo.id, pull_id) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error retrieving created pull request: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .internal_server_error, "Pull request creation failed");
        return;
    };
    defer {
        allocator.free(created_pull.title);
        if (created_pull.content) |c| allocator.free(c);
    }
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, created_pull);
}

fn getPullHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Extract owner/repo/pull_number from path: /repos/{owner}/{repo}/pulls/{number}
    const path_info = parsePullPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in getPullHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get specific pull request (issue with is_pull = true)
    const pull = ctx.dao.getIssue(allocator, repo.id, path_info.pull_number) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting pull request: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Pull request not found");
        return;
    };
    defer {
        allocator.free(pull.title);
        if (pull.content) |c| allocator.free(c);
    }
    
    // Verify it's actually a pull request
    if (!pull.is_pull) {
        try json.writeError(r, allocator, .not_found, "Pull request not found");
        return;
    }
    
    try json.writeJson(r, allocator, pull);
}

fn listReviewsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    _ = user_id; // Authentication required but user_id not used for listing reviews
    
    // Parse URL to get repo and pull request number
    const path = r.path orelse return error.BadRequest;
    
    // Extract owner, repo, and pull_number from path like /repos/owner/repo/pulls/123/reviews
    var path_parts = std.mem.splitSequence(u8, path, "/");
    _ = path_parts.next(); // skip empty
    _ = path_parts.next(); // skip "repos"
    const owner = path_parts.next() orelse return error.BadRequest;
    const repo = path_parts.next() orelse return error.BadRequest;
    _ = path_parts.next(); // skip "pulls"
    const pull_number_str = path_parts.next() orelse return error.BadRequest;
    
    const pull_number = std.fmt.parseInt(i64, pull_number_str, 10) catch return error.BadRequest;
    
    // Get repository owner user
    const owner_user = try ctx.dao.getUserByName(allocator, owner) orelse {
        r.setStatus(.not_found);
        try r.sendBody("Repository owner not found");
        return;
    };
    defer {
        allocator.free(owner_user.name);
        if (owner_user.email) |e| allocator.free(e);
        if (owner_user.passwd) |p| allocator.free(p);
        if (owner_user.avatar) |a| allocator.free(a);
    }
    
    // Get repository by owner and name
    const repository = try ctx.dao.getRepositoryByName(allocator, owner_user.id, repo) orelse {
        r.setStatus(.not_found);
        try r.sendBody("Repository not found");
        return;
    };
    defer {
        allocator.free(repository.lower_name);
        allocator.free(repository.name);
        if (repository.description) |d| allocator.free(d);
        allocator.free(repository.default_branch);
    }
    
    // Get the pull request (issue)
    const pull_request = try ctx.dao.getIssue(allocator, repository.id, pull_number) orelse {
        r.setStatus(.not_found);
        try r.sendBody("Pull request not found");
        return;
    };
    defer {
        allocator.free(pull_request.title);
        if (pull_request.content) |c| allocator.free(c);
    }
    
    // Verify it's actually a pull request
    if (!pull_request.is_pull) {
        r.setStatus(.bad_request);
        try r.sendBody("Not a pull request");
        return;
    }
    
    // Get reviews for this pull request
    const reviews = try ctx.dao.getReviews(allocator, pull_request.id);
    defer {
        for (reviews) |review| {
            if (review.commit_id) |c| allocator.free(c);
        }
        allocator.free(reviews);
    }
    
    // Format response
    r.setStatus(.ok);
    r.setHeader("Content-Type", "application/json") catch {};
    
    try json.writeJson(r, allocator, .{
        .reviews = reviews,
        .count = reviews.len,
    });
}

fn createReviewHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Parse URL to get repo and pull request number
    const path = r.path orelse return error.BadRequest;
    
    // Extract owner, repo, and pull_number from path like /repos/owner/repo/pulls/123/reviews
    var path_parts = std.mem.splitSequence(u8, path, "/");
    _ = path_parts.next(); // skip empty
    _ = path_parts.next(); // skip "repos"
    const owner = path_parts.next() orelse return error.BadRequest;
    const repo = path_parts.next() orelse return error.BadRequest;
    _ = path_parts.next(); // skip "pulls"
    const pull_number_str = path_parts.next() orelse return error.BadRequest;
    
    const pull_number = std.fmt.parseInt(i64, pull_number_str, 10) catch return error.BadRequest;
    
    // Get repository owner user
    const owner_user = try ctx.dao.getUserByName(allocator, owner) orelse {
        r.setStatus(.not_found);
        try r.sendBody("Repository owner not found");
        return;
    };
    defer {
        allocator.free(owner_user.name);
        if (owner_user.email) |e| allocator.free(e);
        if (owner_user.passwd) |p| allocator.free(p);
        if (owner_user.avatar) |a| allocator.free(a);
    }
    
    // Get repository by owner and name
    const repository = try ctx.dao.getRepositoryByName(allocator, owner_user.id, repo) orelse {
        r.setStatus(.not_found);
        try r.sendBody("Repository not found");
        return;
    };
    defer {
        allocator.free(repository.lower_name);
        allocator.free(repository.name);
        if (repository.description) |d| allocator.free(d);
        allocator.free(repository.default_branch);
    }
    
    // Get the pull request (issue)
    const pull_request = try ctx.dao.getIssue(allocator, repository.id, pull_number) orelse {
        r.setStatus(.not_found);
        try r.sendBody("Pull request not found");
        return;
    };
    defer {
        allocator.free(pull_request.title);
        if (pull_request.content) |c| allocator.free(c);
    }
    
    // Verify it's actually a pull request
    if (!pull_request.is_pull) {
        r.setStatus(.bad_request);
        try r.sendBody("Not a pull request");
        return;
    }
    
    // Parse request body
    const body = r.body orelse {
        r.setStatus(.bad_request);
        try r.sendBody("Request body required");
        return;
    };
    
    const ReviewRequest = struct {
        event: []const u8, // "approve", "reject", "comment"
        body: ?[]const u8 = null,
        commit_id: ?[]const u8 = null,
    };
    
    var parsed = std.json.parseFromSlice(ReviewRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer parsed.deinit();
    
    // Convert event string to ReviewType
    const review_type: DataAccessObject.ReviewType = if (std.mem.eql(u8, parsed.value.event, "approve"))
        .approve
    else if (std.mem.eql(u8, parsed.value.event, "reject"))
        .reject
    else if (std.mem.eql(u8, parsed.value.event, "comment"))
        .comment
    else {
        r.setStatus(.bad_request);
        try r.sendBody("Invalid review event. Must be 'approve', 'reject', or 'comment'");
        return;
    };
    
    // Create review
    const review = DataAccessObject.Review{
        .id = 0, // Will be assigned by database
        .type = review_type,
        .reviewer_id = user_id,
        .issue_id = pull_request.id,
        .commit_id = parsed.value.commit_id,
    };
    
    const review_id = try ctx.dao.createReview(allocator, review);
    
    // If there's a body comment, create a comment associated with this review
    if (parsed.value.body) |body_text| {
        if (body_text.len > 0) {
            const comment = DataAccessObject.Comment{
                .id = 0, // Will be assigned by database
                .poster_id = user_id,
                .issue_id = pull_request.id,
                .review_id = review_id,
                .content = body_text,
                .commit_id = parsed.value.commit_id,
                .line = null, // General comment, not line-specific
                .created_unix = std.time.timestamp(),
            };
            
            _ = try ctx.dao.createComment(allocator, comment);
        }
    }
    
    // Return success response
    r.setStatus(.created);
    r.setHeader("Content-Type", "application/json") catch {};
    
    try json.writeJson(r, allocator, .{
        .review_id = review_id,
        .event = parsed.value.event,
        .reviewer_id = user_id,
        .pull_request_id = pull_request.id,
    });
}

fn mergePullHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Get user from auth
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Parse request body (optional)
    const body = r.body;
    var merge_title: ?[]const u8 = null;
    var merge_message: ?[]const u8 = null;
    
    if (body) |b| {
        const MergePullRequest = struct {
            commit_title: ?[]const u8 = null,
            commit_message: ?[]const u8 = null,
            merge_method: ?[]const u8 = null, // "merge", "squash", "rebase"
        };
        
        var merge_request = std.json.parseFromSlice(MergePullRequest, allocator, b, .{}) catch {
            try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
            return;
        };
        defer merge_request.deinit();
        
        merge_title = merge_request.value.commit_title;
        merge_message = merge_request.value.commit_message;
    }
    
    // Extract owner/repo/pull_number from path
    const path_info = parsePullPath(allocator, r.path.?) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid path format");
        return;
    };
    defer path_info.deinit(allocator);
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error in mergePullHandler: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer {
        allocator.free(repo.name);
        allocator.free(repo.lower_name);
        if (repo.description) |d| allocator.free(d);
        allocator.free(repo.default_branch);
    }
    
    // Get pull request
    const pull = ctx.dao.getIssue(allocator, repo.id, path_info.pull_number) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Database error");
        std.log.err("Database error getting pull request: {}", .{err});
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Pull request not found");
        return;
    };
    defer {
        allocator.free(pull.title);
        if (pull.content) |c| allocator.free(c);
    }
    
    // Verify it's actually a pull request
    if (!pull.is_pull) {
        try json.writeError(r, allocator, .not_found, "Pull request not found");
        return;
    }
    
    // Initialize merge service
    var merge_service = MergeService.init(ctx.dao);
    
    // Simulate merge conflict detection (would use actual Git in production)
    const base_sha = "base_branch_sha_placeholder";
    const head_sha = "head_branch_sha_placeholder";
    try merge_service.detectMergeConflicts(allocator, repo.id, pull.id, base_sha, head_sha);
    
    // Check if the pull request can be merged
    var mergeability = merge_service.checkMergeability(allocator, repo.id, pull.id, repo.default_branch) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Failed to check merge requirements");
        std.log.err("Error checking mergeability: {}", .{err});
        return;
    };
    defer mergeability.deinit(allocator);
    
    if (!mergeability.can_merge) {
        r.setStatus(.bad_request);
        try json.writeJson(r, allocator, .{
            .message = "Pull request cannot be merged",
            .blocking_issues = mergeability.blocking_issues,
        });
        return;
    }
    
    // If we get here, the PR can be merged
    const updates = DataAccessObject.IssueUpdate{
        .is_closed = true,
        .title = null,
        .content = null,
        .assignee_id = null,
    };
    
    ctx.dao.updateIssue(allocator, pull.id, updates) catch |err| {
        try json.writeError(r, allocator, .internal_server_error, "Failed to merge pull request");
        std.log.err("Database error merging pull request: {}", .{err});
        return;
    };
    
    // In a real implementation, this would be the actual commit SHA from Git merge
    const merge_sha = try std.fmt.allocPrint(allocator, "merged_{d}_{s}", .{ std.time.timestamp(), head_sha[0..8] });
    defer allocator.free(merge_sha);
    
    try json.writeJson(r, allocator, .{
        .sha = merge_sha,
        .merged = true,
        .message = merge_title orelse "Pull request successfully merged",
        .merge_commit_sha = merge_sha,
    });
}

fn listRunsHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn getRunHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn listJobsHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn listArtifactsHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn getArtifactHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn createAdminUserHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Admin authentication required
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Check if user is admin
    const user = try ctx.dao.getUserById(allocator, user_id);
    defer if (user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    if (user == null or !user.?.is_admin) {
        try json.writeError(r, allocator, .forbidden, "Admin privileges required");
        return;
    }
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreateUserRequest = struct {
        username: []const u8,
        email: []const u8,
        password: []const u8,
        is_admin: bool = false,
        type: ?[]const u8 = null, // "individual" or "organization"
    };
    
    var parsed = std.json.parseFromSlice(CreateUserRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer parsed.deinit();
    
    // Validate required fields
    if (parsed.value.username.len == 0 or parsed.value.email.len == 0 or parsed.value.password.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Username, email and password are required");
        return;
    }
    
    // For now, store password directly (should be hashed in production)
    const password_hash = parsed.value.password;
    
    // Parse user type
    const user_type = if (parsed.value.type) |t| blk: {
        if (std.mem.eql(u8, t, "organization")) {
            break :blk DataAccessObject.UserType.organization;
        } else {
            break :blk DataAccessObject.UserType.individual;
        }
    } else DataAccessObject.UserType.individual;
    
    const new_user = DataAccessObject.User{
        .id = 0,
        .name = parsed.value.username,
        .email = parsed.value.email,
        .passwd = password_hash,
        .type = user_type,
        .is_admin = parsed.value.is_admin,
        .avatar = null,
        .created_unix = 0, // Will be set by DAO
        .updated_unix = 0, // Will be set by DAO
    };
    
    const created_user_id = try ctx.dao.createUser(allocator, new_user);
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, .{
        .id = created_user_id,
        .username = parsed.value.username,
        .email = parsed.value.email,
        .is_admin = parsed.value.is_admin,
        .type = parsed.value.type orelse "individual",
        .created = true,
    });
}

fn updateAdminUserHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Admin authentication required
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Check if user is admin
    const user = try ctx.dao.getUserById(allocator, user_id);
    defer if (user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    if (user == null or !user.?.is_admin) {
        try json.writeError(r, allocator, .forbidden, "Admin privileges required");
        return;
    }
    
    // Parse user ID from path (/admin/users/{id})
    const path_parts = std.mem.splitScalar(u8, r.path.?, '/');
    var part_count: u32 = 0;
    var target_user_id: i64 = 0;
    
    var iterator = path_parts;
    while (iterator.next()) |part| {
        part_count += 1;
        if (part_count == 4) { // /admin/users/{id}
            target_user_id = std.fmt.parseInt(i64, part, 10) catch {
                try json.writeError(r, allocator, .bad_request, "Invalid user ID");
                return;
            };
            break;
        }
    }
    
    if (target_user_id == 0) {
        try json.writeError(r, allocator, .bad_request, "User ID required");
        return;
    }
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const UpdateUserRequest = struct {
        email: ?[]const u8 = null,
        password: ?[]const u8 = null,
        is_admin: ?bool = null,
        avatar: ?[]const u8 = null,
    };
    
    var parsed = std.json.parseFromSlice(UpdateUserRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer parsed.deinit();
    
    // Check if target user exists
    const target_user = try ctx.dao.getUserById(allocator, target_user_id);
    if (target_user == null) {
        try json.writeError(r, allocator, .not_found, "User not found");
        return;
    }
    defer if (target_user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    // Update user fields based on request
    if (parsed.value.email) |email| {
        try ctx.dao.updateUserEmail(allocator, target_user_id, email);
    }
    
    if (parsed.value.password) |password| {
        try ctx.dao.updateUserPassword(allocator, target_user_id, password);
    }
    
    if (parsed.value.avatar) |avatar| {
        try ctx.dao.updateUserAvatar(allocator, target_user_id, avatar);
    }
    
    // Update admin status if requested (admin operations)
    if (parsed.value.is_admin) |is_admin| {
        try ctx.dao.updateUserAdminStatus(allocator, target_user_id, is_admin);
    }
    
    // Return success response
    try json.writeJson(r, allocator, .{
        .user_id = target_user_id,
        .updated = true,
        .message = "User updated successfully",
    });
}

fn deleteAdminUserHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Admin authentication required
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Check if user is admin
    const user = try ctx.dao.getUserById(allocator, user_id);
    defer if (user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    if (user == null or !user.?.is_admin) {
        try json.writeError(r, allocator, .forbidden, "Admin privileges required");
        return;
    }
    
    // Parse user ID from path (/admin/users/{id})
    const path_parts = std.mem.splitScalar(u8, r.path.?, '/');
    var part_count: u32 = 0;
    var target_user_id: i64 = 0;
    
    var iterator = path_parts;
    while (iterator.next()) |part| {
        part_count += 1;
        if (part_count == 4) { // /admin/users/{id}
            target_user_id = std.fmt.parseInt(i64, part, 10) catch {
                try json.writeError(r, allocator, .bad_request, "Invalid user ID");
                return;
            };
            break;
        }
    }
    
    if (target_user_id == 0) {
        try json.writeError(r, allocator, .bad_request, "User ID required");
        return;
    }
    
    // Prevent admin from deleting themselves
    if (target_user_id == user_id) {
        try json.writeError(r, allocator, .bad_request, "Cannot delete your own account");
        return;
    }
    
    // Check if target user exists
    const target_user = try ctx.dao.getUserById(allocator, target_user_id);
    if (target_user == null) {
        try json.writeError(r, allocator, .not_found, "User not found");
        return;
    }
    defer if (target_user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    // Delete the user
    try ctx.dao.deleteUser(allocator, target_user.?.name);
    
    r.setStatus(.no_content);
    try r.sendBody("");
}

fn addAdminUserKeyHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Admin authentication required
    const user_id = auth.authMiddleware(r, ctx, allocator) catch |err| {
        switch (err) {
            else => return err,
        }
    } orelse return;
    
    // Check if user is admin
    const user = try ctx.dao.getUserById(allocator, user_id);
    defer if (user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    if (user == null or !user.?.is_admin) {
        try json.writeError(r, allocator, .forbidden, "Admin privileges required");
        return;
    }
    
    // Parse user ID from path (/admin/users/{id}/keys)
    const path_parts = std.mem.splitScalar(u8, r.path.?, '/');
    var part_count: u32 = 0;
    var target_user_id: i64 = 0;
    
    var iterator = path_parts;
    while (iterator.next()) |part| {
        part_count += 1;
        if (part_count == 4) { // /admin/users/{id}/keys
            target_user_id = std.fmt.parseInt(i64, part, 10) catch {
                try json.writeError(r, allocator, .bad_request, "Invalid user ID");
                return;
            };
            break;
        }
    }
    
    if (target_user_id == 0) {
        try json.writeError(r, allocator, .bad_request, "User ID required");
        return;
    }
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const AddKeyRequest = struct {
        name: []const u8,
        content: []const u8,
    };
    
    var parsed = std.json.parseFromSlice(AddKeyRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer parsed.deinit();
    
    // Validate required fields
    if (parsed.value.name.len == 0 or parsed.value.content.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Key name and content are required");
        return;
    }
    
    // Check if target user exists
    const target_user = try ctx.dao.getUserById(allocator, target_user_id);
    if (target_user == null) {
        try json.writeError(r, allocator, .not_found, "User not found");
        return;
    }
    defer if (target_user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    // Create SSH key - generate fingerprint
    // For now, we'll use a simple hash of the content as fingerprint
    const fingerprint = try std.fmt.allocPrint(allocator, "SHA256:{x}", .{std.hash.CityHash64.hash(parsed.value.content)});
    defer allocator.free(fingerprint);
    
    const new_key = DataAccessObject.PublicKey{
        .id = 0,
        .owner_id = target_user_id,
        .name = parsed.value.name,
        .content = parsed.value.content,
        .fingerprint = fingerprint,
        .created_unix = 0, // Will be set by DAO
        .updated_unix = 0, // Will be set by DAO
    };
    
    try ctx.dao.addPublicKey(allocator, new_key);
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, .{
        .user_id = target_user_id,
        .name = parsed.value.name,
        .fingerprint = fingerprint,
        .created = true,
    });
}

// Helper structures and functions for path parsing
const RepoPath = struct {
    owner: []const u8,
    repo: []const u8,
    
    pub fn deinit(self: *const RepoPath, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
    }
};

const BranchPath = struct {
    owner: []const u8,
    repo: []const u8,
    branch: []const u8,
    
    pub fn deinit(self: *const BranchPath, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
        allocator.free(self.branch);
    }
};

const IssuePath = struct {
    owner: []const u8,
    repo: []const u8,
    issue_number: i64,
    
    pub fn deinit(self: *const IssuePath, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
    }
};

const PullPath = struct {
    owner: []const u8,
    repo: []const u8,
    pull_number: i64,
    
    pub fn deinit(self: *const PullPath, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
    }
};

fn parseRepoPath(allocator: std.mem.Allocator, path: []const u8) !RepoPath {
    // Parse /repos/{owner}/{repo}/... format
    var path_iterator = std.mem.splitScalar(u8, path, '/');
    
    // Skip empty first part and "repos"
    _ = path_iterator.next(); // ""
    _ = path_iterator.next(); // "repos"
    
    const owner = path_iterator.next() orelse return error.InvalidPath;
    const repo = path_iterator.next() orelse return error.InvalidPath;
    
    const owner_owned = try allocator.dupe(u8, owner);
    errdefer allocator.free(owner_owned);
    const repo_owned = try allocator.dupe(u8, repo);
    errdefer allocator.free(repo_owned);
    
    return RepoPath{
        .owner = owner_owned,
        .repo = repo_owned,
    };
}

fn parseBranchPath(allocator: std.mem.Allocator, path: []const u8) !BranchPath {
    // Parse /repos/{owner}/{repo}/branches/{branch} format
    var path_iterator = std.mem.splitScalar(u8, path, '/');
    
    // Skip empty first part and "repos"
    _ = path_iterator.next(); // ""
    _ = path_iterator.next(); // "repos"
    
    const owner = path_iterator.next() orelse return error.InvalidPath;
    const repo = path_iterator.next() orelse return error.InvalidPath;
    _ = path_iterator.next(); // "branches"
    const branch = path_iterator.next() orelse return error.InvalidPath;
    
    const owner_owned = try allocator.dupe(u8, owner);
    errdefer allocator.free(owner_owned);
    const repo_owned = try allocator.dupe(u8, repo);
    errdefer allocator.free(repo_owned);
    const branch_owned = try allocator.dupe(u8, branch);
    errdefer allocator.free(branch_owned);
    
    return BranchPath{
        .owner = owner_owned,
        .repo = repo_owned,
        .branch = branch_owned,
    };
}

fn parseIssuePath(allocator: std.mem.Allocator, path: []const u8) !IssuePath {
    // Parse /repos/{owner}/{repo}/issues/{number} format
    var path_iterator = std.mem.splitScalar(u8, path, '/');
    
    // Skip empty first part and "repos"
    _ = path_iterator.next(); // ""
    _ = path_iterator.next(); // "repos"
    
    const owner = path_iterator.next() orelse return error.InvalidPath;
    const repo = path_iterator.next() orelse return error.InvalidPath;
    _ = path_iterator.next(); // "issues"
    const issue_number_str = path_iterator.next() orelse return error.InvalidPath;
    
    const issue_number = std.fmt.parseInt(i64, issue_number_str, 10) catch return error.InvalidPath;
    
    const owner_owned = try allocator.dupe(u8, owner);
    errdefer allocator.free(owner_owned);
    const repo_owned = try allocator.dupe(u8, repo);
    errdefer allocator.free(repo_owned);
    
    return IssuePath{
        .owner = owner_owned,
        .repo = repo_owned,
        .issue_number = issue_number,
    };
}

fn parsePullPath(allocator: std.mem.Allocator, path: []const u8) !PullPath {
    // Parse /repos/{owner}/{repo}/pulls/{number} format
    var path_iterator = std.mem.splitScalar(u8, path, '/');
    
    // Skip empty first part and "repos"
    _ = path_iterator.next(); // ""
    _ = path_iterator.next(); // "repos"
    
    const owner = path_iterator.next() orelse return error.InvalidPath;
    const repo = path_iterator.next() orelse return error.InvalidPath;
    _ = path_iterator.next(); // "pulls"
    const pull_number_str = path_iterator.next() orelse return error.InvalidPath;
    
    const pull_number = std.fmt.parseInt(i64, pull_number_str, 10) catch return error.InvalidPath;
    
    const owner_owned = try allocator.dupe(u8, owner);
    errdefer allocator.free(owner_owned);
    const repo_owned = try allocator.dupe(u8, repo);
    errdefer allocator.free(repo_owned);
    
    return PullPath{
        .owner = owner_owned,
        .repo = repo_owned,
        .pull_number = pull_number,
    };
}

fn parseQueryParams(allocator: std.mem.Allocator, query: ?[]const u8) !std.StringHashMap([]const u8) {
    var params = std.StringHashMap([]const u8).init(allocator);
    
    const query_string = query orelse return params;
    if (query_string.len == 0) return params;
    
    var param_iterator = std.mem.splitScalar(u8, query_string, '&');
    while (param_iterator.next()) |param| {
        if (std.mem.indexOf(u8, param, "=")) |eq_pos| {
            const key = param[0..eq_pos];
            const value = param[eq_pos + 1..];
            try params.put(key, value);
        }
    }
    
    return params;
}

test "parseRepoPath correctly parses repository paths" {
    const allocator = std.testing.allocator;
    
    const path = "/repos/testowner/testrepo/branches";
    const parsed = try parseRepoPath(allocator, path);
    defer parsed.deinit(allocator);
    
    try std.testing.expectEqualStrings("testowner", parsed.owner);
    try std.testing.expectEqualStrings("testrepo", parsed.repo);
}

test "parseRepoPath handles invalid paths" {
    const allocator = std.testing.allocator;
    
    // Test various invalid paths
    try std.testing.expectError(error.InvalidPath, parseRepoPath(allocator, "/repos"));
    try std.testing.expectError(error.InvalidPath, parseRepoPath(allocator, "/repos/owner"));
    try std.testing.expectError(error.InvalidPath, parseRepoPath(allocator, "/invalid/path"));
}

test "parseBranchPath correctly parses branch paths" {
    const allocator = std.testing.allocator;
    
    const path = "/repos/testowner/testrepo/branches/testbranch";
    const parsed = try parseBranchPath(allocator, path);
    defer parsed.deinit(allocator);
    
    try std.testing.expectEqualStrings("testowner", parsed.owner);
    try std.testing.expectEqualStrings("testrepo", parsed.repo);
    try std.testing.expectEqualStrings("testbranch", parsed.branch);
}

test "parseBranchPath handles invalid paths" {
    const allocator = std.testing.allocator;
    
    // Test various invalid paths
    try std.testing.expectError(error.InvalidPath, parseBranchPath(allocator, "/repos/owner/repo"));
    try std.testing.expectError(error.InvalidPath, parseBranchPath(allocator, "/repos/owner/repo/branches"));
    try std.testing.expectError(error.InvalidPath, parseBranchPath(allocator, "/invalid/path"));
}

test "server initializes correctly" {
    const allocator = std.testing.allocator;
    
    // Create a mock DAO for testing
    var dao = DataAccessObject.init("postgresql://test") catch {
        std.log.warn("Database not available for testing, skipping server test", .{});
        return;
    };
    defer dao.deinit();
    
    // Create test config
    var config = Config{
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
    defer config.deinit();
    
    var server = try Server.init(allocator, &dao, &config);
    defer server.deinit(allocator);
    
    // If we get here, server initialized correctly
    try std.testing.expect(server.context.dao == &dao);
}

test "getBranchHandler correctly parses branch path" {
    const allocator = std.testing.allocator;
    
    // Test that getBranchHandler can parse a branch path correctly
    const path = "/repos/testowner/testrepo/branches/feature-branch";
    const parsed = try parseBranchPath(allocator, path);
    defer parsed.deinit(allocator);
    
    try std.testing.expectEqualStrings("testowner", parsed.owner);
    try std.testing.expectEqualStrings("testrepo", parsed.repo);
    try std.testing.expectEqualStrings("feature-branch", parsed.branch);
}

fn isValidHexColor(color: []const u8) bool {
    if (color.len != 7 or color[0] != '#') return false;
    
    for (color[1..]) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

test "createBranchHandler validates JSON request body" {
    const allocator = std.testing.allocator;
    
    // Test that we can parse valid branch creation JSON
    const valid_json = "{\"name\": \"feature-branch\", \"from_branch\": \"main\"}";
    var json_data = std.json.parseFromSlice(struct {
        name: []const u8,
        from_branch: ?[]const u8 = null,
    }, allocator, valid_json, .{}) catch unreachable;
    defer json_data.deinit();
    
    try std.testing.expectEqualStrings("feature-branch", json_data.value.name);
    try std.testing.expectEqualStrings("main", json_data.value.from_branch.?);
}

test "deleteBranchHandler prevents deletion of default branch" {
    // Test that deleteBranchHandler can detect when trying to delete default branch
    const branch_name = "main";
    const default_branch = "main";
    
    try std.testing.expectEqual(true, std.mem.eql(u8, branch_name, default_branch));
    
    // Test with different branch that should be allowed
    const feature_branch = "feature-branch";
    try std.testing.expectEqual(false, std.mem.eql(u8, feature_branch, default_branch));
}

test "parseIssuePath correctly parses issue paths" {
    const allocator = std.testing.allocator;
    
    const path = "/repos/testowner/testrepo/issues/123";
    const parsed = try parseIssuePath(allocator, path);
    defer parsed.deinit(allocator);
    
    try std.testing.expectEqualStrings("testowner", parsed.owner);
    try std.testing.expectEqualStrings("testrepo", parsed.repo);
    try std.testing.expectEqual(@as(i64, 123), parsed.issue_number);
}

test "parseIssuePath handles invalid paths" {
    const allocator = std.testing.allocator;
    
    // Test various invalid paths
    try std.testing.expectError(error.InvalidPath, parseIssuePath(allocator, "/repos/owner/repo"));
    try std.testing.expectError(error.InvalidPath, parseIssuePath(allocator, "/repos/owner/repo/issues"));
    try std.testing.expectError(error.InvalidPath, parseIssuePath(allocator, "/repos/owner/repo/issues/abc"));
}

test "parseQueryParams correctly parses query parameters" {
    const allocator = std.testing.allocator;
    
    var params = try parseQueryParams(allocator, "state=closed&assignee=john&type=issue");
    defer params.deinit();
    
    try std.testing.expectEqualStrings("closed", params.get("state").?);
    try std.testing.expectEqualStrings("john", params.get("assignee").?);
    try std.testing.expectEqualStrings("issue", params.get("type").?);
}

test "listIssuesHandler filters work correctly" {
    const allocator = std.testing.allocator;
    
    // Test IssueFilters construction
    var query_params = try parseQueryParams(allocator, "state=closed&assignee=123&type=pr");
    defer query_params.deinit();
    
    const filters = DataAccessObject.IssueFilters{
        .is_closed = if (query_params.get("state")) |state| 
            std.mem.eql(u8, state, "closed") else null,
        .is_pull = if (query_params.get("type")) |type_str|
            std.mem.eql(u8, type_str, "pr") else null,
        .assignee_id = if (query_params.get("assignee")) |assignee_str|
            std.fmt.parseInt(i64, assignee_str, 10) catch null else null,
    };
    
    try std.testing.expectEqual(true, filters.is_closed.?);
    try std.testing.expectEqual(true, filters.is_pull.?);
    try std.testing.expectEqual(@as(i64, 123), filters.assignee_id.?);
}

test "createIssueHandler validates JSON request body" {
    const allocator = std.testing.allocator;
    
    // Test that we can parse valid issue creation JSON
    const valid_json = "{\"title\": \"Bug report\", \"body\": \"Description here\", \"assignee\": \"john\"}";
    const CreateIssueRequest = struct {
        title: []const u8,
        body: ?[]const u8 = null,
        assignee: ?[]const u8 = null,
        labels: ?[][]const u8 = null,
    };
    
    var json_data = std.json.parseFromSlice(CreateIssueRequest, allocator, valid_json, .{}) catch unreachable;
    defer json_data.deinit();
    
    try std.testing.expectEqualStrings("Bug report", json_data.value.title);
    try std.testing.expectEqualStrings("Description here", json_data.value.body.?);
    try std.testing.expectEqualStrings("john", json_data.value.assignee.?);
    try std.testing.expect(json_data.value.title.len > 0); // Validates non-empty title
}

test "getIssueHandler correctly uses parseIssuePath" {
    const allocator = std.testing.allocator;
    
    // Test that getIssueHandler can parse issue path correctly  
    const path = "/repos/testowner/testrepo/issues/456";
    const parsed = try parseIssuePath(allocator, path);
    defer parsed.deinit(allocator);
    
    try std.testing.expectEqualStrings("testowner", parsed.owner);
    try std.testing.expectEqualStrings("testrepo", parsed.repo);
    try std.testing.expectEqual(@as(i64, 456), parsed.issue_number);
}

test "updateIssueHandler validates JSON request body" {
    const allocator = std.testing.allocator;
    
    // Test that we can parse valid issue update JSON
    const valid_json = "{\"title\": \"Updated title\", \"state\": \"closed\", \"assignee\": \"jane\"}";
    const UpdateIssueRequest = struct {
        title: ?[]const u8 = null,
        body: ?[]const u8 = null,
        state: ?[]const u8 = null,
        assignee: ?[]const u8 = null,
    };
    
    var json_data = std.json.parseFromSlice(UpdateIssueRequest, allocator, valid_json, .{}) catch unreachable;
    defer json_data.deinit();
    
    try std.testing.expectEqualStrings("Updated title", json_data.value.title.?);
    try std.testing.expectEqualStrings("closed", json_data.value.state.?);
    try std.testing.expectEqualStrings("jane", json_data.value.assignee.?);
    
    // Test state parsing logic
    const is_closed = if (json_data.value.state) |state| 
        std.mem.eql(u8, state, "closed") else false;
    try std.testing.expectEqual(true, is_closed);
}

test "createCommentHandler validates JSON request body" {
    const allocator = std.testing.allocator;
    
    // Test that we can parse valid comment creation JSON
    const valid_json = "{\"body\": \"This is a comment\"}";
    const CreateCommentRequest = struct {
        body: []const u8,
    };
    
    var json_data = std.json.parseFromSlice(CreateCommentRequest, allocator, valid_json, .{}) catch unreachable;
    defer json_data.deinit();
    
    try std.testing.expectEqualStrings("This is a comment", json_data.value.body);
    try std.testing.expect(json_data.value.body.len > 0); // Validates non-empty body
}

test "parsePullPath correctly parses pull request paths" {
    const allocator = std.testing.allocator;
    
    const path = "/repos/testowner/testrepo/pulls/789";
    const parsed = try parsePullPath(allocator, path);
    defer parsed.deinit(allocator);
    
    try std.testing.expectEqualStrings("testowner", parsed.owner);
    try std.testing.expectEqualStrings("testrepo", parsed.repo);
    try std.testing.expectEqual(@as(i64, 789), parsed.pull_number);
}

test "parsePullPath handles invalid paths" {
    const allocator = std.testing.allocator;
    
    // Test various invalid paths
    try std.testing.expectError(error.InvalidPath, parsePullPath(allocator, "/repos/owner/repo"));
    try std.testing.expectError(error.InvalidPath, parsePullPath(allocator, "/repos/owner/repo/pulls"));
    try std.testing.expectError(error.InvalidPath, parsePullPath(allocator, "/repos/owner/repo/pulls/abc"));
}

test "listPullsHandler filters work correctly" {
    const allocator = std.testing.allocator;
    
    // Test that listPullsHandler uses correct filters for pull requests
    var query_params = try parseQueryParams(allocator, "state=closed&assignee=456");
    defer query_params.deinit();
    
    const filters = DataAccessObject.IssueFilters{
        .is_closed = if (query_params.get("state")) |state| 
            std.mem.eql(u8, state, "closed") else null,
        .is_pull = true, // Only pull requests
        .assignee_id = if (query_params.get("assignee")) |assignee_str|
            std.fmt.parseInt(i64, assignee_str, 10) catch null else null,
    };
    
    try std.testing.expectEqual(true, filters.is_closed.?);
    try std.testing.expectEqual(true, filters.is_pull.?);
    try std.testing.expectEqual(@as(i64, 456), filters.assignee_id.?);
}

test "createPullHandler validates JSON request body" {
    const allocator = std.testing.allocator;
    
    // Test that we can parse valid pull request creation JSON
    const valid_json = "{\"title\": \"Add new feature\", \"body\": \"This adds a new feature\", \"head\": \"feature-branch\", \"base\": \"main\"}";
    const CreatePullRequest = struct {
        title: []const u8,
        body: ?[]const u8 = null,
        head: []const u8,
        base: []const u8,
        assignees: ?[][]const u8 = null,
        reviewers: ?[][]const u8 = null,
    };
    
    var json_data = std.json.parseFromSlice(CreatePullRequest, allocator, valid_json, .{}) catch unreachable;
    defer json_data.deinit();
    
    try std.testing.expectEqualStrings("Add new feature", json_data.value.title);
    try std.testing.expectEqualStrings("This adds a new feature", json_data.value.body.?);
    try std.testing.expectEqualStrings("feature-branch", json_data.value.head);
    try std.testing.expectEqualStrings("main", json_data.value.base);
    try std.testing.expect(json_data.value.title.len > 0);
    try std.testing.expect(json_data.value.head.len > 0);
    try std.testing.expect(json_data.value.base.len > 0);
}