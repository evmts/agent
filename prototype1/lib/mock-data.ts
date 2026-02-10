export interface ChatSession {
  id: string
  title: string
  preview: string
  timestamp: string
  group: "Today" | "Yesterday" | "This Week" | "Older"
}

export interface ChatMessage {
  id: string
  type: "user" | "assistant" | "command" | "diff" | "status"
  content: string
  timestamp: string
  command?: {
    cmd: string
    cwd: string
    output: string
    exitCode: number
    running?: boolean
  }
  diff?: {
    files: { name: string; additions: number; deletions: number }[]
    totalAdditions: number
    totalDeletions: number
    status: "Applied" | "Applying" | "Failed" | "Declined"
    snippet: string
  }
}

export interface FileTreeItem {
  name: string
  type: "file" | "folder"
  depth: number
  expanded?: boolean
  children?: FileTreeItem[]
  modified?: boolean
  language?: string
}

export interface Agent {
  id: string
  name: string
  status: "idle" | "working" | "completed" | "failed"
  task: string
  changes: number
}

export interface JJChange {
  file: string
  status: "M" | "A" | "D" | "?"
  additions: number
  deletions: number
}

export const mockSessions: ChatSession[] = [
  { id: "1", title: "Refactor auth middleware", preview: "Can you help me refactor the authentication middleware to use the new JWT library?", timestamp: "2m ago", group: "Today" },
  { id: "2", title: "Fix memory leak in WebSocket", preview: "There's a memory leak when clients disconnect from the WebSocket server...", timestamp: "1h ago", group: "Today" },
  { id: "3", title: "Add dark mode toggle", preview: "I need to implement a dark mode toggle using CSS custom properties...", timestamp: "3h ago", group: "Today" },
  { id: "4", title: "Database migration script", preview: "Write a migration script to add the new user_preferences table with...", timestamp: "Yesterday", group: "Yesterday" },
  { id: "5", title: "Optimize image pipeline", preview: "The image processing pipeline is too slow, need to add caching...", timestamp: "Yesterday", group: "Yesterday" },
  { id: "6", title: "Setup CI/CD pipeline", preview: "Help me configure GitHub Actions for automated testing and deployment...", timestamp: "Mon", group: "This Week" },
  { id: "7", title: "GraphQL schema design", preview: "Design a GraphQL schema for the e-commerce product catalog...", timestamp: "Sun", group: "This Week" },
  { id: "8", title: "Redis caching layer", preview: "Implement a Redis caching layer for the API responses...", timestamp: "Feb 1", group: "Older" },
]

export const mockMessages: ChatMessage[] = [
  {
    id: "m1",
    type: "user",
    content: "Can you help me refactor the authentication middleware to use the new JWT library? The current implementation is using jsonwebtoken but I want to switch to jose.",
    timestamp: "2:34 PM",
  },
  {
    id: "m2",
    type: "assistant",
    content: "I'll help you refactor the auth middleware from `jsonwebtoken` to `jose`. The `jose` library is more modern, has better TypeScript support, and works in edge runtimes.\n\nLet me first look at your current implementation to understand the structure.",
    timestamp: "2:34 PM",
  },
  {
    id: "m3",
    type: "command",
    content: "",
    timestamp: "2:34 PM",
    command: {
      cmd: "cat src/middleware/auth.ts",
      cwd: "~/projects/web-app",
      output: `import jwt from 'jsonwebtoken';\nimport { Request, Response, NextFunction } from 'express';\n\nconst SECRET = process.env.JWT_SECRET!;\n\nexport function authMiddleware(req: Request, res: Response, next: NextFunction) {\n  const token = req.headers.authorization?.split(' ')[1];\n  if (!token) return res.status(401).json({ error: 'No token' });\n  try {\n    const decoded = jwt.verify(token, SECRET);\n    req.user = decoded;\n    next();\n  } catch {\n    res.status(401).json({ error: 'Invalid token' });\n  }\n}`,
      exitCode: 0,
    },
  },
  {
    id: "m4",
    type: "assistant",
    content: "I can see the current middleware. Here's my plan:\n\n1. Replace `jsonwebtoken` import with `jose`\n2. Switch from synchronous `jwt.verify()` to async `jwtVerify()`\n3. Add proper type safety for the JWT payload\n4. Make the middleware async-compatible\n\nLet me apply the changes now.",
    timestamp: "2:35 PM",
  },
  {
    id: "m5",
    type: "diff",
    content: "",
    timestamp: "2:35 PM",
    diff: {
      files: [
        { name: "src/middleware/auth.ts", additions: 18, deletions: 12 },
        { name: "package.json", additions: 1, deletions: 1 },
      ],
      totalAdditions: 19,
      totalDeletions: 13,
      status: "Applied",
      snippet: `- import jwt from 'jsonwebtoken';\n+ import { jwtVerify, type JWTPayload } from 'jose';\n  \n- const SECRET = process.env.JWT_SECRET!;\n+ const SECRET = new TextEncoder().encode(process.env.JWT_SECRET!);\n  \n- export function authMiddleware(\n+ export async function authMiddleware(`,
    },
  },
  {
    id: "m6",
    type: "status",
    content: "JJ snapshot created: auth-refactor-v2",
    timestamp: "2:35 PM",
  },
  {
    id: "m7",
    type: "assistant",
    content: "The refactoring is complete. Here's what changed:\n\n- **`src/middleware/auth.ts`**: Replaced `jsonwebtoken` with `jose`, switched to async `jwtVerify()`, added proper `JWTPayload` typing, and encoded the secret using `TextEncoder`.\n- **`package.json`**: Swapped `jsonwebtoken` dependency for `jose`.\n\nThe middleware is now edge-runtime compatible and has better TypeScript support. You can verify it works by running your tests.",
    timestamp: "2:35 PM",
  },
  {
    id: "m8",
    type: "user",
    content: "Can you run the tests to make sure everything passes?",
    timestamp: "2:36 PM",
  },
  {
    id: "m9",
    type: "command",
    content: "",
    timestamp: "2:36 PM",
    command: {
      cmd: "npm test -- --filter auth",
      cwd: "~/projects/web-app",
      output: ` PASS  tests/auth.test.ts\n  Auth Middleware\n    ✓ should reject requests without token (3ms)\n    ✓ should reject requests with invalid token (5ms)\n    ✓ should accept requests with valid token (4ms)\n    ✓ should decode payload correctly (3ms)\n\nTest Suites: 1 passed, 1 total\nTests:       4 passed, 4 total\nTime:        1.234s`,
      exitCode: 0,
    },
  },
  {
    id: "m10",
    type: "assistant",
    content: "All 4 tests pass. The refactoring from `jsonwebtoken` to `jose` is fully verified and working correctly.",
    timestamp: "2:36 PM",
  },
]

export const mockFileTree: FileTreeItem[] = [
  {
    name: "web-app",
    type: "folder",
    depth: 0,
    expanded: true,
    children: [
      {
        name: "src",
        type: "folder",
        depth: 1,
        expanded: true,
        children: [
          {
            name: "middleware",
            type: "folder",
            depth: 2,
            expanded: true,
            children: [
              { name: "auth.ts", type: "file", depth: 3, modified: true, language: "typescript" },
              { name: "cors.ts", type: "file", depth: 3, language: "typescript" },
              { name: "rate-limit.ts", type: "file", depth: 3, language: "typescript" },
            ],
          },
          {
            name: "routes",
            type: "folder",
            depth: 2,
            expanded: false,
            children: [
              { name: "api.ts", type: "file", depth: 3, language: "typescript" },
              { name: "auth.ts", type: "file", depth: 3, language: "typescript" },
              { name: "users.ts", type: "file", depth: 3, language: "typescript" },
            ],
          },
          {
            name: "models",
            type: "folder",
            depth: 2,
            expanded: false,
            children: [
              { name: "user.ts", type: "file", depth: 3, language: "typescript" },
              { name: "session.ts", type: "file", depth: 3, language: "typescript" },
            ],
          },
          { name: "app.ts", type: "file", depth: 1, language: "typescript" },
          { name: "server.ts", type: "file", depth: 1, language: "typescript" },
        ],
      },
      {
        name: "tests",
        type: "folder",
        depth: 1,
        expanded: false,
        children: [
          { name: "auth.test.ts", type: "file", depth: 2, language: "typescript" },
          { name: "api.test.ts", type: "file", depth: 2, language: "typescript" },
        ],
      },
      { name: "package.json", type: "file", depth: 1, modified: true, language: "json" },
      { name: "tsconfig.json", type: "file", depth: 1, language: "json" },
      { name: ".env", type: "file", depth: 1, language: "env" },
      { name: "README.md", type: "file", depth: 1, language: "markdown" },
    ],
  },
]

export const mockAgents: Agent[] = [
  { id: "a1", name: "CodeReview", status: "completed", task: "Review auth middleware refactor", changes: 2 },
  { id: "a2", name: "TestWriter", status: "working", task: "Generate integration tests for API", changes: 0 },
  { id: "a3", name: "DocGen", status: "idle", task: "Update API documentation", changes: 0 },
  { id: "a4", name: "SecurityScan", status: "failed", task: "Scan dependencies for vulnerabilities", changes: 0 },
]

export const mockJJChanges: JJChange[] = [
  { file: "src/middleware/auth.ts", status: "M", additions: 18, deletions: 12 },
  { file: "package.json", status: "M", additions: 1, deletions: 1 },
  { file: "src/middleware/validate.ts", status: "A", additions: 45, deletions: 0 },
]

export const mockCodeContent = `import { jwtVerify, type JWTPayload } from 'jose';
import { Request, Response, NextFunction } from 'express';

interface UserPayload extends JWTPayload {
  userId: string;
  email: string;
  role: 'admin' | 'user';
}

const SECRET = new TextEncoder().encode(
  process.env.JWT_SECRET!
);

export async function authMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
) {
  const token = req.headers.authorization?.split(' ')[1];

  if (!token) {
    return res.status(401).json({
      error: 'Authentication required'
    });
  }

  try {
    const { payload } = await jwtVerify(
      token,
      SECRET
    ) as { payload: UserPayload };

    req.user = {
      id: payload.userId,
      email: payload.email,
      role: payload.role,
    };

    next();
  } catch (err) {
    if (err instanceof Error) {
      console.error('JWT verification failed:', err.message);
    }
    return res.status(401).json({
      error: 'Invalid or expired token'
    });
  }
}`

export const suggestedPrompts = [
  { label: "Add rate limiting to the API endpoints", category: "Code" },
  { label: "Create a WebSocket connection handler", category: "Create" },
  { label: "Explain the authentication flow", category: "Explore" },
  { label: "Write unit tests for the user model", category: "Code" },
]
