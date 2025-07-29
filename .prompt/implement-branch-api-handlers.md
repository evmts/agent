# Implement Branch API Handlers

## Priority: High

## Problem
Multiple branch-related API handlers in `src/server/server.zig` are currently returning "Not implemented" (lines 320-342). These are core Git functionality that users expect.

## Current State
```zig
// Lines 320-342 in src/server/server.zig
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
```

## Expected Implementation

### 1. List Branches Handler
```zig
fn listBranchesHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/branches
    const path_parts = try parseRepoPath(allocator, r.path.?);
    defer allocator.free(path_parts.owner);
    defer allocator.free(path_parts.repo);
    
    // Get user from auth
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Get repository
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_parts.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    // Get branches from database
    const branches = try ctx.dao.getBranches(allocator, repo.id);
    defer {
        for (branches) |branch| {
            allocator.free(branch.name);
            if (branch.commit_id) |c| allocator.free(c);
        }
        allocator.free(branches);
    }
    
    try json.writeJson(r, allocator, branches);
}
```

### 2. Get Single Branch Handler
```zig
fn getBranchHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Extract owner/repo/branch from path: /repos/{owner}/{repo}/branches/{branch}
    const path_info = try parseBranchPath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    const branch = try ctx.dao.getBranchByName(allocator, repo.id, path_info.branch);
    defer if (branch) |b| {
        allocator.free(b.name);
        if (b.commit_id) |c| allocator.free(c);
    };
    
    if (branch) |b| {
        try json.writeJson(r, allocator, b);
    } else {
        try json.writeError(r, allocator, .not_found, "Branch not found");
    }
}
```

### 3. Create Branch Handler
```zig
fn createBranchHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Parse request body
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreateBranchRequest = struct {
        name: []const u8,
        source_branch: ?[]const u8 = null,
        commit_sha: ?[]const u8 = null,
    };
    
    const parsed = std.json.parseFromSlice(CreateBranchRequest, allocator, body, .{}) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer parsed.deinit();
    
    // Extract repo info from path
    const path_info = try parseRepoPath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    // Get repository and validate permissions
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    // Create branch in database
    const new_branch = Branch{
        .id = 0,
        .repo_id = repo.id,
        .name = parsed.value.name,
        .commit_id = parsed.value.commit_sha,
        .is_protected = false,
    };
    
    try ctx.dao.createBranch(allocator, new_branch);
    
    try json.writeJson(r, allocator, .{
        .name = parsed.value.name,
        .protected = false,
        .created = true,
    });
}
```

### 4. Delete Branch Handler
```zig
fn deleteBranchHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const path_info = try parseBranchPath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    // Prevent deletion of default branch
    if (std.mem.eql(u8, path_info.branch, repo.default_branch)) {
        try json.writeError(r, allocator, .bad_request, "Cannot delete default branch");
        return;
    }
    
    try ctx.dao.deleteBranch(allocator, repo.id, path_info.branch);
    
    r.setStatus(.no_content);
    try r.sendBody("");
}
```

## Helper Functions Needed
```zig
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
    var path_iterator = std.mem.split(u8, path, "/");
    
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
    var path_iterator = std.mem.split(u8, path, "/");
    
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
```

## Files to Modify
- `src/server/server.zig` (implement the 4 handler functions)
- Add helper functions for path parsing
- Update existing DAO methods if needed

## Testing Requirements
- Test all CRUD operations for branches
- Test authentication and authorization
- Test error conditions (branch not found, invalid input)
- Test edge cases (default branch deletion, duplicate branch names)
- Integration tests with actual Git operations

## Dependencies
- Existing DAO branch methods (already implemented)
- Authentication middleware
- JSON utilities
- Path parsing utilities (need to implement)

## Priority Justification
Branch management is core Git functionality that users will expect immediately. Without this, the API is incomplete for basic repository operations.