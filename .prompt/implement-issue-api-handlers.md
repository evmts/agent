# Implement Issue API Handlers

## Priority: High

## Problem
Multiple issue-related API handlers in `src/server/server.zig` are currently returning "Not implemented" (lines 344-378). Issues are essential for project management and collaboration.

## Current State
```zig
// Lines 344-378 in src/server/server.zig
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
```

## Expected Implementation

### 1. List Issues Handler
```zig
fn listIssuesHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/issues
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
    const filters = DataAccessObject.IssueFilters{
        .is_closed = if (query_params.get("state")) |state| 
            std.mem.eql(u8, state, "closed") else null,
        .is_pull = if (query_params.get("type")) |type_str|
            std.mem.eql(u8, type_str, "pr") else null,
        .assignee_id = if (query_params.get("assignee")) |assignee_str|
            std.fmt.parseInt(i64, assignee_str, 10) catch null else null,
    };
    
    const issues = try ctx.dao.listIssues(allocator, repo.id, filters);
    defer {
        for (issues) |issue| {
            allocator.free(issue.title);
            if (issue.content) |c| allocator.free(c);
        }
        allocator.free(issues);
    }
    
    try json.writeJson(r, allocator, issues);
}
```

### 2. Create Issue Handler
```zig
fn createIssueHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
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
    
    const parsed = std.json.parseFromSlice(CreateIssueRequest, allocator, body, .{}) catch {
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
    
    // Resolve assignee if provided
    var assignee_id: ?i64 = null;
    if (parsed.value.assignee) |assignee_name| {
        const assignee = try ctx.dao.getUserByName(allocator, assignee_name);
        if (assignee) |a| {
            assignee_id = a.id;
            freeUser(allocator, a);
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
    
    const issue_id = try ctx.dao.createIssue(allocator, new_issue);
    
    // Handle labels if provided
    if (parsed.value.labels) |labels| {
        for (labels) |label_name| {
            // Find or create label and associate with issue
            // Implementation depends on label handling strategy
        }
    }
    
    // Return created issue
    const created_issue = try ctx.dao.getIssue(allocator, repo.id, issue_id);
    defer if (created_issue) |issue| {
        allocator.free(issue.title);
        if (issue.content) |c| allocator.free(c);
    };
    
    try json.writeJson(r, allocator, created_issue);
}
```

### 3. Get Issue Handler
```zig
fn getIssueHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Extract owner/repo/issue_number from path: /repos/{owner}/{repo}/issues/{number}
    const path_info = try parseIssuePath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    const issue = try ctx.dao.getIssue(allocator, repo.id, path_info.issue_number);
    defer if (issue) |i| {
        allocator.free(i.title);
        if (i.content) |c| allocator.free(c);
    };
    
    if (issue) |i| {
        try json.writeJson(r, allocator, i);
    } else {
        try json.writeError(r, allocator, .not_found, "Issue not found");
    }
}
```

### 4. Update Issue Handler
```zig
fn updateIssueHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
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
    
    const update_request = json.parseFromSlice(UpdateIssueRequest, allocator, body) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer json.parseFree(UpdateIssueRequest, allocator, update_request);
    
    const path_info = try parseIssuePath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    // Get existing issue to validate ownership/permissions
    const existing_issue = try ctx.dao.getIssue(allocator, repo.id, path_info.issue_number);
    if (existing_issue == null) {
        try json.writeError(r, allocator, .not_found, "Issue not found");
        return;
    }
    defer {
        allocator.free(existing_issue.?.title);
        if (existing_issue.?.content) |c| allocator.free(c);
    }
    
    // Build update struct
    var updates = DataAccessObject.IssueUpdate{};
    if (update_request.title) |title| updates.title = title;
    if (update_request.body) |body_text| updates.content = body_text;
    if (update_request.state) |state| {
        if (std.mem.eql(u8, state, "closed")) {
            updates.is_closed = true;
        } else if (std.mem.eql(u8, state, "open")) {
            updates.is_closed = false;
        }
    }
    
    // Handle assignee updates
    if (update_request.assignee) |assignee_name| {
        const assignee = try ctx.dao.getUserByName(allocator, assignee_name);
        if (assignee) |a| {
            updates.assignee_id = a.id;
            freeUser(allocator, a);
        }
    }
    
    try ctx.dao.updateIssue(allocator, existing_issue.?.id, updates);
    
    // Return updated issue
    const updated_issue = try ctx.dao.getIssue(allocator, repo.id, path_info.issue_number);
    defer if (updated_issue) |issue| {
        allocator.free(issue.title);
        if (issue.content) |c| allocator.free(c);
    };
    
    try json.writeJson(r, allocator, updated_issue);
}
```

### 5. Comments Handlers
```zig
fn getCommentsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const path_info = try parseIssuePath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    // Get issue to validate it exists
    const issue = try ctx.dao.getIssue(allocator, repo.id, path_info.issue_number);
    if (issue == null) {
        try json.writeError(r, allocator, .not_found, "Issue not found");
        return;
    }
    defer {
        allocator.free(issue.?.title);
        if (issue.?.content) |c| allocator.free(c);
    }
    
    const comments = try ctx.dao.getComments(allocator, issue.?.id);
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
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreateCommentRequest = struct {
        body: []const u8,
    };
    
    const comment_request = json.parseFromSlice(CreateCommentRequest, allocator, body) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer json.parseFree(CreateCommentRequest, allocator, comment_request);
    
    if (comment_request.body.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Comment body is required");
        return;
    }
    
    const path_info = try parseIssuePath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    const issue = try ctx.dao.getIssue(allocator, repo.id, path_info.issue_number);
    if (issue == null) {
        try json.writeError(r, allocator, .not_found, "Issue not found");
        return;
    }
    defer {
        allocator.free(issue.?.title);
        if (issue.?.content) |c| allocator.free(c);
    }
    
    const new_comment = DataAccessObject.Comment{
        .id = 0,
        .poster_id = user_id,
        .issue_id = issue.?.id,
        .review_id = null,
        .content = comment_request.body,
        .commit_id = null,
        .line = null,
        .created_unix = 0, // Will be set by DAO
    };
    
    const comment_id = try ctx.dao.createComment(allocator, new_comment);
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, .{
        .id = comment_id,
        .body = comment_request.body,
        .created = true,
    });
}
```

## Helper Functions Needed
```zig
const IssuePath = struct {
    owner: []const u8,
    repo: []const u8,
    issue_number: i64,
    
    pub fn deinit(self: *const IssuePath, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
    }
};

fn parseIssuePath(allocator: std.mem.Allocator, path: []const u8) !IssuePath {
    // Parse /repos/{owner}/{repo}/issues/{number} format
}

fn parseQueryParams(query: ?[]const u8) std.StringHashMap([]const u8) {
    // Parse URL query parameters
}
```

## Files to Modify
- `src/server/server.zig` (implement the handler functions)
- Add helper functions for path parsing and query parameters
- Update JSON utilities if needed

## Testing Requirements
- Test CRUD operations for issues and comments
- Test filtering and pagination
- Test authentication and authorization
- Test assignee resolution
- Test label handling
- Integration tests with database operations

## Dependencies
- Existing DAO issue and comment methods (already implemented)
- Authentication middleware
- JSON utilities
- Path parsing utilities (need to implement)

## Benefits
- Provides essential project management functionality
- Enables collaboration through issue tracking
- Completes a major API surface area
- Improves user experience significantly