/**
 * Integration tests for agent duplicate detection.
 */

import { test, expect } from 'bun:test';
import { getToolCallTracker, setToolCallTracker, ToolCallTracker } from './tools';

test('Agent: duplicate detection can be enabled/disabled', () => {
  // Test that we can get and set the tracker
  const originalTracker = getToolCallTracker();
  expect(originalTracker).toBeDefined();

  const customTracker = new ToolCallTracker(10, 60000);
  setToolCallTracker(customTracker);
  expect(getToolCallTracker()).toBe(customTracker);

  // Restore original
  setToolCallTracker(originalTracker);
});

test('Agent: tracker maintains separate session histories', () => {
  const tracker = new ToolCallTracker();

  // Session 1: read file A
  tracker.recordCall('session-1', 'readFile', { filePath: '/a.ts' }, 'content a');

  // Session 2: read file B
  tracker.recordCall('session-2', 'readFile', { filePath: '/b.ts' }, 'content b');

  // Session 1 should only see file A as duplicate
  const check1 = tracker.checkDuplicate('session-1', 'readFile', { filePath: '/a.ts' });
  expect(check1.isDuplicate).toBe(true);

  const check2 = tracker.checkDuplicate('session-1', 'readFile', { filePath: '/b.ts' });
  expect(check2.isDuplicate).toBe(false);

  // Session 2 should only see file B as duplicate
  const check3 = tracker.checkDuplicate('session-2', 'readFile', { filePath: '/b.ts' });
  expect(check3.isDuplicate).toBe(true);

  const check4 = tracker.checkDuplicate('session-2', 'readFile', { filePath: '/a.ts' });
  expect(check4.isDuplicate).toBe(false);
});

test('Agent: tracker handles multiple duplicate checks', () => {
  const tracker = new ToolCallTracker();
  const sessionId = 'test-session';

  // Simulate reading the same file 3 times
  tracker.recordCall(sessionId, 'readFile', { filePath: '/test.ts' }, 'original content');

  // First duplicate check
  const check1 = tracker.checkDuplicate(sessionId, 'readFile', { filePath: '/test.ts' });
  expect(check1.isDuplicate).toBe(true);
  expect(check1.previousResult).toBe('original content');

  // Second duplicate check (should still work)
  const check2 = tracker.checkDuplicate(sessionId, 'readFile', { filePath: '/test.ts' });
  expect(check2.isDuplicate).toBe(true);
  expect(check2.previousResult).toBe('original content');
});

test('Agent: tracker handles complex grep patterns', () => {
  const tracker = new ToolCallTracker();
  const sessionId = 'test-session';

  const grepArgs1 = {
    pattern: 'export.*function',
    path: '/src',
    glob: '*.{ts,tsx}',
    multiline: true,
    caseInsensitive: false,
  };

  tracker.recordCall(sessionId, 'grep', grepArgs1, 'grep results');

  // Exact same grep - duplicate
  const check1 = tracker.checkDuplicate(sessionId, 'grep', grepArgs1);
  expect(check1.isDuplicate).toBe(true);

  // Different pattern - not duplicate
  const grepArgs2 = {
    ...grepArgs1,
    pattern: 'import.*from',
  };
  const check2 = tracker.checkDuplicate(sessionId, 'grep', grepArgs2);
  expect(check2.isDuplicate).toBe(false);

  // Different multiline flag - not duplicate
  const grepArgs3 = {
    ...grepArgs1,
    multiline: false,
  };
  const check3 = tracker.checkDuplicate(sessionId, 'grep', grepArgs3);
  expect(check3.isDuplicate).toBe(false);
});

test('Agent: tracker handles edge cases', () => {
  const tracker = new ToolCallTracker();
  const sessionId = 'test-session';

  // Empty args
  tracker.recordCall(sessionId, 'listPtySessions', {}, '[]');

  // Should never be duplicate for listPtySessions (stateful)
  const check1 = tracker.checkDuplicate(sessionId, 'listPtySessions', {});
  expect(check1.isDuplicate).toBe(false);

  // Check with non-existent session
  const check2 = tracker.checkDuplicate('non-existent', 'readFile', { filePath: '/test.ts' });
  expect(check2.isDuplicate).toBe(false);
});

test('Agent: tracker clearAll works', () => {
  const tracker = new ToolCallTracker();

  tracker.recordCall('session-1', 'readFile', { filePath: '/a.ts' }, 'content a');
  tracker.recordCall('session-2', 'readFile', { filePath: '/b.ts' }, 'content b');

  let stats = tracker.getStats();
  expect(stats.totalSessions).toBe(2);
  expect(stats.totalCalls).toBe(2);

  tracker.clearAll();

  stats = tracker.getStats();
  expect(stats.totalSessions).toBe(0);
  expect(stats.totalCalls).toBe(0);
});
