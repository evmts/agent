/**
 * Agent tools - all tools aggregated for use with Vercel AI SDK.
 */

// Re-export individual tools
export { grepTool, grepImpl, createGrepTool } from './grep';
export { readFileTool, readFileImpl, createReadFileTool } from './read-file';
export { writeFileTool, writeFileImpl, createWriteFileTool } from './write-file';
export { multieditTool, multieditImpl, createMultieditTool } from './multiedit';
export { webFetchTool, webFetchImpl } from './web-fetch';
export { githubTool, githubImpl, validateCommand } from './github';

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
  resolveAndValidatePathSecure,
  fileExists,
  ensureDir,
  getRelativePath,
  truncateLongLines,
} from './filesystem';

// Re-export tool call tracker
export {
  ToolCallTracker,
  getToolCallTracker,
  setToolCallTracker,
  type ToolCall,
  type DuplicateCheck,
} from './tracker';

// Import all tools for aggregation
import { grepTool, createGrepTool } from './grep';
import { readFileTool, createReadFileTool } from './read-file';
import { writeFileTool, createWriteFileTool } from './write-file';
import { multieditTool, createMultieditTool } from './multiedit';
import { webFetchTool } from './web-fetch';
import { githubTool } from './github';
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
  github: githubTool,
  unifiedExec: unifiedExecTool,
  writeStdin: writeStdinTool,
  closePtySession: closePtySessionTool,
  listPtySessions: listPtySessionsTool,
};

export type AgentToolName = keyof typeof agentTools;

/**
 * Tool context for passing sessionId and workingDir to tools.
 */
export interface ToolContext {
  sessionId: string;
  workingDir: string;
}

/**
 * Create tools with context (sessionId and workingDir) bound to them.
 * This allows tools to access read-before-write safety and proper path resolution.
 */
export function createToolsWithContext(context: ToolContext): typeof agentTools {
  return {
    grep: createGrepTool(context),
    readFile: createReadFileTool(context),
    writeFile: createWriteFileTool(context),
    multiedit: createMultieditTool(context),
    webFetch: webFetchTool, // No context needed
    github: githubTool, // No context needed
    unifiedExec: unifiedExecTool, // Has its own context handling
    writeStdin: writeStdinTool, // Has its own context handling
    closePtySession: closePtySessionTool, // Has its own context handling
    listPtySessions: listPtySessionsTool, // Has its own context handling
  };
}
