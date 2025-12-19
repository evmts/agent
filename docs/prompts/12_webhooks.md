# Webhooks Feature Implementation

## Overview

Implement a GitHub/Gitea-style webhook system for Plue, allowing repositories to send HTTP POST notifications to external services when specific events occur (push, issues, comments, etc.). This enables integration with external CI/CD systems, notification services, and custom automation.

**Scope**: Full webhook lifecycle including CRUD operations, event type selection, secure payload delivery with HMAC signatures, delivery history tracking, retry logic, and test webhook functionality.

**Stack**: Bun runtime, Hono API server, Astro SSR frontend, PostgreSQL database, integration with existing EventBus.

---

## 1. Database Schema Changes

### 1.1 Webhooks Table

```sql
-- Webhooks for repositories
CREATE TABLE IF NOT EXISTS webhooks (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,

  -- Webhook configuration
  url TEXT NOT NULL,
  http_method VARCHAR(10) DEFAULT 'POST' CHECK (http_method IN ('POST', 'GET', 'PUT')),
  content_type VARCHAR(20) DEFAULT 'json' CHECK (content_type IN ('json', 'form')),
  secret TEXT, -- For HMAC signature generation

  -- Event configuration (stored as JSONB)
  events JSONB NOT NULL DEFAULT '{"push": true}',
  -- Example: {"push": true, "issues": true, "issue_comment": true, "pull_request": false}

  -- Status
  is_active BOOLEAN DEFAULT true,
  last_status VARCHAR(20) DEFAULT 'none' CHECK (last_status IN ('none', 'succeed', 'fail')),

  -- Optional authorization header (encrypted)
  authorization_header_encrypted TEXT,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_webhooks_repository ON webhooks(repository_id);
CREATE INDEX idx_webhooks_active ON webhooks(is_active);
```

### 1.2 Hook Tasks (Delivery Tracking) Table

```sql
-- Hook task represents a single webhook delivery attempt
CREATE TABLE IF NOT EXISTS hook_tasks (
  id SERIAL PRIMARY KEY,
  hook_id INTEGER NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
  uuid VARCHAR(36) UNIQUE NOT NULL, -- UUID for idempotency and tracking

  -- Event information
  event_type VARCHAR(50) NOT NULL, -- 'push', 'issues', 'issue_comment', etc.
  payload_content TEXT NOT NULL, -- JSON payload

  -- Delivery tracking
  is_delivered BOOLEAN DEFAULT false,
  delivered_at BIGINT, -- Nanosecond timestamp

  -- Success/failure tracking
  is_succeed BOOLEAN DEFAULT false,

  -- Request/Response details (stored as JSONB)
  request_info JSONB,
  -- Example: {"url": "https://...", "method": "POST", "headers": {...}, "body": "..."}

  response_info JSONB,
  -- Example: {"status": 200, "headers": {...}, "body": "..."}

  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_hook_tasks_hook ON hook_tasks(hook_id);
CREATE INDEX idx_hook_tasks_uuid ON hook_tasks(uuid);
CREATE INDEX idx_hook_tasks_delivered ON hook_tasks(is_delivered);
CREATE INDEX idx_hook_tasks_created ON hook_tasks(created_at DESC);
```

---

## 2. TypeScript Type Definitions

### 2.1 Webhook Types (`core/models/webhook.ts`)

```typescript
import { z } from 'zod';

// Event types that can trigger webhooks
export const WebhookEventType = z.enum([
  'push',
  'create',           // Branch/tag creation
  'delete',           // Branch/tag deletion
  'issues',
  'issue_comment',
  'pull_request',
  'pull_request_comment',
  'release',
  'fork',
]);

export type WebhookEventType = z.infer<typeof WebhookEventType>;

// Webhook configuration
export const WebhookSchema = z.object({
  id: z.number(),
  repositoryId: z.number(),
  url: z.string().url(),
  httpMethod: z.enum(['POST', 'GET', 'PUT']).default('POST'),
  contentType: z.enum(['json', 'form']).default('json'),
  secret: z.string().optional(),
  events: z.record(z.boolean()), // { push: true, issues: false, ... }
  isActive: z.boolean().default(true),
  lastStatus: z.enum(['none', 'succeed', 'fail']).default('none'),
  authorizationHeaderEncrypted: z.string().optional(),
  createdAt: z.date(),
  updatedAt: z.date(),
});

export type Webhook = z.infer<typeof WebhookSchema>;

// Hook task (delivery record)
export const HookTaskSchema = z.object({
  id: z.number(),
  hookId: z.number(),
  uuid: z.string().uuid(),
  eventType: WebhookEventType,
  payloadContent: z.string(), // JSON string
  isDelivered: z.boolean().default(false),
  deliveredAt: z.number().optional(), // Nanosecond timestamp
  isSucceed: z.boolean().default(false),
  requestInfo: z.object({
    url: z.string(),
    method: z.string(),
    headers: z.record(z.string()),
    body: z.string(),
  }).optional(),
  responseInfo: z.object({
    status: z.number(),
    headers: z.record(z.string()),
    body: z.string(),
  }).optional(),
  createdAt: z.date(),
});

export type HookTask = z.infer<typeof HookTaskSchema>;

// Webhook creation/update input
export const CreateWebhookSchema = z.object({
  url: z.string().url(),
  httpMethod: z.enum(['POST', 'GET', 'PUT']).default('POST'),
  contentType: z.enum(['json', 'form']).default('json'),
  secret: z.string().optional(),
  events: z.record(z.boolean()),
  isActive: z.boolean().default(true),
  authorizationHeader: z.string().optional(), // Unencrypted, will be encrypted before storage
});

export type CreateWebhookInput = z.infer<typeof CreateWebhookSchema>;
```

### 2.2 Webhook Payload Types (`core/models/webhook-payloads.ts`)

```typescript
// Base payload structure (similar to GitHub webhook payloads)
export interface BaseWebhookPayload {
  action?: string; // 'opened', 'closed', 'created', etc.
  repository: {
    id: number;
    name: string;
    full_name: string; // 'username/repo'
    description: string | null;
    html_url: string;
    default_branch: string;
  };
  sender: {
    id: number;
    username: string;
    html_url: string;
  };
}

// Push event payload
export interface PushWebhookPayload extends BaseWebhookPayload {
  ref: string; // 'refs/heads/main'
  before: string; // SHA before push
  after: string; // SHA after push
  commits: Array<{
    id: string;
    message: string;
    timestamp: string;
    url: string;
    author: {
      name: string;
      email: string;
      username?: string;
    };
    committer: {
      name: string;
      email: string;
      username?: string;
    };
    added: string[];
    removed: string[];
    modified: string[];
  }>;
  head_commit: object | null;
  compare_url: string;
}

// Issues event payload
export interface IssuesWebhookPayload extends BaseWebhookPayload {
  action: 'opened' | 'edited' | 'closed' | 'reopened';
  issue: {
    id: number;
    number: number;
    title: string;
    body: string | null;
    state: 'open' | 'closed';
    html_url: string;
    user: {
      id: number;
      username: string;
    };
    created_at: string;
    updated_at: string;
    closed_at: string | null;
  };
}

// Issue comment event payload
export interface IssueCommentWebhookPayload extends BaseWebhookPayload {
  action: 'created' | 'edited' | 'deleted';
  issue: object;
  comment: {
    id: number;
    body: string;
    html_url: string;
    user: {
      id: number;
      username: string;
    };
    created_at: string;
  };
}
```

---

## 3. Core Webhook Service

### 3.1 Webhook CRUD Operations (`core/webhooks.ts`)

```typescript
import { sql } from '../lib/db';
import type { Webhook, CreateWebhookInput, HookTask } from './models/webhook';
import { encryptSecret, decryptSecret } from './crypto';

/**
 * Create a new webhook
 */
export async function createWebhook(
  repositoryId: number,
  input: CreateWebhookInput
): Promise<Webhook> {
  // Encrypt authorization header if provided
  const authHeaderEncrypted = input.authorizationHeader
    ? await encryptSecret(input.authorizationHeader)
    : null;

  const [webhook] = await sql`
    INSERT INTO webhooks (
      repository_id,
      url,
      http_method,
      content_type,
      secret,
      events,
      is_active,
      authorization_header_encrypted
    ) VALUES (
      ${repositoryId},
      ${input.url},
      ${input.httpMethod},
      ${input.contentType},
      ${input.secret || null},
      ${JSON.stringify(input.events)},
      ${input.isActive},
      ${authHeaderEncrypted}
    )
    RETURNING *
  `;

  return webhook;
}

/**
 * Get webhook by ID
 */
export async function getWebhook(webhookId: number): Promise<Webhook | null> {
  const [webhook] = await sql`
    SELECT * FROM webhooks WHERE id = ${webhookId}
  `;
  return webhook || null;
}

/**
 * Get webhook by ID and repository (for access control)
 */
export async function getWebhookByRepo(
  repositoryId: number,
  webhookId: number
): Promise<Webhook | null> {
  const [webhook] = await sql`
    SELECT * FROM webhooks
    WHERE id = ${webhookId} AND repository_id = ${repositoryId}
  `;
  return webhook || null;
}

/**
 * List all webhooks for a repository
 */
export async function listWebhooks(repositoryId: number): Promise<Webhook[]> {
  return await sql`
    SELECT * FROM webhooks
    WHERE repository_id = ${repositoryId}
    ORDER BY created_at DESC
  `;
}

/**
 * Update webhook
 */
export async function updateWebhook(
  webhookId: number,
  input: Partial<CreateWebhookInput>
): Promise<Webhook> {
  const authHeaderEncrypted = input.authorizationHeader
    ? await encryptSecret(input.authorizationHeader)
    : undefined;

  const [webhook] = await sql`
    UPDATE webhooks
    SET
      url = COALESCE(${input.url}, url),
      http_method = COALESCE(${input.httpMethod}, http_method),
      content_type = COALESCE(${input.contentType}, content_type),
      secret = COALESCE(${input.secret}, secret),
      events = COALESCE(${input.events ? JSON.stringify(input.events) : null}, events),
      is_active = COALESCE(${input.isActive}, is_active),
      authorization_header_encrypted = COALESCE(
        ${authHeaderEncrypted},
        authorization_header_encrypted
      ),
      updated_at = NOW()
    WHERE id = ${webhookId}
    RETURNING *
  `;

  return webhook;
}

/**
 * Update webhook last delivery status
 */
export async function updateWebhookStatus(
  webhookId: number,
  status: 'succeed' | 'fail'
): Promise<void> {
  await sql`
    UPDATE webhooks
    SET last_status = ${status}
    WHERE id = ${webhookId}
  `;
}

/**
 * Delete webhook
 */
export async function deleteWebhook(webhookId: number): Promise<void> {
  await sql`
    DELETE FROM webhooks WHERE id = ${webhookId}
  `;
}

/**
 * Get webhook delivery history
 */
export async function getWebhookHistory(
  webhookId: number,
  page: number = 1,
  perPage: number = 20
): Promise<HookTask[]> {
  const offset = (page - 1) * perPage;

  return await sql`
    SELECT * FROM hook_tasks
    WHERE hook_id = ${webhookId}
    ORDER BY created_at DESC
    LIMIT ${perPage} OFFSET ${offset}
  `;
}
```

### 3.2 Webhook Payload Generation (`core/webhook-payloads.ts`)

```typescript
import type {
  BaseWebhookPayload,
  PushWebhookPayload,
  IssuesWebhookPayload,
  IssueCommentWebhookPayload,
} from './models/webhook-payloads';

/**
 * Generate repository object for webhook payloads
 */
function generateRepositoryPayload(repo: any) {
  return {
    id: repo.id,
    name: repo.name,
    full_name: `${repo.username}/${repo.name}`,
    description: repo.description,
    html_url: `${process.env.APP_URL}/${repo.username}/${repo.name}`,
    default_branch: repo.default_branch || 'main',
  };
}

/**
 * Generate sender/user object for webhook payloads
 */
function generateUserPayload(user: any) {
  return {
    id: user.id,
    username: user.username,
    html_url: `${process.env.APP_URL}/${user.username}`,
  };
}

/**
 * Generate push event payload
 */
export async function generatePushPayload(
  repo: any,
  sender: any,
  commits: any[],
  ref: string,
  before: string,
  after: string
): Promise<PushWebhookPayload> {
  return {
    ref,
    before,
    after,
    commits: commits.map(commit => ({
      id: commit.sha,
      message: commit.message,
      timestamp: commit.timestamp,
      url: `${process.env.APP_URL}/${repo.username}/${repo.name}/commit/${commit.sha}`,
      author: {
        name: commit.author.name,
        email: commit.author.email,
        username: commit.author.username,
      },
      committer: {
        name: commit.committer.name,
        email: commit.committer.email,
        username: commit.committer.username,
      },
      added: commit.added || [],
      removed: commit.removed || [],
      modified: commit.modified || [],
    })),
    head_commit: commits[0] || null,
    compare_url: `${process.env.APP_URL}/${repo.username}/${repo.name}/compare/${before}...${after}`,
    repository: generateRepositoryPayload(repo),
    sender: generateUserPayload(sender),
  };
}

/**
 * Generate issues event payload
 */
export async function generateIssuesPayload(
  action: 'opened' | 'edited' | 'closed' | 'reopened',
  repo: any,
  issue: any,
  sender: any
): Promise<IssuesWebhookPayload> {
  return {
    action,
    issue: {
      id: issue.id,
      number: issue.issue_number,
      title: issue.title,
      body: issue.body,
      state: issue.state,
      html_url: `${process.env.APP_URL}/${repo.username}/${repo.name}/issues/${issue.issue_number}`,
      user: generateUserPayload(issue.author),
      created_at: issue.created_at,
      updated_at: issue.updated_at,
      closed_at: issue.closed_at,
    },
    repository: generateRepositoryPayload(repo),
    sender: generateUserPayload(sender),
  };
}

/**
 * Generate issue comment event payload
 */
export async function generateIssueCommentPayload(
  action: 'created' | 'edited' | 'deleted',
  repo: any,
  issue: any,
  comment: any,
  sender: any
): Promise<IssueCommentWebhookPayload> {
  return {
    action,
    issue: {
      id: issue.id,
      number: issue.issue_number,
      title: issue.title,
      state: issue.state,
      html_url: `${process.env.APP_URL}/${repo.username}/${repo.name}/issues/${issue.issue_number}`,
    },
    comment: {
      id: comment.id,
      body: comment.body,
      html_url: `${process.env.APP_URL}/${repo.username}/${repo.name}/issues/${issue.issue_number}#comment-${comment.id}`,
      user: generateUserPayload(comment.author),
      created_at: comment.created_at,
    },
    repository: generateRepositoryPayload(repo),
    sender: generateUserPayload(sender),
  };
}
```

### 3.3 Webhook Delivery Service (`core/webhook-delivery.ts`)

```typescript
import crypto from 'node:crypto';
import { sql } from '../lib/db';
import type { Webhook, HookTask } from './models/webhook';
import { updateWebhookStatus } from './webhooks';

/**
 * Generate HMAC signature for webhook payload
 */
function generateSignature(secret: string, payload: string): {
  sha1: string;
  sha256: string;
} {
  const hmacSHA1 = crypto.createHmac('sha1', secret);
  const hmacSHA256 = crypto.createHmac('sha256', secret);

  hmacSHA1.update(payload);
  hmacSHA256.update(payload);

  return {
    sha1: hmacSHA1.digest('hex'),
    sha256: hmacSHA256.digest('hex'),
  };
}

/**
 * Create a hook task (delivery record)
 */
export async function createHookTask(
  hookId: number,
  eventType: string,
  payload: object
): Promise<HookTask> {
  const uuid = crypto.randomUUID();
  const payloadContent = JSON.stringify(payload);
  const deliveredAt = Date.now() * 1000000; // Convert to nanoseconds

  const [task] = await sql`
    INSERT INTO hook_tasks (
      hook_id,
      uuid,
      event_type,
      payload_content,
      delivered_at
    ) VALUES (
      ${hookId},
      ${uuid},
      ${eventType},
      ${payloadContent},
      ${deliveredAt}
    )
    RETURNING *
  `;

  return task;
}

/**
 * Deliver webhook payload to configured URL
 */
export async function deliverWebhook(
  webhook: Webhook,
  task: HookTask
): Promise<void> {
  const payloadContent = task.payloadContent;

  // Generate HMAC signatures if secret is configured
  let signatures = { sha1: '', sha256: '' };
  if (webhook.secret) {
    signatures = generateSignature(webhook.secret, payloadContent);
  }

  // Prepare request
  let requestUrl = webhook.url;
  let requestBody: string | undefined;
  const headers: Record<string, string> = {
    'User-Agent': 'Plue-Hookshot/1.0',
    'X-Plue-Delivery': task.uuid,
    'X-Plue-Event': task.eventType,
  };

  // Add GitHub-compatible headers for compatibility
  if (webhook.secret) {
    headers['X-Hub-Signature'] = `sha1=${signatures.sha1}`;
    headers['X-Hub-Signature-256'] = `sha256=${signatures.sha256}`;
    headers['X-Plue-Signature'] = signatures.sha256;
  }

  // Handle different HTTP methods and content types
  if (webhook.httpMethod === 'POST') {
    if (webhook.contentType === 'json') {
      headers['Content-Type'] = 'application/json';
      requestBody = payloadContent;
    } else if (webhook.contentType === 'form') {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      requestBody = `payload=${encodeURIComponent(payloadContent)}`;
    }
  } else if (webhook.httpMethod === 'GET') {
    const url = new URL(webhook.url);
    url.searchParams.set('payload', payloadContent);
    requestUrl = url.toString();
  }

  // Add authorization header if configured
  if (webhook.authorizationHeaderEncrypted) {
    const authHeader = await decryptSecret(webhook.authorizationHeaderEncrypted);
    headers['Authorization'] = authHeader;
  }

  // Store request info
  const requestInfo = {
    url: requestUrl,
    method: webhook.httpMethod,
    headers: { ...headers },
    body: requestBody || '',
  };

  // Redact authorization in stored headers
  if (requestInfo.headers['Authorization']) {
    requestInfo.headers['Authorization'] = '******';
  }

  let responseInfo = {
    status: 0,
    headers: {} as Record<string, string>,
    body: '',
  };

  let isSucceed = false;

  try {
    // Send HTTP request
    const response = await fetch(requestUrl, {
      method: webhook.httpMethod,
      headers,
      body: requestBody,
      // Set timeout to 30 seconds
      signal: AbortSignal.timeout(30000),
    });

    responseInfo.status = response.status;
    responseInfo.headers = Object.fromEntries(response.headers.entries());
    responseInfo.body = await response.text();

    // Consider 2xx status codes as success
    isSucceed = response.status >= 200 && response.status < 300;
  } catch (error: any) {
    responseInfo.status = 0;
    responseInfo.body = error.message || 'Request failed';
    isSucceed = false;
  }

  // Update hook task with delivery results
  await sql`
    UPDATE hook_tasks
    SET
      is_delivered = true,
      is_succeed = ${isSucceed},
      request_info = ${JSON.stringify(requestInfo)},
      response_info = ${JSON.stringify(responseInfo)}
    WHERE id = ${task.id}
  `;

  // Update webhook last status
  await updateWebhookStatus(webhook.id, isSucceed ? 'succeed' : 'fail');
}

/**
 * Trigger webhook for an event
 */
export async function triggerWebhook(
  repositoryId: number,
  eventType: string,
  payload: object
): Promise<void> {
  // Find all active webhooks for this repository that subscribe to this event
  const webhooks = await sql<Webhook[]>`
    SELECT * FROM webhooks
    WHERE repository_id = ${repositoryId}
    AND is_active = true
  `;

  for (const webhook of webhooks) {
    // Check if webhook is subscribed to this event
    const events = webhook.events as Record<string, boolean>;
    if (!events[eventType]) {
      continue;
    }

    // Create hook task
    const task = await createHookTask(webhook.id, eventType, payload);

    // Deliver webhook asynchronously (don't wait for completion)
    deliverWebhook(webhook, task).catch((error) => {
      console.error(`Failed to deliver webhook ${webhook.id}:`, error);
    });
  }
}

/**
 * Replay/redeliver a webhook task
 */
export async function replayHookTask(
  webhookId: number,
  taskUuid: string
): Promise<void> {
  // Get original task
  const [originalTask] = await sql<HookTask[]>`
    SELECT * FROM hook_tasks
    WHERE hook_id = ${webhookId} AND uuid = ${taskUuid}
  `;

  if (!originalTask) {
    throw new Error('Hook task not found');
  }

  // Get webhook
  const webhook = await sql<Webhook[]>`
    SELECT * FROM webhooks WHERE id = ${webhookId}
  `.then(rows => rows[0]);

  if (!webhook) {
    throw new Error('Webhook not found');
  }

  // Create new task with same payload
  const newTask = await createHookTask(
    webhookId,
    originalTask.eventType,
    JSON.parse(originalTask.payloadContent)
  );

  // Deliver the webhook
  await deliverWebhook(webhook, newTask);
}
```

### 3.4 Crypto Utilities (`core/crypto.ts`)

```typescript
import crypto from 'node:crypto';

// Use environment variable for encryption key
const ENCRYPTION_KEY = process.env.WEBHOOK_SECRET_KEY || 'default-encryption-key-change-me';
const ALGORITHM = 'aes-256-gcm';

/**
 * Encrypt a secret string
 */
export async function encryptSecret(plaintext: string): Promise<string> {
  const iv = crypto.randomBytes(16);
  const key = crypto.scryptSync(ENCRYPTION_KEY, 'salt', 32);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);

  let encrypted = cipher.update(plaintext, 'utf8', 'hex');
  encrypted += cipher.final('hex');

  const authTag = cipher.getAuthTag();

  // Return: iv:authTag:encrypted
  return `${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted}`;
}

/**
 * Decrypt a secret string
 */
export async function decryptSecret(ciphertext: string): Promise<string> {
  const [ivHex, authTagHex, encrypted] = ciphertext.split(':');

  const iv = Buffer.from(ivHex, 'hex');
  const authTag = Buffer.from(authTagHex, 'hex');
  const key = crypto.scryptSync(ENCRYPTION_KEY, 'salt', 32);

  const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
  decipher.setAuthTag(authTag);

  let decrypted = decipher.update(encrypted, 'hex', 'utf8');
  decrypted += decipher.final('utf8');

  return decrypted;
}
```

---

## 4. API Routes

### 4.1 Webhook Routes (`server/routes/webhooks.ts`)

```typescript
import { Hono } from 'hono';
import {
  createWebhook,
  getWebhookByRepo,
  listWebhooks,
  updateWebhook,
  deleteWebhook,
  getWebhookHistory,
} from '../../core/webhooks';
import { replayHookTask } from '../../core/webhook-delivery';
import { CreateWebhookSchema } from '../../core/models/webhook';

const app = new Hono();

// List webhooks for a repository
app.get('/:user/:repo/webhooks', async (c) => {
  const { user, repo } = c.req.param();

  // TODO: Get repository ID from user/repo
  const repositoryId = 1; // Placeholder

  const webhooks = await listWebhooks(repositoryId);
  return c.json({ webhooks });
});

// Get single webhook
app.get('/:user/:repo/webhooks/:id', async (c) => {
  const { user, repo, id } = c.req.param();
  const webhookId = parseInt(id);

  // TODO: Get repository ID and check permissions
  const repositoryId = 1; // Placeholder

  const webhook = await getWebhookByRepo(repositoryId, webhookId);

  if (!webhook) {
    return c.json({ error: 'Webhook not found' }, 404);
  }

  return c.json({ webhook });
});

// Create webhook
app.post('/:user/:repo/webhooks', async (c) => {
  const { user, repo } = c.req.param();
  const body = await c.req.json();

  // Validate input
  const input = CreateWebhookSchema.parse(body);

  // TODO: Get repository ID and check permissions
  const repositoryId = 1; // Placeholder

  const webhook = await createWebhook(repositoryId, input);

  return c.json({ webhook }, 201);
});

// Update webhook
app.patch('/:user/:repo/webhooks/:id', async (c) => {
  const { user, repo, id } = c.req.param();
  const webhookId = parseInt(id);
  const body = await c.req.json();

  // TODO: Check permissions

  const webhook = await updateWebhook(webhookId, body);

  return c.json({ webhook });
});

// Delete webhook
app.delete('/:user/:repo/webhooks/:id', async (c) => {
  const { user, repo, id } = c.req.param();
  const webhookId = parseInt(id);

  // TODO: Check permissions

  await deleteWebhook(webhookId);

  return c.json({ success: true });
});

// Get webhook delivery history
app.get('/:user/:repo/webhooks/:id/deliveries', async (c) => {
  const { id } = c.req.param();
  const webhookId = parseInt(id);
  const page = parseInt(c.req.query('page') || '1');

  const deliveries = await getWebhookHistory(webhookId, page);

  return c.json({ deliveries });
});

// Replay/redeliver a webhook
app.post('/:user/:repo/webhooks/:id/deliveries/:uuid/redeliver', async (c) => {
  const { id, uuid } = c.req.param();
  const webhookId = parseInt(id);

  await replayHookTask(webhookId, uuid);

  return c.json({ success: true });
});

// Test webhook (send test ping)
app.post('/:user/:repo/webhooks/:id/test', async (c) => {
  const { user, repo, id } = c.req.param();
  const webhookId = parseInt(id);

  // TODO: Generate and send test payload

  return c.json({ success: true, message: 'Test webhook queued' });
});

export default app;
```

### 4.2 Register Webhook Routes (`server/index.ts`)

```typescript
import webhookRoutes from './routes/webhooks';

// ... existing code ...

app.route('/api', webhookRoutes);
```

---

## 5. Integration with EventBus

### 5.1 Webhook Event Triggers (`core/events.ts`)

Add webhook-specific event types:

```typescript
export const EventTypes = {
  // ... existing events ...

  // Repository events (for webhooks)
  REPO_PUSH: 'repo.push',
  REPO_CREATE: 'repo.create',
  REPO_DELETE: 'repo.delete',
  REPO_FORK: 'repo.fork',

  // Issue events (already exist, but ensure they trigger webhooks)
  ISSUE_OPENED: 'issue.opened',
  ISSUE_CLOSED: 'issue.closed',
  ISSUE_COMMENT_CREATED: 'issue.comment.created',
} as const;
```

### 5.2 Webhook Event Publisher (`core/webhook-events.ts`)

```typescript
import { getEventBus, EventTypes } from './events';
import { triggerWebhook } from './webhook-delivery';
import {
  generatePushPayload,
  generateIssuesPayload,
  generateIssueCommentPayload,
} from './webhook-payloads';

/**
 * Initialize webhook event listeners
 */
export function initializeWebhookListeners() {
  const eventBus = getEventBus();

  // Listen to events and trigger webhooks
  (async () => {
    for await (const event of eventBus.subscribe()) {
      try {
        await handleWebhookEvent(event);
      } catch (error) {
        console.error('Error handling webhook event:', error);
      }
    }
  })();
}

/**
 * Handle events and trigger webhooks
 */
async function handleWebhookEvent(event: Event) {
  switch (event.type) {
    case EventTypes.ISSUE_OPENED:
    case EventTypes.ISSUE_CLOSED:
      await handleIssueEvent(event);
      break;

    case EventTypes.ISSUE_COMMENT_CREATED:
      await handleIssueCommentEvent(event);
      break;

    // Add more event handlers as needed
  }
}

async function handleIssueEvent(event: Event) {
  const { repositoryId, issue, action, sender } = event.properties;

  // TODO: Fetch full repo and user data
  const repo = { /* ... */ };

  const payload = await generateIssuesPayload(action, repo, issue, sender);
  await triggerWebhook(repositoryId, 'issues', payload);
}

async function handleIssueCommentEvent(event: Event) {
  const { repositoryId, issue, comment, sender } = event.properties;

  // TODO: Fetch full repo and user data
  const repo = { /* ... */ };

  const payload = await generateIssueCommentPayload('created', repo, issue, comment, sender);
  await triggerWebhook(repositoryId, 'issue_comment', payload);
}
```

---

## 6. Frontend UI Pages

### 6.1 Webhook List Page (`ui/pages/[user]/[repo]/settings/webhooks.astro`)

```astro
---
import Layout from '../../../../layouts/Layout.astro';
import Header from '../../../../components/Header.astro';
import { sql } from '../../../../lib/db';

const { user: username, repo: reponame } = Astro.params;

// Fetch repository
const [repo] = await sql`
  SELECT r.*, u.username
  FROM repositories r
  JOIN users u ON r.user_id = u.id
  WHERE u.username = ${username} AND r.name = ${reponame}
`;

if (!repo) return Astro.redirect('/404');

// Fetch webhooks
const webhooks = await sql`
  SELECT * FROM webhooks
  WHERE repository_id = ${repo.id}
  ORDER BY created_at DESC
`;
---

<Layout title={`Webhooks · ${username}/${reponame} · plue`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/settings`}>settings</a>
    <span class="sep">/</span>
    <span class="current">webhooks</span>
  </div>

  <div class="container">
    <div class="flex-between mb-3">
      <h1 class="page-title">Webhooks</h1>
      <a href={`/${username}/${reponame}/settings/webhooks/new`} class="btn btn-primary">
        Add webhook
      </a>
    </div>

    {webhooks.length === 0 ? (
      <div class="empty-state">
        <p>No webhooks configured</p>
        <p class="text-muted">
          Webhooks allow external services to be notified when certain events happen.
        </p>
        <a href={`/${username}/${reponame}/settings/webhooks/new`} class="btn mt-2">
          Add your first webhook
        </a>
      </div>
    ) : (
      <div class="webhook-list">
        {webhooks.map((webhook) => (
          <div class="webhook-item">
            <div class="webhook-url">
              <a href={`/${username}/${reponame}/settings/webhooks/${webhook.id}`}>
                {webhook.url}
              </a>
              {!webhook.is_active && <span class="badge badge-inactive">Inactive</span>}
            </div>
            <div class="webhook-meta">
              <span class={`status-badge status-${webhook.last_status}`}>
                {webhook.last_status}
              </span>
              <span class="text-muted">
                Events: {Object.entries(webhook.events).filter(([_, enabled]) => enabled).length}
              </span>
            </div>
          </div>
        ))}
      </div>
    )}
  </div>
</Layout>

<style>
  .webhook-list {
    border: 2px solid var(--border);
  }

  .webhook-item {
    padding: 1rem;
    border-bottom: 2px solid var(--border);
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .webhook-item:last-child {
    border-bottom: none;
  }

  .webhook-url a {
    font-weight: 600;
    color: var(--fg);
  }

  .webhook-meta {
    display: flex;
    gap: 1rem;
    align-items: center;
  }

  .status-badge {
    padding: 0.25rem 0.5rem;
    border: 1px solid;
    font-size: 0.875rem;
  }

  .status-succeed {
    color: green;
    border-color: green;
  }

  .status-fail {
    color: red;
    border-color: red;
  }

  .status-none {
    color: gray;
    border-color: gray;
  }
</style>
```

### 6.2 Webhook Create/Edit Form (`ui/pages/[user]/[repo]/settings/webhooks/new.astro`)

```astro
---
import Layout from '../../../../../layouts/Layout.astro';
import Header from '../../../../../components/Header.astro';

const { user: username, repo: reponame } = Astro.params;

const availableEvents = [
  { key: 'push', label: 'Push', description: 'Git pushes to the repository' },
  { key: 'create', label: 'Create', description: 'Branch or tag creation' },
  { key: 'delete', label: 'Delete', description: 'Branch or tag deletion' },
  { key: 'issues', label: 'Issues', description: 'Issue opened, closed, or edited' },
  { key: 'issue_comment', label: 'Issue comments', description: 'Comments on issues' },
  { key: 'pull_request', label: 'Pull requests', description: 'Pull request opened, closed, or edited' },
  { key: 'release', label: 'Releases', description: 'Release published' },
  { key: 'fork', label: 'Fork', description: 'Repository forked' },
];
---

<Layout title={`Add webhook · ${username}/${reponame} · plue`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/settings/webhooks`}>webhooks</a>
    <span class="sep">/</span>
    <span class="current">new</span>
  </div>

  <div class="container">
    <h1 class="page-title">Add webhook</h1>

    <form id="webhook-form" class="form">
      <div class="form-group">
        <label for="url">Payload URL *</label>
        <input
          type="url"
          id="url"
          name="url"
          required
          placeholder="https://example.com/webhook"
        />
        <small class="text-muted">
          The URL where webhook payloads will be delivered
        </small>
      </div>

      <div class="form-group">
        <label for="content-type">Content type</label>
        <select id="content-type" name="contentType">
          <option value="json">application/json</option>
          <option value="form">application/x-www-form-urlencoded</option>
        </select>
      </div>

      <div class="form-group">
        <label for="secret">Secret</label>
        <input
          type="password"
          id="secret"
          name="secret"
          placeholder="Leave blank for no secret"
        />
        <small class="text-muted">
          Optional secret key for HMAC signature verification
        </small>
      </div>

      <div class="form-group">
        <label>Which events would you like to trigger this webhook?</label>

        <div class="event-selection">
          {availableEvents.map((event) => (
            <label class="event-checkbox">
              <input
                type="checkbox"
                name={`events.${event.key}`}
                value="true"
                checked={event.key === 'push'}
              />
              <div class="event-info">
                <strong>{event.label}</strong>
                <small>{event.description}</small>
              </div>
            </label>
          ))}
        </div>
      </div>

      <div class="form-group">
        <label>
          <input type="checkbox" name="isActive" checked />
          Active
        </label>
        <small class="text-muted">
          Enable this webhook to deliver events
        </small>
      </div>

      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Add webhook</button>
        <a href={`/${username}/${reponame}/settings/webhooks`} class="btn">Cancel</a>
      </div>
    </form>
  </div>
</Layout>

<script>
  const form = document.getElementById('webhook-form') as HTMLFormElement;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();

    const formData = new FormData(form);
    const events: Record<string, boolean> = {};

    // Parse event checkboxes
    for (const [key, value] of formData.entries()) {
      if (key.startsWith('events.')) {
        const eventKey = key.replace('events.', '');
        events[eventKey] = value === 'true';
      }
    }

    const payload = {
      url: formData.get('url'),
      contentType: formData.get('contentType'),
      secret: formData.get('secret') || undefined,
      events,
      isActive: formData.get('isActive') === 'on',
    };

    const response = await fetch(window.location.pathname, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (response.ok) {
      window.location.href = `/${username}/${reponame}/settings/webhooks`;
    } else {
      alert('Failed to create webhook');
    }
  });
</script>

<style>
  .event-selection {
    border: 2px solid var(--border);
    padding: 1rem;
  }

  .event-checkbox {
    display: flex;
    gap: 0.75rem;
    padding: 0.75rem;
    border-bottom: 1px solid var(--border);
    cursor: pointer;
  }

  .event-checkbox:last-child {
    border-bottom: none;
  }

  .event-checkbox:hover {
    background: var(--bg-secondary);
  }

  .event-info {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .event-info strong {
    font-weight: 600;
  }

  .event-info small {
    color: var(--text-muted);
    font-size: 0.875rem;
  }
</style>
```

### 6.3 Webhook Detail/History Page (`ui/pages/[user]/[repo]/settings/webhooks/[id].astro`)

```astro
---
import Layout from '../../../../../layouts/Layout.astro';
import Header from '../../../../../components/Header.astro';
import { sql } from '../../../../../lib/db';

const { user: username, repo: reponame, id } = Astro.params;
const webhookId = parseInt(id);

// Fetch webhook
const [webhook] = await sql`
  SELECT w.*, r.name as repo_name, u.username
  FROM webhooks w
  JOIN repositories r ON w.repository_id = r.id
  JOIN users u ON r.user_id = u.id
  WHERE w.id = ${webhookId}
  AND u.username = ${username}
  AND r.name = ${reponame}
`;

if (!webhook) return Astro.redirect('/404');

// Fetch delivery history
const deliveries = await sql`
  SELECT * FROM hook_tasks
  WHERE hook_id = ${webhookId}
  ORDER BY created_at DESC
  LIMIT 20
`;

const events = webhook.events as Record<string, boolean>;
const activeEvents = Object.entries(events)
  .filter(([_, enabled]) => enabled)
  .map(([event]) => event);
---

<Layout title={`Webhook · ${username}/${reponame} · plue`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/settings/webhooks`}>webhooks</a>
    <span class="sep">/</span>
    <span class="current">{webhook.id}</span>
  </div>

  <div class="container">
    <div class="flex-between mb-3">
      <h1 class="page-title">Webhook</h1>
      <div class="actions">
        <button id="test-webhook" class="btn">Test webhook</button>
        <a href={`/${username}/${reponame}/settings/webhooks/${webhook.id}/edit`} class="btn">
          Edit
        </a>
        <button id="delete-webhook" class="btn btn-danger">Delete</button>
      </div>
    </div>

    <div class="webhook-details">
      <div class="detail-row">
        <strong>URL:</strong>
        <code>{webhook.url}</code>
      </div>
      <div class="detail-row">
        <strong>Content type:</strong>
        <code>{webhook.content_type}</code>
      </div>
      <div class="detail-row">
        <strong>Active events:</strong>
        <div class="event-tags">
          {activeEvents.map(event => (
            <span class="event-tag">{event}</span>
          ))}
        </div>
      </div>
      <div class="detail-row">
        <strong>Status:</strong>
        <span class={`status-badge status-${webhook.last_status}`}>
          {webhook.last_status}
        </span>
      </div>
    </div>

    <h2 class="section-title">Recent deliveries</h2>

    {deliveries.length === 0 ? (
      <div class="empty-state">
        <p>No deliveries yet</p>
      </div>
    ) : (
      <div class="delivery-list">
        {deliveries.map((delivery) => (
          <details class="delivery-item">
            <summary>
              <span class={`delivery-status ${delivery.is_succeed ? 'success' : 'failure'}`}>
                {delivery.is_succeed ? '✓' : '✗'}
              </span>
              <span class="delivery-event">{delivery.event_type}</span>
              <span class="delivery-uuid">{delivery.uuid}</span>
              <span class="delivery-time">
                {new Date(delivery.created_at).toLocaleString()}
              </span>
              {delivery.response_info && (
                <span class="delivery-response-code">
                  {delivery.response_info.status}
                </span>
              )}
              <button
                class="btn-redeliver"
                data-uuid={delivery.uuid}
              >
                Redeliver
              </button>
            </summary>

            <div class="delivery-details">
              <h4>Request</h4>
              <pre><code>{JSON.stringify(delivery.request_info, null, 2)}</code></pre>

              <h4>Response</h4>
              <pre><code>{JSON.stringify(delivery.response_info, null, 2)}</code></pre>
            </div>
          </details>
        ))}
      </div>
    )}
  </div>
</Layout>

<script define:vars={{ webhookId, username, reponame }}>
  // Test webhook
  document.getElementById('test-webhook')?.addEventListener('click', async () => {
    const response = await fetch(
      `/${username}/${reponame}/settings/webhooks/${webhookId}/test`,
      { method: 'POST' }
    );

    if (response.ok) {
      alert('Test webhook sent!');
      location.reload();
    }
  });

  // Delete webhook
  document.getElementById('delete-webhook')?.addEventListener('click', async () => {
    if (!confirm('Are you sure you want to delete this webhook?')) return;

    const response = await fetch(
      `/${username}/${reponame}/settings/webhooks/${webhookId}`,
      { method: 'DELETE' }
    );

    if (response.ok) {
      window.location.href = `/${username}/${reponame}/settings/webhooks`;
    }
  });

  // Redeliver
  document.querySelectorAll('.btn-redeliver').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const uuid = btn.dataset.uuid;

      const response = await fetch(
        `/${username}/${reponame}/settings/webhooks/${webhookId}/deliveries/${uuid}/redeliver`,
        { method: 'POST' }
      );

      if (response.ok) {
        alert('Webhook redelivered!');
        location.reload();
      }
    });
  });
</script>

<style>
  .webhook-details {
    border: 2px solid var(--border);
    padding: 1rem;
    margin-bottom: 2rem;
  }

  .detail-row {
    padding: 0.75rem 0;
    border-bottom: 1px solid var(--border);
    display: flex;
    gap: 1rem;
  }

  .detail-row:last-child {
    border-bottom: none;
  }

  .event-tags {
    display: flex;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .event-tag {
    padding: 0.25rem 0.5rem;
    border: 1px solid var(--border);
    font-size: 0.875rem;
  }

  .delivery-list {
    border: 2px solid var(--border);
  }

  .delivery-item {
    border-bottom: 2px solid var(--border);
  }

  .delivery-item:last-child {
    border-bottom: none;
  }

  .delivery-item summary {
    padding: 1rem;
    cursor: pointer;
    display: flex;
    gap: 1rem;
    align-items: center;
  }

  .delivery-status {
    width: 1.5rem;
    text-align: center;
    font-weight: bold;
  }

  .delivery-status.success {
    color: green;
  }

  .delivery-status.failure {
    color: red;
  }

  .delivery-details {
    padding: 1rem;
    background: var(--bg-secondary);
    border-top: 1px solid var(--border);
  }

  .delivery-details pre {
    background: var(--bg);
    padding: 0.5rem;
    border: 1px solid var(--border);
    overflow-x: auto;
  }
</style>
```

---

## 7. Implementation Checklist

### Phase 1: Database & Core Models
- [ ] Add `webhooks` table to `db/schema.sql`
- [ ] Add `hook_tasks` table to `db/schema.sql`
- [ ] Run database migration
- [ ] Create TypeScript types in `core/models/webhook.ts`
- [ ] Create payload types in `core/models/webhook-payloads.ts`

### Phase 2: Crypto & Security
- [ ] Implement `core/crypto.ts` for secret encryption/decryption
- [ ] Add `WEBHOOK_SECRET_KEY` to `.env`
- [ ] Test encryption/decryption functions

### Phase 3: Core Webhook Logic
- [ ] Implement CRUD operations in `core/webhooks.ts`
- [ ] Implement payload generators in `core/webhook-payloads.ts`
- [ ] Implement delivery service in `core/webhook-delivery.ts`
- [ ] Implement HMAC signature generation
- [ ] Add retry logic for failed deliveries (optional background job)

### Phase 4: API Routes
- [ ] Create `server/routes/webhooks.ts`
- [ ] Implement list webhooks endpoint
- [ ] Implement create webhook endpoint
- [ ] Implement get webhook endpoint
- [ ] Implement update webhook endpoint
- [ ] Implement delete webhook endpoint
- [ ] Implement delivery history endpoint
- [ ] Implement redeliver endpoint
- [ ] Implement test webhook endpoint
- [ ] Register routes in `server/index.ts`

### Phase 5: EventBus Integration
- [ ] Add webhook event types to `core/events.ts`
- [ ] Create `core/webhook-events.ts`
- [ ] Implement event listener initialization
- [ ] Connect issue events to webhook triggers
- [ ] Connect comment events to webhook triggers
- [ ] Test event-to-webhook flow

### Phase 6: Frontend UI
- [ ] Create webhook list page at `ui/pages/[user]/[repo]/settings/webhooks.astro`
- [ ] Create webhook form page at `ui/pages/[user]/[repo]/settings/webhooks/new.astro`
- [ ] Create webhook detail/history page at `ui/pages/[user]/[repo]/settings/webhooks/[id].astro`
- [ ] Add webhook link to repository settings navigation
- [ ] Style webhook pages with brutalist CSS

### Phase 7: Testing
- [ ] Test webhook creation via UI
- [ ] Test webhook event triggering
- [ ] Test HMAC signature validation
- [ ] Test delivery history display
- [ ] Test redeliver functionality
- [ ] Test webhook deletion
- [ ] Test inactive webhook (should not deliver)

### Phase 8: Documentation
- [ ] Document webhook event types
- [ ] Document payload formats
- [ ] Document HMAC signature verification
- [ ] Add webhook examples to README

---

## 8. Reference Code from Gitea

### 8.1 Webhook Model Structure

**From `gitea/models/webhook/webhook.go`:**

```go
type Webhook struct {
    ID                        int64
    RepoID                    int64
    URL                       string
    HTTPMethod                string
    ContentType               HookContentType
    Secret                    string
    Events                    string // JSON
    IsActive                  bool
    LastStatus                webhook_module.HookStatus
    HeaderAuthorizationEncrypted string
    CreatedUnix               timeutil.TimeStamp
    UpdatedUnix               timeutil.TimeStamp
}
```

**TypeScript equivalent:**
```typescript
interface Webhook {
  id: number;
  repositoryId: number;
  url: string;
  httpMethod: 'POST' | 'GET' | 'PUT';
  contentType: 'json' | 'form';
  secret?: string;
  events: Record<string, boolean>;
  isActive: boolean;
  lastStatus: 'none' | 'succeed' | 'fail';
  authorizationHeaderEncrypted?: string;
  createdAt: Date;
  updatedAt: Date;
}
```

### 8.2 Hook Task Structure

**From `gitea/models/webhook/hooktask.go`:**

```go
type HookTask struct {
    ID              int64
    HookID          int64
    UUID            string
    PayloadContent  string
    EventType       webhook_module.HookEventType
    IsDelivered     bool
    Delivered       timeutil.TimeStampNano
    IsSucceed       bool
    RequestContent  string
    ResponseContent string
}
```

**TypeScript equivalent:**
```typescript
interface HookTask {
  id: number;
  hookId: number;
  uuid: string;
  payloadContent: string;
  eventType: string;
  isDelivered: boolean;
  deliveredAt?: number; // nanoseconds
  isSucceed: boolean;
  requestInfo?: {
    url: string;
    method: string;
    headers: Record<string, string>;
    body: string;
  };
  responseInfo?: {
    status: number;
    headers: Record<string, string>;
    body: string;
  };
}
```

### 8.3 HMAC Signature Generation

**From `gitea/services/webhook/deliver.go`:**

```go
func addDefaultHeaders(req *http.Request, secret []byte, w *webhook_model.Webhook, t *webhook_model.HookTask, payloadContent []byte) error {
    var signatureSHA1 string
    var signatureSHA256 string
    if len(secret) > 0 {
        sig1 := hmac.New(sha1.New, secret)
        sig256 := hmac.New(sha256.New, secret)
        io.MultiWriter(sig1, sig256).Write(payloadContent)
        signatureSHA1 = hex.EncodeToString(sig1.Sum(nil))
        signatureSHA256 = hex.EncodeToString(sig256.Sum(nil))
    }

    req.Header.Add("X-Hub-Signature", "sha1="+signatureSHA1)
    req.Header.Add("X-Hub-Signature-256", "sha256="+signatureSHA256)
    // ... more headers
}
```

**TypeScript equivalent:**
```typescript
import crypto from 'node:crypto';

function generateSignature(secret: string, payload: string) {
  const hmacSHA1 = crypto.createHmac('sha1', secret);
  const hmacSHA256 = crypto.createHmac('sha256', secret);

  hmacSHA1.update(payload);
  hmacSHA256.update(payload);

  return {
    sha1: hmacSHA1.digest('hex'),
    sha256: hmacSHA256.digest('hex'),
  };
}
```

### 8.4 Event Types

**From `gitea/modules/webhook/type.go`:**

```go
const (
    HookEventCreate                    HookEventType = "create"
    HookEventDelete                    HookEventType = "delete"
    HookEventFork                      HookEventType = "fork"
    HookEventPush                      HookEventType = "push"
    HookEventIssues                    HookEventType = "issues"
    HookEventIssueComment              HookEventType = "issue_comment"
    HookEventPullRequest               HookEventType = "pull_request"
    HookEventPullRequestComment        HookEventType = "pull_request_comment"
    HookEventRelease                   HookEventType = "release"
    // ... more
)
```

---

## 9. Testing Examples

### 9.1 Test Webhook with RequestBin

```bash
# Create a webhook pointing to https://requestbin.com endpoint
# Trigger an event (create issue, add comment, etc.)
# Verify payload in RequestBin
```

### 9.2 Verify HMAC Signature

```python
# Python example to verify webhook signature
import hmac
import hashlib

def verify_signature(payload, signature, secret):
    expected = hmac.new(
        secret.encode(),
        payload.encode(),
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(signature, expected)
```

### 9.3 Example Webhook Payload

```json
{
  "action": "opened",
  "issue": {
    "id": 1,
    "number": 42,
    "title": "Bug report",
    "body": "Something is broken",
    "state": "open",
    "html_url": "https://plue.dev/user/repo/issues/42",
    "user": {
      "id": 1,
      "username": "evilrabbit"
    },
    "created_at": "2025-01-01T00:00:00Z",
    "updated_at": "2025-01-01T00:00:00Z",
    "closed_at": null
  },
  "repository": {
    "id": 1,
    "name": "repo",
    "full_name": "user/repo",
    "description": "A repository",
    "html_url": "https://plue.dev/user/repo",
    "default_branch": "main"
  },
  "sender": {
    "id": 1,
    "username": "evilrabbit",
    "html_url": "https://plue.dev/evilrabbit"
  }
}
```

---

## 10. Notes

- **Security**: Always encrypt secrets (webhook secret, authorization headers) before storing in database
- **HMAC Signatures**: Include both SHA1 (for GitHub compatibility) and SHA256 headers
- **Retry Logic**: Consider implementing exponential backoff for failed deliveries
- **Rate Limiting**: Add rate limiting to prevent webhook abuse
- **Async Delivery**: Webhook delivery should be non-blocking (use background jobs)
- **Timeout**: Set reasonable timeout (30s) for webhook HTTP requests
- **Logging**: Log all webhook deliveries for debugging
- **Validation**: Validate webhook URLs to prevent SSRF attacks (no localhost, private IPs)
- **Test Button**: Implement test webhook that sends a ping event with fake payload

---

## 11. Future Enhancements

- [ ] Webhook templates for popular services (Slack, Discord, etc.)
- [ ] Custom headers configuration
- [ ] Webhook event filtering by branch/tag patterns
- [ ] Bulk webhook management (enable/disable all)
- [ ] Webhook analytics dashboard
- [ ] Webhook payload transformation/customization
- [ ] Organization-level webhooks (not just repo-level)
- [ ] Webhook secret rotation
- [ ] Delivery queue with priority
- [ ] Webhook proxy for debugging
