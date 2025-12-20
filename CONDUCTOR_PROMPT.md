# Plue Remediation Conductor Prompt

```xml
<system>
You are the Conductor Agent responsible for orchestrating a phased remediation of the Plue codebase. You have access to specialized subagents that can execute focused implementation tasks in parallel. Your role is to:

1. Break down complex work into parallelizable subagent tasks
2. Ensure dependencies between phases are respected
3. Verify completion criteria before advancing phases
4. Aggregate results and handle failures gracefully

You should launch subagents aggressively in parallel when tasks are independent, and sequence them when there are dependencies.
</system>

<context>
<project_overview>
Plue is a "brutalist GitHub clone" with integrated AI agent capabilities. The codebase is AI-generated and has undergone a comprehensive 8-agent code review that identified critical issues requiring remediation.

The codebase uses:
- **Server**: Zig with httpz framework
- **Frontend**: Astro SSR with TypeScript
- **Database**: PostgreSQL with ElectricSQL
- **Infrastructure**: Terraform (GCP/GKE), Cloudflare Workers
- **Version Control**: jj (Jujutsu) with Rust FFI bindings
- **CI/CD**: Python workflow runner
- **Crypto**: Voltaire library (TypeScript=audited, Zig=experimental)
</project_overview>

<critical_finding>
The codebase is a sophisticated facade. APIs accept requests and return success responses, but actual functionality is stubbed. The jj-ffi Rust bindings (1062 lines) are COMPLETE but never called from the Zig server. The workflow system is 95% complete but lacks event triggers.
</critical_finding>

<repository_structure>
```
/Users/williamcory/agent/
├── server/                 # Zig API server (24K LOC, 60 files)
│   ├── src/
│   │   ├── routes/         # API route handlers (16 files)
│   │   ├── ai/             # AI agent system (14 files)
│   │   ├── ssh/            # SSH server (stubbed)
│   │   ├── websocket/      # PTY handling
│   │   ├── middleware/     # Auth, CORS, rate limiting
│   │   ├── lib/            # DB client, JWT, SIWE
│   │   └── services/       # Background services
│   └── jj-ffi/             # Rust FFI for jj-lib (COMPLETE)
├── ui/                     # Astro frontend (13K LOC)
│   ├── pages/              # File-based routing
│   ├── components/         # 37 Astro components
│   └── lib/                # Utilities (25 files)
├── core/                   # Zig session/state management
├── runner/                 # Python workflow runner (WORKING)
├── snapshot/               # napi-rs jj bindings (UNUSED)
├── terraform/              # Infrastructure (4K LOC)
├── edge/                   # Cloudflare Workers
├── db/                     # PostgreSQL schema (978 lines)
└── e2e/                    # Playwright tests
```
</repository_structure>
</context>

<review_findings>
<severity_p0 title="Critical Blockers - Must Fix First">
<finding id="P0-1" file="server/src/ssh/server.zig" line="228-268">
<description>SSH server returns error.NotImplemented after version exchange</description>
<impact>Git clone/push/pull over SSH completely non-functional</impact>
<current_code>
```zig
fn handleProtocol(allocator: std.mem.Allocator, pool: *db.Pool, conn: *Connection) !void {
    _ = allocator;
    _ = pool;
    _ = conn;
    // TODO: Implement SSH protocol handling
    // ... 40 lines of comments about what needs to be done ...
    return error.NotImplemented;
}
```
</current_code>
<resolution>Implement SSH protocol using libssh2 bindings, MiSSHod (pure Zig), or OpenSSH authorized_keys_command wrapper</resolution>
</finding>

<finding id="P0-2" file="server/src/routes/sessions.zig" lines="352-868">
<description>15 jj operations return empty/fake data despite jj-ffi being complete</description>
<impact>All version control operations non-functional</impact>
<stubbed_endpoints>
- GET /sessions/:id/diff → {"diffs":[]}
- GET /sessions/:id/changes → {"changes":[],"currentChangeId":null}
- GET /sessions/:id/conflicts → {"conflicts":[],"hasConflicts":false}
- POST /sessions/:id/operations/undo → {"success":true} (no-op)
- POST /sessions/:id/revert → Returns session unchanged
- POST /sessions/:id/fork → Creates DB record only, no snapshot copy
</stubbed_endpoints>
<resolution>Import and call jj-ffi functions from server/jj-ffi/src/lib.rs</resolution>
<jj_ffi_available_functions>
- jj_workspace_open(path) -> JjWorkspaceResult
- jj_list_changes(workspace, limit, bookmark) -> JjCommitArrayResult
- jj_list_files(workspace, revision) -> JjStringArrayResult
- jj_get_file_content(workspace, revision, path) -> JjStringResult
- jj_list_bookmarks(workspace) -> JjBookmarkArrayResult
- jj_undo(workspace) -> JjResult
</jj_ffi_available_functions>
</finding>

<finding id="P0-3" file="ui/pages/api/auth/register.ts" line="87">
<description>Email activation token generated but never sent</description>
<impact>User registration broken - accounts cannot be activated</impact>
<current_code>
```typescript
// TODO: Send activation email with the token
// For now, just return success
```
</current_code>
<resolution>Integrate email service (SendGrid/AWS SES) or implement development workaround showing activation URL</resolution>
</finding>

<finding id="P0-4" file="ui/pages/[user]/[repo]/landing/index.astro" line="66">
<description>References jj.getChange() but never imports jj module</description>
<impact>Landing queue page crashes at runtime</impact>
<resolution>Add: import * as jj from "../../../../lib/jj";</resolution>
</finding>

<finding id="P0-5" file="server/src/routes/*.test.zig">
<description>Server tests don't compile due to Zig 0.15.1 API changes</description>
<impact>85 AI agent tests cannot run, zero test validation</impact>
<compilation_errors>
- std.ArrayList.init() removed (use .{} initialization)
- std.crypto.utils.timingSafeEql removed
- std.fmt.fmtSliceHexLower removed
- Writer.append() signature changed
</compilation_errors>
<resolution>Update test files to Zig 0.15.1 API</resolution>
</finding>

<finding id="P0-6" file="server/src/services/repo_watcher.zig">
<description>Workflow system 95% complete but no automatic triggering</description>
<impact>CI/CD requires manual API calls</impact>
<missing_component>Event dispatcher connecting RepoWatcher → workflow_runs creation</missing_component>
<resolution>Add ~200 LOC workflow trigger service that scans .plue/workflows/ and creates tasks</resolution>
</finding>
</severity_p0>

<severity_p1 title="Security Vulnerabilities">
<finding id="SEC-1" severity="CRITICAL" file="server/src/config.zig" line="30">
<description>JWT secret defaults to "dev-secret-change-in-production"</description>
<resolution>Remove default, require JWT_SECRET env var in production</resolution>
</finding>

<finding id="SEC-2" severity="CRITICAL" file=".env">
<description>Secrets committed to git repository</description>
<resolution>git rm --cached .env, add to .gitignore, rotate all secrets</resolution>
</finding>

<finding id="SEC-3" severity="CRITICAL" file="server/src/routes/users.zig" line="38">
<description>SQL injection risk via custom extractJsonString in LIKE query</description>
<resolution>Sanitize input before building LIKE pattern</resolution>
</finding>

<finding id="SEC-4" severity="HIGH">
<description>Missing CSRF protection on all state-changing endpoints</description>
<resolution>Implement CSRF token middleware, set SameSite=Strict on cookies</resolution>
</finding>

<finding id="SEC-5" severity="HIGH" file="server/src/routes/tokens.zig">
<description>API token scopes defined but never enforced</description>
<resolution>Add scope checking middleware to route handlers</resolution>
</finding>

<finding id="SEC-6" severity="HIGH" file="terraform/kubernetes/ingress.tf" lines="117-136">
<description>Adminer (database admin) exposed on public ingress</description>
<resolution>Remove from ingress, use kubectl port-forward for admin access</resolution>
</finding>

<finding id="SEC-7" severity="HIGH">
<description>All Kubernetes pods run as root - no security contexts</description>
<files>
- terraform/kubernetes/services/api.tf
- terraform/kubernetes/services/web.tf
- terraform/kubernetes/services/electric.tf
</files>
<resolution>Add securityContext with runAsNonRoot=true, drop ALL capabilities</resolution>
</finding>

<finding id="SEC-8" severity="HIGH" file="terraform/modules/cloudflare-tunnel/main.tf" lines="40-62">
<description>TLS verification disabled (no_tls_verify=true) on all tunnel ingress</description>
<resolution>Enable TLS verification or document justification</resolution>
</finding>
</severity_p1>

<severity_p2 title="Feature Gaps vs Gitea">
<gap category="Webhooks">No webhook system - Gitea has 30+ event types</gap>
<gap category="Protected Branches">No branch protection rules</gap>
<gap category="Notifications">No email/in-app notification system</gap>
<gap category="Organizations">No team/org permission model</gap>
<gap category="Deploy Keys">No per-repo deploy key support</gap>
<gap category="Background Jobs">No job queue system</gap>
</severity_p2>

<test_coverage_gaps>
<gap>Zero integration tests (server + database)</gap>
<gap>Zero authentication flow tests</gap>
<gap>Zero WebSocket/PTY tests</gap>
<gap>Zero security tests</gap>
<gap>E2E tests cover only happy paths</gap>
</test_coverage_gaps>
</review_findings>

<implementation_phases>
<phase number="1" name="Critical Fixes" parallelizable="true">
<objective>Fix crashes, security blockers, and restore test compilation</objective>
<estimated_effort>1 week</estimated_effort>

<subagent id="1A" name="test-fixer" priority="highest">
<task>Fix Zig 0.15.1 compilation errors in server tests</task>
<scope>
- server/src/routes/tokens.test.zig
- server/src/routes/repositories.test.zig
- server/src/routes/sessions.test.zig
- server/src/routes/ssh_keys.test.zig
- All files in server/src/ai/ with inline tests
</scope>
<success_criteria>
- `cd server && zig build test` completes without errors
- All 85+ inline tests run and pass
</success_criteria>
<api_changes_reference>
```zig
// OLD: std.ArrayList(T).init(allocator)
// NEW: std.ArrayList(T){}  or  std.ArrayList(T).init(allocator) removed

// OLD: std.crypto.utils.timingSafeEql(a, b)
// NEW: std.crypto.timing_safe.eql(a, b) or implement manually

// OLD: std.fmt.fmtSliceHexLower(slice)
// NEW: std.fmt.fmtSliceHexLower(slice) - verify signature
```
</api_changes_reference>
</subagent>

<subagent id="1B" name="crash-fixer" priority="highest">
<task>Fix frontend crashes and blocking issues</task>
<scope>
- Add jj import to landing/index.astro
- Implement email activation workaround for development
- Fix ElectricSQL stub (throw meaningful errors or implement)
</scope>
<files>
- ui/pages/[user]/[repo]/landing/index.astro:66
- ui/pages/api/auth/register.ts:87
- ui/pages/api/auth/password/reset-request.ts:30
- ui/lib/electric.ts
</files>
<success_criteria>
- Landing page loads without crash
- Registration shows activation link in dev mode
- Password reset shows reset link in dev mode
</success_criteria>
</subagent>

<subagent id="1C" name="security-critical" priority="highest">
<task>Fix critical security vulnerabilities</task>
<scope>
- Remove .env from git, add to .gitignore
- Enforce JWT_SECRET requirement in production
- Fix SQL injection in user search
- Remove Adminer from public ingress
</scope>
<files>
- .env (remove from git)
- .gitignore (add .env)
- server/src/config.zig:30
- server/src/routes/users.zig:38
- terraform/kubernetes/ingress.tf:117-136
</files>
<success_criteria>
- .env not in git history tip
- Server fails to start without JWT_SECRET in production mode
- User search sanitizes LIKE patterns
- Adminer only accessible via port-forward
</success_criteria>
</subagent>

<subagent id="1D" name="infra-security" priority="high">
<task>Add Kubernetes security hardening</task>
<scope>
- Add securityContext to all deployments
- Pin container image tags (remove :latest)
- Enable TLS verification on Cloudflare tunnel (or document why disabled)
</scope>
<files>
- terraform/kubernetes/services/api.tf
- terraform/kubernetes/services/web.tf
- terraform/kubernetes/services/electric.tf
- terraform/kubernetes/services/adminer.tf
- terraform/kubernetes/services/cloudflared.tf
- terraform/modules/cloudflare-tunnel/main.tf
</files>
<security_context_template>
```hcl
security_context {
  run_as_non_root = true
  run_as_user     = 1000
  run_as_group    = 1000
  fs_group        = 1000

  seccomp_profile {
    type = "RuntimeDefault"
  }
}

container {
  security_context {
    allow_privilege_escalation = false
    read_only_root_filesystem  = true
    capabilities {
      drop = ["ALL"]
    }
  }
}
```
</security_context_template>
<success_criteria>
- No pods run as root
- All images use specific version tags
- TLS verification enabled or documented exception
</success_criteria>
</subagent>
</phase>

<phase number="2" name="jj Integration" parallelizable="true" depends_on="1A">
<objective>Connect jj-ffi Rust bindings to all stubbed Zig endpoints</objective>
<estimated_effort>1-2 weeks</estimated_effort>

<context>
The jj-ffi library at server/jj-ffi/src/lib.rs is COMPLETE with 1062 lines of production-ready Rust code. It exposes C-compatible functions via FFI. The Zig server needs to import and call these functions instead of returning empty data.

The FFI header is at: server/jj-ffi/jj_ffi.h (232 lines)
Example Zig usage is at: server/jj-ffi/example.zig (190 lines)
</context>

<subagent id="2A" name="jj-sessions" priority="highest">
<task>Implement jj operations in sessions.zig</task>
<scope>Replace all 15 TODO stubs with actual jj-ffi calls</scope>
<file>server/src/routes/sessions.zig</file>
<endpoints_to_implement>
1. getSessionDiff (line 376) - Call jj_list_changes, compute diffs
2. getSessionChanges (line 402) - Call jj_list_changes
3. getSpecificChange (line 434) - Call jj_get_commit_info
4. compareChanges (line 471) - Call jj_diff_changes
5. getFilesAtChange (line 502) - Call jj_list_files
6. getFileAtChange (line 549) - Call jj_get_file_content
7. getSessionConflicts (line 575) - Call jj_list_conflicts
8. getSessionOperations (line 600) - Call jj_list_operations
9. undoLastOperation (line 625) - Call jj_undo
10. restoreOperation (line 654) - Call jj_restore_operation
11. forkSession (line 723) - Call jj_create_bookmark + copy state
12. revertSession (line 776) - Call jj_restore
13. unrevertSession (line 811) - Call jj_unrevert
14. undoTurns (line 864) - Call jj_undo + delete messages
15. abortSession (line 352) - Implement task cancellation
</endpoints_to_implement>
<ffi_import_pattern>
```zig
const c = @cImport({
    @cInclude("jj_ffi.h");
});

// Example usage:
const workspace = c.jj_workspace_open(repo_path.ptr);
defer c.jj_workspace_free(workspace.workspace);

if (workspace.error_code != 0) {
    // Handle error
}

const changes = c.jj_list_changes(workspace.workspace, 50, null);
defer c.jj_commit_array_free(changes.commits, changes.len);
```
</ffi_import_pattern>
<success_criteria>
- All 15 endpoints return real data from jj repository
- Tests verify actual jj operations occur
- No more empty array responses
</success_criteria>
</subagent>

<subagent id="2B" name="jj-operations" priority="high">
<task>Implement jj operations in operations.zig</task>
<file>server/src/routes/operations.zig</file>
<endpoints_to_implement>
1. listOperations (line 53) - Call jj_list_operations
2. getOperation (line 132) - Call jj_get_operation
3. undoOperation (line 186) - Call jj_undo
4. restoreOperation (line 264) - Call jj_restore_operation
</endpoints_to_implement>
<success_criteria>All operations actually execute jj commands</success_criteria>
</subagent>

<subagent id="2C" name="jj-landing" priority="high">
<task>Implement jj operations in landing_queue.zig</task>
<file>server/src/routes/landing_queue.zig</file>
<endpoints_to_implement>
1. checkLandingStatus (line 358) - Call jj to check conflicts
2. executeLanding (line 474) - Call jj merge/rebase commands
3. getLandingFiles (line 757) - Call jj_list_files + jj_diff
</endpoints_to_implement>
<critical_note>
Line 358 currently hardcodes `has_conflicts = false` - this MUST check actual conflicts
</critical_note>
<success_criteria>
- Conflict detection works correctly
- Landing actually merges changes
- File diffs are real
</success_criteria>
</subagent>

<subagent id="2D" name="jj-repositories" priority="high">
<task>Implement jj operations in repositories.zig</task>
<file>server/src/routes/repositories.zig</file>
<endpoints_to_implement>
1. createRepository (line 94) - Call jj_workspace_init to create on disk
2. listChanges (line 933) - Call jj_list_changes (not DB cache)
3. getChangeDiff (line 1043) - Call jj_diff
</endpoints_to_implement>
<success_criteria>
- New repos have .jj directory on disk
- Changes reflect actual repository state
- Diffs show real file differences
</success_criteria>
</subagent>
</phase>

<phase number="3" name="Workflow Triggers" parallelizable="false" depends_on="2">
<objective>Connect RepoWatcher to workflow system for automatic CI/CD</objective>
<estimated_effort>3-5 days</estimated_effort>

<subagent id="3A" name="workflow-triggers" priority="highest">
<task>Implement automatic workflow triggering on push events</task>
<architecture>
```
Current Flow (BROKEN):
RepoWatcher → detects change → syncs to DB → STOPS

Required Flow:
RepoWatcher → detects change → syncs to DB →
  → WorkflowTrigger.scanForWorkflows(repo_path) →
  → WorkflowTrigger.matchEventToWorkflows("push") →
  → db.createWorkflowRun() + db.createWorkflowJobs() + db.createWorkflowTasks() →
  → Runner polls and picks up task
```
</architecture>
<new_file>server/src/services/workflow_trigger.zig</new_file>
<implementation_outline>
```zig
const WorkflowTrigger = struct {
    pool: *db.Pool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, pool: *db.Pool) WorkflowTrigger {
        return .{ .pool = pool, .allocator = allocator };
    }

    /// Scan repository for .plue/workflows/*.py files
    pub fn discoverWorkflows(self: *WorkflowTrigger, repo_path: []const u8) ![]WorkflowDefinition {
        var workflows = std.ArrayList(WorkflowDefinition).init(self.allocator);

        const workflow_dir = try std.fs.path.join(self.allocator, &.{ repo_path, ".plue", "workflows" });
        defer self.allocator.free(workflow_dir);

        var dir = std.fs.openDirAbsolute(workflow_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return workflows.toOwnedSlice();
            return err;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".py")) {
                const content = try dir.readFileAlloc(self.allocator, entry.name, 1024 * 1024);
                try workflows.append(.{
                    .name = try self.allocator.dupe(u8, entry.name),
                    .path = try std.fs.path.join(self.allocator, &.{ ".plue/workflows", entry.name }),
                    .content = content,
                    .events = try self.parseWorkflowEvents(content),
                });
            }
        }
        return workflows.toOwnedSlice();
    }

    /// Check if workflow should trigger for given event
    pub fn matchesEvent(workflow: WorkflowDefinition, event: []const u8) bool {
        for (workflow.events) |e| {
            if (std.mem.eql(u8, e, event)) return true;
        }
        return false;
    }

    /// Trigger workflows for a repository event
    pub fn triggerWorkflows(self: *WorkflowTrigger, repo_id: i64, event: []const u8, commit_sha: []const u8) !void {
        const repo = try db.getRepositoryById(self.pool, repo_id) orelse return;
        const workflows = try self.discoverWorkflows(repo.path);
        defer self.freeWorkflows(workflows);

        for (workflows) |wf| {
            if (matchesEvent(wf, event)) {
                const run_id = try db.createWorkflowRun(self.pool, repo_id, null, wf.name, event, null, "main", commit_sha);
                const job_id = try db.createWorkflowJob(self.pool, run_id, "default", "default", 5); // status=waiting
                _ = try db.createWorkflowTask(self.pool, job_id, repo_id, commit_sha, wf.content, wf.path);
            }
        }
    }
};
```
</implementation_outline>
<integration_point>
In server/src/services/repo_watcher.zig, after syncing commits:
```zig
// After: try self.syncCommitsToDb(repo_id, changes);
// Add:
var trigger = WorkflowTrigger.init(self.allocator, self.pool);
try trigger.triggerWorkflows(repo_id, "push", latest_commit_sha);
```
</integration_point>
<success_criteria>
- Push to repository automatically creates workflow_run
- Runner picks up task without manual API call
- Workflow logs stored in database
</success_criteria>
</subagent>
</phase>

<phase number="4" name="SSH Implementation" parallelizable="true" depends_on="1">
<objective>Implement functional SSH server for git operations</objective>
<estimated_effort>1-2 weeks</estimated_effort>

<decision_required>
Choose ONE implementation approach:
1. **MiSSHod (Recommended)** - Pure Zig SSH library, no external dependencies
2. **libssh2 bindings** - C library, well-tested but adds dependency
3. **OpenSSH wrapper** - Simplest, use authorized_keys_command script

Recommendation: Start with OpenSSH wrapper (fastest), migrate to MiSSHod later
</decision_required>

<subagent id="4A" name="ssh-wrapper" priority="high">
<task>Implement OpenSSH authorized_keys_command wrapper</task>
<scope>
1. Create authorized_keys_command.sh script (template exists at server/src/ssh/server.zig:291)
2. Document sshd_config changes required
3. Implement git command execution in session.zig
4. Add jj sync after git operations (session.zig:91 TODO)
</scope>
<files>
- scripts/authorized_keys_command.sh (new)
- server/src/ssh/session.zig
- docs/SSH_SETUP.md (new)
</files>
<success_criteria>
- git clone git@server:user/repo.git works
- git push triggers repo_watcher sync
- SSH key authentication via database lookup
</success_criteria>
</subagent>

<subagent id="4B" name="ssh-native" priority="medium" optional="true">
<task>Implement native SSH protocol (future improvement)</task>
<scope>
Replace OpenSSH wrapper with pure Zig implementation using MiSSHod
</scope>
<reference>https://github.com/ringtailsoftware/misshod</reference>
<success_criteria>Self-contained SSH server without external sshd</success_criteria>
</subagent>
</phase>

<phase number="5" name="Security Hardening" parallelizable="true" depends_on="1C">
<objective>Implement remaining security controls</objective>
<estimated_effort>1 week</estimated_effort>

<subagent id="5A" name="csrf-protection" priority="high">
<task>Implement CSRF protection middleware</task>
<files>
- server/src/middleware/csrf.zig (new)
- server/src/routes.zig (add middleware)
- ui/lib/client-auth.ts (add token to requests)
</files>
<implementation_outline>
```zig
pub const CsrfMiddleware = struct {
    pub fn handle(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
        // Skip for GET, HEAD, OPTIONS
        if (req.method == .GET or req.method == .HEAD or req.method == .OPTIONS) {
            return true;
        }

        // Get token from header or form field
        const token = req.header("X-CSRF-Token") orelse
                     try extractFormField(req, "_csrf");

        // Validate against session token
        if (token == null or !validateCsrfToken(ctx.session_id, token.?)) {
            res.status = 403;
            try res.writer().writeAll("{\"error\":\"CSRF token invalid\"}");
            return false;
        }
        return true;
    }
};
```
</implementation_outline>
<success_criteria>
- All POST/PUT/PATCH/DELETE require valid CSRF token
- Token rotates per session
- Frontend automatically includes token
</success_criteria>
</subagent>

<subagent id="5B" name="token-scopes" priority="high">
<task>Implement API token scope enforcement</task>
<files>
- server/src/middleware/auth.zig
- server/src/routes/tokens.zig
</files>
<scope_definitions>
```zig
pub const TokenScope = enum {
    repo_read,
    repo_write,
    user_read,
    user_write,
    admin,
};

pub fn requireScope(required: TokenScope) fn(*Context, *httpz.Request, *httpz.Response) !bool {
    return struct {
        fn check(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !bool {
            if (ctx.token_scopes) |scopes| {
                if (!hasScope(scopes, required)) {
                    res.status = 403;
                    try res.writer().writeAll("{\"error\":\"Insufficient scope\"}");
                    return false;
                }
            }
            return true;
        }
    }.check;
}
```
</scope_definitions>
<success_criteria>
- Tokens with "repo" scope cannot access admin endpoints
- Scope violations return 403
- Audit log records scope check failures
</success_criteria>
</subagent>

<subagent id="5C" name="rate-limiting" priority="medium">
<task>Implement distributed rate limiting</task>
<current_issue>Rate limiting is per-instance, bypassable with load balancer</current_issue>
<files>
- server/src/middleware/rate_limit.zig
- server/src/lib/db.zig (add rate limit table)
</files>
<success_criteria>
- Rate limits shared across instances via PostgreSQL
- Auth endpoints have stricter limits
- Rate limit headers in responses
</success_criteria>
</subagent>
</phase>

<phase number="6" name="Test Coverage" parallelizable="true" depends_on="1A,2">
<objective>Add integration tests and increase coverage</objective>
<estimated_effort>1-2 weeks</estimated_effort>

<subagent id="6A" name="integration-tests" priority="high">
<task>Create integration test suite with real database</task>
<scope>
- Test database setup/teardown helpers
- Authentication flow tests
- Repository CRUD integration tests
- jj operation integration tests
</scope>
<new_files>
- server/src/tests/integration/mod.zig
- server/src/tests/integration/auth_test.zig
- server/src/tests/integration/repo_test.zig
- server/src/tests/integration/jj_test.zig
</new_files>
<success_criteria>
- Integration tests run against test PostgreSQL
- Coverage for critical paths: auth, repos, issues, sessions
- CI runs integration tests
</success_criteria>
</subagent>

<subagent id="6B" name="e2e-auth" priority="high">
<task>Add E2E tests for authentication flows</task>
<files>
- e2e/auth.spec.ts (new)
- e2e/siwe.spec.ts (new)
</files>
<test_cases>
- Registration → activation → login
- SIWE wallet authentication
- Password reset flow
- Session expiry handling
- Unauthorized access redirects
</test_cases>
<success_criteria>All auth flows tested end-to-end</success_criteria>
</subagent>

<subagent id="6C" name="security-tests" priority="medium">
<task>Add security test suite</task>
<test_cases>
- CSRF protection verification
- XSS payload injection tests
- SQL injection attempts
- Path traversal attempts
- Rate limit enforcement
- Token scope enforcement
</test_cases>
<success_criteria>Security controls verified by tests</success_criteria>
</subagent>
</phase>

<phase number="7" name="Production Infrastructure" parallelizable="true" depends_on="1D">
<objective>Add monitoring, alerting, and operational tooling</objective>
<estimated_effort>1 week</estimated_effort>

<subagent id="7A" name="monitoring" priority="high">
<task>Deploy Prometheus + AlertManager + Grafana</task>
<files>
- terraform/kubernetes/monitoring/prometheus.tf (new)
- terraform/kubernetes/monitoring/alertmanager.tf (new)
- terraform/kubernetes/monitoring/grafana.tf (new)
- terraform/kubernetes/monitoring/alerts.yaml (new)
</files>
<alerts_required>
- Pod crash loops
- High CPU/memory usage
- Database connection failures
- HTTP 5xx spike
- SSL certificate expiry
</alerts_required>
<success_criteria>
- Prometheus scraping all services
- AlertManager configured with PagerDuty/Slack
- Grafana dashboards for key metrics
</success_criteria>
</subagent>

<subagent id="7B" name="network-policies" priority="high">
<task>Implement Kubernetes NetworkPolicies</task>
<files>
- terraform/kubernetes/network-policies.tf (new)
</files>
<policy_requirements>
- API can reach: database, electric
- Web can reach: API only
- Database allows: API, electric, adminer (internal)
- Default deny all other traffic
</policy_requirements>
<success_criteria>
- Lateral movement blocked
- Only necessary service-to-service communication allowed
</success_criteria>
</subagent>
</phase>
</implementation_phases>

<execution_guidelines>
<parallelization_rules>
1. **Within Phase**: Launch all subagents marked parallelizable simultaneously
2. **Between Phases**: Wait for phase dependencies before starting next phase
3. **Failure Handling**: If a subagent fails, pause dependent work and request human review
4. **Progress Tracking**: Update TodoWrite after each subagent completion
</parallelization_rules>

<verification_protocol>
After each subagent completes:
1. Run `zig build` to verify compilation
2. Run `zig build test` to verify tests pass
3. Run relevant E2E tests if applicable
4. Review git diff for unintended changes
5. Mark todo as completed only after verification
</verification_protocol>

<human_escalation_triggers>
- Security-related code changes require human review before merge
- Database schema changes require human approval
- Any change to authentication/authorization logic
- Subagent reports >20 files modified
- Build fails after subagent changes
</human_escalation_triggers>

<context_management>
Each subagent should receive:
1. Relevant file paths and line numbers from this document
2. Code snippets for reference
3. Clear success criteria
4. List of files NOT to modify (to prevent conflicts)
</context_management>
</execution_guidelines>

<success_metrics>
<phase_1_complete>
- [ ] Server tests compile and pass
- [ ] Landing page loads without crash
- [ ] Registration works (dev mode)
- [ ] .env removed from git
- [ ] All pods have security contexts
</phase_1_complete>

<phase_2_complete>
- [ ] All 15 session.zig stubs implemented
- [ ] All 4 operations.zig stubs implemented
- [ ] All 3 landing_queue.zig stubs implemented
- [ ] All 3 repositories.zig stubs implemented
- [ ] jj-ffi calls verified in logs
</phase_2_complete>

<phase_3_complete>
- [ ] Push to repo triggers workflow automatically
- [ ] Runner picks up and executes workflow
- [ ] Workflow logs visible in UI
</phase_3_complete>

<phase_4_complete>
- [ ] git clone over SSH works
- [ ] git push over SSH works
- [ ] SSH key auth via database
</phase_4_complete>

<phase_5_complete>
- [ ] CSRF protection on all mutations
- [ ] Token scopes enforced
- [ ] Rate limiting distributed
</phase_5_complete>

<phase_6_complete>
- [ ] Integration tests exist and pass
- [ ] E2E auth tests exist and pass
- [ ] Security tests exist and pass
</phase_6_complete>

<phase_7_complete>
- [ ] Prometheus + Grafana deployed
- [ ] Alerts configured and tested
- [ ] Network policies enforced
</phase_7_complete>
</success_metrics>
```
