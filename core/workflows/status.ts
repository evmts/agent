/**
 * Workflow status enum and state machine.
 *
 * Based on Gitea's proven model for workflow status management.
 * Status values match database INTEGER values for direct storage.
 */

export enum WorkflowStatus {
  Unknown = 0,
  Success = 1,
  Failure = 2,
  Cancelled = 3,
  Skipped = 4,
  Waiting = 5,
  Running = 6,
  Blocked = 7,
}

/**
 * Check if status represents a completed/final state.
 */
export function isDone(status: WorkflowStatus): boolean {
  return (
    status === WorkflowStatus.Success ||
    status === WorkflowStatus.Failure ||
    status === WorkflowStatus.Cancelled ||
    status === WorkflowStatus.Skipped
  );
}

/**
 * Check if status represents a state where execution actually ran.
 */
export function hasRun(status: WorkflowStatus): boolean {
  return (
    status === WorkflowStatus.Success || status === WorkflowStatus.Failure
  );
}

/**
 * Check if status represents an active/in-progress state.
 */
export function isActive(status: WorkflowStatus): boolean {
  return (
    status === WorkflowStatus.Running ||
    status === WorkflowStatus.Waiting ||
    status === WorkflowStatus.Blocked
  );
}

/**
 * Check if status can transition to Running.
 */
export function canStart(status: WorkflowStatus): boolean {
  return status === WorkflowStatus.Waiting || status === WorkflowStatus.Blocked;
}

/**
 * Get human-readable status label.
 */
export function getStatusLabel(status: WorkflowStatus): string {
  switch (status) {
    case WorkflowStatus.Unknown:
      return 'Unknown';
    case WorkflowStatus.Success:
      return 'Success';
    case WorkflowStatus.Failure:
      return 'Failure';
    case WorkflowStatus.Cancelled:
      return 'Cancelled';
    case WorkflowStatus.Skipped:
      return 'Skipped';
    case WorkflowStatus.Waiting:
      return 'Waiting';
    case WorkflowStatus.Running:
      return 'Running';
    case WorkflowStatus.Blocked:
      return 'Blocked';
    default:
      return 'Unknown';
  }
}

/**
 * Get CSS class for status badge styling.
 */
export function getStatusClass(status: WorkflowStatus): string {
  switch (status) {
    case WorkflowStatus.Success:
      return 'status-success';
    case WorkflowStatus.Failure:
      return 'status-failure';
    case WorkflowStatus.Cancelled:
      return 'status-cancelled';
    case WorkflowStatus.Skipped:
      return 'status-skipped';
    case WorkflowStatus.Waiting:
      return 'status-waiting';
    case WorkflowStatus.Running:
      return 'status-running';
    case WorkflowStatus.Blocked:
      return 'status-blocked';
    default:
      return 'status-unknown';
  }
}

/**
 * Aggregate status from multiple child statuses (e.g., steps -> job, jobs -> run).
 *
 * Priority order:
 * 1. If any child is Running, parent is Running
 * 2. If any child is Blocked, parent is Blocked
 * 3. If any child is Waiting, parent is Waiting
 * 4. If any child is Failure, parent is Failure
 * 5. If any child is Cancelled, parent is Cancelled
 * 6. If all children are Skipped, parent is Skipped
 * 7. If all children are Success, parent is Success
 * 8. Otherwise Unknown
 */
export function aggregateStatus(statuses: WorkflowStatus[]): WorkflowStatus {
  if (statuses.length === 0) {
    return WorkflowStatus.Unknown;
  }

  // Check for active states first
  if (statuses.some((s) => s === WorkflowStatus.Running)) {
    return WorkflowStatus.Running;
  }

  if (statuses.some((s) => s === WorkflowStatus.Blocked)) {
    return WorkflowStatus.Blocked;
  }

  if (statuses.some((s) => s === WorkflowStatus.Waiting)) {
    return WorkflowStatus.Waiting;
  }

  // All statuses should be done at this point
  if (statuses.some((s) => s === WorkflowStatus.Failure)) {
    return WorkflowStatus.Failure;
  }

  if (statuses.some((s) => s === WorkflowStatus.Cancelled)) {
    return WorkflowStatus.Cancelled;
  }

  // Check if all are skipped
  if (statuses.every((s) => s === WorkflowStatus.Skipped)) {
    return WorkflowStatus.Skipped;
  }

  // Check if all are success or skipped
  if (
    statuses.every(
      (s) => s === WorkflowStatus.Success || s === WorkflowStatus.Skipped
    )
  ) {
    return WorkflowStatus.Success;
  }

  return WorkflowStatus.Unknown;
}

/**
 * Parse status from database integer value.
 */
export function parseStatus(value: number): WorkflowStatus {
  if (value >= 0 && value <= 7) {
    return value as WorkflowStatus;
  }
  return WorkflowStatus.Unknown;
}

/**
 * Parse status from string (e.g., from API request).
 */
export function parseStatusString(value: string): WorkflowStatus {
  const normalized = value.toLowerCase();
  switch (normalized) {
    case 'success':
      return WorkflowStatus.Success;
    case 'failure':
    case 'failed':
      return WorkflowStatus.Failure;
    case 'cancelled':
    case 'canceled':
      return WorkflowStatus.Cancelled;
    case 'skipped':
      return WorkflowStatus.Skipped;
    case 'waiting':
    case 'queued':
    case 'pending':
      return WorkflowStatus.Waiting;
    case 'running':
    case 'in_progress':
      return WorkflowStatus.Running;
    case 'blocked':
      return WorkflowStatus.Blocked;
    default:
      return WorkflowStatus.Unknown;
  }
}
