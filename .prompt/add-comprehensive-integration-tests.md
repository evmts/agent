# Add Comprehensive Integration Tests

## Priority: Low

## Problem
While the codebase has excellent unit tests and some integration tests, there could be more comprehensive end-to-end integration tests that verify the entire system works together correctly.

## Current Test Coverage
The project has:
- ✅ Unit tests embedded in source files
- ✅ Database integration tests (with real PostgreSQL)
- ✅ Some HTTP handler tests
- ❌ Limited end-to-end workflow tests
- ❌ Limited multi-component integration tests

## Expected Solution

1. **Create integration test directory structure**:
   ```
   tests/
   ├── integration/
   │   ├── api_workflows.zig          # Full API workflow tests
   │   ├── git_operations.zig         # Git command integration
   │   ├── ssh_sessions.zig           # SSH server integration
   │   ├── lfs_workflows.zig          # LFS upload/download workflows
   │   ├── actions_pipelines.zig      # Actions/CI pipeline tests
   │   └── database_migrations.zig    # Database schema tests
   ├── fixtures/
   │   ├── test_repositories/         # Sample git repositories
   │   ├── test_workflows/            # Sample GitHub Actions workflows  
   │   └── test_data/                 # Sample data files
   └── utils/
       ├── test_server.zig            # Test server utilities
       ├── test_client.zig            # HTTP client for testing
       └── test_environment.zig       # Environment setup/teardown
   ```

2. **API Workflow Integration Tests**:
   ```zig
   // tests/integration/api_workflows.zig
   const TestClient = @import("../utils/test_client.zig").TestClient;
   const TestServer = @import("../utils/test_server.zig").TestServer;
   
   test "complete user workflow: create user, add SSH key, create repo, push code" {
       var test_server = try TestServer.init(testing.allocator);
       defer test_server.deinit();
       
       var client = TestClient.init(test_server.base_url);
       
       // Create user
       const user_response = try client.post("/users", .{
           .name = "integration_test_user",
           .email = "test@example.com",
       });
       try testing.expectEqual(@as(u16, 201), user_response.status);
       
       // Add SSH key
       const key_response = try client.post("/user/keys", .{
           .name = "test_key",
           .content = "ssh-rsa AAAAB3NzaC1yc2EA...",
       });
       try testing.expectEqual(@as(u16, 201), key_response.status);
       
       // Create repository
       const repo_response = try client.post("/user/repos", .{
           .name = "test_repo",
           .description = "Integration test repository",
       });
       try testing.expectEqual(@as(u16, 201), repo_response.status);
       
       // Verify repository exists
       const get_repo_response = try client.get("/repos/integration_test_user/test_repo");
       try testing.expectEqual(@as(u16, 200), get_repo_response.status);
   }
   ```

3. **Git Operations Integration Tests**:
   ```zig
   // tests/integration/git_operations.zig
   test "git operations: clone, commit, push workflow" {
       var test_env = try TestEnvironment.init(testing.allocator);
       defer test_env.deinit();
       
       // Create a test repository
       const repo_path = try test_env.createRepository("test_repo");
       
       // Test git clone
       const clone_result = try test_env.runGitCommand(&.{ "clone", repo_path, "cloned_repo" });
       try testing.expect(clone_result.success);
       
       // Test commit and push
       try test_env.createFile("cloned_repo/README.md", "# Test Repository");
       const add_result = try test_env.runGitCommand(&.{ "add", "README.md" });
       try testing.expect(add_result.success);
       
       const commit_result = try test_env.runGitCommand(&.{ "commit", "-m", "Initial commit" });
       try testing.expect(commit_result.success);
       
       const push_result = try test_env.runGitCommand(&.{ "push", "origin", "main" });
       try testing.expect(push_result.success);
   }
   ```

4. **LFS Workflow Integration Tests**:
   ```zig
   // tests/integration/lfs_workflows.zig  
   test "LFS workflow: upload large file, download, verify integrity" {
       var test_env = try TestEnvironment.init(testing.allocator);
       defer test_env.deinit();
       
       // Create large test file
       const large_file_content = try test_env.generateLargeFile(10 * 1024 * 1024); // 10MB
       defer testing.allocator.free(large_file_content);
       
       // Upload via LFS API
       const upload_response = try test_env.lfsClient.uploadObject("test_oid", large_file_content);
       try testing.expectEqual(@as(u16, 201), upload_response.status);
       
       // Download via LFS API
       const download_response = try test_env.lfsClient.downloadObject("test_oid");
       try testing.expectEqual(@as(u16, 200), download_response.status);
       
       // Verify integrity
       try testing.expectEqualSlices(u8, large_file_content, download_response.body);
   }
   ```

5. **Actions Pipeline Integration Tests**:
   ```zig
   // tests/integration/actions_pipelines.zig
   test "Actions workflow: trigger workflow, execute jobs, collect artifacts" {
       var test_env = try TestEnvironment.init(testing.allocator);
       defer test_env.deinit();
       
       // Create workflow file
       const workflow_yaml = 
           \\name: Test Workflow
           \\on: [push]
           \\jobs:
           \\  test:
           \\    runs-on: ubuntu-latest
           \\    steps:
           \\      - uses: actions/checkout@v4
           \\      - run: echo "Hello, World!" > output.txt
           \\      - uses: actions/upload-artifact@v4
           \\        with:
           \\          name: test-output
           \\          path: output.txt
       ;
       
       // Push workflow file to trigger execution
       try test_env.pushWorkflowFile(".github/workflows/test.yml", workflow_yaml);
       
       // Wait for workflow completion
       const run_id = try test_env.waitForWorkflowRun("Test Workflow");
       
       // Verify job completed successfully
       const run_status = try test_env.getWorkflowRunStatus(run_id);
       try testing.expectEqualStrings("completed", run_status.status);
       try testing.expectEqualStrings("success", run_status.conclusion);
       
       // Verify artifact was created
       const artifacts = try test_env.getWorkflowArtifacts(run_id);
       try testing.expectEqual(@as(usize, 1), artifacts.len);
       try testing.expectEqualStrings("test-output", artifacts[0].name);
   }
   ```

6. **Test Environment Utilities**:
   ```zig
   // tests/utils/test_environment.zig
   pub const TestEnvironment = struct {
       allocator: std.mem.Allocator,
       temp_dir: std.testing.TmpDir,
       server: TestServer,
       database: TestDatabase,
       
       pub fn init(allocator: std.mem.Allocator) !TestEnvironment {
           const temp_dir = std.testing.tmpDir(.{});
           const database = try TestDatabase.init(allocator);
           const server = try TestServer.init(allocator, &database);
           
           return TestEnvironment{
               .allocator = allocator,
               .temp_dir = temp_dir,
               .server = server,
               .database = database,
           };
       }
       
       pub fn deinit(self: *TestEnvironment) void {
           self.server.deinit();
           self.database.deinit();
           self.temp_dir.cleanup();
       }
       
       pub fn createRepository(self: *TestEnvironment, name: []const u8) ![]u8 {
           // Create a real git repository for testing
       }
       
       pub fn runGitCommand(self: *TestEnvironment, args: []const []const u8) !GitResult {
           // Execute git commands in test environment
       }
   };
   ```

## Files to Create
- `tests/integration/api_workflows.zig`
- `tests/integration/git_operations.zig`
- `tests/integration/ssh_sessions.zig`
- `tests/integration/lfs_workflows.zig`
- `tests/integration/actions_pipelines.zig`
- `tests/integration/database_migrations.zig`
- `tests/utils/test_server.zig`
- `tests/utils/test_client.zig`
- `tests/utils/test_environment.zig`
- `tests/utils/test_database.zig`

## Build System Integration
Update `build.zig` to include integration tests:
```zig
const integration_tests = b.addTest(.{
    .root_source_file = b.path("tests/integration/main.zig"),
    .target = target,
    .optimize = optimize,
});

const run_integration_tests = b.addRunArtifact(integration_tests);
const integration_test_step = b.step("test-integration", "Run integration tests");
integration_test_step.dependOn(&run_integration_tests.step);
```

## Benefits
- Verify entire system works end-to-end
- Catch integration issues early
- Test realistic user workflows
- Validate cross-component interactions
- Ensure database migrations work correctly
- Test performance under realistic conditions

## Implementation Strategy
1. **Start with simple API workflows** - basic CRUD operations
2. **Add git operation tests** - clone, push, pull workflows
3. **Integrate LFS testing** - large file upload/download
4. **Add Actions pipeline tests** - workflow execution
5. **Create utilities and fixtures** - reusable test infrastructure
6. **Add to CI pipeline** - run integration tests automatically

## Testing Environment Requirements
- Docker containers for isolated testing
- Test database with migrations
- Sample git repositories
- Mock external services (GitHub, etc.)
- Cleanup mechanisms for test data

## CI/CD Integration
- Run integration tests in CI pipeline
- Use Docker compose for test environment
- Parallel test execution where possible
- Test result reporting and artifact collection