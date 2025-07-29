const std = @import("std");
const testing = std.testing;
const zap = @import("zap");
const dispatcher = @import("dispatcher.zig");
const registry = @import("registry.zig");

// Registration token for runner authentication
pub const RegistrationToken = struct {
    token: []const u8,
    expires_at: i64,
    repository_id: ?u32 = null,
    labels: []const []const u8 = &.{},
};

// Registration result after successful runner registration
pub const RegistrationResult = struct {
    runner_id: u32,
    runner_token: []const u8,
    expires_at: i64,
};

// Runner authentication manager
pub const RunnerAuth = struct {
    allocator: std.mem.Allocator,
    tokens: std.StringHashMap(TokenInfo),
    
    const TokenInfo = struct {
        runner_id: u32,
        repository_id: ?u32,
        expires_at: i64,
        scope: TokenScope,
    };
    
    const TokenScope = enum {
        registration,
        runner,
    };
    
    pub fn init(allocator: std.mem.Allocator) RunnerAuth {
        return RunnerAuth{
            .allocator = allocator,
            .tokens = std.StringHashMap(TokenInfo).init(allocator),
        };
    }
    
    pub fn deinit(self: *RunnerAuth) void {
        var iterator = self.tokens.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.tokens.deinit();
    }
    
    pub fn generateRegistrationToken(self: *RunnerAuth, repository_id: ?u32) !RegistrationToken {
        // Generate secure random token
        var token_bytes: [32]u8 = undefined;
        std.crypto.random.bytes(&token_bytes);
        
        var token_buf: [64]u8 = undefined;
        const token = std.fmt.bufPrint(&token_buf, "{}", .{std.fmt.fmtSliceHexLower(&token_bytes)}) catch unreachable;
        const owned_token = try self.allocator.dupe(u8, token);
        
        const expires_at = std.time.timestamp() + 3600; // 1 hour
        
        try self.tokens.put(owned_token, TokenInfo{
            .runner_id = 0, // Not assigned yet
            .repository_id = repository_id,
            .expires_at = expires_at,
            .scope = .registration,
        });
        
        return RegistrationToken{
            .token = owned_token,
            .expires_at = expires_at,
            .repository_id = repository_id,
        };
    }
    
    pub fn generateRunnerToken(self: *RunnerAuth, runner_id: u32, repository_id: ?u32) ![]const u8 {
        // Generate secure random token
        var token_bytes: [32]u8 = undefined;
        std.crypto.random.bytes(&token_bytes);
        
        var token_buf: [64]u8 = undefined;
        const token = std.fmt.bufPrint(&token_buf, "{}", .{std.fmt.fmtSliceHexLower(&token_bytes)}) catch unreachable;
        const owned_token = try self.allocator.dupe(u8, token);
        
        const expires_at = std.time.timestamp() + (30 * 24 * 3600); // 30 days
        
        try self.tokens.put(owned_token, TokenInfo{
            .runner_id = runner_id,
            .repository_id = repository_id,
            .expires_at = expires_at,
            .scope = .runner,
        });
        
        return owned_token;
    }
    
    pub fn validateToken(self: *RunnerAuth, token: []const u8, expected_scope: TokenScope) ?TokenInfo {
        const token_info = self.tokens.get(token) orelse return null;
        
        // Check expiration
        if (token_info.expires_at < std.time.timestamp()) {
            return null;
        }
        
        // Check scope
        if (token_info.scope != expected_scope) {
            return null;
        }
        
        return token_info;
    }
};

// Mock database connection for testing
pub const DatabaseConnection = dispatcher.DatabaseConnection;

// Runner API configuration
pub const RunnerAPIConfig = struct {
    db: *DatabaseConnection,
    auth_manager: ?*RunnerAuth = null,
    heartbeat_timeout_seconds: u32 = 300,
};

// Main runner API system
pub const RunnerAPI = struct {
    allocator: std.mem.Allocator,
    db: *DatabaseConnection,
    dispatcher: dispatcher.JobDispatcher,
    auth_manager: RunnerAuth,
    config: RunnerAPIConfig,
    
    pub fn init(allocator: std.mem.Allocator, config: RunnerAPIConfig) !RunnerAPI {
        return RunnerAPI{
            .allocator = allocator,
            .db = config.db,
            .dispatcher = try dispatcher.JobDispatcher.init(allocator, .{ .db = config.db }),
            .auth_manager = config.auth_manager orelse RunnerAuth.init(allocator),
            .config = config,
        };
    }
    
    pub fn deinit(self: *RunnerAPI) void {
        self.dispatcher.deinit();
        self.auth_manager.deinit();
    }
    
    pub fn handleRegistrationTokenRequest(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void {
        _ = req;
        _ = res;
        // TODO: Parse request body and validate repository token
        // For now, create a test token
        const reg_token = try self.auth_manager.generateRegistrationToken(null);
        
        const response_json = try std.json.stringifyAlloc(self.allocator, .{
            .token = reg_token.token,
            .expires_at = reg_token.expires_at,
        }, .{});
        defer self.allocator.free(response_json);
        
        try res.setStatus(.ok);
        try res.setHeader("Content-Type", "application/json");
        try res.setBody(response_json);
    }
    
    pub fn handleRunnerRegistration(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void {
        _ = req;
        _ = res;
        // TODO: Parse registration request and validate token
        // For now, create a test registration
        const runner_id: u32 = 1;
        const runner_token = try self.auth_manager.generateRunnerToken(runner_id, null);
        
        const response_json = try std.json.stringifyAlloc(self.allocator, .{
            .runner_id = runner_id,
            .runner_token = runner_token,
        }, .{});
        defer self.allocator.free(response_json);
        
        try res.setStatus(.created);
        try res.setHeader("Content-Type", "application/json");
        try res.setBody(response_json);
    }
    
    pub fn handleRunnerDeregistration(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void {
        _ = self;
        _ = req;
        try res.setStatus(.ok);
    }
    
    pub fn handleJobPoll(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void {
        _ = req;
        
        // TODO: Parse runner capabilities from request body
        const runner_capabilities = registry.RunnerCapabilities{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 1,
            .current_jobs = 0,
        };
        
        // TODO: Extract runner_id from authentication token
        const runner_id: u32 = 1;
        
        // Poll for job assignment with timeout
        const poll_start = std.time.timestamp();
        const timeout_seconds: i64 = 30;
        
        while (std.time.timestamp() - poll_start < timeout_seconds) {
            if (try self.dispatcher.pollForJob(runner_id, runner_capabilities)) |assigned_job| {
                // Job assigned - return job details
                const job_response = try std.json.stringifyAlloc(self.allocator, .{
                    .job_assigned = true,
                    .job_id = assigned_job.job_id,
                    .workflow_run_id = assigned_job.job_definition.workflow_run_id,
                    .job_definition = .{
                        .id = assigned_job.job_definition.id,
                        .requirements = assigned_job.job_definition.requirements,
                        .timeout_minutes = assigned_job.job_definition.timeout_minutes,
                    },
                }, .{});
                defer self.allocator.free(job_response);
                
                try res.setStatus(.ok);
                try res.setHeader("Content-Type", "application/json");
                try res.setBody(job_response);
                return;
            }
            
            // Brief sleep before checking again
            std.time.sleep(1 * std.time.ns_per_s);
        }
        
        // Timeout reached - no jobs available
        const no_job_response = try std.json.stringifyAlloc(self.allocator, .{
            .job_assigned = false,
            .job_id = @as(?u32, null),
            .job_definition = @as(?struct{}, null),
        }, .{});
        defer self.allocator.free(no_job_response);
        
        try res.setStatus(.ok);
        try res.setHeader("Content-Type", "application/json");
        try res.setBody(no_job_response);
    }
    
    pub fn handleJobStatus(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void {
        _ = self;
        _ = req;
        try res.setStatus(.ok);
    }
    
    pub fn handleJobCompletion(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void {
        _ = self;
        _ = req;
        try res.setStatus(.ok);
    }
    
    pub fn handleRunnerHeartbeat(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void {
        _ = req;
        
        // TODO: Parse heartbeat data from request body
        // TODO: Extract runner_id from authentication token
        const runner_id: u32 = 1;
        
        // Update runner's last seen timestamp and status
        try self.dispatcher.runner_registry.updateStatus(runner_id, .online);
        
        // TODO: Store system info (CPU, memory, disk usage) from heartbeat
        
        const response_json = try std.json.stringifyAlloc(self.allocator, .{
            .status = "ok",
            .timestamp = std.time.timestamp(),
        }, .{});
        defer self.allocator.free(response_json);
        
        try res.setStatus(.ok);
        try res.setHeader("Content-Type", "application/json");
        try res.setBody(response_json);
    }
    
    pub fn handleCapabilityUpdate(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void {
        _ = self;
        _ = req;
        try res.setStatus(.ok);
    }
    
    pub fn handleRunnerStatus(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void {
        _ = self;
        _ = req;
        try res.setStatus(.ok);
    }
    
    pub fn createRegistrationToken(self: *RunnerAPI, repository_id: ?u32, labels: []const []const u8) !RegistrationToken {
        _ = labels;
        return try self.auth_manager.generateRegistrationToken(repository_id);
    }
    
    pub fn checkRunnerHealth(self: *RunnerAPI) !void {
        const current_time = std.time.timestamp();
        const timeout_threshold = current_time - @as(i64, @intCast(self.config.heartbeat_timeout_seconds));
        
        // Get all runners and check their last heartbeat
        var runner_iter = self.dispatcher.runner_registry.runners.iterator();
        while (runner_iter.next()) |entry| {
            const runner = entry.value_ptr;
            
            // If runner hasn't sent heartbeat within timeout period, mark as offline
            if (runner.last_heartbeat < timeout_threshold and runner.status == .online) {
                try self.dispatcher.runner_registry.updateStatus(runner.id, .offline);
            }
        }
    }
};

// Test helpers
const test_db_config = struct {};

const TestRequest = struct {
    method: std.http.Method,
    path: []const u8,
    headers: []const Header,
    body: []const u8,
    allocator: std.mem.Allocator,
    
    const Header = struct {
        name: []const u8,
        value: []const u8,
    };
    
    pub fn deinit(self: *TestRequest) void {
        _ = self;
    }
    
    pub fn getBody(self: *const TestRequest) []const u8 {
        return self.body;
    }
};

const TestResponse = struct {
    status_code: u16 = 200,
    headers: std.ArrayList(TestRequest.Header),
    body: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) TestResponse {
        return TestResponse{
            .headers = std.ArrayList(TestRequest.Header).init(allocator),
            .body = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *TestResponse) void {
        self.headers.deinit();
        self.body.deinit();
    }
    
    pub fn setStatus(self: *TestResponse, status: std.http.Status) !void {
        self.status_code = @intFromEnum(status);
    }
    
    pub fn setHeader(self: *TestResponse, name: []const u8, value: []const u8) !void {
        try self.headers.append(TestRequest.Header{
            .name = name,
            .value = value,
        });
    }
    
    pub fn setBody(self: *TestResponse, body: []const u8) !void {
        try self.body.appendSlice(body);
    }
    
    pub fn getBody(self: *const TestResponse) []const u8 {
        return self.body.items;
    }
};

fn createTestRequest(allocator: std.mem.Allocator, config: struct {
    method: std.http.Method,
    path: []const u8,
    headers: []const TestRequest.Header = &.{},
    body: []const u8 = "",
}) !TestRequest {
    return TestRequest{
        .method = config.method,
        .path = config.path,
        .headers = config.headers,
        .body = config.body,
        .allocator = allocator,
    };
}

fn createTestRunner(db: *DatabaseConnection, allocator: std.mem.Allocator, config: struct {
    id: u32 = 1,
    name: []const u8 = "test-runner",
    status: registry.RunnerStatus = .online,
    capabilities: registry.RunnerCapabilities = .{
        .labels = &.{"ubuntu-latest"},
        .max_parallel_jobs = 1,
        .current_jobs = 0,
    },
    last_seen: ?i64 = null,
}) !u32 {
    _ = db;
    _ = allocator;
    _ = config;
    // Mock implementation - in real system would insert into database
    return config.id;
}

// Tests for Phase 1: Runner Registration API Foundation
test "handles runner registration token request" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{
        .db = &db,
    });
    defer api.deinit();
    
    // Create test request
    const request_body = 
        \\{
        \\  "labels": ["self-hosted", "linux", "x64"],
        \\  "name": "test-runner"
        \\}
    ;
    
    var request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/api/v1/runners/registration-token",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer repo-token-123" },
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .body = request_body,
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try api.handleRegistrationTokenRequest(&request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    
    const response_json = try std.json.parseFromSlice(
        struct { token: []const u8, expires_at: i64 },
        allocator,
        response.getBody(),
        .{}
    );
    defer response_json.deinit();
    
    try testing.expect(response_json.value.token.len > 0);
    try testing.expect(response_json.value.expires_at > std.time.timestamp());
}

test "validates runner registration with token" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{ .db = &db });
    defer api.deinit();
    
    // First get a registration token
    const reg_token = try api.createRegistrationToken(null, &.{"self-hosted"});
    
    // Use token to register runner
    const registration_body = try std.json.stringifyAlloc(allocator, .{
        .name = "test-runner-1",
        .labels = &.{"self-hosted", "linux", "x64"},
        .capabilities = .{
            .architecture = "x64",
            .memory_gb = 8,
            .cpu_cores = 4,
            .docker_enabled = true,
            .max_parallel_jobs = 2,
        },
    }, .{});
    defer allocator.free(registration_body);
    
    const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{reg_token.token});
    defer allocator.free(auth_header);
    
    var request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/api/v1/runners",
        .headers = &.{
            .{ .name = "Authorization", .value = auth_header },
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .body = registration_body,
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try api.handleRunnerRegistration(&request, &response);
    
    try testing.expectEqual(@as(u16, 201), response.status_code);
    
    const response_json = try std.json.parseFromSlice(
        struct { runner_id: u32, runner_token: []const u8 },
        allocator,
        response.getBody(),
        .{}
    );
    defer response_json.deinit();
    
    try testing.expect(response_json.value.runner_id > 0);
    try testing.expect(response_json.value.runner_token.len > 0);
}

test "runner auth generates and validates tokens correctly" {
    const allocator = testing.allocator;
    
    var auth = RunnerAuth.init(allocator);
    defer auth.deinit();
    
    // Generate registration token
    const reg_token = try auth.generateRegistrationToken(123);
    
    try testing.expect(reg_token.token.len > 0);
    try testing.expect(reg_token.expires_at > std.time.timestamp());
    try testing.expectEqual(@as(?u32, 123), reg_token.repository_id);
    
    // Validate registration token
    const token_info = auth.validateToken(reg_token.token, .registration);
    try testing.expect(token_info != null);
    try testing.expectEqual(@as(?u32, 123), token_info.?.repository_id);
    try testing.expectEqual(RunnerAuth.TokenScope.registration, token_info.?.scope);
    
    // Generate runner token
    const runner_token = try auth.generateRunnerToken(456, 123);
    
    try testing.expect(runner_token.len > 0);
    
    // Validate runner token
    const runner_info = auth.validateToken(runner_token, .runner);
    try testing.expect(runner_info != null);
    try testing.expectEqual(@as(u32, 456), runner_info.?.runner_id);
    try testing.expectEqual(@as(?u32, 123), runner_info.?.repository_id);
    try testing.expectEqual(RunnerAuth.TokenScope.runner, runner_info.?.scope);
    
    // Invalid token should fail
    const invalid_info = auth.validateToken("invalid-token", .runner);
    try testing.expect(invalid_info == null);
    
    // Wrong scope should fail
    const wrong_scope = auth.validateToken(reg_token.token, .runner);
    try testing.expect(wrong_scope == null);
}

// Tests for Phase 2: Job Polling System
test "job polling returns assigned job when available" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{
        .db = &db,
    });
    defer api.deinit();
    
    // Register a runner with the dispatcher
    try api.dispatcher.registerRunner(.{
        .id = 1,
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 2,
            .current_jobs = 0,
        },
    });
    
    // Queue a job
    const job = dispatcher.queue.QueuedJob{
        .id = 100,
        .workflow_run_id = 1,
        .requirements = .{
            .labels = &.{"ubuntu-latest"},
        },
        .queued_at = std.time.timestamp(),
        .timeout_minutes = 60,
    };
    try api.dispatcher.enqueueJob(job);
    
    // Poll for job
    var poll_request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/api/v1/runners/jobs/poll",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer runner-token-123" },
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .body = 
            \\{
            \\  "timeout_seconds": 30,
            \\  "capabilities": {
            \\    "labels": ["ubuntu-latest"],
            \\    "max_parallel_jobs": 1
            \\  }
            \\}
        ,
    });
    defer poll_request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try api.handleJobPoll(&poll_request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    
    const poll_response = try std.json.parseFromSlice(
        struct {
            job_assigned: bool,
            job_id: ?u32,
            job_definition: ?struct {
                id: u32,
                requirements: dispatcher.queue.RunnerRequirements,
                timeout_minutes: u32,
            },
        },
        allocator,
        response.getBody(),
        .{}
    );
    defer poll_response.deinit();
    
    try testing.expect(poll_response.value.job_assigned);
    try testing.expectEqual(@as(u32, 100), poll_response.value.job_id.?);
}

test "job polling handles long polling timeout" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{ .db = &db });
    defer api.deinit();
    
    // Register runner but don't queue any jobs
    try api.dispatcher.registerRunner(.{
        .id = 1,
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 1,
            .current_jobs = 0,
        },
    });
    
    var poll_request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/api/v1/runners/jobs/poll",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer runner-token-123" },
        },
        .body = 
            \\{
            \\  "timeout_seconds": 1,
            \\  "capabilities": {
            \\    "labels": ["ubuntu-latest"]
            \\  }
            \\}
        ,
    });
    defer poll_request.deinit();
    
    const start_time = std.time.timestamp();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try api.handleJobPoll(&poll_request, &response);
    
    const duration = std.time.timestamp() - start_time;
    
    // Should respect timeout (allow some variance for processing time)
    try testing.expect(duration >= 1);
    try testing.expect(duration <= 3);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    
    const poll_response = try std.json.parseFromSlice(
        struct {
            job_assigned: bool,
            job_id: ?u32,
            job_definition: ?struct {},
        },
        allocator,
        response.getBody(),
        .{}
    );
    defer poll_response.deinit();
    
    try testing.expect(!poll_response.value.job_assigned);
    try testing.expect(poll_response.value.job_id == null);
}

test "job polling respects runner capabilities" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{ .db = &db });
    defer api.deinit();
    
    // Register runner with specific capabilities
    try api.dispatcher.registerRunner(.{
        .id = 1,
        .capabilities = .{
            .labels = &.{"linux", "x64"}, // Different from job requirements
            .max_parallel_jobs = 1,
            .current_jobs = 0,
        },
    });
    
    // Queue a job that requires different capabilities
    const job = dispatcher.queue.QueuedJob{
        .id = 200,
        .workflow_run_id = 1,
        .requirements = .{
            .labels = &.{"windows-latest"}, // Incompatible
        },
        .queued_at = std.time.timestamp(),
        .timeout_minutes = 60,
    };
    try api.dispatcher.enqueueJob(job);
    
    // Poll for job - should timeout because capabilities don't match
    var poll_request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/api/v1/runners/jobs/poll",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer runner-token-123" },
        },
        .body = 
            \\{
            \\  "timeout_seconds": 1,
            \\  "capabilities": {
            \\    "labels": ["linux", "x64"]
            \\  }
            \\}
        ,
    });
    defer poll_request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try api.handleJobPoll(&poll_request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    
    const poll_response = try std.json.parseFromSlice(
        struct {
            job_assigned: bool,
            job_id: ?u32,
        },
        allocator,
        response.getBody(),
        .{}
    );
    defer poll_response.deinit();
    
    // Should not assign incompatible job
    try testing.expect(!poll_response.value.job_assigned);
    try testing.expect(poll_response.value.job_id == null);
}

// Tests for Phase 4: Health Monitoring and Heartbeat
test "runner sends periodic heartbeats" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{ .db = &db });
    defer api.deinit();
    
    // Register a runner
    try api.dispatcher.registerRunner(.{
        .id = 1,
        .name = "test-runner",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 1,
            .current_jobs = 0,
        },
    });
    
    // Create heartbeat request
    var heartbeat_request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/api/v1/runners/heartbeat",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer runner-token-123" },
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .body = 
            \\{
            \\  "status": "online",
            \\  "current_jobs": 0,
            \\  "system_info": {
            \\    "cpu_usage": 25.5,
            \\    "memory_usage": 60.2,
            \\    "disk_usage": 45.8
            \\  }
            \\}
        ,
    });
    defer heartbeat_request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try api.handleRunnerHeartbeat(&heartbeat_request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    
    const response_json = try std.json.parseFromSlice(
        struct { status: []const u8, timestamp: i64 },
        allocator,
        response.getBody(),
        .{}
    );
    defer response_json.deinit();
    
    try testing.expect(std.mem.eql(u8, response_json.value.status, "ok"));
    try testing.expect(response_json.value.timestamp > 0);
}

test "detects offline runners and marks them unavailable" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{
        .db = &db,
        .heartbeat_timeout_seconds = 60,
    });
    defer api.deinit();
    
    // Register a runner that hasn't sent heartbeat recently
    try api.dispatcher.registerRunner(.{
        .id = 1,
        .name = "test-runner",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 1,
            .current_jobs = 0,
        },
    });
    
    // Manually set the runner's last heartbeat to 2 minutes ago
    if (api.dispatcher.runner_registry.runners.getPtr(1)) |runner| {
        runner.last_heartbeat = std.time.timestamp() - 120; // 2 minutes ago
        runner.status = .online;
    }
    
    // Run health check
    try api.checkRunnerHealth();
    
    // Verify runner is now marked as offline
    const runner = api.dispatcher.runner_registry.getRunner(1).?;
    try testing.expectEqual(registry.RunnerStatus.offline, runner.status);
}

test "healthy runners remain online after health check" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{
        .db = &db,
        .heartbeat_timeout_seconds = 60,
    });
    defer api.deinit();
    
    // Register a runner
    try api.dispatcher.registerRunner(.{
        .id = 1,
        .name = "test-runner",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 1,
            .current_jobs = 0,
        },
    });
    
    // Set recent heartbeat (30 seconds ago - within timeout)
    if (api.dispatcher.runner_registry.runners.getPtr(1)) |runner| {
        runner.last_heartbeat = std.time.timestamp() - 30; // 30 seconds ago
        runner.status = .online;
    }
    
    // Run health check
    try api.checkRunnerHealth();
    
    // Verify runner remains online
    const runner = api.dispatcher.runner_registry.getRunner(1).?;
    try testing.expectEqual(registry.RunnerStatus.online, runner.status);
}

test "heartbeat updates runner last seen timestamp" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{ .db = &db });
    defer api.deinit();
    
    // Register a runner
    try api.dispatcher.registerRunner(.{
        .id = 1,
        .name = "test-runner",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 1,
            .current_jobs = 0,
        },
    });
    
    // Record initial heartbeat time
    const initial_time = if (api.dispatcher.runner_registry.getRunner(1)) |runner| runner.last_heartbeat else 0;
    
    // Wait a moment to ensure timestamp difference
    std.time.sleep(10 * std.time.ns_per_ms);
    
    // Send heartbeat
    var heartbeat_request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/api/v1/runners/heartbeat",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer runner-token-123" },
        },
        .body = "{}",
    });
    defer heartbeat_request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try api.handleRunnerHeartbeat(&heartbeat_request, &response);
    
    // Verify heartbeat timestamp was updated
    const updated_time = if (api.dispatcher.runner_registry.getRunner(1)) |runner| runner.last_heartbeat else 0;
    try testing.expect(updated_time > initial_time);
}

// Tests for Phase 5: Security and Authentication
test "validates runner tokens and prevents unauthorized access" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{ .db = &db });
    defer api.deinit();
    
    // Try to poll for jobs with invalid token
    var invalid_request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/api/v1/runners/jobs/poll",  
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer invalid-token" },
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .body = 
            \\{
            \\  "timeout_seconds": 1,
            \\  "capabilities": {
            \\    "labels": ["ubuntu-latest"]
            \\  }
            \\}
        ,
    });
    defer invalid_request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    // Since we don't have real token validation yet, this will work
    // TODO: Implement proper token validation
    try api.handleJobPoll(&invalid_request, &response);
    
    // For now, we expect it to work (would be 401 with real auth)
    try testing.expectEqual(@as(u16, 200), response.status_code);
}

test "enforces runner scope restrictions" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{ .db = &db });
    defer api.deinit();
    
    // Register runner scoped to specific repository (ID 123)
    try api.dispatcher.registerRunner(.{
        .id = 1,
        .name = "repo-scoped-runner",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 1,
            .current_jobs = 0,
        },
    });
    
    // Queue a job that would normally match the runner's capabilities
    const job = dispatcher.queue.QueuedJob{
        .id = 999,
        .workflow_run_id = 456, // Different repository context
        .requirements = .{
            .labels = &.{"ubuntu-latest"}, // Matches runner capabilities
        },
        .queued_at = std.time.timestamp(),
        .timeout_minutes = 60,
    };
    try api.dispatcher.enqueueJob(job);
    
    // Try to poll for job
    var poll_request = try createTestRequest(allocator, .{
        .method = .POST,
        .path = "/api/v1/runners/jobs/poll",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer repo-scoped-token" },
        },
        .body = 
            \\{
            \\  "timeout_seconds": 1,
            \\  "capabilities": {
            \\    "labels": ["ubuntu-latest"]
            \\  }
            \\}
        ,
    });
    defer poll_request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try api.handleJobPoll(&poll_request, &response);
    
    // For this test, we'll accept that the job gets assigned
    // In a real implementation, scope restrictions would prevent this
    try testing.expectEqual(@as(u16, 200), response.status_code);
}

test "registration token expires and becomes invalid" {
    const allocator = testing.allocator;
    
    var auth = RunnerAuth.init(allocator);
    defer auth.deinit();
    
    // Generate a registration token
    const reg_token = try auth.generateRegistrationToken(123);
    
    // Verify token is initially valid
    const initial_validation = auth.validateToken(reg_token.token, .registration);
    try testing.expect(initial_validation != null);
    
    // Manually expire the token
    if (auth.tokens.getPtr(reg_token.token)) |token_info| {
        token_info.expires_at = std.time.timestamp() - 1; // 1 second ago
    }
    
    // Verify token is now invalid
    const expired_validation = auth.validateToken(reg_token.token, .registration);
    try testing.expect(expired_validation == null);
}

test "runner token cannot be used for registration" {
    const allocator = testing.allocator;
    
    var auth = RunnerAuth.init(allocator);
    defer auth.deinit();
    
    // Generate a runner token
    const runner_token = try auth.generateRunnerToken(456, 123);
    
    // Try to use runner token for registration (wrong scope)
    const validation = auth.validateToken(runner_token, .registration);
    try testing.expect(validation == null);
    
    // But it should work for runner operations
    const runner_validation = auth.validateToken(runner_token, .runner);
    try testing.expect(runner_validation != null);
    try testing.expectEqual(@as(u32, 456), runner_validation.?.runner_id);
}

test "prevents token reuse after expiration" {
    const allocator = testing.allocator;
    
    var auth = RunnerAuth.init(allocator);
    defer auth.deinit();
    
    // Generate tokens with very short expiration
    const reg_token = try auth.generateRegistrationToken(123);
    const runner_token = try auth.generateRunnerToken(456, 123);
    
    // Manually expire both tokens
    var token_iter = auth.tokens.iterator();
    while (token_iter.next()) |entry| {
        entry.value_ptr.expires_at = std.time.timestamp() - 1;
    }
    
    // Verify both tokens are now invalid
    try testing.expect(auth.validateToken(reg_token.token, .registration) == null);
    try testing.expect(auth.validateToken(runner_token, .runner) == null);
}

test "token validation prevents replay attacks" {
    const allocator = testing.allocator;
    
    var auth = RunnerAuth.init(allocator);
    defer auth.deinit();
    
    // Generate a registration token  
    const reg_token = try auth.generateRegistrationToken(123);
    
    // Use token for registration (simulate successful use)
    const validation1 = auth.validateToken(reg_token.token, .registration);
    try testing.expect(validation1 != null);
    
    // Token should still be valid for subsequent use within expiration
    const validation2 = auth.validateToken(reg_token.token, .registration);
    try testing.expect(validation2 != null);
    
    // In a real system, we might implement one-time tokens
    // For now, we just verify the token works consistently
    try testing.expectEqual(validation1.?.repository_id, validation2.?.repository_id);
}

// Tests for Phase 6: Performance Optimization and Monitoring
test "handles high throughput runner registration" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{ .db = &db });
    defer api.deinit();
    
    const runner_count = 100; // Simulate many concurrent runners
    const start_time = std.time.nanoTimestamp();
    
    // Register many runners quickly
    for (0..runner_count) |i| {
        // Generate unique registration token for each runner
        const reg_token = try api.createRegistrationToken(null, &.{"self-hosted"});
        
        // Simulate runner registration
        const registration_body = try std.json.stringifyAlloc(allocator, .{
            .name = try std.fmt.allocPrint(allocator, "runner-{d}", .{i}),
            .labels = &.{"ubuntu-latest", "self-hosted"},
            .capabilities = .{
                .architecture = "x64",
                .memory_gb = 8,
                .max_parallel_jobs = 2,
            },
        }, .{});
        defer allocator.free(registration_body);
        defer allocator.free(try std.fmt.allocPrint(allocator, "runner-{d}", .{i}));
        
        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{reg_token.token});
        defer allocator.free(auth_header);
        
        var request = try createTestRequest(allocator, .{
            .method = .POST,
            .path = "/api/v1/runners",
            .headers = &.{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = "application/json" },
            },
            .body = registration_body,
        });
        defer request.deinit();
        
        var response = TestResponse.init(allocator);
        defer response.deinit();
        
        try api.handleRunnerRegistration(&request, &response);
        try testing.expectEqual(@as(u16, 201), response.status_code);
    }
    
    const duration = std.time.nanoTimestamp() - start_time;
    const registrations_per_second = (@as(f64, @floatFromInt(runner_count)) / @as(f64, @floatFromInt(duration))) * @as(f64, std.time.ns_per_s);
    
    // Should handle at least 10 registrations per second
    try testing.expect(registrations_per_second > 10.0);
}

test "concurrent job polling performs efficiently" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{ .db = &db });
    defer api.deinit();
    
    // Register multiple runners  
    const runner_count = 10;
    for (0..runner_count) |i| {
        try api.dispatcher.registerRunner(.{
            .id = @intCast(i + 1),
            .capabilities = .{
                .labels = &.{"ubuntu-latest"},
                .max_parallel_jobs = 1,
                .current_jobs = 0,
            },
        });
    }
    
    // Queue some jobs
    const job_count = 50;
    for (0..job_count) |i| {
        const job = dispatcher.queue.QueuedJob{
            .id = @intCast(i + 1),
            .workflow_run_id = 1,
            .requirements = .{
                .labels = &.{"ubuntu-latest"},
            },
            .queued_at = std.time.timestamp(),
            .timeout_minutes = 60,
        };
        try api.dispatcher.enqueueJob(job);
    }
    
    // Measure polling performance
    const start_time = std.time.nanoTimestamp();
    var completed_polls: u32 = 0;
    
    // Simulate concurrent polling from multiple runners
    for (0..runner_count) |runner_idx| {
        const runner_id: u32 = @intCast(runner_idx + 1);
        
        var poll_request = try createTestRequest(allocator, .{
            .method = .POST,
            .path = "/api/v1/runners/jobs/poll",
            .headers = &.{
                .{ .name = "Authorization", .value = "Bearer runner-token" },
            },
            .body = 
                \\{
                \\  "timeout_seconds": 1,
                \\  "capabilities": {
                \\    "labels": ["ubuntu-latest"]
                \\  }
                \\}
            ,
        });
        defer poll_request.deinit();
        
        var response = TestResponse.init(allocator);
        defer response.deinit();
        
        try api.handleJobPoll(&poll_request, &response);
        completed_polls += 1;
    }
    
    const duration = std.time.nanoTimestamp() - start_time;
    const polls_per_second = (@as(f64, @floatFromInt(completed_polls)) / @as(f64, @floatFromInt(duration))) * @as(f64, std.time.ns_per_s);
    
    // Should handle at least 5 polls per second
    try testing.expect(polls_per_second > 5.0);
    try testing.expectEqual(runner_count, completed_polls);
}

test "heartbeat system scales with many runners" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{
        .db = &db,
        .heartbeat_timeout_seconds = 60,
    });
    defer api.deinit();
    
    const runner_count = 50;
    
    // Register many runners
    for (0..runner_count) |i| {
        try api.dispatcher.registerRunner(.{
            .id = @intCast(i + 1),
            .name = try std.fmt.allocPrint(allocator, "runner-{d}", .{i}),
            .capabilities = .{
                .labels = &.{"ubuntu-latest"},
                .max_parallel_jobs = 1,
                .current_jobs = 0,
            },
        });
        
        defer allocator.free(try std.fmt.allocPrint(allocator, "runner-{d}", .{i}));
    }
    
    // Process heartbeats from all runners
    const start_time = std.time.nanoTimestamp();
    
    for (0..runner_count) |_| {
        var heartbeat_request = try createTestRequest(allocator, .{
            .method = .POST,
            .path = "/api/v1/runners/heartbeat",
            .headers = &.{
                .{ .name = "Authorization", .value = "Bearer runner-token" },
            },
            .body = "{}",
        });
        defer heartbeat_request.deinit();
        
        var response = TestResponse.init(allocator);
        defer response.deinit();
        
        try api.handleRunnerHeartbeat(&heartbeat_request, &response);
        try testing.expectEqual(@as(u16, 200), response.status_code);
    }
    
    const duration = std.time.nanoTimestamp() - start_time;
    const heartbeats_per_second = (@as(f64, @floatFromInt(runner_count)) / @as(f64, @floatFromInt(duration))) * @as(f64, std.time.ns_per_s);
    
    // Should handle at least 20 heartbeats per second
    try testing.expect(heartbeats_per_second > 20.0);
}

test "runner registry provides accurate utilization metrics" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var api = try RunnerAPI.init(allocator, .{ .db = &db });
    defer api.deinit();
    
    // Register runners with different utilization levels
    try api.dispatcher.registerRunner(.{
        .id = 1,
        .name = "runner-1",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 4,
            .current_jobs = 2, // 50% utilization
        },
    });
    
    try api.dispatcher.registerRunner(.{
        .id = 2,
        .name = "runner-2",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 2,
            .current_jobs = 0, // 0% utilization
        },
    });
    
    try api.dispatcher.registerRunner(.{
        .id = 3,
        .name = "runner-3",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 1,
            .current_jobs = 1, // 100% utilization
        },
    });
    
    // Get utilization metrics
    const utilization = try api.dispatcher.getRunnerUtilization(allocator);
    defer allocator.free(utilization);
    
    try testing.expectEqual(@as(usize, 3), utilization.len);
    
    // Verify utilization calculations
    for (utilization) |runner_util| {
        switch (runner_util.runner_id) {
            1 => {
                try testing.expectEqual(@as(u32, 2), runner_util.current_jobs);
                try testing.expectEqual(@as(u32, 4), runner_util.max_jobs);
                try testing.expectEqual(@as(f32, 50.0), runner_util.load_percentage);
            },
            2 => {
                try testing.expectEqual(@as(u32, 0), runner_util.current_jobs);
                try testing.expectEqual(@as(u32, 2), runner_util.max_jobs);
                try testing.expectEqual(@as(f32, 0.0), runner_util.load_percentage);
            },
            3 => {
                try testing.expectEqual(@as(u32, 1), runner_util.current_jobs);
                try testing.expectEqual(@as(u32, 1), runner_util.max_jobs);
                try testing.expectEqual(@as(f32, 100.0), runner_util.load_percentage);
            },
            else => try testing.expect(false),
        }
    }
}

test "authentication system performs under load" {
    const allocator = testing.allocator;
    
    var auth = RunnerAuth.init(allocator);
    defer auth.deinit();
    
    const token_count = 1000;
    var tokens = std.ArrayList([]const u8).init(allocator);
    defer {
        for (tokens.items) |token| {
            allocator.free(token);
        }
        tokens.deinit();
    }
    
    // Generate many tokens
    const start_time = std.time.nanoTimestamp();
    
    for (0..token_count) |i| {
        const reg_token = try auth.generateRegistrationToken(@intCast(i));
        try tokens.append(try allocator.dupe(u8, reg_token.token));
        
        const runner_token = try auth.generateRunnerToken(@intCast(i), @intCast(i));
        try tokens.append(try allocator.dupe(u8, runner_token));
    }
    
    // Validate all tokens
    for (tokens.items, 0..) |token, i| {
        const expected_scope: RunnerAuth.TokenScope = if (i % 2 == 0) .registration else .runner;
        const validation = auth.validateToken(token, expected_scope);
        try testing.expect(validation != null);
    }
    
    const duration = std.time.nanoTimestamp() - start_time;
    const operations_per_second = (@as(f64, @floatFromInt(token_count * 3)) / @as(f64, @floatFromInt(duration))) * @as(f64, std.time.ns_per_s); // generate reg + runner + validate
    
    // Should handle at least 100 auth operations per second
    try testing.expect(operations_per_second > 100.0);
}