/**
 * Integration test for duplicate detection with actual tool execution.
 *
 * This test simulates real tool calls with duplicate detection enabled.
 */

import { test, expect } from 'bun:test';
import { readFileImpl } from './read-file';
import { grepImpl } from './grep';
import { webFetchImpl } from './web-fetch';
import { getToolCallTracker } from './tracker';

test('Integration: readFile with duplicate detection', async () => {
  const tracker = getToolCallTracker();
  const sessionId = 'integration-test-1';

  // Clear any existing state
  tracker.clearSession(sessionId);

  // First read - not a duplicate
  const testFilePath = `${process.cwd()}/package.json`;
  const check1 = tracker.checkDuplicate(sessionId, 'readFile', {
    filePath: testFilePath,
  });
  expect(check1.isDuplicate).toBe(false);

  // Execute the actual read
  const result1 = await readFileImpl(testFilePath);
  expect(result1.success).toBe(true);

  // Record the call
  tracker.recordCall(
    sessionId,
    'readFile',
    { filePath: testFilePath },
    result1.content ?? ''
  );

  // Second read - should be duplicate
  const check2 = tracker.checkDuplicate(sessionId, 'readFile', {
    filePath: testFilePath,
  });
  expect(check2.isDuplicate).toBe(true);
  expect(check2.previousResult).toBe(result1.content);

  // Cleanup
  tracker.clearSession(sessionId);
});

test('Integration: grep with duplicate detection', async () => {
  const tracker = getToolCallTracker();
  const sessionId = 'integration-test-2';

  tracker.clearSession(sessionId);

  const grepArgs = {
    pattern: 'export',
    path: `${process.cwd()}/ai/tools`,
    glob: '*.ts',
  };

  // First grep - not a duplicate
  const check1 = tracker.checkDuplicate(sessionId, 'grep', grepArgs);
  expect(check1.isDuplicate).toBe(false);

  // Execute the actual grep
  const result1 = await grepImpl(
    grepArgs.pattern,
    grepArgs.path,
    grepArgs.glob
  );
  expect(result1.success).toBe(true);

  // Record the call
  tracker.recordCall(
    sessionId,
    'grep',
    grepArgs,
    result1.formattedOutput ?? ''
  );

  // Second grep with same args - should be duplicate
  const check2 = tracker.checkDuplicate(sessionId, 'grep', grepArgs);
  expect(check2.isDuplicate).toBe(true);
  expect(check2.previousResult).toBe(result1.formattedOutput);

  // Different pattern - not a duplicate
  const grepArgs2 = { ...grepArgs, pattern: 'import' };
  const check3 = tracker.checkDuplicate(sessionId, 'grep', grepArgs2);
  expect(check3.isDuplicate).toBe(false);

  // Cleanup
  tracker.clearSession(sessionId);
});

test('Integration: webFetch with duplicate detection', async () => {
  const tracker = getToolCallTracker();
  const sessionId = 'integration-test-3';

  tracker.clearSession(sessionId);

  // Note: This test uses a real URL - might fail if offline
  const url = 'https://example.com';

  // First fetch - not a duplicate
  const check1 = tracker.checkDuplicate(sessionId, 'webFetch', { url });
  expect(check1.isDuplicate).toBe(false);

  // Execute the actual fetch
  const result1 = await webFetchImpl(url);

  // Only continue if fetch succeeded (network might be unavailable)
  if (result1.success) {
    // Record the call
    tracker.recordCall(
      sessionId,
      'webFetch',
      { url },
      result1.content ?? ''
    );

    // Second fetch - should be duplicate
    const check2 = tracker.checkDuplicate(sessionId, 'webFetch', { url });
    expect(check2.isDuplicate).toBe(true);
    expect(check2.previousResult).toBe(result1.content);

    // Different URL - not a duplicate
    const check3 = tracker.checkDuplicate(sessionId, 'webFetch', {
      url: 'https://example.org',
    });
    expect(check3.isDuplicate).toBe(false);
  }

  // Cleanup
  tracker.clearSession(sessionId);
});

test('Integration: multiple tools across session', async () => {
  const tracker = getToolCallTracker();
  const sessionId = 'integration-test-4';

  tracker.clearSession(sessionId);

  // Read a file
  const testFilePath = `${process.cwd()}/package.json`;
  const readResult = await readFileImpl(testFilePath);
  expect(readResult.success).toBe(true);
  tracker.recordCall(
    sessionId,
    'readFile',
    { filePath: testFilePath },
    readResult.content ?? ''
  );

  // Run a grep
  const grepPath = `${process.cwd()}/ai/tools`;
  const grepResult = await grepImpl('test', grepPath, '*.ts');
  expect(grepResult.success).toBe(true);
  tracker.recordCall(
    sessionId,
    'grep',
    { pattern: 'test', path: grepPath, glob: '*.ts' },
    grepResult.formattedOutput ?? ''
  );

  // Verify both are tracked
  const stats = tracker.getStats();
  expect(stats.callsByTool.readFile).toBeGreaterThan(0);
  expect(stats.callsByTool.grep).toBeGreaterThan(0);

  // Verify duplicates work correctly
  const readCheck = tracker.checkDuplicate(sessionId, 'readFile', {
    filePath: testFilePath,
  });
  expect(readCheck.isDuplicate).toBe(true);

  const grepCheck = tracker.checkDuplicate(sessionId, 'grep', {
    pattern: 'test',
    path: grepPath,
    glob: '*.ts',
  });
  expect(grepCheck.isDuplicate).toBe(true);

  // Cleanup
  tracker.clearSession(sessionId);
});
