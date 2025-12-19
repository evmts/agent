/**
 * Tests for tool call tracker and duplicate detection.
 */

import { test, expect } from 'bun:test';
import { ToolCallTracker } from './tracker';

test('ToolCallTracker: basic duplicate detection for readFile', () => {
  const tracker = new ToolCallTracker();
  const sessionId = 'test-session-1';

  // First call - not a duplicate
  const check1 = tracker.checkDuplicate(sessionId, 'readFile', {
    filePath: '/test/file.ts',
  });
  expect(check1.isDuplicate).toBe(false);

  // Record the call
  tracker.recordCall(
    sessionId,
    'readFile',
    { filePath: '/test/file.ts' },
    'file contents here'
  );

  // Second call with same path - should be duplicate
  const check2 = tracker.checkDuplicate(sessionId, 'readFile', {
    filePath: '/test/file.ts',
  });
  expect(check2.isDuplicate).toBe(true);
  expect(check2.previousResult).toBe('file contents here');

  // Different file - not a duplicate
  const check3 = tracker.checkDuplicate(sessionId, 'readFile', {
    filePath: '/test/other.ts',
  });
  expect(check3.isDuplicate).toBe(false);
});

test('ToolCallTracker: different sessions have separate histories', () => {
  const tracker = new ToolCallTracker();
  const session1 = 'session-1';
  const session2 = 'session-2';

  // Record call in session 1
  tracker.recordCall(
    session1,
    'readFile',
    { filePath: '/test/file.ts' },
    'session 1 content'
  );

  // Check in session 2 - should not be duplicate
  const check = tracker.checkDuplicate(session2, 'readFile', {
    filePath: '/test/file.ts',
  });
  expect(check.isDuplicate).toBe(false);

  // Record same call in session 2
  tracker.recordCall(
    session2,
    'readFile',
    { filePath: '/test/file.ts' },
    'session 2 content'
  );

  // Now check in session 2 again - should be duplicate with session 2 result
  const check2 = tracker.checkDuplicate(session2, 'readFile', {
    filePath: '/test/file.ts',
  });
  expect(check2.isDuplicate).toBe(true);
  expect(check2.previousResult).toBe('session 2 content');
});

test('ToolCallTracker: grep duplicate detection', () => {
  const tracker = new ToolCallTracker();
  const sessionId = 'test-session';

  // Record grep call
  tracker.recordCall(
    sessionId,
    'grep',
    {
      pattern: 'function',
      path: '/src',
      glob: '*.ts',
      multiline: false,
      caseInsensitive: true,
    },
    'grep results'
  );

  // Same grep - should be duplicate
  const check1 = tracker.checkDuplicate(sessionId, 'grep', {
    pattern: 'function',
    path: '/src',
    glob: '*.ts',
    multiline: false,
    caseInsensitive: true,
  });
  expect(check1.isDuplicate).toBe(true);

  // Different pattern - not duplicate
  const check2 = tracker.checkDuplicate(sessionId, 'grep', {
    pattern: 'class',
    path: '/src',
    glob: '*.ts',
    multiline: false,
    caseInsensitive: true,
  });
  expect(check2.isDuplicate).toBe(false);

  // Different path - not duplicate
  const check3 = tracker.checkDuplicate(sessionId, 'grep', {
    pattern: 'function',
    path: '/lib',
    glob: '*.ts',
    multiline: false,
    caseInsensitive: true,
  });
  expect(check3.isDuplicate).toBe(false);
});

test('ToolCallTracker: writeFile duplicate detection', () => {
  const tracker = new ToolCallTracker();
  const sessionId = 'test-session';

  // Record write
  tracker.recordCall(
    sessionId,
    'writeFile',
    { filePath: '/test/output.ts', content: 'hello world' },
    'success'
  );

  // Same path and content - duplicate
  const check1 = tracker.checkDuplicate(sessionId, 'writeFile', {
    filePath: '/test/output.ts',
    content: 'hello world',
  });
  expect(check1.isDuplicate).toBe(true);

  // Same path but different content - not duplicate
  const check2 = tracker.checkDuplicate(sessionId, 'writeFile', {
    filePath: '/test/output.ts',
    content: 'different content',
  });
  expect(check2.isDuplicate).toBe(false);
});

test('ToolCallTracker: exec tools never duplicate', () => {
  const tracker = new ToolCallTracker();
  const sessionId = 'test-session';

  // Record exec call
  tracker.recordCall(
    sessionId,
    'unifiedExec',
    { command: 'ls -la' },
    'file1\nfile2'
  );

  // Same command - should NOT be duplicate (exec has side effects)
  const check = tracker.checkDuplicate(sessionId, 'unifiedExec', {
    command: 'ls -la',
  });
  expect(check.isDuplicate).toBe(false);
});

test('ToolCallTracker: webFetch duplicate detection', () => {
  const tracker = new ToolCallTracker();
  const sessionId = 'test-session';

  // Record fetch
  tracker.recordCall(
    sessionId,
    'webFetch',
    { url: 'https://example.com' },
    '<html>content</html>'
  );

  // Same URL - duplicate
  const check1 = tracker.checkDuplicate(sessionId, 'webFetch', {
    url: 'https://example.com',
  });
  expect(check1.isDuplicate).toBe(true);

  // Different URL - not duplicate
  const check2 = tracker.checkDuplicate(sessionId, 'webFetch', {
    url: 'https://other.com',
  });
  expect(check2.isDuplicate).toBe(false);
});

test('ToolCallTracker: history size limit', () => {
  const tracker = new ToolCallTracker(5); // Max 5 items
  const sessionId = 'test-session';

  // Add 6 calls
  for (let i = 0; i < 6; i++) {
    tracker.recordCall(
      sessionId,
      'readFile',
      { filePath: `/test/file${i}.ts` },
      `content ${i}`
    );
  }

  // Check that history is limited
  const stats = tracker.getStats();
  expect(stats.totalCalls).toBeLessThanOrEqual(5);
});

test('ToolCallTracker: clearSession', () => {
  const tracker = new ToolCallTracker();
  const sessionId = 'test-session';

  // Record call
  tracker.recordCall(
    sessionId,
    'readFile',
    { filePath: '/test/file.ts' },
    'content'
  );

  // Verify it's in history
  let check = tracker.checkDuplicate(sessionId, 'readFile', {
    filePath: '/test/file.ts',
  });
  expect(check.isDuplicate).toBe(true);

  // Clear session
  tracker.clearSession(sessionId);

  // Check again - should not be duplicate anymore
  check = tracker.checkDuplicate(sessionId, 'readFile', {
    filePath: '/test/file.ts',
  });
  expect(check.isDuplicate).toBe(false);
});

test('ToolCallTracker: age-based expiration', async () => {
  const tracker = new ToolCallTracker(50, 100); // 100ms max age
  const sessionId = 'test-session';

  // Record call
  tracker.recordCall(
    sessionId,
    'readFile',
    { filePath: '/test/file.ts' },
    'content'
  );

  // Check immediately - should be duplicate
  let check = tracker.checkDuplicate(sessionId, 'readFile', {
    filePath: '/test/file.ts',
  });
  expect(check.isDuplicate).toBe(true);

  // Wait for expiration
  await new Promise((resolve) => setTimeout(resolve, 150));

  // Check again - should be expired
  check = tracker.checkDuplicate(sessionId, 'readFile', {
    filePath: '/test/file.ts',
  });
  expect(check.isDuplicate).toBe(false);
});

test('ToolCallTracker: getStats', () => {
  const tracker = new ToolCallTracker();
  const session1 = 'session-1';
  const session2 = 'session-2';

  // Add some calls
  tracker.recordCall(session1, 'readFile', { filePath: '/a.ts' }, 'content a');
  tracker.recordCall(session1, 'grep', { pattern: 'test' }, 'matches');
  tracker.recordCall(session2, 'readFile', { filePath: '/b.ts' }, 'content b');

  const stats = tracker.getStats();
  expect(stats.totalSessions).toBe(2);
  expect(stats.totalCalls).toBe(3);
  expect(stats.callsByTool.readFile).toBe(2);
  expect(stats.callsByTool.grep).toBe(1);
});
