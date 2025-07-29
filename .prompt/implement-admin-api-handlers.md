# Implement Admin API Handlers

## Priority: Medium

## Problem
Administrative API handlers in `src/server/server.zig` are currently returning "Not implemented" (lines 500-540). These endpoints are essential for system administration and user management.

## Current State
```zig
// Lines 500-540 in src/server/server.zig show placeholder handlers for:
fn adminUsersHandler(r: zap.Request, ctx: *Context) !void {
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn adminReposHandler(r: zap.Request, ctx: *Context) !void {
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn adminSystemInfoHandler(r: zap.Request, ctx: *Context) !void {
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}

fn adminConfigHandler(r: zap.Request, ctx: *Context) !void {
    r.setStatus(.not_implemented);
    try r.sendBody("Not implemented");
}
```

## Expected Implementation

### 1. Admin Users Handler
```zig
fn adminUsersHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    // Admin authentication required
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const user = try ctx.dao.getUser(allocator, user_id);
    defer if (user) |u| freeUser(allocator, u);
    
    if (user == null or !user.?.is_admin) {
        try json.writeError(r, allocator, .forbidden, "Admin privileges required");
        return;
    }
    
    switch (r.method) {
        .GET => {
            // List all users with admin details
            const page = if (r.query) |query| blk: {
                if (std.mem.indexOf(u8, query, "page=")) |idx| {
                    const page_start = idx + 5;
                    const page_end = std.mem.indexOfAny(u8, query[page_start..], "&") orelse query.len - page_start;
                    break :blk std.fmt.parseInt(u32, query[page_start..page_start + page_end], 10) catch 1;
                }
                break :blk 1;
            } else 1;
            
            const per_page: u32 = 50;
            const offset = (page - 1) * per_page;
            
            const users = try ctx.dao.listAllUsers(allocator, offset, per_page);
            defer {
                for (users.items) |u| {
                    allocator.free(u.name);
                    allocator.free(u.email);
                    if (u.full_name) |fn| allocator.free(fn);
                }
                allocator.free(users.items);
            }
            
            const admin_user_list = struct {
                users: []DataAccessObject.User,
                total_count: u32,
                page: u32,
                per_page: u32,
            }{
                .users = users.items,
                .total_count = users.total_count,
                .page = page,
                .per_page = per_page,
            };
            
            try json.writeJson(r, allocator, admin_user_list);
        },
        .POST => {
            // Create user (admin-only)
            const body = r.body orelse {
                try json.writeError(r, allocator, .bad_request, "Request body required");
                return;
            };
            
            const CreateUserRequest = struct {
                username: []const u8,
                email: []const u8,
                password: []const u8,
                full_name: ?[]const u8 = null,
                is_admin: bool = false,
                is_active: bool = true,
            };
            
            const user_request = json.parseFromSlice(CreateUserRequest, allocator, body) catch {
                try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
                return;
            };
            defer json.parseFree(CreateUserRequest, allocator, user_request);
            
            // Validate required fields
            if (user_request.username.len == 0 or user_request.email.len == 0 or user_request.password.len == 0) {
                try json.writeError(r, allocator, .bad_request, "Username, email and password are required");
                return;
            }
            
            // Hash password
            const password_hash = try auth.hashPassword(allocator, user_request.password);
            defer allocator.free(password_hash);
            
            const new_user = DataAccessObject.User{
                .id = 0,
                .name = user_request.username,
                .email = user_request.email,
                .password_hash = password_hash,
                .full_name = user_request.full_name,
                .is_admin = user_request.is_admin,
                .is_active = user_request.is_active,
                .created_unix = 0, // Will be set by DAO
            };
            
            const created_user_id = try ctx.dao.createUser(allocator, new_user);
            
            r.setStatus(.created);
            try json.writeJson(r, allocator, .{
                .id = created_user_id,
                .username = user_request.username,
                .email = user_request.email,
                .is_admin = user_request.is_admin,
                .is_active = user_request.is_active,
                .created = true,
            });
        },
        else => {
            try json.writeError(r, allocator, .method_not_allowed, "Method not allowed");
        },
    }
}
```

### 2. Admin Repositories Handler
```zig
fn adminReposHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const user = try ctx.dao.getUser(allocator, user_id);
    defer if (user) |u| freeUser(allocator, u);
    
    if (user == null or !user.?.is_admin) {
        try json.writeError(r, allocator, .forbidden, "Admin privileges required");
        return;
    }
    
    switch (r.method) {
        .GET => {
            // List all repositories with admin details
            const filters = struct {
                is_private: ?bool = null,
                is_archived: ?bool = null,
                owner_id: ?i64 = null,
            }{};
            
            if (r.query) |query| {
                // Parse query parameters for filtering
                if (std.mem.indexOf(u8, query, "private=true")) |_| {
                    filters.is_private = true;
                } else if (std.mem.indexOf(u8, query, "private=false")) |_| {
                    filters.is_private = false;
                }
                
                if (std.mem.indexOf(u8, query, "archived=true")) |_| {
                    filters.is_archived = true;
                } else if (std.mem.indexOf(u8, query, "archived=false")) |_| {
                    filters.is_archived = false;
                }
            }
            
            const repos = try ctx.dao.listAllRepositories(allocator, filters);
            defer {
                for (repos) |repo| {
                    allocator.free(repo.name);
                    if (repo.description) |d| allocator.free(d);
                    allocator.free(repo.default_branch);
                }
                allocator.free(repos);
            }
            
            // Enrich with statistics
            var repo_stats = std.ArrayList(struct {
                repository: DataAccessObject.Repository,
                stats: struct {
                    size_kb: u64,
                    commit_count: u32,
                    branch_count: u32,
                    issue_count: u32,
                    last_activity: i64,
                },
            }).init(allocator);
            defer repo_stats.deinit();
            
            for (repos) |repo| {
                const stats = try ctx.dao.getRepositoryStats(allocator, repo.id);
                try repo_stats.append(.{
                    .repository = repo,
                    .stats = stats,
                });
            }
            
            try json.writeJson(r, allocator, repo_stats.items);
        },
        .DELETE => {
            // Force delete repository (admin-only)
            const path_parts = std.mem.split(u8, r.path.?, "/");
            var part_count: u32 = 0;
            var repo_id: i64 = 0;
            
            while (path_parts.next()) |part| {
                part_count += 1;
                if (part_count == 4) { // /admin/repos/{id}
                    repo_id = std.fmt.parseInt(i64, part, 10) catch {
                        try json.writeError(r, allocator, .bad_request, "Invalid repository ID");
                        return;
                    };
                    break;
                }
            }
            
            if (repo_id == 0) {
                try json.writeError(r, allocator, .bad_request, "Repository ID required");
                return;
            }
            
            // Force delete repository and all associated data
            try ctx.dao.forceDeleteRepository(allocator, repo_id);
            
            r.setStatus(.no_content);
            try r.sendBody("");
        },
        else => {
            try json.writeError(r, allocator, .method_not_allowed, "Method not allowed");
        },
    }
}
```

### 3. Admin System Info Handler
```zig
fn adminSystemInfoHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const user = try ctx.dao.getUser(allocator, user_id);
    defer if (user) |u| freeUser(allocator, u);
    
    if (user == null or !user.?.is_admin) {
        try json.writeError(r, allocator, .forbidden, "Admin privileges required");
        return;
    }
    
    // Gather system statistics
    const system_info = struct {
        version: []const u8,
        uptime_seconds: u64,
        memory_usage: struct {
            total_kb: u64,
            used_kb: u64,
            available_kb: u64,
        },
        database: struct {
            connection_count: u32,
            active_queries: u32,
            total_size_mb: u64,
        },
        repositories: struct {
            total_count: u32,
            public_count: u32,
            private_count: u32,
            total_size_gb: f64,
        },
        users: struct {
            total_count: u32,
            active_count: u32,
            admin_count: u32,
        },
        actions: struct {
            total_workflows: u32,
            active_runners: u32,
            queued_jobs: u32,
            running_jobs: u32,
        },
        lfs: struct {
            total_objects: u32,
            total_size_gb: f64,
            s3_objects: u32,
            filesystem_objects: u32,
        },
    }{
        .version = "1.0.0", // Should come from build info
        .uptime_seconds = getSystemUptime(),
        .memory_usage = getMemoryUsage(),
        .database = try getDatabaseStats(ctx.dao),
        .repositories = try getRepositoryStats(ctx.dao, allocator),
        .users = try getUserStats(ctx.dao, allocator),
        .actions = try getActionsStats(ctx.dao, allocator),
        .lfs = try getLFSStats(ctx.dao, allocator),
    };
    
    try json.writeJson(r, allocator, system_info);
}
```

### 4. Admin Configuration Handler
```zig
fn adminConfigHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const user = try ctx.dao.getUser(allocator, user_id);
    defer if (user) |u| freeUser(allocator, u);
    
    if (user == null or !user.?.is_admin) {
        try json.writeError(r, allocator, .forbidden, "Admin privileges required");
        return;
    }
    
    switch (r.method) {
        .GET => {
            // Get system configuration
            const config = try ctx.dao.getSystemConfiguration(allocator);
            defer {
                // Free config strings
                for (config.items) |item| {
                    allocator.free(item.key);
                    allocator.free(item.value);
                }
                allocator.free(config.items);
            }
            
            try json.writeJson(r, allocator, config.items);
        },
        .PUT => {
            // Update system configuration
            const body = r.body orelse {
                try json.writeError(r, allocator, .bad_request, "Request body required");
                return;
            };
            
            const ConfigUpdate = struct {
                settings: []struct {
                    key: []const u8,
                    value: []const u8,
                },
            };
            
            const config_update = json.parseFromSlice(ConfigUpdate, allocator, body) catch {
                try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
                return;
            };
            defer json.parseFree(ConfigUpdate, allocator, config_update);
            
            // Validate and update each setting
            for (config_update.settings) |setting| {
                if (!isValidConfigKey(setting.key)) {
                    try json.writeError(r, allocator, .bad_request, "Invalid configuration key");
                    return;
                }
                
                try ctx.dao.updateSystemConfiguration(allocator, setting.key, setting.value);
            }
            
            try json.writeJson(r, allocator, .{
                .updated = true,
                .count = config_update.settings.len,
            });
        },
        else => {
            try json.writeError(r, allocator, .method_not_allowed, "Method not allowed");
        },
    }
}
```

### 5. User Management Operations
```zig
fn adminUserOperationsHandler(r: zap.Request, ctx: *Context) !void {
    const allocator = ctx.allocator;
    
    const user_id = try auth.authMiddleware(r, ctx, allocator) orelse return;
    
    const user = try ctx.dao.getUser(allocator, user_id);
    defer if (user) |u| freeUser(allocator, u);
    
    if (user == null or !user.?.is_admin) {
        try json.writeError(r, allocator, .forbidden, "Admin privileges required");
        return;
    }
    
    // Parse user ID from path
    const target_user_id = try parseUserIdFromPath(r.path.?);
    
    switch (r.method) {
        .POST => {
            // Admin operations on users
            const body = r.body orelse {
                try json.writeError(r, allocator, .bad_request, "Request body required");
                return;
            };
            
            const UserOperation = struct {
                action: []const u8, // "suspend", "activate", "make_admin", "remove_admin", "reset_password"
                reason: ?[]const u8 = null,
                new_password: ?[]const u8 = null,
            };
            
            const operation = json.parseFromSlice(UserOperation, allocator, body) catch {
                try json.writeError(r, allocator, .bad_request, "Invalid JSON format");
                return;
            };
            defer json.parseFree(UserOperation, allocator, operation);
            
            if (std.mem.eql(u8, operation.action, "suspend")) {
                try ctx.dao.suspendUser(allocator, target_user_id, operation.reason);
            } else if (std.mem.eql(u8, operation.action, "activate")) {
                try ctx.dao.activateUser(allocator, target_user_id);
            } else if (std.mem.eql(u8, operation.action, "make_admin")) {
                try ctx.dao.updateUserAdminStatus(allocator, target_user_id, true);
            } else if (std.mem.eql(u8, operation.action, "remove_admin")) {
                try ctx.dao.updateUserAdminStatus(allocator, target_user_id, false);
            } else if (std.mem.eql(u8, operation.action, "reset_password")) {
                if (operation.new_password == null) {
                    try json.writeError(r, allocator, .bad_request, "New password required");
                    return;
                }
                const password_hash = try auth.hashPassword(allocator, operation.new_password.?);
                defer allocator.free(password_hash);
                try ctx.dao.updateUserPassword(allocator, target_user_id, password_hash);
            } else {
                try json.writeError(r, allocator, .bad_request, "Unknown action");
                return;
            }
            
            try json.writeJson(r, allocator, .{
                .action = operation.action,
                .target_user_id = target_user_id,
                .success = true,
            });
        },
        else => {
            try json.writeError(r, allocator, .method_not_allowed, "Method not allowed");
        },
    }
}
```

## Helper Functions Needed
```zig
fn getSystemUptime() u64 {
    // Return system uptime in seconds
    // Implementation depends on OS
}

fn getMemoryUsage() struct { total_kb: u64, used_kb: u64, available_kb: u64 } {
    // Get system memory usage
    // Implementation depends on OS
}

fn getDatabaseStats(dao: *DataAccessObject) !struct {
    connection_count: u32,
    active_queries: u32,
    total_size_mb: u64,
} {
    // Query database for connection and size statistics
}

fn getRepositoryStats(dao: *DataAccessObject, allocator: std.mem.Allocator) !struct {
    total_count: u32,
    public_count: u32,
    private_count: u32,
    total_size_gb: f64,
} {
    // Query repository statistics
}

fn getUserStats(dao: *DataAccessObject, allocator: std.mem.Allocator) !struct {
    total_count: u32,
    active_count: u32,
    admin_count: u32,
} {
    // Query user statistics
}

fn isValidConfigKey(key: []const u8) bool {
    // Validate configuration key against allowed keys
    const allowed_keys = [_][]const u8{
        "site.name",
        "site.description", 
        "registration.enabled",
        "registration.email_verification",
        "auth.session_timeout",
        "git.max_repo_size",
        "actions.enabled",
        "lfs.enabled",
        "lfs.max_file_size",
    };
    
    for (allowed_keys) |allowed| {
        if (std.mem.eql(u8, key, allowed)) return true;
    }
    return false;
}

fn parseUserIdFromPath(path: []const u8) !i64 {
    // Parse user ID from path like /admin/users/{id}/operations
}
```

## Files to Modify
- `src/server/server.zig` (implement admin handlers)
- `src/database/dao.zig` (add admin-specific methods)
- Add system statistics gathering utilities
- Add configuration management methods

## Testing Requirements
- Test admin authentication and authorization
- Test user management operations
- Test repository management operations
- Test system information gathering
- Test configuration updates
- Test proper error handling for non-admin users
- Integration tests with actual system operations

## Dependencies
- Existing DAO infrastructure
- Admin authentication middleware
- System information gathering utilities
- Configuration management system
- User management system

## Benefits
- Enables system administration
- Provides user management capabilities
- Offers system monitoring and statistics
- Supports configuration management
- Essential for running a multi-user Git server