const std = @import("std");

/// Risk level for approval requests
pub const RiskLevel = enum {
    low, // Read-only operations
    medium, // Local modifications
    high, // System changes, network access
    critical, // Destructive operations

    pub fn toString(self: RiskLevel) []const u8 {
        return switch (self) {
            .low => "Low Risk",
            .medium => "Medium Risk",
            .high => "High Risk",
            .critical => "CRITICAL",
        };
    }
};

/// Type of approval request
pub const ApprovalType = enum {
    command_execution,
    file_write,
    file_delete,
    batch,
};

/// File operation type
pub const FileOperation = enum {
    create,
    modify,
    delete,
};

/// Command details for approval
pub const CommandDetails = struct {
    command: []const u8,
    working_dir: ?[]const u8 = null,
    risk_level: RiskLevel = .medium,
};

/// File change details for approval
pub const FileChangeDetails = struct {
    path: []const u8,
    operation: FileOperation,
    diff: ?[]const u8 = null,
};

/// Approval request that requires user decision
pub const ApprovalRequest = struct {
    id: []const u8,
    request_type: ApprovalType,
    description: []const u8,
    timestamp: i64,

    // Payload - only one is set based on request_type
    command: ?CommandDetails = null,
    file_change: ?FileChangeDetails = null,
};

/// User's decision on an approval request
pub const Decision = enum {
    approve,
    decline,
    modify,
};

/// Scope of the approval
pub const Scope = enum {
    once, // This instance only
    session, // All similar in this session
    always, // Remember for future
};

/// Response to an approval request
pub const ApprovalResponse = struct {
    request_id: []const u8,
    decision: Decision,
    scope: Scope = .once,
    modified_command: ?[]const u8 = null,
};

/// Manages pending approval requests
pub const ApprovalManager = struct {
    allocator: std.mem.Allocator,
    pending_requests: std.ArrayList(ApprovalRequest),
    session_approvals: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) ApprovalManager {
        return .{
            .allocator = allocator,
            .pending_requests = std.ArrayList(ApprovalRequest){},
            .session_approvals = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *ApprovalManager) void {
        self.pending_requests.deinit(self.allocator);
        self.session_approvals.deinit();
    }

    /// Add a new approval request
    pub fn addRequest(self: *ApprovalManager, request: ApprovalRequest) !void {
        // Check if already approved for session
        if (self.session_approvals.contains(request.id)) {
            return; // Auto-approve
        }
        try self.pending_requests.append(self.allocator, request);
    }

    /// Get the current pending request (if any)
    pub fn getCurrentRequest(self: *ApprovalManager) ?*ApprovalRequest {
        if (self.pending_requests.items.len > 0) {
            return &self.pending_requests.items[0];
        }
        return null;
    }

    /// Respond to an approval request
    pub fn respond(self: *ApprovalManager, response: ApprovalResponse) !void {
        // Find and remove request
        for (self.pending_requests.items, 0..) |req, i| {
            if (std.mem.eql(u8, req.id, response.request_id)) {
                _ = self.pending_requests.orderedRemove(i);

                // Handle session approval
                if (response.decision == .approve and response.scope == .session) {
                    try self.session_approvals.put(response.request_id, {});
                }
                break;
            }
        }
    }

    /// Check if there are pending approval requests
    pub fn hasPending(self: *ApprovalManager) bool {
        return self.pending_requests.items.len > 0;
    }

    /// Get number of pending requests
    pub fn pendingCount(self: *ApprovalManager) usize {
        return self.pending_requests.items.len;
    }

    /// Clear all pending requests
    pub fn clearAll(self: *ApprovalManager) void {
        self.pending_requests.clearRetainingCapacity();
    }
};
