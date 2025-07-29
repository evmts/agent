# Implement Labels and Milestones API

## Priority: Medium

## Problem
The labels and milestones API handlers in `src/server/server.zig` are currently returning "Not implemented" (lines 450-480). These features are essential for project organization and issue tracking.

## Current State
```zig
// Lines 450-480 in src/server/server.zig show placeholder handlers for:
fn listLabelsHandler(r: zap.Request, ctx: *Context) !void {
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn createLabelHandler(r: zap.Request, ctx: *Context) !void {
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn listMilestonesHandler(r: zap.Request, ctx: *Context) !void {
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn createMilestoneHandler(r: zap.Request, ctx: *Context) !void {
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}
```

## Expected Implementation

### 1. Database Schema Requirements
```sql
-- Labels table
CREATE TABLE IF NOT EXISTS labels (
    id SERIAL PRIMARY KEY,
    repository_id INTEGER NOT NULL REFERENCES repositories(id),
    name VARCHAR(255) NOT NULL,
    color VARCHAR(7) NOT NULL, -- Hex color code
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(repository_id, name)
);

-- Issue-Label relationships
CREATE TABLE IF NOT EXISTS issue_labels (
    issue_id INTEGER NOT NULL REFERENCES issues(id),
    label_id INTEGER NOT NULL REFERENCES labels(id),
    PRIMARY KEY(issue_id, label_id)
);

-- Milestones table
CREATE TABLE IF NOT EXISTS milestones (
    id SERIAL PRIMARY KEY,
    repository_id INTEGER NOT NULL REFERENCES repositories(id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    state VARCHAR(20) DEFAULT 'open', -- 'open' or 'closed'
    due_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    closed_at TIMESTAMP,
    UNIQUE(repository_id, title)
);

-- Issue-Milestone relationships
ALTER TABLE issues ADD COLUMN milestone_id INTEGER REFERENCES milestones(id);
```

### 2. List Labels Handler
```zig
fn listLabelsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    // Extract owner/repo from path: /repos/{owner}/{repo}/labels
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
    
    const labels = try ctx.dao.getLabels(allocator, repo.id);
    defer {
        for (labels) |label| {
            allocator.free(label.name);
            allocator.free(label.color);
            if (label.description) |d| allocator.free(d);
        }
        allocator.free(labels);
    }
    
    try json.writeJson(r, allocator, labels);
}
```

### 3. Create Label Handler
```zig
fn createLabelHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreateLabelRequest = struct {
        name: []const u8,
        color: []const u8,
        description: ?[]const u8 = null,
    };
    
    const label_request = json.parseFromSlice(CreateLabelRequest, allocator, body) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer json.parseFree(CreateLabelRequest, allocator, label_request);
    
    // Validate required fields
    if (label_request.name.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Label name is required");
        return;
    }
    
    // Validate color format (hex color)
    if (!isValidHexColor(label_request.color)) {
        try json.writeError(r, allocator, .bad_request, "Color must be a valid hex color (e.g., #ff0000)");
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
    
    // Check if user has write access
    const has_access = try ctx.dao.userHasWriteAccess(allocator, user_id, repo.id);
    if (!has_access) {
        try json.writeError(r, allocator, .forbidden, "Insufficient permissions");
        return;
    }
    
    const new_label = DataAccessObject.Label{
        .id = 0,
        .repository_id = repo.id,
        .name = label_request.name,
        .color = label_request.color,
        .description = label_request.description,
        .created_at = 0, // Will be set by DAO
    };
    
    const label_id = try ctx.dao.createLabel(allocator, new_label);
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, .{
        .id = label_id,
        .name = label_request.name,
        .color = label_request.color,
        .description = label_request.description,
        .created = true,
    });
}
```

### 4. Update/Delete Label Handlers
```zig
fn updateLabelHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const UpdateLabelRequest = struct {
        name: ?[]const u8 = null,
        color: ?[]const u8 = null,
        description: ?[]const u8 = null,
    };
    
    const update_request = json.parseFromSlice(UpdateLabelRequest, allocator, body) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer json.parseFree(UpdateLabelRequest, allocator, update_request);
    
    const path_info = try parseLabelPath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    // Validate color if provided
    if (update_request.color) |color| {
        if (!isValidHexColor(color)) {
            try json.writeError(r, allocator, .bad_request, "Color must be a valid hex color");
            return;
        }
    }
    
    const updates = DataAccessObject.LabelUpdate{
        .name = update_request.name,
        .color = update_request.color,
        .description = update_request.description,
    };
    
    try ctx.dao.updateLabel(allocator, repo.id, path_info.label_name, updates);
    
    const updated_label = try ctx.dao.getLabelByName(allocator, repo.id, path_info.label_name);
    defer if (updated_label) |label| {
        allocator.free(label.name);
        allocator.free(label.color);
        if (label.description) |d| allocator.free(d);
    };
    
    try json.writeJson(r, allocator, updated_label);
}

fn deleteLabelHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const path_info = try parseLabelPath(allocator, r.path.?);
    defer path_info.deinit(allocator);
    
    const repo = ctx.dao.getRepositoryByName(allocator, user_id, path_info.repo) catch |err| {
        try handleDatabaseError(r, allocator, err);
        return;
    } orelse {
        try json.writeError(r, allocator, .not_found, "Repository not found");
        return;
    };
    defer freeRepository(allocator, repo);
    
    try ctx.dao.deleteLabel(allocator, repo.id, path_info.label_name);
    
    r.setStatus(.no_content);
    try r.sendBody("");
}
```

### 5. Milestone Handlers
```zig
fn listMilestonesHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
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
    
    // Parse state filter
    const state_filter = if (r.query) |query| blk: {
        if (std.mem.indexOf(u8, query, "state=closed")) |_| {
            break :blk "closed";
        } else if (std.mem.indexOf(u8, query, "state=all")) |_| {
            break :blk "all";
        } else {
            break :blk "open";
        }
    } else "open";
    
    const milestones = try ctx.dao.getMilestones(allocator, repo.id, state_filter);
    defer {
        for (milestones) |milestone| {
            allocator.free(milestone.title);
            if (milestone.description) |d| allocator.free(d);
        }
        allocator.free(milestones);
    }
    
    try json.writeJson(r, allocator, milestones);
}

fn createMilestoneHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const body = r.body orelse {
        try json.writeError(r, allocator, .bad_request, "Request body required");
        return;
    };
    
    const CreateMilestoneRequest = struct {
        title: []const u8,
        description: ?[]const u8 = null,
        due_on: ?[]const u8 = null, // ISO 8601 date string
    };
    
    const milestone_request = json.parseFromSlice(CreateMilestoneRequest, allocator, body) catch {
        try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
        return;
    };
    defer json.parseFree(CreateMilestoneRequest, allocator, milestone_request);
    
    if (milestone_request.title.len == 0) {
        try json.writeError(r, allocator, .bad_request, "Milestone title is required");
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
    
    // Parse due date if provided
    var due_date: ?i64 = null;
    if (milestone_request.due_on) |due_str| {
        due_date = parseISODate(due_str) catch {
            try json.writeError(r, allocator, .bad_request, "Invalid due date format");
            return;
        };
    }
    
    const new_milestone = DataAccessObject.Milestone{
        .id = 0,
        .repository_id = repo.id,
        .title = milestone_request.title,
        .description = milestone_request.description,
        .state = "open",
        .due_date = due_date,
        .created_at = 0, // Will be set by DAO
        .closed_at = null,
    };
    
    const milestone_id = try ctx.dao.createMilestone(allocator, new_milestone);
    
    r.setStatus(.created);
    try json.writeJson(r, allocator, .{
        .id = milestone_id,
        .title = milestone_request.title,
        .description = milestone_request.description,
        .due_on = milestone_request.due_on,
        .state = "open",
        .created = true,
    });
}
```

## Helper Functions Needed
```zig
const LabelPath = struct {
    owner: []const u8,
    repo: []const u8,
    label_name: []const u8,
    
    pub fn deinit(self: *const LabelPath, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
        allocator.free(self.label_name);
    }
};

fn parseLabelPath(allocator: std.mem.Allocator, path: []const u8) !LabelPath {
    // Parse /repos/{owner}/{repo}/labels/{label_name} format
}

fn isValidHexColor(color: []const u8) bool {
    if (color.len != 7 or color[0] != '#') return false;
    
    for (color[1..]) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

fn parseISODate(date_str: []const u8) !i64 {
    // Parse ISO 8601 date string to Unix timestamp
    // Implementation depends on date parsing approach
}
```

## Files to Modify
- `src/server/server.zig` (implement handler functions)
- `src/database/dao.zig` (add label and milestone methods)
- Database migration scripts (create tables)
- Add helper functions for validation and parsing

## Testing Requirements
- Test CRUD operations for labels and milestones
- Test color validation for labels
- Test date parsing for milestones
- Test label-issue associations
- Test milestone-issue associations
- Test duplicate name handling
- Integration tests with issue management

## Dependencies
- Existing DAO infrastructure
- Authentication and authorization
- JSON parsing utilities
- Date/time parsing utilities
- Database schema updates

## Benefits
- Enables better project organization
- Supports issue categorization with labels
- Provides project planning with milestones
- Improves issue tracking workflow
- Essential for project management features