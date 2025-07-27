const std = @import("std");
const httpz = @import("httpz");
pub const DataAccessObject = @import("../database/dao.zig");

// Import handlers
const health = @import("handlers/health.zig");
const users = @import("handlers/users.zig");
const orgs = @import("handlers/orgs.zig");
const repos = @import("handlers/repos.zig");

const Server = @This();

pub const Context = struct {
    dao: *DataAccessObject,
};

server: httpz.Server(*Context),
context: *Context,

pub fn init(allocator: std.mem.Allocator, dao: *DataAccessObject) !Server {
    const context = try allocator.create(Context);
    context.* = Context{ .dao = dao };
    
    var server = try httpz.Server(*Context).init(allocator, .{ .port = 8000, .address = "0.0.0.0" }, context);
    
    var router = try server.router(.{});
    router.get("/", health.indexHandler, .{});
    router.get("/health", health.healthHandler, .{});
    
    // User endpoints
    router.get("/user", users.getCurrentUserHandler, .{}); // Authenticated user endpoint
    router.post("/user/keys", users.createSSHKeyHandler, .{}); // Create SSH key
    router.get("/user/keys", users.listSSHKeysHandler, .{}); // List SSH keys
    router.delete("/user/keys/:id", users.deleteSSHKeyHandler, .{}); // Delete SSH key
    router.get("/users", users.getUsersHandler, .{});
    router.post("/users", users.createUserHandler, .{});
    router.get("/users/:name", users.getUserHandler, .{});
    router.put("/users/:name", users.updateUserHandler, .{});
    router.delete("/users/:name", users.deleteUserHandler, .{});
    router.get("/user/orgs", users.listUserOrgsHandler, .{}); // List user's organizations
    router.post("/user/repos", users.createUserRepoHandler, .{}); // Create user repository
    
    // Organization endpoints
    router.post("/orgs", orgs.createOrgHandler, .{}); // Create organization
    router.get("/orgs/:org", orgs.getOrgHandler, .{}); // Get organization
    router.patch("/orgs/:org", orgs.updateOrgHandler, .{}); // Update organization
    router.delete("/orgs/:org", orgs.deleteOrgHandler, .{}); // Delete organization
    router.get("/orgs/:org/members", orgs.listOrgMembersHandler, .{}); // List org members
    router.delete("/orgs/:org/members/:username", orgs.removeOrgMemberHandler, .{}); // Remove member
    router.post("/orgs/:org/repos", orgs.createOrgRepoHandler, .{}); // Create org repository
    
    // Repository endpoints
    router.get("/repos/:owner/:name", repos.getRepoHandler, .{});
    router.patch("/repos/:owner/:name", repos.updateRepoHandler, .{}); // Update repository
    router.delete("/repos/:owner/:name", repos.deleteRepoHandler, .{}); // Delete repository
    router.post("/repos/:owner/:name/forks", repos.forkRepoHandler, .{}); // Fork repository
    
    // Branch endpoints (TODO: move to branches.zig)
    router.get("/repos/:owner/:name/branches", listBranchesHandler, .{}); // List branches
    router.get("/repos/:owner/:name/branches/:branch", getBranchHandler, .{}); // Get branch
    router.post("/repos/:owner/:name/branches", createBranchHandler, .{}); // Create branch
    router.delete("/repos/:owner/:name/branches/:branch", deleteBranchHandler, .{}); // Delete branch
    
    // Issue endpoints (TODO: move to issues.zig)
    router.get("/repos/:owner/:name/issues", listIssuesHandler, .{}); // List issues
    router.post("/repos/:owner/:name/issues", createIssueHandler, .{});
    router.get("/repos/:owner/:name/issues/:index", getIssueHandler, .{});
    router.patch("/repos/:owner/:name/issues/:index", updateIssueHandler, .{}); // Update issue
    router.get("/repos/:owner/:name/issues/:index/comments", getCommentsHandler, .{}); // List comments
    router.post("/repos/:owner/:name/issues/:index/comments", createCommentHandler, .{}); // Add comment
    
    // Label endpoints (TODO: move to labels.zig)
    router.get("/repos/:owner/:name/labels", listLabelsHandler, .{}); // List labels
    router.post("/repos/:owner/:name/labels", createLabelHandler, .{}); // Create label
    router.patch("/repos/:owner/:name/labels/:id", updateLabelHandler, .{}); // Update label
    router.delete("/repos/:owner/:name/labels/:id", deleteLabelHandler, .{}); // Delete label
    router.post("/repos/:owner/:name/issues/:index/labels", addLabelsToIssueHandler, .{}); // Add labels to issue
    router.delete("/repos/:owner/:name/issues/:index/labels/:id", removeLabelFromIssueHandler, .{}); // Remove label from issue
    
    // Pull request endpoints (TODO: move to pulls.zig)
    router.get("/repos/:owner/:name/pulls", listPullsHandler, .{}); // List pull requests
    router.post("/repos/:owner/:name/pulls", createPullHandler, .{}); // Create pull request
    router.get("/repos/:owner/:name/pulls/:index", getPullHandler, .{}); // Get pull request
    router.get("/repos/:owner/:name/pulls/:index/reviews", listReviewsHandler, .{}); // List reviews
    router.post("/repos/:owner/:name/pulls/:index/reviews", createReviewHandler, .{}); // Submit review
    router.post("/repos/:owner/:name/pulls/:index/merge", mergePullHandler, .{}); // Merge PR
    
    // Actions/CI endpoints (TODO: move to actions.zig)
    router.get("/repos/:owner/:name/actions/runs", listRunsHandler, .{}); // List workflow runs
    router.get("/repos/:owner/:name/actions/runs/:run_id", getRunHandler, .{}); // Get workflow run
    router.get("/repos/:owner/:name/actions/runs/:run_id/jobs", listJobsHandler, .{}); // List jobs for run
    router.get("/repos/:owner/:name/actions/runs/:run_id/artifacts", listArtifactsHandler, .{}); // List artifacts for run
    router.get("/repos/:owner/:name/actions/artifacts/:artifact_id", getArtifactHandler, .{}); // Get artifact
    
    // Actions/CI secrets and runners (already moved)
    router.get("/orgs/:org/actions/secrets", orgs.listOrgSecretsHandler, .{}); // List org secrets
    router.put("/orgs/:org/actions/secrets/:secretname", orgs.createOrgSecretHandler, .{}); // Create/update org secret
    router.delete("/orgs/:org/actions/secrets/:secretname", orgs.deleteOrgSecretHandler, .{}); // Delete org secret
    router.get("/repos/:owner/:name/actions/secrets", repos.listRepoSecretsHandler, .{}); // List repo secrets
    router.put("/repos/:owner/:name/actions/secrets/:secretname", repos.createRepoSecretHandler, .{}); // Create/update repo secret
    router.delete("/repos/:owner/:name/actions/secrets/:secretname", repos.deleteRepoSecretHandler, .{}); // Delete repo secret
    router.get("/orgs/:org/actions/runners", orgs.listOrgRunnersHandler, .{}); // List org runners
    router.get("/repos/:owner/:name/actions/runners", repos.listRepoRunnersHandler, .{}); // List repo runners
    router.get("/orgs/:org/actions/runners/registration-token", orgs.getOrgRunnerTokenHandler, .{}); // Get org runner token
    router.get("/repos/:owner/:name/actions/runners/registration-token", repos.getRepoRunnerTokenHandler, .{}); // Get repo runner token
    router.delete("/orgs/:org/actions/runners/:runner_id", orgs.deleteOrgRunnerHandler, .{}); // Delete org runner
    router.delete("/repos/:owner/:name/actions/runners/:runner_id", repos.deleteRepoRunnerHandler, .{}); // Delete repo runner
    
    // Admin endpoints (TODO: move to admin.zig)
    router.post("/admin/users", createAdminUserHandler, .{}); // Create user
    router.patch("/admin/users/:username", updateAdminUserHandler, .{}); // Update user
    router.delete("/admin/users/:username", deleteAdminUserHandler, .{}); // Delete user
    router.post("/admin/users/:username/keys", addAdminUserKeyHandler, .{}); // Add SSH key
    
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

// Temporary placeholder functions for handlers not yet moved
// These will be removed as we extract more handler files

fn listBranchesHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn getBranchHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn createBranchHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn deleteBranchHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn listIssuesHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn createIssueHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn getIssueHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn updateIssueHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn getCommentsHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn createCommentHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn listLabelsHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn createLabelHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn updateLabelHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn deleteLabelHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn addLabelsToIssueHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn removeLabelFromIssueHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn listPullsHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn createPullHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn getPullHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn listReviewsHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn createReviewHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn mergePullHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn listRunsHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn getRunHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn listJobsHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn listArtifactsHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn getArtifactHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn createAdminUserHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn updateAdminUserHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn deleteAdminUserHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
}

fn addAdminUserKeyHandler(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 501;
    res.body = "Not implemented";
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