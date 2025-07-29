const std = @import("std");
const zap = @import("zap");
pub const DataAccessObject = @import("../database/dao.zig");
const router = @import("router.zig");

// Import handlers
const health = @import("handlers/health.zig");
const users = @import("handlers/users.zig");
const orgs = @import("handlers/orgs.zig");
const repos = @import("handlers/repos.zig");

const Server = @This();

pub const Context = struct {
    dao: *DataAccessObject,
    allocator: std.mem.Allocator,
};

listener: zap.HttpListener,
context: *Context,

// Global context for handlers to access
var global_context: *Context = undefined;

pub fn init(allocator: std.mem.Allocator, dao: *DataAccessObject) !Server {
    const context = try allocator.create(Context);
    context.* = Context{ 
        .dao = dao,
        .allocator = allocator,
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
            if (std.mem.endsWith(u8, path, "/branches")) {
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
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn getBranchHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn createBranchHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn deleteBranchHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn listIssuesHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn createIssueHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn getIssueHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn updateIssueHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn getCommentsHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn createCommentHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn listLabelsHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn createLabelHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn updateLabelHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn deleteLabelHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
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
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn createPullHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn getPullHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn listReviewsHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn createReviewHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn mergePullHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
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
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn updateAdminUserHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn deleteAdminUserHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn addAdminUserKeyHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
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
    
    var server = try Server.init(allocator, &dao);
    defer server.deinit(allocator);
    
    // If we get here, server initialized correctly
    try std.testing.expect(server.context.dao == &dao);
}