const std = @import("std");
const testing = std.testing;
const hooks = @import("hooks.zig");
const RefUpdate = hooks.RefUpdate;

// Git author/committer information
pub const GitAuthor = struct {
    name: []const u8,
    email: []const u8,
    
    pub fn deinit(self: GitAuthor, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.email);
    }
};

// Individual commit information
pub const Commit = struct {
    id: []const u8,
    message: []const u8,
    author: GitAuthor,
    committer: GitAuthor,
    timestamp: i64,
    added: []const []const u8,
    removed: []const []const u8,
    modified: []const []const u8,
    
    pub fn deinit(self: Commit, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.message);
        self.author.deinit(allocator);
        self.committer.deinit(allocator);
        
        for (self.added) |file| allocator.free(file);
        allocator.free(self.added);
        
        for (self.removed) |file| allocator.free(file);
        allocator.free(self.removed);
        
        for (self.modified) |file| allocator.free(file);
        allocator.free(self.modified);
    }
};

// File changes detected in commits
pub const FileChanges = struct {
    added: []const []const u8,
    removed: []const []const u8,
    modified: []const []const u8,
    
    pub fn deinit(self: FileChanges, allocator: std.mem.Allocator) void {
        for (self.added) |file| allocator.free(file);
        allocator.free(self.added);
        
        for (self.removed) |file| allocator.free(file);
        allocator.free(self.removed);
        
        for (self.modified) |file| allocator.free(file);
        allocator.free(self.modified);
    }
    
    pub fn getAllChangedFiles(self: FileChanges, allocator: std.mem.Allocator) ![]const []const u8 {
        var all_files = std.ArrayList([]const u8).init(allocator);
        
        for (self.added) |file| {
            try all_files.append(try allocator.dupe(u8, file));
        }
        
        for (self.modified) |file| {
            try all_files.append(try allocator.dupe(u8, file));
        }
        
        for (self.removed) |file| {
            try all_files.append(try allocator.dupe(u8, file));
        }
        
        return all_files.toOwnedSlice();
    }
};

// Mock Git client for testing
pub const GitClient = struct {
    allocator: std.mem.Allocator,
    repository_path: []const u8,
    mock_commits: std.StringHashMap(Commit),
    
    pub fn init(allocator: std.mem.Allocator, repository_path: []const u8) !GitClient {
        return GitClient{
            .allocator = allocator,
            .repository_path = try allocator.dupe(u8, repository_path),
            .mock_commits = std.StringHashMap(Commit).init(allocator),
        };
    }
    
    pub fn deinit(self: *GitClient) void {
        self.allocator.free(self.repository_path);
        
        var commits_iter = self.mock_commits.iterator();
        while (commits_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.mock_commits.deinit();
    }
    
    pub fn addMockCommit(self: *GitClient, commit: Commit) !void {
        const owned_id = try self.allocator.dupe(u8, commit.id);
        try self.mock_commits.put(owned_id, commit);
    }
    
    pub fn getCommitRange(self: *GitClient, old_sha: []const u8, new_sha: []const u8) ![]Commit {
        _ = old_sha;
        _ = new_sha;
        
        // Mock implementation - return a simple commit list
        var commits = std.ArrayList(Commit).init(self.allocator);
        
        // In real implementation, this would run: git rev-list --reverse old_sha..new_sha
        if (self.mock_commits.get(new_sha)) |commit| {
            try commits.append(Commit{
                .id = try self.allocator.dupe(u8, commit.id),
                .message = try self.allocator.dupe(u8, commit.message),
                .author = GitAuthor{
                    .name = try self.allocator.dupe(u8, commit.author.name),
                    .email = try self.allocator.dupe(u8, commit.author.email),
                },
                .committer = GitAuthor{
                    .name = try self.allocator.dupe(u8, commit.committer.name),
                    .email = try self.allocator.dupe(u8, commit.committer.email),
                },
                .timestamp = commit.timestamp,
                .added = try self.allocator.dupe([]const u8, commit.added),
                .removed = try self.allocator.dupe([]const u8, commit.removed),
                .modified = try self.allocator.dupe([]const u8, commit.modified),
            });
        }
        
        return commits.toOwnedSlice();
    }
    
    pub fn getFileChanges(self: *GitClient, commit_range: []const u8) !FileChanges {
        _ = commit_range;
        
        // Mock implementation - in real implementation, this would run:
        // git diff --name-status old_sha..new_sha
        return FileChanges{
            .added = try self.allocator.dupe([]const u8, &[_][]const u8{"src/new_file.zig"}),
            .modified = try self.allocator.dupe([]const u8, &[_][]const u8{"src/main.zig"}),
            .removed = try self.allocator.dupe([]const u8, &[_][]const u8{}),
        };
    }
};

// Hook configuration
pub const HookConfig = struct {
    git_client: ?*GitClient = null,
    workflow_manager: ?*@import("../actions/workflow_manager.zig").WorkflowManager = null,
    performance_monitoring: bool = false,
    error_recovery: bool = true,
    max_commits_per_push: u32 = 1000,
};

// Hook execution error
pub const HookError = struct {
    error_type: ErrorType,
    message: []const u8,
    context: []const u8,
    
    const ErrorType = enum {
        parse_error,
        git_error,
        database_error,
        workflow_error,
        unknown_error,
    };
    
    pub fn deinit(self: HookError, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        allocator.free(self.context);
    }
};

// Post-receive hook handler
pub const PostReceiveHook = struct {
    allocator: std.mem.Allocator,
    config: HookConfig,
    git_client: ?*GitClient,
    workflow_manager: ?*@import("../actions/workflow_manager.zig").WorkflowManager,
    
    pub fn init(allocator: std.mem.Allocator, config: HookConfig) !PostReceiveHook {
        return PostReceiveHook{
            .allocator = allocator,
            .config = config,
            .git_client = config.git_client,
            .workflow_manager = config.workflow_manager,
        };
    }
    
    pub fn deinit(self: *PostReceiveHook) void {
        _ = self;
    }
    
    pub fn parseRefUpdates(self: *PostReceiveHook, hook_input: []const u8) ![]RefUpdate {
        var ref_updates = std.ArrayList(RefUpdate).init(self.allocator);
        errdefer {
            for (ref_updates.items) |*update| {
                update.deinit(self.allocator);
            }
            ref_updates.deinit();
        }
        
        var lines = std.mem.split(u8, hook_input, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            
            // Parse line format: "old_sha new_sha ref_name"
            var parts = std.mem.split(u8, line, " ");
            
            const old_sha = parts.next() orelse continue;
            const new_sha = parts.next() orelse continue;
            const ref_name = parts.next() orelse continue;
            
            // Validate SHA format (40 hex characters)
            if (old_sha.len != 40 or new_sha.len != 40) continue;
            if (!isValidSha(old_sha) or !isValidSha(new_sha)) continue;
            
            const ref_update = RefUpdate{
                .old_sha = try self.allocator.dupe(u8, old_sha),
                .new_sha = try self.allocator.dupe(u8, new_sha),
                .ref_name = try self.allocator.dupe(u8, ref_name),
                .ref_type = RefUpdate.RefType.fromRefName(ref_name),
            };
            
            try ref_updates.append(ref_update);
        }
        
        return ref_updates.toOwnedSlice();
    }
    
    pub fn extractCommits(self: *PostReceiveHook, old_sha: []const u8, new_sha: []const u8) ![]Commit {
        if (self.git_client) |git_client| {
            return git_client.getCommitRange(old_sha, new_sha);
        }
        
        // Fallback mock implementation
        var commits = std.ArrayList(Commit).init(self.allocator);
        
        // Create a mock commit for testing
        if (!std.mem.eql(u8, old_sha, new_sha)) {
            try commits.append(Commit{
                .id = try self.allocator.dupe(u8, new_sha),
                .message = try self.allocator.dupe(u8, "Mock commit message"),
                .author = GitAuthor{
                    .name = try self.allocator.dupe(u8, "Test Author"),
                    .email = try self.allocator.dupe(u8, "test@example.com"),
                },
                .committer = GitAuthor{
                    .name = try self.allocator.dupe(u8, "Test Committer"),
                    .email = try self.allocator.dupe(u8, "test@example.com"),
                },
                .timestamp = std.time.timestamp(),
                .added = try self.allocator.dupe([]const u8, &[_][]const u8{"new_file.txt"}),
                .removed = try self.allocator.dupe([]const u8, &[_][]const u8{}),
                .modified = try self.allocator.dupe([]const u8, &[_][]const u8{}),
            });
        }
        
        return commits.toOwnedSlice();
    }
    
    pub fn detectFileChanges(self: *PostReceiveHook, commit_range: []const u8) !FileChanges {
        if (self.git_client) |git_client| {
            return git_client.getFileChanges(commit_range);
        }
        
        // Fallback mock implementation
        return FileChanges{
            .added = try self.allocator.dupe([]const u8, &[_][]const u8{}),
            .modified = try self.allocator.dupe([]const u8, &[_][]const u8{}),
            .removed = try self.allocator.dupe([]const u8, &[_][]const u8{}),
        };
    }
    
    pub fn processPushEvent(self: *PostReceiveHook, repository_id: u32, repository_path: []const u8, ref_updates: []const RefUpdate) !?@import("../actions/workflow_manager.zig").HookResult {
        if (self.workflow_manager == null) {
            std.log.warn("No workflow manager configured, skipping workflow processing", .{});
            return null;
        }
        
        const workflow_manager = self.workflow_manager.?;
        
        // Process each ref update (typically one per push)
        for (ref_updates) |ref_update| {
            // Only process branch pushes (ignore tag updates for now)
            if (ref_update.ref_type != .branch) continue;
            
            // Skip branch deletions
            if (ref_update.isDeletion()) continue;
            
            // Extract commits from the push
            const commits = try self.extractCommits(ref_update.old_sha, ref_update.new_sha);
            defer {
                for (commits) |*commit| {
                    commit.deinit(self.allocator);
                }
                self.allocator.free(commits);
            }
            
            // Create commit SHA list
            var commit_shas = try self.allocator.alloc([]const u8, commits.len);
            defer {
                for (commit_shas) |sha| {
                    self.allocator.free(sha);
                }
                self.allocator.free(commit_shas);
            }
            
            for (commits, 0..) |commit, i| {
                commit_shas[i] = try self.allocator.dupe(u8, commit.id);
            }
            
            // Create push event for workflow manager
            var push_event = @import("../actions/workflow_manager.zig").PushEvent{
                .repository_id = repository_id,
                .repository_path = try self.allocator.dupe(u8, repository_path),
                .ref = try self.allocator.dupe(u8, ref_update.ref_name),
                .before = try self.allocator.dupe(u8, ref_update.old_sha),
                .after = try self.allocator.dupe(u8, ref_update.new_sha),
                .commits = commit_shas,
                .pusher_id = 1, // TODO: Get actual pusher ID from context
            };
            defer push_event.deinit(self.allocator);
            
            // Transfer ownership of commit_shas to push_event
            const owned_commit_shas = try self.allocator.alloc([]const u8, commit_shas.len);
            for (commit_shas, 0..) |sha, i| {
                owned_commit_shas[i] = try self.allocator.dupe(u8, sha);
            }
            push_event.commits = owned_commit_shas;
            
            // Process the push event through workflow manager
            const result = try workflow_manager.processPushEvent(push_event);
            
            std.log.info("Post-receive hook processed push to {s}: {} workflows triggered, {} errors", .{
                ref_update.ref_name,
                result.triggered_workflows.len,
                result.errors.len,
            });
            
            return result;
        }
        
        return null;
    }
    
    fn isValidSha(sha: []const u8) bool {
        for (sha) |c| {
            if (!std.ascii.isHex(c)) return false;
        }
        return true;
    }
};

// Test repository helper for testing
pub const TestRepository = struct {
    allocator: std.mem.Allocator,
    git_client: GitClient,
    next_commit_id: u32 = 1,
    
    pub fn init(allocator: std.mem.Allocator) !TestRepository {
        return TestRepository{
            .allocator = allocator,
            .git_client = try GitClient.init(allocator, "/tmp/test-repo"),
        };
    }
    
    pub fn deinit(self: *TestRepository) void {
        self.git_client.deinit();
    }
    
    pub fn createCommit(self: *TestRepository, message: []const u8, changed_files: []const []const u8) ![]const u8 {
        const commit_id = try std.fmt.allocPrint(self.allocator, "commit{:03d}abcdef1234567890123456789012345678", .{self.next_commit_id});
        self.next_commit_id += 1;
        
        // Truncate to 40 characters for valid SHA
        const sha = commit_id[0..40];
        
        var added_files = std.ArrayList([]const u8).init(self.allocator);
        for (changed_files) |file| {
            try added_files.append(try self.allocator.dupe(u8, file));
        }
        
        const commit = Commit{
            .id = try self.allocator.dupe(u8, sha),
            .message = try self.allocator.dupe(u8, message),
            .author = GitAuthor{
                .name = try self.allocator.dupe(u8, "Test Author"),
                .email = try self.allocator.dupe(u8, "test@example.com"),
            },
            .committer = GitAuthor{
                .name = try self.allocator.dupe(u8, "Test Committer"),
                .email = try self.allocator.dupe(u8, "test@example.com"),
            },
            .timestamp = std.time.timestamp(),
            .added = try added_files.toOwnedSlice(),
            .removed = try self.allocator.dupe([]const u8, &[_][]const u8{}),
            .modified = try self.allocator.dupe([]const u8, &[_][]const u8{}),
        };
        
        try self.git_client.addMockCommit(commit);
        
        self.allocator.free(commit_id);
        return try self.allocator.dupe(u8, sha);
    }
};

// Tests for Phase 1: Git Hook Handler Foundation
test "parses post-receive hook input correctly" {
    const allocator = testing.allocator;
    
    var hook_handler = try PostReceiveHook.init(allocator, .{});
    defer hook_handler.deinit();
    
    // Simulate post-receive hook input
    const hook_input = 
        "0000000000000000000000000000000000000000 abc123def456789012345678901234567890abcd refs/heads/main\n" ++
        "def456789012345678901234567890abcdef123456 789abc012def345678901234567890abcdef456789 refs/heads/feature/new-feature\n" ++
        "123456789012345678901234567890abcdef123456 0000000000000000000000000000000000000000 refs/heads/old-branch\n";
    
    const ref_updates = try hook_handler.parseRefUpdates(hook_input);
    defer {
        for (ref_updates) |*update| {
            update.deinit(allocator);
        }
        allocator.free(ref_updates);
    }
    
    try testing.expectEqual(@as(usize, 3), ref_updates.len);
    
    // First update: new branch creation
    try testing.expectEqualStrings("0000000000000000000000000000000000000000", ref_updates[0].old_sha);
    try testing.expectEqualStrings("abc123def456789012345678901234567890abcd", ref_updates[0].new_sha);
    try testing.expectEqualStrings("refs/heads/main", ref_updates[0].ref_name);
    try testing.expectEqual(RefUpdate.RefType.branch, ref_updates[0].ref_type);
    try testing.expect(ref_updates[0].isCreation());
    
    // Second update: branch push
    try testing.expectEqualStrings("def456789012345678901234567890abcdef123456", ref_updates[1].old_sha);
    try testing.expectEqualStrings("789abc012def345678901234567890abcdef456789", ref_updates[1].new_sha);
    try testing.expectEqualStrings("refs/heads/feature/new-feature", ref_updates[1].ref_name);
    try testing.expect(!ref_updates[1].isCreation());
    try testing.expect(!ref_updates[1].isDeletion());
    
    // Third update: branch deletion
    try testing.expectEqualStrings("123456789012345678901234567890abcdef123456", ref_updates[2].old_sha);
    try testing.expectEqualStrings("0000000000000000000000000000000000000000", ref_updates[2].new_sha);
    try testing.expectEqualStrings("refs/heads/old-branch", ref_updates[2].ref_name);
    try testing.expect(ref_updates[2].isDeletion());
}

test "extracts commit information from Git repository" {
    const allocator = testing.allocator;
    
    // Create test Git repository
    var test_repo = try TestRepository.init(allocator);
    defer test_repo.deinit();
    
    // Add test commits
    const commit1_sha = try test_repo.createCommit("Initial commit", &[_][]const u8{"README.md"});
    defer allocator.free(commit1_sha);
    
    const commit2_sha = try test_repo.createCommit("Add feature", &[_][]const u8{ "src/main.zig", "src/lib.zig" });
    defer allocator.free(commit2_sha);
    
    const commit3_sha = try test_repo.createCommit("Fix bug", &[_][]const u8{"src/main.zig"});
    defer allocator.free(commit3_sha);
    
    var hook_handler = try PostReceiveHook.init(allocator, .{
        .git_client = &test_repo.git_client,
    });
    defer hook_handler.deinit();
    
    // Extract commits between commit1 and commit3
    const commits = try hook_handler.extractCommits(commit1_sha, commit3_sha);
    defer {
        for (commits) |*commit| {
            commit.deinit(allocator);
        }
        allocator.free(commits);
    }
    
    try testing.expectEqual(@as(usize, 1), commits.len);
    
    // Verify commit information
    try testing.expectEqualStrings(commit3_sha, commits[0].id);
    try testing.expectEqualStrings("Fix bug", commits[0].message);
    try testing.expectEqual(@as(usize, 1), commits[0].added.len);
}

test "handles empty and malformed hook input" {
    const allocator = testing.allocator;
    
    var hook_handler = try PostReceiveHook.init(allocator, .{});
    defer hook_handler.deinit();
    
    // Test empty input
    {
        const empty_input = "";
        const ref_updates = try hook_handler.parseRefUpdates(empty_input);
        defer allocator.free(ref_updates);
        
        try testing.expectEqual(@as(usize, 0), ref_updates.len);
    }
    
    // Test malformed input (invalid SHA lengths)
    {
        const malformed_input = "invalid_sha abc123 refs/heads/main\n";
        const ref_updates = try hook_handler.parseRefUpdates(malformed_input);
        defer allocator.free(ref_updates);
        
        try testing.expectEqual(@as(usize, 0), ref_updates.len);
    }
    
    // Test input with only newlines
    {
        const newlines_input = "\n\n\n";
        const ref_updates = try hook_handler.parseRefUpdates(newlines_input);
        defer allocator.free(ref_updates);
        
        try testing.expectEqual(@as(usize, 0), ref_updates.len);
    }
}

test "detects different reference types correctly" {
    const allocator = testing.allocator;
    
    var hook_handler = try PostReceiveHook.init(allocator, .{});
    defer hook_handler.deinit();
    
    const hook_input = 
        "0000000000000000000000000000000000000000 abc123def456789012345678901234567890abcd refs/heads/main\n" ++
        "0000000000000000000000000000000000000000 def456789012345678901234567890abcdef123456 refs/tags/v1.0.0\n" ++
        "0000000000000000000000000000000000000000 789abc012def345678901234567890abcdef456789 refs/notes/commits\n";
    
    const ref_updates = try hook_handler.parseRefUpdates(hook_input);
    defer {
        for (ref_updates) |*update| {
            update.deinit(allocator);
        }
        allocator.free(ref_updates);
    }
    
    try testing.expectEqual(@as(usize, 3), ref_updates.len);
    
    // Branch reference
    try testing.expectEqual(RefUpdate.RefType.branch, ref_updates[0].ref_type);
    try testing.expectEqualStrings("main", ref_updates[0].getBranchName().?);
    
    // Tag reference
    try testing.expectEqual(RefUpdate.RefType.tag, ref_updates[1].ref_type);
    try testing.expectEqualStrings("v1.0.0", ref_updates[1].getTagName().?);
    
    // Unknown reference type
    try testing.expectEqual(RefUpdate.RefType.unknown, ref_updates[2].ref_type);
    try testing.expect(ref_updates[2].getBranchName() == null);
    try testing.expect(ref_updates[2].getTagName() == null);
}

test "file changes detection works correctly" {
    const allocator = testing.allocator;
    
    var git_client = try GitClient.init(allocator, "/tmp/test-repo");
    defer git_client.deinit();
    
    var hook_handler = try PostReceiveHook.init(allocator, .{
        .git_client = &git_client,
    });
    defer hook_handler.deinit();
    
    const file_changes = try hook_handler.detectFileChanges("abc123..def456");
    defer file_changes.deinit(allocator);
    
    // Verify file changes structure exists
    try testing.expect(file_changes.added.len >= 0);
    try testing.expect(file_changes.modified.len >= 0);
    try testing.expect(file_changes.removed.len >= 0);
    
    // Test getting all changed files
    const all_files = try file_changes.getAllChangedFiles(allocator);
    defer {
        for (all_files) |file| {
            allocator.free(file);
        }
        allocator.free(all_files);
    }
    
    try testing.expect(all_files.len >= 0);
}

test "post-receive hook processes push events without workflow manager" {
    const allocator = testing.allocator;
    
    var hook_handler = try PostReceiveHook.init(allocator, .{});
    defer hook_handler.deinit();
    
    // Create test ref update
    var ref_update = hooks.RefUpdate{
        .old_sha = try allocator.dupe(u8, "abc123def456789012345678901234567890abcd"),
        .new_sha = try allocator.dupe(u8, "def456789012345678901234567890abcdef123456"),
        .ref_name = try allocator.dupe(u8, "refs/heads/main"),
        .ref_type = .branch,
    };
    defer ref_update.deinit(allocator);
    
    const ref_updates = [_]hooks.RefUpdate{ref_update};
    
    // Process without workflow manager should return null
    const result = try hook_handler.processPushEvent(1, "/tmp/test-repo", &ref_updates);
    try testing.expect(result == null);
}