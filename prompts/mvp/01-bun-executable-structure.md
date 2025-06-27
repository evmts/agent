# Create Bun Executable Project Structure for Plue AI Editor

You are an AI agent executing a well-scoped task to build an AI editor in Zig. This task focuses on creating the TypeScript/Bun executable infrastructure that will wrap complex JavaScript libraries for use by the Zig core.

## Context

<context>
<project_overview>
Plue is a multi-agent coding assistant with a hybrid Swift-Zig-TypeScript architecture:
- **Swift**: Native macOS UI using SwiftUI (presentation layer only)
- **Zig**: High-performance core library handling ALL business logic and state
- **TypeScript/Bun**: Compiled executables wrapping complex JS libraries to avoid reimplementing them in Zig

The TypeScript executables communicate with Zig via JSON-based IPC, allowing us to leverage battle-tested JavaScript libraries for:
- AI provider SDKs (Anthropic, OpenAI, GitHub Copilot, etc.)
- LSP client functionality
- OAuth authentication flows
- HTML to Markdown conversion
- Diff generation and patch application
</project_overview>

<architecture_pattern>
Communication flow: Swift UI → Zig Core → Spawn Bun Executable → JSON Response → Zig Core → Swift UI

Key principles:
- Executables are stateless - all state remains in Zig
- Communication via standardized JSON protocol
- Executables are compiled with `bun build --compile` and bundled with the app
- Error handling and timeouts managed by Zig
</architecture_pattern>

<reference_implementation>
The opencode project (located in the gitignored opencode/ directory) provides reference implementations:
- Package structure: opencode/packages/opencode/package.json
- Build configuration: opencode/packages/opencode/bunfig.toml
- Entry point pattern: opencode/packages/opencode/src/index.ts
- Binary setup: opencode/packages/opencode/bin/opencode
- Build scripts: opencode/packages/opencode/script/postinstall.mjs, publish.ts
</reference_implementation>

<existing_zig_code>
The Zig core already has basic infrastructure in place:
- build.zig exists and manages the Swift build process
- Basic FFI interface is implemented in src/libplue.zig
- State management structure is defined
- Event system for Swift-Zig communication exists
</existing_zig_code>
</context>

## Task: Create Bun Executable Project Structure

### Requirements

1. **Create a new TypeScript project structure** under `executables/` directory with:
   - Shared utilities and types for all executables
   - Individual directories for each executable
   - Common JSON IPC protocol implementation
   - Error handling and logging utilities
   - Build and compilation scripts

2. **Set up the base executable framework** with:
   - Standard request/response protocol handling
   - Timeout management
   - Error serialization
   - Logging to stderr (stdout is reserved for JSON responses)
   - Graceful shutdown handling

3. **Create the build infrastructure** including:
   - TypeScript configuration for Bun
   - Bunfig.toml for optimization settings
   - Compilation scripts that produce standalone executables
   - Integration with the main Zig build system

4. **Implement the standard protocol** as defined in the API:
   ```json
   // Request
   {
       "action": "string",
       "params": {},
       "timeout": 30000
   }
   
   // Response
   {
       "success": true,
       "data": {},
       "error": {
           "code": "string",
           "message": "string"
       }
   }
   ```

### Detailed Steps

1. **Create the directory structure**:
   ```
   executables/
   ├── shared/
   │   ├── src/
   │   │   ├── protocol.ts    // Request/Response types and validation
   │   │   ├── logger.ts      // Stderr logging utility
   │   │   ├── error.ts       // Error types and serialization
   │   │   └── index.ts       // Re-exports
   │   ├── package.json
   │   └── tsconfig.json
   ├── plue-ai-provider/
   │   ├── src/
   │   │   └── index.ts       // Main entry point
   │   ├── package.json
   │   └── tsconfig.json
   ├── plue-lsp-client/
   ├── plue-auth/
   ├── plue-html-markdown/
   ├── plue-diff/
   ├── package.json           // Workspace root
   ├── bunfig.toml
   ├── tsconfig.base.json
   └── build.ts              // Build script for all executables
   ```

2. **Implement shared protocol module** with:
   - Type-safe request/response interfaces
   - JSON schema validation using a lightweight validator
   - Timeout handling with AbortController
   - Structured error types matching Zig's error codes

3. **Create the base executable template** that:
   - Reads JSON from stdin
   - Validates the request format
   - Routes to action handlers
   - Catches all errors and returns proper error responses
   - Logs debug information to stderr
   - Handles SIGTERM/SIGINT for graceful shutdown

4. **Set up the build system**:
   - Configure Bun workspace in root package.json
   - Create bunfig.toml with production optimizations
   - Write build.ts script that compiles each executable
   - Ensure executables are self-contained with all dependencies bundled
   - Output executables to a `bin/` directory

5. **Integrate with Zig build system**:
   - Modify build.zig to trigger TypeScript build
   - Ensure executables are copied to the correct location for packaging
   - Add build dependencies so Zig build fails if TypeScript build fails

6. **Create comprehensive tests**:
   - Unit tests for protocol handling
   - Integration tests spawning actual executables
   - Error case testing (malformed JSON, timeouts, crashes)
   - Performance benchmarks for IPC overhead

### Implementation Approach

Follow a test-driven development (TDD) approach:

1. **Start with tests first** - Write tests for the protocol module before implementation
2. **Implement incrementally** - Get basic stdin/stdout working before adding features
3. **Commit frequently** - Make commits whenever tests pass and code builds:
   - After creating directory structure
   - After implementing protocol types
   - After basic executable template works
   - After build system integration
   - After each test suite passes

### Git Workflow

Work in a git worktree to keep the main branch clean:
```bash
git worktree add worktrees/bun-executables -b feat/bun-executable-structure
cd worktrees/bun-executables
```

Make atomic commits with descriptive messages following conventional commits:
- `feat: create TypeScript workspace structure for Bun executables`
- `feat: implement JSON IPC protocol with type safety`
- `feat: add base executable template with error handling`
- `feat: integrate Bun build with Zig build system`
- `test: add comprehensive protocol validation tests`

## Success Criteria

✅ **Task is complete when**:
1. TypeScript workspace structure is created with all planned executable directories
2. Shared protocol module has 100% test coverage and handles all edge cases
3. A sample "hello world" executable can be compiled and called from Zig
4. Build system produces self-contained executables under 10MB each
5. Integration with Zig build.zig works seamlessly
6. All tests pass and code follows TypeScript best practices
7. Documentation explains how to add new executables

## Technical Considerations

<typescript_best_practices>
- Use strict TypeScript configuration with all checks enabled
- Prefer interfaces over types for better error messages
- Use discriminated unions for request/response types
- Implement proper error boundaries to catch all exceptions
- Use structured logging with correlation IDs
- Avoid large dependencies - prefer lightweight alternatives
</typescript_best_practices>

<performance_requirements>
- Executable startup time must be under 100ms
- JSON parsing/serialization overhead should be minimal
- Memory usage should be bounded (no leaks)
- Support streaming responses for large data
</performance_requirements>

Remember: The executables are intentionally stateless. They should not maintain any state between invocations. All state management happens in the Zig core.