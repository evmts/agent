/**
 * Database operations for workflow system.
 */

import sql from '../../db/client';
import { WorkflowStatus, parseStatus } from './status';
import type {
  WorkflowDefinition,
  CreateWorkflowDefinitionOptions,
  WorkflowRunner,
  RegisterRunnerOptions,
  RunnerWithToken,
  WorkflowRun,
  CreateWorkflowRunOptions,
  WorkflowJob,
  CreateWorkflowJobOptions,
  WorkflowTask,
  CreateWorkflowTaskOptions,
  WorkflowStep,
  CreateWorkflowStepOptions,
  UpdateWorkflowStepOptions,
  WorkflowLog,
  AppendLogOptions,
  TaskWithContext,
} from './types';
import { createHash, randomBytes } from 'crypto';

// =============================================================================
// Helper Functions
// =============================================================================

function generateToken(): { token: string; hash: string; lastEight: string } {
  const token = randomBytes(32).toString('hex');
  const hash = createHash('sha256').update(token).digest('hex');
  const lastEight = token.slice(-8);
  return { token, hash, lastEight };
}

function rowToDate(value: unknown): Date | undefined {
  if (!value) return undefined;
  if (value instanceof Date) return value;
  return new Date(value as string);
}

// =============================================================================
// Workflow Definition Operations
// =============================================================================

export async function getWorkflowDefinition(
  id: number
): Promise<WorkflowDefinition | null> {
  const rows = await sql`
    SELECT * FROM workflow_definitions WHERE id = ${id}
  `;
  const row = rows[0];
  if (!row) return null;
  return rowToWorkflowDefinition(row);
}

export async function getWorkflowDefinitionByName(
  repositoryId: number,
  name: string
): Promise<WorkflowDefinition | null> {
  const rows = await sql`
    SELECT * FROM workflow_definitions
    WHERE repository_id = ${repositoryId} AND name = ${name}
  `;
  const row = rows[0];
  if (!row) return null;
  return rowToWorkflowDefinition(row);
}

export async function listWorkflowDefinitions(
  repositoryId: number
): Promise<WorkflowDefinition[]> {
  const rows = await sql`
    SELECT * FROM workflow_definitions
    WHERE repository_id = ${repositoryId}
    ORDER BY name
  `;
  return rows.map(rowToWorkflowDefinition);
}

export async function createWorkflowDefinition(
  options: CreateWorkflowDefinitionOptions
): Promise<WorkflowDefinition> {
  const rows = await sql`
    INSERT INTO workflow_definitions (
      repository_id, name, file_path, file_sha, events, is_agent_workflow
    ) VALUES (
      ${options.repositoryId},
      ${options.name},
      ${options.filePath},
      ${options.fileSha ?? null},
      ${JSON.stringify(options.events ?? [])},
      ${options.isAgentWorkflow ?? false}
    )
    RETURNING *
  `;
  return rowToWorkflowDefinition(rows[0]);
}

export async function updateWorkflowDefinition(
  id: number,
  updates: Partial<CreateWorkflowDefinitionOptions>
): Promise<WorkflowDefinition | null> {
  const rows = await sql`
    UPDATE workflow_definitions SET
      file_sha = COALESCE(${updates.fileSha ?? null}, file_sha),
      events = COALESCE(${updates.events ? JSON.stringify(updates.events) : null}, events),
      is_agent_workflow = COALESCE(${updates.isAgentWorkflow ?? null}, is_agent_workflow),
      updated_at = NOW()
    WHERE id = ${id}
    RETURNING *
  `;
  const row = rows[0];
  if (!row) return null;
  return rowToWorkflowDefinition(row);
}

function rowToWorkflowDefinition(row: Record<string, unknown>): WorkflowDefinition {
  return {
    id: row.id as number,
    repositoryId: row.repository_id as number,
    name: row.name as string,
    filePath: row.file_path as string,
    fileSha: row.file_sha as string | undefined,
    events: (row.events as string[]) ?? [],
    isAgentWorkflow: row.is_agent_workflow as boolean,
    createdAt: rowToDate(row.created_at)!,
    updatedAt: rowToDate(row.updated_at)!,
  };
}

// =============================================================================
// Workflow Runner Operations
// =============================================================================

export async function getRunner(id: number): Promise<WorkflowRunner | null> {
  const rows = await sql`
    SELECT * FROM workflow_runners WHERE id = ${id}
  `;
  const row = rows[0];
  if (!row) return null;
  return rowToRunner(row);
}

export async function getRunnerByToken(
  tokenHash: string
): Promise<WorkflowRunner | null> {
  const rows = await sql`
    SELECT * FROM workflow_runners WHERE token_hash = ${tokenHash}
  `;
  const row = rows[0];
  if (!row) return null;
  return rowToRunner(row);
}

export async function listRunners(
  repositoryId?: number
): Promise<WorkflowRunner[]> {
  if (repositoryId) {
    const rows = await sql`
      SELECT * FROM workflow_runners
      WHERE repository_id = ${repositoryId} OR repository_id IS NULL
      ORDER BY name
    `;
    return rows.map(rowToRunner);
  }
  const rows = await sql`
    SELECT * FROM workflow_runners ORDER BY name
  `;
  return rows.map(rowToRunner);
}

export async function registerRunner(
  options: RegisterRunnerOptions
): Promise<RunnerWithToken> {
  const { token, hash, lastEight } = generateToken();

  const rows = await sql`
    INSERT INTO workflow_runners (
      name, owner_id, repository_id, version, labels, status, token_hash, token_last_eight
    ) VALUES (
      ${options.name},
      ${options.ownerId ?? null},
      ${options.repositoryId ?? null},
      ${options.version ?? null},
      ${JSON.stringify(options.labels ?? [])},
      'online',
      ${hash},
      ${lastEight}
    )
    RETURNING *
  `;
  const runner = rowToRunner(rows[0]);
  return { ...runner, token };
}

export async function updateRunnerStatus(
  id: number,
  status: 'online' | 'offline' | 'busy'
): Promise<void> {
  await sql`
    UPDATE workflow_runners SET
      status = ${status},
      last_online_at = CASE WHEN ${status} = 'online' THEN NOW() ELSE last_online_at END,
      last_active_at = NOW(),
      updated_at = NOW()
    WHERE id = ${id}
  `;
}

export async function updateRunnerHeartbeat(tokenHash: string): Promise<void> {
  await sql`
    UPDATE workflow_runners SET
      last_online_at = NOW(),
      last_active_at = NOW(),
      status = 'online',
      updated_at = NOW()
    WHERE token_hash = ${tokenHash}
  `;
}

function rowToRunner(row: Record<string, unknown>): WorkflowRunner {
  return {
    id: row.id as number,
    name: row.name as string,
    ownerId: row.owner_id as number | undefined,
    repositoryId: row.repository_id as number | undefined,
    version: row.version as string | undefined,
    labels: (row.labels as string[]) ?? [],
    status: row.status as 'online' | 'offline' | 'busy',
    lastOnlineAt: rowToDate(row.last_online_at),
    lastActiveAt: rowToDate(row.last_active_at),
    tokenHash: row.token_hash as string | undefined,
    tokenLastEight: row.token_last_eight as string | undefined,
    createdAt: rowToDate(row.created_at)!,
    updatedAt: rowToDate(row.updated_at)!,
  };
}

// =============================================================================
// Workflow Run Operations
// =============================================================================

export async function getRun(id: number): Promise<WorkflowRun | null> {
  const rows = await sql`
    SELECT * FROM workflow_runs WHERE id = ${id}
  `;
  const row = rows[0];
  if (!row) return null;
  return rowToRun(row);
}

export async function getRunBySession(
  sessionId: string
): Promise<WorkflowRun | null> {
  const rows = await sql`
    SELECT * FROM workflow_runs WHERE session_id = ${sessionId}
  `;
  const row = rows[0];
  if (!row) return null;
  return rowToRun(row);
}

export async function listRuns(
  repositoryId: number,
  options?: { status?: WorkflowStatus; limit?: number; offset?: number }
): Promise<WorkflowRun[]> {
  const limit = options?.limit ?? 20;
  const offset = options?.offset ?? 0;

  if (options?.status !== undefined) {
    const rows = await sql`
      SELECT * FROM workflow_runs
      WHERE repository_id = ${repositoryId} AND status = ${options.status}
      ORDER BY created_at DESC
      LIMIT ${limit} OFFSET ${offset}
    `;
    return rows.map(rowToRun);
  }

  const rows = await sql`
    SELECT * FROM workflow_runs
    WHERE repository_id = ${repositoryId}
    ORDER BY created_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;
  return rows.map(rowToRun);
}

export async function createRun(
  options: CreateWorkflowRunOptions
): Promise<WorkflowRun> {
  const rows = await sql`
    INSERT INTO workflow_runs (
      repository_id, workflow_definition_id, run_number, title,
      trigger_event, trigger_user_id, event_payload,
      ref, commit_sha, status,
      concurrency_group, concurrency_cancel, session_id
    ) VALUES (
      ${options.repositoryId},
      ${options.workflowDefinitionId ?? null},
      (SELECT COALESCE(MAX(run_number), 0) + 1 FROM workflow_runs WHERE repository_id = ${options.repositoryId}),
      ${options.title},
      ${options.triggerEvent},
      ${options.triggerUserId ?? null},
      ${options.eventPayload ? JSON.stringify(options.eventPayload) : null},
      ${options.ref ?? null},
      ${options.commitSha ?? null},
      ${WorkflowStatus.Waiting},
      ${options.concurrencyGroup ?? null},
      ${options.concurrencyCancel ?? false},
      ${options.sessionId ?? null}
    )
    RETURNING *
  `;
  return rowToRun(rows[0]);
}

export async function updateRunStatus(
  id: number,
  status: WorkflowStatus,
  stoppedAt?: Date
): Promise<void> {
  if (stoppedAt) {
    await sql`
      UPDATE workflow_runs SET
        status = ${status},
        started_at = COALESCE(started_at, CASE WHEN ${status} = ${WorkflowStatus.Running} THEN NOW() ELSE NULL END),
        stopped_at = ${stoppedAt},
        updated_at = NOW()
      WHERE id = ${id}
    `;
  } else {
    await sql`
      UPDATE workflow_runs SET
        status = ${status},
        started_at = COALESCE(started_at, CASE WHEN ${status} = ${WorkflowStatus.Running} THEN NOW() ELSE NULL END),
        updated_at = NOW()
      WHERE id = ${id}
    `;
  }
}

function rowToRun(row: Record<string, unknown>): WorkflowRun {
  return {
    id: row.id as number,
    repositoryId: row.repository_id as number,
    workflowDefinitionId: row.workflow_definition_id as number | undefined,
    runNumber: row.run_number as number,
    title: row.title as string,
    triggerEvent: row.trigger_event as string,
    triggerUserId: row.trigger_user_id as number | undefined,
    eventPayload: row.event_payload as Record<string, unknown> | undefined,
    ref: row.ref as string | undefined,
    commitSha: row.commit_sha as string | undefined,
    status: parseStatus(row.status as number),
    concurrencyGroup: row.concurrency_group as string | undefined,
    concurrencyCancel: row.concurrency_cancel as boolean,
    startedAt: rowToDate(row.started_at),
    stoppedAt: rowToDate(row.stopped_at),
    createdAt: rowToDate(row.created_at)!,
    updatedAt: rowToDate(row.updated_at)!,
    sessionId: row.session_id as string | undefined,
  };
}

// =============================================================================
// Workflow Job Operations
// =============================================================================

export async function getJob(id: number): Promise<WorkflowJob | null> {
  const rows = await sql`
    SELECT * FROM workflow_jobs WHERE id = ${id}
  `;
  const row = rows[0];
  if (!row) return null;
  return rowToJob(row);
}

export async function getJobsForRun(runId: number): Promise<WorkflowJob[]> {
  const rows = await sql`
    SELECT * FROM workflow_jobs
    WHERE run_id = ${runId}
    ORDER BY id
  `;
  return rows.map(rowToJob);
}

export async function createJob(
  options: CreateWorkflowJobOptions
): Promise<WorkflowJob> {
  const rows = await sql`
    INSERT INTO workflow_jobs (
      run_id, repository_id, name, job_id,
      needs, runs_on, status,
      raw_concurrency, concurrency_group, concurrency_cancel
    ) VALUES (
      ${options.runId},
      ${options.repositoryId},
      ${options.name},
      ${options.jobId},
      ${JSON.stringify(options.needs ?? [])},
      ${JSON.stringify(options.runsOn ?? [])},
      ${WorkflowStatus.Waiting},
      ${options.rawConcurrency ?? null},
      ${options.concurrencyGroup ?? null},
      ${options.concurrencyCancel ?? false}
    )
    RETURNING *
  `;
  return rowToJob(rows[0]);
}

export async function updateJobStatus(
  id: number,
  status: WorkflowStatus,
  stoppedAt?: Date
): Promise<void> {
  if (stoppedAt) {
    await sql`
      UPDATE workflow_jobs SET
        status = ${status},
        started_at = COALESCE(started_at, CASE WHEN ${status} = ${WorkflowStatus.Running} THEN NOW() ELSE NULL END),
        stopped_at = ${stoppedAt},
        updated_at = NOW()
      WHERE id = ${id}
    `;
  } else {
    await sql`
      UPDATE workflow_jobs SET
        status = ${status},
        started_at = COALESCE(started_at, CASE WHEN ${status} = ${WorkflowStatus.Running} THEN NOW() ELSE NULL END),
        updated_at = NOW()
      WHERE id = ${id}
    `;
  }
}

function rowToJob(row: Record<string, unknown>): WorkflowJob {
  return {
    id: row.id as number,
    runId: row.run_id as number,
    repositoryId: row.repository_id as number,
    name: row.name as string,
    jobId: row.job_id as string,
    needs: (row.needs as string[]) ?? [],
    runsOn: (row.runs_on as string[]) ?? [],
    status: parseStatus(row.status as number),
    attempt: row.attempt as number,
    rawConcurrency: row.raw_concurrency as string | undefined,
    concurrencyGroup: row.concurrency_group as string | undefined,
    concurrencyCancel: row.concurrency_cancel as boolean,
    startedAt: rowToDate(row.started_at),
    stoppedAt: rowToDate(row.stopped_at),
    createdAt: rowToDate(row.created_at)!,
    updatedAt: rowToDate(row.updated_at)!,
  };
}

// =============================================================================
// Workflow Task Operations
// =============================================================================

export async function getTask(id: number): Promise<WorkflowTask | null> {
  const rows = await sql`
    SELECT * FROM workflow_tasks WHERE id = ${id}
  `;
  const row = rows[0];
  if (!row) return null;
  return rowToTask(row);
}

export async function getTaskByToken(
  tokenHash: string
): Promise<WorkflowTask | null> {
  const rows = await sql`
    SELECT * FROM workflow_tasks WHERE token_hash = ${tokenHash}
  `;
  const row = rows[0];
  if (!row) return null;
  return rowToTask(row);
}

export async function getTaskWithContext(
  id: number
): Promise<TaskWithContext | null> {
  const task = await getTask(id);
  if (!task) return null;

  const job = await getJob(task.jobId);
  if (!job) return null;

  const run = await getRun(job.runId);
  if (!run) return null;

  const runner = task.runnerId ? await getRunner(task.runnerId) : undefined;

  return { ...task, job, run, runner };
}

export async function createTask(
  options: CreateWorkflowTaskOptions
): Promise<WorkflowTask> {
  const { token, hash, lastEight } = generateToken();

  const rows = await sql`
    INSERT INTO workflow_tasks (
      job_id, repository_id, attempt, status,
      commit_sha, workflow_content, workflow_path,
      token_hash, token_last_eight
    ) VALUES (
      ${options.jobId},
      ${options.repositoryId},
      ${options.attempt ?? 1},
      ${WorkflowStatus.Waiting},
      ${options.commitSha ?? null},
      ${options.workflowContent ?? null},
      ${options.workflowPath ?? null},
      ${hash},
      ${lastEight}
    )
    RETURNING *
  `;
  const task = rowToTask(rows[0]);
  // Include token for returning to runner
  return { ...task, tokenHash: hash, token } as WorkflowTask & { token: string };
}

export async function assignTaskToRunner(
  taskId: number,
  runnerId: number
): Promise<void> {
  await sql`
    UPDATE workflow_tasks SET
      runner_id = ${runnerId},
      status = ${WorkflowStatus.Running},
      started_at = NOW(),
      updated_at = NOW()
    WHERE id = ${taskId}
  `;
}

export async function updateTaskStatus(
  id: number,
  status: WorkflowStatus,
  stoppedAt?: Date
): Promise<void> {
  if (stoppedAt) {
    await sql`
      UPDATE workflow_tasks SET
        status = ${status},
        stopped_at = ${stoppedAt},
        updated_at = NOW()
      WHERE id = ${id}
    `;
  } else {
    await sql`
      UPDATE workflow_tasks SET
        status = ${status},
        updated_at = NOW()
      WHERE id = ${id}
    `;
  }
}

/**
 * Find an available task for a runner.
 * Returns the oldest waiting task that matches the runner's labels.
 */
export async function findAvailableTask(
  runnerId: number,
  labels: string[]
): Promise<TaskWithContext | null> {
  // Find waiting tasks where the job's runs_on labels match the runner's labels
  // For simplicity, we check if the runner has all required labels
  const rows = await sql`
    SELECT t.id FROM workflow_tasks t
    JOIN workflow_jobs j ON t.job_id = j.id
    WHERE t.status = ${WorkflowStatus.Waiting}
      AND t.runner_id IS NULL
      AND (
        j.runs_on = '[]'::jsonb
        OR j.runs_on <@ ${JSON.stringify(labels)}::jsonb
      )
    ORDER BY t.created_at ASC
    LIMIT 1
  `;

  if (rows.length === 0) return null;

  const taskId = rows[0].id as number;
  await assignTaskToRunner(taskId, runnerId);

  return getTaskWithContext(taskId);
}

function rowToTask(row: Record<string, unknown>): WorkflowTask {
  return {
    id: row.id as number,
    jobId: row.job_id as number,
    runnerId: row.runner_id as number | undefined,
    attempt: row.attempt as number,
    status: parseStatus(row.status as number),
    repositoryId: row.repository_id as number,
    commitSha: row.commit_sha as string | undefined,
    workflowContent: row.workflow_content as string | undefined,
    workflowPath: row.workflow_path as string | undefined,
    tokenHash: row.token_hash as string | undefined,
    tokenLastEight: row.token_last_eight as string | undefined,
    logFilename: row.log_filename as string | undefined,
    logSize: (row.log_size as number) ?? 0,
    startedAt: rowToDate(row.started_at),
    stoppedAt: rowToDate(row.stopped_at),
    createdAt: rowToDate(row.created_at)!,
    updatedAt: rowToDate(row.updated_at)!,
  };
}

// =============================================================================
// Workflow Step Operations
// =============================================================================

export async function getStep(id: number): Promise<WorkflowStep | null> {
  const rows = await sql`
    SELECT * FROM workflow_steps WHERE id = ${id}
  `;
  const row = rows[0];
  if (!row) return null;
  return rowToStep(row);
}

export async function getStepsForTask(taskId: number): Promise<WorkflowStep[]> {
  const rows = await sql`
    SELECT * FROM workflow_steps
    WHERE task_id = ${taskId}
    ORDER BY step_index
  `;
  return rows.map(rowToStep);
}

export async function createStep(
  options: CreateWorkflowStepOptions
): Promise<WorkflowStep> {
  const rows = await sql`
    INSERT INTO workflow_steps (
      task_id, name, step_index, status
    ) VALUES (
      ${options.taskId},
      ${options.name},
      ${options.stepIndex},
      ${WorkflowStatus.Waiting}
    )
    RETURNING *
  `;
  return rowToStep(rows[0]);
}

export async function updateStep(
  id: number,
  updates: UpdateWorkflowStepOptions
): Promise<void> {
  await sql`
    UPDATE workflow_steps SET
      status = COALESCE(${updates.status ?? null}, status),
      log_index = COALESCE(${updates.logIndex ?? null}, log_index),
      log_length = COALESCE(${updates.logLength ?? null}, log_length),
      output = COALESCE(${updates.output ? JSON.stringify(updates.output) : null}, output),
      started_at = COALESCE(${updates.startedAt ?? null}, started_at),
      stopped_at = COALESCE(${updates.stoppedAt ?? null}, stopped_at)
    WHERE id = ${id}
  `;
}

export async function updateStepStatus(
  id: number,
  status: WorkflowStatus,
  stoppedAt?: Date
): Promise<void> {
  if (stoppedAt) {
    await sql`
      UPDATE workflow_steps SET
        status = ${status},
        started_at = COALESCE(started_at, CASE WHEN ${status} = ${WorkflowStatus.Running} THEN NOW() ELSE NULL END),
        stopped_at = ${stoppedAt}
      WHERE id = ${id}
    `;
  } else {
    await sql`
      UPDATE workflow_steps SET
        status = ${status},
        started_at = COALESCE(started_at, CASE WHEN ${status} = ${WorkflowStatus.Running} THEN NOW() ELSE NULL END)
      WHERE id = ${id}
    `;
  }
}

function rowToStep(row: Record<string, unknown>): WorkflowStep {
  return {
    id: row.id as number,
    taskId: row.task_id as number,
    name: row.name as string,
    stepIndex: row.step_index as number,
    status: parseStatus(row.status as number),
    logIndex: (row.log_index as number) ?? 0,
    logLength: (row.log_length as number) ?? 0,
    output: row.output as Record<string, unknown> | undefined,
    startedAt: rowToDate(row.started_at),
    stoppedAt: rowToDate(row.stopped_at),
    createdAt: rowToDate(row.created_at)!,
  };
}

// =============================================================================
// Workflow Log Operations
// =============================================================================

export async function appendLogs(options: AppendLogOptions): Promise<void> {
  if (options.lines.length === 0) return;

  // Get current max line number for this task/step
  const maxResult = await sql`
    SELECT COALESCE(MAX(line_number), -1) as max_line
    FROM workflow_logs
    WHERE task_id = ${options.taskId} AND step_index = ${options.stepIndex}
  `;
  let lineNumber = (maxResult[0].max_line as number) + 1;

  // Insert all lines
  for (const content of options.lines) {
    await sql`
      INSERT INTO workflow_logs (task_id, step_index, line_number, content)
      VALUES (${options.taskId}, ${options.stepIndex}, ${lineNumber}, ${content})
    `;
    lineNumber++;
  }

  // Update step log_length
  await sql`
    UPDATE workflow_steps SET
      log_length = log_length + ${options.lines.length}
    WHERE task_id = ${options.taskId} AND step_index = ${options.stepIndex}
  `;
}

export async function getLogs(
  taskId: number,
  stepIndex?: number,
  options?: { offset?: number; limit?: number }
): Promise<WorkflowLog[]> {
  const limit = options?.limit ?? 1000;
  const offset = options?.offset ?? 0;

  if (stepIndex !== undefined) {
    const rows = await sql`
      SELECT * FROM workflow_logs
      WHERE task_id = ${taskId} AND step_index = ${stepIndex}
      ORDER BY line_number
      OFFSET ${offset} LIMIT ${limit}
    `;
    return rows.map(rowToLog);
  }

  const rows = await sql`
    SELECT * FROM workflow_logs
    WHERE task_id = ${taskId}
    ORDER BY step_index, line_number
    OFFSET ${offset} LIMIT ${limit}
  `;
  return rows.map(rowToLog);
}

function rowToLog(row: Record<string, unknown>): WorkflowLog {
  return {
    id: row.id as number,
    taskId: row.task_id as number,
    stepIndex: row.step_index as number,
    lineNumber: row.line_number as number,
    content: row.content as string,
    timestamp: rowToDate(row.timestamp)!,
  };
}

// =============================================================================
// Commit Status Operations
// =============================================================================

export interface CommitStatus {
  id: number;
  repositoryId: number;
  commitSha: string;
  context: string;
  state: 'pending' | 'success' | 'failure' | 'error';
  description: string | undefined;
  targetUrl: string | undefined;
  workflowRunId: number | undefined;
  createdAt: Date;
  updatedAt: Date;
}

export interface CreateCommitStatusOptions {
  repositoryId: number;
  commitSha: string;
  context: string;
  state: 'pending' | 'success' | 'failure' | 'error';
  description?: string;
  targetUrl?: string;
  workflowRunId?: number;
}

export async function createOrUpdateCommitStatus(
  options: CreateCommitStatusOptions
): Promise<CommitStatus> {
  const rows = await sql`
    INSERT INTO commit_statuses (
      repository_id, commit_sha, context, state,
      description, target_url, workflow_run_id
    ) VALUES (
      ${options.repositoryId},
      ${options.commitSha},
      ${options.context},
      ${options.state},
      ${options.description ?? null},
      ${options.targetUrl ?? null},
      ${options.workflowRunId ?? null}
    )
    ON CONFLICT (repository_id, commit_sha, context)
    DO UPDATE SET
      state = EXCLUDED.state,
      description = EXCLUDED.description,
      target_url = EXCLUDED.target_url,
      workflow_run_id = EXCLUDED.workflow_run_id,
      updated_at = NOW()
    RETURNING *
  `;
  return rowToCommitStatus(rows[0]);
}

export async function getCommitStatuses(
  repositoryId: number,
  commitSha: string
): Promise<CommitStatus[]> {
  const rows = await sql`
    SELECT * FROM commit_statuses
    WHERE repository_id = ${repositoryId} AND commit_sha = ${commitSha}
    ORDER BY context
  `;
  return rows.map(rowToCommitStatus);
}

export async function getCommitStatusByContext(
  repositoryId: number,
  commitSha: string,
  context: string
): Promise<CommitStatus | null> {
  const rows = await sql`
    SELECT * FROM commit_statuses
    WHERE repository_id = ${repositoryId}
      AND commit_sha = ${commitSha}
      AND context = ${context}
  `;
  if (rows.length === 0) return null;
  return rowToCommitStatus(rows[0]);
}

/**
 * Update commit status when a workflow run completes.
 */
export async function updateCommitStatusFromRun(
  run: WorkflowRun
): Promise<void> {
  if (!run.commitSha) return;

  const workflowDef = run.workflowDefinitionId
    ? await getWorkflowDefinition(run.workflowDefinitionId)
    : null;

  const context = workflowDef?.name ?? `workflow-${run.id}`;

  let state: 'pending' | 'success' | 'failure' | 'error';
  let description: string;

  if (run.status === WorkflowStatus.Success) {
    state = 'success';
    description = 'All checks passed';
  } else if (run.status === WorkflowStatus.Failure) {
    state = 'failure';
    description = 'Some checks failed';
  } else if (run.status === WorkflowStatus.Running || run.status === WorkflowStatus.Waiting) {
    state = 'pending';
    description = 'Checks in progress';
  } else {
    state = 'error';
    description = 'Checks encountered an error';
  }

  await createOrUpdateCommitStatus({
    repositoryId: run.repositoryId,
    commitSha: run.commitSha,
    context,
    state,
    description,
    workflowRunId: run.id,
  });
}

function rowToCommitStatus(row: Record<string, unknown>): CommitStatus {
  return {
    id: row.id as number,
    repositoryId: row.repository_id as number,
    commitSha: row.commit_sha as string,
    context: row.context as string,
    state: row.state as 'pending' | 'success' | 'failure' | 'error',
    description: row.description as string | undefined,
    targetUrl: row.target_url as string | undefined,
    workflowRunId: row.workflow_run_id as number | undefined,
    createdAt: rowToDate(row.created_at)!,
    updatedAt: rowToDate(row.updated_at)!,
  };
}
