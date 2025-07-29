# Implement Actions Database Operations

## Priority: High

## Problem
The Actions/CI system has extensive TODO comments in `src/actions/models.zig` (lines 522-638) indicating that core database operations are not implemented. This prevents the Actions system from functioning.

## Current State
```zig
// Lines 522-638 in src/actions/models.zig show multiple TODO items:

pub fn createWorkflow(self: *ActionsDAO, workflow_data: Workflow) !u32 {
    _ = self;
    _ = workflow_data;
    // TODO: Implement database insertion
    return 1; // Mock ID for testing
}

pub fn getWorkflow(self: *ActionsDAO, workflow_id: u32) !Workflow {
    _ = self;
    _ = workflow_id;
    // TODO: Implement database query
    return ActionsError.WorkflowNotFound;
}

// Plus 15+ more TODO implementations...
```

## Expected Implementation

### 1. Database Schema Requirements
First, ensure the database has the required tables:
```sql
-- Workflows table
CREATE TABLE IF NOT EXISTS workflows (
    id SERIAL PRIMARY KEY,
    repository_id INTEGER NOT NULL,
    name VARCHAR(255) NOT NULL,
    file_path VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Workflow runs table  
CREATE TABLE IF NOT EXISTS workflow_runs (
    id SERIAL PRIMARY KEY,
    repository_id INTEGER NOT NULL,
    workflow_id INTEGER REFERENCES workflows(id),
    run_number INTEGER NOT NULL,
    trigger_event VARCHAR(50) NOT NULL,
    commit_sha VARCHAR(40) NOT NULL,
    branch VARCHAR(255) NOT NULL,
    actor_id INTEGER NOT NULL,
    status VARCHAR(20) DEFAULT 'queued',
    conclusion VARCHAR(20),
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Jobs table
CREATE TABLE IF NOT EXISTS workflow_jobs (
    id SERIAL PRIMARY KEY,
    run_id INTEGER REFERENCES workflow_runs(id),
    job_name VARCHAR(255) NOT NULL,
    status VARCHAR(20) DEFAULT 'queued',
    conclusion VARCHAR(20),
    runner_id INTEGER,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Runners table
CREATE TABLE IF NOT EXISTS action_runners (
    id SERIAL PRIMARY KEY,
    uuid VARCHAR(36) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    owner_id INTEGER NOT NULL,
    repository_id INTEGER DEFAULT 0,
    token_hash VARCHAR(255) NOT NULL,
    labels TEXT, -- JSON array of labels
    status VARCHAR(20) DEFAULT 'offline',
    last_online TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Secrets table
CREATE TABLE IF NOT EXISTS action_secrets (
    id SERIAL PRIMARY KEY,
    owner_id INTEGER NOT NULL,
    repository_id INTEGER DEFAULT 0,
    name VARCHAR(255) NOT NULL,
    encrypted_data TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(owner_id, repository_id, name)
);
```

### 2. Workflow Operations Implementation
```zig
pub fn createWorkflow(self: *ActionsDAO, workflow_data: Workflow) !u32 {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = 
        \\INSERT INTO workflows (repository_id, name, file_path, content, is_active) 
        \\VALUES ($1, $2, $3, $4, $5) 
        \\RETURNING id
    ;
    
    const result = try client.query(query, .{
        workflow_data.repository_id,
        workflow_data.name,
        workflow_data.file_path,
        workflow_data.content,
        workflow_data.is_active,
    });
    
    if (try result.next()) |row| {
        return @intCast(row.get(i32, 0));
    }
    
    return ActionsError.DatabaseError;
}

pub fn getWorkflow(self: *ActionsDAO, workflow_id: u32) !Workflow {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = 
        \\SELECT id, repository_id, name, file_path, content, is_active, 
        \\       EXTRACT(EPOCH FROM created_at)::BIGINT as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::BIGINT as updated_at
        \\FROM workflows WHERE id = $1
    ;
    
    const result = try client.query(query, .{workflow_id});
    
    if (try result.next()) |row| {
        return Workflow{
            .id = @intCast(row.get(i32, 0)),
            .repository_id = @intCast(row.get(i32, 1)),
            .name = try self.allocator.dupe(u8, row.get([]const u8, 2)),
            .file_path = try self.allocator.dupe(u8, row.get([]const u8, 3)),
            .content = try self.allocator.dupe(u8, row.get([]const u8, 4)),
            .is_active = row.get(bool, 5),
            .created_at = row.get(i64, 6),
            .updated_at = row.get(i64, 7),
        };
    }
    
    return ActionsError.WorkflowNotFound;
}

pub fn deleteWorkflow(self: *ActionsDAO, workflow_id: u32) !void {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "DELETE FROM workflows WHERE id = $1";
    const result = try client.query(query, .{workflow_id});
    
    // Check if any rows were affected
    if (result.affectedRows() == 0) {
        return ActionsError.WorkflowNotFound;
    }
}
```

### 3. Workflow Run Operations Implementation
```zig
pub fn createWorkflowRun(self: *ActionsDAO, run_data: struct {
    repository_id: u32,
    workflow_id: u32,
    trigger_event: TriggerEvent,
    commit_sha: []const u8,
    branch: []const u8,
    actor_id: u32,
}) !u32 {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    // Get next run number for this repository
    const run_number_query = 
        \\SELECT COALESCE(MAX(run_number), 0) + 1 
        \\FROM workflow_runs 
        \\WHERE repository_id = $1
    ;
    
    const run_number_result = try client.query(run_number_query, .{run_data.repository_id});
    const run_number = if (try run_number_result.next()) |row| 
        @as(u32, @intCast(row.get(i32, 0))) else 1;
    
    const insert_query = 
        \\INSERT INTO workflow_runs 
        \\(repository_id, workflow_id, run_number, trigger_event, commit_sha, branch, actor_id) 
        \\VALUES ($1, $2, $3, $4, $5, $6, $7) 
        \\RETURNING id
    ;
    
    const trigger_event_str = switch (run_data.trigger_event) {
        .push => "push",
        .pull_request => "pull_request",
        .schedule => "schedule",
        .workflow_dispatch => "workflow_dispatch",
        .repository_dispatch => "repository_dispatch",
    };
    
    const result = try client.query(insert_query, .{
        run_data.repository_id,
        run_data.workflow_id,
        run_number,
        trigger_event_str,
        run_data.commit_sha,
        run_data.branch,
        run_data.actor_id,
    });
    
    if (try result.next()) |row| {
        return @intCast(row.get(i32, 0));
    }
    
    return ActionsError.DatabaseError;
}

pub fn getWorkflowRun(self: *ActionsDAO, run_id: u32) !WorkflowRun {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = 
        \\SELECT id, repository_id, workflow_id, run_number, trigger_event, 
        \\       commit_sha, branch, actor_id, status, conclusion,
        \\       EXTRACT(EPOCH FROM started_at)::BIGINT as started_at,
        \\       EXTRACT(EPOCH FROM completed_at)::BIGINT as completed_at,
        \\       EXTRACT(EPOCH FROM created_at)::BIGINT as created_at
        \\FROM workflow_runs WHERE id = $1
    ;
    
    const result = try client.query(query, .{run_id});
    
    if (try result.next()) |row| {
        const trigger_event_str = row.get([]const u8, 4);
        const trigger_event = if (std.mem.eql(u8, trigger_event_str, "push"))
            TriggerEvent.push
        else if (std.mem.eql(u8, trigger_event_str, "pull_request"))
            TriggerEvent.pull_request
        else if (std.mem.eql(u8, trigger_event_str, "schedule"))
            TriggerEvent.schedule
        else if (std.mem.eql(u8, trigger_event_str, "workflow_dispatch"))
            TriggerEvent.workflow_dispatch
        else
            TriggerEvent.repository_dispatch;
        
        return WorkflowRun{
            .id = @intCast(row.get(i32, 0)),
            .repository_id = @intCast(row.get(i32, 1)),
            .workflow_id = @intCast(row.get(i32, 2)),
            .run_number = @intCast(row.get(i32, 3)),
            .trigger_event = trigger_event,
            .commit_sha = try self.allocator.dupe(u8, row.get([]const u8, 5)),
            .branch = try self.allocator.dupe(u8, row.get([]const u8, 6)),
            .actor_id = @intCast(row.get(i32, 7)),
            .status = parseRunStatus(row.get([]const u8, 8)),
            .conclusion = if (row.get(?[]const u8, 9)) |c| parseRunConclusion(c) else null,
            .started_at = row.get(?i64, 10),
            .completed_at = row.get(?i64, 11),
            .created_at = row.get(i64, 12),
        };
    }
    
    return ActionsError.WorkflowRunNotFound;
}
```

### 4. Runner Operations Implementation
```zig
pub fn registerRunner(self: *ActionsDAO, runner_data: struct {
    uuid: []const u8,
    name: []const u8,
    owner_id: u32,
    repository_id: u32,
    token_hash: []const u8,
    labels: []const []const u8,
}) !u32 {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    // Serialize labels to JSON
    var labels_json = std.ArrayList(u8).init(self.allocator);
    defer labels_json.deinit();
    
    try labels_json.append('[');
    for (runner_data.labels, 0..) |label, i| {
        if (i > 0) try labels_json.appendSlice(",");
        try labels_json.writer().print("\"{s}\"", .{label});
    }
    try labels_json.append(']');
    
    const query = 
        \\INSERT INTO action_runners 
        \\(uuid, name, owner_id, repository_id, token_hash, labels, status, last_online) 
        \\VALUES ($1, $2, $3, $4, $5, $6, 'online', NOW()) 
        \\RETURNING id
    ;
    
    const result = try client.query(query, .{
        runner_data.uuid,
        runner_data.name,
        runner_data.owner_id,
        runner_data.repository_id,
        runner_data.token_hash,
        labels_json.items,
    });
    
    if (try result.next()) |row| {
        return @intCast(row.get(i32, 0));
    }
    
    return ActionsError.DatabaseError;
}

pub fn getRunner(self: *ActionsDAO, runner_id: u32) !ActionRunner {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = 
        \\SELECT id, uuid, name, owner_id, repository_id, token_hash, 
        \\       labels, status, EXTRACT(EPOCH FROM last_online)::BIGINT as last_online
        \\FROM action_runners WHERE id = $1
    ;
    
    const result = try client.query(query, .{runner_id});
    
    if (try result.next()) |row| {
        // Parse labels JSON
        const labels_json = row.get(?[]const u8, 6) orelse "[]";
        const labels = try parseLabelsJson(self.allocator, labels_json);
        
        return ActionRunner{
            .id = @intCast(row.get(i32, 0)),
            .uuid = try self.allocator.dupe(u8, row.get([]const u8, 1)),
            .name = try self.allocator.dupe(u8, row.get([]const u8, 2)),
            .owner_id = @intCast(row.get(i32, 3)),
            .repository_id = @intCast(row.get(i32, 4)),
            .token_hash = try self.allocator.dupe(u8, row.get([]const u8, 5)),
            .labels = labels,
            .status = try self.allocator.dupe(u8, row.get([]const u8, 7)),
            .last_online = row.get(?i64, 8),
        };
    }
    
    return ActionsError.RunnerNotFound;
}

pub fn updateRunnerStatus(self: *ActionsDAO, runner_id: u32, status: []const u8) !void {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = 
        \\UPDATE action_runners 
        \\SET status = $1, last_online = NOW() 
        \\WHERE id = $2
    ;
    
    const result = try client.query(query, .{ status, runner_id });
    
    if (result.affectedRows() == 0) {
        return ActionsError.RunnerNotFound;
    }
}

pub fn removeRunner(self: *ActionsDAO, runner_id: u32) !void {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = "DELETE FROM action_runners WHERE id = $1";
    const result = try client.query(query, .{runner_id});
    
    if (result.affectedRows() == 0) {
        return ActionsError.RunnerNotFound;
    }
}
```

### 5. Secrets Operations Implementation
```zig
pub fn createSecret(self: *ActionsDAO, secret_data: struct {
    owner_id: u32,
    repository_id: u32,
    name: []const u8,
    encrypted_value: []const u8,
}) !void {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = 
        \\INSERT INTO action_secrets (owner_id, repository_id, name, encrypted_data) 
        \\VALUES ($1, $2, $3, $4) 
        \\ON CONFLICT (owner_id, repository_id, name) 
        \\DO UPDATE SET encrypted_data = $4
    ;
    
    _ = try client.query(query, .{
        secret_data.owner_id,
        secret_data.repository_id,
        secret_data.name,
        secret_data.encrypted_value,
    });
}

pub fn getSecret(self: *ActionsDAO, owner_id: u32, repository_id: u32, name: []const u8) !ActionSecret {
    const client = try self.pool.acquire();
    defer self.pool.release(client);
    
    const query = 
        \\SELECT id, owner_id, repository_id, name, encrypted_data,
        \\       EXTRACT(EPOCH FROM created_at)::BIGINT as created_at
        \\FROM action_secrets 
        \\WHERE (owner_id = $1 AND repository_id = 0) 
        \\   OR (owner_id = 0 AND repository_id = $2)
        \\   AND name = $3
        \\ORDER BY repository_id DESC
        \\LIMIT 1
    ;
    
    const result = try client.query(query, .{ owner_id, repository_id, name });
    
    if (try result.next()) |row| {
        return ActionSecret{
            .id = @intCast(row.get(i32, 0)),
            .owner_id = @intCast(row.get(i32, 1)),
            .repository_id = @intCast(row.get(i32, 2)),
            .name = try self.allocator.dupe(u8, row.get([]const u8, 3)),
            .encrypted_data = try self.allocator.dupe(u8, row.get([]const u8, 4)),
            .created_at = row.get(i64, 5),
        };
    }
    
    return ActionsError.SecretNotFound;
}
```

## Helper Functions Needed
```zig
fn parseRunStatus(status_str: []const u8) RunStatus {
    if (std.mem.eql(u8, status_str, "queued")) return .queued;
    if (std.mem.eql(u8, status_str, "in_progress")) return .in_progress;
    if (std.mem.eql(u8, status_str, "completed")) return .completed;
    return .queued; // Default
}

fn parseRunConclusion(conclusion_str: []const u8) RunConclusion {
    if (std.mem.eql(u8, conclusion_str, "success")) return .success;
    if (std.mem.eql(u8, conclusion_str, "failure")) return .failure;
    if (std.mem.eql(u8, conclusion_str, "cancelled")) return .cancelled;
    return .failure; // Default
}

fn parseLabelsJson(allocator: std.mem.Allocator, json_str: []const u8) ![][]const u8 {
    // Parse JSON array of strings into array of owned strings
    const parsed = std.json.parseFromSlice([][]const u8, allocator, json_str, .{}) catch {
        // Return empty array if parsing fails
        return try allocator.alloc([]const u8, 0);
    };
    defer parsed.deinit();
    
    // Create owned copies of all strings
    var owned_labels = try allocator.alloc([]const u8, parsed.value.len);
    errdefer {
        for (owned_labels[0..owned_labels.len]) |label| {
            allocator.free(label);
        }
        allocator.free(owned_labels);
    }
    
    for (parsed.value, 0..) |label, i| {
        owned_labels[i] = try allocator.dupe(u8, label);
    }
    
    return owned_labels;
}
```

## Files to Modify
- `src/actions/models.zig` (implement all TODO database operations)
- Database migration scripts (create tables if not exists)
- Add helper functions for data conversion

## Testing Requirements
- Test all CRUD operations for workflows, runs, jobs, runners, secrets
- Test database constraints and foreign key relationships
- Test concurrent access scenarios
- Test data serialization/deserialization (especially JSON fields)
- Integration tests with the Actions execution system

## Dependencies
- PostgreSQL database with appropriate schema
- Database connection pool (already exists)
- JSON parsing utilities
- Encryption utilities for secrets

## Benefits
- Enables the Actions/CI system to function
- Provides persistent storage for workflow execution
- Enables runner management and job distribution
- Supports secrets management for secure CI/CD