/**
 * Tests for grep tool with multiline pattern matching and pagination support.
 */

import { describe, test, expect, beforeAll, afterAll } from 'bun:test';
import { grepImpl } from './grep';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

// Test directory setup
const TEST_DIR = resolve(import.meta.dir, '../../.test-tmp/grep');

beforeAll(async () => {
  // Clean up any existing test directory
  await rm(TEST_DIR, { recursive: true, force: true });
  await mkdir(TEST_DIR, { recursive: true });

  // Create test files
  await writeFile(
    resolve(TEST_DIR, 'file1.ts'),
    `export function authenticate(user: string, password: string) {
  console.log('Authenticating user:', user);
  return true;
}

export function authorize(user: string) {
  return user === 'admin';
}
`
  );

  await writeFile(
    resolve(TEST_DIR, 'file2.js'),
    `function calculate(a, b) {
  return a + b;
}

function authenticate(username) {
  console.log('Login attempt');
  return true;
}
`
  );

  await writeFile(
    resolve(TEST_DIR, 'file3.py'),
    `def authenticate(username, password):
    """Authenticate a user"""
    print(f"Authenticating {username}")
    return True

def process_data():
    return None
`
  );

  await writeFile(
    resolve(TEST_DIR, 'multiline.txt'),
    `This is a single line.
function example() {
  const x = 1;
  const y = 2;
  return x + y;
}
Another line here.
`
  );

  // Create nested directory structure
  await mkdir(resolve(TEST_DIR, 'nested'), { recursive: true });
  await writeFile(
    resolve(TEST_DIR, 'nested/deep.ts'),
    `export const SECRET = 'hidden';
export const PUBLIC = 'visible';
`
  );
});

afterAll(async () => {
  // Clean up test directory
  await rm(TEST_DIR, { recursive: true, force: true });
});

describe('grepImpl - basic pattern search', () => {
  test('should find simple pattern match', async () => {
    const result = await grepImpl('authenticate', TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.matches).toBeDefined();
    expect(result.matches!.length).toBeGreaterThan(0);
    expect(result.formattedOutput).toContain('authenticate');
    expect(result.truncated).toBe(false);
  });

  test('should find pattern in specific file', async () => {
    const result = await grepImpl('authenticate', resolve(TEST_DIR, 'file1.ts'));

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBe(1);
    expect(result.matches![0]!.path).toContain('file1.ts');
    expect(result.matches![0]!.text).toContain('authenticate');
  });

  test('should return no matches for non-existent pattern', async () => {
    const result = await grepImpl('nonexistentpattern12345', TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.matches).toEqual([]);
    expect(result.formattedOutput).toBe('No matches found');
    expect(result.totalCount).toBe(0);
  });

  test('should find pattern with line numbers', async () => {
    const result = await grepImpl('authenticate', TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
    expect(result.matches![0]!.lineNumber).toBeGreaterThan(0);
  });

  test('should find regex pattern', async () => {
    const result = await grepImpl('function.*\\(', TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
  });
});

describe('grepImpl - glob filter', () => {
  test('should filter by glob pattern - typescript files', async () => {
    const result = await grepImpl('authenticate', TEST_DIR, '*.ts');

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);

    // All matches should be from .ts files
    for (const match of result.matches!) {
      expect(match.path).toMatch(/\.ts$/);
    }
  });

  test('should filter by glob pattern - javascript files', async () => {
    const result = await grepImpl('authenticate', TEST_DIR, '*.js');

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBe(1);
    expect(result.matches![0]!.path).toContain('file2.js');
  });

  test('should filter by glob pattern - multiple extensions', async () => {
    const result = await grepImpl('authenticate', TEST_DIR, '*.{ts,js}');

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);

    // All matches should be from .ts or .js files
    for (const match of result.matches!) {
      expect(match.path).toMatch(/\.(ts|js)$/);
    }
  });

  test('should filter by glob pattern - python files', async () => {
    const result = await grepImpl('authenticate', TEST_DIR, '*.py');

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBe(1);
    expect(result.matches![0]!.path).toContain('file3.py');
  });
});

describe('grepImpl - multiline mode', () => {
  test('should match multiline pattern with multiline enabled', async () => {
    const result = await grepImpl('function.*\\{[\\s\\S]*?return', TEST_DIR, undefined, true);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
    expect(result.formattedOutput).toContain('(multiline mode enabled)');
  });

  test('should match across lines with multiline mode', async () => {
    const result = await grepImpl('function example.*\\n.*const x', TEST_DIR, undefined, true);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
    expect(result.matches![0]!.text).toContain('function example');
    expect(result.matches![0]!.text).toContain('const x');
  });

  test('should format multiline matches with line ranges', async () => {
    const result = await grepImpl('function.*\\{[\\s\\S]*?\\}', resolve(TEST_DIR, 'multiline.txt'), undefined, true);

    expect(result.success).toBe(true);
    expect(result.formattedOutput).toContain('Lines');
  });
});

describe('grepImpl - case insensitive', () => {
  test('should find pattern case-insensitively', async () => {
    const result = await grepImpl('AUTHENTICATE', TEST_DIR, undefined, undefined, true);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
  });

  test('should be case sensitive by default', async () => {
    const result = await grepImpl('AUTHENTICATE', TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.matches).toEqual([]);
  });

  test('should match different cases with case insensitive flag', async () => {
    const result = await grepImpl('function', TEST_DIR, undefined, undefined, true);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
  });
});

describe('grepImpl - pagination', () => {
  test('should limit results with headLimit', async () => {
    const result = await grepImpl('function', TEST_DIR, undefined, undefined, undefined, undefined, undefined, undefined, undefined, 2);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBe(2);
    expect(result.truncated).toBe(true);
    expect(result.formattedOutput).toContain('Output truncated to first 2 matches');
  });

  test('should skip results with offset', async () => {
    // First get all results to know total count
    const allResults = await grepImpl('function', TEST_DIR);
    const totalCount = allResults.matches!.length;

    // Skip first 2
    const result = await grepImpl('function', TEST_DIR, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, 2);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBe(totalCount - 2);
    expect(result.formattedOutput).toContain(`showing matches 3-${totalCount}`);
  });

  test('should combine offset and headLimit for pagination', async () => {
    const result = await grepImpl('function', TEST_DIR, undefined, undefined, undefined, undefined, undefined, undefined, undefined, 2, 1);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBe(2);
    expect(result.formattedOutput).toContain('showing matches 2-3');
  });

  test('should handle offset beyond total results', async () => {
    const result = await grepImpl('authenticate', TEST_DIR, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, 100);

    expect(result.success).toBe(true);
    expect(result.matches).toEqual([]);
  });

  test('should handle headLimit of 0 as unlimited', async () => {
    const result = await grepImpl('function', TEST_DIR, undefined, undefined, undefined, undefined, undefined, undefined, undefined, 0);

    expect(result.success).toBe(true);
    expect(result.truncated).toBe(false);
  });
});

describe('grepImpl - context lines', () => {
  test('should include context lines with contextLines parameter', async () => {
    const result = await grepImpl('authenticate', resolve(TEST_DIR, 'file1.ts'), undefined, undefined, undefined, undefined, undefined, undefined, 1);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
  });

  test('should include lines before with contextBefore', async () => {
    const result = await grepImpl('authenticate', resolve(TEST_DIR, 'file1.ts'), undefined, undefined, undefined, undefined, 1);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
  });

  test('should include lines after with contextAfter', async () => {
    const result = await grepImpl('authenticate', resolve(TEST_DIR, 'file1.ts'), undefined, undefined, undefined, undefined, undefined, 1);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
  });
});

describe('grepImpl - maxCount', () => {
  test('should limit matches per file with maxCount', async () => {
    const result = await grepImpl('function', TEST_DIR, undefined, undefined, undefined, 1);

    expect(result.success).toBe(true);

    // Group matches by file
    const matchesByFile = new Map<string, number>();
    for (const match of result.matches!) {
      const count = matchesByFile.get(match.path) ?? 0;
      matchesByFile.set(match.path, count + 1);
    }

    // Each file should have at most 1 match
    for (const count of matchesByFile.values()) {
      expect(count).toBeLessThanOrEqual(1);
    }
  });
});

describe('grepImpl - output formatting', () => {
  test('should format output with file paths and line numbers', async () => {
    const result = await grepImpl('authenticate', TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.formattedOutput).toContain(':');
    expect(result.formattedOutput).toContain('Line');
  });

  test('should group matches by file', async () => {
    const result = await grepImpl('authenticate', TEST_DIR);

    expect(result.success).toBe(true);
    // Should contain multiple file names
    const fileCount = (result.formattedOutput!.match(/\.ts:|\.js:|\.py:/g) || []).length;
    expect(fileCount).toBeGreaterThan(1);
  });

  test('should show match count in output', async () => {
    const result = await grepImpl('authenticate', TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.formattedOutput).toMatch(/Found \d+ match(es)?/);
  });
});

describe('grepImpl - error handling', () => {
  test('should handle invalid regex pattern', async () => {
    const result = await grepImpl('[invalid(regex', TEST_DIR);

    expect(result.success).toBe(false);
    expect(result.error).toBeDefined();
  });

  test('should handle non-existent path', async () => {
    const result = await grepImpl('pattern', '/nonexistent/path/12345');

    // ripgrep returns exit code 2 for missing paths
    expect(result.success).toBe(false);
    expect(result.error).toBeDefined();
  });

  test('should handle empty pattern gracefully', async () => {
    const result = await grepImpl('', TEST_DIR);

    // Empty pattern is technically valid in ripgrep (matches everything)
    expect(result.success).toBeDefined();
  });
});

describe('grepImpl - working directory', () => {
  test('should use custom working directory', async () => {
    const result = await grepImpl('authenticate', '.', undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
  });

  test('should respect working directory for relative paths', async () => {
    const result = await grepImpl('authenticate', 'file1.ts', undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBe(1);
  });
});

describe('grepImpl - edge cases', () => {
  test('should handle special regex characters', async () => {
    const result = await grepImpl('\\(', TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
  });

  test('should handle unicode patterns', async () => {
    // Create a file with unicode
    await writeFile(resolve(TEST_DIR, 'unicode.txt'), 'Hello 世界\nBonjour 世界\n');

    const result = await grepImpl('世界', TEST_DIR);

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBe(2);
  });

  test('should search hidden files when requested', async () => {
    // Create a hidden file
    await writeFile(resolve(TEST_DIR, '.hidden'), 'secret content\n');

    const result = await grepImpl('secret', TEST_DIR);

    // Should find it because we pass --hidden to ripgrep
    expect(result.success).toBe(true);
    expect(result.matches!.length).toBeGreaterThan(0);
  });

  test('should exclude .git directory', async () => {
    // Create a .git directory with content
    await mkdir(resolve(TEST_DIR, '.git'), { recursive: true });
    await writeFile(resolve(TEST_DIR, '.git/config'), 'authenticate = true\n');

    const result = await grepImpl('authenticate', TEST_DIR);

    // Should not find matches in .git directory
    expect(result.success).toBe(true);
    for (const match of result.matches!) {
      expect(match.path).not.toContain('.git');
    }
  });

  test('should handle empty files', async () => {
    await writeFile(resolve(TEST_DIR, 'empty.txt'), '');

    const result = await grepImpl('anything', resolve(TEST_DIR, 'empty.txt'));

    expect(result.success).toBe(true);
    expect(result.matches).toEqual([]);
  });

  test('should handle very long lines', async () => {
    const longLine = 'x'.repeat(10000) + ' authenticate ' + 'x'.repeat(10000);
    await writeFile(resolve(TEST_DIR, 'longline.txt'), longLine);

    const result = await grepImpl('authenticate', resolve(TEST_DIR, 'longline.txt'));

    expect(result.success).toBe(true);
    expect(result.matches!.length).toBe(1);
  });
});
