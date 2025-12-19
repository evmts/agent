/**
 * Read file tool with line truncation and safety features.
 */

import { tool } from 'ai';
import { z } from 'zod';
import { resolveAndValidatePath, fileExists } from './filesystem';
import { updateFileTracker } from '../../core/state';

// Constants
const DEFAULT_READ_LIMIT = 2000; // lines
const MAX_LINE_LENGTH = 2000; // characters

interface ReadFileResult {
  success: boolean;
  content?: string;
  error?: string;
  lineCount?: number;
  truncated?: boolean;
}

async function readFileImpl(
  filePath: string,
  offset?: number,
  limit?: number,
  workingDir?: string,
  sessionId?: string
): Promise<ReadFileResult> {
  // Validate path
  const [absPath, pathError] = resolveAndValidatePath(filePath, workingDir);
  if (pathError) {
    return { success: false, error: pathError };
  }

  // Check file exists
  if (!(await fileExists(absPath))) {
    return { success: false, error: `file not found: ${filePath}` };
  }

  try {
    const file = Bun.file(absPath);
    const text = await file.text();
    const lines = text.split('\n');

    // Track file read time for read-before-write safety
    if (sessionId) {
      const stats = await file.stat();
      await updateFileTracker(sessionId, absPath, Date.now(), stats.mtime.getTime());
    }

    // Apply offset and limit
    const startLine = offset ?? 0;
    const lineLimit = limit ?? DEFAULT_READ_LIMIT;
    const endLine = Math.min(startLine + lineLimit, lines.length);

    let selectedLines = lines.slice(startLine, endLine);
    const truncated = endLine < lines.length;

    // Truncate long lines
    selectedLines = selectedLines.map((line) => {
      if (line.length > MAX_LINE_LENGTH) {
        return `${line.slice(0, MAX_LINE_LENGTH)}... [truncated]`;
      }
      return line;
    });

    // Format with line numbers (cat -n style)
    const formatted = selectedLines
      .map((line, i) => {
        const lineNum = startLine + i + 1;
        const padding = ' '.repeat(Math.max(0, 6 - String(lineNum).length));
        return `${padding}${lineNum}\t${line}`;
      })
      .join('\n');

    return {
      success: true,
      content: formatted,
      lineCount: selectedLines.length,
      truncated,
    };
  } catch (error) {
    return {
      success: false,
      error: `Failed to read file: ${error}`,
    };
  }
}

const readFileParameters = z.object({
  filePath: z.string().describe('Absolute path to the file to read'),
  offset: z.number().optional().describe('Line number to start reading from (0-indexed)'),
  limit: z.number().optional().describe('Maximum number of lines to read'),
});

export const readFileTool = tool({
  description: `Read a file from the filesystem.

Returns file contents with line numbers. Supports offset and limit for large files.
By default reads up to 2000 lines. Lines longer than 2000 characters are truncated.

Use this tool to read source code, configuration files, and other text files.`,
  parameters: readFileParameters,
  // @ts-expect-error - Zod v4 type inference issue with AI SDK
  execute: async (args: z.infer<typeof readFileParameters>) => {
    const result = await readFileImpl(args.filePath, args.offset, args.limit);
    if (!result.success) {
      return `Error: ${result.error}`;
    }
    let output = result.content!;
    if (result.truncated) {
      output += `\n\n[Output truncated. Use offset parameter to read more.]`;
    }
    return output;
  },
});

export { readFileImpl };
