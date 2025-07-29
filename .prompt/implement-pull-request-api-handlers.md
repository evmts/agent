# Implement Pull Request API Handlers

## Priority: High

## Problem
Pull request-related API handlers in `src/server/server.zig` are currently returning "Not implemented" (lines 380-420). Pull requests are essential for code review and collaboration workflows.

## Current State
```zig
// Lines 380-420 in src/server/server.zig
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

fn mergePullHandler(r: zap.Request, ctx: *Context) !void {
    _ = ctx;
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}
```

## Expected Implementation

### 1. List Pull Requests Handler
```zig
fn listPullsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/pulls
    const path_info = try parseRepoPath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    // Parse query parameters for filtering
    const query_params = parseQueryParams(r.query);
    const filters = DataAccessObject.PullRequestFilters{
        .state = if (query_params.get("state")) |state|
            if (std.mem.eql(u8, state, "closed")) .closed
            else if (std.mem.eql(u8, state, "merged")) .merged
            else .open
        else .open,
        .base_branch = query_params.get("base"),
        .head_branch = query_params.get("head"),
    };
    
    const pulls = try ctx.dao.listPullRequests(allocator, repo.id, filters);
    defer {
        for (pulls) |pull| {
            allocator.free(pull.title);
            if (pull.body) |b| allocator.free(b);
            allocator.free(pull.head_branch);
            allocator.free(pull.base_branch);
        }
        allocator.free(pulls);
    }
    
    try json.writeJson(r, allocator, pulls);
}
```

### 2. Create Pull Request Handler
```zig
fn createPullHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
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
    
    const parsed = std.json.parseFromSlice(CreatePullRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer parsed.deinit();
    
    // Validate required fields
    if (parsed.value.title.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Title is required");
        return;
    }
    
    const path_info = try parseRepoPath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    // Validate branches exist
    const head_branch = try ctx.dao.getBranchByName(allocator, repo.id, parsed.value.head);
    if (head_branch == null) {
        try json.writeError(r, allocator, .bad_request, "Head branch does not exist");
        return;
    }
    defer if (head_branch) |b| {
        allocator.free(b.name);
        if (b.commit_id) |c| allocator.free(c);
    };
    
    const base_branch = try ctx.dao.getBranchByName(allocator, repo.id, parsed.value.base);
    if (base_branch == null) {
        try json.writeError(r, allocator, .bad_request, "Base branch does not exist");
        return;
    }
    defer if (base_branch) |b| {
        allocator.free(b.name);
        if (b.commit_id) |c| allocator.free(c);
    };
    
    // Create pull request
    const new_pull = DataAccessObject.PullRequest{
        .id = 0,
        .repo_id = repo.id,
        .index = 0, // Will be set by DAO
        .poster_id = user_id,
        .title = parsed.value.title,
        .body = parsed.value.body,
        .head_branch = parsed.value.head,
        .base_branch = parsed.value.base,
        .merge_base = head_branch.?.commit_id, // Calculate proper merge base
        .has_merged = false,
        .is_closed = false,
        .created_unix = 0, // Will be set by DAO
    };
    
    const pull_id = try ctx.dao.createPullRequest(allocator, new_pull);
    
    // Handle assignees and reviewers
    if (parsed.value.assignees) |assignees| {
        for (assignees) |assignee_name| {
            const assignee = try ctx.dao.getUserByName(allocator, assignee_name);
            if (assignee) |a| {
                try ctx.dao.assignPullRequest(allocator, pull_id, a.id);
                freeUser(allocator, a);
            }
        }
    }
    
    if (parsed.value.reviewers) |reviewers| {
        for (reviewers) |reviewer_name| {
            const reviewer = try ctx.dao.getUserByName(allocator, reviewer_name);
            if (reviewer) |r| {
                try ctx.dao.requestReview(allocator, pull_id, r.id);
                freeUser(allocator, r);
            }
        }
    }
    
    // Return created pull request
    const created_pull = try ctx.dao.getPullRequest(allocator, repo.id, pull_id);
    defer if (created_pull) |pull| {
        allocator.free(pull.title);
        if (pull.body) |b| allocator.free(b);
        allocator.free(pull.head_branch);
        allocator.free(pull.base_branch);
    };
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, created_pull);
}
```

### 3. Get Pull Request Handler
```zig
fn getPullHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Extract owner/repo/pull_number from path: /repos/{owner}/{repo}/pulls/{number}
    const path_info = try parsePullPath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    const pull = try ctx.dao.getPullRequest(allocator, repo.id, path_info.pull_number);
    defer if (pull) |p| {
        allocator.free(p.title);
        if (p.body) |b| allocator.free(b);
        allocator.free(p.head_branch);
        allocator.free(p.base_branch);
    };
    
    if (pull) |p| {
        // Enrich with additional data
        const reviews = try ctx.dao.getPullRequestReviews(allocator, p.id);
        defer for (reviews) |review| {
            if (review.body) |b| allocator.free(b);
        };
        defer allocator.free(reviews);
        
        const files_changed = try ctx.dao.getPullRequestFiles(allocator, p.id);
        defer for (files_changed) |file| {
            allocator.free(file.filename);
        };
        defer allocator.free(files_changed);
        
        const enriched_pull = struct {
            id: i64,
            number: i64,
            title: []const u8,
            body: ?[]const u8,
            head: []const u8,
            base: []const u8,
            state: []const u8,
            reviews: []DataAccessObject.Review,
            files: []DataAccessObject.PullRequestFile,
            mergeable: bool,
        }{
            .id = p.id,
            .number = p.index,
            .title = p.title,
            .body = p.body,
            .head = p.head_branch,
            .base = p.base_branch,
            .state = if (p.has_merged) "merged" else if (p.is_closed) "closed" else "open",
            .reviews = reviews,
            .files = files_changed,
            .mergeable = !p.has_merged and !p.is_closed,
        };
        
        try json.writeJson(r, allocator, enriched_pull);
    } else {
        try json.writeError(r, allocator, .not_found, "Pull request not found");
    }
}
```

### 4. Merge Pull Request Handler
```zig
fn mergePullHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const MergePullRequest = struct {
        commit_title: ?[]const u8 = null,
        commit_message: ?[]const u8 = null,
        merge_method: ?[]const u8 = null, // "merge", "squash", "rebase"
    };
    
    const merge_request = json.parseFromSlice(MergePullRequest, allocator, body) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer json.parseFree(MergePullRequest, allocator, merge_request);
    
    const path_info = try parsePullPath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    const pull = try ctx.dao.getPullRequest(allocator, repo.id, path_info.pull_number);
    if (pull == null) {
        try json.writeError(r, allocator, .not_found, "Pull request not found");
        return;
    }
    defer {
        allocator.free(pull.?.title);
        if (pull.?.body) |b| allocator.free(b);
        allocator.free(pull.?.head_branch);
        allocator.free(pull.?.base_branch);
    }
    
    // Validate pull request can be merged
    if (pull.?.has_merged) {
        try json.writeError(r, allocator, .bad_request, "Pull request is already merged");
        return;
    }
    
    if (pull.?.is_closed) {
        try json.writeError(r, allocator, .bad_request, "Pull request is closed");
        return;
    }
    
    // Check if user has permission to merge
    const has_permission = try ctx.dao.userCanMerge(allocator, user_id, repo.id);
    if (!has_permission) {
        try json.writeError(r, allocator, .forbidden, "Insufficient permissions to merge");
        return;
    }
    
    // Check if required reviews are satisfied
    const required_reviews = try ctx.dao.getRequiredReviews(allocator, repo.id);
    const approved_reviews = try ctx.dao.getApprovedReviews(allocator, pull.?.id);
    if (approved_reviews.len < required_reviews) {
        try json.writeError(r, allocator, .bad_request, "Pull request requires more approvals");
        return;
    }
    
    // Perform the merge
    const merge_method = if (merge_request.merge_method) |method|
        if (std.mem.eql(u8, method, "squash")) MergeMethod.squash
        else if (std.mem.eql(u8, method, "rebase")) MergeMethod.rebase
        else MergeMethod.merge
    else MergeMethod.merge;
    
    const merge_commit = try ctx.dao.mergePullRequest(allocator, .{
        .pull_id = pull.?.id,
        .merger_id = user_id,
        .method = merge_method,
        .commit_title = merge_request.commit_title,
        .commit_message = merge_request.commit_message,
    });
    
    try json.writeJson(r, allocator, .{
        .sha = merge_commit.sha,
        .merged = true,
        .message = "Pull request successfully merged",
    });
}
```

## Helper Functions Needed
```zig
const PullPath = struct {
    owner: []const u8,
    repo: []const u8,
    pull_number: i64,
    
    pub fn deinit(self: *const PullPath, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
    }
};

fn parsePullPath(allocator: std.mem.Allocator, path: []const u8) !PullPath {
    // Parse /repos/{owner}/{repo}/pulls/{number} format
}

const MergeMethod = enum {
    merge,
    squash, 
    rebase,
};
```

## Files to Modify
- `src/server/server.zig` (implement the handler functions)
- Add helper functions for pull request path parsing
- Extend DAO with pull request merge operations

## Testing Requirements
- Test CRUD operations for pull requests
- Test merge conflict handling
- Test review workflow integration
- Test permission checks for merging
- Test different merge methods
- Integration tests with Git operations

## Dependencies
- Existing DAO pull request methods
- Git merge operations
- Authentication and authorization
- Review system integration
- Branch management system

## Benefits
- Enables code review workflows
- Supports collaborative development
- Completes core Git hosting functionality
- Essential for team-based development