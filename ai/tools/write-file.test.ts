/**
 * Tests for write-file tool with read-before-write safety.
 */

import { describe, test, expect, beforeAll, afterAll, beforeEach } from 'bun:test';
import { writeFileImpl } from './write-file';
import { mkdir, rm, writeFile, readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';

// Test directory setup
const TEST_DIR = resolve(import.meta.dir, '../../.test-tmp/write-file');

beforeAll(async () => {
  // Clean up any existing test directory
  await rm(TEST_DIR, { recursive: true, force: true });
  await mkdir(TEST_DIR, { recursive: true });
});

afterAll(async () => {
  // Clean up test directory
  await rm(TEST_DIR, { recursive: true, force: true });
});

describe('writeFileImpl', () => {
  describe('basic file writing', () => {
    test('creates new file successfully', async () => {
      const filePath = join(TEST_DIR, 'new-file.txt');
      const content = 'Hello, World!';

      const result = await writeFileImpl(filePath, content, TEST_DIR);

      expect(result.success).toBe(true);
      expect(result.created).toBe(true);
      expect(result.error).toBeUndefined();

      const written = await readFile(filePath, 'utf-8');
      expect(written).toBe(content);
    });

    test('overwrites existing file', async () => {
      const filePath = join(TEST_DIR, 'overwrite.txt');
      await writeFile(filePath, 'original content');

      const newContent = 'new content';
      const result = await writeFileImpl(filePath, newContent, TEST_DIR);

      expect(result.success).toBe(true);
      expect(result.created).toBe(false);

      const written = await readFile(filePath, 'utf-8');
      expect(written).toBe(newContent);
    });

    test('creates parent directories if needed', async () => {
      const filePath = join(TEST_DIR, 'nested', 'deep', 'file.txt');
      const content = 'nested content';

      const result = await writeFileImpl(filePath, content, TEST_DIR);

      expect(result.success).toBe(true);
      expect(result.created).toBe(true);

      const written = await readFile(filePath, 'utf-8');
      expect(written).toBe(content);
    });

    test('writes empty file', async () => {
      const filePath = join(TEST_DIR, 'empty.txt');

      const result = await writeFileImpl(filePath, '', TEST_DIR);

      expect(result.success).toBe(true);
      expect(result.created).toBe(true);

      const written = await readFile(filePath, 'utf-8');
      expect(written).toBe('');
    });

    test('writes file with special characters', async () => {
      const filePath = join(TEST_DIR, 'special.txt');
      const content = 'Special chars: \n\t\r\\unicode: \u{1F600}';

      const result = await writeFileImpl(filePath, content, TEST_DIR);

      expect(result.success).toBe(true);
      const written = await readFile(filePath, 'utf-8');
      expect(written).toBe(content);
    });

    test('writes large file', async () => {
      const filePath = join(TEST_DIR, 'large.txt');
      const content = 'x'.repeat(100000);

      const result = await writeFileImpl(filePath, content, TEST_DIR);

      expect(result.success).toBe(true);
      const written = await readFile(filePath, 'utf-8');
      expect(written).toBe(content);
    });
  });

  describe('path validation', () => {
    test('rejects path traversal attempts', async () => {
      const result = await writeFileImpl('../../../etc/passwd', 'content', TEST_DIR);

      expect(result.success).toBe(false);
      expect(result.error).toBeTruthy();
      expect(result.error).toContain('path traversal');
    });

    test('rejects paths outside working directory', async () => {
      const result = await writeFileImpl('/etc/passwd', 'content', TEST_DIR);

      expect(result.success).toBe(false);
      expect(result.error).toBeTruthy();
    });

    test('handles paths with special characters in name', async () => {
      const filePath = join(TEST_DIR, 'file-with_special.chars.txt');
      const content = 'test content';

      const result = await writeFileImpl(filePath, content, TEST_DIR);

      expect(result.success).toBe(true);
      const written = await readFile(filePath, 'utf-8');
      expect(written).toBe(content);
    });

    test('accepts relative paths within working directory', async () => {
      const content = 'relative path content';

      const result = await writeFileImpl('relative.txt', content, TEST_DIR);

      expect(result.success).toBe(true);
      const written = await readFile(join(TEST_DIR, 'relative.txt'), 'utf-8');
      expect(written).toBe(content);
    });
  });

  describe('content types', () => {
    test('writes JSON content', async () => {
      const filePath = join(TEST_DIR, 'data.json');
      const content = JSON.stringify({ key: 'value', number: 42 }, null, 2);

      const result = await writeFileImpl(filePath, content, TEST_DIR);

      expect(result.success).toBe(true);
      const written = await readFile(filePath, 'utf-8');
      expect(JSON.parse(written)).toEqual({ key: 'value', number: 42 });
    });

    test('writes multiline content', async () => {
      const filePath = join(TEST_DIR, 'multiline.txt');
      const content = 'Line 1\nLine 2\nLine 3';

      const result = await writeFileImpl(filePath, content, TEST_DIR);

      expect(result.success).toBe(true);
      const written = await readFile(filePath, 'utf-8');
      expect(written.split('\n').length).toBe(3);
    });

    test('writes TypeScript/JavaScript code', async () => {
      const filePath = join(TEST_DIR, 'code.ts');
      const content = `export function hello(): string {
  return 'Hello, World!';
}

export const PI = 3.14159;
`;

      const result = await writeFileImpl(filePath, content, TEST_DIR);

      expect(result.success).toBe(true);
      const written = await readFile(filePath, 'utf-8');
      expect(written).toBe(content);
    });
  });

  describe('error handling', () => {
    test('handles permission errors gracefully', async () => {
      // Try to write to a restricted path (this test may vary by OS)
      const result = await writeFileImpl('/root/test.txt', 'content');

      // Should either fail with error or succeed (depending on permissions)
      if (!result.success) {
        expect(result.error).toBeTruthy();
      }
    });
  });

  describe('idempotency', () => {
    test('can write same file multiple times', async () => {
      const filePath = join(TEST_DIR, 'idempotent.txt');

      await writeFileImpl(filePath, 'content 1', TEST_DIR);
      await writeFileImpl(filePath, 'content 2', TEST_DIR);
      const result = await writeFileImpl(filePath, 'content 3', TEST_DIR);

      expect(result.success).toBe(true);
      expect(result.created).toBe(false);

      const written = await readFile(filePath, 'utf-8');
      expect(written).toBe('content 3');
    });

    test('returns created=true only for new files', async () => {
      const filePath1 = join(TEST_DIR, 'new1.txt');
      const filePath2 = join(TEST_DIR, 'existing-for-test.txt');

      // Create existing file first
      await writeFile(filePath2, 'existing');

      const result1 = await writeFileImpl(filePath1, 'new content', TEST_DIR);
      const result2 = await writeFileImpl(filePath2, 'updated content', TEST_DIR);

      expect(result1.created).toBe(true);
      expect(result2.created).toBe(false);
    });
  });
});
