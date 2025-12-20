/**
 * Filesystem utilities for safe file operations.
 *
 * Provides path validation, resolution, and safe file operations
 * to prevent path traversal and ensure files stay within working directory.
 */

import { resolve, relative } from 'node:path';
import { stat, mkdir, realpath } from 'node:fs/promises';

// Error messages
export const ERROR_FILE_NOT_FOUND = 'file not found: {}';
export const ERROR_FILE_OUTSIDE_CWD = 'file {} is not in the current working directory';
export const ERROR_PATH_TRAVERSAL = 'path traversal detected in: {}';
export const ERROR_NOT_ABSOLUTE = 'file path must be absolute: {}';
export const ERROR_SYMLINK_ESCAPE = 'symlink points outside working directory: {}';

/**
 * Resolve and validate a file path.
 *
 * @param filePath - The file path to validate
 * @param workingDir - The working directory (defaults to cwd)
 * @returns Tuple of [resolvedPath, errorMessage]
 */
export function resolveAndValidatePath(
  filePath: string,
  workingDir?: string
): [string, string | null] {
  const cwd = workingDir ?? process.cwd();

  // Check for path traversal attempts
  if (filePath.includes('..')) {
    return ['', ERROR_PATH_TRAVERSAL.replace('{}', filePath)];
  }

  // Resolve to absolute path
  let absPath: string;
  if (filePath.startsWith('/')) {
    absPath = filePath;
  } else {
    absPath = resolve(cwd, filePath);
  }

  // Normalize the path
  absPath = resolve(absPath);

  // Ensure path is within working directory
  const relPath = relative(cwd, absPath);
  if (relPath.startsWith('..') || relPath.startsWith('/')) {
    return ['', ERROR_FILE_OUTSIDE_CWD.replace('{}', filePath)];
  }

  return [absPath, null];
}

/**
 * Resolve and validate a file path, following symlinks.
 * This is the secure version that prevents symlink-based path traversal.
 *
 * @param filePath - The file path to validate
 * @param workingDir - The working directory (defaults to cwd)
 * @returns Tuple of [resolvedPath, errorMessage]
 */
export async function resolveAndValidatePathSecure(
  filePath: string,
  workingDir?: string
): Promise<[string, string | null]> {
  const cwd = workingDir ?? process.cwd();

  // First do basic validation
  const [absPath, basicError] = resolveAndValidatePath(filePath, workingDir);
  if (basicError) {
    return ['', basicError];
  }

  // Resolve the real path of the working directory (in case it's a symlink)
  let realCwd: string;
  try {
    realCwd = await realpath(cwd);
  } catch {
    realCwd = cwd;
  }

  // Check if the file exists and resolve its real path
  try {
    const realAbsPath = await realpath(absPath);

    // Check if the real path is within the real working directory
    const relPath = relative(realCwd, realAbsPath);
    if (relPath.startsWith('..') || relPath.startsWith('/')) {
      return ['', ERROR_SYMLINK_ESCAPE.replace('{}', filePath)];
    }

    return [realAbsPath, null];
  } catch (error) {
    // File doesn't exist yet - check the parent directory
    const parentPath = resolve(absPath, '..');

    try {
      const realParentPath = await realpath(parentPath);
      const relParentPath = relative(realCwd, realParentPath);

      if (relParentPath.startsWith('..') || relParentPath.startsWith('/')) {
        return ['', ERROR_SYMLINK_ESCAPE.replace('{}', filePath)];
      }

      // Parent is safe, return the original resolved path
      return [absPath, null];
    } catch {
      // Parent doesn't exist either, return the original path
      // (operation will fail later with proper error)
      return [absPath, null];
    }
  }
}

/**
 * Check if a file exists.
 */
export async function fileExists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath);
    return true;
  } catch {
    return false;
  }
}

/**
 * Ensure a directory exists, creating it if necessary.
 */
export async function ensureDir(dirPath: string): Promise<void> {
  try {
    await mkdir(dirPath, { recursive: true });
  } catch (error) {
    // Ignore if directory already exists
    if ((error as NodeJS.ErrnoException).code !== 'EEXIST') {
      throw error;
    }
  }
}

/**
 * Get relative path from working directory.
 */
export function getRelativePath(absPath: string, workingDir?: string): string {
  const cwd = workingDir ?? process.cwd();
  try {
    return relative(cwd, absPath);
  } catch {
    return absPath;
  }
}

/**
 * Truncate long lines in text.
 *
 * @param text - Text to truncate
 * @param maxLineLength - Maximum characters per line
 * @returns Truncated text
 */
export function truncateLongLines(text: string, maxLineLength: number = 2000): string {
  return text
    .split('\n')
    .map((line) => {
      if (line.length > maxLineLength) {
        return `${line.slice(0, maxLineLength)}... [truncated]`;
      }
      return line;
    })
    .join('\n');
}
