# Gitea MVP Schema Implementation

## Task Definition

Implement the complete database schema for a Gitea MVP including core user management, repository features, issue tracking, and CI/CD (Actions) functionality.

## Context & Constraints

### Technical Requirements

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: 
  - pg.zig (already integrated) - https://github.com/karlseguin/pg.zig
  - Python psycopg2 for migrations (existing pattern)
  - Docker Compose for orchestration
- **Performance**: Connection pooling via existing Pool implementation
- **Compatibility**: PostgreSQL 16, must work in Docker environment

### Business Context

This is the next major step in building Plue, a git wrapper application modeled after Gitea. The existing codebase has basic user CRUD operations and we need to expand to support the full MVP schema including organizations, repositories, issues/PRs, and Actions (CI/CD).

## Detailed Specifications

### Input

The provided Gitea MVP database schema with 13 core tables:
- User & Organization Management (User, OrgUser, PublicKey)
- Repository Management (Repository, Branch, LFSMetaObject, LFSLock)
- Issue Tracking (Issue, Label, IssueLabel, Review, Comment)
- Actions/CI (ActionRun, ActionJob, ActionRunner, ActionRunnerToken, ActionArtifact, ActionSecret)

### Expected Output

1. Python migrations for all tables in the existing migration framework
2. Zig model structs for each table
3. Extended DAO methods following existing patterns
4. Comprehensive tests for all functionality
5. Working integration with existing HTTP API server

### Steps

**CRITICAL**: Each step must be completed with `zig build && zig build test` verification before proceeding.

#### Step 1: Create Python Migrations

Extend `scripts/migrate.py` with new migrations following the existing pattern:
- Migration 2: Core user extensions (Type, IsAdmin, Avatar fields)
- Migration 3: Organization support (OrgUser table)
- Migration 4: SSH keys (PublicKey table)
- Migration 5: Repository tables (Repository, Branch)
- Migration 6: LFS support tables
- Migration 7: Issue tracking tables
- Migration 8: Review and Comment tables
- Migration 9: Actions core tables
- Migration 10: Actions runner and artifact tables

Each migration must:
- Include proper foreign key constraints
- Add necessary indexes for performance
- Follow PostgreSQL naming conventions (lowercase with underscores)

#### Step 2: Create Zig Model Structs

Organize models in `src/database/models/`:
- `user.zig` - Extended User, OrgUser, PublicKey
- `repository.zig` - Repository, Branch, LFS models
- `issue.zig` - Issue, Label, Review, Comment
- `action.zig` - All Actions-related models

Model design principles:
- Use `?[]const u8` for nullable strings
- Use `i64` for all ID fields and timestamps
- Create enums for type fields (UserType, ReviewType, etc.)
- Keep field names matching database columns

#### Step 3: Extend DAO Implementation

Update `src/database/dao.zig` with methods for each model:
- Follow existing pattern: allocator passed to methods, not constructor
- Use prepared statements for all queries
- Handle nullable fields with Zig optionals
- Duplicate strings from query results when needed outside scope
- Group methods by domain (user methods, repo methods, etc.)

Example pattern:
```zig
pub fn createRepository(self: *DataAccessObject, allocator: Allocator, repo: Repository) !void {
    _ = allocator;
    _ = try self.pool.exec(
        \\INSERT INTO repositories (owner_id, lower_name, name, description, 
        \\  default_branch, is_private, is_fork, fork_id, created_unix, updated_unix)
        \\VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    , .{
        repo.owner_id, repo.lower_name, repo.name, repo.description,
        repo.default_branch, repo.is_private, repo.is_fork, repo.fork_id,
        repo.created_unix, repo.updated_unix,
    });
}
```

#### Step 4: Add Comprehensive Tests

Each model file must include tests following the existing pattern:
- Self-contained tests with no abstractions
- Direct database setup in each test
- Test CRUD operations for each model
- Test relationships and constraints
- Clean up test data explicitly
- Skip gracefully if database unavailable

#### Step 5: Integrate with HTTP Server

Extend `src/server/server.zig` with new endpoints:
- `/repos` - Repository CRUD
- `/repos/:owner/:name` - Individual repo operations
- `/repos/:owner/:name/issues` - Issue operations
- `/actions/runners` - Runner registration
- Use request arena allocator for all allocations
- Set proper Content-Type headers for JSON
- Handle errors with appropriate HTTP status codes

### Docker Verification

After each major step:
1. Run `docker-compose down -v` to clean volumes
2. Run `docker-compose up --build` to test full stack
3. Verify migrations apply cleanly
4. Test API endpoints with curl

## Code Style & Architecture

### Design Patterns

- **DAO Pattern**: All database access through DataAccessObject
- **Arena Allocation**: Use HTTP request arena for request-scoped data
- **Error Handling**: Return meaningful errors, map DB errors appropriately
- **Memory Management**: Clear ownership rules, use defer for cleanup

### Code Organization

```
project/
├── scripts/
│   └── migrate.py          # Extended with new migrations
├── src/
│   ├── database/
│   │   ├── dao.zig        # Extended DAO methods
│   │   ├── models/        # New model definitions
│   │   │   ├── user.zig
│   │   │   ├── repository.zig
│   │   │   ├── issue.zig
│   │   │   └── action.zig
│   │   └── pool.zig       # Existing connection pool
│   └── server/
│       └── server.zig     # Extended with new endpoints
```

### Migration Patterns

Follow the existing Python migration pattern:
```python
migrations = [
    (1, "Create users table", """..."""),
    (2, "Add user type and admin fields", """
        ALTER TABLE users 
        ADD COLUMN type INTEGER DEFAULT 0,
        ADD COLUMN is_admin BOOLEAN DEFAULT FALSE,
        ADD COLUMN avatar VARCHAR(255);
    """),
    # ... more migrations
]
```

### Success Criteria

1. All migrations apply successfully in Docker
2. `zig build && zig build test` passes with zero errors
3. All CRUD operations work for each model
4. API endpoints return proper JSON responses
5. No memory leaks (proper cleanup in all paths)
6. Integration tests pass in docker-compose
7. Can create full object graphs (user -> org -> repo -> issue)

## Important Notes

- **Build Verification**: Run `zig build && zig build test` after EVERY change
- **Docker Testing**: Services must bind to `0.0.0.0` not `localhost`
- **String Handling**: Always duplicate strings from DB results if needed outside query scope
- **Connection Management**: Never manually close connections - pool handles lifecycle
- **Test Data**: Use prefixed names (e.g., "test_") to avoid conflicts

## Implementation Summary

This prompt was implemented across three major commits:

### Documentation & Planning
**Commit**: 76bc59d - 📝 Document database testing philosophy and schema plan (Jul 26, 2025)

**What was implemented**:
- Updated CLAUDE.md with explicit database testing philosophy (no mocking)
- Created this prompt document with detailed schema specifications
- Established patterns for database testing in the project

### Database Migrations
**Commit**: 6135fbb - 🗄️ Add database migrations for Gitea MVP schema (Jul 26, 2025)

**What was implemented**:
- Extended migrate.py with 10 migrations covering all MVP tables
- User extensions (type, is_admin, avatar fields)
- Organization membership (org_user table)
- SSH public keys for authentication
- Repository and branch management tables
- Git LFS support tables
- Issue tracking with labels
- Pull request reviews and comments
- Actions/CI core tables with runners and artifacts
- Proper foreign key constraints and indexes throughout

### Zig Model Structs
**Commit**: cfe5564 - ✨ Add Zig model structs for all database tables (Jul 26, 2025)

**What was implemented**:
- Created organized model files by domain:
  - user.zig: User, OrgUser, PublicKey models with UserType enum
  - repository.zig: Repository, Branch, LFS models
  - issue.zig: Issue, Label, Review, Comment models with ReviewType enum
  - action.zig: All CI/CD models including runs, jobs, runners, artifacts
- Comprehensive unit tests for each model
- Database integration tests following CLAUDE.md principles (real PostgreSQL, no mocks)

**How it went**:
The schema implementation was completed successfully in a systematic manner. The team first documented the testing philosophy and created a detailed plan, then implemented the migrations and model structs. The implementation established strong patterns that were followed throughout the project's evolution.

**What was NOT completed in this prompt**:
- Step 3: Extending DAO with methods for each model - This was done incrementally in later commits as API endpoints were implemented
- Step 4: Some integration tests were added later as the API evolved
- Step 5: HTTP server integration - This was done in the next prompt (3-implement-api-schema.md)

The separation of schema/models from DAO/API implementation proved to be a good architectural decision, allowing the project to evolve incrementally with each layer building on the previous one.