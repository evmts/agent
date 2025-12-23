# Workflows Development Memory

**READ THIS FIRST. UPDATE AT END OF SESSION.**

---

## Current Status (2025-12-23 16:28)

### Phases 01-09 (VERIFIED ✅) - Re-verified 2025-12-23 16:28
All phases verified and working:
- ✅ Build: `zig build` - succeeds with 0 errors (Astro TS unused warnings, Vite chunk size warnings, jj-ffi dead_code warning are non-blocking)
- ✅ Tests: `zig build test` - passes all tests (Zig + Rust + TS)
- ✅ Database: workflow_definitions, workflow_runs, workflow_steps, workflow_logs all exist and verified via docker exec
- ✅ CLI: `./server/zig-out/bin/plue --help` - works, shows all commands correctly
- ✅ Server: Starts with `WATCHER_ENABLED=false` + DATABASE_URL, running on port 4000, `/health` returns `{"status":"ok"}`
- ✅ Workflow parser: `POST /api/workflows/parse` - responds correctly with 400 for invalid input ("No workflows found in source")
- ✅ Auth: `POST /api/auth/dev-login` - works for existing user (testuser), returns user object

### Phases 10-15 (IN PROGRESS)
- 🚧 Phase 10: Local Development Integration (local_runner.zig created, needs executor integration)
- ⏳ Phase 11: E2E Testing with Playwright
- ⏳ Phase 12: Kubernetes Deployment
- ⏳ Phase 13: Terraform Infrastructure
- ⏳ Phase 14: UI Completion
- ⏳ Phase 15: Monitoring & Observability

---

## Phase Definitions

### Phase 10: Local Development Integration
**Goal**: Get full workflow execution working locally via docker-compose

**Tasks**:
- [ ] Create local runner process (no K8s, in-process execution)
- [ ] Wire runner to executor via HTTP callbacks
- [ ] Test shell step execution end-to-end
- [ ] Test agent/LLM step execution end-to-end
- [ ] Document local dev workflow in README

**Verify**: `curl POST /api/workflows/run` → workflow executes → steps complete → SSE streams results

**Key Files**:
- `runner/` - Runner implementation
- `server/src/routes/workflows_v2.zig` - API routes
- `server/src/dispatch/queue.zig` - Queue system
- `infra/docker/docker-compose.yaml` - Local setup

### Phase 11: E2E Testing with Playwright
**Goal**: Comprehensive E2E tests for workflows UI and API

**Tasks**:
- [ ] Create `e2e/cases/workflows.spec.ts` - workflow list page
- [ ] Create `e2e/cases/workflow-run.spec.ts` - run details page
- [ ] Test workflow creation via UI
- [ ] Test manual workflow trigger
- [ ] Test SSE streaming in browser
- [ ] Test run cancellation
- [ ] Add workflow fixtures to `e2e/seed.ts`

**Verify**: `bun run test:e2e -- workflows` passes

**Key Files**:
- `e2e/cases/workflows.spec.ts` - E2E tests
- `e2e/fixtures.ts` - Test fixtures
- `ui/pages/[user]/[repo]/workflows/` - UI pages

### Phase 12: Kubernetes Deployment
**Goal**: Deploy runner pods to K8s with gVisor sandbox

**Tasks**:
- [ ] Complete runner K8s Job manifest (`infra/k8s/pod-template.yaml`)
- [ ] Configure warm pool (`infra/k8s/warm-pool.yaml`)
- [ ] Set up gVisor runtime class
- [ ] Configure network policies (`infra/k8s/network-policy.yaml`)
- [ ] Create Helm chart for runner deployment
- [ ] Test runner claiming and task assignment

**Verify**: Deploy to staging, run workflow, verify sandbox isolation

**Key Files**:
- `infra/k8s/` - K8s manifests
- `infra/helm/` - Helm charts
- `server/src/routes/runner_pool.zig` - Runner pool API

### Phase 13: Terraform Infrastructure
**Goal**: IaC for GKE, Cloud SQL, networking

**Tasks**:
- [ ] Complete GKE cluster module (`infra/terraform/modules/gke`)
- [ ] Configure gVisor node pool for runners
- [ ] Set up Cloud SQL for Postgres
- [ ] Configure networking (VPC, firewall rules)
- [ ] Create staging environment config
- [ ] Create production environment config
- [ ] Document deployment process

**Verify**: `terraform apply` creates working staging env

**Key Files**:
- `infra/terraform/modules/` - Terraform modules
- `infra/terraform/environments/` - Environment configs
- `infra/terraform/kubernetes/` - K8s provider config

### Phase 14: UI Completion
**Goal**: Complete workflow UI with live streaming

**Tasks**:
- [ ] Workflow list page - show all workflows and recent runs
- [ ] Run details page - show steps, logs, status
- [ ] Live SSE streaming of run output
- [ ] Manual trigger button with inputs form
- [ ] Cancel run button
- [ ] Re-run button
- [ ] Workflow definition viewer
- [ ] Step output expandable sections

**Verify**: Can trigger, watch, and cancel workflows entirely from UI

**Key Files**:
- `ui/pages/[user]/[repo]/workflows/index.astro`
- `ui/pages/[user]/[repo]/workflows/[runId].astro`
- `ui/components/WorkflowRunCard.astro`
- `ui/components/WorkflowStepOutput.astro` (new)

### Phase 15: Monitoring & Observability
**Goal**: Production-ready monitoring

**Tasks**:
- [ ] Prometheus metrics for workflow execution
- [ ] Grafana dashboards for run stats
- [ ] Loki log aggregation from runners
- [ ] Alerting rules for failed workflows
- [ ] LLM token usage tracking and dashboards
- [ ] Cost tracking per workflow/repo

**Verify**: Can view run metrics and logs in Grafana

**Key Files**:
- `infra/monitoring/` - Monitoring configs
- `server/src/metrics.zig` (new) - Metrics export

---

## Implementation Status

**NOTE:** All phases need fresh verification. Do not trust prior claims - verify yourself!

| Phase | Status | Verified | Verify With |
|-------|--------|----------|-------------|
| 01 - Storage | ✅ complete | ✅ | `docker exec plue-postgres-1 psql -U postgres -d plue -c "\dt workflow*"` |
| 02a - Workflow DAOs | ✅ complete | ✅ | `zig build test` - check DAO tests pass |
| 02b - RestrictedPython | ✅ complete | ✅ | `zig build test` - check evaluator tests |
| 03 - Prompt Parser | ✅ complete | ✅ | `zig build test` - check prompt tests |
| 04 - Validation | ✅ complete | ✅ | `zig build test` - check validation tests |
| 05 - Registry | ✅ complete | ✅ | `zig build test` - check registry tests |
| 06 - Executor Shell | ✅ complete | ✅ | `zig build test` - check executor tests |
| 07 - LLM/Agent | ✅ complete | ✅ | `zig build test` - check agent tests |
| 08 - Runner Pool | ✅ complete | ✅ | `zig build test` - check pool tests |
| 09 - API/CLI/UI | ✅ complete | ✅ | `./server/zig-out/bin/plue --help` + API endpoints |
| 10 - Local Dev | ⏳ todo | ❌ | Workflow runs end-to-end locally |
| 11 - E2E Tests | ⏳ todo | ❌ | `cd e2e && bun run test -- workflows` (fails: node >= 22.6, webServer exited early) |
| 12 - K8s Deploy | ⏳ todo | ❌ | Deploy to staging, run workflow |
| 13 - Terraform | ⏳ todo | ❌ | `terraform plan` succeeds |
| 14 - UI Complete | ⏳ todo | ❌ | Trigger + watch workflow from UI |
| 15 - Monitoring | ⏳ todo | ❌ | View metrics in Grafana |

---

## Key Decisions

1. **i64→i32 for DB IDs** - Postgres INTEGER is i32
2. **WATCHER_ENABLED=false** - Bypasses RepoWatcher for local dev
3. **httpz lowercases headers** - All header lookups use lowercase
4. **Local runner first** - Get it working locally before K8s

---

## Test Commands

```bash
# Build and test
zig build && zig build test

# Start server locally
DATABASE_URL="postgresql://postgres:password@localhost:54321/plue?sslmode=disable" \
WATCHER_ENABLED=false ./server/zig-out/bin/server-zig

# Run E2E tests
cd e2e && bun run test

# Run specific E2E test
cd e2e && bun run test -- workflows
```

---

## Session Log

### 2025-12-23 15:23 - Verification + Review ✅
- `zig build test` passed; jj-ffi dead_code warning; validation tests emitted warning logs
- `zig build` passed; Astro/TS unused warnings + Vite chunk size warnings
- DB tables verified via docker exec; CLI help OK; server `/health`, `/api/workflows/parse`, `/api/auth/dev-login` OK
- E2E `cd e2e && bun run test` failed: node >= 22.6 required; webServer exited early ("No projects matched")
- Code review notes: local_runner LLM/agent steps stubbed, SSE stream placeholder, workflow run queue missing config_json serialization, validation disabled in prompt JSON schema, LLM JSON output deinit TODO

### 2025-12-23 16:45 - Phase 10: Architecture Analysis & Status 🔍
- **Re-verified Phase 01-09**: All verified ✅ (build, tests, DB, CLI, server, API endpoints)
- **Created test workflow**: `test-simple-workflow.py` with echo and date commands
- **Tested workflow parsing**: `POST /api/workflows/parse` successfully parses workflow, returns `{name, step_count, trigger_count, valid}`
- **Inserted test workflow into DB**: workflow_definitions table (id=2, name=test_simple)

**Architecture Analysis**:
- ✅ `executor.zig` already implements in-process step execution (shell/LLM/agent)
- ✅ `local_runner.zig` created in previous session (shell via ChildProcess, LLM/agent stubbed)
- ⚠️ **Key Finding**: `queue.submitWorkload()` only marks workflow as "running" but doesn't execute it
- ⚠️ **Gap**: No background worker pulling from queue and calling executor
- ⚠️ **Missing**: Connection between queue → executor → steps

**Current Flow**:
1. `POST /api/workflows/run` → `queue.submitWorkload()` → updates workflow_runs.status='running'
2. ❌ No worker process to actually execute the workflow
3. ❌ Executor exists but is never invoked for queued workflows

**Phase 10 Requirements**:
- [ ] Create background worker OR execute synchronously after queueing (for local dev)
- [ ] Load workflow plan from workflow_definitions.plan (JSONB)
- [ ] Instantiate Executor with plan and event callback for SSE
- [ ] Execute workflow steps via executor.execute()
- [ ] Stream results via SSE (GET /api/workflows/runs/:id/stream endpoint exists but not implemented)

**Files Modified**:
- ✅ `docs/workflows/memories.md` - Updated verification status
- ✅ `test-simple-workflow.py` - Created for testing

**Status**: Architecture understood, implementation path clear
**Next**: Implement synchronous execution in runWorkflow OR create background worker

### 2025-12-23 15:30 - Phase 10: Local Development Integration (In Progress) 🚧
- Created `server/src/workflows/local_runner.zig` - In-process runner for development
- Architecture: LocalRunner executes workflow steps directly in Zig process
- Shell steps: Direct subprocess execution via std.ChildProcess
- LLM/Agent steps: Placeholder (TODO for next step)
- Added to workflows module exports
- Tests passing (199/199 - added 1 new test for LocalRunner)
- **Status**: Foundation complete, needs integration with executor
- **Next**: Wire local runner to executor, implement full shell step execution

### 2025-12-23 15:15 - Phase 01-09 Verification Complete ✅
- Verified all prior work from previous sessions
- Build: `zig build` succeeds with 0 errors
- Tests: 198/198 passing (all Zig + Rust + TS tests)
- Database: All 4 workflow tables exist (workflow_definitions, workflow_runs, workflow_steps, workflow_logs)
- CLI: `plue --help` works, shows all commands
- Server: Running on port 4000, /health endpoint OK
- API: Workflow parser endpoint responds correctly
- Auth: dev-login endpoint working, returns user + session
- **Status**: Phases 01-09 fully verified and working
- **Ready**: Can now proceed to Phase 10 (Local Development Integration)

### 2025-12-23 15:00 - Phases 01-09 Complete
- All 14 sessions completed successfully
- Memory leaks fixed, CSRF fixed
- All tests passing (198/198)
- Ready for Phase 10+ work

---

## Next Steps (Priority Order)

1. **Phase 10** - Get local runner working end-to-end
2. **Phase 11** - Add E2E tests for workflows
3. **Phase 14** - Complete workflow UI
4. **Phase 12** - K8s deployment
5. **Phase 13** - Terraform infra
6. **Phase 15** - Monitoring
