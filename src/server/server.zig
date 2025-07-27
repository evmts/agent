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
                return listBranchesHandler(r, global_context);
            } else if (std.mem.indexOf(u8, path, "/branches/") != null) {
                return getBranchHandler(r, global_context);
            } else if (std.mem.endsWith(u8, path, "/issues")) {
                return listIssuesHandler(r, global_context);
            } else if (std.mem.indexOf(u8, path, "/issues/") != null) {
                if (std.mem.endsWith(u8, path, "/comments")) {
                    return getCommentsHandler(r, global_context);
                } else {
                    return getIssueHandler(r, global_context);
                }
            } else if (std.mem.endsWith(u8, path, "/labels")) {
                return listLabelsHandler(r, global_context);
            } else if (std.mem.endsWith(u8, path, "/pulls")) {
                return listPullsHandler(r, global_context);
            } else if (std.mem.indexOf(u8, path, "/pulls/") != null) {
                if (std.mem.endsWith(u8, path, "/reviews")) {
                    return listReviewsHandler(r, global_context);
                } else {
                    return getPullHandler(r, global_context);
                }
            } else if (std.mem.endsWith(u8, path, "/actions/runs")) {
                return listRunsHandler(r, global_context);
            } else if (std.mem.indexOf(u8, path, "/actions/runs/") != null) {
                if (std.mem.endsWith(u8, path, "/jobs")) {
                    return listJobsHandler(r, global_context);
                } else if (std.mem.endsWith(u8, path, "/artifacts")) {
                    return listArtifactsHandler(r, global_context);
                } else {
                    return getRunHandler(r, global_context);
                }
            } else if (std.mem.indexOf(u8, path, "/actions/artifacts/") != null) {
                return getArtifactHandler(r, global_context);
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
                return createBranchHandler(r, global_context);
            } else if (std.mem.endsWith(u8, path, "/issues")) {
                return createIssueHandler(r, global_context);
            } else if (std.mem.indexOf(u8, path, "/issues/") != null and std.mem.endsWith(u8, path, "/comments")) {
                return createCommentHandler(r, global_context);
            } else if (std.mem.indexOf(u8, path, "/issues/") != null and std.mem.endsWith(u8, path, "/labels")) {
                return addLabelsToIssueHandler(r, global_context);
            } else if (std.mem.endsWith(u8, path, "/labels")) {
                return createLabelHandler(r, global_context);
            } else if (std.mem.endsWith(u8, path, "/pulls")) {
                return createPullHandler(r, global_context);
            } else if (std.mem.indexOf(u8, path, "/pulls/") != null) {
                if (std.mem.endsWith(u8, path, "/reviews")) {
                    return createReviewHandler(r, global_context);
                } else if (std.mem.endsWith(u8, path, "/merge")) {
                    return mergePullHandler(r, global_context);
                }
            }
        } else if (std.mem.startsWith(u8, path, "/admin/users")) {
            if (std.mem.endsWith(u8, path, "/keys")) {
                return addAdminUserKeyHandler(r, global_context);
            } else {
                return createAdminUserHandler(r, global_context);
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
                return updateIssueHandler(r, global_context);
            } else if (std.mem.indexOf(u8, path, "/labels/") != null) {
                return updateLabelHandler(r, global_context);
            } else {
                router.callHandler(r, repos.updateRepoHandler, global_context);
                return;
            }
        } else if (std.mem.startsWith(u8, path, "/admin/users/")) {
            return updateAdminUserHandler(r, global_context);
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
                return deleteBranchHandler(r, global_context);
            } else if (std.mem.indexOf(u8, path, "/labels/") != null) {
                if (std.mem.indexOf(u8, path, "/issues/") != null) {
                    return removeLabelFromIssueHandler(r, global_context);
                } else {
                    return deleteLabelHandler(r, global_context);
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
            return deleteAdminUserHandler(r, global_context);
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