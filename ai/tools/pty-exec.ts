/**
 * PTY execution tools for interactive command execution.
 *
 * Provides tools for running commands in pseudo-terminal sessions
 * and interacting with them via stdin.
 */

import { tool } from '../../node_modules/ai/dist/index.mjs';
import { z } from 'zod';
import { getPtyManager, type SessionInfo } from './pty-manager';

// Constants
const DEFAULT_YIELD_TIME_MS = 100;
const DEFAULT_MAX_OUTPUT_TOKENS = 10000;
const MAX_OUTPUT_CHARS = 50000;

function _estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}

function truncateOutput(text: string, maxTokens: number): [string, boolean] {
  const maxChars = maxTokens * 4;
  if (text.length > maxChars) {
    return [`${text.slice(0, maxChars)}\n[Output truncated]`, true];
  }
  return [text, false];
}

interface ExecResult {
  success: boolean;
  sessionId?: string;
  output?: string;
  running?: boolean;
  exitCode?: number | null;
  error?: string;
  truncated?: boolean;
}

/**
 * Run a command in an interactive PTY session.
 */
async function unifiedExecImpl(
  cmd: string,
  workdir?: string,
  shell?: string,
  login?: boolean,
  yieldTimeMs?: number,
  maxOutputTokens?: number
): Promise<ExecResult> {
  const manager = getPtyManager();
  const timeout = yieldTimeMs ?? DEFAULT_YIELD_TIME_MS;
  const maxTokens = maxOutputTokens ?? DEFAULT_MAX_OUTPUT_TOKENS;

  try {
    // Create PTY session
    const session = await manager.createSession({
      cmd,
      workdir,
      shell,
      login,
    });

    // Wait for initial output
    let output = await manager.readOutput(session.id, timeout, MAX_OUTPUT_CHARS);

    // Truncate to token limit
    let truncated: boolean;
    [output, truncated] = truncateOutput(output, maxTokens);

    // Check process status
    const status = manager.getProcessStatus(session.id);

    return {
      success: true,
      sessionId: session.id,
      output,
      running: status.running,
      exitCode: status.exitCode,
      truncated,
    };
  } catch (error) {
    return {
      success: false,
      error: String(error),
    };
  }
}

/**
 * Write input to a running PTY session.
 */
async function writeStdinImpl(
  sessionId: string,
  chars: string,
  yieldTimeMs?: number,
  maxOutputTokens?: number
): Promise<ExecResult> {
  const manager = getPtyManager();
  const timeout = yieldTimeMs ?? DEFAULT_YIELD_TIME_MS;
  const maxTokens = maxOutputTokens ?? DEFAULT_MAX_OUTPUT_TOKENS;

  try {
    // Write input to session
    if (chars) {
      await manager.writeInput(sessionId, chars);
    }

    // Wait for output
    let output = await manager.readOutput(sessionId, timeout, MAX_OUTPUT_CHARS);

    // Truncate to token limit
    let truncated: boolean;
    [output, truncated] = truncateOutput(output, maxTokens);

    // Check process status
    const status = manager.getProcessStatus(sessionId);

    return {
      success: true,
      output,
      running: status.running,
      exitCode: status.exitCode,
      truncated,
    };
  } catch (error) {
    if (String(error).includes('not found')) {
      return {
        success: false,
        error: `Session ${sessionId} not found`,
      };
    }
    return {
      success: false,
      error: String(error),
    };
  }
}

/**
 * Close a PTY session.
 */
async function closePtySessionImpl(
  sessionId: string,
  force?: boolean
): Promise<{ success: boolean; error?: string }> {
  const manager = getPtyManager();

  try {
    await manager.closeSession(sessionId, force);
    return { success: true };
  } catch (error) {
    if (String(error).includes('not found')) {
      return {
        success: false,
        error: `Session ${sessionId} not found`,
      };
    }
    return {
      success: false,
      error: String(error),
    };
  }
}

/**
 * List all active PTY sessions.
 */
function listPtySessionsImpl(): { success: boolean; sessions: SessionInfo[] } {
  const manager = getPtyManager();
  return {
    success: true,
    sessions: manager.listSessions(),
  };
}

// Tool definitions

const unifiedExecParameters = z.object({
  cmd: z.string().describe('Command to execute'),
  workdir: z.string().optional().describe('Working directory'),
  shell: z.string().optional().describe('Shell to use (defaults to $SHELL)'),
  login: z.boolean().optional().describe('Use login shell'),
  yieldTimeMs: z.number().optional().describe('Time to wait for output (default: 100ms)'),
  maxOutputTokens: z.number().optional().describe('Max output tokens (default: 10000)'),
});

export const unifiedExecTool = tool({
  description: `Run a command in an interactive PTY session.

Starts a command in a pseudo-terminal and returns initial output along with a session ID
for follow-up interactions via writeStdin.

Use this for:
- Interactive programs (python, node REPL)
- Commands that need stdin input
- Long-running processes

Returns a session_id that can be used with writeStdin to send input.`,
  parameters: unifiedExecParameters,
  // @ts-expect-error - Zod v4 type inference issue with AI SDK
  execute: async (args: z.infer<typeof unifiedExecParameters>) => {
    const result = await unifiedExecImpl(
      args.cmd,
      args.workdir,
      args.shell,
      args.login,
      args.yieldTimeMs,
      args.maxOutputTokens
    );

    if (!result.success) {
      return `Error: ${result.error}`;
    }

    return JSON.stringify({
      sessionId: result.sessionId,
      output: result.output,
      running: result.running,
      exitCode: result.exitCode,
      truncated: result.truncated,
    });
  },
});

const writeStdinParameters = z.object({
  sessionId: z.string().describe('PTY session ID from unifiedExec'),
  chars: z.string().describe('Characters to write (use \\n for newline, \\x03 for Ctrl+C)'),
  yieldTimeMs: z.number().optional().describe('Time to wait for output (default: 100ms)'),
  maxOutputTokens: z.number().optional().describe('Max output tokens (default: 10000)'),
});

export const writeStdinTool = tool({
  description: `Write input to a running PTY session.

Sends input to a session started with unifiedExec and returns any new output.
Include \\n for newlines to submit commands.

Examples:
- Send a command: chars="print('hello')\\n"
- Send Ctrl+C: chars="\\x03"
- Send Ctrl+D: chars="\\x04"`,
  parameters: writeStdinParameters,
  // @ts-expect-error - Zod v4 type inference issue with AI SDK
  execute: async (args: z.infer<typeof writeStdinParameters>) => {
    const result = await writeStdinImpl(
      args.sessionId,
      args.chars,
      args.yieldTimeMs,
      args.maxOutputTokens
    );

    if (!result.success) {
      return `Error: ${result.error}`;
    }

    return JSON.stringify({
      output: result.output,
      running: result.running,
      exitCode: result.exitCode,
      truncated: result.truncated,
    });
  },
});

const closePtySessionParameters = z.object({
  sessionId: z.string().describe('PTY session ID to close'),
  force: z.boolean().optional().describe('Force kill with SIGKILL (default: false)'),
});

export const closePtySessionTool = tool({
  description: `Close a PTY session.

Terminates the process and cleans up resources.
Use force=true to send SIGKILL instead of SIGTERM.`,
  parameters: closePtySessionParameters,
  // @ts-expect-error - Zod v4 type inference issue with AI SDK
  execute: async (args: z.infer<typeof closePtySessionParameters>) => {
    const result = await closePtySessionImpl(args.sessionId, args.force);
    return result.success
      ? `Session ${args.sessionId} closed`
      : `Error: ${result.error}`;
  },
});

const listPtySessionsParameters = z.object({});

export const listPtySessionsTool = tool({
  description: `List all active PTY sessions.

Shows session IDs, commands, and status of all running sessions.`,
  parameters: listPtySessionsParameters,
  // @ts-expect-error - Zod v4 type inference issue with AI SDK
  execute: async (_args: z.infer<typeof listPtySessionsParameters>) => {
    const result = listPtySessionsImpl();
    if (result.sessions.length === 0) {
      return 'No active PTY sessions';
    }

    const lines = result.sessions.map((s) => {
      const status = s.running ? 'running' : `exited`;
      return `- ${s.id}: ${s.command} (${status}, workdir: ${s.workdir})`;
    });

    return `Active PTY sessions:\n${lines.join('\n')}`;
  },
});

export {
  unifiedExecImpl,
  writeStdinImpl,
  closePtySessionImpl,
  listPtySessionsImpl,
};
