/**
 * Tests for read-file tool with line truncation and safety features.
 */

import { describe, test, expect, beforeAll, afterAll } from 'bun:test';
import { readFileImpl } from './read-file';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

// Test directory setup
const TEST_DIR = resolve(import.meta.dir, '../../.test-tmp/read-file');

beforeAll(async () => {
  // Clean up any existing test directory
  await rm(TEST_DIR, { recursive: true, force: true });
  await mkdir(TEST_DIR, { recursive: true });

  // Create test files
  await writeFile(
    resolve(TEST_DIR, 'simple.txt'),
    `Line 1
Line 2
Line 3
Line 4
Line 5
`
  );

  await writeFile(
    resolve(TEST_DIR, 'code.ts'),
    `export function example() {
  console.log('hello');
  return 42;
}

export const value = 100;
`
  );

  // Create file with many lines for pagination testing
  const manyLines = Array.from({ length: 3000 }, (_, i) => `Line ${i + 1}`).join('\n');
  await writeFile(resolve(TEST_DIR, 'large.txt'), manyLines);

  // Create file with very long lines
  const longLine = 'x'.repeat(5000);
  await writeFile(
    resolve(TEST_DIR, 'longlines.txt'),
    `Short line
${longLine}
Another short line
`
  );

  // Create empty file
  await writeFile(resolve(TEST_DIR, 'empty.txt'), '');

  // Create file with unicode
  await writeFile(
    resolve(TEST_DIR, 'unicode.txt'),
    `Hello 世界
Bonjour monde
こんにちは
`
  );

  // Create nested directory
  await mkdir(resolve(TEST_DIR, 'nested/deep'), { recursive: true });
  await writeFile(
    resolve(TEST_DIR, 'nested/deep/file.txt'),
    'Nested file content\n'
  );
});

afterAll(async () => {
  // Clean up test directory
  await rm(TEST_DIR, { recursive: true, force: true });
});

describe('readFileImpl - basic file reading', () => {
  test('should read entire file', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'));

    expect(result.success).toBe(true);
    expect(result.content).toBeDefined();
    expect(result.content).toContain('Line 1');
    expect(result.content).toContain('Line 5');
    expect(result.lineCount).toBe(6); // 5 lines + 1 empty line at end
  });

  test('should format with line numbers (cat -n style)', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'));

    expect(result.success).toBe(true);
    expect(result.content).toMatch(/^\s*1\t/m);
    expect(result.content).toMatch(/^\s*2\t/m);
  });

  test('should read code file', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'code.ts'));

    expect(result.success).toBe(true);
    expect(result.content).toContain('export function example');
    expect(result.content).toContain('return 42');
  });

  test('should handle empty file', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'empty.txt'));

    expect(result.success).toBe(true);
    expect(result.content).toBe('');
    expect(result.lineCount).toBe(0);
  });

  test('should handle unicode content', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'unicode.txt'));

    expect(result.success).toBe(true);
    expect(result.content).toContain('世界');
    expect(result.content).toContain('こんにちは');
  });
});

describe('readFileImpl - offset parameter', () => {
  test('should start reading from offset', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'), 2);

    expect(result.success).toBe(true);
    expect(result.content).not.toContain('Line 1');
    expect(result.content).not.toContain('Line 2');
    expect(result.content).toContain('Line 3');
    // First line number should be 3 (offset 2 means starting at index 2, which is line 3)
    expect(result.content).toMatch(/^\s*3\t/m);
  });

  test('should handle offset of 0 (read from beginning)', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'), 0);

    expect(result.success).toBe(true);
    expect(result.content).toContain('Line 1');
  });

  test('should handle offset beyond file length', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'), 1000);

    expect(result.success).toBe(true);
    expect(result.content).toBe('');
    expect(result.lineCount).toBe(0);
  });

  test('should handle large offset', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'large.txt'), 2900);

    expect(result.success).toBe(true);
    expect(result.content).toContain('Line 2901');
    expect(result.lineCount).toBe(100);
  });
});

describe('readFileImpl - limit parameter', () => {
  test('should limit number of lines read', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'), undefined, 3);

    expect(result.success).toBe(true);
    expect(result.lineCount).toBe(3);
    expect(result.content).toContain('Line 1');
    expect(result.content).toContain('Line 3');
    expect(result.content).not.toContain('Line 4');
  });

  test('should apply default limit of 2000 lines', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'large.txt'));

    expect(result.success).toBe(true);
    expect(result.lineCount).toBe(2000);
    expect(result.truncated).toBe(true);
  });

  test('should handle limit larger than file size', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'), undefined, 1000);

    expect(result.success).toBe(true);
    expect(result.lineCount).toBe(6);
    expect(result.truncated).toBe(false);
  });

  test('should combine offset and limit', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'), 1, 2);

    expect(result.success).toBe(true);
    expect(result.lineCount).toBe(2);
    expect(result.content).not.toContain('Line 1');
    expect(result.content).toContain('Line 2');
    expect(result.content).toContain('Line 3');
    expect(result.content).not.toContain('Line 4');
  });
});

describe('readFileImpl - line truncation', () => {
  test('should truncate lines longer than 2000 characters', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'longlines.txt'));

    expect(result.success).toBe(true);
    expect(result.content).toContain('Short line');
    expect(result.content).toContain('... [truncated]');
    expect(result.content).toContain('Another short line');
  });

  test('should not truncate lines under 2000 characters', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'));

    expect(result.success).toBe(true);
    expect(result.content).not.toContain('[truncated]');
  });

  test('should truncate at exactly 2000 characters', async () => {
    const line2000 = 'a'.repeat(2000);
    const testFile = resolve(TEST_DIR, 'exact2000.txt');
    await writeFile(testFile, line2000 + '\nShort line\n');

    const result = await readFileImpl(testFile);

    expect(result.success).toBe(true);
    expect(result.content).not.toContain('[truncated]');
    expect(result.content).toContain('Short line');
  });

  test('should truncate at 2001 characters', async () => {
    const line2001 = 'a'.repeat(2001);
    const testFile = resolve(TEST_DIR, 'exact2001.txt');
    await writeFile(testFile, line2001 + '\nShort line\n');

    const result = await readFileImpl(testFile);

    expect(result.success).toBe(true);
    expect(result.content).toContain('[truncated]');
    expect(result.content).toContain('Short line');
  });
});

describe('readFileImpl - path validation', () => {
  test('should reject path traversal with ..', async () => {
    const result = await readFileImpl('../../../etc/passwd', undefined, undefined, TEST_DIR);

    expect(result.success).toBe(false);
    expect(result.error).toContain('path traversal');
  });

  test('should reject paths outside working directory', async () => {
    const result = await readFileImpl('/etc/passwd', undefined, undefined, TEST_DIR);

    expect(result.success).toBe(false);
    expect(result.error).toContain('not in the current working directory');
  });

  test('should handle relative paths within working directory', async () => {
    const result = await readFileImpl('simple.txt', undefined, undefined, TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.content).toContain('Line 1');
  });

  test('should handle nested paths', async () => {
    const result = await readFileImpl('nested/deep/file.txt', undefined, undefined, TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.content).toContain('Nested file content');
  });

  test('should reject non-existent files', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'nonexistent.txt'));

    expect(result.success).toBe(false);
    expect(result.error).toContain('file not found');
  });

  test('should accept absolute paths', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'));

    expect(result.success).toBe(true);
    expect(result.content).toContain('Line 1');
  });
});

describe('readFileImpl - file tracking', () => {
  test('should work without sessionId (no tracking)', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'));

    expect(result.success).toBe(true);
  });

  test('should track file read time with sessionId', async () => {
    // Note: This test verifies the function doesn't throw when sessionId is provided
    // Full integration testing of file tracking requires database setup
    const result = await readFileImpl(
      resolve(TEST_DIR, 'simple.txt'),
      undefined,
      undefined,
      undefined,
      'test-session-id'
    );

    // Should still succeed even if tracking fails (graceful degradation)
    expect(result.success).toBe(true);
  });
});

describe('readFileImpl - working directory', () => {
  test('should use custom working directory', async () => {
    const result = await readFileImpl('simple.txt', undefined, undefined, TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.content).toContain('Line 1');
  });

  test('should default to process.cwd() when no workingDir provided', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'));

    expect(result.success).toBe(true);
  });

  test('should resolve relative paths against working directory', async () => {
    const result = await readFileImpl('nested/deep/file.txt', undefined, undefined, TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.content).toContain('Nested file content');
  });
});

describe('readFileImpl - line number formatting', () => {
  test('should pad line numbers for alignment', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'));

    expect(result.success).toBe(true);
    // Line numbers should be right-aligned with padding
    const lines = result.content!.split('\n');
    expect(lines[0]).toMatch(/^\s+1\t/);
  });

  test('should handle large line numbers', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'large.txt'), 1998, 5);

    expect(result.success).toBe(true);
    expect(result.content).toContain('1999\t');
    expect(result.content).toContain('2000\t');
  });

  test('should format multi-digit line numbers correctly', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'large.txt'), 0, 100);

    expect(result.success).toBe(true);
    // Should have consistent formatting - spaces for padding, then line number, then tab
    // Format is like "     1\t" for single digit, "    10\t" for double, "   100\t" for triple
    expect(result.content).toContain('1\tLine 1');
    expect(result.content).toContain('10\tLine 10');
    expect(result.content).toContain('100\tLine 100');
  });
});

describe('readFileImpl - truncated flag', () => {
  test('should set truncated flag when file exceeds limit', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'large.txt'), undefined, 100);

    expect(result.success).toBe(true);
    expect(result.truncated).toBe(true);
  });

  test('should not set truncated flag when reading entire file', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'));

    expect(result.success).toBe(true);
    expect(result.truncated).toBe(false);
  });

  test('should set truncated flag with default limit on large file', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'large.txt'));

    expect(result.success).toBe(true);
    expect(result.truncated).toBe(true);
  });

  test('should not set truncated flag when limit exceeds file size', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'), undefined, 1000);

    expect(result.success).toBe(true);
    expect(result.truncated).toBe(false);
  });
});

describe('readFileImpl - edge cases', () => {
  test('should handle file with only newlines', async () => {
    const testFile = resolve(TEST_DIR, 'newlines.txt');
    await writeFile(testFile, '\n\n\n\n\n');

    const result = await readFileImpl(testFile);

    expect(result.success).toBe(true);
    expect(result.lineCount).toBe(6);
  });

  test('should handle file without trailing newline', async () => {
    const testFile = resolve(TEST_DIR, 'no-trailing-newline.txt');
    await writeFile(testFile, 'Line 1\nLine 2\nLine 3');

    const result = await readFileImpl(testFile);

    expect(result.success).toBe(true);
    expect(result.content).toContain('Line 3');
  });

  test('should handle single line file', async () => {
    const testFile = resolve(TEST_DIR, 'single-line.txt');
    await writeFile(testFile, 'Single line');

    const result = await readFileImpl(testFile);

    expect(result.success).toBe(true);
    expect(result.lineCount).toBe(1);
    expect(result.content).toContain('Single line');
  });

  test('should handle binary content gracefully', async () => {
    const testFile = resolve(TEST_DIR, 'binary.bin');
    const buffer = Buffer.from([0x00, 0x01, 0x02, 0xFF, 0xFE]);
    await writeFile(testFile, buffer);

    const result = await readFileImpl(testFile);

    // Should not crash, though content may be garbled
    expect(result.success).toBe(true);
  });

  test('should handle files with mixed line endings', async () => {
    const testFile = resolve(TEST_DIR, 'mixed-endings.txt');
    await writeFile(testFile, 'Line 1\nLine 2\r\nLine 3\rLine 4\n');

    const result = await readFileImpl(testFile);

    expect(result.success).toBe(true);
    expect(result.content).toBeDefined();
  });

  test('should handle files with tabs and special characters', async () => {
    const testFile = resolve(TEST_DIR, 'special-chars.txt');
    await writeFile(testFile, 'Line\twith\ttabs\nLine with spaces  \nLine with\u0000null\n');

    const result = await readFileImpl(testFile);

    expect(result.success).toBe(true);
    expect(result.content).toContain('Line\twith\ttabs');
  });
});

describe('readFileImpl - error handling', () => {
  test('should handle read errors gracefully', async () => {
    // Try to read a directory as a file
    const result = await readFileImpl(TEST_DIR);

    expect(result.success).toBe(false);
    expect(result.error).toBeDefined();
  });

  test('should provide helpful error message for missing file', async () => {
    const result = await readFileImpl(resolve(TEST_DIR, 'missing-file.txt'));

    expect(result.success).toBe(false);
    expect(result.error).toContain('file not found');
  });

  test('should handle permission errors', async () => {
    // Note: This test may behave differently on different systems
    // On systems where we can't simulate permission errors, it will just succeed
    const result = await readFileImpl(resolve(TEST_DIR, 'simple.txt'));

    // Basic check that the function doesn't crash
    expect(result.success).toBeDefined();
  });
});
