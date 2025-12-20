# Plue Comprehensive Code Review Report

## Executive Summary

**Repository:** Plue - A brutalist GitHub clone with AI agent capabilities
**Review Date:** December 20, 2025
**Review Method:** 8 specialized AI agents reviewing in parallel
**Lines of Code:** ~50,000+ across Zig, TypeScript, Python, Rust, Terraform

### Overall Assessment: NOT PRODUCTION READY

| Category | Rating | Status |
|----------|--------|--------|
| **Server Core** | 70% | Major stubs |
| **Security** | 40% | 14 vulnerabilities |
| **Frontend** | 75% | 14 incomplete features |
| **Test Coverage** | POOR | Broken tests, no integration |
| **Infrastructure** | 65% | Missing security hardening |
| **Crypto (TypeScript)** | 95% | Production ready |
| **Crypto (Zig)** | 30% | Unaudited, timing attacks |
| **CI/CD System** | 95% | Missing event triggers |
| **Gitea Comparison** | 30% | ~30% feature parity |

---

## Critical Blockers (P0)

### 1. SSH Server Completely Stubbed
**File:** `server/src/ssh/server.zig:268`
**Impact:** Git clone/push/pull over SSH non-functional
**Code:** Returns `error.NotImplemented` after version exchange

### 2. jj Integration Returns Fake Data
**Files:** 25+ endpoints in sessions.zig, operations.zig, landing_queue.zig
**Impact:** All version control operations return empty arrays
**Note:** jj-ffi Rust bindings are COMPLETE (1062 lines) but never called from Zig

### 3. Email Verification Not Sent
**File:** `ui/pages/api/auth/register.ts:87`
**Impact:** Users cannot activate accounts - registration broken

### 4. Landing Page Will Crash
**File:** `ui/pages/[user]/[repo]/landing/index.astro:66`
**Impact:** Missing jj import causes runtime crash

### 5. Server Tests Don't Compile
**Impact:** 85 AI agent tests cannot run, 15 compilation errors
**Cause:** Zig 0.15.1 API changes not updated

### 6. No Automatic Workflow Triggering
**Impact:** CI/CD requires manual API calls - not functional for real use

---

## Security Vulnerabilities (14 Found)

### Critical (3)
1. **Weak JWT Secret Default** - `"dev-secret-change-in-production"` hardcoded
2. **Secrets in .env Committed** - SESSION_SECRET, JWT_SECRET visible in git
3. **SQL Injection Risk** - Custom JSON parser in user search

### High (5)
1. **Missing CSRF Protection** - All POST/PUT/DELETE vulnerable
2. **No Token Scope Enforcement** - API tokens bypass declared scopes
3. **Path Traversal Risk** - AI file tools accept arbitrary paths
4. **SIWE Nonce 10-minute Window** - Replay attack window too large
5. **Per-Instance Rate Limiting** - Bypassable with load balancer

### Medium (4)
1. Session fixation vulnerability
2. API tokens never expire
3. Missing repository visibility checks
4. Weak nonce entropy (modulo bias)

### Low (2)
1. Error messages leak implementation details
2. CSP allows unsafe-inline

---

## Infrastructure Issues

### Critical Security Gaps
- **No Pod Security** - All containers run as root
- **Adminer Publicly Exposed** - Database admin tool on public ingress
- **`:latest` Image Tags** - Non-deterministic deployments
- **TLS Verification Disabled** - MITM risk on Cloudflare tunnel

### Missing Production Requirements
- No monitoring/alerting stack (Prometheus, AlertManager)
- No network policies (despite Calico enabled)
- No secret rotation
- No WAF rules
- No disaster recovery plan
- No CI/CD pipeline configuration

---

## Test Coverage Assessment

| Component | Tests | Status |
|-----------|-------|--------|
| Server Routes | 4 files | Broken (won't compile) |
| AI Agent System | 85 tests | Cannot run |
| UI Utilities | 160 tests | Passing |
| E2E Tests | 3 specs | Partial coverage |
| Workflow Tests | 15 tests | Passing |
| Integration Tests | 0 | None exist |
| Security Tests | 0 | None exist |

**Major Gaps:**
- Zero integration tests
- No database tests
- No authentication flow tests
- No WebSocket/PTY tests
- Test pyramid inverted

---

## Feature Completeness vs Gitea

| Feature | Gitea | Plue | Gap |
|---------|-------|------|-----|
| SSH Git Operations | Full | Stubbed | **P0** |
| Webhook System | 30+ events | None | **P0** |
| Protected Branches | Full | None | **P1** |
| Merge Strategies | 6 types | Basic | **P1** |
| Deploy Keys | Full | None | **P1** |
| Organization Support | Full | None | **P1** |
| Notification System | Full | None | **P0** |
| Background Jobs | Queue system | None | **P1** |

**Plue implements ~30% of Gitea's production features**

---

## Voltaire Crypto Library

### Production Ready (TypeScript)
- Uses @noble/curves, @noble/hashes (audited)
- All EVM precompiles implemented correctly
- EIP compliance verified
- 852 test files, 30 fuzz tests

### NOT Production Ready (Zig)
- Custom secp256k1 is UNAUDITED
- Timing attack vulnerabilities documented
- Non-constant-time operations leak secrets
- RIPEMD160 unaudited

**Recommendation:** Use TypeScript API for production, Zig is experimental only

---

## Workflow/CI System

### What Works (95% complete)
- Python runner fully functional
- Database schema complete
- API routes implemented
- Task assignment works
- Log streaming works

### What's Missing (Critical Gap)
- **No automatic workflow triggering** - Needs ~200 LOC event dispatcher
- RepoWatcher doesn't connect to workflow system
- No workflow file discovery in `.plue/workflows/`

---

## Priority Remediation Plan

### Week 1 (Critical Path)
1. Fix server test compilation (Zig 0.15.1 API updates)
2. Add jj import to landing page
3. Implement email sending or workaround
4. Remove secrets from .env, rotate all
5. Add pod security contexts
6. Remove Adminer from public ingress

### Week 2-3 (Security)
1. Implement CSRF protection
2. Add token scope enforcement
3. Reduce SIWE nonce window
4. Add distributed rate limiting
5. Implement workflow event triggers

### Month 1 (Core Features)
1. Connect jj-ffi to all stubbed endpoints
2. Implement SSH protocol (or use OpenSSH wrapper)
3. Add webhook system
4. Deploy network policies
5. Add monitoring stack

### Month 2+ (Production Readiness)
1. Protected branch rules
2. Code review enforcement
3. Disaster recovery testing
4. Security audit
5. Performance testing

---

## Files Requiring Immediate Attention

### Server (Critical Stubs)
- `server/src/ssh/server.zig:228-268` - SSH protocol
- `server/src/routes/sessions.zig` - 15 jj stubs
- `server/src/routes/operations.zig` - 4 jj stubs
- `server/src/routes/landing_queue.zig` - 3 jj stubs
- `server/src/routes/repositories.zig:94` - Repo initialization

### Frontend (Broken)
- `ui/pages/[user]/[repo]/landing/index.astro:66` - Missing import
- `ui/pages/api/auth/register.ts:87` - Email TODO
- `ui/lib/electric.ts` - ElectricSQL not implemented

### Security
- `server/src/config.zig:30` - JWT secret default
- `.env` - Remove from git
- `terraform/kubernetes/ingress.tf:117-136` - Remove Adminer

### Tests (Compilation)
- `server/src/routes/*.test.zig` - Fix Zig 0.15.1 API

---

## Positive Findings

1. **Well-structured codebase** - Clear separation of concerns
2. **Good Zig practices** - Proper error handling, memory management
3. **Comprehensive database schema** - 43 well-designed tables
4. **Excellent UI utility tests** - 160 passing tests
5. **Working workflow runner** - Python system is production-ready
6. **Strong TypeScript crypto** - Uses audited libraries
7. **Good Terraform modules** - Modular, reusable infrastructure
8. **jj-ffi bindings complete** - Just need Zig integration

---

## Conclusion

Plue is a **promising but incomplete** implementation. The architecture is sound, with good separation of concerns and sensible technology choices. However, **critical functionality is stubbed** rather than implemented:

- **SSH server returns NotImplemented**
- **25+ jj operations return empty data**
- **Workflows require manual triggering**
- **Tests don't compile**
- **14 security vulnerabilities**

The codebase appears to be a sophisticated facade - APIs accept requests and return success, but actual functionality is missing. The jj-ffi Rust bindings are fully implemented but never called from the Zig server.

**Recommendation:** Block production deployment. Allocate 2-3 months of focused development to:
1. Connect jj-ffi to all stubbed endpoints
2. Implement SSH or use OpenSSH wrapper
3. Add workflow event triggering
4. Fix security vulnerabilities
5. Add integration tests

The foundation is solid - it needs execution, not redesign.

---

*Generated by 8-agent parallel code review on December 20, 2025*
