/**
 * Agent tools - all tools aggregated for use with Vercel AI SDK.
 */

// Re-export individual tools
export { grepTool, grepImpl } from './grep';
export { readFileTool, readFileImpl } from './read-file';
export { writeFileTool, writeFileImpl } from './write-file';
export { multieditTool, multieditImpl } from './multiedit';
export { webFetchTool, webFetchImpl } from './web-fetch';

// Re-export PTY tools
export {
  unifiedExecTool,
  writeStdinTool,
  closePtySessionTool,
  listPtySessionsTool,
  unifiedExecImpl,
  writeStdinImpl,
  closePtySessionImpl,
  listPtySessionsImpl,
} from './pty-exec';

// Re-export PTY manager
export {
  PTYManager,
  getPtyManager,
  setPtyManager,
  type PTYSession,
  type ProcessStatus,
  type SessionInfo,
} from './pty-manager';

// Re-export filesystem utilities
export {
  resolveAndValidatePath,
  fileExists,
  ensureDir,
  getRelativePath,
  truncateLongLines,
} from './filesystem';

// Import all tools for aggregation
import { grepTool } from './grep';
import { readFileTool } from './read-file';
import { writeFileTool } from './write-file';
import { multieditTool } from './multiedit';
import { webFetchTool } from './web-fetch';
import { unifiedExecTool, writeStdinTool, closePtySessionTool, listPtySessionsTool } from './pty-exec';

/**
 * All available agent tools.
 *
 * This object is passed to Vercel AI SDK's streamText or generateText.
 */
export const agentTools = {
  grep: grepTool,
  readFile: readFileTool,
  writeFile: writeFileTool,
  multiedit: multieditTool,
  webFetch: webFetchTool,
  unifiedExec: unifiedExecTool,
  writeStdin: writeStdinTool,
  closePtySession: closePtySessionTool,
  listPtySessions: listPtySessionsTool,
};

export type AgentToolName = keyof typeof agentTools;
