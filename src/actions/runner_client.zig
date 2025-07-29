const std = @import("std");
const testing = std.testing;
const registry = @import("registry.zig");
const dispatcher = @import("dispatcher.zig");

// HTTP client errors
pub const ClientError = error{
    ServerUnavailable,
    AuthenticationFailed,
    RegistrationFailed,
    NetworkError,
    InvalidResponse,
    Timeout,
};

// Poll result from server
pub const PollResult = union(enum) {
    job_assigned: AssignedJob,
    no_jobs: void,
    runner_offline: void,
    server_error: []const u8,
    
    pub const AssignedJob = struct {
        job_id: u32,
        workflow_run_id: u32,
        job_definition: JobDefinition,
        secrets: std.StringHashMap([]const u8),
        timeout_minutes: u32,
    };
    
    pub const JobDefinition = struct {
        id: u32,
        requirements: dispatcher.queue.RunnerRequirements,
        timeout_minutes: u32,
    };
};

// Registration token response
pub const RegistrationToken = struct {
    token: []const u8,
    expires_at: i64,
};

// Registration result response
pub const RegistrationResult = struct {
    runner_id: u32,
    runner_token: []const u8,
};

// Runner client configuration
pub const RunnerClientConfig = struct {
    server_url: []const u8,
    repository_token: []const u8 = "",
    runner_name: []const u8 = "test-runner",
    capabilities: registry.RunnerCapabilities,
    poll_timeout_seconds: u32 = 30,
    retry_attempts: u32 = 3,
    retry_delay_seconds: u32 = 10,
};

// Mock HTTP client for testing
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    mock_responses: std.ArrayList(MockResponse),
    request_count: u32 = 0,
    
    const MockResponse = struct {
        status_code: u16,
        body: []const u8,
        delay_seconds: u32 = 0,
    };
    
    pub fn init(allocator: std.mem.Allocator) HttpClient {
        return HttpClient{
            .allocator = allocator,
            .mock_responses = std.ArrayList(MockResponse).init(allocator),
        };
    }
    
    pub fn deinit(self: *HttpClient) void {
        for (self.mock_responses.items) |response| {
            self.allocator.free(response.body);
        }
        self.mock_responses.deinit();
    }
    
    pub fn addMockResponse(self: *HttpClient, status_code: u16, body: []const u8, delay_seconds: u32) !void {
        const owned_body = try self.allocator.dupe(u8, body);
        try self.mock_responses.append(MockResponse{
            .status_code = status_code,
            .body = owned_body,
            .delay_seconds = delay_seconds,
        });
    }
    
    pub fn post(self: *HttpClient, url: []const u8, headers: []const Header, body: []const u8) !HttpResponse {
        _ = url;
        _ = headers;
        _ = body;
        
        if (self.request_count >= self.mock_responses.items.len) {
            return ClientError.ServerUnavailable;
        }
        
        const mock_response = self.mock_responses.items[self.request_count];
        self.request_count += 1;
        
        // Simulate network delay
        if (mock_response.delay_seconds > 0) {
            std.time.sleep(@as(u64, mock_response.delay_seconds) * std.time.ns_per_s);
        }
        
        return HttpResponse{
            .status_code = mock_response.status_code,
            .body = try self.allocator.dupe(u8, mock_response.body),
            .allocator = self.allocator,
        };
    }
    
    const Header = struct {
        name: []const u8,
        value: []const u8,
    };
    
    const HttpResponse = struct {
        status_code: u16,
        body: []const u8,
        allocator: std.mem.Allocator,
        
        pub fn deinit(self: HttpResponse) void {
            self.allocator.free(self.body);
        }
    };
};

// Runner client implementation
pub const RunnerClient = struct {
    allocator: std.mem.Allocator,
    config: RunnerClientConfig,
    http_client: HttpClient,
    auth_token: ?[]const u8 = null,
    runner_id: ?u32 = null,
    is_active: bool = true,
    
    pub fn init(allocator: std.mem.Allocator, config: RunnerClientConfig) !RunnerClient {
        return RunnerClient{
            .allocator = allocator,
            .config = config,
            .http_client = HttpClient.init(allocator),
        };
    }
    
    pub fn deinit(self: *RunnerClient) void {
        if (self.auth_token) |token| {
            self.allocator.free(token);
        }
        self.http_client.deinit();
    }
    
    pub fn requestRegistrationToken(self: *RunnerClient) !RegistrationToken {
        const request_body = try std.json.stringifyAlloc(self.allocator, .{
            .labels = self.config.capabilities.labels,
            .name = self.config.runner_name,
        }, .{});
        defer self.allocator.free(request_body);
        
        const headers = [_]HttpClient.Header{
            .{ .name = "Authorization", .value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.config.repository_token}) },
            .{ .name = "Content-Type", .value = "application/json" },
        };
        defer self.allocator.free(headers[0].value);
        
        const response = self.http_client.post(
            try std.fmt.allocPrint(self.allocator, "{s}/api/v1/runners/registration-token", .{self.config.server_url}),
            &headers,
            request_body
        ) catch |err| switch (err) {
            error.ServerUnavailable => return ClientError.ServerUnavailable,
            else => return ClientError.NetworkError,
        };
        defer response.deinit();
        defer self.allocator.free(try std.fmt.allocPrint(self.allocator, "{s}/api/v1/runners/registration-token", .{self.config.server_url}));
        
        if (response.status_code != 200) {
            return ClientError.AuthenticationFailed;
        }
        
        const parsed = try std.json.parseFromSlice(
            struct { token: []const u8, expires_at: i64 },
            self.allocator,
            response.body,
            .{}
        );
        defer parsed.deinit();
        
        return RegistrationToken{
            .token = try self.allocator.dupe(u8, parsed.value.token),
            .expires_at = parsed.value.expires_at,
        };
    }
    
    pub fn register(self: *RunnerClient) !RegistrationResult {
        const reg_token = try self.requestRegistrationToken();
        defer self.allocator.free(reg_token.token);
        
        const request_body = try std.json.stringifyAlloc(self.allocator, .{
            .name = self.config.runner_name,
            .labels = self.config.capabilities.labels,
            .capabilities = .{
                .architecture = self.config.capabilities.architecture,
                .memory_gb = self.config.capabilities.memory_gb,
                .cpu_cores = self.config.capabilities.cpu_cores,
                .docker_enabled = self.config.capabilities.docker_enabled,
                .max_parallel_jobs = self.config.capabilities.max_parallel_jobs,
            },
        }, .{});
        defer self.allocator.free(request_body);
        
        const headers = [_]HttpClient.Header{
            .{ .name = "Authorization", .value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{reg_token.token}) },
            .{ .name = "Content-Type", .value = "application/json" },
        };
        defer self.allocator.free(headers[0].value);
        
        const response = self.http_client.post(
            try std.fmt.allocPrint(self.allocator, "{s}/api/v1/runners", .{self.config.server_url}),
            &headers,
            request_body
        ) catch |err| switch (err) {
            error.ServerUnavailable => return ClientError.ServerUnavailable,
            else => return ClientError.NetworkError,
        };
        defer response.deinit();
        defer self.allocator.free(try std.fmt.allocPrint(self.allocator, "{s}/api/v1/runners", .{self.config.server_url}));
        
        if (response.status_code != 201) {
            return ClientError.RegistrationFailed;
        }
        
        const parsed = try std.json.parseFromSlice(
            struct { runner_id: u32, runner_token: []const u8 },
            self.allocator,
            response.body,
            .{}
        );
        defer parsed.deinit();
        
        // Store authentication info
        self.runner_id = parsed.value.runner_id;
        self.auth_token = try self.allocator.dupe(u8, parsed.value.runner_token);
        
        return RegistrationResult{
            .runner_id = parsed.value.runner_id,
            .runner_token = try self.allocator.dupe(u8, parsed.value.runner_token),
        };
    }
    
    pub fn deregister(self: *RunnerClient) !void {
        if (self.auth_token == null or self.runner_id == null) {
            return;
        }
        
        const headers = [_]HttpClient.Header{
            .{ .name = "Authorization", .value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.auth_token.?}) },
        };
        defer self.allocator.free(headers[0].value);
        
        const response = self.http_client.post(
            try std.fmt.allocPrint(self.allocator, "{s}/api/v1/runners/{d}/deregister", .{ self.config.server_url, self.runner_id.? }),
            &headers,
            ""
        ) catch |err| switch (err) {
            error.ServerUnavailable => return ClientError.ServerUnavailable,
            else => return ClientError.NetworkError,
        };
        defer response.deinit();
        defer self.allocator.free(try std.fmt.allocPrint(self.allocator, "{s}/api/v1/runners/{d}/deregister", .{ self.config.server_url, self.runner_id.? }));
        
        self.is_active = false;
    }
    
    pub fn pollForJob(self: *RunnerClient) ClientError!PollResult {
        if (self.auth_token == null) {
            return ClientError.AuthenticationFailed;
        }
        
        const request_body = try std.json.stringifyAlloc(self.allocator, .{
            .timeout_seconds = self.config.poll_timeout_seconds,
            .capabilities = .{
                .labels = self.config.capabilities.labels,
                .architecture = self.config.capabilities.architecture,
                .memory_gb = self.config.capabilities.memory_gb,
                .max_parallel_jobs = self.config.capabilities.max_parallel_jobs,
                .current_jobs = self.config.capabilities.current_jobs,
            },
        }, .{});
        defer self.allocator.free(request_body);
        
        const headers = [_]HttpClient.Header{
            .{ .name = "Authorization", .value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.auth_token.?}) },
            .{ .name = "Content-Type", .value = "application/json" },
        };
        defer self.allocator.free(headers[0].value);
        
        var attempts: u32 = 0;
        while (attempts < self.config.retry_attempts) {
            const response = self.http_client.post(
                try std.fmt.allocPrint(self.allocator, "{s}/api/v1/runners/jobs/poll", .{self.config.server_url}),
                &headers,
                request_body
            ) catch |err| switch (err) {
                error.ServerUnavailable => {
                    attempts += 1;
                    if (attempts >= self.config.retry_attempts) {
                        return ClientError.ServerUnavailable;
                    }
                    std.time.sleep(self.config.retry_delay_seconds * std.time.ns_per_s);
                    continue;
                },
                else => return ClientError.NetworkError,
            };
            defer response.deinit();
            defer self.allocator.free(try std.fmt.allocPrint(self.allocator, "{s}/api/v1/runners/jobs/poll", .{self.config.server_url}));
            
            switch (response.status_code) {
                200 => {
                    const parsed = try std.json.parseFromSlice(
                        struct {
                            job_assigned: bool,
                            job_id: ?u32,
                            job_definition: ?struct {
                                id: u32,
                                requirements: dispatcher.queue.RunnerRequirements,
                                timeout_minutes: u32,
                            },
                        },
                        self.allocator,
                        response.body,
                        .{}
                    );
                    defer parsed.deinit();
                    
                    if (parsed.value.job_assigned and parsed.value.job_id != null) {
                        return PollResult{
                            .job_assigned = PollResult.AssignedJob{
                                .job_id = parsed.value.job_id.?,
                                .workflow_run_id = 0, // TODO: Extract from response
                                .job_definition = PollResult.JobDefinition{
                                    .id = parsed.value.job_definition.?.id,
                                    .requirements = parsed.value.job_definition.?.requirements,
                                    .timeout_minutes = parsed.value.job_definition.?.timeout_minutes,
                                },
                                .secrets = std.StringHashMap([]const u8).init(self.allocator),
                                .timeout_minutes = parsed.value.job_definition.?.timeout_minutes,
                            },
                        };
                    } else {
                        return PollResult.no_jobs;
                    }
                },
                401 => return ClientError.AuthenticationFailed,
                else => {
                    attempts += 1;
                    if (attempts >= self.config.retry_attempts) {
                        return ClientError.ServerUnavailable;
                    }
                    std.time.sleep(self.config.retry_delay_seconds * std.time.ns_per_s);
                },
            }
        }
        
        return ClientError.ServerUnavailable;
    }
    
    pub fn updateJobStatus(self: *RunnerClient, job_id: u32, status: dispatcher.JobStatus) !void {
        _ = self;
        _ = job_id;
        _ = status;
        // TODO: Implement job status update
    }
    
    pub fn completeJob(self: *RunnerClient, job_id: u32, result: dispatcher.JobResult) !void {
        _ = self;
        _ = job_id;
        _ = result;
        // TODO: Implement job completion
    }
    
    pub fn sendHeartbeat(self: *RunnerClient) !void {
        _ = self;
        // TODO: Implement heartbeat
    }
    
    pub fn updateCapabilities(self: *RunnerClient, capabilities: registry.RunnerCapabilities) !void {
        _ = self;
        _ = capabilities;
        // TODO: Implement capability update
    }
    
    pub fn reportStatus(self: *RunnerClient, status: registry.RunnerStatus) !void {
        _ = self;
        _ = status;
        // TODO: Implement status reporting
    }
};

// Test server for integration testing
const TestServer = struct {
    allocator: std.mem.Allocator,
    port: u16,
    is_running: bool = false,
    
    pub fn init(allocator: std.mem.Allocator, port: u16) TestServer {
        return TestServer{
            .allocator = allocator,
            .port = port,
        };
    }
    
    pub fn deinit(self: *TestServer) void {
        _ = self;
    }
    
    pub fn start(self: *TestServer) !void {
        self.is_running = true;
    }
    
    pub fn stop(self: *TestServer) void {
        self.is_running = false;
    }
};

// Test data
const test_capabilities = registry.RunnerCapabilities{
    .labels = &.{"self-hosted", "linux"},
    .architecture = "x64",
    .memory_gb = 8,
    .max_parallel_jobs = 2,
};

const test_client_config = RunnerClientConfig{
    .server_url = "http://localhost:8080",
    .repository_token = "repo-token-123",
    .runner_name = "test-runner",
    .capabilities = test_capabilities,
    .poll_timeout_seconds = 1, // Short timeout for testing
    .retry_attempts = 2,
    .retry_delay_seconds = 1,
};

// Tests for Phase 3: Runner Client Implementation
test "runner client completes registration flow" {
    const allocator = testing.allocator;
    
    var client = try RunnerClient.init(allocator, test_client_config);
    defer client.deinit();
    
    // Mock successful registration token request
    try client.http_client.addMockResponse(200, 
        \\{"token": "reg-token-abc123", "expires_at": 1234567890}
    , 0);
    
    // Mock successful runner registration
    try client.http_client.addMockResponse(201, 
        \\{"runner_id": 42, "runner_token": "runner-token-xyz789"}
    , 0);
    
    // Request registration token
    const reg_token = try client.requestRegistrationToken();
    defer allocator.free(reg_token.token);
    
    try testing.expect(reg_token.token.len > 0);
    try testing.expectEqual(@as(i64, 1234567890), reg_token.expires_at);
    
    // Complete registration
    const registration_result = try client.register();
    defer allocator.free(registration_result.runner_token);
    
    try testing.expectEqual(@as(u32, 42), registration_result.runner_id);
    try testing.expect(registration_result.runner_token.len > 0);
    try testing.expectEqual(@as(u32, 42), client.runner_id.?);
    try testing.expect(client.auth_token != null);
}

test "runner client polls for jobs with retry" {
    const allocator = testing.allocator;
    
    var client = try RunnerClient.init(allocator, test_client_config);
    defer client.deinit();
    
    // Set up authentication
    client.auth_token = try allocator.dupe(u8, "test-token");
    client.runner_id = 1;
    
    // Mock server temporarily unavailable (first attempt fails)
    try client.http_client.addMockResponse(503, "Service Unavailable", 0);
    
    // Mock successful response (second attempt succeeds)
    try client.http_client.addMockResponse(200, 
        \\{"job_assigned": false, "job_id": null, "job_definition": null}
    , 0);
    
    const poll_result = try client.pollForJob();
    
    // Should eventually succeed after retry
    try testing.expectEqual(PollResult.no_jobs, poll_result);
}

test "runner client handles job assignment response" {
    const allocator = testing.allocator;
    
    var client = try RunnerClient.init(allocator, test_client_config);
    defer client.deinit();
    
    // Set up authentication
    client.auth_token = try allocator.dupe(u8, "test-token");
    client.runner_id = 1;
    
    // Mock job assignment response
    const job_response = 
        \\{
        \\  "job_assigned": true,
        \\  "job_id": 123,
        \\  "job_definition": {
        \\    "id": 123,
        \\    "requirements": {
        \\      "labels": ["ubuntu-latest"],
        \\      "architecture": "x64",
        \\      "min_memory_gb": 2,
        \\      "requires_docker": false
        \\    },
        \\    "timeout_minutes": 60
        \\  }
        \\}
    ;
    
    try client.http_client.addMockResponse(200, job_response, 0);
    
    const poll_result = try client.pollForJob();
    
    switch (poll_result) {
        .job_assigned => |job| {
            try testing.expectEqual(@as(u32, 123), job.job_id);
            try testing.expectEqual(@as(u32, 123), job.job_definition.id);
            try testing.expectEqual(@as(u32, 60), job.job_definition.timeout_minutes);
            
            // Clean up the secrets map
            job.secrets.deinit();
        },
        else => try testing.expect(false), // Should have received a job
    }
}

test "runner client handles authentication failure" {
    const allocator = testing.allocator;
    
    var client = try RunnerClient.init(allocator, test_client_config);
    defer client.deinit();
    
    // Set up invalid authentication
    client.auth_token = try allocator.dupe(u8, "invalid-token");
    client.runner_id = 1;
    
    // Mock authentication failure
    try client.http_client.addMockResponse(401, "Unauthorized", 0);
    
    const poll_result = client.pollForJob();
    
    try testing.expectError(ClientError.AuthenticationFailed, poll_result);
}

test "runner client handles network errors gracefully" {
    const allocator = testing.allocator;
    
    var client = try RunnerClient.init(allocator, .{
        .server_url = "http://localhost:8080",
        .repository_token = "repo-token-123",
        .runner_name = "test-runner",  
        .capabilities = test_capabilities,
        .retry_attempts = 1, // Only one attempt
        .retry_delay_seconds = 1,
    });
    defer client.deinit();
    
    // Set up authentication
    client.auth_token = try allocator.dupe(u8, "test-token");
    client.runner_id = 1;
    
    // Don't add any mock responses - this will trigger ServerUnavailable error
    
    const poll_result = client.pollForJob();
    
    try testing.expectError(ClientError.ServerUnavailable, poll_result);
}