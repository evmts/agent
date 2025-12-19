# CI/CD Actions Feature Implementation

## Overview

Implement a GitHub Actions / Gitea Actions-compatible CI/CD system for Plue, allowing repositories to define and execute automated workflows via YAML files in `.github/workflows/` or `.gitea/workflows/`. This enables automated testing, building, deployment, and custom automation triggered by repository events (push, pull requests, releases, etc.).

**Scope**: MVP implementation covering workflow YAML parsing, workflow run execution, job/step visualization UI, runner registration and management, basic secrets management, and artifacts upload/download. Advanced features like matrix builds, caching strategies, and self-hosted runner pools are noted but not required for initial implementation.

**Stack**: Bun runtime, Hono API server, Astro SSR frontend, PostgreSQL database, integration with existing git operations and EventBus.

---

## 1. Database Schema Changes

### 1.1 Action Runs Table

```sql
-- Represents a complete workflow run (triggered by an event)
CREATE TABLE IF NOT EXISTS action_runs (
  id SERIAL PRIMARY KEY,

  -- Repository association
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  owner_id INTEGER NOT NULL, -- For faster queries

  -- Workflow identification
  workflow_id VARCHAR(255) NOT NULL, -- Filename like "ci.yml"
  title VARCHAR(512) NOT NULL, -- Workflow title from YAML
  run_index BIGINT NOT NULL, -- Sequential per-repo run number

  -- Trigger information
  trigger_user_id INTEGER REFERENCES users(id),
  trigger_event VARCHAR(50) NOT NULL, -- 'push', 'pull_request', 'release', etc.
  event_payload TEXT, -- JSON event payload

  -- Git reference
  ref VARCHAR(255) NOT NULL, -- 'refs/heads/main', 'refs/tags/v1.0.0', etc.
  commit_sha VARCHAR(64) NOT NULL,

  -- Status tracking
  status VARCHAR(20) NOT NULL DEFAULT 'waiting'
    CHECK (status IN ('waiting', 'blocked', 'running', 'success', 'failure', 'cancelled', 'skipped')),

  -- Timing
  started BIGINT, -- Unix timestamp (milliseconds)
  stopped BIGINT, -- Unix timestamp (milliseconds)
  previous_duration BIGINT DEFAULT 0, -- For rerun tracking (milliseconds)

  -- Concurrency control
  concurrency_group VARCHAR(255) DEFAULT '',
  concurrency_cancel BOOLEAN DEFAULT false,

  -- Approval (for fork PRs)
  need_approval BOOLEAN DEFAULT false,
  approved_by INTEGER REFERENCES users(id),

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(repository_id, run_index)
);

CREATE INDEX idx_action_runs_repository ON action_runs(repository_id);
CREATE INDEX idx_action_runs_workflow ON action_runs(workflow_id);
CREATE INDEX idx_action_runs_status ON action_runs(status);
CREATE INDEX idx_action_runs_commit ON action_runs(commit_sha);
CREATE INDEX idx_action_runs_ref ON action_runs(ref);
CREATE INDEX idx_action_runs_concurrency ON action_runs(repository_id, concurrency_group);
```

### 1.2 Action Jobs Table

```sql
-- Represents a single job within a workflow run
CREATE TABLE IF NOT EXISTS action_jobs (
  id SERIAL PRIMARY KEY,

  -- Run association
  run_id BIGINT NOT NULL REFERENCES action_runs(id) ON DELETE CASCADE,
  repository_id INTEGER NOT NULL,
  owner_id INTEGER NOT NULL,

  -- Job identification
  job_id VARCHAR(255) NOT NULL, -- Job ID from YAML (e.g., 'build', 'test')
  name VARCHAR(512) NOT NULL, -- Job display name
  attempt BIGINT DEFAULT 1, -- Retry attempt number

  -- Job definition (stored as JSON)
  workflow_payload BYTEA, -- Complete job YAML + workflow globals
  needs JSONB DEFAULT '[]', -- Array of job IDs this job depends on
  runs_on JSONB DEFAULT '[]', -- Array of runner labels (e.g., ['ubuntu-latest'])

  -- Task tracking
  task_id BIGINT, -- Current/latest task ID assigned to this job

  -- Status
  status VARCHAR(20) NOT NULL DEFAULT 'waiting'
    CHECK (status IN ('waiting', 'blocked', 'running', 'success', 'failure', 'cancelled', 'skipped')),

  -- Timing
  started BIGINT,
  stopped BIGINT,

  -- Concurrency (job-level)
  concurrency_group VARCHAR(255) DEFAULT '',
  concurrency_cancel BOOLEAN DEFAULT false,
  concurrency_evaluated BOOLEAN DEFAULT false,

  commit_sha VARCHAR(64) NOT NULL,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_action_jobs_run ON action_jobs(run_id);
CREATE INDEX idx_action_jobs_repository ON action_jobs(repository_id);
CREATE INDEX idx_action_jobs_status ON action_jobs(status);
CREATE INDEX idx_action_jobs_task ON action_jobs(task_id);
CREATE INDEX idx_action_jobs_concurrency ON action_jobs(repository_id, concurrency_group);
```

### 1.3 Action Tasks Table

```sql
-- Represents a distribution of a job to a specific runner
CREATE TABLE IF NOT EXISTS action_tasks (
  id SERIAL PRIMARY KEY,

  -- Job association
  job_id BIGINT NOT NULL REFERENCES action_jobs(id) ON DELETE CASCADE,
  runner_id BIGINT, -- NULL if not yet assigned

  repository_id INTEGER NOT NULL,
  owner_id INTEGER NOT NULL,
  commit_sha VARCHAR(64) NOT NULL,

  -- Attempt tracking
  attempt BIGINT NOT NULL DEFAULT 1,

  -- Status
  status VARCHAR(20) NOT NULL DEFAULT 'waiting'
    CHECK (status IN ('waiting', 'running', 'success', 'failure', 'cancelled', 'skipped')),

  -- Timing
  started BIGINT,
  stopped BIGINT,

  -- Security token for runner authentication
  token_hash VARCHAR(64) UNIQUE,
  token_salt VARCHAR(64),
  token_last_eight VARCHAR(8),

  -- Log tracking
  log_filename VARCHAR(512),
  log_size BIGINT DEFAULT 0,
  log_length BIGINT DEFAULT 0, -- Line count
  log_expired BOOLEAN DEFAULT false,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_action_tasks_job ON action_tasks(job_id);
CREATE INDEX idx_action_tasks_runner ON action_tasks(runner_id);
CREATE INDEX idx_action_tasks_status ON action_tasks(status);
CREATE INDEX idx_action_tasks_token ON action_tasks(token_last_eight);
CREATE INDEX idx_action_tasks_log_expired ON action_tasks(stopped, log_expired);
```

### 1.4 Action Task Steps Table

```sql
-- Represents individual steps within a task
CREATE TABLE IF NOT EXISTS action_task_steps (
  id SERIAL PRIMARY KEY,

  -- Task association
  task_id BIGINT NOT NULL REFERENCES action_tasks(id) ON DELETE CASCADE,
  repository_id INTEGER NOT NULL,

  -- Step details
  step_index BIGINT NOT NULL, -- Order within the task (0-indexed)
  name VARCHAR(512) NOT NULL,

  -- Status
  status VARCHAR(20) NOT NULL DEFAULT 'waiting'
    CHECK (status IN ('waiting', 'running', 'success', 'failure', 'cancelled', 'skipped')),

  -- Timing
  started BIGINT,
  stopped BIGINT,

  -- Log tracking (offsets into task log)
  log_index BIGINT DEFAULT 0, -- Start offset in log
  log_length BIGINT DEFAULT 0, -- Number of log lines

  created_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(task_id, step_index)
);

CREATE INDEX idx_action_task_steps_task ON action_task_steps(task_id);
```

### 1.5 Action Runners Table

```sql
-- Represents runner agents that execute jobs
CREATE TABLE IF NOT EXISTS action_runners (
  id SERIAL PRIMARY KEY,

  -- Runner identification
  uuid VARCHAR(36) UNIQUE NOT NULL,
  name VARCHAR(255) NOT NULL,
  version VARCHAR(64), -- Runner version

  -- Scope (one of these will be non-zero)
  owner_id INTEGER, -- Org/user-level runner
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE, -- Repo-level runner
  -- Both 0 means global runner

  description TEXT,

  -- Security token
  token_hash VARCHAR(64) UNIQUE NOT NULL,
  token_salt VARCHAR(64) NOT NULL,

  -- Labels (JSON array of strings)
  agent_labels JSONB NOT NULL DEFAULT '[]', -- e.g., ["ubuntu-latest", "self-hosted"]

  -- Status tracking
  last_online BIGINT, -- Unix timestamp (milliseconds)
  last_active BIGINT, -- Unix timestamp (milliseconds)

  -- Ephemeral runners (auto-delete after job completion)
  ephemeral BOOLEAN DEFAULT false,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP
);

CREATE INDEX idx_action_runners_owner ON action_runners(owner_id);
CREATE INDEX idx_action_runners_repo ON action_runners(repository_id);
CREATE INDEX idx_action_runners_uuid ON action_runners(uuid);
CREATE INDEX idx_action_runners_last_online ON action_runners(last_online);
```

### 1.6 Action Secrets Table

```sql
-- Encrypted secrets for workflows
CREATE TABLE IF NOT EXISTS action_secrets (
  id SERIAL PRIMARY KEY,

  -- Scope (one of these will be non-zero)
  owner_id INTEGER, -- Org/user-level secret
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE, -- Repo-level secret
  -- Both 0 means global secret (admin only)

  -- Secret identification
  name VARCHAR(255) NOT NULL,

  -- Encrypted data (use crypto.createCipher or similar)
  data_encrypted TEXT NOT NULL,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(owner_id, repository_id, name)
);

CREATE INDEX idx_action_secrets_owner ON action_secrets(owner_id);
CREATE INDEX idx_action_secrets_repo ON action_secrets(repository_id);
```

### 1.7 Action Variables Table

```sql
-- Non-sensitive environment variables for workflows
CREATE TABLE IF NOT EXISTS action_variables (
  id SERIAL PRIMARY KEY,

  -- Scope (one of these will be non-zero)
  owner_id INTEGER, -- Org/user-level variable
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE, -- Repo-level variable
  -- Both 0 means global variable

  -- Variable identification
  name VARCHAR(255) NOT NULL,

  -- Unencrypted data
  data TEXT NOT NULL,
  description TEXT,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(owner_id, repository_id, name)
);

CREATE INDEX idx_action_variables_owner ON action_variables(owner_id);
CREATE INDEX idx_action_variables_repo ON action_variables(repository_id);
```

### 1.8 Action Artifacts Table

```sql
-- Artifacts uploaded by workflow runs
CREATE TABLE IF NOT EXISTS action_artifacts (
  id SERIAL PRIMARY KEY,

  -- Run association
  run_id BIGINT NOT NULL REFERENCES action_runs(id) ON DELETE CASCADE,
  runner_id BIGINT,
  repository_id INTEGER NOT NULL,
  owner_id INTEGER NOT NULL,
  commit_sha VARCHAR(64) NOT NULL,

  -- Artifact identification
  artifact_name VARCHAR(255) NOT NULL, -- E.g., 'build-output'
  artifact_path VARCHAR(512) NOT NULL, -- Path within artifact (for multi-file artifacts)

  -- Storage
  storage_path VARCHAR(512) NOT NULL, -- Path in object storage
  file_size BIGINT NOT NULL,
  file_compressed_size BIGINT,
  content_encoding VARCHAR(50), -- 'gzip', 'application/zip', etc.

  -- Status
  status VARCHAR(20) NOT NULL DEFAULT 'upload_pending'
    CHECK (status IN ('upload_pending', 'upload_confirmed', 'upload_error', 'expired', 'pending_deletion', 'deleted')),

  -- Expiration
  expired_at BIGINT, -- Unix timestamp (milliseconds)

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(run_id, artifact_name, artifact_path)
);

CREATE INDEX idx_action_artifacts_run ON action_artifacts(run_id);
CREATE INDEX idx_action_artifacts_repository ON action_artifacts(repository_id);
CREATE INDEX idx_action_artifacts_status ON action_artifacts(status);
CREATE INDEX idx_action_artifacts_expired ON action_artifacts(expired_at);
```

---

## 2. TypeScript Type Definitions

### 2.1 Actions Core Types (`core/models/actions.ts`)

```typescript
import { z } from 'zod';

// Status enum shared across runs/jobs/tasks
export const ActionStatus = z.enum([
  'waiting',
  'blocked',
  'running',
  'success',
  'failure',
  'cancelled',
  'skipped',
]);
export type ActionStatus = z.infer<typeof ActionStatus>;

// Event types that trigger workflows
export const ActionEventType = z.enum([
  'push',
  'pull_request',
  'pull_request_target',
  'pull_request_review',
  'pull_request_comment',
  'issue_comment',
  'issues',
  'create',
  'delete',
  'release',
  'fork',
  'schedule',
  'workflow_dispatch',
  'repository_dispatch',
]);
export type ActionEventType = z.infer<typeof ActionEventType>;

// Action Run
export const ActionRunSchema = z.object({
  id: z.number(),
  repositoryId: z.number(),
  ownerId: z.number(),
  workflowId: z.string(),
  title: z.string(),
  runIndex: z.number(),
  triggerUserId: z.number().optional(),
  triggerEvent: ActionEventType,
  eventPayload: z.string().optional(), // JSON string
  ref: z.string(), // 'refs/heads/main'
  commitSha: z.string(),
  status: ActionStatus,
  started: z.number().optional(),
  stopped: z.number().optional(),
  previousDuration: z.number().default(0),
  concurrencyGroup: z.string().default(''),
  concurrencyCancel: z.boolean().default(false),
  needApproval: z.boolean().default(false),
  approvedBy: z.number().optional(),
  createdAt: z.date(),
  updatedAt: z.date(),
});
export type ActionRun = z.infer<typeof ActionRunSchema>;

// Action Job
export const ActionJobSchema = z.object({
  id: z.number(),
  runId: z.number(),
  repositoryId: z.number(),
  ownerId: z.number(),
  jobId: z.string(), // From YAML
  name: z.string(),
  attempt: z.number().default(1),
  workflowPayload: z.instanceof(Buffer).optional(), // Stored as bytea
  needs: z.array(z.string()).default([]),
  runsOn: z.array(z.string()).default([]),
  taskId: z.number().optional(),
  status: ActionStatus,
  started: z.number().optional(),
  stopped: z.number().optional(),
  concurrencyGroup: z.string().default(''),
  concurrencyCancel: z.boolean().default(false),
  concurrencyEvaluated: z.boolean().default(false),
  commitSha: z.string(),
  createdAt: z.date(),
  updatedAt: z.date(),
});
export type ActionJob = z.infer<typeof ActionJobSchema>;

// Action Task
export const ActionTaskSchema = z.object({
  id: z.number(),
  jobId: z.number(),
  runnerId: z.number().optional(),
  repositoryId: z.number(),
  ownerId: z.number(),
  commitSha: z.string(),
  attempt: z.number().default(1),
  status: ActionStatus,
  started: z.number().optional(),
  stopped: z.number().optional(),
  tokenHash: z.string().optional(),
  tokenSalt: z.string().optional(),
  tokenLastEight: z.string().optional(),
  logFilename: z.string().optional(),
  logSize: z.number().default(0),
  logLength: z.number().default(0),
  logExpired: z.boolean().default(false),
  createdAt: z.date(),
  updatedAt: z.date(),
});
export type ActionTask = z.infer<typeof ActionTaskSchema>;

// Action Task Step
export const ActionTaskStepSchema = z.object({
  id: z.number(),
  taskId: z.number(),
  repositoryId: z.number(),
  stepIndex: z.number(),
  name: z.string(),
  status: ActionStatus,
  started: z.number().optional(),
  stopped: z.number().optional(),
  logIndex: z.number().default(0),
  logLength: z.number().default(0),
  createdAt: z.date(),
});
export type ActionTaskStep = z.infer<typeof ActionTaskStepSchema>;

// Action Runner
export const ActionRunnerSchema = z.object({
  id: z.number(),
  uuid: z.string().uuid(),
  name: z.string(),
  version: z.string().optional(),
  ownerId: z.number().optional(),
  repositoryId: z.number().optional(),
  description: z.string().optional(),
  tokenHash: z.string(),
  tokenSalt: z.string(),
  agentLabels: z.array(z.string()).default([]),
  lastOnline: z.number().optional(),
  lastActive: z.number().optional(),
  ephemeral: z.boolean().default(false),
  createdAt: z.date(),
  updatedAt: z.date(),
  deletedAt: z.date().optional(),
});
export type ActionRunner = z.infer<typeof ActionRunnerSchema>;

// Action Secret
export const ActionSecretSchema = z.object({
  id: z.number(),
  ownerId: z.number().optional(),
  repositoryId: z.number().optional(),
  name: z.string(),
  dataEncrypted: z.string(),
  createdAt: z.date(),
  updatedAt: z.date(),
});
export type ActionSecret = z.infer<typeof ActionSecretSchema>;

// Action Variable
export const ActionVariableSchema = z.object({
  id: z.number(),
  ownerId: z.number().optional(),
  repositoryId: z.number().optional(),
  name: z.string(),
  data: z.string(),
  description: z.string().optional(),
  createdAt: z.date(),
  updatedAt: z.date(),
});
export type ActionVariable = z.infer<typeof ActionVariableSchema>;

// Action Artifact
export const ArtifactStatus = z.enum([
  'upload_pending',
  'upload_confirmed',
  'upload_error',
  'expired',
  'pending_deletion',
  'deleted',
]);
export type ArtifactStatus = z.infer<typeof ArtifactStatus>;

export const ActionArtifactSchema = z.object({
  id: z.number(),
  runId: z.number(),
  runnerId: z.number().optional(),
  repositoryId: z.number(),
  ownerId: z.number(),
  commitSha: z.string(),
  artifactName: z.string(),
  artifactPath: z.string(),
  storagePath: z.string(),
  fileSize: z.number(),
  fileCompressedSize: z.number().optional(),
  contentEncoding: z.string().optional(),
  status: ArtifactStatus,
  expiredAt: z.number().optional(),
  createdAt: z.date(),
  updatedAt: z.date(),
});
export type ActionArtifact = z.infer<typeof ActionArtifactSchema>;
```

### 2.2 Workflow YAML Types (`core/models/workflow.ts`)

```typescript
// Simplified workflow structure (based on GitHub Actions spec)
export interface WorkflowFile {
  name?: string;
  on: WorkflowTrigger;
  env?: Record<string, string>;
  jobs: Record<string, WorkflowJob>;
  concurrency?: string | {
    group: string;
    'cancel-in-progress'?: boolean;
  };
}

export type WorkflowTrigger =
  | string // Simple: "push"
  | string[] // Multiple: ["push", "pull_request"]
  | Record<string, WorkflowEventConfig>; // Complex

export interface WorkflowEventConfig {
  branches?: string[];
  'branches-ignore'?: string[];
  tags?: string[];
  'tags-ignore'?: string[];
  paths?: string[];
  'paths-ignore'?: string[];
  types?: string[]; // For issues, pull_request, etc.
}

export interface WorkflowJob {
  name?: string;
  'runs-on': string | string[]; // Runner labels
  needs?: string | string[]; // Job dependencies
  if?: string; // Conditional expression
  env?: Record<string, string>;
  steps: WorkflowStep[];
  timeout?: number; // Minutes
  concurrency?: string | {
    group: string;
    'cancel-in-progress'?: boolean;
  };
}

export interface WorkflowStep {
  name?: string;
  id?: string;
  if?: string;
  uses?: string; // Action to use (e.g., 'actions/checkout@v3')
  run?: string; // Shell command
  with?: Record<string, string | number | boolean>; // Action inputs
  env?: Record<string, string>;
  'continue-on-error'?: boolean;
  'timeout-minutes'?: number;
}
```

---

## 3. Database Layer

### 3.1 Action Runs DB Functions (`db/action-runs.ts`)

```typescript
import { db } from './index';
import type { ActionRun, ActionStatus } from '../core/models/actions';

export async function createActionRun(data: {
  repositoryId: number;
  ownerId: number;
  workflowId: string;
  title: string;
  triggerUserId?: number;
  triggerEvent: string;
  eventPayload?: string;
  ref: string;
  commitSha: string;
  concurrencyGroup?: string;
  concurrencyCancel?: boolean;
  needApproval?: boolean;
}): Promise<ActionRun> {
  // Get next run index for this repository
  const result = await db.query<{ max: number }>(
    'SELECT COALESCE(MAX(run_index), 0) + 1 as max FROM action_runs WHERE repository_id = $1',
    [data.repositoryId]
  );
  const runIndex = result.rows[0].max;

  const insertResult = await db.query(
    `INSERT INTO action_runs (
      repository_id, owner_id, workflow_id, title, run_index,
      trigger_user_id, trigger_event, event_payload, ref, commit_sha,
      concurrency_group, concurrency_cancel, need_approval, status
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, 'waiting')
    RETURNING *`,
    [
      data.repositoryId,
      data.ownerId,
      data.workflowId,
      data.title,
      runIndex,
      data.triggerUserId,
      data.triggerEvent,
      data.eventPayload,
      data.ref,
      data.commitSha,
      data.concurrencyGroup || '',
      data.concurrencyCancel || false,
      data.needApproval || false,
    ]
  );

  return insertResult.rows[0];
}

export async function getActionRunByIndex(
  repositoryId: number,
  runIndex: number
): Promise<ActionRun | null> {
  const result = await db.query(
    'SELECT * FROM action_runs WHERE repository_id = $1 AND run_index = $2',
    [repositoryId, runIndex]
  );
  return result.rows[0] || null;
}

export async function listActionRuns(
  repositoryId: number,
  options?: {
    status?: ActionStatus;
    workflowId?: string;
    limit?: number;
    offset?: number;
  }
): Promise<ActionRun[]> {
  let query = 'SELECT * FROM action_runs WHERE repository_id = $1';
  const params: unknown[] = [repositoryId];
  let paramIndex = 2;

  if (options?.status) {
    query += ` AND status = $${paramIndex}`;
    params.push(options.status);
    paramIndex++;
  }

  if (options?.workflowId) {
    query += ` AND workflow_id = $${paramIndex}`;
    params.push(options.workflowId);
    paramIndex++;
  }

  query += ' ORDER BY run_index DESC';

  if (options?.limit) {
    query += ` LIMIT $${paramIndex}`;
    params.push(options.limit);
    paramIndex++;
  }

  if (options?.offset) {
    query += ` OFFSET $${paramIndex}`;
    params.push(options.offset);
  }

  const result = await db.query(query, params);
  return result.rows;
}

export async function updateActionRunStatus(
  id: number,
  status: ActionStatus,
  opts?: {
    started?: number;
    stopped?: number;
  }
): Promise<void> {
  const updates: string[] = ['status = $2', 'updated_at = NOW()'];
  const params: unknown[] = [id, status];
  let paramIndex = 3;

  if (opts?.started) {
    updates.push(`started = $${paramIndex}`);
    params.push(opts.started);
    paramIndex++;
  }

  if (opts?.stopped) {
    updates.push(`stopped = $${paramIndex}`);
    params.push(opts.stopped);
    paramIndex++;
  }

  await db.query(
    `UPDATE action_runs SET ${updates.join(', ')} WHERE id = $1`,
    params
  );
}

export async function cancelActionRun(runId: number): Promise<void> {
  await db.query(
    `UPDATE action_runs SET status = 'cancelled', stopped = $2, updated_at = NOW()
     WHERE id = $1 AND status IN ('waiting', 'running', 'blocked')`,
    [runId, Date.now()]
  );
}
```

### 3.2 Action Jobs DB Functions (`db/action-jobs.ts`)

```typescript
import { db } from './index';
import type { ActionJob, ActionStatus } from '../core/models/actions';

export async function createActionJob(data: {
  runId: number;
  repositoryId: number;
  ownerId: number;
  jobId: string;
  name: string;
  workflowPayload?: Buffer;
  needs?: string[];
  runsOn?: string[];
  commitSha: string;
  concurrencyGroup?: string;
  concurrencyCancel?: boolean;
}): Promise<ActionJob> {
  const result = await db.query(
    `INSERT INTO action_jobs (
      run_id, repository_id, owner_id, job_id, name,
      workflow_payload, needs, runs_on, commit_sha,
      concurrency_group, concurrency_cancel, status
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'waiting')
    RETURNING *`,
    [
      data.runId,
      data.repositoryId,
      data.ownerId,
      data.jobId,
      data.name,
      data.workflowPayload,
      JSON.stringify(data.needs || []),
      JSON.stringify(data.runsOn || []),
      data.commitSha,
      data.concurrencyGroup || '',
      data.concurrencyCancel || false,
    ]
  );

  return result.rows[0];
}

export async function getJobsByRunId(runId: number): Promise<ActionJob[]> {
  const result = await db.query(
    'SELECT * FROM action_jobs WHERE run_id = $1 ORDER BY id',
    [runId]
  );
  return result.rows;
}

export async function updateJobStatus(
  id: number,
  status: ActionStatus,
  opts?: {
    started?: number;
    stopped?: number;
    taskId?: number;
  }
): Promise<void> {
  const updates: string[] = ['status = $2', 'updated_at = NOW()'];
  const params: unknown[] = [id, status];
  let paramIndex = 3;

  if (opts?.started) {
    updates.push(`started = $${paramIndex}`);
    params.push(opts.started);
    paramIndex++;
  }

  if (opts?.stopped) {
    updates.push(`stopped = $${paramIndex}`);
    params.push(opts.stopped);
    paramIndex++;
  }

  if (opts?.taskId) {
    updates.push(`task_id = $${paramIndex}`);
    params.push(opts.taskId);
    paramIndex++;
  }

  await db.query(
    `UPDATE action_jobs SET ${updates.join(', ')} WHERE id = $1`,
    params
  );
}

// Aggregate job statuses to determine run status
export function aggregateJobStatus(jobs: ActionJob[]): ActionStatus {
  if (jobs.length === 0) return 'waiting';

  const allSuccessOrSkipped = jobs.every(
    (j) => j.status === 'success' || j.status === 'skipped'
  );
  const allSkipped = jobs.every((j) => j.status === 'skipped');
  const hasFailure = jobs.some((j) => j.status === 'failure');
  const hasCancelled = jobs.some((j) => j.status === 'cancelled');
  const hasRunning = jobs.some((j) => j.status === 'running');
  const hasWaiting = jobs.some((j) => j.status === 'waiting');
  const hasBlocked = jobs.some((j) => j.status === 'blocked');

  if (allSkipped) return 'skipped';
  if (allSuccessOrSkipped) return 'success';
  if (hasCancelled) return 'cancelled';
  if (hasRunning) return 'running';
  if (hasWaiting) return 'waiting';
  if (hasFailure) return 'failure';
  if (hasBlocked) return 'blocked';

  return 'waiting';
}
```

### 3.3 Action Runners DB Functions (`db/action-runners.ts`)

```typescript
import { db } from './index';
import type { ActionRunner } from '../core/models/actions';
import { createHash, randomBytes } from 'crypto';

export async function createActionRunner(data: {
  name: string;
  ownerId?: number;
  repositoryId?: number;
  description?: string;
  agentLabels?: string[];
  ephemeral?: boolean;
}): Promise<{ runner: ActionRunner; token: string }> {
  // Generate UUID and token
  const uuid = randomUUID();
  const token = randomBytes(20).toString('hex'); // 40 chars
  const tokenSalt = randomBytes(10).toString('hex');
  const tokenHash = createHash('sha256')
    .update(token + tokenSalt)
    .digest('hex');

  const result = await db.query(
    `INSERT INTO action_runners (
      uuid, name, owner_id, repository_id, description,
      token_hash, token_salt, agent_labels, ephemeral
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    RETURNING *`,
    [
      uuid,
      data.name,
      data.ownerId || null,
      data.repositoryId || null,
      data.description,
      tokenHash,
      tokenSalt,
      JSON.stringify(data.agentLabels || []),
      data.ephemeral || false,
    ]
  );

  return {
    runner: result.rows[0],
    token, // Return plaintext token only on creation
  };
}

export async function getRunnerByUUID(uuid: string): Promise<ActionRunner | null> {
  const result = await db.query(
    'SELECT * FROM action_runners WHERE uuid = $1 AND deleted_at IS NULL',
    [uuid]
  );
  return result.rows[0] || null;
}

export async function listRunners(options?: {
  repositoryId?: number;
  ownerId?: number;
  includeGlobal?: boolean; // Include global runners
}): Promise<ActionRunner[]> {
  let query = 'SELECT * FROM action_runners WHERE deleted_at IS NULL';
  const params: unknown[] = [];
  let paramIndex = 1;

  if (options?.repositoryId) {
    query += ` AND (repository_id = $${paramIndex}`;
    params.push(options.repositoryId);
    paramIndex++;

    if (options.includeGlobal) {
      query += ' OR (owner_id = 0 AND repository_id = 0))';
    } else {
      query += ')';
    }
  } else if (options?.ownerId) {
    query += ` AND (owner_id = $${paramIndex}`;
    params.push(options.ownerId);
    paramIndex++;

    if (options.includeGlobal) {
      query += ' OR (owner_id = 0 AND repository_id = 0))';
    } else {
      query += ')';
    }
  }

  query += ' ORDER BY created_at DESC';

  const result = await db.query(query, params);
  return result.rows;
}

export async function updateRunnerActivity(
  runnerId: number,
  active: boolean = false
): Promise<void> {
  const now = Date.now();
  await db.query(
    `UPDATE action_runners
     SET last_online = $2, last_active = $3, updated_at = NOW()
     WHERE id = $1`,
    [runnerId, now, active ? now : null]
  );
}

export async function deleteRunner(runnerId: number): Promise<void> {
  await db.query(
    'UPDATE action_runners SET deleted_at = NOW() WHERE id = $1',
    [runnerId]
  );
}

function randomUUID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}
```

### 3.4 Secrets & Variables DB Functions (`db/action-secrets.ts`)

```typescript
import { db } from './index';
import { createCipheriv, createDecipheriv, randomBytes, scryptSync } from 'crypto';
import type { ActionSecret, ActionVariable } from '../core/models/actions';

const ENCRYPTION_KEY = process.env.ACTION_SECRET_KEY || 'default-key-change-me'; // Should be 32 bytes
const ALGORITHM = 'aes-256-gcm';

function encrypt(text: string): string {
  const key = scryptSync(ENCRYPTION_KEY, 'salt', 32);
  const iv = randomBytes(16);
  const cipher = createCipheriv(ALGORITHM, key, iv);

  const encrypted = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();

  // Return iv:authTag:encrypted as base64
  return [
    iv.toString('base64'),
    authTag.toString('base64'),
    encrypted.toString('base64'),
  ].join(':');
}

function decrypt(encryptedText: string): string {
  const [ivB64, authTagB64, encryptedB64] = encryptedText.split(':');
  const key = scryptSync(ENCRYPTION_KEY, 'salt', 32);
  const iv = Buffer.from(ivB64, 'base64');
  const authTag = Buffer.from(authTagB64, 'base64');
  const encrypted = Buffer.from(encryptedB64, 'base64');

  const decipher = createDecipheriv(ALGORITHM, key, iv);
  decipher.setAuthTag(authTag);

  return decipher.update(encrypted) + decipher.final('utf8');
}

export async function createSecret(data: {
  name: string;
  data: string;
  ownerId?: number;
  repositoryId?: number;
}): Promise<ActionSecret> {
  const encrypted = encrypt(data.data);

  const result = await db.query(
    `INSERT INTO action_secrets (name, data_encrypted, owner_id, repository_id)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (owner_id, repository_id, name)
     DO UPDATE SET data_encrypted = EXCLUDED.data_encrypted, updated_at = NOW()
     RETURNING *`,
    [data.name.toUpperCase(), encrypted, data.ownerId || null, data.repositoryId || null]
  );

  return result.rows[0];
}

export async function getSecretsForRun(
  repositoryId: number,
  ownerId: number
): Promise<Record<string, string>> {
  // Fetch secrets with precedence: repo > owner > global
  const result = await db.query(
    `SELECT name, data_encrypted FROM action_secrets
     WHERE (repository_id = $1 OR owner_id = $2 OR (owner_id = 0 AND repository_id = 0))
     ORDER BY
       CASE
         WHEN repository_id = $1 THEN 1
         WHEN owner_id = $2 THEN 2
         ELSE 3
       END`,
    [repositoryId, ownerId]
  );

  const secrets: Record<string, string> = {};
  for (const row of result.rows) {
    if (!secrets[row.name]) {
      secrets[row.name] = decrypt(row.data_encrypted);
    }
  }

  return secrets;
}

export async function deleteSecret(id: number): Promise<void> {
  await db.query('DELETE FROM action_secrets WHERE id = $1', [id]);
}

// Variables (similar but unencrypted)
export async function createVariable(data: {
  name: string;
  data: string;
  description?: string;
  ownerId?: number;
  repositoryId?: number;
}): Promise<ActionVariable> {
  const result = await db.query(
    `INSERT INTO action_variables (name, data, description, owner_id, repository_id)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (owner_id, repository_id, name)
     DO UPDATE SET data = EXCLUDED.data, description = EXCLUDED.description, updated_at = NOW()
     RETURNING *`,
    [
      data.name.toUpperCase(),
      data.data,
      data.description,
      data.ownerId || null,
      data.repositoryId || null,
    ]
  );

  return result.rows[0];
}

export async function getVariablesForRun(
  repositoryId: number,
  ownerId: number
): Promise<Record<string, string>> {
  const result = await db.query(
    `SELECT name, data FROM action_variables
     WHERE (repository_id = $1 OR owner_id = $2 OR (owner_id = 0 AND repository_id = 0))
     ORDER BY
       CASE
         WHEN repository_id = $1 THEN 1
         WHEN owner_id = $2 THEN 2
         ELSE 3
       END`,
    [repositoryId, ownerId]
  );

  const variables: Record<string, string> = {};
  for (const row of result.rows) {
    if (!variables[row.name]) {
      variables[row.name] = row.data;
    }
  }

  return variables;
}
```

---

## 4. Services Layer

### 4.1 Workflow Parser Service (`services/workflow-parser.ts`)

```typescript
import yaml from 'yaml';
import type { WorkflowFile } from '../core/models/workflow';

export async function parseWorkflowFile(content: string): Promise<WorkflowFile> {
  try {
    const parsed = yaml.parse(content) as WorkflowFile;

    // Basic validation
    if (!parsed.on) {
      throw new Error('Workflow missing "on" trigger configuration');
    }
    if (!parsed.jobs || Object.keys(parsed.jobs).length === 0) {
      throw new Error('Workflow must define at least one job');
    }

    return parsed;
  } catch (error) {
    throw new Error(`Failed to parse workflow YAML: ${error.message}`);
  }
}

export function matchesEvent(
  workflow: WorkflowFile,
  eventType: string,
  eventData: {
    ref?: string; // 'refs/heads/main'
    branch?: string;
    tag?: string;
    action?: string; // 'opened', 'closed', etc.
    paths?: string[]; // Changed file paths
  }
): boolean {
  const trigger = workflow.on;

  // Simple string trigger
  if (typeof trigger === 'string') {
    return trigger === eventType;
  }

  // Array of triggers
  if (Array.isArray(trigger)) {
    return trigger.includes(eventType);
  }

  // Object with event configurations
  if (typeof trigger === 'object' && trigger[eventType]) {
    const eventConfig = trigger[eventType];

    // If true or no config, match
    if (eventConfig === true || !eventConfig) {
      return true;
    }

    // Check branch filters
    if (eventData.branch) {
      if (eventConfig.branches) {
        if (!matchesPattern(eventData.branch, eventConfig.branches)) {
          return false;
        }
      }
      if (eventConfig['branches-ignore']) {
        if (matchesPattern(eventData.branch, eventConfig['branches-ignore'])) {
          return false;
        }
      }
    }

    // Check tag filters
    if (eventData.tag) {
      if (eventConfig.tags) {
        if (!matchesPattern(eventData.tag, eventConfig.tags)) {
          return false;
        }
      }
      if (eventConfig['tags-ignore']) {
        if (matchesPattern(eventData.tag, eventConfig['tags-ignore'])) {
          return false;
        }
      }
    }

    // Check path filters
    if (eventData.paths && eventConfig.paths) {
      const hasMatch = eventData.paths.some((path) =>
        matchesPattern(path, eventConfig.paths!)
      );
      if (!hasMatch) return false;
    }

    if (eventData.paths && eventConfig['paths-ignore']) {
      const hasMatch = eventData.paths.some((path) =>
        matchesPattern(path, eventConfig['paths-ignore']!)
      );
      if (hasMatch) return false;
    }

    // Check activity types (for issues, pull_request, etc.)
    if (eventData.action && eventConfig.types) {
      if (!eventConfig.types.includes(eventData.action)) {
        return false;
      }
    }

    return true;
  }

  return false;
}

function matchesPattern(value: string, patterns: string[]): boolean {
  return patterns.some((pattern) => {
    // Simple glob matching (*, **)
    const regex = new RegExp(
      '^' + pattern.replace(/\*\*/g, '.*').replace(/\*/g, '[^/]*') + '$'
    );
    return regex.test(value);
  });
}
```

### 4.2 Workflow Runner Service (`services/workflow-runner.ts`)

```typescript
import { getRepositoryFiles } from '../ui/lib/git';
import { parseWorkflowFile, matchesEvent } from './workflow-parser';
import { createActionRun, createActionJob } from '../db/action-jobs';
import { EventBus } from '../core/events';
import type { WorkflowFile } from '../core/models/workflow';

export async function detectAndRunWorkflows(params: {
  repositoryId: number;
  ownerId: number;
  commitSha: string;
  ref: string; // 'refs/heads/main'
  triggerUserId: number;
  eventType: string;
  eventData: {
    branch?: string;
    tag?: string;
    action?: string;
    paths?: string[];
  };
  eventPayload?: Record<string, unknown>;
}): Promise<void> {
  // Find workflow files in .github/workflows or .gitea/workflows
  const workflowFiles = await findWorkflowFiles(
    params.repositoryId,
    params.commitSha
  );

  for (const { path, content } of workflowFiles) {
    try {
      const workflow = await parseWorkflowFile(content);

      // Check if workflow should run for this event
      if (!matchesEvent(workflow, params.eventType, params.eventData)) {
        continue;
      }

      // Create the run
      const run = await createActionRun({
        repositoryId: params.repositoryId,
        ownerId: params.ownerId,
        workflowId: path.split('/').pop()!, // Just filename
        title: workflow.name || path,
        triggerUserId: params.triggerUserId,
        triggerEvent: params.eventType,
        eventPayload: params.eventPayload ? JSON.stringify(params.eventPayload) : undefined,
        ref: params.ref,
        commitSha: params.commitSha,
        concurrencyGroup: typeof workflow.concurrency === 'string'
          ? workflow.concurrency
          : workflow.concurrency?.group,
        concurrencyCancel: typeof workflow.concurrency === 'object'
          ? workflow.concurrency['cancel-in-progress']
          : false,
      });

      // Create jobs for this run
      await createJobsForRun(run.id, params, workflow);

      // Emit event for job scheduling
      EventBus.emit('action_run_created', { runId: run.id });
    } catch (error) {
      console.error(`Failed to process workflow ${path}:`, error);
    }
  }
}

async function findWorkflowFiles(
  repositoryId: number,
  commitSha: string
): Promise<Array<{ path: string; content: string }>> {
  const workflows: Array<{ path: string; content: string }> = [];

  // Check .github/workflows/
  try {
    const githubFiles = await getRepositoryFiles(
      repositoryId,
      '.github/workflows',
      commitSha
    );
    for (const file of githubFiles.filter((f) => f.name.endsWith('.yml') || f.name.endsWith('.yaml'))) {
      workflows.push({
        path: `.github/workflows/${file.name}`,
        content: file.content,
      });
    }
  } catch {
    // Directory doesn't exist
  }

  // Check .gitea/workflows/
  try {
    const giteaFiles = await getRepositoryFiles(
      repositoryId,
      '.gitea/workflows',
      commitSha
    );
    for (const file of giteaFiles.filter((f) => f.name.endsWith('.yml') || f.name.endsWith('.yaml'))) {
      workflows.push({
        path: `.gitea/workflows/${file.name}`,
        content: file.content,
      });
    }
  } catch {
    // Directory doesn't exist
  }

  return workflows;
}

async function createJobsForRun(
  runId: number,
  runParams: {
    repositoryId: number;
    ownerId: number;
    commitSha: string;
  },
  workflow: WorkflowFile
): Promise<void> {
  const jobEntries = Object.entries(workflow.jobs);

  for (const [jobId, jobDef] of jobEntries) {
    const needs = Array.isArray(jobDef.needs)
      ? jobDef.needs
      : jobDef.needs
      ? [jobDef.needs]
      : [];

    const runsOn = Array.isArray(jobDef['runs-on'])
      ? jobDef['runs-on']
      : [jobDef['runs-on']];

    await createActionJob({
      runId,
      repositoryId: runParams.repositoryId,
      ownerId: runParams.ownerId,
      jobId,
      name: jobDef.name || jobId,
      needs,
      runsOn,
      commitSha: runParams.commitSha,
      concurrencyGroup: typeof jobDef.concurrency === 'string'
        ? jobDef.concurrency
        : jobDef.concurrency?.group,
      concurrencyCancel: typeof jobDef.concurrency === 'object'
        ? jobDef.concurrency['cancel-in-progress']
        : false,
    });
  }
}
```

### 4.3 Job Scheduler Service (`services/job-scheduler.ts`)

```typescript
import { getJobsByRunId, updateJobStatus, aggregateJobStatus } from '../db/action-jobs';
import { updateActionRunStatus } from '../db/action-runs';
import { EventBus } from '../core/events';

// Listen for run creation and schedule jobs
EventBus.on('action_run_created', async ({ runId }: { runId: number }) => {
  await scheduleJobsForRun(runId);
});

async function scheduleJobsForRun(runId: number): Promise<void> {
  const jobs = await getJobsByRunId(runId);

  // Find jobs with no dependencies or all dependencies satisfied
  const readyJobs = jobs.filter((job) => {
    if (job.needs.length === 0) return true;

    return job.needs.every((needJobId) => {
      const depJob = jobs.find((j) => j.jobId === needJobId);
      return depJob?.status === 'success';
    });
  });

  // Mark ready jobs as waiting (they can be picked up by runners)
  for (const job of readyJobs) {
    if (job.status === 'waiting') {
      // Already waiting, emit event for runner assignment
      EventBus.emit('action_job_ready', { jobId: job.id });
    }
  }

  // Update run status based on job statuses
  const runStatus = aggregateJobStatus(jobs);
  await updateActionRunStatus(runId, runStatus, {
    started: runStatus === 'running' ? Date.now() : undefined,
    stopped: ['success', 'failure', 'cancelled', 'skipped'].includes(runStatus)
      ? Date.now()
      : undefined,
  });
}

// When a job completes, check if dependent jobs can run
EventBus.on('action_job_completed', async ({ jobId }: { jobId: number }) => {
  // Get the job to find its run
  const jobs = await getJobsByRunId(jobId); // Need to get run ID first
  // Then reschedule
  // (simplified - you'd get the run ID from the job first)
});
```

---

## 5. API Routes

### 5.1 Actions Routes (`server/routes/actions.ts`)

```typescript
import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { listActionRuns, getActionRunByIndex, cancelActionRun } from '../../db/action-runs';
import { getJobsByRunId } from '../../db/action-jobs';
import { listRunners, createActionRunner, deleteRunner } from '../../db/action-runners';
import { createSecret, createVariable } from '../../db/action-secrets';

export const actionsRouter = new Hono();

// List runs for a repository
actionsRouter.get('/repos/:repoId/runs', async (c) => {
  const repoId = parseInt(c.req.param('repoId'));
  const { workflow, status, limit = '50', page = '1' } = c.req.query();

  const runs = await listActionRuns(repoId, {
    workflowId: workflow,
    status: status as any,
    limit: parseInt(limit),
    offset: (parseInt(page) - 1) * parseInt(limit),
  });

  return c.json({ runs });
});

// Get specific run
actionsRouter.get('/repos/:repoId/runs/:runIndex', async (c) => {
  const repoId = parseInt(c.req.param('repoId'));
  const runIndex = parseInt(c.req.param('runIndex'));

  const run = await getActionRunByIndex(repoId, runIndex);
  if (!run) {
    return c.json({ error: 'Run not found' }, 404);
  }

  const jobs = await getJobsByRunId(run.id);

  return c.json({ run, jobs });
});

// Cancel a run
actionsRouter.post('/repos/:repoId/runs/:runIndex/cancel', async (c) => {
  const repoId = parseInt(c.req.param('repoId'));
  const runIndex = parseInt(c.req.param('runIndex'));

  const run = await getActionRunByIndex(repoId, runIndex);
  if (!run) {
    return c.json({ error: 'Run not found' }, 404);
  }

  await cancelActionRun(run.id);

  return c.json({ success: true });
});

// List runners
actionsRouter.get('/repos/:repoId/runners', async (c) => {
  const repoId = parseInt(c.req.param('repoId'));

  const runners = await listRunners({
    repositoryId: repoId,
    includeGlobal: true,
  });

  return c.json({ runners });
});

// Create runner registration token
actionsRouter.post('/repos/:repoId/runners/registration-token', async (c) => {
  const repoId = parseInt(c.req.param('repoId'));

  // In a real implementation, create a time-limited registration token
  // For now, create a runner and return its token
  const { runner, token } = await createActionRunner({
    name: 'New Runner',
    repositoryId: repoId,
    agentLabels: ['self-hosted'],
  });

  return c.json({ token, runnerId: runner.id });
});

// Delete runner
actionsRouter.delete('/repos/:repoId/runners/:runnerId', async (c) => {
  const runnerId = parseInt(c.req.param('runnerId'));

  await deleteRunner(runnerId);

  return c.json({ success: true });
});

// Secrets
actionsRouter.post(
  '/repos/:repoId/secrets',
  zValidator(
    'json',
    z.object({
      name: z.string(),
      value: z.string(),
    })
  ),
  async (c) => {
    const repoId = parseInt(c.req.param('repoId'));
    const { name, value } = c.req.valid('json');

    await createSecret({
      name,
      data: value,
      repositoryId: repoId,
    });

    return c.json({ success: true });
  }
);

// Variables
actionsRouter.post(
  '/repos/:repoId/variables',
  zValidator(
    'json',
    z.object({
      name: z.string(),
      value: z.string(),
      description: z.string().optional(),
    })
  ),
  async (c) => {
    const repoId = parseInt(c.req.param('repoId'));
    const { name, value, description } = c.req.valid('json');

    await createVariable({
      name,
      data: value,
      description,
      repositoryId: repoId,
    });

    return c.json({ success: true });
  }
);
```

---

## 6. UI Components

### 6.1 Workflow Run List Page (`ui/pages/[user]/[repo]/actions/index.astro`)

```astro
---
import Layout from '../../../../layouts/Layout.astro';
import { getRepository } from '../../../../lib/db';
import { listActionRuns } from '../../../../../db/action-runs';

const { user, repo } = Astro.params;
const repository = await getRepository(user!, repo!);

if (!repository) {
  return Astro.redirect('/404');
}

const runs = await listActionRuns(repository.id, { limit: 50 });

const formatDuration = (started?: number, stopped?: number) => {
  if (!started) return '-';
  const end = stopped || Date.now();
  const ms = end - started;
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  if (minutes === 0) return `${seconds}s`;
  return `${minutes}m ${seconds % 60}s`;
};

const getStatusEmoji = (status: string) => {
  switch (status) {
    case 'success': return '✓';
    case 'failure': return '✗';
    case 'cancelled': return '⊘';
    case 'running': return '⟳';
    default: return '○';
  }
};
---

<Layout title={`Actions - ${repository.name}`}>
  <div class="repo-header">
    <h1>{repository.name}</h1>
    <nav>
      <a href={`/${user}/${repo}`}>Code</a>
      <a href={`/${user}/${repo}/issues`}>Issues</a>
      <a href={`/${user}/${repo}/actions`} class="active">Actions</a>
    </nav>
  </div>

  <div class="actions-container">
    <div class="actions-header">
      <h2>Workflow Runs</h2>
      <a href={`/${user}/${repo}/actions/workflows`} class="btn">Manage Workflows</a>
    </div>

    <div class="runs-list">
      {runs.length === 0 ? (
        <div class="empty-state">
          <p>No workflow runs yet</p>
          <p>Add a workflow file in <code>.github/workflows/</code> to get started</p>
        </div>
      ) : (
        <table>
          <thead>
            <tr>
              <th>Status</th>
              <th>Workflow</th>
              <th>Event</th>
              <th>Commit</th>
              <th>Branch</th>
              <th>Duration</th>
              <th>Run #</th>
            </tr>
          </thead>
          <tbody>
            {runs.map((run) => (
              <tr>
                <td>
                  <span class={`status status-${run.status}`}>
                    {getStatusEmoji(run.status)}
                  </span>
                </td>
                <td>
                  <a href={`/${user}/${repo}/actions/runs/${run.runIndex}`}>
                    {run.title}
                  </a>
                </td>
                <td>{run.triggerEvent}</td>
                <td>
                  <code class="commit-sha">
                    {run.commitSha.substring(0, 7)}
                  </code>
                </td>
                <td>
                  {run.ref.replace('refs/heads/', '').replace('refs/tags/', '')}
                </td>
                <td>{formatDuration(run.started, run.stopped)}</td>
                <td>#{run.runIndex}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  </div>

  <style>
    .actions-container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 2rem;
    }

    .actions-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 2rem;
    }

    .runs-list table {
      width: 100%;
      border-collapse: collapse;
    }

    .runs-list th,
    .runs-list td {
      text-align: left;
      padding: 0.75rem;
      border-bottom: 1px solid #333;
    }

    .status {
      font-size: 1.2rem;
    }

    .status-success { color: #0f0; }
    .status-failure { color: #f00; }
    .status-running { color: #ff0; animation: spin 1s linear infinite; }
    .status-cancelled { color: #666; }

    @keyframes spin {
      to { transform: rotate(360deg); }
    }

    .commit-sha {
      font-family: monospace;
      background: #222;
      padding: 2px 6px;
      border-radius: 3px;
    }

    .empty-state {
      text-align: center;
      padding: 4rem;
      color: #666;
    }
  </style>
</Layout>
```

### 6.2 Workflow Run Detail Page (`ui/pages/[user]/[repo]/actions/runs/[runIndex].astro`)

```astro
---
import Layout from '../../../../../layouts/Layout.astro';
import { getRepository } from '../../../../../lib/db';
import { getActionRunByIndex } from '../../../../../../db/action-runs';
import { getJobsByRunId } from '../../../../../../db/action-jobs';

const { user, repo, runIndex } = Astro.params;
const repository = await getRepository(user!, repo!);

if (!repository) {
  return Astro.redirect('/404');
}

const run = await getActionRunByIndex(repository.id, parseInt(runIndex!));
if (!run) {
  return Astro.redirect(`/${user}/${repo}/actions`);
}

const jobs = await getJobsByRunId(run.id);

const formatDuration = (started?: number, stopped?: number) => {
  if (!started) return '-';
  const end = stopped || Date.now();
  const ms = end - started;
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  if (minutes === 0) return `${seconds}s`;
  return `${minutes}m ${seconds % 60}s`;
};
---

<Layout title={`${run.title} - Run #${run.runIndex}`}>
  <div class="run-detail">
    <div class="run-header">
      <h1>
        <span class={`status-badge status-${run.status}`}>{run.status}</span>
        {run.title}
      </h1>
      <div class="run-meta">
        <p>Run #{run.runIndex}</p>
        <p>Triggered by {run.triggerEvent}</p>
        <p>Commit: <code>{run.commitSha.substring(0, 7)}</code></p>
        <p>Duration: {formatDuration(run.started, run.stopped)}</p>
      </div>

      <div class="run-actions">
        {run.status === 'running' && (
          <button class="btn btn-danger" data-action="cancel">Cancel</button>
        )}
        {['success', 'failure', 'cancelled'].includes(run.status) && (
          <button class="btn" data-action="rerun">Re-run</button>
        )}
      </div>
    </div>

    <div class="jobs-container">
      <h2>Jobs</h2>
      <div class="jobs-list">
        {jobs.map((job) => (
          <div class={`job-card job-${job.status}`}>
            <div class="job-header">
              <h3>{job.name}</h3>
              <span class="job-status">{job.status}</span>
            </div>
            <div class="job-meta">
              <p>Duration: {formatDuration(job.started, job.stopped)}</p>
              {job.runsOn && <p>Runs on: {job.runsOn.join(', ')}</p>}
            </div>
            <a href={`/${user}/${repo}/actions/runs/${runIndex}/jobs/${job.id}`} class="view-job">
              View job details →
            </a>
          </div>
        ))}
      </div>
    </div>
  </div>

  <script>
    document.querySelector('[data-action="cancel"]')?.addEventListener('click', async () => {
      const response = await fetch(window.location.pathname + '/cancel', {
        method: 'POST',
      });
      if (response.ok) {
        window.location.reload();
      }
    });

    document.querySelector('[data-action="rerun"]')?.addEventListener('click', async () => {
      const response = await fetch(window.location.pathname + '/rerun', {
        method: 'POST',
      });
      if (response.ok) {
        window.location.reload();
      }
    });
  </script>

  <style>
    .run-detail {
      max-width: 1200px;
      margin: 0 auto;
      padding: 2rem;
    }

    .run-header {
      margin-bottom: 3rem;
    }

    .status-badge {
      display: inline-block;
      padding: 0.25rem 0.75rem;
      border-radius: 12px;
      font-size: 0.875rem;
      font-weight: bold;
      text-transform: uppercase;
    }

    .status-success { background: #0f0; color: #000; }
    .status-failure { background: #f00; color: #fff; }
    .status-running { background: #ff0; color: #000; }
    .status-cancelled { background: #666; color: #fff; }

    .run-meta {
      margin-top: 1rem;
      display: flex;
      gap: 2rem;
      color: #999;
    }

    .jobs-list {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
      gap: 1rem;
    }

    .job-card {
      border: 2px solid #333;
      padding: 1.5rem;
      border-radius: 8px;
    }

    .job-success { border-color: #0f0; }
    .job-failure { border-color: #f00; }
    .job-running { border-color: #ff0; }

    .job-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 1rem;
    }

    .view-job {
      display: inline-block;
      margin-top: 1rem;
      color: #0af;
      text-decoration: none;
    }

    .view-job:hover {
      text-decoration: underline;
    }
  </style>
</Layout>
```

### 6.3 Runner Management Page (`ui/pages/[user]/[repo]/settings/actions/runners.astro`)

```astro
---
import Layout from '../../../../../layouts/Layout.astro';
import { getRepository } from '../../../../../lib/db';
import { listRunners } from '../../../../../../db/action-runners';

const { user, repo } = Astro.params;
const repository = await getRepository(user!, repo!);

if (!repository) {
  return Astro.redirect('/404');
}

const runners = await listRunners({
  repositoryId: repository.id,
  includeGlobal: true,
});

const getRunnerStatus = (runner: any) => {
  const now = Date.now();
  if (!runner.lastOnline) return 'offline';
  if (now - runner.lastOnline < 60000) { // 1 minute
    if (runner.lastActive && now - runner.lastActive < 10000) { // 10 seconds
      return 'active';
    }
    return 'idle';
  }
  return 'offline';
};
---

<Layout title={`Runners - ${repository.name}`}>
  <div class="runners-page">
    <div class="page-header">
      <h1>Runners</h1>
      <button class="btn btn-primary" id="add-runner">Add runner</button>
    </div>

    <div class="runners-list">
      {runners.length === 0 ? (
        <div class="empty-state">
          <p>No runners configured</p>
          <p>Add a self-hosted runner to run workflows on your own infrastructure</p>
        </div>
      ) : (
        <table>
          <thead>
            <tr>
              <th>Status</th>
              <th>Name</th>
              <th>Labels</th>
              <th>Scope</th>
              <th>Last Seen</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {runners.map((runner) => {
              const status = getRunnerStatus(runner);
              const isRepoRunner = runner.repositoryId === repository.id;

              return (
                <tr>
                  <td>
                    <span class={`runner-status runner-${status}`}>
                      {status}
                    </span>
                  </td>
                  <td>{runner.name}</td>
                  <td>
                    {runner.agentLabels.map((label: string) => (
                      <span class="label-badge">{label}</span>
                    ))}
                  </td>
                  <td>
                    {isRepoRunner ? 'Repository' : 'Inherited'}
                  </td>
                  <td>
                    {runner.lastOnline
                      ? new Date(runner.lastOnline).toLocaleString()
                      : 'Never'}
                  </td>
                  <td>
                    {isRepoRunner && (
                      <button
                        class="btn-link btn-danger"
                        data-runner-id={runner.id}
                        data-action="delete"
                      >
                        Delete
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </div>

    <dialog id="add-runner-dialog">
      <div class="dialog-content">
        <h2>Add Self-Hosted Runner</h2>
        <p>Follow these steps to add a self-hosted runner:</p>
        <ol>
          <li>
            Download the runner package:
            <pre><code>curl -o runner.tar.gz https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz</code></pre>
          </li>
          <li>
            Generate a registration token:
            <button id="generate-token" class="btn btn-primary">Generate Token</button>
            <pre id="token-display" style="display: none;"></pre>
          </li>
          <li>
            Configure the runner:
            <pre><code>./config.sh --url {repository.htmlUrl} --token YOUR_TOKEN</code></pre>
          </li>
          <li>
            Run the runner:
            <pre><code>./run.sh</code></pre>
          </li>
        </ol>
        <button class="btn" id="close-dialog">Close</button>
      </div>
    </dialog>
  </div>

  <script>
    document.getElementById('add-runner')?.addEventListener('click', () => {
      const dialog = document.getElementById('add-runner-dialog') as HTMLDialogElement;
      dialog.showModal();
    });

    document.getElementById('close-dialog')?.addEventListener('click', () => {
      const dialog = document.getElementById('add-runner-dialog') as HTMLDialogElement;
      dialog.close();
    });

    document.getElementById('generate-token')?.addEventListener('click', async () => {
      const response = await fetch(`/api/repos/${window.location.pathname.split('/')[1]}/${window.location.pathname.split('/')[2]}/runners/registration-token`, {
        method: 'POST',
      });
      const data = await response.json();
      const display = document.getElementById('token-display');
      if (display) {
        display.textContent = data.token;
        display.style.display = 'block';
      }
    });

    document.querySelectorAll('[data-action="delete"]').forEach((btn) => {
      btn.addEventListener('click', async (e) => {
        const runnerId = (e.target as HTMLElement).dataset.runnerId;
        if (confirm('Are you sure you want to delete this runner?')) {
          await fetch(`/api/repos/${window.location.pathname.split('/')[1]}/${window.location.pathname.split('/')[2]}/runners/${runnerId}`, {
            method: 'DELETE',
          });
          window.location.reload();
        }
      });
    });
  </script>

  <style>
    .runners-page {
      max-width: 1200px;
      margin: 0 auto;
      padding: 2rem;
    }

    .page-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 2rem;
    }

    .runner-status {
      display: inline-block;
      width: 8px;
      height: 8px;
      border-radius: 50%;
      margin-right: 0.5rem;
    }

    .runner-active { background: #0f0; }
    .runner-idle { background: #ff0; }
    .runner-offline { background: #666; }

    .label-badge {
      display: inline-block;
      background: #333;
      padding: 2px 8px;
      border-radius: 12px;
      font-size: 0.75rem;
      margin-right: 0.25rem;
    }

    dialog {
      max-width: 800px;
      background: #1a1a1a;
      border: 2px solid #333;
      border-radius: 8px;
      padding: 2rem;
    }

    dialog::backdrop {
      background: rgba(0, 0, 0, 0.8);
    }

    .dialog-content pre {
      background: #0a0a0a;
      padding: 1rem;
      border-radius: 4px;
      overflow-x: auto;
    }
  </style>
</Layout>
```

---

## 7. Event Integration

### 7.1 Hook Actions into Git Events (`core/events.ts` - additions)

```typescript
// Add to existing EventBus

import { detectAndRunWorkflows } from '../services/workflow-runner';

// Trigger workflows on push
EventBus.on('git:push', async (data: {
  repositoryId: number;
  ownerId: number;
  userId: number;
  ref: string; // 'refs/heads/main'
  before: string; // Previous commit SHA
  after: string; // New commit SHA
  commits: Array<{ sha: string; message: string; author: string }>;
}) => {
  const branch = data.ref.startsWith('refs/heads/')
    ? data.ref.replace('refs/heads/', '')
    : undefined;

  const tag = data.ref.startsWith('refs/tags/')
    ? data.ref.replace('refs/tags/', '')
    : undefined;

  await detectAndRunWorkflows({
    repositoryId: data.repositoryId,
    ownerId: data.ownerId,
    commitSha: data.after,
    ref: data.ref,
    triggerUserId: data.userId,
    eventType: 'push',
    eventData: {
      branch,
      tag,
      // Would need to get changed paths from commits
    },
    eventPayload: {
      ref: data.ref,
      before: data.before,
      after: data.after,
      commits: data.commits,
    },
  });
});

// Trigger workflows on pull request
EventBus.on('pull_request:opened', async (data: {
  repositoryId: number;
  ownerId: number;
  userId: number;
  pullRequestId: number;
  headSha: string;
  baseBranch: string;
}) => {
  await detectAndRunWorkflows({
    repositoryId: data.repositoryId,
    ownerId: data.ownerId,
    commitSha: data.headSha,
    ref: `refs/pull/${data.pullRequestId}/head`,
    triggerUserId: data.userId,
    eventType: 'pull_request',
    eventData: {
      branch: data.baseBranch,
      action: 'opened',
    },
    eventPayload: {
      action: 'opened',
      number: data.pullRequestId,
    },
  });
});
```

---

## 8. Implementation Checklist

### Phase 1: Foundation (Database + Models)
- [ ] Create database migration with all action tables
- [ ] Define TypeScript models and Zod schemas
- [ ] Implement database layer functions for runs, jobs, tasks
- [ ] Implement database layer functions for runners
- [ ] Implement database layer functions for secrets/variables
- [ ] Implement database layer functions for artifacts

### Phase 2: Core Services
- [ ] Implement YAML workflow parser
- [ ] Implement event matching logic (branches, paths, etc.)
- [ ] Implement workflow detection service
- [ ] Implement job creation from workflow definition
- [ ] Implement job scheduler (dependency resolution)
- [ ] Implement basic job executor (stub for MVP)

### Phase 3: API Layer
- [ ] Implement API routes for listing/viewing runs
- [ ] Implement API routes for canceling/rerunning runs
- [ ] Implement API routes for runner management
- [ ] Implement API routes for secrets management
- [ ] Implement API routes for variables management
- [ ] Implement API routes for artifact upload/download

### Phase 4: UI Components
- [ ] Create workflow runs list page
- [ ] Create workflow run detail page
- [ ] Create job detail page with step visualization
- [ ] Create runner management page
- [ ] Create secrets management page
- [ ] Create variables management page
- [ ] Add "Actions" tab to repository navigation

### Phase 5: Event Integration
- [ ] Hook workflow detection into push events
- [ ] Hook workflow detection into pull request events
- [ ] Hook workflow detection into issue events
- [ ] Hook workflow detection into release events

### Phase 6: Runner Protocol (Advanced)
- [ ] Implement runner registration protocol
- [ ] Implement task assignment to runners
- [ ] Implement log streaming from runners
- [ ] Implement step execution reporting
- [ ] Implement artifact upload protocol
- [ ] Implement task completion/failure handling

### Phase 7: Enhancements (Post-MVP)
- [ ] Matrix build support
- [ ] Workflow caching
- [ ] Workflow reusable workflows (composite actions)
- [ ] Workflow environments
- [ ] Manual workflow dispatch
- [ ] Scheduled workflows (cron)
- [ ] Workflow artifacts retention policies
- [ ] Workflow logs retention/expiration

---

## 9. Testing Strategy

### Unit Tests
```typescript
// services/workflow-parser.test.ts
import { test, expect } from 'bun:test';
import { parseWorkflowFile, matchesEvent } from './workflow-parser';

test('parseWorkflowFile - simple workflow', async () => {
  const yaml = `
name: CI
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: npm test
  `;

  const workflow = await parseWorkflowFile(yaml);
  expect(workflow.name).toBe('CI');
  expect(workflow.on).toBe('push');
  expect(Object.keys(workflow.jobs)).toContain('build');
});

test('matchesEvent - branch filter', () => {
  const workflow = {
    name: 'Test',
    on: {
      push: {
        branches: ['main', 'develop'],
      },
    },
    jobs: {},
  };

  expect(matchesEvent(workflow, 'push', { branch: 'main' })).toBe(true);
  expect(matchesEvent(workflow, 'push', { branch: 'feature' })).toBe(false);
});
```

### Integration Tests
```typescript
// db/action-runs.test.ts
import { test, expect, beforeAll, afterAll } from 'bun:test';
import { createActionRun, getActionRunByIndex } from './action-runs';
import { db } from './index';

beforeAll(async () => {
  // Setup test database
  await db.query('DELETE FROM action_runs');
});

afterAll(async () => {
  // Cleanup
  await db.query('DELETE FROM action_runs');
});

test('createActionRun - creates with sequential index', async () => {
  const run1 = await createActionRun({
    repositoryId: 1,
    ownerId: 1,
    workflowId: 'ci.yml',
    title: 'CI',
    triggerEvent: 'push',
    ref: 'refs/heads/main',
    commitSha: 'abc123',
  });

  expect(run1.runIndex).toBe(1);

  const run2 = await createActionRun({
    repositoryId: 1,
    ownerId: 1,
    workflowId: 'ci.yml',
    title: 'CI',
    triggerEvent: 'push',
    ref: 'refs/heads/main',
    commitSha: 'def456',
  });

  expect(run2.runIndex).toBe(2);
});
```

---

## 10. Security Considerations

1. **Secret Encryption**: Use AES-256-GCM for encrypting secrets at rest
2. **Runner Authentication**: Use time-limited tokens with HMAC verification
3. **Fork PR Protection**: Require approval for workflows from fork PRs
4. **Artifact Access Control**: Verify user permissions before serving artifacts
5. **Log Sanitization**: Mask secrets in workflow logs automatically
6. **Rate Limiting**: Limit workflow runs per repository/user
7. **Resource Limits**: Set timeouts and memory limits for jobs

---

## 11. Gitea Reference Code Mapping

### Key Gitea Files Referenced:
- `models/actions/run.go` → `db/action-runs.ts`
- `models/actions/run_job.go` → `db/action-jobs.ts`
- `models/actions/task.go` → `db/action-tasks.ts`
- `models/actions/runner.go` → `db/action-runners.ts`
- `models/actions/artifact.go` → `db/action-artifacts.ts`
- `models/actions/variable.go` → `db/action-secrets.ts`
- `modules/actions/workflows.go` → `services/workflow-parser.ts`
- `routers/web/repo/actions/view.go` → `ui/pages/[user]/[repo]/actions/`

### Translation Notes:
- Gitea uses XORM ORM → Plue uses raw SQL with Zod validation
- Gitea uses Go templates → Plue uses Astro components
- Gitea's `timeutil.TimeStamp` → JavaScript `number` (milliseconds)
- Gitea's Status enums → TypeScript string literal types

---

## 12. Performance Optimizations

1. **Database Indexing**: All foreign keys and frequently queried columns indexed
2. **Job Scheduling**: Use database transactions for atomic job assignment
3. **Log Streaming**: Stream logs directly to object storage (future)
4. **Artifact Storage**: Use object storage (S3-compatible) for artifacts
5. **Caching**: Cache workflow YAML parsing results per commit SHA
6. **Pagination**: All list endpoints support pagination

---

## Notes for Implementation

- Start with MVP: Basic workflow parsing, job creation, and UI visualization
- Runner execution can be stubbed initially (just mark jobs as success)
- Focus on the database schema and UI first for rapid iteration
- Use existing Plue patterns (EventBus, db layer, Astro pages)
- Test with simple workflows (single job, basic steps) before complex scenarios
- Consider using `nektos/act` library for YAML parsing (same as Gitea)
