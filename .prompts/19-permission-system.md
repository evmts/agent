# Implement Core Permission Logic for Repository Access

<task_definition>
Implement a comprehensive permission system for repository access control that integrates with the database layer and provides fine-grained authorization for Git operations. This system will handle user permissions, organization access, repository visibility, and Git protocol authorization with enterprise-grade security and performance.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: Database models (issue #18), Configuration system
- **Location**: `src/auth/permissions.zig`
- **Database**: PostgreSQL with proper indexing for performance
- **Security**: Role-based access control (RBAC) with fine-grained permissions
- **Memory**: Efficient permission caching with TTL and invalidation
- **Integration**: SSH server, HTTP Git server, API endpoints

</technical_requirements>

<business_context>

Plue requires a sophisticated permission system to support:

- **Repository Access Control**: Public, private, and internal repositories
- **Organization Permissions**: Organization-level access and team management
- **Git Protocol Authorization**: SSH and HTTP Git operations (clone, fetch, push)
- **Admin Operations**: System administration and user management
- **API Access Control**: REST API endpoint authorization
- **Audit Requirements**: Permission changes and access logging

The system must scale to thousands of users and repositories while maintaining sub-millisecond permission checks through intelligent caching.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

Permission system requirements:

1. **Permission Levels**:
   - `None` - No access
   - `Read` - Clone, fetch, pull operations
   - `Write` - Push operations, branch management
   - `Admin` - Repository settings, collaborator management
   - `Owner` - Full control including deletion

2. **Repository Visibility**:
   - `Public` - Readable by everyone, write access controlled
   - `Private` - Access controlled by explicit permissions
   - `Internal` - Readable by authenticated users

3. **Organization Permissions**:
   - `Member` - Basic organization access
   - `Admin` - Organization management
   - `Owner` - Full organization control

4. **Permission Sources**:
   - Repository collaborators (direct user permissions)
   - Organization team memberships
   - Repository ownership
   - System admin permissions

Expected permission check scenarios:
```zig
// Direct repository access
const permission = try permission_checker.getUserRepoPermission(allocator, user_id, repo_id);

// Git protocol authorization
const can_push = try permission_checker.canUserPushToRepo(allocator, user_id, "owner/repo");
const can_clone = try permission_checker.canUserCloneRepo(allocator, user_id, "owner/repo");

// Organization permissions
const org_role = try permission_checker.getUserOrgRole(allocator, user_id, org_id);

// API endpoint authorization
const can_admin = try permission_checker.canUserAdminRepo(allocator, user_id, repo_id);
```

</input>

<expected_output>

A complete permission system providing:

1. **Permission Checker**: Core authorization logic with caching
2. **Role Management**: User roles and organization permissions
3. **Repository Access Control**: Fine-grained repository permissions
4. **Git Protocol Authorization**: SSH and HTTP Git operation authorization
5. **Permission Caching**: High-performance caching with intelligent invalidation
6. **Audit Logging**: Comprehensive permission change and access logging
7. **Admin Interface**: Permission management APIs and tools
8. **Integration Hooks**: Easy integration with SSH, HTTP, and API layers

Core API structure:
```zig
const PermissionChecker = struct {
    db: *DatabaseConnection,
    cache: *PermissionCache,
    audit_logger: *AuditLogger,

    // Core permission checking
    pub fn getUserRepoPermission(self: *PermissionChecker, allocator: std.mem.Allocator, user_id: u32, repo_id: u32) !PermissionLevel;
    pub fn canUserAccessRepo(self: *PermissionChecker, allocator: std.mem.Allocator, user_id: u32, repo_path: []const u8, operation: GitOperation) !bool;
    
    // Git protocol authorization
    pub fn authorizeGitOperation(self: *PermissionChecker, allocator: std.mem.Allocator, context: GitAuthContext) !AuthorizationResult;
    
    // Organization permissions
    pub fn getUserOrgRole(self: *PermissionChecker, allocator: std.mem.Allocator, user_id: u32, org_id: u32) !OrganizationRole;
    
    // Permission management
    pub fn grantRepoPermission(self: *PermissionChecker, allocator: std.mem.Allocator, granter_id: u32, user_id: u32, repo_id: u32, level: PermissionLevel) !void;
    pub fn revokeRepoPermission(self: *PermissionChecker, allocator: std.mem.Allocator, revoker_id: u32, user_id: u32, repo_id: u32) !void;
};

const PermissionLevel = enum {
    none,
    read,
    write,
    admin,
    owner,
    
    pub fn canRead(self: PermissionLevel) bool;
    pub fn canWrite(self: PermissionLevel) bool;
    pub fn canAdmin(self: PermissionLevel) bool;
};

const GitOperation = enum {
    clone,
    fetch,
    push,
    
    pub fn requiredPermissionLevel(self: GitOperation) PermissionLevel;
};
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach. Use real database for all tests. Run `zig build && zig build test` after EVERY change.

**CRITICAL**: Zero tolerance for test failures. Any failing tests indicate YOU caused a regression.

<phase_1>
<title>Phase 1: Core Permission Types and Enums (TDD)</title>

1. **Create permission module structure**
   ```bash
   mkdir -p src/auth
   touch src/auth/permissions.zig
   ```

2. **Write tests for permission levels**
   ```zig
   test "PermissionLevel hierarchy and capabilities" {
       try testing.expect(PermissionLevel.read.canRead());
       try testing.expect(!PermissionLevel.read.canWrite());
       try testing.expect(!PermissionLevel.read.canAdmin());
       
       try testing.expect(PermissionLevel.write.canRead());
       try testing.expect(PermissionLevel.write.canWrite());
       try testing.expect(!PermissionLevel.write.canAdmin());
       
       try testing.expect(PermissionLevel.admin.canRead());
       try testing.expect(PermissionLevel.admin.canWrite());
       try testing.expect(PermissionLevel.admin.canAdmin());
   }
   
   test "GitOperation permission requirements" {
       try testing.expectEqual(PermissionLevel.read, GitOperation.clone.requiredPermissionLevel());
       try testing.expectEqual(PermissionLevel.read, GitOperation.fetch.requiredPermissionLevel());
       try testing.expectEqual(PermissionLevel.write, GitOperation.push.requiredPermissionLevel());
   }
   ```

3. **Implement permission level enums and capabilities**
4. **Add Git operation permission mapping**

</phase_1>

<phase_2>
<title>Phase 2: Database Permission Queries (TDD)</title>

1. **Write tests for repository permission queries**
   ```zig
   test "gets user repository permission from database" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       // Create test user and repository
       const user_id = try createTestUser(&db, allocator, .{});
       defer _ = db.deleteUser(allocator, user_id) catch {};
       
       const repo_id = try createTestRepository(&db, allocator, .{ .owner_id = user_id });
       defer _ = db.deleteRepository(allocator, repo_id) catch {};
       
       var permission_checker = PermissionChecker.init(&db);
       
       // Owner should have owner permission
       const permission = try permission_checker.getUserRepoPermission(allocator, user_id, repo_id);
       try testing.expectEqual(PermissionLevel.owner, permission);
   }
   
   test "gets collaborator permission from database" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       // Create test users and repository
       const owner_id = try createTestUser(&db, allocator, .{});
       defer _ = db.deleteUser(allocator, owner_id) catch {};
       
       const collaborator_id = try createTestUser(&db, allocator, .{});
       defer _ = db.deleteUser(allocator, collaborator_id) catch {};
       
       const repo_id = try createTestRepository(&db, allocator, .{ .owner_id = owner_id });
       defer _ = db.deleteRepository(allocator, repo_id) catch {};
       
       // Grant write permission to collaborator
       try db.addRepositoryCollaborator(allocator, repo_id, collaborator_id, .write);
       defer _ = db.removeRepositoryCollaborator(allocator, repo_id, collaborator_id) catch {};
       
       var permission_checker = PermissionChecker.init(&db);
       
       const permission = try permission_checker.getUserRepoPermission(allocator, collaborator_id, repo_id);
       try testing.expectEqual(PermissionLevel.write, permission);
   }
   ```

2. **Implement database permission queries**
3. **Add repository ownership detection**
4. **Test collaborator permission resolution**

</phase_2>

<phase_3>
<title>Phase 3: Repository Visibility and Public Access (TDD)</title>

1. **Write tests for repository visibility**
   ```zig
   test "public repository allows read access to any user" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       // Create public repository
       const owner_id = try createTestUser(&db, allocator, .{});
       defer _ = db.deleteUser(allocator, owner_id) catch {};
       
       const repo_id = try createTestRepository(&db, allocator, .{ 
           .owner_id = owner_id, 
           .visibility = .public 
       });
       defer _ = db.deleteRepository(allocator, repo_id) catch {};
       
       // Create random user
       const random_user_id = try createTestUser(&db, allocator, .{});
       defer _ = db.deleteUser(allocator, random_user_id) catch {};
       
       var permission_checker = PermissionChecker.init(&db);
       
       // Random user should have read access to public repo
       const can_read = try permission_checker.canUserAccessRepo(allocator, random_user_id, "owner/repo", .clone);
       try testing.expect(can_read);
       
       // But not write access
       const can_write = try permission_checker.canUserAccessRepo(allocator, random_user_id, "owner/repo", .push);
       try testing.expect(!can_write);
   }
   
   test "private repository denies access to unauthorized users" {
       // Test private repository access control
   }
   ```

2. **Implement repository visibility handling**
3. **Add public repository read access**
4. **Test private repository access control**

</phase_3>

<phase_4>
<title>Phase 4: Organization and Team Permissions (TDD)</title>

1. **Write tests for organization permissions**
   ```zig
   test "organization member has access to internal repositories" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       // Create organization and user
       const org_id = try createTestOrganization(&db, allocator, .{});
       defer _ = db.deleteOrganization(allocator, org_id) catch {};
       
       const user_id = try createTestUser(&db, allocator, .{});
       defer _ = db.deleteUser(allocator, user_id) catch {};
       
       // Add user to organization
       try db.addOrganizationMember(allocator, org_id, user_id, .member);
       defer _ = db.removeOrganizationMember(allocator, org_id, user_id) catch {};
       
       // Create internal repository in organization
       const repo_id = try createTestRepository(&db, allocator, .{ 
           .owner_id = org_id, 
           .visibility = .internal 
       });
       defer _ = db.deleteRepository(allocator, repo_id) catch {};
       
       var permission_checker = PermissionChecker.init(&db);
       
       // Organization member should have read access
       const can_read = try permission_checker.canUserAccessRepo(allocator, user_id, "org/repo", .clone);
       try testing.expect(can_read);
   }
   ```

2. **Implement organization membership checking**
3. **Add team-based permissions**
4. **Test organization admin permissions**

</phase_4>

<phase_5>
<title>Phase 5: Permission Caching and Performance (TDD)</title>

1. **Write tests for permission caching**
   ```zig
   test "permission cache improves lookup performance" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       var permission_checker = try PermissionChecker.initWithCache(allocator, &db, .{
           .ttl_seconds = 300,
           .max_entries = 1000,
       });
       defer permission_checker.deinit(allocator);
       
       // First lookup should hit database
       const start1 = std.time.nanoTimestamp();
       const permission1 = try permission_checker.getUserRepoPermission(allocator, user_id, repo_id);
       const duration1 = std.time.nanoTimestamp() - start1;
       
       // Second lookup should hit cache (much faster)
       const start2 = std.time.nanoTimestamp();
       const permission2 = try permission_checker.getUserRepoPermission(allocator, user_id, repo_id);
       const duration2 = std.time.nanoTimestamp() - start2;
       
       try testing.expectEqual(permission1, permission2);
       try testing.expect(duration2 < duration1 / 2); // Cache should be much faster
   }
   
   test "permission cache invalidation on permission changes" {
       // Test cache invalidation when permissions are modified
   }
   ```

2. **Implement permission caching system**
3. **Add cache invalidation logic**
4. **Test cache performance and correctness**

</phase_5>

<phase_6>
<title>Phase 6: Git Protocol Integration and Authorization (TDD)</title>

1. **Write tests for Git protocol authorization**
   ```zig
   test "authorizes SSH Git operations" {
       const allocator = testing.allocator;
       
       var permission_checker = try PermissionChecker.init(allocator, &db);
       defer permission_checker.deinit(allocator);
       
       const git_context = GitAuthContext{
           .user_id = user_id,
           .repository_path = "owner/repo.git",
           .operation = .push,
           .protocol = .ssh,
           .client_ip = "192.168.1.100",
       };
       
       const auth_result = try permission_checker.authorizeGitOperation(allocator, git_context);
       
       if (auth_result.authorized) {
           try testing.expect(auth_result.permission_level.canWrite());
       } else {
           log.info("Authorization denied: {s}", .{auth_result.denial_reason});
       }
   }
   ```

2. **Implement Git protocol authorization**
3. **Add comprehensive authorization context**
4. **Test SSH and HTTP Git operation authorization**

</phase_6>

<phase_7>
<title>Phase 7: Audit Logging and Permission Management (TDD)</title>

1. **Write tests for audit logging**
   ```zig
   test "logs permission changes for audit" {
       // Test permission grant/revoke logging
   }
   ```

2. **Implement permission management APIs**
3. **Add comprehensive audit logging**
4. **Test permission change workflows**

</phase_7>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **Database Integration**: All tests use real PostgreSQL database
- **Performance Testing**: Permission lookup performance with large datasets
- **Caching Testing**: Cache hit rates, invalidation, and consistency
- **Security Testing**: Access control bypass attempts and edge cases
- **Concurrency Testing**: Concurrent permission checks and modifications
- **Memory Safety**: Zero memory leaks in permission operations

</testing_requirements>

<success_criteria>

1. **All tests pass**: Complete test coverage with zero failures
2. **Performance**: Sub-millisecond permission checks with caching
3. **Security**: Comprehensive access control with no bypass vulnerabilities
4. **Integration**: Seamless integration with SSH and HTTP Git servers
5. **Scalability**: Support for thousands of users and repositories
6. **Audit compliance**: Complete audit trail for permission changes
7. **Memory safety**: Zero memory leaks in all operations

</success_criteria>

</quality_assurance>

<reference_implementations>

- **GitHub permissions**: Repository collaborators and organization teams
- **GitLab permissions**: Project members and group access levels
- **Gitea permissions**: Repository access control and organization management
- **RBAC patterns**: Industry-standard role-based access control implementations

</reference_implementations>