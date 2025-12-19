/**
 * Write file tool with read-before-write safety.
 */

import { tool } from 'ai';
import { z } from 'zod';
import { dirname } from 'path';
import { resolveAndValidatePath, ensureDir, fileExists } from './filesystem';
import { getFileTracker, updateFileTracker } from '../../core/state';

interface WriteFileResult {
  success: boolean;
  error?: string;
  created?: boolean;
}

async function writeFileImpl(
  filePath: string,
  content: string,
  workingDir?: string,
  sessionId?: string
): Promise<WriteFileResult> {
  // Validate path
  const [absPath, pathError] = resolveAndValidatePath(filePath, workingDir);
  if (pathError) {
    return { success: false, error: pathError };
  }

  // Check read-before-write safety
  if (sessionId) {
    const tracker = await getFileTracker(sessionId);
    const exists = await fileExists(absPath);

    if (exists) {
      // File exists - must have been read first
      const lastRead = tracker.readTimes.get(absPath);
      if (!lastRead) {
        return {
          success: false,
          error: 'File has not been read in this session. Read the file first before writing.',
        };
      }

      // Check if file was modified since last read
      const file = Bun.file(absPath);
      const stats = await file.stat();
      const lastMod = tracker.modTimes.get(absPath);

      if (lastMod && stats.mtime.getTime() > lastMod) {
        return {
          success: false,
          error: 'File has been modified since it was last read. Read the file again.',
        };
      }
    }
  }

  try {
    // Ensure parent directory exists
    await ensureDir(dirname(absPath));

    const existed = await fileExists(absPath);

    // Write file
    await Bun.write(absPath, content);

    // Update tracker
    if (sessionId) {
      const file = Bun.file(absPath);
      const stats = await file.stat();
      await updateFileTracker(sessionId, absPath, Date.now(), stats.mtime.getTime());
    }

    return {
      success: true,
      created: !existed,
    };
  } catch (error) {
    return {
      success: false,
      error: `Failed to write file: ${error}`,
    };
  }
}

export const writeFileTool = tool({
  description: `Write content to a file.

Creates the file if it doesn't exist, or overwrites if it does.
Parent directories are created automatically if needed.

IMPORTANT: You must read existing files with the readFile tool before overwriting them.
This ensures you understand the file's contents before making changes.`,
  parameters: z.object({
    filePath: z.string().describe('Absolute path to the file to write'),
    content: z.string().describe('Content to write to the file'),
  }),
  execute: async (args) => {
    const result = await writeFileImpl(args.filePath, args.content);
    if (!result.success) {
      return `Error: ${result.error}`;
    }
    return result.created
      ? `Created file: ${args.filePath}`
      : `Updated file: ${args.filePath}`;
  },
});

export { writeFileImpl };
