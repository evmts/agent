/**
 * Tests for workflow status utilities.
 */

import { describe, test, expect } from 'bun:test';
import {
  WorkflowStatus,
  isDone,
  hasRun,
  isActive,
  canStart,
  getStatusLabel,
  getStatusClass,
  aggregateStatus,
  parseStatus,
  parseStatusString,
} from '../status';

describe('WorkflowStatus enum', () => {
  test('has correct values', () => {
    expect(WorkflowStatus.Unknown).toBe(0);
    expect(WorkflowStatus.Success).toBe(1);
    expect(WorkflowStatus.Failure).toBe(2);
    expect(WorkflowStatus.Cancelled).toBe(3);
    expect(WorkflowStatus.Skipped).toBe(4);
    expect(WorkflowStatus.Waiting).toBe(5);
    expect(WorkflowStatus.Running).toBe(6);
    expect(WorkflowStatus.Blocked).toBe(7);
  });
});

describe('isDone', () => {
  test('returns true for completed states', () => {
    expect(isDone(WorkflowStatus.Success)).toBe(true);
    expect(isDone(WorkflowStatus.Failure)).toBe(true);
    expect(isDone(WorkflowStatus.Cancelled)).toBe(true);
    expect(isDone(WorkflowStatus.Skipped)).toBe(true);
  });

  test('returns false for non-completed states', () => {
    expect(isDone(WorkflowStatus.Unknown)).toBe(false);
    expect(isDone(WorkflowStatus.Waiting)).toBe(false);
    expect(isDone(WorkflowStatus.Running)).toBe(false);
    expect(isDone(WorkflowStatus.Blocked)).toBe(false);
  });
});

describe('hasRun', () => {
  test('returns true for states that executed', () => {
    expect(hasRun(WorkflowStatus.Success)).toBe(true);
    expect(hasRun(WorkflowStatus.Failure)).toBe(true);
  });

  test('returns false for states that did not execute', () => {
    expect(hasRun(WorkflowStatus.Unknown)).toBe(false);
    expect(hasRun(WorkflowStatus.Cancelled)).toBe(false);
    expect(hasRun(WorkflowStatus.Skipped)).toBe(false);
    expect(hasRun(WorkflowStatus.Waiting)).toBe(false);
    expect(hasRun(WorkflowStatus.Running)).toBe(false);
    expect(hasRun(WorkflowStatus.Blocked)).toBe(false);
  });
});

describe('isActive', () => {
  test('returns true for active states', () => {
    expect(isActive(WorkflowStatus.Running)).toBe(true);
    expect(isActive(WorkflowStatus.Waiting)).toBe(true);
    expect(isActive(WorkflowStatus.Blocked)).toBe(true);
  });

  test('returns false for inactive states', () => {
    expect(isActive(WorkflowStatus.Unknown)).toBe(false);
    expect(isActive(WorkflowStatus.Success)).toBe(false);
    expect(isActive(WorkflowStatus.Failure)).toBe(false);
    expect(isActive(WorkflowStatus.Cancelled)).toBe(false);
    expect(isActive(WorkflowStatus.Skipped)).toBe(false);
  });
});

describe('canStart', () => {
  test('returns true for startable states', () => {
    expect(canStart(WorkflowStatus.Waiting)).toBe(true);
    expect(canStart(WorkflowStatus.Blocked)).toBe(true);
  });

  test('returns false for non-startable states', () => {
    expect(canStart(WorkflowStatus.Unknown)).toBe(false);
    expect(canStart(WorkflowStatus.Success)).toBe(false);
    expect(canStart(WorkflowStatus.Failure)).toBe(false);
    expect(canStart(WorkflowStatus.Cancelled)).toBe(false);
    expect(canStart(WorkflowStatus.Skipped)).toBe(false);
    expect(canStart(WorkflowStatus.Running)).toBe(false);
  });
});

describe('getStatusLabel', () => {
  test('returns correct labels', () => {
    expect(getStatusLabel(WorkflowStatus.Unknown)).toBe('Unknown');
    expect(getStatusLabel(WorkflowStatus.Success)).toBe('Success');
    expect(getStatusLabel(WorkflowStatus.Failure)).toBe('Failure');
    expect(getStatusLabel(WorkflowStatus.Cancelled)).toBe('Cancelled');
    expect(getStatusLabel(WorkflowStatus.Skipped)).toBe('Skipped');
    expect(getStatusLabel(WorkflowStatus.Waiting)).toBe('Waiting');
    expect(getStatusLabel(WorkflowStatus.Running)).toBe('Running');
    expect(getStatusLabel(WorkflowStatus.Blocked)).toBe('Blocked');
  });

  test('returns Unknown for invalid values', () => {
    expect(getStatusLabel(99 as WorkflowStatus)).toBe('Unknown');
  });
});

describe('getStatusClass', () => {
  test('returns correct CSS classes', () => {
    expect(getStatusClass(WorkflowStatus.Success)).toBe('status-success');
    expect(getStatusClass(WorkflowStatus.Failure)).toBe('status-failure');
    expect(getStatusClass(WorkflowStatus.Running)).toBe('status-running');
  });
});

describe('aggregateStatus', () => {
  test('returns Unknown for empty array', () => {
    expect(aggregateStatus([])).toBe(WorkflowStatus.Unknown);
  });

  test('returns Running if any is Running', () => {
    expect(
      aggregateStatus([
        WorkflowStatus.Success,
        WorkflowStatus.Running,
        WorkflowStatus.Waiting,
      ])
    ).toBe(WorkflowStatus.Running);
  });

  test('returns Blocked if any is Blocked (and none Running)', () => {
    expect(
      aggregateStatus([
        WorkflowStatus.Success,
        WorkflowStatus.Blocked,
        WorkflowStatus.Waiting,
      ])
    ).toBe(WorkflowStatus.Blocked);
  });

  test('returns Waiting if any is Waiting (and none Running/Blocked)', () => {
    expect(
      aggregateStatus([WorkflowStatus.Success, WorkflowStatus.Waiting])
    ).toBe(WorkflowStatus.Waiting);
  });

  test('returns Failure if any is Failure (and all done)', () => {
    expect(
      aggregateStatus([WorkflowStatus.Success, WorkflowStatus.Failure])
    ).toBe(WorkflowStatus.Failure);
  });

  test('returns Cancelled if any is Cancelled (and no Failure)', () => {
    expect(
      aggregateStatus([WorkflowStatus.Success, WorkflowStatus.Cancelled])
    ).toBe(WorkflowStatus.Cancelled);
  });

  test('returns Skipped if all are Skipped', () => {
    expect(
      aggregateStatus([WorkflowStatus.Skipped, WorkflowStatus.Skipped])
    ).toBe(WorkflowStatus.Skipped);
  });

  test('returns Success if all are Success or Skipped', () => {
    expect(
      aggregateStatus([WorkflowStatus.Success, WorkflowStatus.Skipped])
    ).toBe(WorkflowStatus.Success);
    expect(
      aggregateStatus([WorkflowStatus.Success, WorkflowStatus.Success])
    ).toBe(WorkflowStatus.Success);
  });
});

describe('parseStatus', () => {
  test('parses valid values', () => {
    expect(parseStatus(0)).toBe(WorkflowStatus.Unknown);
    expect(parseStatus(1)).toBe(WorkflowStatus.Success);
    expect(parseStatus(6)).toBe(WorkflowStatus.Running);
  });

  test('returns Unknown for invalid values', () => {
    expect(parseStatus(-1)).toBe(WorkflowStatus.Unknown);
    expect(parseStatus(99)).toBe(WorkflowStatus.Unknown);
  });
});

describe('parseStatusString', () => {
  test('parses common status strings', () => {
    expect(parseStatusString('success')).toBe(WorkflowStatus.Success);
    expect(parseStatusString('SUCCESS')).toBe(WorkflowStatus.Success);
    expect(parseStatusString('failure')).toBe(WorkflowStatus.Failure);
    expect(parseStatusString('failed')).toBe(WorkflowStatus.Failure);
    expect(parseStatusString('cancelled')).toBe(WorkflowStatus.Cancelled);
    expect(parseStatusString('canceled')).toBe(WorkflowStatus.Cancelled);
    expect(parseStatusString('running')).toBe(WorkflowStatus.Running);
    expect(parseStatusString('in_progress')).toBe(WorkflowStatus.Running);
    expect(parseStatusString('waiting')).toBe(WorkflowStatus.Waiting);
    expect(parseStatusString('queued')).toBe(WorkflowStatus.Waiting);
    expect(parseStatusString('pending')).toBe(WorkflowStatus.Waiting);
  });

  test('returns Unknown for unrecognized strings', () => {
    expect(parseStatusString('invalid')).toBe(WorkflowStatus.Unknown);
    expect(parseStatusString('')).toBe(WorkflowStatus.Unknown);
  });
});
