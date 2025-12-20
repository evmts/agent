/**
 * Tests for filesystem utilities.
 */

import { describe, test, expect, beforeEach, afterEach } from 'bun:test';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import {
  resolveAndValidatePath,
  fileExists,
  ensureDir,
  getRelativePath,
  truncateLongLines,
  ERROR_PATH_TRAVERSAL,
  ERROR_FILE_OUTSIDE_CWD,
} from '../filesystem';

// Test directory for file operations
const TEST_DIR = join(process.cwd(), '__test_filesystem__');

describe('resolveAndValidatePath', () => {
  describe('path traversal prevention', () => {
    test('rejects paths with .. traversal', () => {
      const [path, error] = resolveAndValidatePath('../etc/passwd');

      expect(path).toBe('');
      expect(error).toBe(ERROR_PATH_TRAVERSAL.replace('{}', '../etc/passwd'));
    });

    test('rejects paths with .. in middle', () => {
      const [path, error] = resolveAndValidatePath('foo/../../../etc/passwd');

      expect(path).toBe('');
      expect(error).toBe(ERROR_PATH_TRAVERSAL.replace('{}', 'foo/../../../etc/passwd'));
    });

    test('rejects multiple .. segments', () => {
      const [path, error] = resolveAndValidatePath('../../sensitive');

      expect(path).toBe('');
      expect(error).toBeTruthy();
    });

    test('rejects hidden .. in complex paths', () => {
      const [path, error] = resolveAndValidatePath('foo/bar/../../../etc/passwd');

      expect(path).toBe('');
      expect(error).toBeTruthy();
    });
  });

  describe('working directory validation', () => {
    test('accepts relative paths within working directory', () => {
      const [path, error] = resolveAndValidatePath('foo/bar.txt', '/home/user');

      expect(error).toBeNull();
      expect(path).toBe('/home/user/foo/bar.txt');
    });

    test('accepts absolute paths within working directory', () => {
      const [path, error] = resolveAndValidatePath('/home/user/foo/bar.txt', '/home/user');

      expect(error).toBeNull();
      expect(path).toBe('/home/user/foo/bar.txt');
    });

    test('rejects absolute paths outside working directory', () => {
      const [path, error] = resolveAndValidatePath('/etc/passwd', '/home/user');

      expect(path).toBe('');
      expect(error).toBe(ERROR_FILE_OUTSIDE_CWD.replace('{}', '/etc/passwd'));
    });

    test('rejects paths that resolve outside working directory', () => {
      const [path, error] = resolveAndValidatePath('/home/other/file.txt', '/home/user');

      expect(path).toBe('');
      expect(error).toBeTruthy();
    });

    test('uses process.cwd() when working directory not provided', () => {
      const [path, error] = resolveAndValidatePath('test.txt');

      expect(error).toBeNull();
      expect(path).toBe(join(process.cwd(), 'test.txt'));
    });
  });

  describe('path resolution', () => {
    test('resolves relative paths', () => {
      const [path, error] = resolveAndValidatePath('foo/bar.txt', '/home/user');

      expect(error).toBeNull();
      expect(path).toBe('/home/user/foo/bar.txt');
    });

    test('resolves single filename', () => {
      const [path, error] = resolveAndValidatePath('file.txt', '/home/user');

      expect(error).toBeNull();
      expect(path).toBe('/home/user/file.txt');
    });

    test('resolves nested paths', () => {
      const [path, error] = resolveAndValidatePath('a/b/c/d/file.txt', '/home/user');

      expect(error).toBeNull();
      expect(path).toBe('/home/user/a/b/c/d/file.txt');
    });

    test('normalizes paths', () => {
      const [path, error] = resolveAndValidatePath('foo/./bar.txt', '/home/user');

      expect(error).toBeNull();
      expect(path).toBe('/home/user/foo/bar.txt');
    });

    test('handles paths with special characters', () => {
      const [path, error] = resolveAndValidatePath('foo-bar_baz.txt', '/home/user');

      expect(error).toBeNull();
      expect(path).toBe('/home/user/foo-bar_baz.txt');
    });

    test('handles paths with spaces', () => {
      const [path, error] = resolveAndValidatePath('my file.txt', '/home/user');

      expect(error).toBeNull();
      expect(path).toBe('/home/user/my file.txt');
    });
  });

  describe('edge cases', () => {
    test('handles root directory as working directory', () => {
      const [path, error] = resolveAndValidatePath('file.txt', '/');

      expect(error).toBeNull();
      expect(path).toBe('/file.txt');
    });

    test('handles empty relative path segments', () => {
      const [path, error] = resolveAndValidatePath('foo//bar.txt', '/home/user');

      expect(error).toBeNull();
      expect(path).toContain('foo/bar.txt');
    });

    test('handles working directory with trailing slash', () => {
      const [path, error] = resolveAndValidatePath('file.txt', '/home/user/');

      expect(error).toBeNull();
      expect(path).toContain('file.txt');
    });
  });
});

describe('fileExists', () => {
  beforeEach(async () => {
    await mkdir(TEST_DIR, { recursive: true });
  });

  afterEach(async () => {
    await rm(TEST_DIR, { recursive: true, force: true });
  });

  test('returns true for existing file', async () => {
    const filePath = join(TEST_DIR, 'test.txt');
    await writeFile(filePath, 'content');

    const exists = await fileExists(filePath);

    expect(exists).toBe(true);
  });

  test('returns false for non-existing file', async () => {
    const filePath = join(TEST_DIR, 'nonexistent.txt');

    const exists = await fileExists(filePath);

    expect(exists).toBe(false);
  });

  test('returns true for existing directory', async () => {
    const exists = await fileExists(TEST_DIR);

    expect(exists).toBe(true);
  });

  test('returns false for non-existing directory', async () => {
    const dirPath = join(TEST_DIR, 'nonexistent-dir');

    const exists = await fileExists(dirPath);

    expect(exists).toBe(false);
  });

  test('handles nested paths', async () => {
    const nestedDir = join(TEST_DIR, 'a', 'b', 'c');
    const filePath = join(nestedDir, 'test.txt');

    await mkdir(nestedDir, { recursive: true });
    await writeFile(filePath, 'content');

    const exists = await fileExists(filePath);

    expect(exists).toBe(true);
  });

  test('does not throw for invalid paths', async () => {
    const exists = await fileExists('/invalid/path/that/does/not/exist/file.txt');

    expect(exists).toBe(false);
  });
});

describe('ensureDir', () => {
  beforeEach(async () => {
    await mkdir(TEST_DIR, { recursive: true });
  });

  afterEach(async () => {
    await rm(TEST_DIR, { recursive: true, force: true });
  });

  test('creates directory if it does not exist', async () => {
    const dirPath = join(TEST_DIR, 'new-dir');

    await ensureDir(dirPath);

    const exists = await fileExists(dirPath);
    expect(exists).toBe(true);
  });

  test('does nothing if directory already exists', async () => {
    const dirPath = join(TEST_DIR, 'existing-dir');

    await mkdir(dirPath);
    await ensureDir(dirPath);

    const exists = await fileExists(dirPath);
    expect(exists).toBe(true);
  });

  test('creates nested directories', async () => {
    const dirPath = join(TEST_DIR, 'a', 'b', 'c', 'd');

    await ensureDir(dirPath);

    const exists = await fileExists(dirPath);
    expect(exists).toBe(true);
  });

  test('creates deeply nested directories', async () => {
    const dirPath = join(TEST_DIR, 'level1', 'level2', 'level3', 'level4', 'level5');

    await ensureDir(dirPath);

    const exists = await fileExists(dirPath);
    expect(exists).toBe(true);
  });

  test('works with absolute paths', async () => {
    const dirPath = join(TEST_DIR, 'absolute-test');

    await ensureDir(dirPath);

    const exists = await fileExists(dirPath);
    expect(exists).toBe(true);
  });

  test('can be called multiple times idempotently', async () => {
    const dirPath = join(TEST_DIR, 'idempotent-test');

    await ensureDir(dirPath);
    await ensureDir(dirPath);
    await ensureDir(dirPath);

    const exists = await fileExists(dirPath);
    expect(exists).toBe(true);
  });
});

describe('getRelativePath', () => {
  test('returns relative path from working directory', () => {
    const relativePath = getRelativePath('/home/user/project/file.txt', '/home/user');

    expect(relativePath).toBe('project/file.txt');
  });

  test('returns relative path for nested files', () => {
    const relativePath = getRelativePath('/home/user/a/b/c/file.txt', '/home/user');

    expect(relativePath).toBe('a/b/c/file.txt');
  });

  test('returns file name for file in working directory', () => {
    const relativePath = getRelativePath('/home/user/file.txt', '/home/user');

    expect(relativePath).toBe('file.txt');
  });

  test('returns .. for parent directory', () => {
    const relativePath = getRelativePath('/home/file.txt', '/home/user');

    expect(relativePath).toBe('../file.txt');
  });

  test('uses process.cwd() when working directory not provided', () => {
    const absPath = join(process.cwd(), 'test', 'file.txt');
    const relativePath = getRelativePath(absPath);

    expect(relativePath).toBe('test/file.txt');
  });

  test('handles paths with common prefix', () => {
    const relativePath = getRelativePath('/home/user/project/src/file.txt', '/home/user/project');

    expect(relativePath).toBe('src/file.txt');
  });

  test('handles same path', () => {
    const relativePath = getRelativePath('/home/user/project', '/home/user/project');

    expect(relativePath).toBe('');
  });

  test('returns absolute path on error', () => {
    // This should not throw, but return the absolute path
    const absolutePath = '/some/absolute/path';
    const relativePath = getRelativePath(absolutePath, '/different/base');

    expect(relativePath).toBeTruthy();
  });
});

describe('truncateLongLines', () => {
  test('does not modify short lines', () => {
    const text = 'This is a short line';
    const result = truncateLongLines(text);

    expect(result).toBe(text);
  });

  test('truncates lines longer than default max length', () => {
    const longLine = 'a'.repeat(3000);
    const result = truncateLongLines(longLine);

    expect(result.length).toBeLessThan(longLine.length);
    expect(result).toContain('... [truncated]');
  });

  test('truncates at specified max length', () => {
    const longLine = 'a'.repeat(200);
    const result = truncateLongLines(longLine, 100);

    expect(result).toBe('a'.repeat(100) + '... [truncated]');
  });

  test('handles multiline text', () => {
    const text = 'Short line\n' + 'a'.repeat(3000) + '\nAnother short line';
    const result = truncateLongLines(text);

    const lines = result.split('\n');
    expect(lines[0]).toBe('Short line');
    expect(lines[1]).toContain('... [truncated]');
    expect(lines[2]).toBe('Another short line');
  });

  test('truncates multiple long lines', () => {
    const line1 = 'a'.repeat(3000);
    const line2 = 'b'.repeat(3000);
    const text = `${line1}\n${line2}`;
    const result = truncateLongLines(text);

    const lines = result.split('\n');
    expect(lines[0]).toContain('... [truncated]');
    expect(lines[1]).toContain('... [truncated]');
  });

  test('preserves empty lines', () => {
    const text = 'Line 1\n\nLine 3';
    const result = truncateLongLines(text);

    expect(result).toBe(text);
    expect(result.split('\n').length).toBe(3);
  });

  test('handles text with only newlines', () => {
    const text = '\n\n\n';
    const result = truncateLongLines(text);

    expect(result).toBe(text);
  });

  test('handles empty string', () => {
    const result = truncateLongLines('');

    expect(result).toBe('');
  });

  test('handles text with different line endings', () => {
    const longLine = 'a'.repeat(3000);
    const text = `Short\n${longLine}\nAnother`;
    const result = truncateLongLines(text, 100);

    const lines = result.split('\n');
    expect(lines[0]).toBe('Short');
    expect(lines[1]).toContain('... [truncated]');
    expect(lines[2]).toBe('Another');
  });

  test('uses default max length of 2000', () => {
    const line1999 = 'a'.repeat(1999);
    const line2000 = 'a'.repeat(2000);
    const line2001 = 'a'.repeat(2001);

    expect(truncateLongLines(line1999)).toBe(line1999);
    expect(truncateLongLines(line2000)).toBe(line2000);
    expect(truncateLongLines(line2001)).toContain('... [truncated]');
  });

  test('custom max length works correctly', () => {
    const text = 'a'.repeat(50);

    const result10 = truncateLongLines(text, 10);
    const result30 = truncateLongLines(text, 30);
    const result100 = truncateLongLines(text, 100);

    expect(result10).toBe('a'.repeat(10) + '... [truncated]');
    expect(result30).toBe('a'.repeat(30) + '... [truncated]');
    expect(result100).toBe(text);
  });

  test('handles lines exactly at max length', () => {
    const text = 'a'.repeat(2000);
    const result = truncateLongLines(text, 2000);

    expect(result).toBe(text);
    expect(result).not.toContain('truncated');
  });

  test('preserves line structure', () => {
    const text = 'Line 1\nLine 2\nLine 3\nLine 4';
    const result = truncateLongLines(text);

    expect(result.split('\n').length).toBe(4);
    expect(result).toBe(text);
  });

  test('handles mixed short and long lines', () => {
    const lines = [
      'Short',
      'a'.repeat(3000),
      'Another short',
      'b'.repeat(3000),
      'Final short',
    ];
    const text = lines.join('\n');
    const result = truncateLongLines(text, 100);

    const resultLines = result.split('\n');
    expect(resultLines[0]).toBe('Short');
    expect(resultLines[1]).toContain('... [truncated]');
    expect(resultLines[2]).toBe('Another short');
    expect(resultLines[3]).toContain('... [truncated]');
    expect(resultLines[4]).toBe('Final short');
  });
});

describe('error message constants', () => {
  test('ERROR_PATH_TRAVERSAL has placeholder', () => {
    expect(ERROR_PATH_TRAVERSAL).toContain('{}');
    expect(ERROR_PATH_TRAVERSAL).toContain('path traversal');
  });

  test('ERROR_FILE_OUTSIDE_CWD has placeholder', () => {
    expect(ERROR_FILE_OUTSIDE_CWD).toContain('{}');
    expect(ERROR_FILE_OUTSIDE_CWD).toContain('current working directory');
  });

  test('error messages can be formatted', () => {
    const path = '../etc/passwd';
    const formatted = ERROR_PATH_TRAVERSAL.replace('{}', path);

    expect(formatted).toContain(path);
    expect(formatted).not.toContain('{}');
  });
});
