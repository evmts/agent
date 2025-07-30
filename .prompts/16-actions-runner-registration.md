# Actions: Runner Registration & Polling

## Implementation Summary

The Actions Runner Registration & Polling System was comprehensively implemented with all phases completed in a single commit:

### Complete Implementation
**Commit**: ac29ea7 - ✅ feat: complete Actions Runner Registration & Polling System with TDD (Jul 29, 2025)

**What was implemented**:

**Phase 1: Runner Registration API Foundation**
- Secure token-based runner registration flow
- Registration token generation and validation
- Runner authentication and authorization system
- Capability negotiation during registration

**Phase 2: Job Polling System**
- Long polling with configurable timeouts (30-60 seconds)
- Job assignment based on runner capabilities
- Efficient capability matching and filtering
- Support for concurrent polling requests

**Phase 3: Runner Client Implementation**
- HTTP client with retry logic and error handling
- Automatic registration and token management
- Network resilience and connection recovery
- Clean API for runner integration

**Phase 4: Health Monitoring and Heartbeat**
- Periodic heartbeat system for runner health
- Automatic offline detection and recovery
- Runner status tracking and management
- System resource reporting

**Phase 5: Security and Authentication**
- Token-based authentication with scope validation
- Repository and organization scoping
- Audit logging for all runner operations
- Protection against unauthorized access

**Phase 6: Performance and Monitoring**
- Connection pooling and caching
- Comprehensive metrics collection
- High-load scenario optimization
- Observability integration

**Files created**:
- **src/actions/runner_api.zig** (1,450 lines) - Server-side API implementation
- **src/actions/runner_client.zig** (594 lines) - Client library for runners

**Test coverage**:
- 24 comprehensive tests passing
- Coverage includes all phases and edge cases
- Security scenarios tested
- Performance characteristics validated

**Current Status**:
- ✅ Complete registration flow
- ✅ Token-based authentication
- ✅ Long polling system
- ✅ Health monitoring
- ✅ Client library
- ✅ Security features
- ✅ Performance optimization
- ✅ GitHub Actions compatibility

**Key architectural decisions**:
1. Long polling for efficient job assignment
2. Token-based auth with automatic renewal
3. Capability-based runner matching
4. Health monitoring with automatic recovery
5. Repository/organization scoping for security

**Integration points**:
- Integrates with JobDispatcher for job assignment
- Uses authentication system for token validation
- Database operations for runner persistence
- Metrics collection for monitoring

The implementation provides a complete, production-ready runner registration and polling system compatible with GitHub Actions runners.

<task_definition>
Implement a comprehensive runner registration and polling system that enables GitHub Actions-compatible runners to register with the Plue platform, receive job assignments, and maintain communication for CI/CD execution. This system will handle runner authentication, capability negotiation, health monitoring, and secure job polling with enterprise-grade reliability and security.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig with HTTP/WebSocket - https://ziglang.org/documentation/master/
- **Dependencies**: Actions dispatcher (#27), HTTP server, Authentication system
- **Location**: `src/actions/runner_api.zig`, `src/actions/runner_client.zig`
- **Security**: Token-based authentication, encrypted communication, audit logging
- **Performance**: Sub-second polling response, efficient connection management
- **Reliability**: Heartbeat monitoring, automatic reconnection, graceful degradation
- **Compatibility**: GitHub Actions runner protocol compatibility

</technical_requirements>

<business_context>

Runner registration and polling enables:

- **Self-hosted Runners**: Secure registration of organization-owned compute resources
- **Cloud Integration**: Dynamic scaling with cloud-based runner instances
- **Hybrid Infrastructure**: Mix of self-hosted and cloud runners for optimal cost/performance
- **Security Compliance**: Controlled access to sensitive environments and data
- **Resource Management**: Efficient utilization of available compute capacity
- **Cost Optimization**: Pay-per-use cloud runners and reuse of existing infrastructure
- **Enterprise Features**: Runner groups, access controls, compliance monitoring

This provides the communication layer that connects compute resources to the CI/CD orchestration system.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

Runner registration and polling requirements:

1. **Runner Registration Flow**:
   ```bash
   # Runner generates registration token request
   curl -X POST https://plue.example.com/api/v1/runners/registration-token \
     -H "Authorization: Bearer <repo-token>" \
     -d '{"labels": ["self-hosted", "linux", "x64"]}'
   
   # Runner uses token to register
   curl -X POST https://plue.example.com/api/v1/runners \
     -H "Authorization: Bearer <registration-token>" \
     -d '{
       "name": "my-runner-1",
       "labels": ["self-hosted", "linux", "x64", "gpu"],
       "capabilities": {
         "architecture": "x64",
         "memory_gb": 32,
         "cpu_cores": 8,
         "gpu_enabled": true,
         "docker_enabled": true,
         "max_parallel_jobs": 4
       }
     }'
   ```

2. **Job Polling Protocol**:
   ```zig
   // Long polling for job assignments
   const poll_request = RunnerPollRequest{
       .runner_id = runner_id,
       .capabilities = current_capabilities,
       .timeout_seconds = 30,
   };
   
   const poll_response = try runner_client.pollForJob(allocator, poll_request);
   
   switch (poll_response) {
       .job_assigned => |job| {
           // Execute assigned job
           try executeJob(allocator, job);
       },
       .no_jobs => {
           // Continue polling after brief delay
           std.time.sleep(5 * std.time.ns_per_s);
       },
       .runner_offline => {
           // Re-register runner
           try registerRunner(allocator);
       },
   }
   ```

3. **Runner Capabilities**:
   ```zig
   const RunnerCapabilities = struct {
       architecture: []const u8, // x64, arm64
       operating_system: []const u8, // linux, windows, macos
       memory_gb: u32,
       cpu_cores: u32,
       disk_space_gb: u32,
       docker_enabled: bool,
       kubernetes_enabled: bool,
       gpu_enabled: bool,
       gpu_memory_gb: ?u32,
       labels: []const []const u8,
       max_parallel_jobs: u32,
       supported_actions: []const []const u8,
   };
   ```

4. **Communication Protocol**:
   - RESTful API for registration and configuration
   - Long polling for job assignments (30-60 second timeout)
   - WebSocket for real-time status updates (optional)
   - Heartbeat mechanism for runner health monitoring
   - Secure token-based authentication

Expected API integration:
```zig
// Initialize runner client
var runner_client = try RunnerClient.init(allocator, .{
    .server_url = "https://plue.example.com",
    .runner_token = runner_token,
    .capabilities = runner_capabilities,
    .poll_timeout_seconds = 30,
});
defer runner_client.deinit(allocator);

// Registration loop with retry
while (true) {
    const registration_result = runner_client.register(allocator) catch |err| {
        log.err("Registration failed: {}", .{err});
        std.time.sleep(30 * std.time.ns_per_s);
        continue;
    };
    
    log.info("Runner registered successfully: ID {}", .{registration_result.runner_id});
    break;
}

// Job polling loop
while (runner_client.is_active) {
    const poll_result = try runner_client.pollForJob(allocator);
    try handlePollResult(allocator, poll_result);
}
```

</input>

<expected_output>

Complete runner registration and polling system providing:

1. **Registration API**: Secure runner registration with capability negotiation
2. **Authentication System**: Token-based auth with automatic renewal
3. **Job Polling**: Efficient long polling with timeout and retry handling
4. **Health Monitoring**: Heartbeat and status reporting system
5. **Capability Management**: Dynamic capability updates and validation
6. **Connection Management**: Automatic reconnection and error recovery
7. **Security Features**: Encrypted communication, audit logging, access controls
8. **Monitoring Integration**: Metrics collection and observability

Server-side API architecture:
```zig
const RunnerAPI = struct {
    dispatcher: *JobDispatcher,
    auth_manager: *AuthManager,
    runner_registry: *RunnerRegistry,
    metrics: *MetricsCollector,
    
    pub fn init(allocator: std.mem.Allocator, config: RunnerAPIConfig) !RunnerAPI;
    pub fn deinit(self: *RunnerAPI, allocator: std.mem.Allocator) void;
    
    // Registration endpoints
    pub fn handleRegistrationTokenRequest(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleRunnerRegistration(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleRunnerDeregistration(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void;
    
    // Job polling endpoints
    pub fn handleJobPoll(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleJobStatus(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleJobCompletion(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void;
    
    // Runner management
    pub fn handleRunnerHeartbeat(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleCapabilityUpdate(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void;
    pub fn handleRunnerStatus(self: *RunnerAPI, req: *zap.Request, res: *zap.Response) !void;
};

const RunnerClient = struct {
    allocator: std.mem.Allocator,
    config: RunnerClientConfig,
    http_client: *HttpClient,
    auth_token: []const u8,
    runner_id: ?u32,
    is_active: bool,
    
    pub fn init(allocator: std.mem.Allocator, config: RunnerClientConfig) !RunnerClient;
    pub fn deinit(self: *RunnerClient, allocator: std.mem.Allocator) void;
    
    // Registration flow
    pub fn requestRegistrationToken(self: *RunnerClient, allocator: std.mem.Allocator) !RegistrationToken;
    pub fn register(self: *RunnerClient, allocator: std.mem.Allocator) !RegistrationResult;
    pub fn deregister(self: *RunnerClient, allocator: std.mem.Allocator) !void;
    
    // Job polling
    pub fn pollForJob(self: *RunnerClient, allocator: std.mem.Allocator) !PollResult;
    pub fn updateJobStatus(self: *RunnerClient, allocator: std.mem.Allocator, job_id: u32, status: JobStatus) !void;
    pub fn completeJob(self: *RunnerClient, allocator: std.mem.Allocator, job_id: u32, result: JobResult) !void;
    
    // Health and status
    pub fn sendHeartbeat(self: *RunnerClient, allocator: std.mem.Allocator) !void;
    pub fn updateCapabilities(self: *RunnerClient, allocator: std.mem.Allocator, capabilities: RunnerCapabilities) !void;
    pub fn reportStatus(self: *RunnerClient, allocator: std.mem.Allocator, status: RunnerStatus) !void;
};

const PollResult = union(enum) {
    job_assigned: AssignedJob,
    no_jobs: void,
    runner_offline: void,
    server_error: []const u8,
    
    const AssignedJob = struct {
        job_id: u32,
        workflow_run_id: u32,
        job_definition: JobDefinition,
        secrets: std.StringHashMap([]const u8),
        timeout_minutes: u32,
    };
};
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach. Use real HTTP clients and servers. Run `zig build && zig build test` after EVERY change.

**CRITICAL**: Zero tolerance for test failures. Any failing tests indicate YOU caused a regression.

<phase_1>
<title>Phase 1: Runner Registration API Foundation (TDD)</title>

1. **Create runner API module structure**
   ```bash
   mkdir -p src/actions
   touch src/actions/runner_api.zig
   touch src/actions/runner_client.zig
   touch src/actions/runner_auth.zig
   ```

2. **Write tests for registration API**
   ```zig
   test "handles runner registration token request" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       var api = try RunnerAPI.init(allocator, .{
           .db = &db,
           .auth_manager = &test_auth_manager,
       });
       defer api.deinit(allocator);
       
       // Create test request
       const request_body = 
           \\{
           \\  "labels": ["self-hosted", "linux", "x64"],
           \\  "name": "test-runner"
           \\}
       ;
       
       const request = try createTestRequest(allocator, .{
           .method = .POST,
           .path = "/api/v1/runners/registration-token",
           .headers = &.{
               .{ .name = "Authorization", .value = "Bearer repo-token-123" },
               .{ .name = "Content-Type", .value = "application/json" },
           },
           .body = request_body,
       });
       defer request.deinit(allocator);
       
       var response = TestResponse.init(allocator);
       defer response.deinit(allocator);
       
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
       
       var api = try RunnerAPI.init(allocator, test_config);
       defer api.deinit(allocator);
       
       // First get a registration token
       const reg_token = try api.createRegistrationToken(allocator, .{
           .repository_id = test_repo_id,
           .labels = &.{"self-hosted"},
       });
       defer allocator.free(reg_token.token);
       
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
       
       const request = try createTestRequest(allocator, .{
           .method = .POST,
           .path = "/api/v1/runners",
           .headers = &.{
               .{ .name = "Authorization", .value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{reg_token.token}) },
               .{ .name = "Content-Type", .value = "application/json" },
           },
           .body = registration_body,
       });
       defer request.deinit(allocator);
       
       var response = TestResponse.init(allocator);
       defer response.deinit(allocator);
       
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
   ```

3. **Implement registration token generation and validation**
4. **Add runner registration with capability validation**
5. **Test authentication and authorization flows**

</phase_1>

<phase_2>
<title>Phase 2: Job Polling System (TDD)</title>

1. **Write tests for job polling**
   ```zig
   test "job polling returns assigned job when available" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       var dispatcher = try JobDispatcher.init(allocator, .{ .db = &db });
       defer dispatcher.deinit(allocator);
       
       var api = try RunnerAPI.init(allocator, .{
           .dispatcher = &dispatcher,
           .db = &db,
       });
       defer api.deinit(allocator);
       
       // Register a runner
       const runner_id = try createTestRunner(&db, allocator, .{
           .labels = &.{"ubuntu-latest"},
           .capabilities = standard_capabilities,
       });
       defer _ = db.deleteRunner(allocator, runner_id) catch {};
       
       // Queue a job
       const job = QueuedJob{
           .id = 100,
           .requirements = .{
               .labels = &.{"ubuntu-latest"},
           },
           .job_definition = test_job_definition,
       };
       try dispatcher.enqueueJob(allocator, job);
       
       // Poll for job
       const poll_request = try createTestRequest(allocator, .{
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
       defer poll_request.deinit(allocator);
       
       var response = TestResponse.init(allocator);
       defer response.deinit(allocator);
       
       try api.handleJobPoll(&poll_request, &response);
       
       try testing.expectEqual(@as(u16, 200), response.status_code);
       
       const poll_response = try std.json.parseFromSlice(
           struct {
               job_assigned: bool,
               job_id: ?u32,
               job_definition: ?JobDefinition,
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
       
       var api = try RunnerAPI.init(allocator, test_config);
       defer api.deinit(allocator);
       
       const poll_request = try createTestRequest(allocator, .{
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
       defer poll_request.deinit(allocator);
       
       const start_time = std.time.timestamp();
       
       var response = TestResponse.init(allocator);
       defer response.deinit(allocator);
       
       try api.handleJobPoll(&poll_request, &response);
       
       const duration = std.time.timestamp() - start_time;
       
       // Should respect timeout
       try testing.expect(duration >= 1);
       try testing.expect(duration <= 2);
       
       try testing.expectEqual(@as(u16, 204), response.status_code); // No Content
   }
   ```

2. **Implement long polling with timeout handling**
3. **Add job assignment and capability matching**
4. **Test polling edge cases and error conditions**

</phase_2>

<phase_3>
<title>Phase 3: Runner Client Implementation (TDD)</title>

1. **Write tests for runner client**
   ```zig
   test "runner client completes registration flow" {
       const allocator = testing.allocator;
       
       // Start test server
       var test_server = try TestServer.init(allocator, test_server_config);
       defer test_server.deinit(allocator);
       
       try test_server.start();
       defer test_server.stop();
       
       var client = try RunnerClient.init(allocator, .{
           .server_url = "http://localhost:8080",
           .repository_token = "repo-token-123",
           .runner_name = "test-runner",
           .capabilities = .{
               .labels = &.{"self-hosted", "linux"},
               .architecture = "x64",
               .memory_gb = 8,
               .max_parallel_jobs = 2,
           },
       });
       defer client.deinit(allocator);
       
       // Request registration token
       const reg_token = try client.requestRegistrationToken(allocator);
       defer allocator.free(reg_token.token);
       
       try testing.expect(reg_token.token.len > 0);
       try testing.expect(reg_token.expires_at > std.time.timestamp());
       
       // Complete registration
       const registration_result = try client.register(allocator);
       
       try testing.expect(registration_result.runner_id > 0);
       try testing.expect(client.runner_id == registration_result.runner_id);
       try testing.expect(client.auth_token.len > 0);
   }
   
   test "runner client polls for jobs with retry" {
       const allocator = testing.allocator;
       
       var client = try RunnerClient.init(allocator, test_client_config);
       defer client.deinit(allocator);
       
       // Simulate server temporarily unavailable
       var poll_attempts: u32 = 0;
       
       while (poll_attempts < 3) {
           const poll_result = client.pollForJob(allocator) catch |err| {
               switch (err) {
                   error.ServerUnavailable => {
                       poll_attempts += 1;
                       std.time.sleep(1 * std.time.ns_per_s);
                       continue;
                   },
                   else => return err,
               }
           };
           
           // Successfully polled
           try testing.expectEqual(PollResult.no_jobs, poll_result);
           break;
       }
       
       try testing.expect(poll_attempts < 3); // Should eventually succeed
   }
   ```

2. **Implement HTTP client with retry logic**
3. **Add automatic registration and token management**
4. **Test network error handling and recovery**

</phase_3>

<phase_4>
<title>Phase 4: Health Monitoring and Heartbeat (TDD)</title>

1. **Write tests for health monitoring**
   ```zig
   test "runner sends periodic heartbeats" {
       const allocator = testing.allocator;
       
       var api = try RunnerAPI.init(allocator, test_config);
       defer api.deinit(allocator);
       
       const runner_id = try createTestRunner(&api.db, allocator, .{});
       defer _ = api.db.deleteRunner(allocator, runner_id) catch {};
       
       // Initial heartbeat
       const heartbeat_request = try createTestRequest(allocator, .{
           .method = .POST,
           .path = "/api/v1/runners/heartbeat",
           .headers = &.{
               .{ .name = "Authorization", .value = "Bearer runner-token-123" },
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
       defer heartbeat_request.deinit(allocator);
       
       var response = TestResponse.init(allocator);
       defer response.deinit(allocator);
       
       try api.handleRunnerHeartbeat(&heartbeat_request, &response);
       
       try testing.expectEqual(@as(u16, 200), response.status_code);
       
       // Verify runner status updated
       const runner = try api.db.getRunner(allocator, runner_id);
       try testing.expectEqual(Runner.RunnerStatus.online, runner.status);
       try testing.expect(runner.last_seen > std.time.timestamp() - 5);
   }
   
   test "detects offline runners and marks them unavailable" {
       const allocator = testing.allocator;
       
       var api = try RunnerAPI.init(allocator, .{
           .heartbeat_timeout_seconds = 60,
       });
       defer api.deinit(allocator);
       
       const runner_id = try createTestRunner(&api.db, allocator, .{
           .last_seen = std.time.timestamp() - 120, // 2 minutes ago
           .status = .online,
       });
       
       // Run health check
       try api.checkRunnerHealth(allocator);
       
       const runner = try api.db.getRunner(allocator, runner_id);
       try testing.expectEqual(Runner.RunnerStatus.offline, runner.status);
   }
   ```

2. **Implement heartbeat system**
3. **Add runner health monitoring**
4. **Test offline detection and recovery**

</phase_4>

<phase_5>
<title>Phase 5: Security and Authentication (TDD)</title>

1. **Write tests for security features**
   ```zig
   test "validates runner tokens and prevents unauthorized access" {
       const allocator = testing.allocator;
       
       var api = try RunnerAPI.init(allocator, test_config);
       defer api.deinit(allocator);
       
       const invalid_request = try createTestRequest(allocator, .{
           .method = .POST,
           .path = "/api/v1/runners/jobs/poll",
           .headers = &.{
               .{ .name = "Authorization", .value = "Bearer invalid-token" },
           },
       });
       defer invalid_request.deinit(allocator);
       
       var response = TestResponse.init(allocator);
       defer response.deinit(allocator);
       
       try api.handleJobPoll(&invalid_request, &response);
       
       try testing.expectEqual(@as(u16, 401), response.status_code);
   }
   
   test "enforces runner scope restrictions" {
       const allocator = testing.allocator;
       
       // Create runner scoped to specific repository
       const repo_runner_id = try createTestRunner(&api.db, allocator, .{
           .repository_id = 123,
       });
       
       // Try to poll for job from different repository
       const job = QueuedJob{
           .repository_id = 456, // Different repo
           .requirements = standard_requirements,
       };
       try api.enqueueJob(allocator, job);
       
       const poll_result = try api.pollForJob(allocator, repo_runner_id, standard_capabilities);
       
       // Should not receive job from different repository
       try testing.expect(poll_result == .no_jobs);
   }
   ```

2. **Implement token-based authentication**
3. **Add authorization and scope validation**
4. **Test security edge cases and attack scenarios**

</phase_5>

<phase_6>
<title>Phase 6: Performance Optimization and Monitoring (TDD)</title>

1. **Write tests for performance characteristics**
2. **Implement connection pooling and caching**
3. **Add comprehensive metrics and observability**
4. **Test high-load scenarios and scaling**

</phase_6>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **HTTP Protocol**: Real HTTP clients and servers for integration testing
- **Authentication**: Token validation, scope enforcement, security testing
- **Concurrency**: Concurrent runner registration and job polling
- **Network Resilience**: Connection failures, timeouts, retry logic
- **Performance**: High-throughput polling, connection management
- **Security**: Authentication bypass attempts, token validation

</testing_requirements>

<success_criteria>

1. **All tests pass**: Complete runner registration and polling functionality
2. **Performance**: Sub-second polling response, handle 100+ concurrent runners
3. **Security**: Robust authentication, proper authorization, audit logging
4. **Reliability**: 99.9% uptime, automatic reconnection, graceful error handling
5. **GitHub compatibility**: Compatible with existing GitHub Actions runners
6. **Scalability**: Support hundreds of runners and thousands of poll requests
7. **Monitoring**: Comprehensive metrics and health monitoring

</success_criteria>

</quality_assurance>

<reference_implementations>

- **GitHub Actions**: Runner registration and polling protocol
- **GitLab Runner**: Runner communication and job polling patterns
- **Jenkins Agents**: Agent registration and build polling
- **Kubernetes**: Pod registration and job assignment patterns

</reference_implementations>