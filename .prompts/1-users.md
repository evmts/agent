# Init cli

## Task Definition

Initialize the postgres database access object in zig

## Context & Constraints

### Technical Requirements

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: zig pg library https://github.com/karlseguin/pg.zig , Docker
- **Performance**: n/a
- **Compatibility**: n/a

### Business Context

This is a brand new repo that will build an application named plue. This is a git wrapper application modeled after graphite and gitea.

## Detailed Specifications

### Input

I will give you the sql specs and your job is to implement the entire data access object

### Expected Output

I expect working setup in docker that given postgres credentials spins up our zig app and connects to postgres.

### Steps

There are many steps to this task that should be followed. **IMPORTANT** Never move on to the next step until you have verified the previous step worked and have emoji conventional committed the change. Each step has substeps.

### Task Management
**CRITICAL**: Use the TodoWrite tool extensively to track progress and provide visibility to the user. This should be used for:
- Breaking down each step into specific actionable items
- Marking tasks as in_progress when starting work
- Marking tasks as completed immediately when finished
- Providing clear status updates on overall progress

The TodoWrite tool is essential for:
- Complex multi-step tasks like this one
- Giving users visibility into progress  
- Tracking what has been completed vs what remains
- Avoiding missing any required steps

**Pattern**: Always create todos at the start of each major step, update status as you work, and mark items completed immediately upon finishing.

## Step 0: Docker Infrastructure

### Context

We currently have a native app that spins up with the `run` command of our zig cli (written with zig clap in previous prompt). This native app is using webui to run a native zig app. The app itself is a solid.js spa.

Take Action: Read the build.zig to see how we build it

### Critical Implementation Details

**Architecture Support**: Must support both ARM64 (Apple Silicon) and x86_64 architectures
**Container Networking**: Servers must bind to 0.0.0.0, not localhost, for container access
**Build Dependencies**: Zig builder stage needs Node.js/npm for SPA compilation
**Docker Compose**: Remove obsolete `version:` field (causes warnings in modern Docker)

### Substeps

1. **Add Multi-Stage Dockerfile**

Create a proper multi-stage Dockerfile with these stages:
- **zig-builder**: Download architecture-appropriate Zig, install Node.js/npm, build project
- **spa-builder**: Build SPA assets with Node.js
- **web**: nginx server for SPA (with custom nginx.conf)  
- **cli**: Minimal Alpine with Zig binary and wget for health checks

```docker
# Build stage for Zig application
FROM alpine:3.19 as zig-builder

ARG ZIGVER=0.14.0

RUN apk update && \
    apk add \
        curl \
        xz \
        git \
        libc-dev \
        nodejs \
        npm

# Architecture-aware Zig installation
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then ZIG_ARCH="aarch64"; else ZIG_ARCH="x86_64"; fi && \
    curl -L https://ziglang.org/download/$ZIGVER/zig-linux-$ZIG_ARCH-$ZIGVER.tar.xz -O && \
    tar xf zig-linux-$ZIG_ARCH-$ZIGVER.tar.xz && \
    mv zig-linux-$ZIG_ARCH-$ZIGVER/ /usr/local/zig/

ENV PATH="/usr/local/zig:${PATH}"

WORKDIR /app
COPY . .
RUN zig build -Doptimize=ReleaseSafe
```

2. **Add docker-compose.yml**

Create docker-compose.yml with these services (no version field):
- **postgres**: with health check using pg_isready  
- **api-server**: placeholder (simple Python HTTP server initially)
- **web**: nginx serving SPA with health endpoint
- **healthcheck**: Python service to validate all components

**Important**: Configure nginx with custom conf that includes /health endpoint

3. **Add Comprehensive Health Check Script**

Create `scripts/healthcheck.py` that:
- Validates web service serves SPA correctly with title "Plue"
- Tests API server endpoints
- Confirms postgres connectivity
- Uses requests + BeautifulSoup for HTML parsing
- Provides clear success/failure feedback

4. **Add nginx Configuration**

Create `docker/nginx.conf` with:
- Proper MIME types
- SPA routing (try_files fallback)
- /health endpoint for monitoring
- Appropriate headers

### Testing & Validation

- Fix SPA title in `src/gui/index.html` to "Plue"
- Verify architecture detection works on both ARM64 and x86_64
- Test all health checks pass
- Confirm services can communicate within docker network
- Validate build process works in clean environment

### Common Pitfalls to Avoid

- Don't use localhost binding in containers (use 0.0.0.0)
- Don't forget Node.js in Zig builder stage  
- Don't include obsolete docker-compose version field
- Don't skip architecture detection for Zig downloads
- Don't forget wget in CLI stage for health checks

## Step 1: HTTP API Server with httpz

### Critical Implementation Details

**httpz API**: Router methods (get, post, etc.) return void, not errors - don't use `try`
**Server Binding**: MUST bind to "0.0.0.0" for container networking, not localhost
**Handler Signatures**: For Server(void), handlers are `fn(*Request, *Response) !void`
**Docker Commands**: Use `command: ["server"]` not `["plue", "server"]` in docker-compose

### Substeps

1. **Install httpz Dependency**
```bash
zig fetch --save "git+https://github.com/karlseguin/http.zig#master"
```

2. **Update build.zig**
Add httpz module with proper target/optimize parameters:
```zig
const httpz = b.dependency("httpz", .{
    .target = target,
    .optimize = optimize,
});
exe_mod.addImport("httpz", httpz.module("httpz"));
```

3. **Create Server Module**
Create `src/server/server.zig` with:
- Server struct containing `httpz.Server(void)` (not pointer)
- init() method that creates server with `.address = "0.0.0.0"`
- Router setup: `var router = try server.router(.{});`
- Route registration: `router.get("/", handler, .{});` (NO try)
- Handler functions with correct signature

**Critical**: Handler signature is `fn(_: *httpz.Request, res: *httpz.Response) !void`

4. **Add Server Command**
Create `src/commands/server.zig` that:
- Imports server module
- Initializes server with allocator
- Calls server.listen() with proper error handling
- Includes basic unit tests

5. **Update Main CLI**
- Add server command to enum and routing
- Update help text to describe server command
- Import ServerCommand module

6. **Update Docker Integration**
- Replace Python placeholder in docker-compose
- Use `command: ["server"]` (not full path)
- Update health check to use `/health` endpoint
- Ensure wget is available in CLI container

### Testing & Validation

**Local Testing**:
```bash
zig build && zig build test
./zig-out/bin/plue server &
curl http://localhost:8000/
curl http://localhost:8000/health
```

**Docker Testing**:
- All services start successfully  
- Health check script passes for all services
- API server accessible from other containers
- No "Connection refused" errors

### Common Pitfalls to Avoid

- **Router API**: Don't use `try router.get()` - router methods return void
- **Server Binding**: Don't bind to localhost - use "0.0.0.0" for containers
- **Docker Commands**: Don't use `["plue", "server"]` - use `["server"]` 
- **Handler Signatures**: Don't add extra void parameter - check httpz docs
- **Server Type**: Use `httpz.Server(void)` not pointer to it
- **Architecture**: Ensure Docker builds work on both ARM64 and x86_64

### Router Setup Pattern
```zig
pub fn init(allocator: std.mem.Allocator) !Server {
    var server = try httpz.Server(void).init(allocator, .{ 
        .port = 8000, 
        .address = "0.0.0.0" 
    }, {});
    
    var router = try server.router(.{});  // CAN return error
    router.get("/", indexHandler, .{});    // Returns void
    router.get("/health", healthHandler, .{});  // Returns void
    
    return Server{ .server = server };
}
```

## Step 2: PostgreSQL Database Integration

### Prompt Rebase Instructions

After completing this step, you should update this prompt section with:
- Any critical implementation details discovered during development
- Common pitfalls encountered and how to avoid them  
- Testing patterns that worked well or needed refinement
- Docker/build configuration issues and solutions
- Memory management patterns specific to database operations

**Reference**: See how Steps 0 and 1 were enhanced with "Critical Implementation Details", "Common Pitfalls to Avoid", and specific code examples. Follow the same pattern for database integration learnings.

### Critical Implementation Details

**CLAUDE.md Rule**: Don't pass allocator into constructors - pass into individual methods for explicitness
**Database Connection**: Use environment variables for connection parameters
**Testing Strategy**: E2E tests require running database - add test target to docker-compose
**Memory Management**: Always use defer for cleanup after allocations

### Substeps

1. **Install pg.zig Dependency**
```bash
zig fetch --save "git+https://github.com/karlseguin/pg.zig#master"
```

2. **Update CLAUDE.md**
Add this rule to the allocator best practices section:
```
### Allocator Usage in Constructors
- DON'T pass allocator into constructors/init methods
- DO pass allocator into individual methods that need allocation
- This makes memory usage explicit at call sites
- Helps prevent hidden allocations and ownership confusion
```

3. **Create Database Module**
Create `src/database/dao.zig` with:
- DataAccessObject struct (no allocator field)
- Connection info struct with database credentials
- init() method that establishes connection (no allocator parameter)
- CRUD methods that take allocator parameters when needed
- Proper error handling for all database operations

4. **Add Database Migration Scripts**
Create `scripts/migrate.py` that:
- Creates users table with id, name columns
- Handles schema versioning
- Uses environment variables for connection
- Provides rollback functionality

5. **Implement CRUD Operations**
Add methods to DataAccessObject:
- createUser(allocator, name) -> creates user record
- getUserByName(allocator, name) -> retrieves user
- updateUserName(allocator, old_name, new_name) -> updates record
- deleteUser(allocator, name) -> removes record
- listUsers(allocator) -> returns all users

6. **Add E2E Tests**
Create comprehensive tests that:
- Test all CRUD operations end-to-end
- Require database to be running
- Clean up test data between runs
- Follow CLAUDE.md zero-abstraction test principles

7. **Update Docker Compose**
Add services:
- **db-migrate**: Runs migration scripts
- **api-test**: Runs database tests against live DB
- Update depends_on relationships

### Testing & Validation

**Database Connection**:
```zig
const dao = try DataAccessObject.init("postgresql://user:pass@localhost/plue");
defer dao.deinit();

try dao.createUser(allocator, "test_user");
const user = try dao.getUserByName(allocator, "test_user");
```

**E2E Test Pattern**:
```zig
test "database CRUD operations" {
    const allocator = std.testing.allocator;
    const dao = try DataAccessObject.init(test_db_url);
    defer dao.deinit();
    
    // Test create
    try dao.createUser(allocator, "alice");
    
    // Test read
    const user = try dao.getUserByName(allocator, "alice");
    try std.testing.expectEqualStrings("alice", user.name);
    
    // Test update
    try dao.updateUserName(allocator, "alice", "alice_updated");
    
    // Test delete
    try dao.deleteUser(allocator, "alice_updated");
}
```

### Common Pitfalls to Avoid

- **Allocator in Constructor**: Don't store allocator in DataAccessObject struct
- **Connection Management**: Don't forget to deinit database connections
- **Test Isolation**: Don't let tests interfere with each other's data
- **Error Handling**: Don't ignore database connection errors
- **Memory Leaks**: Always defer cleanup for allocated resources

## Step 3: Connect Database to HTTP Server

### Prompt Rebase Instructions

After completing this step, you should update this prompt section with:
- HTTP/database integration patterns that work well
- JSON handling and parsing lessons learned
- Error handling patterns for database failures
- Health check integration specifics
- Performance considerations for database connections
- Security considerations for API endpoints

**Reference**: Follow the same enhancement pattern used in Steps 0, 1, and 2. Add "Critical Implementation Details", "Common Pitfalls to Avoid", testing patterns, and specific code examples based on actual implementation experience.

### Critical Implementation Details

**Database Integration**: Pass database instance to server, not as global state
**Error Handling**: Return proper HTTP status codes for database errors
**Resource Management**: Ensure database connections are properly managed per request
**Testing**: Update health check to verify end-to-end database connectivity

### Substeps

1. **Update Server to Accept Database**
Modify server initialization to:
- Accept DataAccessObject instance in init
- Store DAO reference for route handlers
- Pass database through route context

2. **Add Database Routes**
Implement REST endpoints:
- `GET /users` -> list all users
- `POST /users` -> create new user (JSON body with name)
- `GET /users/:name` -> get specific user
- `PUT /users/:name` -> update user name
- `DELETE /users/:name` -> delete user

3. **Update Route Handlers**
Modify handlers to:
- Accept database operations
- Handle database errors properly (return 500, 404, etc.)
- Parse JSON request bodies
- Return JSON responses
- Use allocator for database operations

4. **Integration Testing**
Update server command to:
- Initialize database connection
- Pass DAO to server
- Handle database connection failures gracefully

5. **Update Health Check**
Modify `scripts/healthcheck.py` to:
- Test database read/write through API
- Create test user via POST
- Retrieve user via GET
- Update user via PUT  
- Delete user via DELETE
- Verify all operations succeed

6. **Update Docker Compose**
Ensure proper service dependencies:
- API server depends on database
- Health check waits for API server
- Migration runs before API server starts

### Testing & Validation

**API Testing Pattern**:
```bash
# Create user
curl -X POST http://localhost:8000/users -d '{"name":"alice"}' -H "Content-Type: application/json"

# Get user
curl http://localhost:8000/users/alice

# Update user  
curl -X PUT http://localhost:8000/users/alice -d '{"name":"alice_updated"}' -H "Content-Type: application/json"

# Delete user
curl -X DELETE http://localhost:8000/users/alice_updated
```

**Health Check Integration**:
The health check should verify full stack functionality by testing database operations through the HTTP API, not just checking service availability.

### Common Pitfalls to Avoid

- **Global State**: Don't use global database variables
- **Connection Leaks**: Don't forget to manage database connections per request  
- **Error Codes**: Don't return 200 for database errors
- **JSON Parsing**: Don't forget proper Content-Type headers
- **Transaction Safety**: Don't ignore database transaction boundaries

## Code Style & Architecture

### Design Patterns

- Write idiomatic performant zig according to CLAUDE.md
- Keep file structure flat with all cmds just in cmd
- Make commmands easily testable and agnostic to the cli application logic keep all cli specific logic in the main entrypoint

### Code Organization

```
project/
├── build.zig
├── CLAUDE.md
├── CONTRIBUTING.md
|-- scripts/*.py
|-- Dockerfile and docker-compose.yml
├── src/
│   ├── main.zig
│   ├── commands/
    |-- database/
    |-- server/
```

### Success criteria

All steps completed with pr in production ready state
No hacks or workarounds
