/**
 * Workflows Data Access Object
 *
 * SQL operations for workflow definitions and runs.
 */

import { sql } from '../client';

// =============================================================================
// Types
// =============================================================================

export interface WorkflowDefinition {
  id: number;
  repository_id: number;
  name: string;
  file_path: string;
  triggers: string;
  plan: string;
  created_at: Date;
  updated_at: Date;
}

export interface WorkflowRun {
  id: number;
  repository_id: number;
  workflow_definition_id: number;
  run_number: number;
  title: string;
  trigger_event: string;
  status: number;
  ref: string | null;
  commit_sha: string | null;
  created_at: Date;
  started_at: Date | null;
  stopped_at: Date | null;
}

export interface WorkflowJob {
  id: number;
  workflow_run_id: number;
  name: string;
  status: number;
  started_at: Date | null;
  completed_at: Date | null;
}

export interface WorkflowStep {
  id: number;
  workflow_job_id: number;
  name: string;
  status: number;
  conclusion: string | null;
  started_at: Date | null;
  completed_at: Date | null;
}

// Status codes
export const WorkflowStatus = {
  SUCCESS: 1,
  FAILURE: 2,
  CANCELLED: 3,
  PENDING: 4,
  WAITING: 5,
  RUNNING: 6,
} as const;

// =============================================================================
// Workflow Definitions
// =============================================================================

/**
 * List workflow definitions for a repository
 */
export async function listDefinitions(repositoryId: number): Promise<WorkflowDefinition[]> {
  return await sql<WorkflowDefinition[]>`
    SELECT * FROM workflow_definitions
    WHERE repository_id = ${repositoryId}
    ORDER BY name
  `;
}

/**
 * Get workflow definition by ID
 */
export async function getDefinition(id: number): Promise<WorkflowDefinition | null> {
  const [def] = await sql<WorkflowDefinition[]>`
    SELECT * FROM workflow_definitions WHERE id = ${id}
  `;
  return def || null;
}

// =============================================================================
// Workflow Runs
// =============================================================================

/**
 * List workflow runs for a repository with optional filters
 */
export async function listRuns(
  repositoryId: number,
  options: {
    status?: number;
    workflowDefinitionId?: number;
    limit?: number;
    offset?: number;
  } = {}
): Promise<WorkflowRun[]> {
  const { status, workflowDefinitionId, limit = 20, offset = 0 } = options;

  return await sql<WorkflowRun[]>`
    SELECT * FROM workflow_runs
    WHERE repository_id = ${repositoryId}
    ${status !== undefined ? sql`AND status = ${status}` : sql``}
    ${workflowDefinitionId !== undefined ? sql`AND workflow_definition_id = ${workflowDefinitionId}` : sql``}
    ORDER BY created_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;
}

/**
 * Count workflow runs for a repository with optional filters
 */
export async function countRuns(
  repositoryId: number,
  options: {
    status?: number;
    workflowDefinitionId?: number;
  } = {}
): Promise<number> {
  const { status, workflowDefinitionId } = options;

  const [result] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count FROM workflow_runs
    WHERE repository_id = ${repositoryId}
    ${status !== undefined ? sql`AND status = ${status}` : sql``}
    ${workflowDefinitionId !== undefined ? sql`AND workflow_definition_id = ${workflowDefinitionId}` : sql``}
  `;
  return result?.count || 0;
}

/**
 * Get workflow run by ID
 */
export async function getRun(id: number): Promise<WorkflowRun | null> {
  const [run] = await sql<WorkflowRun[]>`
    SELECT * FROM workflow_runs WHERE id = ${id}
  `;
  return run || null;
}

/**
 * Count errors for a workflow definition
 */
export async function countErrors(workflowDefinitionId: number): Promise<number> {
  const [result] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count FROM workflow_runs
    WHERE workflow_definition_id = ${workflowDefinitionId} AND status = ${WorkflowStatus.FAILURE}
  `;
  return result?.count || 0;
}

/**
 * Count running workflows for a repository
 */
export async function countRunning(repositoryId: number): Promise<number> {
  const [result] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count FROM workflow_runs
    WHERE repository_id = ${repositoryId} AND status = ${WorkflowStatus.RUNNING}
  `;
  return result?.count || 0;
}

/**
 * Count recent failures for a repository (last 24h)
 */
export async function countRecentFailures(repositoryId: number): Promise<number> {
  const [result] = await sql<[{ count: number }]>`
    SELECT COUNT(*)::int as count FROM workflow_runs
    WHERE repository_id = ${repositoryId}
    AND status = ${WorkflowStatus.FAILURE}
    AND created_at > NOW() - INTERVAL '24 hours'
  `;
  return result?.count || 0;
}

// =============================================================================
// Workflow Jobs & Steps
// =============================================================================

/**
 * List jobs for a workflow run
 */
export async function listJobs(workflowRunId: number): Promise<WorkflowJob[]> {
  return await sql<WorkflowJob[]>`
    SELECT * FROM workflow_jobs
    WHERE workflow_run_id = ${workflowRunId}
    ORDER BY id
  `;
}

/**
 * List steps for a workflow job
 */
export async function listSteps(workflowJobId: number): Promise<WorkflowStep[]> {
  return await sql<WorkflowStep[]>`
    SELECT * FROM workflow_steps
    WHERE workflow_job_id = ${workflowJobId}
    ORDER BY id
  `;
}

/**
 * List tasks for a workflow run
 */
export async function listTasks(workflowRunId: number): Promise<any[]> {
  return await sql`
    SELECT * FROM tasks
    WHERE workflow_run_id = ${workflowRunId}
    ORDER BY step_order
  `;
}

/**
 * List artifacts for a workflow run
 */
export async function listArtifacts(workflowRunId: number): Promise<any[]> {
  return await sql`
    SELECT * FROM workflow_artifacts
    WHERE workflow_run_id = ${workflowRunId}
    ORDER BY created_at
  `;
}
