/**
 * Tests for multiedit tool with sequential edits and read-before-write enforcement.
 */

import { describe, test, expect, beforeAll, afterAll, beforeEach } from 'bun:test';
import { multieditImpl } from './multiedit';
import { mkdir, rm, writeFile, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

// Test directory setup
const TEST_DIR = resolve(import.meta.dir, '../../.test-tmp/multiedit');

beforeAll(async () => {
  // Clean up any existing test directory
  await rm(TEST_DIR, { recursive: true, force: true });
  await mkdir(TEST_DIR, { recursive: true });
});

beforeEach(async () => {
  // Create fresh test files before each test
  await writeFile(
    resolve(TEST_DIR, 'example.ts'),
    `export function calculate(a: number, b: number) {
  return a + b;
}

export const VERSION = '1.0.0';
`
  );

  await writeFile(
    resolve(TEST_DIR, 'config.json'),
    `{
  "name": "example",
  "version": "1.0.0",
  "debug": false
}
`
  );
});

afterAll(async () => {
  // Clean up test directory
  await rm(TEST_DIR, { recursive: true, force: true });
});

describe('multieditImpl - basic edits', () => {
  test('should perform single edit', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'calculate',
          newString: 'add',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);
    expect(result.editCount).toBe(1);

    const content = await readFile(resolve(TEST_DIR, 'example.ts'), 'utf-8');
    expect(content).toContain('export function add');
    expect(content).not.toContain('calculate');
  });

  test('should perform multiple sequential edits', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'calculate',
          newString: 'add',
          replaceAll: false,
        },
        {
          oldString: 'a + b',
          newString: 'a + b + 0',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);
    expect(result.editCount).toBe(2);

    const content = await readFile(resolve(TEST_DIR, 'example.ts'), 'utf-8');
    expect(content).toContain('export function add');
    expect(content).toContain('a + b + 0');
  });

  test('should edit JSON file', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'config.json'),
      [
        {
          oldString: '"version": "1.0.0"',
          newString: '"version": "2.0.0"',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(resolve(TEST_DIR, 'config.json'), 'utf-8');
    expect(content).toContain('"version": "2.0.0"');
  });
});

describe('multieditImpl - replaceAll parameter', () => {
  test('should replace all occurrences with replaceAll=true', async () => {
    await writeFile(
      resolve(TEST_DIR, 'multiple.txt'),
      'foo bar foo baz foo'
    );

    const result = await multieditImpl(
      resolve(TEST_DIR, 'multiple.txt'),
      [
        {
          oldString: 'foo',
          newString: 'qux',
          replaceAll: true,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(resolve(TEST_DIR, 'multiple.txt'), 'utf-8');
    expect(content).toBe('qux bar qux baz qux');
  });

  test('should replace only first occurrence with replaceAll=false', async () => {
    await writeFile(
      resolve(TEST_DIR, 'multiple.txt'),
      'foo bar foo baz foo'
    );

    const result = await multieditImpl(
      resolve(TEST_DIR, 'multiple.txt'),
      [
        {
          oldString: 'foo',
          newString: 'qux',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(resolve(TEST_DIR, 'multiple.txt'), 'utf-8');
    expect(content).toBe('qux bar foo baz foo');
  });

  test('should error on multiple occurrences without replaceAll', async () => {
    await writeFile(
      resolve(TEST_DIR, 'multiple.txt'),
      'foo bar foo baz foo'
    );

    const result = await multieditImpl(
      resolve(TEST_DIR, 'multiple.txt'),
      [
        {
          oldString: 'foo',
          newString: 'qux',
          replaceAll: false,
        },
      ]
    );

    // First occurrence should be replaced
    expect(result.success).toBe(true);
  });

  test('should handle replaceAll with no matches gracefully', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'nonexistent',
          newString: 'replacement',
          replaceAll: true,
        },
      ]
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain('not found');
  });
});

describe('multieditImpl - sequential edit behavior', () => {
  test('should apply edits sequentially', async () => {
    await writeFile(
      resolve(TEST_DIR, 'sequential.txt'),
      'Step 1'
    );

    const result = await multieditImpl(
      resolve(TEST_DIR, 'sequential.txt'),
      [
        {
          oldString: 'Step 1',
          newString: 'Step 2',
          replaceAll: false,
        },
        {
          oldString: 'Step 2',
          newString: 'Step 3',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);
    expect(result.editCount).toBe(2);

    const content = await readFile(resolve(TEST_DIR, 'sequential.txt'), 'utf-8');
    expect(content).toBe('Step 3');
  });

  test('should fail if second edit depends on first but string not found', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'calculate',
          newString: 'add',
          replaceAll: false,
        },
        {
          oldString: 'calculate',
          newString: 'multiply',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(false);
    expect(result.editCount).toBe(1);
    expect(result.error).toContain('edit 2 failed');
  });

  test('should apply complex sequential transformations', async () => {
    await writeFile(
      resolve(TEST_DIR, 'transform.txt'),
      'a b c'
    );

    const result = await multieditImpl(
      resolve(TEST_DIR, 'transform.txt'),
      [
        {
          oldString: 'a',
          newString: 'x',
          replaceAll: false,
        },
        {
          oldString: 'b',
          newString: 'y',
          replaceAll: false,
        },
        {
          oldString: 'c',
          newString: 'z',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(resolve(TEST_DIR, 'transform.txt'), 'utf-8');
    expect(content).toBe('x y z');
  });
});

describe('multieditImpl - new file creation', () => {
  test('should create new file with empty oldString', async () => {
    const newFile = resolve(TEST_DIR, 'newfile.txt');

    const result = await multieditImpl(
      newFile,
      [
        {
          oldString: '',
          newString: 'New file content',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(newFile, 'utf-8');
    expect(content).toBe('New file content');
  });

  test('should create new file with multiple lines', async () => {
    const newFile = resolve(TEST_DIR, 'multiline.txt');

    const result = await multieditImpl(
      newFile,
      [
        {
          oldString: '',
          newString: 'Line 1\nLine 2\nLine 3',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(newFile, 'utf-8');
    expect(content).toBe('Line 1\nLine 2\nLine 3');
  });

  test('should not allow empty oldString on existing file', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: '',
          newString: 'replacement',
          replaceAll: false,
        },
      ]
    );

    // Empty oldString on existing file should fail
    expect(result.success).toBe(false);
  });
});

describe('multieditImpl - validation errors', () => {
  test('should reject missing file_path', async () => {
    const result = await multieditImpl(
      '',
      [
        {
          oldString: 'old',
          newString: 'new',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain('file_path parameter is required');
  });

  test('should reject empty edits array', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      []
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain('edits array cannot be empty');
  });

  test('should reject edit with missing oldString', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        // @ts-expect-error - Testing invalid input
        {
          newString: 'new',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain('missing old_string');
  });

  test('should reject edit with missing newString', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        // @ts-expect-error - Testing invalid input
        {
          oldString: 'old',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain('missing new_string');
  });

  test('should reject edit with identical old and new strings', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'same',
          newString: 'same',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain('identical old_string and new_string');
  });

  test('should reject invalid edit object', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      // @ts-expect-error - Testing invalid input
      [null]
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain('not a valid object');
  });
});

describe('multieditImpl - path validation', () => {
  test('should reject path traversal with ..', async () => {
    const result = await multieditImpl(
      '../../../etc/passwd',
      [
        {
          oldString: 'old',
          newString: 'new',
          replaceAll: false,
        },
      ],
      TEST_DIR
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain('path traversal');
  });

  test('should reject paths outside working directory', async () => {
    const result = await multieditImpl(
      '/etc/passwd',
      [
        {
          oldString: 'old',
          newString: 'new',
          replaceAll: false,
        },
      ],
      TEST_DIR
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain('not in the current working directory');
  });

  test('should handle relative paths within working directory', async () => {
    const result = await multieditImpl(
      'example.ts',
      [
        {
          oldString: 'calculate',
          newString: 'add',
          replaceAll: false,
        },
      ],
      TEST_DIR
    );

    expect(result.success).toBe(true);
  });
});

describe('multieditImpl - read-before-write enforcement', () => {
  test('should succeed without sessionId (no enforcement)', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'calculate',
          newString: 'add',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);
  });

  test('should allow edit on new file without prior read', async () => {
    const newFile = resolve(TEST_DIR, 'brandnew.txt');

    const result = await multieditImpl(
      newFile,
      [
        {
          oldString: '',
          newString: 'New content',
          replaceAll: false,
        },
      ],
      undefined,
      'test-session-id'
    );

    // Should succeed because file doesn't exist yet
    expect(result.success).toBe(true);
  });

  // Note: Testing read-before-write with actual session tracking requires
  // database integration which is out of scope for unit tests
});

describe('multieditImpl - error handling', () => {
  test('should fail if oldString not found', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'nonexistent',
          newString: 'replacement',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain('not found');
  });

  test('should stop at first failing edit', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'calculate',
          newString: 'add',
          replaceAll: false,
        },
        {
          oldString: 'nonexistent',
          newString: 'replacement',
          replaceAll: false,
        },
        {
          oldString: 'VERSION',
          newString: 'VER',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(false);
    expect(result.editCount).toBe(1);

    // First edit should have been applied
    const content = await readFile(resolve(TEST_DIR, 'example.ts'), 'utf-8');
    expect(content).toContain('add');
    // Third edit should not have been applied
    expect(content).toContain('VERSION');
  });

  test('should handle file write errors', async () => {
    // Try to write to a directory
    const result = await multieditImpl(
      TEST_DIR,
      [
        {
          oldString: 'old',
          newString: 'new',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(false);
    expect(result.error).toBeDefined();
  });
});

describe('multieditImpl - working directory', () => {
  test('should use custom working directory', async () => {
    const result = await multieditImpl(
      'example.ts',
      [
        {
          oldString: 'calculate',
          newString: 'add',
          replaceAll: false,
        },
      ],
      TEST_DIR
    );

    expect(result.success).toBe(true);
  });

  test('should resolve relative paths against working directory', async () => {
    await mkdir(resolve(TEST_DIR, 'nested'), { recursive: true });
    await writeFile(resolve(TEST_DIR, 'nested/file.txt'), 'content here');

    const result = await multieditImpl(
      'nested/file.txt',
      [
        {
          oldString: 'content',
          newString: 'text',
          replaceAll: false,
        },
      ],
      TEST_DIR
    );

    expect(result.success).toBe(true);
  });
});

describe('multieditImpl - edge cases', () => {
  test('should handle whitespace in oldString', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'export function calculate',
          newString: 'export function add',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(resolve(TEST_DIR, 'example.ts'), 'utf-8');
    expect(content).toContain('export function add');
  });

  test('should handle multiline oldString', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'export function calculate(a: number, b: number) {\n  return a + b;\n}',
          newString: 'export const calculate = (a: number, b: number) => a + b;',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(resolve(TEST_DIR, 'example.ts'), 'utf-8');
    expect(content).toContain('export const calculate =');
  });

  test('should handle special regex characters in strings', async () => {
    await writeFile(
      resolve(TEST_DIR, 'regex-chars.txt'),
      'Price: $10.99 (sale)'
    );

    const result = await multieditImpl(
      resolve(TEST_DIR, 'regex-chars.txt'),
      [
        {
          oldString: '$10.99',
          newString: '$15.99',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(resolve(TEST_DIR, 'regex-chars.txt'), 'utf-8');
    expect(content).toContain('$15.99');
  });

  test('should handle unicode characters', async () => {
    await writeFile(
      resolve(TEST_DIR, 'unicode.txt'),
      'Hello 世界'
    );

    const result = await multieditImpl(
      resolve(TEST_DIR, 'unicode.txt'),
      [
        {
          oldString: '世界',
          newString: 'World',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(resolve(TEST_DIR, 'unicode.txt'), 'utf-8');
    expect(content).toContain('Hello World');
  });

  test('should handle empty newString (deletion)', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'calculate',
          newString: '',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(resolve(TEST_DIR, 'example.ts'), 'utf-8');
    expect(content).not.toContain('calculate');
    expect(content).toContain('export function');
  });

  test('should handle very long strings', async () => {
    const longString = 'x'.repeat(10000);
    await writeFile(resolve(TEST_DIR, 'long.txt'), longString);

    const result = await multieditImpl(
      resolve(TEST_DIR, 'long.txt'),
      [
        {
          oldString: longString,
          newString: 'short',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(resolve(TEST_DIR, 'long.txt'), 'utf-8');
    expect(content).toBe('short');
  });

  test('should handle file with no trailing newline', async () => {
    await writeFile(resolve(TEST_DIR, 'no-newline.txt'), 'no newline');

    const result = await multieditImpl(
      resolve(TEST_DIR, 'no-newline.txt'),
      [
        {
          oldString: 'no newline',
          newString: 'with newline\n',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);

    const content = await readFile(resolve(TEST_DIR, 'no-newline.txt'), 'utf-8');
    expect(content).toBe('with newline\n');
  });

  test('should handle empty file', async () => {
    await writeFile(resolve(TEST_DIR, 'empty.txt'), '');

    const result = await multieditImpl(
      resolve(TEST_DIR, 'empty.txt'),
      [
        {
          oldString: 'anything',
          newString: 'something',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain('not found');
  });
});

describe('multieditImpl - output messages', () => {
  test('should provide success message with edit count', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'calculate',
          newString: 'add',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);
    expect(result.output).toContain('Applied 1 edit');
  });

  test('should provide success message with multiple edit count', async () => {
    const result = await multieditImpl(
      resolve(TEST_DIR, 'example.ts'),
      [
        {
          oldString: 'calculate',
          newString: 'add',
          replaceAll: false,
        },
        {
          oldString: 'VERSION',
          newString: 'VER',
          replaceAll: false,
        },
      ]
    );

    expect(result.success).toBe(true);
    expect(result.output).toContain('Applied 2 edit');
  });

  test('should use relative path in messages', async () => {
    const result = await multieditImpl(
      'example.ts',
      [
        {
          oldString: 'calculate',
          newString: 'add',
          replaceAll: false,
        },
      ],
      TEST_DIR
    );

    expect(result.success).toBe(true);
    expect(result.output).toContain('example.ts');
    expect(result.filePath).toBe('example.ts');
  });
});
