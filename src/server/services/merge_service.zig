const std = @import("std");
const DataAccessObject = @import("../../database/dao.zig");

pub const MergeError = error{
    BranchProtected,
    InsufficientReviews,
    RequiredStatusChecksPending,
    RequiredStatusChecksFailed,
    MergeConflicts,
    PullRequestClosed,
    DatabaseError,
    OutOfMemory,
};

pub const Mergeability = struct {
    can_merge: bool,
    blocking_issues: [][]const u8,
    
    pub fn deinit(self: *Mergeability, allocator: std.mem.Allocator) void {
        for (self.blocking_issues) |issue| {
            allocator.free(issue);
        }
        allocator.free(self.blocking_issues);
    }
};

pub const MergeService = struct {
    dao: *DataAccessObject,
    
    pub fn init(dao: *DataAccessObject) MergeService {
        return MergeService{
            .dao = dao,
        };
    }
    
    /// Check if a pull request can be merged based on protection rules
    pub fn checkMergeability(self: *MergeService, allocator: std.mem.Allocator, repo_id: i64, pull_request_id: i64, base_branch: []const u8) !Mergeability {
        var blocking_issues = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (blocking_issues.items) |issue| {
                allocator.free(issue);
            }
            blocking_issues.deinit();
        }
        
        // Get pull request details
        const pull_request = try self.dao.getIssue(allocator, repo_id, pull_request_id) orelse {
            try blocking_issues.append(try allocator.dupe(u8, "Pull request not found"));
            return Mergeability{
                .can_merge = false,
                .blocking_issues = try blocking_issues.toOwnedSlice(),
            };
        };
        defer {
            allocator.free(pull_request.title);
            if (pull_request.content) |c| allocator.free(c);
        }
        
        // Check if PR is closed
        if (pull_request.is_closed) {
            try blocking_issues.append(try allocator.dupe(u8, "Pull request is already closed"));
        }
        
        // Check branch protection rules
        if (try self.dao.getBranchProtectionRule(allocator, repo_id, base_branch)) |protection_rule| {
            defer {
                allocator.free(protection_rule.branch_name);
                if (protection_rule.required_status_checks) |checks| allocator.free(checks);
            }
            
            // Check review requirements
            if (protection_rule.require_reviews) {
                const reviews = try self.dao.getReviews(allocator, pull_request.id);
                defer {
                    for (reviews) |review| {
                        if (review.commit_id) |c| allocator.free(c);
                    }
                    allocator.free(reviews);
                }
                
                var approval_count: i32 = 0;
                for (reviews) |review| {
                    if (review.type == .approve) {
                        approval_count += 1;
                    }
                }
                
                if (approval_count < protection_rule.required_review_count) {
                    const msg = try std.fmt.allocPrint(allocator, "Insufficient reviews: {} required, {} received", .{ protection_rule.required_review_count, approval_count });
                    try blocking_issues.append(msg);
                }
            }
            
            // Check required status checks
            if (protection_rule.require_status_checks) {
                const status_checks = try self.dao.getStatusChecks(allocator, repo_id, pull_request.id);
                defer {
                    for (status_checks) |check| {
                        allocator.free(check.context);
                        if (check.target_url) |url| allocator.free(url);
                        if (check.description) |desc| allocator.free(desc);
                    }
                    allocator.free(status_checks);
                }
                
                if (protection_rule.required_status_checks) |required_checks_json| {
                    // Parse required checks from JSON array
                    var parsed = std.json.parseFromSlice([][]const u8, allocator, required_checks_json, .{}) catch {
                        try blocking_issues.append(try allocator.dupe(u8, "Invalid required status checks configuration"));
                        return Mergeability{
                            .can_merge = false,
                            .blocking_issues = try blocking_issues.toOwnedSlice(),
                        };
                    };
                    defer parsed.deinit();
                    
                    for (parsed.value) |required_check| {
                        var found = false;
                        var is_successful = false;
                        
                        for (status_checks) |check| {
                            if (std.mem.eql(u8, check.context, required_check)) {
                                found = true;
                                if (check.state == .success) {
                                    is_successful = true;
                                }
                                break;
                            }
                        }
                        
                        if (!found) {
                            const msg = try std.fmt.allocPrint(allocator, "Required status check missing: {s}", .{required_check});
                            try blocking_issues.append(msg);
                        } else if (!is_successful) {
                            const msg = try std.fmt.allocPrint(allocator, "Required status check failed: {s}", .{required_check});
                            try blocking_issues.append(msg);
                        }
                    }
                }
            }
        }
        
        // Check for merge conflicts
        if (try self.dao.getMergeConflictStatus(allocator, repo_id, pull_request.id)) |conflict_status| {
            defer {
                allocator.free(conflict_status.base_sha);
                allocator.free(conflict_status.head_sha);
                allocator.free(conflict_status.conflicted_files);
            }
            
            if (conflict_status.conflict_detected) {
                try blocking_issues.append(try allocator.dupe(u8, "Pull request has merge conflicts that must be resolved"));
            }
        }
        
        return Mergeability{
            .can_merge = blocking_issues.items.len == 0,
            .blocking_issues = try blocking_issues.toOwnedSlice(),
        };
    }
    
    /// Simulate merge conflict detection (in a real implementation, this would use Git)
    pub fn detectMergeConflicts(self: *MergeService, allocator: std.mem.Allocator, repo_id: i64, pull_request_id: i64, base_sha: []const u8, head_sha: []const u8) !void {
        // In a real implementation, this would:
        // 1. Clone the repository
        // 2. Attempt to merge base_sha and head_sha
        // 3. Detect conflicted files
        // 4. Store the result
        
        // For now, we'll simulate by checking if the SHAs are different
        const has_conflicts = !std.mem.eql(u8, base_sha, head_sha) and 
                             (std.mem.indexOf(u8, base_sha, "conflict") != null or 
                              std.mem.indexOf(u8, head_sha, "conflict") != null);
        
        const conflicted_files = if (has_conflicts) "[\"src/main.zig\", \"README.md\"]" else "[]";
        
        const conflict_status = DataAccessObject.MergeConflict{
            .id = 0, // Will be assigned by database
            .repo_id = repo_id,
            .pull_request_id = pull_request_id,
            .base_sha = base_sha,
            .head_sha = head_sha,
            .conflicted_files = conflicted_files,
            .conflict_detected = has_conflicts,
            .last_checked_unix = std.time.timestamp(),
        };
        
        try self.dao.updateMergeConflictStatus(allocator, conflict_status);
    }
    
    /// Create or update a status check
    pub fn updateStatusCheck(self: *MergeService, allocator: std.mem.Allocator, repo_id: i64, pull_request_id: i64, context: []const u8, state: DataAccessObject.StatusState, target_url: ?[]const u8, description: ?[]const u8) !void {
        const status_check = DataAccessObject.StatusCheck{
            .id = 0, // Will be assigned by database
            .repo_id = repo_id,
            .pull_request_id = pull_request_id,
            .context = context,
            .state = state,
            .target_url = target_url,
            .description = description,
            .created_unix = std.time.timestamp(),
            .updated_unix = std.time.timestamp(),
        };
        
        _ = try self.dao.createStatusCheck(allocator, status_check);
    }
};

// Tests for merge service following TDD
test "MergeService basic initialization" {
    // Mock DAO - in real tests this would be a proper DAO instance
    var mock_dao = DataAccessObject{
        .pool = undefined, // This would be a real pool in actual tests
    };
    
    const merge_service = MergeService.init(&mock_dao);
    try std.testing.expect(merge_service.dao == &mock_dao);
}

test "MergeService merge conflict simulation" {
    // Test the conflict detection logic
    const base_sha = "abc123def456";
    const head_sha = "conflict789ghi";
    
    // Should detect conflict due to "conflict" in head_sha
    const has_conflicts = !std.mem.eql(u8, base_sha, head_sha) and 
                         (std.mem.indexOf(u8, base_sha, "conflict") != null or 
                          std.mem.indexOf(u8, head_sha, "conflict") != null);
    
    try std.testing.expectEqual(true, has_conflicts);
    
    // Test no conflict case
    const clean_base = "abc123def456";
    const clean_head = "def456ghi789";
    
    const no_conflicts = !std.mem.eql(u8, clean_base, clean_head) and 
                        (std.mem.indexOf(u8, clean_base, "conflict") != null or 
                         std.mem.indexOf(u8, clean_head, "conflict") != null);
    
    try std.testing.expectEqual(false, no_conflicts);
}

test "Mergeability blocking issues management" {
    const allocator = std.testing.allocator;
    
    var blocking_issues = std.ArrayList([]const u8).init(allocator);
    defer {
        for (blocking_issues.items) |issue| {
            allocator.free(issue);
        }
        blocking_issues.deinit();
    }
    
    try blocking_issues.append(try allocator.dupe(u8, "Insufficient reviews"));
    try blocking_issues.append(try allocator.dupe(u8, "Status checks failed"));
    
    var mergeability = Mergeability{
        .can_merge = false,
        .blocking_issues = try blocking_issues.toOwnedSlice(),
    };
    defer mergeability.deinit(allocator);
    
    try std.testing.expectEqual(false, mergeability.can_merge);
    try std.testing.expectEqual(@as(usize, 2), mergeability.blocking_issues.len);
    try std.testing.expectEqualStrings("Insufficient reviews", mergeability.blocking_issues[0]);
    try std.testing.expectEqualStrings("Status checks failed", mergeability.blocking_issues[1]);
}