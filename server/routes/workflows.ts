/**
 * Workflow routes - API for managing workflow runs.
 */

import { Hono } from 'hono';
import { requireAuth, requireActiveAccount } from '../middleware/auth';
import {
  listRuns,
  getRun,
  createRun,
  updateRunStatus,
  getJobsForRun,
  createJob,
  getStepsForTask,
  createTask,
  getLogs,
  listWorkflowDefinitions,
  getWorkflowDefinitionByName,
  WorkflowStatus,
  parseStatusString,
} from '../../core/workflows';
import sql from '../../db/client';

const app = new Hono();

// Apply authentication to all workflow routes
app.use('*', requireAuth, requireActiveAccount);

// =============================================================================
// Helper Functions
// =============================================================================

/**
 * Get repository ID from user/repo path.
 */
async function getRepositoryId(
  username: string,
  repoName: string
): Promise<number | null> {
  const rows = await sql`
    SELECT r.id FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.lower_username = ${username.toLowerCase()}
      AND LOWER(r.name) = ${repoName.toLowerCase()}
  `;
  return rows[0]?.id ?? null;
}

// =============================================================================
// Workflow Runs
// =============================================================================

/**
 * GET /:user/:repo/workflows/runs
 * List workflow runs for a repository.
 */
app.get('/:user/:repo/workflows/runs', async (c) => {
  const { user, repo } = c.req.param();
  const statusParam = c.req.query('status');
  const page = parseInt(c.req.query('page') ?? '1');
  const perPage = parseInt(c.req.query('per_page') ?? '20');

  const repositoryId = await getRepositoryId(user, repo);
  if (!repositoryId) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const status = statusParam ? parseStatusString(statusParam) : undefined;
  const offset = (page - 1) * perPage;

  const runs = await listRuns(repositoryId, {
    status,
    limit: perPage,
    offset,
  });

  return c.json({
    runs,
    page,
    perPage,
  });
});

/**
 * GET /:user/:repo/workflows/runs/:runId
 * Get a specific workflow run with its jobs.
 */
app.get('/:user/:repo/workflows/runs/:runId', async (c) => {
  const runId = parseInt(c.req.param('runId'));

  const run = await getRun(runId);
  if (!run) {
    return c.json({ error: 'Workflow run not found' }, 404);
  }

  const jobs = await getJobsForRun(runId);

  return c.json({ run, jobs });
});

/**
 * GET /:user/:repo/workflows/runs/:runId/jobs/:jobId/steps
 * Get steps for a specific job.
 */
app.get('/:user/:repo/workflows/runs/:runId/jobs/:jobId/steps', async (c) => {
  const jobId = parseInt(c.req.param('jobId'));

  // Get the task for this job (assuming one task per job for now)
  const rows = await sql`
    SELECT id FROM workflow_tasks WHERE job_id = ${jobId} ORDER BY attempt DESC LIMIT 1
  `;

  if (rows.length === 0) {
    return c.json({ steps: [] });
  }

  const taskId = rows[0].id as number;
  const steps = await getStepsForTask(taskId);

  return c.json({ steps });
});

/**
 * GET /:user/:repo/workflows/runs/:runId/logs
 * Get logs for a workflow run.
 */
app.get('/:user/:repo/workflows/runs/:runId/logs', async (c) => {
  const runId = parseInt(c.req.param('runId'));
  const stepIndex = c.req.query('step')
    ? parseInt(c.req.query('step')!)
    : undefined;

  // Get all tasks for this run
  const taskRows = await sql`
    SELECT t.id FROM workflow_tasks t
    JOIN workflow_jobs j ON t.job_id = j.id
    WHERE j.run_id = ${runId}
    ORDER BY j.id, t.attempt
  `;

  if (taskRows.length === 0) {
    return c.text('', 200, { 'Content-Type': 'text/plain' });
  }

  // Aggregate logs from all tasks
  let allLogs = '';
  for (const row of taskRows) {
    const taskId = row.id as number;
    const logs = await getLogs(taskId, stepIndex);
    allLogs += logs.map((l) => l.content).join('\n');
    if (logs.length > 0) allLogs += '\n';
  }

  return c.text(allLogs, 200, { 'Content-Type': 'text/plain' });
});

// =============================================================================
// Workflow Dispatch (Manual Trigger)
// =============================================================================

/**
 * POST /:user/:repo/workflows/dispatch
 * Manually trigger a workflow.
 */
app.post('/:user/:repo/workflows/dispatch', async (c) => {
  const { user, repo } = c.req.param();
  const body = await c.req.json();

  const repositoryId = await getRepositoryId(user, repo);
  if (!repositoryId) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  // Get authenticated user from context
  const authUser = c.get('user') as { id: number } | undefined;

  // Create the workflow run
  const run = await createRun({
    repositoryId,
    workflowDefinitionId: body.workflowDefinitionId,
    title: body.title ?? 'Manual workflow run',
    triggerEvent: 'manual',
    triggerUserId: authUser?.id,
    eventPayload: body.inputs,
    ref: body.ref ?? 'main',
    commitSha: body.commitSha,
  });

  // Create a default job if workflow content is provided
  if (body.workflowContent) {
    const job = await createJob({
      runId: run.id,
      repositoryId,
      name: 'default',
      jobId: 'default',
    });

    // Create a task for the job
    await createTask({
      jobId: job.id,
      repositoryId,
      commitSha: body.commitSha,
      workflowContent: body.workflowContent,
      workflowPath: body.workflowPath ?? '.plue/workflows/manual.py',
    });

    // Update run status to waiting (ready for runner)
    await updateRunStatus(run.id, WorkflowStatus.Waiting);
  }

  return c.json({ run }, 201);
});

/**
 * POST /:user/:repo/workflows/:workflowName/dispatch
 * Trigger a specific workflow by name.
 */
app.post('/:user/:repo/workflows/:workflowName/dispatch', async (c) => {
  const { user, repo, workflowName } = c.req.param();
  const body = await c.req.json();

  const repositoryId = await getRepositoryId(user, repo);
  if (!repositoryId) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  // Find the workflow definition
  const definition = await getWorkflowDefinitionByName(repositoryId, workflowName);
  if (!definition) {
    return c.json({ error: 'Workflow not found' }, 404);
  }

  // Get authenticated user from context
  const authUser = c.get('user') as { id: number } | undefined;

  // Create the workflow run
  const run = await createRun({
    repositoryId,
    workflowDefinitionId: definition.id,
    title: definition.name,
    triggerEvent: 'manual',
    triggerUserId: authUser?.id,
    eventPayload: body.inputs,
    ref: body.ref ?? 'main',
    commitSha: body.commitSha,
  });

  // Create a default job
  const job = await createJob({
    runId: run.id,
    repositoryId,
    name: definition.name,
    jobId: 'main',
  });

  // Create a task for the job
  // In a full implementation, we'd read the workflow file from the repo
  await createTask({
    jobId: job.id,
    repositoryId,
    commitSha: body.commitSha,
    workflowPath: definition.filePath,
  });

  return c.json({ run }, 201);
});

// =============================================================================
// Workflow Control
// =============================================================================

/**
 * POST /:user/:repo/workflows/runs/:runId/cancel
 * Cancel a running workflow.
 */
app.post('/:user/:repo/workflows/runs/:runId/cancel', async (c) => {
  const runId = parseInt(c.req.param('runId'));

  const run = await getRun(runId);
  if (!run) {
    return c.json({ error: 'Workflow run not found' }, 404);
  }

  // Can only cancel running or waiting workflows
  if (
    run.status !== WorkflowStatus.Running &&
    run.status !== WorkflowStatus.Waiting
  ) {
    return c.json({ error: 'Cannot cancel completed workflow' }, 400);
  }

  await updateRunStatus(runId, WorkflowStatus.Cancelled, new Date());

  return c.json({ ok: true });
});

/**
 * POST /:user/:repo/workflows/runs/:runId/rerun
 * Re-run a completed workflow.
 */
app.post('/:user/:repo/workflows/runs/:runId/rerun', async (c) => {
  const runId = parseInt(c.req.param('runId'));

  const originalRun = await getRun(runId);
  if (!originalRun) {
    return c.json({ error: 'Workflow run not found' }, 404);
  }

  // Get authenticated user from context
  const authUser = c.get('user') as { id: number } | undefined;

  // Create a new run based on the original
  const newRun = await createRun({
    repositoryId: originalRun.repositoryId,
    workflowDefinitionId: originalRun.workflowDefinitionId ?? undefined,
    title: `${originalRun.title} (rerun)`,
    triggerEvent: 'manual',
    triggerUserId: authUser?.id,
    eventPayload: originalRun.eventPayload,
    ref: originalRun.ref ?? undefined,
    commitSha: originalRun.commitSha ?? undefined,
  });

  // Copy jobs from original run
  const originalJobs = await getJobsForRun(runId);
  for (const job of originalJobs) {
    const newJob = await createJob({
      runId: newRun.id,
      repositoryId: originalRun.repositoryId,
      name: job.name,
      jobId: job.jobId,
      needs: job.needs,
      runsOn: job.runsOn,
    });

    // Get original task for workflow content
    const taskRows = await sql`
      SELECT workflow_content, workflow_path, commit_sha
      FROM workflow_tasks
      WHERE job_id = ${job.id}
      ORDER BY attempt DESC
      LIMIT 1
    `;

    if (taskRows.length > 0) {
      const originalTask = taskRows[0];
      await createTask({
        jobId: newJob.id,
        repositoryId: originalRun.repositoryId,
        commitSha: (originalTask.commit_sha as string) ?? undefined,
        workflowContent: (originalTask.workflow_content as string) ?? undefined,
        workflowPath: (originalTask.workflow_path as string) ?? undefined,
      });
    }
  }

  return c.json({ run: newRun }, 201);
});

// =============================================================================
// Workflow Definitions
// =============================================================================

/**
 * GET /:user/:repo/workflows
 * List workflow definitions for a repository.
 */
app.get('/:user/:repo/workflows', async (c) => {
  const { user, repo } = c.req.param();

  const repositoryId = await getRepositoryId(user, repo);
  if (!repositoryId) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const definitions = await listWorkflowDefinitions(repositoryId);

  return c.json({ workflows: definitions });
});

export default app;
