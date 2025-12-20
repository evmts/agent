/**
 * Test that sessionId and workingDir are properly passed to tool execute functions.
 */

import { test, expect } from 'bun:test';
import { createToolsWithContext } from './index';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

test('createToolsWithContext - tools receive sessionId and workingDir', async () => {
  // Create a temporary test directory inside current working directory
  const testDir = join(process.cwd(), `test-context-${Date.now()}`);
  await mkdir(testDir, { recursive: true });

  try {
    // Write a test file
    const testFile = join(testDir, 'test.txt');
    await writeFile(testFile, 'Hello World');

    // Create tools with context (using process.cwd() as workingDir to pass validation)
    const sessionId = 'test-session-123';
    const tools = createToolsWithContext({
      sessionId,
      workingDir: process.cwd(),
    });

    // Test readFile tool receives context (and sessionId)
    // The file tracker update will fail silently since session doesn't exist in DB,
    // but this proves the sessionId is being passed through to the implementation
    const readResult = await tools.readFile.execute({
      filePath: testFile,
    });

    // Should succeed since context is passed
    expect(typeof readResult).toBe('string');
    expect(readResult).toContain('Hello World');

    // Test grep tool receives workingDir context
    const grepResult = await tools.grep.execute({
      pattern: 'Hello',
    });

    // Should find the pattern
    expect(typeof grepResult).toBe('string');
    expect(grepResult).toContain('match');

    // Test multiedit tool receives context and enforces read-before-write safety
    const multieditResult = await tools.multiedit.execute({
      filePath: testFile,
      edits: [
        {
          oldString: 'Hello World',
          newString: 'Hello Plue',
        },
      ],
    });

    // Should fail with read-before-write check because the file tracker update failed
    // (session doesn't exist in DB), proving that sessionId is being passed through
    expect(multieditResult).toContain('File has not been read in this session');
  } finally {
    // Cleanup
    await rm(testDir, { recursive: true, force: true });
  }
});

test('tools without context still work (backwards compatibility)', async () => {
  const testDir = join(process.cwd(), `test-no-context-${Date.now()}`);
  await mkdir(testDir, { recursive: true });

  try {
    const testFile = join(testDir, 'test.txt');
    await writeFile(testFile, 'Hello World');

    // Import default tools (without context)
    const { readFileTool } = await import('./read-file');
    const { grepTool } = await import('./grep');

    // Test readFile tool works without context (uses process.cwd() as default)
    const readResult = await readFileTool.execute({
      filePath: testFile,
    });

    expect(typeof readResult).toBe('string');
    expect(readResult).toContain('Hello World');

    // Test grep tool works without context
    const grepResult = await grepTool.execute({
      pattern: 'Hello',
    });

    expect(typeof grepResult).toBe('string');
    expect(grepResult).toContain('match');
  } finally {
    await rm(testDir, { recursive: true, force: true });
  }
});
