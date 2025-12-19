#!/usr/bin/env bun
/**
 * Headless exec mode for Plue TUI.
 *
 * Usage:
 *   plue exec "your prompt here"
 *   echo "your prompt" | plue exec
 *   plue exec -f prompt.txt
 */

import pc from 'picocolors';
import { PlueClient, } from './client';

export interface ExecOptions {
  apiUrl: string;
  sessionId?: string;
  model?: string;
  outputFormat: 'text' | 'json' | 'stream';
  timeout?: number;
}

export interface ExecResult {
  success: boolean;
  sessionId: string;
  text: string;
  toolCalls: Array<{
    name: string;
    input: Record<string, any>;
    output?: string;
  }>;
  error?: string;
  duration: number;
}

/**
 * Run a single prompt in headless mode
 */
export async function exec(
  prompt: string,
  options: ExecOptions
): Promise<ExecResult> {
  const startTime = Date.now();
  const client = new PlueClient(options.apiUrl, options.timeout || 60000);

  const result: ExecResult = {
    success: false,
    sessionId: '',
    text: '',
    toolCalls: [],
    duration: 0,
  };

  try {
    // Check server health first
    const healthy = await client.healthCheck();
    if (!healthy) {
      throw new Error(`Server not reachable at ${options.apiUrl}`);
    }

    // Get or create session
    let sessionId = options.sessionId;
    if (!sessionId) {
      if (options.outputFormat === 'stream') {
        console.error(pc.dim('Creating session...'));
      }
      const session = await client.createSession({
        directory: process.cwd(),
        model: options.model,
      });
      sessionId = session.id;
    }
    result.sessionId = sessionId;

    // Send message and collect response
    if (options.outputFormat === 'stream') {
      // Stream mode: output events as they arrive
      console.error(pc.dim(`Session: ${sessionId}`));
      console.error('');
    }

    let currentToolCall: { name: string; input: Record<string, any> } | null = null;

    for await (const event of client.sendMessage(sessionId, prompt, {
      model: options.model,
    })) {
      switch (event.type) {
        case 'part.updated': {
          const delta = event.properties.delta;
          if (delta) {
            result.text += delta;
            if (options.outputFormat === 'stream') {
              process.stdout.write(delta);
            }
          }
          break;
        }

        case 'tool.call': {
          currentToolCall = {
            name: event.properties.toolName,
            input: event.properties.input || {},
          };
          if (options.outputFormat === 'stream') {
            console.error(pc.cyan(`\n[tool: ${event.properties.toolName}]`));
          }
          break;
        }

        case 'tool.result': {
          if (currentToolCall) {
            result.toolCalls.push({
              ...currentToolCall,
              output: event.properties.output,
            });
            currentToolCall = null;
          }
          if (options.outputFormat === 'stream') {
            const preview = (event.properties.output || '').slice(0, 100);
            console.error(pc.dim(`[result: ${preview}${preview.length >= 100 ? '...' : ''}]`));
          }
          break;
        }

        case 'message.completed': {
          result.success = true;
          break;
        }

        case 'error': {
          result.error = event.properties.error;
          break;
        }
      }
    }

    if (options.outputFormat === 'stream') {
      console.log(''); // Final newline
    }

    result.success = !result.error;
  } catch (err: any) {
    result.error = err.message;
  }

  result.duration = Date.now() - startTime;
  return result;
}

/**
 * Parse exec command line arguments
 */
export function parseExecArgs(args: string[]): {
  prompt: string;
  options: Partial<ExecOptions>;
} {
  let prompt = '';
  const options: Partial<ExecOptions> = {
    outputFormat: 'text',
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    switch (arg) {
      case '-f':
      case '--file': {
        const file = args[++i];
        if (file) {
          prompt = Bun.file(file).text() as unknown as string;
        }
        break;
      }

      case '-s':
      case '--session': {
        options.sessionId = args[++i];
        break;
      }

      case '-m':
      case '--model': {
        options.model = args[++i];
        break;
      }

      case '--json': {
        options.outputFormat = 'json';
        break;
      }

      case '--stream': {
        options.outputFormat = 'stream';
        break;
      }

      case '--timeout': {
        options.timeout = parseInt(args[++i] || '60000', 10);
        break;
      }

      case '--api-url': {
        options.apiUrl = args[++i];
        break;
      }

      default: {
        // Remaining args are the prompt
        if (!arg?.startsWith('-')) {
          prompt = args.slice(i).join(' ');
          i = args.length; // Break loop
        }
        break;
      }
    }
  }

  return { prompt, options };
}

/**
 * Read prompt from stdin if available
 */
export async function readStdinPrompt(): Promise<string | null> {
  // Check if stdin has data (not a TTY)
  if (process.stdin.isTTY) {
    return null;
  }

  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }

  return Buffer.concat(chunks).toString('utf-8').trim();
}

/**
 * Main exec entry point
 */
export async function runExec(args: string[]): Promise<void> {
  const { prompt: argPrompt, options } = parseExecArgs(args);

  // Priority: args > file > stdin
  let prompt = argPrompt;

  if (!prompt) {
    const stdinPrompt = await readStdinPrompt();
    if (stdinPrompt) {
      prompt = stdinPrompt;
    }
  }

  if (!prompt) {
    console.error(pc.red('Error: No prompt provided'));
    console.error('');
    console.error('Usage:');
    console.error('  plue exec "your prompt here"');
    console.error('  plue exec -f prompt.txt');
    console.error('  echo "your prompt" | plue exec');
    console.error('');
    console.error('Options:');
    console.error('  -f, --file <path>     Read prompt from file');
    console.error('  -s, --session <id>    Use existing session');
    console.error('  -m, --model <model>   Model to use');
    console.error('  --json                Output as JSON');
    console.error('  --stream              Stream output as it arrives');
    console.error('  --timeout <ms>        Request timeout (default: 60000)');
    console.error('  --api-url <url>       API server URL');
    process.exit(1);
  }

  const fullOptions: ExecOptions = {
    apiUrl: options.apiUrl || process.env.PLUE_API_URL || 'http://localhost:4000',
    sessionId: options.sessionId,
    model: options.model,
    outputFormat: options.outputFormat || 'text',
    timeout: options.timeout,
  };

  const result = await exec(prompt, fullOptions);

  if (fullOptions.outputFormat === 'json') {
    console.log(JSON.stringify(result, null, 2));
  } else if (fullOptions.outputFormat === 'text') {
    if (result.error) {
      console.error(pc.red(`Error: ${result.error}`));
      process.exit(1);
    }
    console.log(result.text);
  }
  // Stream mode already outputs as it goes

  process.exit(result.success ? 0 : 1);
}
