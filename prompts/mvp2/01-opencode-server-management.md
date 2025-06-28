# Implement OpenCode Server Management System in Zig

## Context

You are implementing the OpenCode server management system for Plue, a multi-agent coding assistant. This is the first component of the MVP2 architecture that uses OpenCode as an HTTP server backend instead of reimplementing its functionality.

### Project Overview

Plue is adopting a simplified architecture where:
- **Swift**: Handles the native macOS UI using SwiftUI
- **Zig**: Manages all business logic, state, and server orchestration
- **OpenCode**: Provides AI capabilities, tool execution, and session management via HTTP

Your task is to create the server management infrastructure that spawns, monitors, and controls the OpenCode server process.

### OpenCode Server Details

OpenCode runs as an HTTP server using the following command:
```bash
cd /path/to/opencode && bun run packages/opencode/src/server/server.ts
```

The server:
- Listens on a configurable port (default: 3000, but use port 0 for automatic assignment)
- Provides a REST API for all operations
- Provides an event stream at `GET /event` for real-time updates (SSE)
- No explicit health check endpoint (use the event stream connection as health indicator)
- Can be configured via environment variables
- Server URL is passed to child processes via `OPENCODE_SERVER` environment variable

### Directory Structure

```
plue/
├── src/
│   ├── main.zig         # Application entry point
│   ├── server/
│   │   ├── manager.zig  # OpenCode server manager (YOU WILL CREATE THIS)
│   │   └── config.zig   # Server configuration (YOU WILL CREATE THIS)
│   └── util/
│       ├── process.zig  # Process utilities (YOU WILL CREATE THIS)
│       └── allocator.zig # Memory management utilities
├── lib/
│   └── opencode/        # OpenCode submodule (future location)
└── opencode/            # Current OpenCode location
```

### Corner Cases and Implementation Details from OpenCode

Based on OpenCode's implementation, pay attention to these critical details:

1. **Port Assignment**: Use port 0 to let the OS assign an available port automatically, avoiding conflicts
2. **Event Stream as Health Check**: Instead of a dedicated health endpoint, establish an SSE connection to `/event`
3. **Process Exit Callbacks**: Use `onExit` callbacks to ensure cleanup when child processes terminate
4. **Environment Variable Passing**: Pass server URL via `OPENCODE_SERVER` env var to child processes
5. **Force Kill Pattern**: Use SIGKILL for cleanup (like LSP servers) when graceful shutdown fails
6. **Auto-Update Handling**: Run update checks asynchronously to avoid blocking startup
7. **Log File Management**: Write logs to a separate file in the data directory for debugging
8. **Race Condition Prevention**: Ensure server is fully started before attempting connections
9. **Orphaned Process Detection**: Track PIDs to detect and clean up orphaned processes
10. **Connection Loss Handling**: Implement reconnection logic for the event stream

### Reference Implementation

Study how OpenCode spawns processes:
```typescript
// From packages/opencode/src/util/process.ts
export async function exec(command: string, options?: { cwd?: string }) {
  const proc = Bun.spawn(command.split(" "), {
    cwd: options?.cwd,
    stdout: "pipe",
    stderr: "pipe",
  });
  
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  
  if (proc.exitCode !== 0) {
    throw new Error(`Command failed: ${stderr}`);
  }
  
  return stdout;
}
```

## Requirements

### 1. Process Management Module (`src/util/process.zig`)

Create a reusable process spawning module that:
- Spawns child processes with configurable environment
- Captures stdout/stderr for logging
- Handles process termination gracefully
- Supports timeout-based killing
- Provides cross-platform compatibility (focus on macOS first)

Example API:
```zig
pub const ProcessOptions = struct {
    cwd: ?[]const u8 = null,
    env: ?std.process.EnvMap = null,
    stdout: enum { inherit, pipe, ignore } = .pipe,
    stderr: enum { inherit, pipe, ignore } = .pipe,
};

pub const Process = struct {
    pid: std.process.Child.Id,
    handle: *std.process.Child,
    
    pub fn spawn(allocator: std.mem.Allocator, argv: []const []const u8, options: ProcessOptions) !Process
    pub fn wait(self: *Process) !u8
    pub fn kill(self: *Process) !void
    pub fn isAlive(self: *const Process) bool
};
```

### 2. Server Configuration (`src/server/config.zig`)

Define server configuration with sensible defaults:
```zig
pub const ServerConfig = struct {
    /// Path to OpenCode directory
    opencode_path: []const u8,
    
    /// Port to run the server on (0 = auto-assign)
    port: u16 = 0,
    
    /// Host to bind to
    host: []const u8 = "127.0.0.1",
    
    /// Environment variables to pass to OpenCode
    env: std.process.EnvMap,
    
    /// Maximum startup time in milliseconds
    startup_timeout_ms: u32 = 30000,
    
    /// Event stream reconnect interval in milliseconds
    event_stream_reconnect_ms: u32 = 1000,
    
    /// Maximum consecutive connection failures before restart
    max_connection_failures: u32 = 3,
    
    /// Force kill timeout after graceful shutdown
    force_kill_timeout_ms: u32 = 5000,
    
    /// Log file path (optional)
    log_file_path: ?[]const u8 = null,
    
    pub fn initDefault(allocator: std.mem.Allocator) !ServerConfig
    pub fn validate(self: *const ServerConfig) !void
};
```

### 3. Server Manager (`src/server/manager.zig`)

Implement the core server management logic:

```zig
pub const ServerManager = struct {
    allocator: std.mem.Allocator,
    config: ServerConfig,
    process: ?Process,
    state: ServerState,
    event_stream: ?*EventStreamConnection,
    consecutive_failures: u32,
    actual_port: u16, // Store the OS-assigned port
    server_url: []const u8,
    log_file: ?std.fs.File,
    
    pub const ServerState = enum {
        stopped,
        starting,
        waiting_ready, // New state for waiting server readiness
        running,
        stopping,
        crashed,
    };
    
    /// Initialize a new server manager
    pub fn init(allocator: std.mem.Allocator, config: ServerConfig) !ServerManager
    
    /// Start the OpenCode server
    pub fn start(self: *ServerManager) !void
    
    /// Stop the server gracefully
    pub fn stop(self: *ServerManager) !void
    
    /// Force stop the server (SIGKILL)
    pub fn forceStop(self: *ServerManager) !void
    
    /// Restart the server
    pub fn restart(self: *ServerManager) !void
    
    /// Connect to event stream (replaces health check)
    pub fn connectEventStream(self: *ServerManager) !void
    
    /// Handle event stream disconnection
    pub fn handleDisconnection(self: *ServerManager) void
    
    /// Get current server state
    pub fn getState(self: *const ServerManager) ServerState
    
    /// Get server URL (includes actual port)
    pub fn getUrl(self: *const ServerManager) []const u8
    
    /// Wait for server to be ready
    pub fn waitReady(self: *ServerManager, timeout_ms: u32) !void
    
    /// Cleanup resources
    pub fn deinit(self: *ServerManager) void
};
```

### 4. Event Stream Connection (Health Monitoring)

Implement event stream connection for health monitoring:
- Connect to SSE endpoint at `/event`
- Initial empty message confirms connection: `data: {}`
- Monitor for disconnections and reconnect automatically
- Track consecutive failures for restart logic
- Parse event data for system status

```zig
pub const EventStreamConnection = struct {
    url: []const u8,
    http_client: *HttpClient,
    abort_signal: std.atomic.Value(bool),
    
    pub fn connect(self: *EventStreamConnection) !void
    pub fn disconnect(self: *EventStreamConnection) void
    pub fn readEvent(self: *EventStreamConnection) !?Event
};
```

### 5. Startup Sequence

1. Validate configuration
2. Create log file if configured
3. Set up environment variables (merge with existing)
4. Spawn OpenCode process with port 0
5. Parse actual port from stdout/stderr
6. Build server URL with actual port
7. Set OPENCODE_SERVER environment variable
8. Wait for event stream connection (with timeout)
9. Handle startup failures with clear error messages
10. Log startup time and port assignment

### 6. Shutdown Sequence

1. Disconnect event stream gracefully
2. Send graceful shutdown signal (SIGTERM)
3. Wait for process to exit (with timeout)
4. Force kill if necessary (SIGKILL) - following OpenCode's pattern
5. Clean up resources (close log files, free memory)
6. Ensure no zombie processes (use waitpid)
7. Remove any temporary files or sockets

### 7. Error Handling

Create specific error types:
```zig
pub const ServerError = error{
    PortInUse,
    StartupTimeout,
    EventStreamConnectionFailed,
    ProcessSpawnFailed,
    InvalidConfiguration,
    ServerCrashed,
    PortParsingFailed,
    LogFileCreationFailed,
    EnvironmentSetupFailed,
    ProcessAlreadyRunning,
    ForceKillTimeout,
};
```

Include detailed error context:
```zig
pub const ErrorContext = struct {
    message: []const u8,
    details: ?[]const u8 = null,
    stdout: ?[]const u8 = null,
    stderr: ?[]const u8 = null,
};
```

## Implementation Steps

### Step 1: Create Process Utilities
1. Create `src/util/process.zig`
2. Implement cross-platform process spawning
3. Add stdout/stderr capture for port parsing
4. Implement proper waitpid for zombie prevention
5. Write comprehensive tests

### Step 2: Define Server Configuration
1. Create `src/server/config.zig`
2. Implement configuration validation
3. Add environment variable merging (preserve existing PATH, etc.)
4. Support log file configuration
5. Create configuration tests

### Step 3: Implement Server Manager
1. Create `src/server/manager.zig`
2. Implement state machine for server lifecycle
3. Add event stream connection monitoring
4. Parse port from server output
5. Handle edge cases (crashes, timeouts, orphaned processes)

### Step 4: Add Integration Tests
1. Test server startup/shutdown
2. Test event stream disconnection and reconnection
3. Test port conflict resolution (port 0)
4. Test force kill scenarios
5. Test log file rotation

### Step 5: Create Example Usage
```zig
// Example in main.zig
const server_config = try ServerConfig.initDefault(allocator);
server_config.opencode_path = "./opencode";
server_config.port = 0; // Let OS assign port
server_config.log_file_path = "/tmp/opencode.log";

var server = try ServerManager.init(allocator, server_config);
defer server.deinit();

try server.start();
try server.waitReady(30000); // Wait up to 30 seconds
std.log.info("OpenCode server running at {s}", .{server.getUrl()});

// Monitor event stream
while (server.getState() == .running) {
    std.time.sleep(1 * std.time.ns_per_s);
}
```

## Testing Requirements

1. **Unit Tests** (>95% coverage):
   - Process spawning and termination
   - Configuration validation
   - State transitions
   - Error handling

2. **Integration Tests**:
   - Full server lifecycle
   - Health check scenarios
   - Crash recovery
   - Port conflict handling

3. **Performance Tests**:
   - Startup time measurement
   - Memory usage monitoring
   - Health check overhead

## Security Considerations

1. **Process Isolation**: Run OpenCode with minimal privileges
2. **Port Security**: Bind only to localhost by default
3. **Environment Sanitization**: Filter sensitive environment variables
4. **Resource Limits**: Implement memory and CPU limits
5. **Logging**: Never log sensitive information

## Platform-Specific Notes

### macOS
- Use `posix_spawn` for better process control
- Handle macOS-specific signals properly
- Consider App Sandbox restrictions

### Future Linux Support
- Prepare for systemd integration
- Handle different process models
- Consider cgroups for resource limits

## Additional Corner Cases and UX Improvements

Based on OpenCode's implementation, handle these scenarios:

### Process Management Edge Cases
1. **Binary Extraction**: If running from embedded binary, extract to cache directory with proper permissions (0o755)
2. **Working Directory**: Preserve the original CWD when spawning OpenCode
3. **Signal Propagation**: Ensure SIGINT/SIGTERM propagate to child process
4. **Exit Callbacks**: Register cleanup in process exit callbacks to avoid dangling resources

### Error Recovery Patterns
1. **Startup Retry**: If initial start fails, wait briefly and retry once before failing
2. **Connection Backoff**: Use exponential backoff for event stream reconnection
3. **Partial Startup**: Detect when server starts but event stream fails
4. **Crash Detection**: Monitor for unexpected process exits and log crash reasons

### UX Enhancements
1. **Progress Indication**: Log "Starting OpenCode server..." with spinner or progress
2. **Port Display**: Clearly show the assigned port in logs: "Server started on port 52341"
3. **Startup Time**: Log how long server took to start for performance monitoring
4. **Graceful Messages**: Show "Shutting down OpenCode server..." during stop
5. **Error Context**: Include last few lines of stderr in error messages

### Monitoring Improvements
1. **PID Tracking**: Store and display process PID for debugging
2. **Memory Usage**: Periodically log server memory usage
3. **Event Count**: Track number of events received for health metrics
4. **Uptime Tracking**: Monitor and log server uptime

### Debugging Features
1. **Debug Mode**: Add verbose logging mode that shows all stdout/stderr
2. **Event Log**: Option to log all SSE events for debugging
3. **State Transitions**: Log all state machine transitions with timestamps
4. **Environment Dump**: Log effective environment variables in debug mode

## Success Criteria

The implementation is complete when:
- [ ] OpenCode server starts reliably within 30 seconds
- [ ] Port 0 assignment works correctly and actual port is captured
- [ ] Event stream connection establishes and reconnects on failure
- [ ] Automatic restart works after 3 consecutive connection failures
- [ ] Graceful shutdown completes within 5 seconds
- [ ] Force kill (SIGKILL) executes if graceful shutdown fails
- [ ] No zombie processes are left behind (proper waitpid usage)
- [ ] Server URL is correctly passed via OPENCODE_SERVER env var
- [ ] Log files are created and rotated properly
- [ ] All tests pass with >95% coverage
- [ ] Memory usage is stable over time
- [ ] Clear error messages for all failure scenarios
- [ ] Race conditions during startup are handled

## Git Workflow

Use git worktrees for development:
```bash
cd /Users/williamcory/plue
git worktree add -b feat_add_opencode_server_management ../plue-server-management
cd ../plue-server-management
```

Commit frequently with conventional commits:
- `feat: add process spawning utilities`
- `feat: implement server configuration`
- `feat: add server manager with health checks`
- `test: add server lifecycle tests`
- `docs: document server management API`

The branch name should be: `feat_add_opencode_server_management`

## Execution Instructions

**IMPORTANT**: Follow these instructions when executing this prompt:
1. Before implementing, commit this prompt file first
2. As you implement, commit your changes frequently
3. If you notice errors in the prompt or missing context, update the prompt and commit those changes too
4. The code samples in this prompt may have bugs - review and fix them as needed during implementation

## Implementation Status Report

### Completed Components

✅ **Process Utilities** (`src/util/process.zig`)
- Process spawning with environment variable support
- Stdout/stderr capture for logging
- Process termination with timeout
- Cross-platform process status checking
- Tests included in module

✅ **Server Configuration** (`src/server/config.zig`)
- Configuration struct with all specified fields
- Environment variable inheritance from current process
- Configuration validation
- Tests included in module

✅ **Server Manager** (`src/server/manager.zig`)
- State machine implementation
- Process spawning with port 0
- Basic port parsing from stdout
- Graceful and force shutdown
- Memory cleanup in deinit
- Tests included in module

✅ **Test Executable** (`src/opencode_server_test.zig`)
- Command-line interface
- Signal handling for Ctrl+C
- Logging and error reporting

✅ **Build Integration**
- Added to build.zig as `test-opencode` step

### Unfinished Components

❌ **Event Stream Connection**
- HTTP/SSE client stub only - no actual implementation
- `EventStreamConnection.connect()` is a no-op that logs a warning
- No reconnection logic implemented
- No event parsing or health monitoring
- **Reason**: Zig's std.http.Client API has changed significantly and needs proper research
- **Impact**: Health monitoring and automatic restart on failures won't work

❌ **Port Parsing Robustness**
- Current implementation only looks for "port" string in stdout
- May fail with different OpenCode output formats
- No handling of port binding failures
- **Reason**: Need to analyze actual OpenCode startup output patterns
- **Impact**: Server URL might be incorrect if port parsing fails

❌ **Server Startup Issues**
- OpenCode server appears to hang during startup in testing
- May need to handle npm/bun install before first run
- May need to set additional environment variables
- **Reason**: Insufficient understanding of OpenCode's startup requirements
- **Impact**: Server won't start properly without correct setup

❌ **Log Rotation**
- Log file creation works but no rotation implemented
- **Reason**: Deprioritized for MVP
- **Impact**: Log files will grow unbounded

❌ **Performance Monitoring**
- No memory usage tracking
- No uptime monitoring
- **Reason**: Deprioritized for MVP
- **Impact**: Can't detect memory leaks or performance issues

### Dependencies for Next Tasks

**Critical for Task 02 (HTTP Client Infrastructure)**:
- The HTTP/SSE client implementation is moved to Task 02
- Task 02 should implement a proper HTTP client that can handle SSE
- Once Task 02 is complete, return to update EventStreamConnection

**Critical for Task 03 (OpenCode API Client)**:
- Server must be able to start successfully
- Port parsing must work to get correct server URL
- These issues should be debugged before implementing API client

### Recommended Actions

1. **Debug OpenCode Startup** (Before Task 03):
   - Run OpenCode manually to understand startup process
   - Check if npm/bun install is needed
   - Capture actual stdout/stderr output patterns
   - Update port parsing logic based on findings

2. **Move HTTP/SSE to Task 02**:
   - Task 02 already covers HTTP client infrastructure
   - Add SSE support requirements to that task
   - Return to complete EventStreamConnection after Task 02

3. **Document OpenCode Requirements**:
   - Create a separate document with OpenCode setup steps
   - Include environment variables needed
   - Document expected output formats

### Modified Success Criteria

The MINIMAL implementation for unblocking next tasks:
- [x] Process spawning works (can start/stop processes)
- [x] Configuration management works
- [x] Basic server lifecycle management works
- [ ] Server actually starts (needs debugging)
- [ ] Port parsing captures correct port (needs improvement)
- [ ] ~~Event stream health monitoring~~ (moved to Task 02)

The remaining items can be addressed after core functionality works.