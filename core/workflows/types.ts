/**
 * Workflow system types.
 *
 * Hierarchy: WorkflowRun -> WorkflowJob -> WorkflowTask -> WorkflowStep
 *
 * - WorkflowRun: A single execution of a workflow (triggered by event or manual)
 * - WorkflowJob: A job within a run (can have dependencies via `needs`)
 * - WorkflowTask: Actual execution of a job on a runner (one task per job per attempt)
 * - WorkflowStep: Individual steps within a task
 */

import { WorkflowStatus } from './status';

// =============================================================================
// Workflow Definition
// =============================================================================

export interface WorkflowDefinition {
  id: number;
  repositoryId: number;
  name: string;
  filePath: string;
  fileSha?: string;
  events: string[];
  isAgentWorkflow: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface CreateWorkflowDefinitionOptions {
  repositoryId: number;
  name: string;
  filePath: string;
  fileSha?: string;
  events?: string[];
  isAgentWorkflow?: boolean;
}

// =============================================================================
// Workflow Runner
// =============================================================================

export type RunnerStatus = 'online' | 'offline' | 'busy';

export interface WorkflowRunner {
  id: number;
  name: string;
  ownerId?: number;
  repositoryId?: number;
  version?: string;
  labels: string[];
  status: RunnerStatus;
  lastOnlineAt?: Date;
  lastActiveAt?: Date;
  tokenHash?: string;
  tokenLastEight?: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface RegisterRunnerOptions {
  name: string;
  ownerId?: number;
  repositoryId?: number;
  version?: string;
  labels?: string[];
}

export interface RunnerWithToken extends WorkflowRunner {
  token: string; // Only returned on registration
}

// =============================================================================
// Workflow Run
// =============================================================================

export interface WorkflowRun {
  id: number;
  repositoryId: number;
  workflowDefinitionId?: number;
  runNumber: number;
  title: string;

  // Trigger info
  triggerEvent: string;
  triggerUserId?: number;
  eventPayload?: Record<string, unknown>;

  // Git context
  ref?: string;
  commitSha?: string;

  // Status
  status: WorkflowStatus;

  // Concurrency
  concurrencyGroup?: string;
  concurrencyCancel: boolean;

  // Timing
  startedAt?: Date;
  stoppedAt?: Date;
  createdAt: Date;
  updatedAt: Date;

  // Agent session link
  sessionId?: string;
}

export interface CreateWorkflowRunOptions {
  repositoryId: number;
  workflowDefinitionId?: number;
  title: string;
  triggerEvent: string;
  triggerUserId?: number;
  eventPayload?: Record<string, unknown>;
  ref?: string;
  commitSha?: string;
  concurrencyGroup?: string;
  concurrencyCancel?: boolean;
  sessionId?: string;
}

export interface WorkflowRunWithJobs extends WorkflowRun {
  jobs: WorkflowJob[];
}

// =============================================================================
// Workflow Job
// =============================================================================

export interface WorkflowJob {
  id: number;
  runId: number;
  repositoryId: number;

  name: string;
  jobId: string;

  // Dependencies
  needs: string[];
  runsOn: string[];

  // Status
  status: WorkflowStatus;
  attempt: number;

  // Concurrency
  rawConcurrency?: string;
  concurrencyGroup?: string;
  concurrencyCancel: boolean;

  // Timing
  startedAt?: Date;
  stoppedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface CreateWorkflowJobOptions {
  runId: number;
  repositoryId: number;
  name: string;
  jobId: string;
  needs?: string[];
  runsOn?: string[];
  rawConcurrency?: string;
  concurrencyGroup?: string;
  concurrencyCancel?: boolean;
}

export interface WorkflowJobWithSteps extends WorkflowJob {
  steps: WorkflowStep[];
}

// =============================================================================
// Workflow Task
// =============================================================================

export interface WorkflowTask {
  id: number;
  jobId: number;
  runnerId?: number;

  attempt: number;
  status: WorkflowStatus;

  // Repository context
  repositoryId: number;
  commitSha?: string;

  // Workflow content
  workflowContent?: string;
  workflowPath?: string;

  // Auth
  tokenHash?: string;
  tokenLastEight?: string;

  // Logging
  logFilename?: string;
  logSize: number;

  // Timing
  startedAt?: Date;
  stoppedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface CreateWorkflowTaskOptions {
  jobId: number;
  repositoryId: number;
  attempt?: number;
  commitSha?: string;
  workflowContent?: string;
  workflowPath?: string;
}

export interface TaskWithContext extends WorkflowTask {
  job: WorkflowJob;
  run: WorkflowRun;
  runner?: WorkflowRunner;
}

// =============================================================================
// Workflow Step
// =============================================================================

export interface WorkflowStep {
  id: number;
  taskId: number;

  name: string;
  stepIndex: number;

  status: WorkflowStatus;

  // Logging
  logIndex: number;
  logLength: number;

  // Output
  output?: Record<string, unknown>;

  // Timing
  startedAt?: Date;
  stoppedAt?: Date;
  createdAt: Date;
}

export interface CreateWorkflowStepOptions {
  taskId: number;
  name: string;
  stepIndex: number;
}

export interface UpdateWorkflowStepOptions {
  status?: WorkflowStatus;
  logIndex?: number;
  logLength?: number;
  output?: Record<string, unknown>;
  startedAt?: Date;
  stoppedAt?: Date;
}

// =============================================================================
// Workflow Log
// =============================================================================

export interface WorkflowLog {
  id: number;
  taskId: number;
  stepIndex: number;
  lineNumber: number;
  content: string;
  timestamp: Date;
}

export interface AppendLogOptions {
  taskId: number;
  stepIndex: number;
  lines: string[];
}

// =============================================================================
// Workflow Artifact
// =============================================================================

export interface WorkflowArtifact {
  id: number;
  runId: number;
  taskId?: number;

  name: string;
  fileSize: number;
  filePath: string;
  contentType?: string;

  expiresAt?: Date;
  createdAt: Date;
}

export interface CreateWorkflowArtifactOptions {
  runId: number;
  taskId?: number;
  name: string;
  fileSize: number;
  filePath: string;
  contentType?: string;
  expiresAt?: Date;
}

// =============================================================================
// API Types
// =============================================================================

export interface DispatchWorkflowOptions {
  ref?: string;
  inputs?: Record<string, unknown>;
}

export interface FetchTaskResponse {
  task: TaskWithContext | null;
}

export interface UpdateTaskStatusRequest {
  status: WorkflowStatus;
  steps?: Array<{
    index: number;
    status: WorkflowStatus;
    logIndex?: number;
    logLength?: number;
    output?: Record<string, unknown>;
    startedAt?: string;
    stoppedAt?: string;
  }>;
  stoppedAt?: string;
}

export interface AppendLogsRequest {
  stepIndex: number;
  lines: string[];
}
