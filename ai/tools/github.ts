/**
 * GitHub CLI wrapper tool with whitelisted safe operations.
 *
 * Wraps the `gh` CLI to provide safe GitHub operations for the agent.
 * Only allows specific commands to prevent destructive actions.
 */

import { tool } from '../../node_modules/ai/dist/index.mjs';
import { z } from 'zod';

// Whitelisted gh subcommands and their allowed operations
const ALLOWED_COMMANDS: Record<string, string[]> = {
  pr: ['create', 'list', 'view', 'checkout', 'status', 'diff', 'checks'],
  issue: ['create', 'list', 'view', 'status'],
  repo: ['clone', 'view', 'sync'],
  run: ['list', 'view', 'watch'],
  workflow: ['list', 'view'],
};

// Commands that are explicitly blocked (even if they match patterns above)
const BLOCKED_PATTERNS = [
  'delete',
  'close',
  'merge',      // PR merging should be done through Plue UI
  'auth',
  'config',
  'secret',
  'variable',
  '--force',
  '-f',
];

interface GithubResult {
  success: boolean;
  output?: string;
  error?: string;
  exitCode?: number;
}

/**
 * Validate that a gh command is allowed.
 */
function validateCommand(args: string[]): { valid: boolean; reason?: string } {
  if (args.length === 0) {
    return { valid: false, reason: 'No command provided' };
  }

  const subcommand = args[0];
  const operation = args[1];

  // Check for blocked patterns anywhere in args
  const argsString = args.join(' ').toLowerCase();
  for (const blocked of BLOCKED_PATTERNS) {
    if (argsString.includes(blocked.toLowerCase())) {
      return { valid: false, reason: `Blocked pattern: ${blocked}` };
    }
  }

  // Check if subcommand is allowed
  const allowedOps = ALLOWED_COMMANDS[subcommand];
  if (!allowedOps) {
    return {
      valid: false,
      reason: `Subcommand '${subcommand}' not allowed. Allowed: ${Object.keys(ALLOWED_COMMANDS).join(', ')}`
    };
  }

  // Check if operation is allowed for this subcommand
  if (operation && !allowedOps.includes(operation)) {
    return {
      valid: false,
      reason: `Operation '${operation}' not allowed for '${subcommand}'. Allowed: ${allowedOps.join(', ')}`
    };
  }

  return { valid: true };
}

/**
 * Execute a gh CLI command.
 */
async function githubImpl(
  args: string[],
  workingDir?: string
): Promise<GithubResult> {
  // Validate the command
  const validation = validateCommand(args);
  if (!validation.valid) {
    return {
      success: false,
      error: `Command not allowed: ${validation.reason}`,
    };
  }

  try {
    const proc = Bun.spawn(['gh', ...args], {
      cwd: workingDir ?? process.cwd(),
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        ...process.env,
        // Disable interactive prompts
        GH_PROMPT_DISABLED: '1',
      },
    });

    const [stdout, stderr] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    const exitCode = await proc.exited;

    if (exitCode !== 0) {
      return {
        success: false,
        output: stdout.trim(),
        error: stderr.trim() || `Command failed with exit code ${exitCode}`,
        exitCode,
      };
    }

    return {
      success: true,
      output: stdout.trim(),
      exitCode: 0,
    };
  } catch (error) {
    if (error instanceof Error && error.message.includes('ENOENT')) {
      return {
        success: false,
        error: 'GitHub CLI (gh) not found. Please install: https://cli.github.com/',
      };
    }
    return {
      success: false,
      error: `Unexpected error: ${error}`,
    };
  }
}

const githubParameters = z.object({
  command: z.string().describe(
    `The gh CLI command to run (without the 'gh' prefix).
Examples:
- "pr create --title 'Fix bug' --body 'Description'"
- "pr list --state open"
- "pr view 123"
- "issue create --title 'Bug report' --body 'Details'"
- "repo clone owner/repo"
- "run list --limit 5"`
  ),
  workingDir: z.string().optional().describe('Working directory for the command'),
});

export const githubTool = tool({
  description: `Execute GitHub CLI (gh) commands safely.

Allowed operations:
- pr: create, list, view, checkout, status, diff, checks
- issue: create, list, view, status
- repo: clone, view, sync
- run: list, view, watch (CI/CD)
- workflow: list, view

Blocked operations: delete, close, merge, auth, config, secrets

Prerequisites:
- gh CLI must be installed
- User must be authenticated (gh auth login)

Examples:
- Create PR: command="pr create --title 'Fix bug' --body 'Fixes issue #123'"
- List open PRs: command="pr list --state open"
- View PR checks: command="pr checks 123"
- Clone repo: command="repo clone owner/repo"`,
  parameters: githubParameters,
  // @ts-expect-error - Zod v4 type inference issue with AI SDK
  execute: async (args: { command: string; workingDir?: string }) => {
    // Split command string into args array
    const cmdArgs = parseCommandArgs(args.command);

    const result = await githubImpl(cmdArgs, args.workingDir);

    if (result.success) {
      return result.output || 'Command completed successfully';
    }

    let errorMsg = `Error: ${result.error}`;
    if (result.output) {
      errorMsg += `\n\nOutput:\n${result.output}`;
    }
    return errorMsg;
  },
});

/**
 * Parse a command string into an array of arguments.
 * Handles quoted strings properly.
 */
function parseCommandArgs(command: string): string[] {
  const args: string[] = [];
  let current = '';
  let inQuote: string | null = null;

  for (let i = 0; i < command.length; i++) {
    const char = command[i];

    if (inQuote) {
      if (char === inQuote) {
        inQuote = null;
      } else {
        current += char;
      }
    } else if (char === '"' || char === "'") {
      inQuote = char;
    } else if (char === ' ') {
      if (current) {
        args.push(current);
        current = '';
      }
    } else {
      current += char;
    }
  }

  if (current) {
    args.push(current);
  }

  return args;
}

export { githubImpl, validateCommand };
