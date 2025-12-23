# Workflows Development Memory

**READ THIS FIRST. UPDATE AT END OF SESSION.**

---

## Current Status (2025-12-23 15:00)

### Completed (Phases 01-09) ✅
- ✅ Build: `zig build` succeeds
- ✅ Tests: 198/198 pass, zero memory leaks
- ✅ Database: All 4 workflow tables exist
- ✅ CLI: `plue --help` works
- ✅ Server: Starts on port 4000 with `WATCHER_ENABLED=false`
- ✅ Workflow parser: `/api/workflows/parse` works
- ✅ Auth: `/api/auth/dev-login` works

### In Progress (Phases 10-15)
- ⏳ Phase 10: Local Development Integration
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

| Phase | Status | Verified | Notes |
|-------|--------|----------|-------|
| 01 - Storage | ✅ done | ✅ | DB tables exist |
| 02a - Workflow DAOs | ✅ done | ✅ | Tests pass |
| 02b - RestrictedPython | ✅ done | ✅ | Tests pass |
| 03 - Prompt Parser | ✅ done | ✅ | Tests pass |
| 04 - Validation | ✅ done | ✅ | Tests pass |
| 05 - Registry | ✅ done | ✅ | Tests pass |
| 06 - Executor Shell | ✅ done | ✅ | Tests pass |
| 07 - LLM/Agent | ✅ done | ✅ | Tests pass |
| 08 - Runner Pool | ✅ done | ✅ | Tests pass |
| 09 - API/CLI/UI | ✅ done | ✅ | API + CLI work |
| 10 - Local Dev | ⏳ todo | ❌ | Runner needs wiring |
| 11 - E2E Tests | ⏳ todo | ❌ | No workflow E2E tests yet |
| 12 - K8s Deploy | ⏳ todo | ❌ | Manifests exist, untested |
| 13 - Terraform | ⏳ todo | ❌ | Modules exist, untested |
| 14 - UI Complete | ⏳ todo | ❌ | Basic pages exist |
| 15 - Monitoring | ⏳ todo | ❌ | Configs exist, not integrated |

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
