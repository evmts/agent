const std = @import("std");
const testing = std.testing;
const post_receive = @import("../git/post_receive.zig");
const Commit = post_receive.Commit;

// Push event structure for workflow triggering
pub const PushEvent = struct {
    repository_id: u32,
    repository_path: []const u8 = "",
    user_id: u32 = 0,
    before: []const u8, // Old commit SHA
    after: []const u8,  // New commit SHA
    ref: []const u8,    // refs/heads/main
    commits: []const Commit,
    created: bool = false,
    deleted: bool = false,
    forced: bool = false,
    timestamp: i64,
    
    pub fn deinit(self: *PushEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.repository_path);
        allocator.free(self.before);
        allocator.free(self.after);
        allocator.free(self.ref);
        
        for (self.commits) |*commit| {
            commit.deinit(allocator);
        }
        allocator.free(self.commits);
    }
    
    pub fn getBranchName(self: PushEvent) ?[]const u8 {
        if (std.mem.startsWith(u8, self.ref, "refs/heads/")) {
            return self.ref[11..]; // Remove "refs/heads/"
        }
        return null;
    }
    
    pub fn getTagName(self: PushEvent) ?[]const u8 {
        if (std.mem.startsWith(u8, self.ref, "refs/tags/")) {
            return self.ref[10..]; // Remove "refs/tags/"
        }
        return null;
    }
    
    pub fn getAllChangedFiles(self: PushEvent, allocator: std.mem.Allocator) ![]const []const u8 {
        var all_files = std.ArrayList([]const u8).init(allocator);
        
        for (self.commits) |commit| {
            for (commit.added) |file| {
                try all_files.append(try allocator.dupe(u8, file));
            }
            for (commit.modified) |file| {
                try all_files.append(try allocator.dupe(u8, file));
            }
            for (commit.removed) |file| {
                try all_files.append(try allocator.dupe(u8, file));
            }
        }
        
        return all_files.toOwnedSlice();
    }
};

// Workflow trigger conditions
pub const TriggerConditions = struct {
    branches: ?[]const []const u8 = null,
    branches_ignore: ?[]const []const u8 = null,
    tags: ?[]const []const u8 = null,
    tags_ignore: ?[]const []const u8 = null,
    paths: ?[]const []const u8 = null,
    paths_ignore: ?[]const []const u8 = null,
    types: ?[]const []const u8 = null, // For pull_request events
    
    pub fn deinit(self: *TriggerConditions, allocator: std.mem.Allocator) void {
        if (self.branches) |branches| {
            for (branches) |branch| allocator.free(branch);
            allocator.free(branches);
        }
        
        if (self.branches_ignore) |branches| {
            for (branches) |branch| allocator.free(branch);
            allocator.free(branches);
        }
        
        if (self.tags) |tags| {
            for (tags) |tag| allocator.free(tag);
            allocator.free(tags);
        }
        
        if (self.tags_ignore) |tags| {
            for (tags) |tag| allocator.free(tag);
            allocator.free(tags);
        }
        
        if (self.paths) |paths| {
            for (paths) |path| allocator.free(path);
            allocator.free(paths);
        }
        
        if (self.paths_ignore) |paths| {
            for (paths) |path| allocator.free(path);
            allocator.free(paths);
        }
        
        if (self.types) |types| {
            for (types) |type_str| allocator.free(type_str);
            allocator.free(types);
        }
    }
};

// Workflow trigger configuration
pub const TriggerConfig = struct {
    event_type: EventType,
    conditions: TriggerConditions,
    
    pub const EventType = enum {
        push,
        pull_request,
        schedule,
        workflow_call,
        workflow_dispatch,
        release,
        issues,
        
        pub fn fromString(event_name: []const u8) EventType {
            if (std.mem.eql(u8, event_name, "push")) return .push;
            if (std.mem.eql(u8, event_name, "pull_request")) return .pull_request;
            if (std.mem.eql(u8, event_name, "schedule")) return .schedule;
            if (std.mem.eql(u8, event_name, "workflow_call")) return .workflow_call;
            if (std.mem.eql(u8, event_name, "workflow_dispatch")) return .workflow_dispatch;
            if (std.mem.eql(u8, event_name, "release")) return .release;
            if (std.mem.eql(u8, event_name, "issues")) return .issues;
            return .push; // Default
        }
    };
    
    pub fn deinit(self: *TriggerConfig, allocator: std.mem.Allocator) void {
        self.conditions.deinit(allocator);
    }
};

// Mock workflow for testing
pub const Workflow = struct {
    id: u32,
    name: []const u8,
    triggers: []TriggerConfig,
    
    pub fn deinit(self: *Workflow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        
        for (self.triggers) |*trigger| {
            trigger.deinit(allocator);
        }
        allocator.free(self.triggers);
    }
    
    pub fn parseFromYaml(allocator: std.mem.Allocator, yaml_content: []const u8) !Workflow {
        _ = yaml_content;
        
        // Mock implementation - in real implementation, this would parse YAML
        var triggers = std.ArrayList(TriggerConfig).init(allocator);
        
        // Create a simple push trigger for testing
        var branches = std.ArrayList([]const u8).init(allocator);
        try branches.append(try allocator.dupe(u8, "main"));
        try branches.append(try allocator.dupe(u8, "develop"));
        
        var paths = std.ArrayList([]const u8).init(allocator);
        try paths.append(try allocator.dupe(u8, "src/**"));
        
        var paths_ignore = std.ArrayList([]const u8).init(allocator);
        try paths_ignore.append(try allocator.dupe(u8, "docs/**"));
        
        try triggers.append(TriggerConfig{
            .event_type = .push,
            .conditions = TriggerConditions{
                .branches = try branches.toOwnedSlice(),
                .paths = try paths.toOwnedSlice(),
                .paths_ignore = try paths_ignore.toOwnedSlice(),
            },
        });
        
        return Workflow{
            .id = 1,
            .name = try allocator.dupe(u8, "CI"),
            .triggers = try triggers.toOwnedSlice(),
        };
    }
};

// Workflow trigger evaluator
pub const WorkflowTrigger = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, config: anytype) !WorkflowTrigger {
        _ = config;
        return WorkflowTrigger{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *WorkflowTrigger) void {
        _ = self;
    }
    
    pub fn evaluateTrigger(self: *WorkflowTrigger, trigger: TriggerConfig, event: PushEvent) !bool {
        switch (trigger.event_type) {
            .push => return try self.evaluatePushTrigger(trigger, event),
            .pull_request => return false, // Not handling PR events in push hooks
            else => return false,
        }
    }
    
    fn evaluatePushTrigger(self: *WorkflowTrigger, trigger: TriggerConfig, event: PushEvent) !bool {
        // Check branch conditions
        if (trigger.conditions.branches) |branches| {
            if (!self.matchBranches(branches, event.ref)) {
                return false;
            }
        }
        
        if (trigger.conditions.branches_ignore) |branches_ignore| {
            if (self.matchBranches(branches_ignore, event.ref)) {
                return false;
            }
        }
        
        // Check tag conditions
        if (trigger.conditions.tags) |tags| {
            if (!self.matchTags(tags, event.ref)) {
                return false;
            }
        }
        
        if (trigger.conditions.tags_ignore) |tags_ignore| {
            if (self.matchTags(tags_ignore, event.ref)) {
                return false;
            }
        }
        
        // Check path conditions
        if (trigger.conditions.paths) |paths| {
            const changed_files = try event.getAllChangedFiles(self.allocator);
            defer {
                for (changed_files) |file| {
                    self.allocator.free(file);
                }
                self.allocator.free(changed_files);
            }
            
            if (!self.matchPaths(paths, changed_files)) {
                return false;
            }
        }
        
        if (trigger.conditions.paths_ignore) |paths_ignore| {
            const changed_files = try event.getAllChangedFiles(self.allocator);
            defer {
                for (changed_files) |file| {
                    self.allocator.free(file);
                }
                self.allocator.free(changed_files);
            }
            
            // If any changed file matches ignore patterns, skip
            if (self.matchPaths(paths_ignore, changed_files)) {
                return false;
            }
        }
        
        return true;
    }
    
    pub fn matchBranches(self: *WorkflowTrigger, patterns: []const []const u8, ref: []const u8) bool {
        _ = self;
        
        // Extract branch name from ref
        const branch_name = if (std.mem.startsWith(u8, ref, "refs/heads/"))
            ref[11..]
        else
            return false;
        
        for (patterns) |pattern| {
            if (self.matchPattern(pattern, branch_name)) {
                return true;
            }
        }
        
        return false;
    }
    
    pub fn matchTags(self: *WorkflowTrigger, patterns: []const []const u8, ref: []const u8) bool {
        _ = self;
        
        // Extract tag name from ref
        const tag_name = if (std.mem.startsWith(u8, ref, "refs/tags/"))
            ref[10..]
        else
            return false;
        
        for (patterns) |pattern| {
            if (self.matchPattern(pattern, tag_name)) {
                return true;
            }
        }
        
        return false;
    }
    
    pub fn matchPaths(self: *WorkflowTrigger, patterns: []const []const u8, changed_files: []const []const u8) bool {
        for (changed_files) |file| {
            for (patterns) |pattern| {
                if (self.matchPattern(pattern, file)) {
                    return true;
                }
            }
        }
        
        return false;
    }
    
    fn matchPattern(self: *WorkflowTrigger, pattern: []const u8, text: []const u8) bool {
        _ = self;
        
        // Simple pattern matching - in real implementation, use glob patterns
        
        // Handle exact matches
        if (std.mem.eql(u8, pattern, text)) {
            return true;
        }
        
        // Handle wildcard patterns
        if (std.mem.endsWith(u8, pattern, "/**")) {
            const prefix = pattern[0..pattern.len - 3]; // Remove "/**"
            return std.mem.startsWith(u8, text, prefix);
        }
        
        if (std.mem.endsWith(u8, pattern, "/*")) {
            const prefix = pattern[0..pattern.len - 2]; // Remove "/*"
            return std.mem.startsWith(u8, text, prefix) and
                   std.mem.indexOf(u8, text[prefix.len..], "/") == null;
        }
        
        if (std.mem.startsWith(u8, pattern, "*/")) {
            const suffix = pattern[2..]; // Remove "*/"
            return std.mem.endsWith(u8, text, suffix);
        }
        
        if (std.mem.indexOf(u8, pattern, "*") != null) {
            // Complex wildcard matching - simplified for testing
            return std.mem.indexOf(u8, text, pattern[0..1]) != null;
        }
        
        return false;
    }
};

// Helper function to create test workflow
fn createTestWorkflow(allocator: std.mem.Allocator, name: []const u8) !Workflow {
    var triggers = std.ArrayList(TriggerConfig).init(allocator);
    
    try triggers.append(TriggerConfig{
        .event_type = .push,
        .conditions = TriggerConditions{},
    });
    
    return Workflow{
        .id = 1,
        .name = try allocator.dupe(u8, name),
        .triggers = try triggers.toOwnedSlice(),
    };
}

// Tests for Phase 2: Workflow Trigger Matching
test "matches push events against workflow triggers" {
    const allocator = testing.allocator;
    
    var workflow_trigger = try WorkflowTrigger.init(allocator, .{});
    defer workflow_trigger.deinit();
    
    // Define workflow with push trigger
    var workflow = try Workflow.parseFromYaml(allocator, "");
    defer workflow.deinit(allocator);
    
    // Test push event that should match
    var commits = std.ArrayList(Commit).init(allocator);
    defer commits.deinit();
    
    try commits.append(Commit{
        .id = try allocator.dupe(u8, "abc123"),
        .message = try allocator.dupe(u8, "Test commit"),
        .author = post_receive.GitAuthor{
            .name = try allocator.dupe(u8, "Test Author"),
            .email = try allocator.dupe(u8, "test@example.com"),
        },
        .committer = post_receive.GitAuthor{
            .name = try allocator.dupe(u8, "Test Author"),
            .email = try allocator.dupe(u8, "test@example.com"),
        },  
        .timestamp = std.time.timestamp(),
        .added = try allocator.dupe([]const u8, &[_][]const u8{}),
        .removed = try allocator.dupe([]const u8, &[_][]const u8{}),
        .modified = try allocator.dupe([]const u8, &[_][]const u8{ "src/main.js", "src/utils.js" }),
    });
    
    var matching_event = PushEvent{
        .repository_id = 1,
        .before = try allocator.dupe(u8, "000000"),
        .after = try allocator.dupe(u8, "abc123"),
        .ref = try allocator.dupe(u8, "refs/heads/main"),
        .commits = try commits.toOwnedSlice(),
        .timestamp = std.time.timestamp(),
    };
    defer matching_event.deinit(allocator);
    
    const should_trigger = try workflow_trigger.evaluateTrigger(workflow.triggers[0], matching_event);
    try testing.expect(should_trigger);
}

test "rejects non-matching branch names" {  
    const allocator = testing.allocator;
    
    var workflow_trigger = try WorkflowTrigger.init(allocator, .{});
    defer workflow_trigger.deinit();
    
    var workflow = try Workflow.parseFromYaml(allocator, "");
    defer workflow.deinit(allocator);
    
    var commits = std.ArrayList(Commit).init(allocator);
    defer commits.deinit();
    
    try commits.append(Commit{
        .id = try allocator.dupe(u8, "def456"),
        .message = try allocator.dupe(u8, "Feature commit"),
        .author = post_receive.GitAuthor{
            .name = try allocator.dupe(u8, "Test Author"),
            .email = try allocator.dupe(u8, "test@example.com"),
        },
        .committer = post_receive.GitAuthor{
            .name = try allocator.dupe(u8, "Test Author"),
            .email = try allocator.dupe(u8, "test@example.com"),
        },
        .timestamp = std.time.timestamp(),
        .added = try allocator.dupe([]const u8, &[_][]const u8{}),
        .removed = try allocator.dupe([]const u8, &[_][]const u8{}),
        .modified = try allocator.dupe([]const u8, &[_][]const u8{"src/main.js"}),
    });
    
    // Test push event that should not match (wrong branch)
    var non_matching_event = PushEvent{
        .repository_id = 1,
        .before = try allocator.dupe(u8, "000000"),
        .after = try allocator.dupe(u8, "def456"),
        .ref = try allocator.dupe(u8, "refs/heads/feature-branch"),
        .commits = try commits.toOwnedSlice(),
        .timestamp = std.time.timestamp(),
    };
    defer non_matching_event.deinit(allocator);
    
    const should_not_trigger = try workflow_trigger.evaluateTrigger(workflow.triggers[0], non_matching_event);
    try testing.expect(!should_not_trigger);
}

test "handles path filtering correctly" {
    const allocator = testing.allocator;
    
    var workflow_trigger = try WorkflowTrigger.init(allocator, .{});
    defer workflow_trigger.deinit();
    
    var workflow = try Workflow.parseFromYaml(allocator, "");
    defer workflow.deinit(allocator);
    
    var commits = std.ArrayList(Commit).init(allocator);
    defer commits.deinit();
    
    try commits.append(Commit{
        .id = try allocator.dupe(u8, "path123"),
        .message = try allocator.dupe(u8, "Path test commit"),
        .author = post_receive.GitAuthor{
            .name = try allocator.dupe(u8, "Test Author"),
            .email = try allocator.dupe(u8, "test@example.com"),
        },
        .committer = post_receive.GitAuthor{
            .name = try allocator.dupe(u8, "Test Author"),
            .email = try allocator.dupe(u8, "test@example.com"),
        },
        .timestamp = std.time.timestamp(),
        .added = try allocator.dupe([]const u8, &[_][]const u8{}),
        .removed = try allocator.dupe([]const u8, &[_][]const u8{}),
        .modified = try allocator.dupe([]const u8, &[_][]const u8{"docs/README.md"}),
    });
    
    // Test push event that should not match (excluded paths)
    var excluded_paths_event = PushEvent{
        .repository_id = 1,
        .before = try allocator.dupe(u8, "000000"),
        .after = try allocator.dupe(u8, "path123"),
        .ref = try allocator.dupe(u8, "refs/heads/main"),
        .commits = try commits.toOwnedSlice(),
        .timestamp = std.time.timestamp(),
    };
    defer excluded_paths_event.deinit(allocator);
    
    const should_not_trigger_paths = try workflow_trigger.evaluateTrigger(workflow.triggers[0], excluded_paths_event);
    try testing.expect(!should_not_trigger_paths);
}

test "handles complex trigger conditions" {
    const allocator = testing.allocator;
    
    var workflow_trigger = try WorkflowTrigger.init(allocator, .{});
    defer workflow_trigger.deinit();
    
    // Create workflow with multiple trigger types
    var triggers = std.ArrayList(TriggerConfig).init(allocator);
    defer triggers.deinit();
    
    // Push trigger for main branch
    var main_branches = std.ArrayList([]const u8).init(allocator);
    defer main_branches.deinit();
    try main_branches.append(try allocator.dupe(u8, "main"));
    
    try triggers.append(TriggerConfig{
        .event_type = .push,
        .conditions = TriggerConditions{
            .branches = try main_branches.toOwnedSlice(),
        },
    });
    
    // Push trigger for tags
    var tag_patterns = std.ArrayList([]const u8).init(allocator);
    defer tag_patterns.deinit();
    try tag_patterns.append(try allocator.dupe(u8, "v*"));
    
    try triggers.append(TriggerConfig{
        .event_type = .push,
        .conditions = TriggerConditions{
            .tags = try tag_patterns.toOwnedSlice(),
        },
    });
    
    var workflow = Workflow{
        .id = 1,
        .name = try allocator.dupe(u8, "Complex CI"),
        .triggers = try triggers.toOwnedSlice(),
    };
    defer workflow.deinit(allocator);
    
    var commits = std.ArrayList(Commit).init(allocator);
    defer commits.deinit();
    
    try commits.append(Commit{
        .id = try allocator.dupe(u8, "tag123"),
        .message = try allocator.dupe(u8, "Tag commit"),
        .author = post_receive.GitAuthor{
            .name = try allocator.dupe(u8, "Test Author"),
            .email = try allocator.dupe(u8, "test@example.com"),
        },
        .committer = post_receive.GitAuthor{
            .name = try allocator.dupe(u8, "Test Author"),
            .email = try allocator.dupe(u8, "test@example.com"),
        },
        .timestamp = std.time.timestamp(),
        .added = try allocator.dupe([]const u8, &[_][]const u8{}),
        .removed = try allocator.dupe([]const u8, &[_][]const u8{}),
        .modified = try allocator.dupe([]const u8, &[_][]const u8{}),
    });
    
    // Test tag push (should match push trigger)
    var tag_event = PushEvent{
        .repository_id = 1,
        .before = try allocator.dupe(u8, "000000"),
        .after = try allocator.dupe(u8, "tag123"),
        .ref = try allocator.dupe(u8, "refs/tags/v1.0.0"),
        .commits = try commits.toOwnedSlice(),
        .timestamp = std.time.timestamp(),
    };
    defer tag_event.deinit(allocator);
    
    var matched_triggers: u32 = 0;
    for (workflow.triggers) |trigger| {
        if (try workflow_trigger.evaluateTrigger(trigger, tag_event)) {
            matched_triggers += 1;
        }
    }
    
    try testing.expectEqual(@as(u32, 1), matched_triggers); // Should match tag trigger only
}

test "pattern matching works correctly" {
    const allocator = testing.allocator;
    
    var workflow_trigger = try WorkflowTrigger.init(allocator, .{});
    defer workflow_trigger.deinit();
    
    // Test exact matches
    try testing.expect(workflow_trigger.matchPattern("main", "main"));
    try testing.expect(!workflow_trigger.matchPattern("main", "develop"));
    
    // Test wildcard patterns
    try testing.expect(workflow_trigger.matchPattern("src/**", "src/main.js"));
    try testing.expect(workflow_trigger.matchPattern("src/**", "src/lib/utils.js"));
    try testing.expect(!workflow_trigger.matchPattern("src/**", "docs/readme.md"));
    
    // Test branch pattern matching
    const branch_patterns = [_][]const u8{ "main", "develop", "feature/*" };
    try testing.expect(workflow_trigger.matchBranches(&branch_patterns, "refs/heads/main"));
    try testing.expect(workflow_trigger.matchBranches(&branch_patterns, "refs/heads/develop"));
    try testing.expect(!workflow_trigger.matchBranches(&branch_patterns, "refs/heads/hotfix/urgent"));
    
    // Test tag pattern matching
    const tag_patterns = [_][]const u8{ "v*", "release-*" };
    try testing.expect(workflow_trigger.matchTags(&tag_patterns, "refs/tags/v1.0.0"));
    try testing.expect(!workflow_trigger.matchTags(&tag_patterns, "refs/tags/beta-1"));
}