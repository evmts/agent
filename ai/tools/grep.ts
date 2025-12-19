/**
 * Grep tool with multiline pattern matching and pagination support.
 *
 * Uses ripgrep for efficient searching with support for multiline patterns
 * and paginated results.
 */

import { tool } from 'ai';
import { z } from 'zod';

// Constants
const DEFAULT_TIMEOUT_MS = 30000;
const DEFAULT_HEAD_LIMIT = 0; // 0 = unlimited

interface GrepMatch {
  type: 'match';
  path: string;
  lineNumber: number;
  text: string;
  absoluteOffset?: number;
  submatches?: Array<{ start: number; end: number }>;
}

interface GrepResult {
  success: boolean;
  matches?: GrepMatch[];
  formattedOutput?: string;
  error?: string;
  truncated?: boolean;
  totalCount?: number;
}

async function grepImpl(
  pattern: string,
  path?: string,
  glob?: string,
  multiline?: boolean,
  caseInsensitive?: boolean,
  maxCount?: number,
  contextBefore?: number,
  contextAfter?: number,
  contextLines?: number,
  headLimit?: number,
  offset?: number,
  workingDir?: string
): Promise<GrepResult> {
  // Build ripgrep arguments
  const args: string[] = [
    '--json',
    '--hidden',
    '--glob=!.git/*',
  ];

  if (multiline) {
    args.push('-U', '--multiline-dotall');
  }

  if (caseInsensitive) {
    args.push('-i');
  }

  // Context lines (-C takes precedence)
  if (contextLines !== undefined && contextLines > 0) {
    args.push(`-C${contextLines}`);
  } else {
    if (contextAfter !== undefined && contextAfter > 0) {
      args.push(`-A${contextAfter}`);
    }
    if (contextBefore !== undefined && contextBefore > 0) {
      args.push(`-B${contextBefore}`);
    }
  }

  if (glob) {
    args.push(`--glob=${glob}`);
  }

  if (maxCount !== undefined && maxCount > 0) {
    args.push(`--max-count=${maxCount}`);
  }

  args.push(pattern);

  if (path) {
    args.push(path);
  }

  try {
    const proc = Bun.spawn(['rg', ...args], {
      cwd: workingDir ?? process.cwd(),
      stdout: 'pipe',
      stderr: 'pipe',
    });

    const stdout = await new Response(proc.stdout).text();
    const exitCode = await proc.exited;

    // No matches (exit code 1)
    if (exitCode === 1) {
      return {
        success: true,
        matches: [],
        formattedOutput: 'No matches found',
        truncated: false,
        totalCount: 0,
      };
    }

    // Error (exit code != 0 and != 1)
    if (exitCode !== 0) {
      const stderr = await new Response(proc.stderr).text();
      return {
        success: false,
        error: stderr.trim() || 'Unknown error',
      };
    }

    // Parse JSON output
    const lines = stdout.trim().split('\n');
    const matches: GrepMatch[] = [];

    for (const line of lines) {
      if (!line) continue;
      try {
        const data = JSON.parse(line);
        if (data.type === 'match') {
          const matchData = data.data;
          matches.push({
            type: 'match',
            path: matchData.path.text,
            lineNumber: matchData.line_number,
            text: matchData.lines.text.replace(/\n$/, ''),
            absoluteOffset: matchData.absolute_offset,
            submatches: matchData.submatches,
          });
        }
      } catch {
        // Skip malformed JSON lines
      }
    }

    if (matches.length === 0) {
      return {
        success: true,
        matches: [],
        formattedOutput: 'No matches found',
        truncated: false,
        totalCount: 0,
      };
    }

    // Apply pagination
    const totalCount = matches.length;
    let paginatedMatches = matches;

    if (offset !== undefined && offset > 0) {
      paginatedMatches = paginatedMatches.slice(offset);
    }

    let truncated = false;
    const limit = headLimit ?? DEFAULT_HEAD_LIMIT;
    if (limit > 0 && paginatedMatches.length > limit) {
      paginatedMatches = paginatedMatches.slice(0, limit);
      truncated = true;
    }

    // Format output
    const formattedOutput = formatMatches(paginatedMatches, multiline ?? false, totalCount, offset ?? 0, limit, truncated);

    return {
      success: true,
      matches: paginatedMatches,
      formattedOutput,
      truncated,
      totalCount,
    };
  } catch (error) {
    if (error instanceof Error && error.message.includes('ENOENT')) {
      return {
        success: false,
        error: 'ripgrep (rg) not found in PATH. Please install ripgrep.',
      };
    }
    return {
      success: false,
      error: `Unexpected error: ${error}`,
    };
  }
}

function formatMatches(
  matches: GrepMatch[],
  multiline: boolean,
  totalCount: number,
  offset: number,
  headLimit: number,
  truncated: boolean
): string {
  const lines: string[] = [
    `Found ${matches.length} match${matches.length !== 1 ? 'es' : ''}`,
  ];

  if (offset > 0 || headLimit > 0) {
    if (truncated) {
      lines.push(`(showing matches ${offset + 1}-${offset + matches.length} of ${totalCount} total)`);
    } else if (offset > 0) {
      lines.push(`(showing matches ${offset + 1}-${offset + matches.length} of ${totalCount} total)`);
    }
  }

  if (multiline) {
    lines.push('(multiline mode enabled)');
  }

  lines.push('');

  let currentFile = '';
  for (const match of matches) {
    if (currentFile !== match.path) {
      if (currentFile) lines.push('');
      currentFile = match.path;
      lines.push(`${match.path}:`);
    }

    if (multiline && match.text.includes('\n')) {
      const textLines = match.text.split('\n');
      const lastLineNum = match.lineNumber + textLines.length - 1;
      lines.push(`  Lines ${match.lineNumber}-${lastLineNum}:`);
      textLines.forEach((textLine, i) => {
        lines.push(`    ${match.lineNumber + i}: ${textLine}`);
      });
    } else {
      lines.push(`  Line ${match.lineNumber}: ${match.text}`);
    }
  }

  if (truncated && headLimit > 0) {
    lines.push('');
    lines.push(`(Output truncated to first ${headLimit} matches. Use offset parameter to see more results.)`);
  }

  return lines.join('\n');
}

const grepParameters = z.object({
  pattern: z.string().describe('Regular expression pattern to search for'),
  path: z.string().optional().describe('Directory or file to search in (defaults to working directory)'),
  glob: z.string().optional().describe('File pattern filter (e.g., "*.ts", "*.{js,jsx}")'),
  multiline: z.boolean().optional().describe('Enable multiline mode where . matches newlines'),
  caseInsensitive: z.boolean().optional().describe('Case-insensitive search'),
  maxCount: z.number().optional().describe('Maximum matches per file'),
  contextBefore: z.number().optional().describe('Lines to show before each match'),
  contextAfter: z.number().optional().describe('Lines to show after each match'),
  contextLines: z.number().optional().describe('Lines before AND after (takes precedence)'),
  headLimit: z.number().optional().describe('Limit output to first N matches (0 = unlimited)'),
  offset: z.number().optional().describe('Skip first N matches'),
});

export const grepTool = tool({
  description: `Search for patterns in files using ripgrep.

Supports regular expressions, multiline matching, and pagination for large result sets.

Examples:
- Search for a function: pattern="def authenticate", glob="*.py"
- Multiline search: pattern="function.*\\{", multiline=true
- Paginated results: headLimit=10, offset=0 (first page), offset=10 (second page)`,
  parameters: grepParameters,
  // @ts-expect-error - Zod v4 type inference issue with AI SDK
  execute: async (args: z.infer<typeof grepParameters>) => {
    const result = await grepImpl(
      args.pattern,
      args.path,
      args.glob,
      args.multiline,
      args.caseInsensitive,
      args.maxCount,
      args.contextBefore,
      args.contextAfter,
      args.contextLines,
      args.headLimit,
      args.offset
    );
    return result.success
      ? result.formattedOutput!
      : `Error: ${result.error}`;
  },
});

export { grepImpl };
