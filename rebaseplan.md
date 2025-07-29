# Plue Git Rebase Plan

This document outlines the strategy for rebasing the entire Git history of the Plue project into a clean, logical sequence of commits. Each major feature will be squashed into a single commit, preceded by a rewritten prompt that accurately reflects the final implementation.

---

### 1. Foundational Setup

**Action:** `pick 5f593f3 chore: zig init`
- **Strategy:** This is the root commit, so we'll pick it as the starting point.

**Action:** `squash 4e51711 chore: Add CLAUDE.md`
**Action:** `squash c96ba72 chore: Add gitignore`
**Action:** `squash d8da72b Update documentation for full-stack application`
**Action:** `squash 4bee9ae Update CLAUDE.md with project-specific standards`
**Action:** `squash cb4e738 docs: add mandatory atomic commit protocol for TDD cycles`
- **Strategy:** These commits all relate to project setup and documentation. They will be squashed into the initial commit to create a single, clean "Initial Project Setup" commit. The final commit message will summarize the setup of project standards, documentation, and gitignore.

**Action:** `reword f48bf2c feat: ⚡ Initialize CLI app with zig-clap`
- **Strategy:** This will be the first major feature commit. I will rewrite the commit message to encompass all the squashed commits below it. The prompt file (`.prompts/0-init-cli.md`) will be renamed to `.prompts/0-application-foundation.md` and rewritten to be a comprehensive guide for the entire foundational setup.

**Action:** `squash 48e1300 ✨ Integrate SolidJS GUI build system with WebUI`
**Action:** `squash c7ba80f Add complete Docker infrastructure for development`
**Action:** `squash 5f4a47c ⚡ Add HTTP API server with httpz`
- **Strategy:** These commits represent the core application foundation: GUI, Docker, and the initial HTTP server. They will be squashed into the `f48bf2c` commit to create a single "feat: ✨ establish complete application foundation" commit.

---

### 2. Database and API Implementation

**Action:** `reword 76bc59d Document database testing philosophy and schema plan`
- **Strategy:** This commit will be rewritten to represent the entire database and API implementation. The corresponding prompt (`.prompts/2-gitea-mvp-schema.md`) will be updated to reflect the final, comprehensive schema and API design.

**Action:** `fixup 031d77d Enhance prompts with implementation learnings`
- **Strategy:** This is a meta-commit that will be fixup'd into the database commit, as its learnings are applied to the rewritten prompt.

**Action:** `squash 79b2114 Add PostgreSQL database integration with CRUD operations`
**Action:** `squash c53b8dd ✨ Connect database to HTTP server with REST API endpoints`
**Action:** `squash 6135fbb Add database migrations for Gitea MVPschema`
**Action:** `squash cfe5564 ✨ Add Zig model structs for all database tables`
**Action:** `squash c5a16cd ♻️ Refactor DAO with extended models and new methods`
**Action:** `squash b89a6a9 Add REST API endpoints for repositories and issues`
**Action:** `fixup 546b204 Update Docker setup for database testing`
**Action:** `squash 8ae4ac5 feat: add auth token support for API authentication`
**Action:** `squash 84d3c65 feat: add authenticated GET /user endpoint`
**Action:** `squash 40fc941 feat: add SSH key management endpoints`
**Action:** `squash 9f05df0 feat: add organization management endpoints`
**Action:** `squash 80acf64 test: add comprehensive integration tests for user/org APIs`
**Action:** `fixup a7e37ae fix: move prompt to correct folder with consistent naming`
**Action:** `squash 703700d feat: add repository and branch management endpoints`
**Action:** `squash 28543ee feat: implement Phase 3 - issue and pull request APIs`
**Action:** `squash 963599f feat: implement Phase 4 - Actions/CI endpoints`
**Action:** `squash 67f10df feat: implement Phase 5 - Admin endpoints`
- **Strategy:** All of these commits are part of the initial database and API implementation. They will be squashed into the `76bc59d` commit to create a single, clean "feat: 🗄️ implement Gitea MVP database schema and API" commit.

---

### 3. Server Refactoring

**Action:** `reword 614068e feat: add refactoring plan for breaking up large files`
- **Strategy:** This commit will be rewritten to summarize the server refactoring. The corresponding prompt (`.prompts/4-refactor-large-files.md`) will be updated to reflect the final refactoring strategy.

**Action:** `squash 27f778d refactor: extract user handlers to separate module`
**Action:** `squash 975160e refactor: extract organization handlers to separate module`
**Action:** `squash 54b497a refactor: extract repository handlers to separate module`
**Action:** `fixup 2922934 refactor: partial server handler extraction (WIP)`
- **Strategy:** These commits are all part of the server refactoring. They will be squashed into the `614068e` commit to create a single "refactor: ♻️ extract server handlers into separate modules" commit.

---

### 4. `httpz` to `zap` Migration

**Action:** `reword ec676c5 docs: add migration prompt for httpz to zap framework`
- **Strategy:** This commit will be rewritten to summarize the migration from `httpz` to `zap`. The corresponding prompt (`.prompts/5-migrate-httpz-to-zap.md`) will be updated to be a comprehensive guide for the migration.

**Action:** `fixup 0404fd2 rename: number migration prompt to follow convention`
- **Strategy:** This is a minor fixup that will be squashed into the migration commit.

**Action:** `squash 6971045 refactor: migrate from httpz to zap web framework (WIP)`
**Action:** `squash 01eb949 ✨ feat: migrate users handlers to zap framework`
**Action:** `fixup c51317e wip: continue httpz to zap migration`
**Action:** `squash 0b523e5 ✨ feat: migrate organization handlers to zap framework`
**Action:** `squash 5da59f1 ✨ feat: migrate repository handlers to zap framework`
**Action:** `fixup 9eaa6e2 fix: resolve compilation errors after zap migration`
**Action:** `fixup 98b5c2d docs: update documentation for zap migration`
- **Strategy:** These commits are all part of the `httpz` to `zap` migration. They will be squashed into the `ec676c5` commit to create a single "feat: ✨ migrate from httpz to zap web framework" commit.

---

### 5. Terraform AWS Deployment

**Action:** `reword db8a3ed docs: add Terraform AWS deployment prompt and comment guidelines`
- **Strategy:** This commit will be rewritten to summarize the Terraform AWS deployment. The corresponding prompt (`.prompts/6-terraform-aws-deployment.md`) will be updated to be a comprehensive guide for the deployment.

**Action:** `squash ec6e7a4 feat: add complete Terraform AWS infrastructure for ECS deployment`
- **Strategy:** This commit will be squashed into the `db8a3ed` commit to create a single "feat: 🚀 add complete Terraform AWS infrastructure for ECS deployment" commit.

---

### 6. Secure Git Command Wrapper

**Action:** `reword 6ab1f64 docs: add detailed prompt for secure Git command execution wrapper`
- **Strategy:** This commit will be rewritten to summarize the implementation of the secure Git command wrapper. The corresponding prompt (`.prompts/7-git-command-wrapper.md`) will be updated to be a comprehensive guide for the implementation.

**Action:** `fixup 5a7a5c6 ✨ feat: enhance Git command wrapper prompt based on production patterns`
**Action:** `fixup 0ab7b44 feat: incorporate production insights from Gitea and Zig research`
**Action:** `fixup b9961da docs: add comprehensive Zig implementation patterns to Git wrapper`
**Action:** `fixup f022ffc refactor: reorganize Git wrapper promptwith XML tags for clarity`
**Action:** `fixup 7680e46 feat: add security follow-up considerations to Git wrapper prompt`
- **Strategy:** These are all prompt enhancements that will be fixup'd into the main commit.

**Action:** `squash 06f8d6b ✅ test: implement core security validation for Git wrapper (Phase 1)`
**Action:** `squash 07821de ✅ test: implement Git executable detection (Phase 2)`
**Action:** `squash 3acf62b ✅ test: implement basic Git command execution (Phase 3)`
**Action:** `squash c5b99a1 ✅ test: implement environment and working directory support (Phase 4)`
**Action:** `squash 18568cf ✅ test: implement streaming I/O support (Phase 5)`
**Action:** `squash 8bade25 ✅ test: implement timeout enforcement with thread monitoring (Phase 6)`
**Action:** `squash dec0968 ✅ test: implement Git protocol support with contextual environment (Phase 7)`
**Action:** `squash fa22aac ✅ test: implement Git smart HTTP protocol handlers (Phase 8)`
**Action:** `fixup 7b976a9 fix(git): resolve command execution deadlocks and update Zig syntax`
- **Strategy:** These commits are all part of the Git command wrapper implementation. They will be squashed into the `6ab1f64` commit to create a single "feat: 🔒 implement secure Git command execution wrapper" commit.

---

### 7. Configuration Management

**Action:** `reword 6fdf317 prompt: Implement configuration management prompt`
- **Strategy:** This commit will be rewritten to summarize the implementation of the configuration management system. The corresponding prompt (`.prompts/13-configuration-management.md`) will be updated to be a comprehensive guide for the implementation.

**Action:** `fixup 0785fa4 prompt: Improve prompt`
**Action:** `fixup 9deb4e9 polish: enhance configuration management prompt with research insights`
- **Strategy:** These are prompt enhancements that will be fixup'd into the main commit.

**Action:** `squash 61810ad ✅ test: implement configuration error types and file permission validation (Phase 1-2)`
**Action:** `squash e0ce145 ✅ test: implement INI parser with comprehensive parsing capabilities (Phase 3)`
**Action:** `squash 944b7b7 ✅ test: implement configuration validation logic (Phase 5)`
**Action:** `squash 23e8783 ✅ test: implement file-based secrets support with security (Phase 6)`
**Action:** `squash 8493117 ✅ test: implement complete configuration loading with integration tests (Phase 7)`
**Action:** `squash 39e2478 ✅ test: implement configuration sanitization and security enhancements (Phase 7.5)`
**Action:** `squash 86896b1 ✅ test: implement usage examples and helper functions (Phase 8)`
**Action:** `squash 92eede3 ✅ feat: implement TDD Phase 1 - production-grade config foundations`
**Action:** `squash 43fd09f ✅ feat: complete TDD Phase 2 - zero-dependency INI parser`
**Action:** `squash 327649b ✅ feat: complete TDD Phase 3 - advanced secret management`
**Action:** `squash d93fe91 ✅ test: phase 4 - secure memory clearing and production logging`
**Action:** `squash 807bd1c ✅ test: phase 5 - complete configuration loading with comprehensive validation`
**Action:** `fixup 5c27175 ♻️ refactor(config): add dependency injection for environment variables`
- **Strategy:** These commits are all part of the configuration management implementation. They will be squashed into the `6fdf317` commit to create a single "feat: ⚙️ implement production-grade configuration management" commit.

---

### 8. Permission System

**Action:** `reword 1ecedf9 docs: add permission system implementation prompt`
- **Strategy:** This commit will be rewritten to summarize the implementation of the permission system. The corresponding prompt (`.prompts/14-permission-system.md`) will be updated to be a comprehensive guide for the implementation.

**Action:** `drop aa212aa docs: add permission system implementation prompt`
- **Strategy:** This is a duplicate prompt and will be dropped.

**Action:** `fixup 1684511 ✨ feat: enhance permission system prompt with Gitea patterns`
- **Strategy:** This is a prompt enhancement that will be fixup'd into the main commit.

**Action:** `squash 29ed98c feat: implement core permission types with tests (AccessMode, Visibility, UnitType, Permission, PermissionError)`
**Action:** `squash 93040c0 feat: implement PermissionCachewith tests for request-level caching`
**Action:** `squash d822687 feat: add permission models and DAO methods for permission data access`
**Action:** `squash 9a46f69 feat: implement hasOrgOrUserVisible with comprehensive tests`
**Action:** `squash fbd3876 feat: implement checkOrgTeamPermission with comprehensive team permission tests`
**Action:** `fixup 8ec6f4d feat: complete permission system with all Gitea production patterns`
- **Strategy:** These commits are all part of the permission system implementation. They will be squashed into the `1ecedf9` commit to create a single "feat: 🔐 implement Gitea-inspired permission system" commit.

---

### 9. SSH Server

**Action:** `reword 085c493 docs: add SSH server implementation prompt for issue #20`
- **Strategy:** This commit will be rewritten to summarize the implementation of the SSH server. The corresponding prompt (`.prompts/8-ssh-server.md`) will be updated to be a comprehensive guide for the implementation.

**Action:** `fixup 7766792 ✨ enhance: SSH server prompt with permission integration and security patterns`
**Action:** `fixup f5e4277 enhance: SSH server prompt with Zig research insights`
**Action:** `fixup 7bd4c3c prompt: Enhance with ssh c instructions`
**Action:** `fixup fb8c034 docs: enhance SSH server prompt with implementation guidelines`
- **Strategy:** These are all prompt enhancements that will be fixup'd into the main commit.

**Action:** `squash e88de70 feat: add zig-libssh2 and zig-mbedtls as git submodules`
**Action:** `squash dd4b8f2 feat: integrate libssh2 and mbedTLS into build system`
**Action:** `squash bd47b97 feat: implement libssh2 C bindings with comprehensive error handling`
**Action:** `squash 674b6de feat: implement SSH securitywith rate limiting and connection tracking`
**Action:** `squash af26fa8 feat: implement SSH host key management with multi-algorithm support`
**Action:** `squash 8348e30 ⏹️ feat: implement graceful SSH server shutdown with atomic state management`
**Action:** `squash 1dfe15c feat: integrate SSH modules into test framework`
**Action:** `squash 92e3304 ⚡ feat: implement SSH command parsing and validation`
**Action:** `squash 7102808 feat: implement SSH public key authentication system`
**Action:** `squash 6c02cbc feat: implement SSH session lifecycle management`
**Action:** `squash 9beaaf5 feat: implement complete SSH server orchestration`
**Action:** `squash 4e6a9db feat: add libssh2 configuration for direct integration`
**Action:** `squash 3e585b4 feat: implement direct libssh2 integrationwithout wrapper layer`
**Action:** `squash 312f14c ⚙️ feat: update build system for direct libssh2 integration`
**Action:** `squash 6a26478 feat: add official libssh2 repository as direct dependency`
- **Strategy:** These commits are all part of the SSH server implementation. They will be squashed into the `085c493` commit to create a single "feat:  SSH server implementation" commit.

---

### 10. LFS Storage and Final Fixes

**Action:** `reword 083692a prompt: Add comprehensive technical prompts for all remaining GitHub issues`
- **Strategy:** This commit will be rewritten to summarize the implementation of the LFS storage backend. The corresponding prompt (`.prompts/10-lfs-storage-backend.md`) will be updated to be a comprehensive guide for the implementation.

**Action:** `fixup 2a9720e enhance: transform prompts with Gitea production patterns`
**Action:** `fixup da6a744 fix: correct prompt file numbering and remove duplicates`
**Action:** `fixup b779c42 ✨ enhance: add minor Gitea configuration patterns to config prompt`
**Action:** `fixup 64e612f enhance: transform prompts with Gitea production patterns`
**Action:** `fixup 2534fea fix: renumber prompt files sequentially from 0-18`
- **Strategy:** These are all prompt enhancements and fixes that will be fixup'd into the main commit.

**Action:** `squash 5a99d3e ✅ test: phase 1 & 5 - http server foundation and lfs storage`
**Action:** `squash 293f3fe ✅ test: phase 2 & 3 - authentication and git smart http protocol`
**Action:** `squash ab16b7f ✅ test: phase 4 - git lfs batch api implementation`
**Action:** `squash 45f7490 ✅ test: phase 1, 2 & 5 - lfs storage backends foundation`
**Action:** `squash f3c2d17 ✨ feat: implement enterprise LFS storage interface with multi-backend support`
**Action:** `squash f086c9b feat: implement S3-compatible cloud storage backend with multipart upload`
**Action:** `squash 4800d65 feat: implement enhanced metadata management with analytics and search`
**Action:** `squash de54434 ⚡ feat: implement batch operations with performance optimization and caching`
**Action:** `squash 6e8a321 feat: implement enterprise administrative operations and monitoring`
- **Strategy:** These commits are all part of the LFS storage implementation. They will be squashed into the `083692a` commit to create a single "feat: 🗄️ implement enterprise LFS object storage backend" commit.

---

### 11. Final Fixes

**Action:** `pick e205ae0 fix(build): add missing dependencies to test builds`
- **Strategy:** This is a standalone fix that will be picked as is.

**Action:** `squash 61ea647 ✅ test: configure root.zig to run all module tests`
**Action:** `squash e6c3f32 ♻️ refactor(server): use environment variable from config`
**Action:** `squash 21ce987 test: skip GUI test that hangs waiting for UI`
**Action:** `squash 0e93d8b test(handlers): use system temp directories for git tests`
- **Strategy:** These are all minor fixes and test improvements that will be squashed into a single "chore: 🔧 final fixes and test improvements" commit.