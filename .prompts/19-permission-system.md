# Implement Enterprise Permission System with Organization/Team Support (ENHANCED WITH GITEA PRODUCTION PATTERNS)

<task_definition>
Implement a comprehensive enterprise-grade permission system for repository access control that provides organization/team support, unit-level permissions, visibility patterns, and request-level caching. This system handles complex permission hierarchies, team-based access control, fine-grained repository permissions, and Git protocol authorization with production-grade security and performance following Gitea's battle-tested patterns.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: Database models (issue #18), Configuration system
- **Location**: `src/auth/permissions.zig`, `src/auth/teams.zig`, `src/auth/units.zig`
- **Database**: PostgreSQL with advanced indexing for complex queries
- **Security**: Multi-tier RBAC with organization/team/unit-level permissions
- **Memory**: Request-level caching with invalidation cascades
- **🆕 Organizations**: Full organization support with team hierarchies
- **🆕 Unit Permissions**: Fine-grained unit-level access control (issues, PRs, wiki, etc.)
- **🆕 Visibility Patterns**: Complex visibility rules with inheritance
- **Integration**: SSH server, HTTP Git server, API endpoints, webhook systems

</technical_requirements>

<business_context>

Plue requires an enterprise-grade permission system to support:

- **🆕 Organization Management**: Multi-tier organization hierarchies with team structures
- **🆕 Team-Based Access**: Granular team permissions with inheritance patterns
- **🆕 Unit-Level Permissions**: Fine-grained control over repository features (issues, PRs, wiki, releases, packages)
- **🆕 Complex Visibility**: Public, private, internal, and limited visibility with organization-specific rules
- **Repository Access Control**: Repository-level permissions with collaborative features
- **Git Protocol Authorization**: SSH and HTTP Git operations with team-aware routing
- **Admin Operations**: Multi-level administration (system, organization, repository)
- **API Access Control**: Context-aware API endpoint authorization
- **🆕 Audit & Compliance**: Comprehensive audit trails with organization-level reporting
- **🆕 Integration Patterns**: Webhook permissions, external authentication, LDAP/SAML integration

The system must scale to thousands of organizations, teams, and repositories while maintaining sub-millisecond permission checks through request-level caching and smart invalidation patterns following Gitea's production architecture.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

🆕 **Enterprise Permission System Requirements (Gitea Production Patterns)**:

1. **🆕 Multi-Tier Permission Architecture**:
   ```zig
   // Repository-level permissions
   const RepositoryPermission = enum {
       none,      // No access
       read,      // Clone, fetch, pull operations
       write,     // Push operations, branch management  
       admin,     // Repository settings, collaborator management
       owner,     // Full control including deletion
   };
   
   // Organization-level roles
   const OrganizationRole = enum {
       none,      // No organization access
       member,    // Basic organization access
       admin,     // Organization management
       owner,     // Full organization control
   };
   
   // Team-level permissions with inheritance
   const TeamPermission = enum {
       none,      // No team access
       read,      // Team visibility, basic access
       write,     // Team repository write access
       admin,     // Team management, member administration
   };
   ```

2. **🆕 Unit-Level Permissions (Fine-Grained Control)**:
   ```zig
   const UnitType = enum {
       code,           // Repository code access
       issues,         // Issue tracking
       pull_requests,  // Pull request management
       releases,       // Release management
       wiki,           // Wiki access
       packages,       // Package management
       actions,        // CI/CD actions
       projects,       // Project management
   };
   
   const UnitPermission = struct {
       unit_type: UnitType,
       access_mode: AccessMode,
       
       const AccessMode = enum {
           none,    // Unit disabled
           read,    // Read-only access
           write,   // Read-write access
           admin,   // Administrative access
       };
   };
   ```

3. **🆕 Complex Visibility Patterns**:
   ```zig
   const RepositoryVisibility = enum {
       public,      // Visible to everyone
       internal,    // Visible to authenticated users
       private,     // Visible only to authorized users
       limited,     // Visible to organization members only
       
       pub fn isVisibleTo(self: RepositoryVisibility, user: ?User, org: ?Organization) bool;
   };
   ```

4. **🆕 Team Hierarchy and Inheritance**:
   - Teams can inherit permissions from parent teams
   - Team permissions override individual collaborator permissions
   - Organization-level default permissions
   - Repository-specific team access controls

5. **🆕 Permission Resolution Priority** (highest to lowest):
   - Repository owner permissions
   - Repository admin collaborator permissions
   - Organization owner permissions
   - Team-specific permissions (merged)
   - Organization member base permissions
   - Repository visibility settings
   - System-level permissions

6. **🆕 Advanced Permission Sources**:
   - Direct repository collaborators
   - Organization team memberships (with inheritance)
   - Organization base permissions
   - Repository ownership
   - System administrator privileges
   - External authentication provider groups (LDAP/SAML)
   - Temporary access grants

🆕 **Expected Enterprise Permission Check Scenarios**:
```zig
// Multi-tier permission resolution
const context = PermissionContext{
    .user_id = user_id,
    .organization_id = org_id,
    .repository_id = repo_id,
    .request_id = request_id, // For caching
};

// Repository-level permissions with team inheritance
const repo_permission = try permission_checker.getUserRepoPermission(allocator, context);

// Unit-level permission checks
const can_view_issues = try permission_checker.hasUnitAccess(allocator, context, .issues, .read);
const can_manage_releases = try permission_checker.hasUnitAccess(allocator, context, .releases, .admin);

// Team-based authorization with inheritance
const team_permissions = try permission_checker.getUserTeamPermissions(allocator, user_id, org_id);

// Organization role resolution
const org_role = try permission_checker.getUserOrgRole(allocator, user_id, org_id);

// Complex visibility checks
const can_see_repo = try permission_checker.canUserSeeRepository(allocator, user_id, repo_path);

// Git protocol authorization with team context
const git_auth = GitAuthContext{
    .user_id = user_id,
    .repository_path = "org/repo.git",
    .operation = .push,
    .branch = "main",
    .team_context = team_context,
};
const can_push = try permission_checker.authorizeGitOperation(allocator, git_auth);

// API endpoint authorization with unit awareness
const api_context = APIAuthContext{
    .user_id = user_id,
    .endpoint = "/api/v1/repos/org/repo/issues",
    .method = .POST,
    .required_unit = .issues,
    .required_access = .write,
};
const can_access_api = try permission_checker.authorizeAPIAccess(allocator, api_context);
```

</input>

<expected_output>

🆕 **Complete Enterprise Permission System Providing**:

1. **🆕 Multi-Tier Permission Checker**: Core authorization with organization/team/unit awareness
2. **🆕 Team Management System**: Team hierarchies with permission inheritance
3. **🆕 Unit-Level Access Control**: Fine-grained feature-level permissions
4. **🆕 Organization Role Management**: Complex organization structures with role inheritance
5. **🆕 Advanced Visibility Engine**: Complex visibility patterns with organization rules
6. **Repository Access Control**: Enhanced repository permissions with team integration
7. **Git Protocol Authorization**: Team-aware SSH and HTTP Git operation authorization
8. **🆕 Request-Level Caching**: High-performance caching with cascade invalidation
9. **🆕 Comprehensive Audit System**: Multi-level audit trails with organization reporting
10. **🆕 Integration Framework**: LDAP/SAML, webhook permissions, external auth providers
11. **Admin Interface**: Multi-tier administration tools (system/org/repo)
12. **Performance Optimization**: Sub-millisecond checks with smart caching patterns

🆕 **Enhanced Enterprise Permission Architecture**:
```zig
const PermissionChecker = struct {
    db: *DatabaseConnection,
    cache: *RequestLevelCache,
    audit_logger: *AuditLogger,
    team_manager: *TeamManager,
    org_manager: *OrganizationManager,

    // 🆕 Multi-tier permission resolution
    pub fn getUserRepoPermission(self: *PermissionChecker, allocator: std.mem.Allocator, context: PermissionContext) !ResolvedPermission;
    pub fn hasUnitAccess(self: *PermissionChecker, allocator: std.mem.Allocator, context: PermissionContext, unit: UnitType, access: AccessMode) !bool;
    
    // 🆕 Team-based authorization
    pub fn getUserTeamPermissions(self: *PermissionChecker, allocator: std.mem.Allocator, user_id: u32, org_id: u32) ![]TeamPermissionSet;
    pub fn resolveTeamInheritance(self: *PermissionChecker, allocator: std.mem.Allocator, team_id: u32) !ResolvedTeamPermission;
    
    // 🆕 Organization management
    pub fn getUserOrgRole(self: *PermissionChecker, allocator: std.mem.Allocator, user_id: u32, org_id: u32) !OrganizationRole;
    pub fn checkOrgTeamPermission(self: *PermissionChecker, allocator: std.mem.Allocator, user_id: u32, org_id: u32, team_id: u32) !TeamPermission;
    
    // 🆕 Advanced visibility and access
    pub fn canUserSeeRepository(self: *PermissionChecker, allocator: std.mem.Allocator, user_id: u32, repo_path: []const u8) !bool;
    pub fn getRepositoryVisibilityLevel(self: *PermissionChecker, allocator: std.mem.Allocator, repo_id: u32, user_context: UserContext) !VisibilityLevel;
    
    // 🆕 Enhanced Git protocol authorization
    pub fn authorizeGitOperation(self: *PermissionChecker, allocator: std.mem.Allocator, context: GitAuthContext) !AuthorizationResult;
    pub fn authorizeAPIAccess(self: *PermissionChecker, allocator: std.mem.Allocator, context: APIAuthContext) !APIAuthorizationResult;
    
    // 🆕 Advanced permission management
    pub fn grantTeamRepoAccess(self: *PermissionChecker, allocator: std.mem.Allocator, granter_id: u32, team_id: u32, repo_id: u32, units: []UnitPermission) !void;
    pub fn updateUserOrgRole(self: *PermissionChecker, allocator: std.mem.Allocator, admin_id: u32, user_id: u32, org_id: u32, role: OrganizationRole) !void;
    pub fn bulkUpdateTeamPermissions(self: *PermissionChecker, allocator: std.mem.Allocator, team_updates: []TeamPermissionUpdate) !BulkUpdateResult;
    
    // 🆕 Request-level caching with invalidation
    pub fn invalidateUserPermissions(self: *PermissionChecker, allocator: std.mem.Allocator, user_id: u32) !void;
    pub fn invalidateRepositoryPermissions(self: *PermissionChecker, allocator: std.mem.Allocator, repo_id: u32) !void;
    pub fn invalidateOrganizationPermissions(self: *PermissionChecker, allocator: std.mem.Allocator, org_id: u32) !void;
};

// 🆕 Enhanced permission structures
const ResolvedPermission = struct {
    repository_access: RepositoryPermission,
    unit_permissions: []UnitPermission,
    source: PermissionSource,
    team_context: ?TeamContext,
    expires_at: ?i64,
    
    const PermissionSource = enum {
        repository_owner,
        repository_collaborator,
        organization_owner,
        organization_admin,
        team_permission,
        organization_member,
        public_access,
        system_admin,
    };
};

const PermissionContext = struct {
    user_id: u32,
    repository_id: ?u32,
    organization_id: ?u32,
    team_id: ?u32,
    request_id: []const u8, // For request-level caching
    client_ip: ?[]const u8,
    user_agent: ?[]const u8,
};

// 🆕 Team management structures
const TeamManager = struct {
    pub fn getTeamHierarchy(self: *TeamManager, allocator: std.mem.Allocator, team_id: u32) !TeamHierarchy;
    pub fn resolveInheritedPermissions(self: *TeamManager, allocator: std.mem.Allocator, team_path: []u32) ![]UnitPermission;
    pub fn validateTeamAccess(self: *TeamManager, allocator: std.mem.Allocator, user_id: u32, team_id: u32) !bool;
};

const OrganizationManager = struct {
    pub fn getOrgDefaultPermissions(self: *OrganizationManager, allocator: std.mem.Allocator, org_id: u32) ![]UnitPermission;
    pub fn getUserOrgMembership(self: *OrganizationManager, allocator: std.mem.Allocator, user_id: u32, org_id: u32) !?OrganizationMembership;
    pub fn checkOrgVisibilityRules(self: *OrganizationManager, allocator: std.mem.Allocator, org_id: u32, user_context: UserContext) !bool;
};
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach. Use real database for all tests. Run `zig build && zig build test` after EVERY change.

**CRITICAL**: Zero tolerance for test failures. Any failing tests indicate YOU caused a regression.

<phase_1>
<title>Phase 1: 🆕 Enterprise Permission Foundation with Unit-Level Access (TDD)</title>

1. **Create enhanced permission module structure**
   ```bash
   mkdir -p src/auth
   touch src/auth/permissions.zig
   touch src/auth/teams.zig
   touch src/auth/units.zig
   touch src/auth/organizations.zig
   ```

2. **🆕 Write tests for multi-tier permission architecture**
   ```zig
   test "RepositoryPermission hierarchy with unit-level access" {
       try testing.expect(RepositoryPermission.read.canRead());
       try testing.expect(!RepositoryPermission.read.canWrite());
       try testing.expect(!RepositoryPermission.read.canAdmin());
       
       try testing.expect(RepositoryPermission.write.canRead());
       try testing.expect(RepositoryPermission.write.canWrite());
       try testing.expect(!RepositoryPermission.write.canAdmin());
       
       try testing.expect(RepositoryPermission.admin.canRead());
       try testing.expect(RepositoryPermission.admin.canWrite());
       try testing.expect(RepositoryPermission.admin.canAdmin());
   }
   
   test "UnitPermission validates access modes correctly" {
       const issues_write = UnitPermission{
           .unit_type = .issues,
           .access_mode = .write,
       };
       
       try testing.expect(issues_write.canRead());
       try testing.expect(issues_write.canWrite());
       try testing.expect(!issues_write.canAdmin());
       
       const releases_admin = UnitPermission{
           .unit_type = .releases,
           .access_mode = .admin,
       };
       
       try testing.expect(releases_admin.canRead());
       try testing.expect(releases_admin.canWrite());
       try testing.expect(releases_admin.canAdmin());
   }
   
   test "OrganizationRole inheritance patterns" {
       try testing.expect(OrganizationRole.owner.inheritsFrom(.admin));
       try testing.expect(OrganizationRole.admin.inheritsFrom(.member));
       try testing.expect(!OrganizationRole.member.inheritsFrom(.admin));
   }
   
   test "TeamPermission with inheritance validation" {
       const parent_team_permission = TeamPermission.admin;
       const child_team_permission = TeamPermission.write;
       
       const effective_permission = TeamPermission.resolve(parent_team_permission, child_team_permission);
       try testing.expectEqual(TeamPermission.admin, effective_permission); // Parent wins
   }
   ```

3. **🆕 Implement multi-tier permission enums with unit awareness**
4. **🆕 Add team permission inheritance logic**
5. **🆕 Create organization role hierarchy system**

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
2. **🆕 Enterprise Features**: Organization/team support, unit-level permissions, visibility patterns
3. **🆕 Performance**: Sub-millisecond permission checks with request-level caching
4. **🆕 Team Management**: Full team hierarchy support with permission inheritance
5. **🆕 Unit-Level Control**: Fine-grained access control for all repository features
6. **Security**: Comprehensive access control with no bypass vulnerabilities
7. **Integration**: Seamless integration with SSH, HTTP Git servers, and API endpoints
8. **Scalability**: Support for thousands of organizations, teams, and repositories
9. **🆕 Advanced Caching**: Request-level caching with cascade invalidation
10. **🆕 Audit Compliance**: Multi-tier audit trails with organization-level reporting
11. **Memory safety**: Zero memory leaks in all operations
12. **🆕 Production Ready**: Battle-tested patterns from Gitea's production environment

</success_criteria>

</quality_assurance>

<reference_implementations>

**🆕 Enhanced with Gitea Production Patterns:**
- [🆕 Gitea Organization Management](https://github.com/go-gitea/gitea/blob/main/models/organization/org.go)
- [🆕 Gitea Team Permissions](https://github.com/go-gitea/gitea/blob/main/models/organization/team.go)
- [🆕 Gitea Unit-Level Access Control](https://github.com/go-gitea/gitea/blob/main/models/unit/unit.go)
- [🆕 Gitea Permission Resolution](https://github.com/go-gitea/gitea/blob/main/models/perm/access.go)
- [🆕 Gitea Repository Visibility](https://github.com/go-gitea/gitea/blob/main/models/repo/repo.go)
- [🆕 Gitea Permission Caching](https://github.com/go-gitea/gitea/blob/main/modules/cache/)
- **GitHub permissions**: Repository collaborators and organization teams
- **GitLab permissions**: Project members and group access levels
- **Enterprise RBAC patterns**: Multi-tier access control implementations

**🆕 Key Gitea Patterns Implemented:**
- Organization/team hierarchies with permission inheritance
- Unit-level permissions for fine-grained feature control
- Complex visibility patterns with organization-specific rules
- Request-level permission caching with cascade invalidation
- Team-based repository access with bulk operations
- Comprehensive audit trails with organization-level reporting

</reference_implementations>