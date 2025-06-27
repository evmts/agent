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

<example-code>
This section provides a starting point for the code you need to write.

### 1. Root Workspace Files

**`executables/package.json`**
```json
{
  "name": "plue-executables",
  "private": true,
  "workspaces": [
    "shared",
    "plue-ai-provider",
    "plue-lsp-client",
    "plue-auth",
    "plue-html-markdown",
    "plue-diff"
  ],
  "scripts": {
    "build": "bun run build.ts",
    "typecheck": "bun workspaces run typecheck"
  },
  "devDependencies": {
    "@types/bun": "latest",
    "typescript": "^5.4.5",
    "zod": "^3.23.8"
  }
}
```

**`executables/tsconfig.base.json`**
```json
{
  "compilerOptions": {
    "lib": ["ESNext"],
    "module": "ESNext",
    "target": "ESNext",
    "moduleResolution": "bundler",
    "moduleDetection": "force",
    "allowImportingTsExtensions": true,
    "noEmit": true,
    "composite": true,
    "strict": true,
    "downlevelIteration": true,
    "skipLibCheck": true,
    "jsx": "react-jsx",
    "allowSyntheticDefaultImports": true,
    "forceConsistentCasingInFileNames": true,
    "allowJs": true,
    "types": [
      "bun-types"
    ]
  }
}
```

**`executables/bunfig.toml`**
```toml
# Bun configuration file
# For now, this can be empty. We can add optimizations later.
# Example:
# [build]
# splitting = true
# sourcemap = "external"
```

**`executables/build.ts`**
```typescript
import { readdir } from 'fs/promises';
import { join } from 'path';

const executablesDir = '.';
const outputDir = join(executablesDir, '..', 'bin');

async function buildExecutables() {
  const entries = await readdir(executablesDir, { withFileTypes: true });
  const executablePackages = entries
    .filter(entry => entry.isDirectory() && entry.name.startsWith('plue-'))
    .map(entry => entry.name);

  console.log(`Found executables: ${executablePackages.join(', ')}`);

  for (const pkg of executablePackages) {
    console.log(`Building ${pkg}...`);
    const result = await Bun.build({
      entrypoints: [join(executablesDir, pkg, 'src', 'index.ts')],
      outdir: outputDir,
      target: 'bun',
      naming: pkg,
      compile: true,
      minify: true,
      sourcemap: 'none',
    });

    if (!result.success) {
      console.error(`Build failed for ${pkg}:`);
      console.error(result.logs.join('\n'));
      process.exit(1);
    }
  }

  console.log('All executables built successfully!');
}

buildExecutables();
```

### 2. Shared Utilities

**`executables/shared/package.json`**
```json
{
  "name": "@plue/shared",
  "version": "0.0.1",
  "private": true,
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "scripts": {
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "zod": "^3.23.8"
  }
}
```

**`executables/shared/tsconfig.json`**
```json
{
  "extends": "../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src"]
}
```

**`executables/shared/src/protocol.ts`**
```typescript
import { z } from 'zod';

export const RequestSchema = z.object({
  action: z.string(),
  params: z.record(z.unknown()),
  timeout: z.number().int().positive().optional(),
});

export type Request = z.infer<typeof RequestSchema>;

export const SuccessResponseSchema = z.object({
  success: z.literal(true),
  data: z.record(z.unknown()),
});

export type SuccessResponse = z.infer<typeof SuccessResponseSchema>;

export const ErrorResponseSchema = z.object({
  success: z.literal(false),
  error: z.object({
    code: z.string(),
    message: z.string(),
  }),
});

export type ErrorResponse = z.infer<typeof ErrorResponseSchema>;

export type Response = SuccessResponse | ErrorResponse;
```

**`executables/shared/src/logger.ts`**
```typescript
export class Logger {
  static log(...args: unknown[]) {
    console.error(`[LOG]`, ...args);
  }

  static error(...args: unknown[]) {
    console.error(`[ERROR]`, ...args);
  }
}
```

**`executables/shared/src/error.ts`**
```typescript
import type { ErrorResponse } from './protocol';

export class ExecutableError extends Error {
  constructor(public code: string, message: string) {
    super(message);
    this.name = 'ExecutableError';
  }

  toResponse(): ErrorResponse {
    return {
      success: false,
      error: {
        code: this.code,
        message: this.message,
      },
    };
  }
}

export class InvalidRequestError extends ExecutableError {
  constructor(message: string = 'Invalid request format') {
    super('INVALID_REQUEST', message);
  }
}

export class UnknownActionError extends ExecutableError {
  constructor(action: string) {
    super('UNKNOWN_ACTION', `Action '${action}' is not recognized.`);
  }
}
```

**`executables/shared/src/index.ts`**
```typescript
export * from './protocol';
export * from './logger';
export * from './error';
```

### 3. Example Executable: `plue-ai-provider`

**`executables/plue-ai-provider/package.json`**
```json
{
  "name": "plue-ai-provider",
  "version": "0.0.1",
  "private": true,
  "main": "src/index.ts",
  "scripts": {
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@plue/shared": "workspace:*"
  }
}
```

**`executables/plue-ai-provider/tsconfig.json`**
```json
{
  "extends": "../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": "src",
    "paths": {
      "@plue/shared": ["../shared/src"]
    }
  },
  "include": ["src"],
  "references": [{ "path": "../shared" }]
}
```

**`executables/plue-ai-provider/src/index.ts`**
```typescript
import {
  RequestSchema,
  Logger,
  ExecutableError,
  InvalidRequestError,
  UnknownActionError,
  type Response,
} from '@plue/shared';

async function handleRequest(request: unknown): Promise<Response> {
  const validation = RequestSchema.safeParse(request);
  if (!validation.success) {
    throw new InvalidRequestError(validation.error.message);
  }

  const { action, params } = validation.data;
  Logger.log(`Handling action: ${action}`);

  switch (action) {
    case 'hello':
      return {
        success: true,
        data: {
          message: `Hello, ${params.name || 'world'}!`,
        },
      };
    // Add other action handlers here
    default:
      throw new UnknownActionError(action);
  }
}

async function main() {
  try {
    const input = await Bun.stdin.text();
    if (!input) {
        throw new InvalidRequestError('No input received from stdin.');
    }
    const request = JSON.parse(input);
    const response = await handleRequest(request);
    process.stdout.write(JSON.stringify(response));
  } catch (e) {
    let error: ExecutableError;
    if (e instanceof ExecutableError) {
      error = e;
    } else if (e instanceof Error) {
      error = new ExecutableError('UNHANDLED_EXCEPTION', e.message);
    } else {
      error = new ExecutableError('UNKNOWN_ERROR', 'An unknown error occurred.');
    }
    Logger.error(error.message, error.stack);
    process.stdout.write(JSON.stringify(error.toResponse()));
    process.exit(1);
  }
}

main();
```
</example-code>

```