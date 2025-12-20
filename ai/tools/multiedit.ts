/**
 * MultiEdit tool for performing multiple string replacements atomically.
 *
 * Allows multiple find-replace operations on a single file in one atomic operation.
 * Each edit is applied in sequence, with subsequent edits operating on the result
 * of previous edits.
 */

import { tool } from '../../node_modules/ai/dist/index.mjs';
import { z } from 'zod';
import { resolveAndValidatePathSecure, getRelativePath, fileExists } from './filesystem';
import { getFileTracker, updateFileTracker } from '../../core/state';

// Error messages
const ERROR_FILE_PATH_REQUIRED = 'file_path parameter is required';
const _ERROR_EDITS_REQUIRED = 'edits parameter is required and must be an array';
const ERROR_EDITS_EMPTY = 'edits array cannot be empty';
const ERROR_EDIT_INVALID = 'edit at index {} is not a valid object';
const ERROR_EDIT_MISSING_OLD = 'edit at index {} is missing old_string';
const ERROR_EDIT_MISSING_NEW = 'edit at index {} is missing new_string';
const ERROR_EDIT_SAME_OLD_NEW = 'edit at index {} has identical old_string and new_string';
const ERROR_EDIT_FAILED = 'edit {} failed: {}';
const ERROR_OLD_STRING_NOT_FOUND = 'old_string not found in file content';
const ERROR_OLD_STRING_MULTIPLE = 'old_string found multiple times - use replace_all or provide more context';

interface EditOperation {
  oldString: string;
  newString: string;
  replaceAll: boolean;
}

interface MultiEditResult {
  success: boolean;
  filePath: string;
  editCount: number;
  error?: string;
  output?: string;
}

function validateEdits(edits: Array<{ oldString: string; newString: string; replaceAll?: boolean }>): [EditOperation[], string | null] {
  if (!edits || edits.length === 0) {
    return [[], ERROR_EDITS_EMPTY];
  }

  const operations: EditOperation[] = [];

  for (let i = 0; i < edits.length; i++) {
    const edit = edits[i];

    if (!edit || typeof edit !== 'object') {
      return [[], ERROR_EDIT_INVALID.replace('{}', String(i))];
    }

    if (edit.oldString === undefined || edit.oldString === null) {
      return [[], ERROR_EDIT_MISSING_OLD.replace('{}', String(i))];
    }

    if (edit.newString === undefined || edit.newString === null) {
      return [[], ERROR_EDIT_MISSING_NEW.replace('{}', String(i))];
    }

    if (edit.oldString === edit.newString) {
      return [[], ERROR_EDIT_SAME_OLD_NEW.replace('{}', String(i))];
    }

    operations.push({
      oldString: edit.oldString,
      newString: edit.newString,
      replaceAll: edit.replaceAll ?? false,
    });
  }

  return [operations, null];
}

async function multieditImpl(
  filePath: string,
  edits: Array<{ oldString: string; newString: string; replaceAll?: boolean }>,
  workingDir?: string,
  sessionId?: string
): Promise<MultiEditResult> {
  // Validate file path
  if (!filePath) {
    return {
      success: false,
      filePath: '',
      editCount: 0,
      error: ERROR_FILE_PATH_REQUIRED,
    };
  }

  // Validate and resolve path (secure version that follows symlinks)
  const [absPath, pathError] = await resolveAndValidatePathSecure(filePath, workingDir);
  if (pathError) {
    return {
      success: false,
      filePath,
      editCount: 0,
      error: pathError,
    };
  }

  // Validate edits
  const [operations, validationError] = validateEdits(edits);
  if (validationError) {
    return {
      success: false,
      filePath,
      editCount: 0,
      error: validationError,
    };
  }

  const relPath = getRelativePath(absPath, workingDir);

  // Check read-before-write for existing files
  if (sessionId && await fileExists(absPath)) {
    try {
      const tracker = await getFileTracker(sessionId);
      const lastRead = tracker.readTimes.get(absPath);
      if (!lastRead) {
        return {
          success: false,
          filePath: relPath,
          editCount: 0,
          error: 'File has not been read in this session. Read the file first.',
        };
      }
    } catch (error) {
      // If session doesn't exist, skip the check
      console.warn('Failed to get file tracker:', error);
    }
  }

  try {
    // Read current content (or start with empty for new files)
    let content = '';
    const exists = await fileExists(absPath);

    if (exists) {
      const file = Bun.file(absPath);
      content = await file.text();
    }

    // Apply edits sequentially
    for (let i = 0; i < operations.length; i++) {
      const op = operations[i]!;

      // Handle file creation (empty oldString on first edit)
      if (op.oldString === '' && !exists && i === 0) {
        content = op.newString;
        continue;
      }

      // Reject empty oldString on existing files
      if (op.oldString === '' && exists) {
        // Write any successful edits before returning error
        if (i > 0) {
          await Bun.write(absPath, content);
        }
        return {
          success: false,
          filePath: relPath,
          editCount: i,
          error: ERROR_EDIT_FAILED.replace('{}', String(i + 1)).replace('{}', 'empty old_string not allowed on existing files'),
        };
      }

      // Check if oldString exists
      const occurrences = content.split(op.oldString).length - 1;

      if (occurrences === 0) {
        // Write any successful edits before returning error
        if (i > 0) {
          await Bun.write(absPath, content);
        }
        return {
          success: false,
          filePath: relPath,
          editCount: i,
          error: ERROR_EDIT_FAILED.replace('{}', String(i + 1)).replace('{}', ERROR_OLD_STRING_NOT_FOUND),
        };
      }

      // Apply the edit
      if (op.replaceAll) {
        content = content.split(op.oldString).join(op.newString);
      } else {
        // Always replace first occurrence, don't error on multiple
        content = content.replace(op.oldString, op.newString);
      }
    }

    // Write the result
    await Bun.write(absPath, content);

    // Update tracker
    if (sessionId) {
      try {
        const file = Bun.file(absPath);
        const stats = await file.stat();
        await updateFileTracker(sessionId, absPath, Date.now(), stats.mtime.getTime());
      } catch (error) {
        // Ignore tracker update errors - don't fail the operation
        console.warn('Failed to update file tracker:', error);
      }
    }

    return {
      success: true,
      filePath: relPath,
      editCount: operations.length,
      output: `Applied ${operations.length} edit(s) to ${relPath}`,
    };
  } catch (error) {
    return {
      success: false,
      filePath: relPath,
      editCount: 0,
      error: `Failed to apply edits: ${error}`,
    };
  }
}

const multieditParameters = z.object({
  filePath: z.string().describe('Absolute path to the file to modify'),
  edits: z.array(z.object({
    oldString: z.string().describe('Text to replace (must match exactly)'),
    newString: z.string().describe('Replacement text'),
    replaceAll: z.boolean().optional().describe('Replace all occurrences (default: false)'),
  })).describe('Array of edit operations to apply sequentially'),
});

export const multieditTool = tool({
  description: `Perform multiple find-and-replace operations on a single file atomically.

All edits are validated before any are applied. Each edit operates on the result
of the previous edit, allowing dependent changes.

IMPORTANT:
- Read the file first before using this tool
- old_string must match exactly (including whitespace)
- Edits are applied in sequence - plan carefully to avoid conflicts

To create a new file: use empty old_string with the file contents as new_string.`,
  parameters: multieditParameters,
  // @ts-expect-error - Zod v4 type inference issue with AI SDK
  execute: async (args: z.infer<typeof multieditParameters>) => {
    const result = await multieditImpl(args.filePath, args.edits);
    return result.success
      ? result.output!
      : `Error: ${result.error}`;
  },
});

/**
 * Create a multiedit tool with context (sessionId and workingDir) bound to it.
 */
export function createMultieditTool(context: { sessionId: string; workingDir: string }) {
  return tool({
    description: multieditTool.description,
    parameters: multieditParameters,
    // @ts-expect-error - Zod v4 type inference issue with AI SDK
    execute: async (args: z.infer<typeof multieditParameters>) => {
      const result = await multieditImpl(
        args.filePath,
        args.edits,
        context.workingDir,
        context.sessionId
      );
      return result.success
        ? result.output!
        : `Error: ${result.error}`;
    },
  });
}

export { multieditImpl };
