/**
 * Runner routes - API for workflow runners to register and fetch tasks.
 */

import { Hono } from 'hono';
import { createHash } from 'crypto';
import {
  registerRunner,
  getRunnerByToken,
  updateRunnerHeartbeat,
  findAvailableTask,
  getTaskByToken,
  updateTaskStatus,
  updateJobStatus,
  updateRunStatus,
  appendLogs,
  getStepsForTask,
  updateStep,
  createStep,
  WorkflowStatus,
  isDone,
  aggregateStatus,
} from '../../core/workflows';

const app = new Hono();

/**
 * Hash a token for lookup.
 */
function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/**
 * Extract runner token from request header.
 */
function getRunnerToken(c: { req: { header: (name: string) => string | undefined } }): string | null {
  const header = c.req.header('Authorization');
  if (!header?.startsWith('Bearer ')) return null;
  return header.slice(7);
}

/**
 * Extract task token from request header.
 */
function getTaskToken(c: { req: { header: (name: string) => string | undefined } }): string | null {
  return c.req.header('X-Task-Token') ?? null;
}

// =============================================================================
// Runner Registration and Heartbeat
// =============================================================================

/**
 * POST /runners/register
 * Register a new runner with the server.
 */
app.post('/register', async (c) => {
  const body = await c.req.json();

  if (!body.name) {
    return c.json({ error: 'Runner name is required' }, 400);
  }

  const runner = await registerRunner({
    name: body.name,
    version: body.version,
    labels: body.labels ?? [],
  });

  return c.json({
    runner: {
      id: runner.id,
      name: runner.name,
      labels: runner.labels,
    },
    token: runner.token,
  }, 201);
});

/**
 * POST /runners/heartbeat
 * Update runner status and last seen timestamp.
 */
app.post('/heartbeat', async (c) => {
  const token = getRunnerToken(c);
  if (!token) {
    return c.json({ error: 'Runner token required' }, 401);
  }

  const tokenHash = hashToken(token);
  const runner = await getRunnerByToken(tokenHash);
  if (!runner) {
    return c.json({ error: 'Invalid runner token' }, 401);
  }

  await updateRunnerHeartbeat(tokenHash);

  return c.json({ ok: true });
});

// =============================================================================
// Task Fetch and Status Update
// =============================================================================

/**
 * GET /runners/tasks/fetch
 * Long-poll for an available task to execute.
 */
app.get('/tasks/fetch', async (c) => {
  const token = getRunnerToken(c);
  if (!token) {
    return c.json({ error: 'Runner token required' }, 401);
  }

  const tokenHash = hashToken(token);
  const runner = await getRunnerByToken(tokenHash);
  if (!runner) {
    return c.json({ error: 'Invalid runner token' }, 401);
  }

  // Update heartbeat
  await updateRunnerHeartbeat(tokenHash);

  // Try to find an available task
  const task = await findAvailableTask(runner.id, runner.labels);

  if (!task) {
    return c.json({ task: null });
  }

  // Return task with context
  return c.json({
    task: {
      id: task.id,
      jobId: task.jobId,
      attempt: task.attempt,
      repositoryId: task.repositoryId,
      commitSha: task.commitSha,
      workflowContent: task.workflowContent,
      workflowPath: task.workflowPath,
      token: task.tokenHash, // Task-specific token for status updates

      // Include job and run context
      job: {
        id: task.job.id,
        name: task.job.name,
        jobId: task.job.jobId,
      },
      run: {
        id: task.run.id,
        runNumber: task.run.runNumber,
        title: task.run.title,
        triggerEvent: task.run.triggerEvent,
        ref: task.run.ref,
        commitSha: task.run.commitSha,
      },
    },
  });
});

/**
 * POST /runners/tasks/:taskId/status
 * Update task execution status.
 */
app.post('/tasks/:taskId/status', async (c) => {
  const taskId = parseInt(c.req.param('taskId'));
  const taskToken = getTaskToken(c);

  if (!taskToken) {
    return c.json({ error: 'Task token required' }, 401);
  }

  // Verify task token
  const tokenHash = hashToken(taskToken);
  const task = await getTaskByToken(tokenHash);
  if (!task || task.id !== taskId) {
    return c.json({ error: 'Invalid task token' }, 401);
  }

  const body = await c.req.json();
  const status = body.status as WorkflowStatus;
  const stoppedAt = body.stoppedAt ? new Date(body.stoppedAt) : undefined;

  // Update task status
  await updateTaskStatus(taskId, status, stoppedAt);

  // Update steps if provided
  if (body.steps && Array.isArray(body.steps)) {
    const existingSteps = await getStepsForTask(taskId);
    const existingStepsByIndex = new Map(
      existingSteps.map((s) => [s.stepIndex, s])
    );

    for (const stepData of body.steps) {
      const existingStep = existingStepsByIndex.get(stepData.index);

      if (existingStep) {
        await updateStep(existingStep.id, {
          status: stepData.status,
          logIndex: stepData.logIndex,
          logLength: stepData.logLength,
          output: stepData.output,
          startedAt: stepData.startedAt ? new Date(stepData.startedAt) : undefined,
          stoppedAt: stepData.stoppedAt ? new Date(stepData.stoppedAt) : undefined,
        });
      } else {
        // Create step if it doesn't exist
        const step = await createStep({
          taskId,
          name: stepData.name ?? `Step ${stepData.index}`,
          stepIndex: stepData.index,
        });
        await updateStep(step.id, {
          status: stepData.status,
          output: stepData.output,
          startedAt: stepData.startedAt ? new Date(stepData.startedAt) : undefined,
          stoppedAt: stepData.stoppedAt ? new Date(stepData.stoppedAt) : undefined,
        });
      }
    }
  }

  // If task is done, update job status
  if (isDone(status)) {
    await updateJobStatus(task.jobId, status, stoppedAt);

    // Also update run status based on aggregated job statuses
    // (In a full implementation, we'd aggregate all jobs)
    await updateRunStatus(task.repositoryId, status, stoppedAt);
  }

  return c.json({ ok: true });
});

/**
 * POST /runners/tasks/:taskId/logs
 * Append log lines to a task step.
 */
app.post('/tasks/:taskId/logs', async (c) => {
  const taskId = parseInt(c.req.param('taskId'));
  const taskToken = getTaskToken(c);

  if (!taskToken) {
    return c.json({ error: 'Task token required' }, 401);
  }

  // Verify task token
  const tokenHash = hashToken(taskToken);
  const task = await getTaskByToken(tokenHash);
  if (!task || task.id !== taskId) {
    return c.json({ error: 'Invalid task token' }, 401);
  }

  const body = await c.req.json();

  if (typeof body.stepIndex !== 'number' || !Array.isArray(body.lines)) {
    return c.json({ error: 'stepIndex and lines array required' }, 400);
  }

  await appendLogs({
    taskId,
    stepIndex: body.stepIndex,
    lines: body.lines,
  });

  return c.json({ ok: true });
});

export default app;
