# Implement Gitea MVP API Schema

## Context

We have a working Plue project with:
- A PostgreSQL database with streamlined MVP schema
- A basic HTTP server (`src/server/server.zig`) with simple endpoints
- DAO layer (`src/database/dao.zig`) with CRUD operations
- Model structs for all database tables
- Python healthcheck script showing API interaction patterns

## Goal

Implement the complete MVP API schema for Gitea-compatible endpoints, focusing on the core functionality needed for a modern Git hosting and CI/CD platform.

## Current State

### Working Endpoints
- `GET /health` - Health check
- `GET /users` - List users
- `POST /users` - Create user
- `GET /users/:name` - Get user by name
- `PUT /users/:name` - Update user name
- `DELETE /users/:name` - Delete user
- `POST /repos` - Create repository
- `GET /repos/:owner/:name` - Get repository
- `POST /repos/:owner/:name/issues` - Create issue
- `GET /repos/:owner/:name/issues/:index` - Get issue

### DAO Methods Available
- User: createUser, getUserByName, updateUserName, deleteUser, listUsers
- Organization: addUserToOrg, getOrgUsers
- SSH Keys: addPublicKey, getUserPublicKeys
- Repository: createRepository, getRepositoryByName
- Issue: createIssue, getIssue

## Implementation Tasks

### Phase 1: Complete User & Organization APIs

1. **User Management**
   - [x] `GET /user` - Get authenticated user (modify to use auth context)
   - [ ] `GET /users/{username}` - Get user/org public profile
   - [ ] `POST /user/keys` - Add SSH key
   - [ ] `GET /user/keys` - List SSH keys
   - [ ] `DELETE /user/keys/{id}` - Delete SSH key

2. **Organization Management**
   - [ ] `POST /orgs` - Create organization
   - [ ] `GET /orgs/{org}` - Get organization details
   - [ ] `PATCH /orgs/{org}` - Update organization
   - [ ] `DELETE /orgs/{org}` - Delete organization
   - [ ] `GET /orgs/{org}/members` - List org members
   - [ ] `DELETE /orgs/{org}/members/{username}` - Remove member
   - [ ] `GET /user/orgs` - List user's organizations

### Phase 2: Repository APIs

1. **Repository Operations**
   - [x] `POST /user/repos` - Create user repository
   - [ ] `POST /orgs/{org}/repos` - Create org repository
   - [ ] `PATCH /repos/{owner}/{repo}` - Update repository
   - [ ] `DELETE /repos/{owner}/{repo}` - Delete repository
   - [ ] `POST /repos/{owner}/{repo}/forks` - Fork repository

2. **Branch Management**
   - [ ] `GET /repos/{owner}/{repo}/branches` - List branches
   - [ ] `GET /repos/{owner}/{repo}/branches/{branch}` - Get branch
   - [ ] `POST /repos/{owner}/{repo}/branches` - Create branch
   - [ ] `DELETE /repos/{owner}/{repo}/branches/{branch}` - Delete branch

3. **File & Content Access**
   - [ ] `GET /repos/{owner}/{repo}/contents/{filepath}` - Get file/directory
   - [ ] `POST /repos/{owner}/{repo}/contents/{filepath}` - Create file
   - [ ] `PUT /repos/{owner}/{repo}/contents/{filepath}` - Update file
   - [ ] `DELETE /repos/{owner}/{repo}/contents/{filepath}` - Delete file

4. **Raw Git Data**
   - [ ] `GET /repos/{owner}/{repo}/git/commits/{sha}` - Get commit
   - [ ] `GET /repos/{owner}/{repo}/git/trees/{sha}` - Get tree
   - [ ] `GET /repos/{owner}/{repo}/git/blobs/{sha}` - Get blob

### Phase 3: Issue & Pull Request APIs

1. **Issues**
   - [ ] `GET /repos/{owner}/{repo}/issues` - List issues
   - [x] `POST /repos/{owner}/{repo}/issues` - Create issue
   - [x] `GET /repos/{owner}/{repo}/issues/{index}` - Get issue
   - [ ] `PATCH /repos/{owner}/{repo}/issues/{index}` - Update issue
   - [ ] `GET /repos/{owner}/{repo}/issues/{index}/comments` - List comments
   - [ ] `POST /repos/{owner}/{repo}/issues/{index}/comments` - Add comment

2. **Labels**
   - [ ] `GET /repos/{owner}/{repo}/labels` - List labels
   - [ ] `POST /repos/{owner}/{repo}/labels` - Create label
   - [ ] `PATCH /repos/{owner}/{repo}/labels/{id}` - Update label
   - [ ] `DELETE /repos/{owner}/{repo}/labels/{id}` - Delete label
   - [ ] `POST /repos/{owner}/{repo}/issues/{index}/labels` - Add labels to issue
   - [ ] `DELETE /repos/{owner}/{repo}/issues/{index}/labels/{id}` - Remove label

3. **Pull Requests**
   - [ ] `GET /repos/{owner}/{repo}/pulls` - List pull requests
   - [ ] `POST /repos/{owner}/{repo}/pulls` - Create pull request
   - [ ] `GET /repos/{owner}/{repo}/pulls/{index}` - Get pull request
   - [ ] `GET /repos/{owner}/{repo}/pulls/{index}/reviews` - List reviews
   - [ ] `POST /repos/{owner}/{repo}/pulls/{index}/reviews` - Submit review
   - [ ] `POST /repos/{owner}/{repo}/pulls/{index}/merge` - Merge PR

### Phase 4: Actions (CI/CD) APIs

1. **Workflow Runs**
   - [ ] `GET /repos/{owner}/{repo}/actions/runs` - List runs
   - [ ] `GET /repos/{owner}/{repo}/actions/runs/{run_id}` - Get run
   - [ ] `GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs` - List jobs

2. **Artifacts**
   - [ ] `GET /repos/{owner}/{repo}/actions/runs/{run_id}/artifacts` - List artifacts
   - [ ] `GET /repos/{owner}/{repo}/actions/artifacts/{artifact_id}` - Get artifact

3. **Secrets**
   - [ ] `GET /orgs/{org}/actions/secrets` - List org secrets
   - [ ] `PUT /orgs/{org}/actions/secrets/{secretname}` - Create/update secret
   - [ ] `DELETE /orgs/{org}/actions/secrets/{secretname}` - Delete secret
   - [ ] `GET /repos/{owner}/{repo}/actions/secrets` - List repo secrets
   - [ ] `PUT /repos/{owner}/{repo}/actions/secrets/{secretname}` - Create/update secret
   - [ ] `DELETE /repos/{owner}/{repo}/actions/secrets/{secretname}` - Delete secret

4. **Runners**
   - [ ] `GET /orgs/{org}/actions/runners` - List org runners
   - [ ] `GET /repos/{owner}/{repo}/actions/runners` - List repo runners
   - [ ] `GET /orgs/{org}/actions/runners/registration-token` - Get org token
   - [ ] `GET /repos/{owner}/{repo}/actions/runners/registration-token` - Get repo token
   - [ ] `DELETE /orgs/{org}/actions/runners/{runner_id}` - Delete org runner
   - [ ] `DELETE /repos/{owner}/{repo}/actions/runners/{runner_id}` - Delete repo runner

### Phase 5: Admin APIs

- [ ] `POST /admin/users` - Create user
- [ ] `PATCH /admin/users/{username}` - Update user
- [ ] `DELETE /admin/users/{username}` - Delete user
- [ ] `POST /admin/users/{username}/keys` - Add SSH key to user

## Implementation Guidelines

### 1. Request/Response Format
- All responses should be JSON with proper `Content-Type: application/json`
- Use consistent error response format: `{"error": "message"}`
- Follow REST conventions for status codes
- Include pagination headers for list endpoints

### 2. Authentication & Authorization
- For MVP, use simple header-based auth: `Authorization: token <token>`
- Store auth tokens in database (add table if needed)
- Check permissions based on user/org ownership

### 3. Code Organization
- Add route handlers to `src/server/server.zig`
- Extend DAO methods in `src/database/dao.zig` as needed
- Create new model methods for complex queries
- Keep handlers focused - delegate business logic to DAO

### 4. Error Handling
- Database errors → 500 Internal Server Error
- Missing resources → 404 Not Found
- Invalid input → 400 Bad Request
- Unauthorized → 401 Unauthorized
- Forbidden → 403 Forbidden

### 5. Testing Strategy
- Write Zig integration tests in each source file
- Test happy path and error cases
- Verify database state changes
- Check response format compliance
- Follow project pattern: tests in same file as implementation

## Python SDK Scripts

Create Python SDK scripts in `scripts/` for internal tooling and database interaction:

### 1. `user_management.py`
```python
#!/usr/bin/env python3
"""SDK for User and SSH Key API operations"""

import requests
import json
import sys

BASE_URL = "http://api-server:8000"
AUTH_TOKEN = "test-token-123"

class UserAPI:
    def __init__(self, base_url=BASE_URL, token=AUTH_TOKEN):
        self.base_url = base_url
        self.headers = {"Authorization": f"token {token}"}
    
    def get_current_user(self):
        """Get the authenticated user's profile"""
        print("Fetching current user...")
    resp = requests.get(f"{BASE_URL}/user", headers=headers)
    assert resp.status_code == 200
    user_data = resp.json()
    assert "id" in user_data
    assert "name" in user_data
    
    # Test SSH keys
    print("Testing SSH key endpoints...")
    key_data = {
        "name": "test-key",
        "key": "ssh-rsa AAAAB3NzaC1yc2EA... test@example.com"
    }
    
    # Create key
    resp = requests.post(f"{BASE_URL}/user/keys", json=key_data, headers=headers)
    assert resp.status_code == 201
    key_id = resp.json()["id"]
    
    # List keys
    resp = requests.get(f"{BASE_URL}/user/keys", headers=headers)
    assert resp.status_code == 200
    keys = resp.json()
    assert len(keys) > 0
    
    # Delete key
    resp = requests.delete(f"{BASE_URL}/user/keys/{key_id}", headers=headers)
    assert resp.status_code == 200
    
    print("✅ User endpoints test passed!")

if __name__ == "__main__":
    test_user_endpoints()
```

### 2. `repository_management.py`
```python
#!/usr/bin/env python3
"""SDK for Repository API operations"""

import requests
import json
import base64

BASE_URL = "http://api-server:8000"
AUTH_TOKEN = "test-token-123"

class RepositoryAPI:
    def __init__(self, base_url=BASE_URL, token=AUTH_TOKEN):
        self.base_url = base_url
        self.headers = {"Authorization": f"token {token}"}
    
    def create_repository(self, name, description=None, private=False):
        """Create a new repository"""
        print(f"Creating repository '{name}'...")
    repo_data = {
        "name": "test-repo",
        "description": "Test repository",
        "private": false
    }
    resp = requests.post(f"{BASE_URL}/user/repos", json=repo_data, headers=headers)
    assert resp.status_code == 201
    
    # Get repository
    resp = requests.get(f"{BASE_URL}/repos/testuser/test-repo", headers=headers)
    assert resp.status_code == 200
    repo = resp.json()
    assert repo["name"] == "test-repo"
    
    # Test branch operations
    print("Testing branch operations...")
    branch_data = {"branch": "feature", "source": "main"}
    resp = requests.post(f"{BASE_URL}/repos/testuser/test-repo/branches", 
                        json=branch_data, headers=headers)
    assert resp.status_code == 201
    
    # Test file operations
    print("Testing file operations...")
    file_data = {
        "message": "Add README",
        "content": base64.b64encode(b"# Test Repo").decode(),
        "branch": "main"
    }
    resp = requests.post(f"{BASE_URL}/repos/testuser/test-repo/contents/README.md",
                        json=file_data, headers=headers)
    assert resp.status_code == 201
    
    print("✅ Repository endpoints test passed!")

if __name__ == "__main__":
    test_repository_endpoints()
```

### 3. `issue_management.py`
```python
#!/usr/bin/env python3
"""SDK for Issue and Label API operations"""

import requests
import json

BASE_URL = "http://api-server:8000"
AUTH_TOKEN = "test-token-123"

class IssueAPI:
    def __init__(self, base_url=BASE_URL, token=AUTH_TOKEN):
        self.base_url = base_url
        self.headers = {"Authorization": f"token {token}"}
    
    def create_label(self, owner, repo, name, color, description=None):
        """Create a new label for issues"""
        print(f"Creating label '{name}'...")
    label_data = {
        "name": "bug",
        "color": "#ff0000",
        "description": "Something isn't working"
    }
    resp = requests.post(f"{BASE_URL}/repos/testuser/test-repo/labels",
                        json=label_data, headers=headers)
    assert resp.status_code == 201
    label_id = resp.json()["id"]
    
    # Create issue
    print("Testing issue creation...")
    issue_data = {
        "title": "Test Issue",
        "body": "This is a test issue",
        "labels": [label_id]
    }
    resp = requests.post(f"{BASE_URL}/repos/testuser/test-repo/issues",
                        json=issue_data, headers=headers)
    assert resp.status_code == 201
    issue = resp.json()
    issue_number = issue["number"]
    
    # Add comment
    print("Testing comment creation...")
    comment_data = {"body": "This is a test comment"}
    resp = requests.post(f"{BASE_URL}/repos/testuser/test-repo/issues/{issue_number}/comments",
                        json=comment_data, headers=headers)
    assert resp.status_code == 201
    
    # Update issue
    print("Testing issue update...")
    update_data = {"state": "closed"}
    resp = requests.patch(f"{BASE_URL}/repos/testuser/test-repo/issues/{issue_number}",
                         json=update_data, headers=headers)
    assert resp.status_code == 200
    
    print("✅ Issue endpoints test passed!")

if __name__ == "__main__":
    test_issue_endpoints()
```

### 4. `actions_management.py`
```python
#!/usr/bin/env python3
"""SDK for Actions (CI/CD) API operations"""

import requests
import json

BASE_URL = "http://api-server:8000"
AUTH_TOKEN = "test-token-123"

class ActionsAPI:
    def __init__(self, base_url=BASE_URL, token=AUTH_TOKEN):
        self.base_url = base_url
        self.headers = {"Authorization": f"token {token}"}
    
    def create_secret(self, owner, repo, secret_name, encrypted_value):
        """Create or update a repository secret"""
        print(f"Setting secret '{secret_name}'...")
    secret_data = {
        "encrypted_value": "encrypted_secret_value",
        "visibility": "private"
    }
    resp = requests.put(f"{BASE_URL}/repos/testuser/test-repo/actions/secrets/TEST_SECRET",
                       json=secret_data, headers=headers)
    assert resp.status_code in [201, 204]
    
    # List secrets
    resp = requests.get(f"{BASE_URL}/repos/testuser/test-repo/actions/secrets", headers=headers)
    assert resp.status_code == 200
    secrets = resp.json()
    assert len(secrets["secrets"]) > 0
    
    # Test runners
    print("Testing runner registration...")
    resp = requests.get(f"{BASE_URL}/repos/testuser/test-repo/actions/runners/registration-token",
                       headers=headers)
    assert resp.status_code == 200
    token = resp.json()
    assert "token" in token
    assert "expires_at" in token
    
    # List workflow runs (should be empty initially)
    print("Testing workflow runs...")
    resp = requests.get(f"{BASE_URL}/repos/testuser/test-repo/actions/runs", headers=headers)
    assert resp.status_code == 200
    runs = resp.json()
    assert "workflow_runs" in runs
    
    print("✅ Actions endpoints test passed!")

if __name__ == "__main__":
    test_actions_endpoints()
```

## DAO Extensions Needed

### 1. Authentication
```zig
// Add to dao.zig
pub const AuthToken = struct {
    id: i64,
    user_id: i64,
    token: []const u8,
    created_unix: i64,
    expires_unix: i64,
};

pub fn createAuthToken(self: *DataAccessObject, allocator: std.mem.Allocator, user_id: i64) !AuthToken
pub fn getAuthToken(self: *DataAccessObject, allocator: std.mem.Allocator, token: []const u8) !?AuthToken
pub fn deleteAuthToken(self: *DataAccessObject, allocator: std.mem.Allocator, token: []const u8) !void
```

### 2. Additional Repository Methods
```zig
pub fn updateRepository(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64, updates: RepositoryUpdate) !void
pub fn deleteRepository(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64) !void
pub fn forkRepository(self: *DataAccessObject, allocator: std.mem.Allocator, source_id: i64, owner_id: i64, name: []const u8) !i64
```

### 3. Branch Operations
```zig
pub fn createBranch(self: *DataAccessObject, allocator: std.mem.Allocator, branch: Branch) !void
pub fn getBranches(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64) ![]Branch
pub fn deleteBranch(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64, name: []const u8) !void
```

### 4. Issue Operations
```zig
pub fn listIssues(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64, filters: IssueFilters) ![]Issue
pub fn updateIssue(self: *DataAccessObject, allocator: std.mem.Allocator, issue_id: i64, updates: IssueUpdate) !void
pub fn createComment(self: *DataAccessObject, allocator: std.mem.Allocator, comment: Comment) !i64
pub fn getComments(self: *DataAccessObject, allocator: std.mem.Allocator, issue_id: i64) ![]Comment
```

### 5. Label Operations
```zig
pub fn createLabel(self: *DataAccessObject, allocator: std.mem.Allocator, label: Label) !i64
pub fn getLabels(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64) ![]Label
pub fn addLabelToIssue(self: *DataAccessObject, allocator: std.mem.Allocator, issue_id: i64, label_id: i64) !void
```

### 6. Actions/CI Operations
```zig
pub fn createActionRun(self: *DataAccessObject, allocator: std.mem.Allocator, run: ActionRun) !i64
pub fn getActionRuns(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64) ![]ActionRun
pub fn createActionSecret(self: *DataAccessObject, allocator: std.mem.Allocator, secret: ActionSecret) !void
pub fn getActionSecrets(self: *DataAccessObject, allocator: std.mem.Allocator, repo_id: i64) ![]ActionSecret
```

## JSON Response Helpers

Add to server.zig:
```zig
fn writeJson(res: *httpz.Response, allocator: std.mem.Allocator, value: anytype) !void {
    var json_builder = std.ArrayList(u8).init(allocator);
    try std.json.stringify(value, .{}, json_builder.writer());
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, json_builder.items);
    json_builder.deinit();
}

fn writeError(res: *httpz.Response, allocator: std.mem.Allocator, status: u16, message: []const u8) !void {
    res.status = status;
    try writeJson(res, allocator, .{ .error = message });
}
```

## Middleware for Authentication

```zig
fn authMiddleware(ctx: *Context, req: *httpz.Request, res: *httpz.Response, next: httpz.Next) !void {
    const auth_header = req.header("authorization") orelse {
        try writeError(res, req.arena, 401, "Missing authorization header");
        return;
    };
    
    if (!std.mem.startsWith(u8, auth_header, "token ")) {
        try writeError(res, req.arena, 401, "Invalid authorization format");
        return;
    }
    
    const token = auth_header[6..];
    const auth_token = try ctx.dao.getAuthToken(req.arena, token) orelse {
        try writeError(res, req.arena, 401, "Invalid token");
        return;
    };
    
    // Add user_id to request context
    req.user_id = auth_token.user_id;
    
    try next(ctx, req, res);
}
```

## Zig Integration Tests

Add comprehensive tests to `src/server/server.zig` following the project pattern:

```zig
test "user API endpoints" {
    const allocator = std.testing.allocator;
    
    // Initialize test database
    const test_db_url = std.posix.getenv("TEST_DATABASE_URL") orelse "postgresql://plue:plue_password@localhost:5432/plue";
    var dao = DataAccessObject.init(test_db_url) catch |err| switch (err) {
        error.ConnectionRefused => {
            std.log.warn("Database not available for testing, skipping", .{});
            return;
        },
        else => return err,
    };
    defer dao.deinit();
    
    // Clean up test data
    dao.deleteUser(allocator, "test_api_user") catch {};
    
    // Create test server
    var server = try Server.init(allocator, &dao);
    defer server.deinit(allocator);
    
    // Test GET /user endpoint
    {
        // Create auth token for test user
        const test_user = try dao.createUser(allocator, .{
            .name = "test_api_user",
            .email = "api@test.com",
            .type = .individual,
        });
        const token = try dao.createAuthToken(allocator, test_user.id);
        defer dao.deleteAuthToken(allocator, token.token) catch {};
        
        // Simulate request
        var req = try httpz.Request.init(allocator);
        defer req.deinit();
        req.method = .GET;
        req.path = "/user";
        req.headers.add("Authorization", try std.fmt.allocPrint(allocator, "token {s}", .{token.token}));
        
        var res = httpz.Response.init(allocator);
        defer res.deinit();
        
        try getUserHandler(&server.context, &req, &res);
        
        try std.testing.expectEqual(@as(u16, 200), res.status);
        try std.testing.expect(std.mem.indexOf(u8, res.body, "test_api_user") != null);
    }
    
    // Test SSH key endpoints
    {
        // Test POST /user/keys
        var req = try httpz.Request.init(allocator);
        defer req.deinit();
        req.method = .POST;
        req.path = "/user/keys";
        req.body = "{\"name\":\"test-key\",\"key\":\"ssh-rsa AAAAB3...\"}";
        
        var res = httpz.Response.init(allocator);
        defer res.deinit();
        
        try createSSHKeyHandler(&server.context, &req, &res);
        try std.testing.expectEqual(@as(u16, 201), res.status);
    }
    
    // Clean up
    dao.deleteUser(allocator, "test_api_user") catch {};
}

test "repository API endpoints" {
    const allocator = std.testing.allocator;
    
    // Similar setup...
    
    // Test repository creation
    {
        var req = try httpz.Request.init(allocator);
        defer req.deinit();
        req.method = .POST;
        req.path = "/user/repos";
        req.body = "{\"name\":\"test-repo\",\"description\":\"Test repo\",\"private\":false}";
        
        var res = httpz.Response.init(allocator);
        defer res.deinit();
        
        try createRepoHandler(&server.context, &req, &res);
        try std.testing.expectEqual(@as(u16, 201), res.status);
    }
    
    // Test branch operations
    {
        // Create branch
        var req = try httpz.Request.init(allocator);
        defer req.deinit();
        req.method = .POST;
        req.path = "/repos/test_user/test-repo/branches";
        req.body = "{\"branch\":\"feature\",\"source\":\"main\"}";
        
        var res = httpz.Response.init(allocator);
        defer res.deinit();
        
        try createBranchHandler(&server.context, &req, &res);
        try std.testing.expectEqual(@as(u16, 201), res.status);
    }
}

test "issue API endpoints" {
    const allocator = std.testing.allocator;
    
    // Test label CRUD
    {
        // Create label
        var req = try httpz.Request.init(allocator);
        defer req.deinit();
        req.method = .POST;
        req.path = "/repos/test_user/test-repo/labels";
        req.body = "{\"name\":\"bug\",\"color\":\"#ff0000\"}";
        
        var res = httpz.Response.init(allocator);
        defer res.deinit();
        
        try createLabelHandler(&server.context, &req, &res);
        try std.testing.expectEqual(@as(u16, 201), res.status);
    }
    
    // Test issue operations
    {
        // List issues
        var req = try httpz.Request.init(allocator);
        defer req.deinit();
        req.method = .GET;
        req.path = "/repos/test_user/test-repo/issues";
        
        var res = httpz.Response.init(allocator);
        defer res.deinit();
        
        try listIssuesHandler(&server.context, &req, &res);
        try std.testing.expectEqual(@as(u16, 200), res.status);
        try std.testing.expect(std.mem.indexOf(u8, res.body, "[") != null); // JSON array
    }
}

test "actions API endpoints" {
    const allocator = std.testing.allocator;
    
    // Test secrets management
    {
        // Create secret
        var req = try httpz.Request.init(allocator);
        defer req.deinit();
        req.method = .PUT;
        req.path = "/repos/test_user/test-repo/actions/secrets/TEST_SECRET";
        req.body = "{\"encrypted_value\":\"encrypted_value\"}";
        
        var res = httpz.Response.init(allocator);
        defer res.deinit();
        
        try createSecretHandler(&server.context, &req, &res);
        try std.testing.expectEqual(@as(u16, 201), res.status);
    }
    
    // Test runner registration
    {
        var req = try httpz.Request.init(allocator);
        defer req.deinit();
        req.method = .GET;
        req.path = "/repos/test_user/test-repo/actions/runners/registration-token";
        
        var res = httpz.Response.init(allocator);
        defer res.deinit();
        
        try getRunnerTokenHandler(&server.context, &req, &res);
        try std.testing.expectEqual(@as(u16, 200), res.status);
        try std.testing.expect(std.mem.indexOf(u8, res.body, "token") != null);
    }
}
```

## Success Criteria

1. All API endpoints return correct status codes
2. JSON responses match expected format
3. Database operations are properly transactional
4. Error handling is consistent across endpoints
5. All Zig integration tests pass
6. Python SDK scripts work correctly for database operations
7. Memory management follows project standards (proper defer/errdefer)
8. Code follows single responsibility principle
9. Tests are included in source files (Zig pattern)

## Notes

- Start with Phase 1 and work incrementally
- Test each endpoint thoroughly before moving on
- Keep the implementation simple - avoid over-engineering
- Focus on correctness over performance initially
- Use existing patterns from current handlers
- Remember to handle both user and organization contexts
- Git operations (commits, trees, blobs) will interface with actual git repositories later