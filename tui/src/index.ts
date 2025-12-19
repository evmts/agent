#!/usr/bin/env bun
/**
 * Plue TUI - Terminal User Interface for Plue AI Agent.
 *
 * A brutalist CLI chat interface using @clack/prompts.
 */

import * as p from '@clack/prompts';
import pc from 'picocolors';
import { PlueClient, type Session, type StreamEvent } from './client';
import { runExec } from './exec';

// Configuration
const API_URL = process.env.PLUE_API_URL || 'http://localhost:4000';
const VERSION = '0.0.1';

// State
let client: PlueClient;
let currentSession: Session | null = null;
let isRunning = true;

// Braille spinner frames
const _spinnerFrames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

/**
 * Display the logo/header
 */
function showLogo() {
  console.log();
  console.log(pc.cyan(pc.bold('  ▄▀▀▄ █    █  █ ▄▀▀▀ ')));
  console.log(pc.cyan(pc.bold('  █▄▄█ █    █  █ █▀▀  ')));
  console.log(pc.cyan(pc.bold('  █    █▄▄▄ ▀▄▄▀ ▀▄▄▄ ')));
  console.log();
  console.log(pc.dim(`  v${VERSION} • ${API_URL}`));
  console.log();
}

/**
 * Format a timestamp
 */
function formatTime(ts: number): string {
  return new Date(ts).toLocaleTimeString();
}

/**
 * Truncate text with ellipsis
 */
function truncate(text: string, maxLen: number): string {
  if (text.length <= maxLen) return text;
  return `${text.slice(0, maxLen - 3)}...`;
}

/**
 * Display a message in the chat format
 */
function displayMessage(role: 'user' | 'assistant' | 'tool', content: string) {
  const prefix =
    role === 'user'
      ? pc.blue(pc.bold('> '))
      : role === 'assistant'
        ? pc.green(pc.bold('⏺ '))
        : pc.cyan(pc.bold('🔧 '));

  const lines = content.split('\n');
  for (let i = 0; i < lines.length; i++) {
    if (i === 0) {
      console.log(prefix + lines[i]);
    } else {
      console.log(`  ${lines[i]}`);
    }
  }
}

/**
 * Display tool call info
 */
function displayToolCall(name: string, input?: Record<string, any>) {
  console.log(pc.cyan(`  🔧 ${name}`));
  if (input && Object.keys(input).length > 0) {
    const preview = JSON.stringify(input);
    console.log(pc.dim(`     ${truncate(preview, 60)}`));
  }
}

/**
 * Display tool result
 */
function displayToolResult(_name: string, output?: string) {
  if (output) {
    const preview = truncate(output.replace(/\n/g, ' '), 80);
    console.log(pc.dim(`  ← ${preview}`));
  }
}

/**
 * Handle streaming response with inline display
 */
async function handleStreamingResponse(
  stream: AsyncGenerator<StreamEvent>
): Promise<string> {
  let textContent = '';
  const _spinnerIdx = 0;
  let _lastToolName = '';

  // Start spinner
  process.stdout.write(pc.green('⏺ '));

  for await (const event of stream) {
    switch (event.type) {
      case 'part.updated': {
        const delta = event.properties.delta;
        if (delta) {
          // Clear spinner if present, write text
          process.stdout.write(delta);
          textContent += delta;
        }
        break;
      }

      case 'tool.call': {
        const { toolName, input } = event.properties;
        _lastToolName = toolName;
        // New line before tool
        if (textContent) {
          console.log();
        }
        displayToolCall(toolName, input);
        break;
      }

      case 'tool.result': {
        const { toolName, output } = event.properties;
        displayToolResult(toolName, output);
        // Resume with new prompt
        process.stdout.write(pc.green('⏺ '));
        break;
      }

      case 'message.completed': {
        // Finish with newline
        if (textContent) {
          console.log();
        }
        break;
      }

      case 'error': {
        console.log();
        console.log(pc.red(`Error: ${event.properties.error}`));
        break;
      }
    }
  }

  console.log();
  return textContent;
}

/**
 * Show help for slash commands
 */
function showHelp() {
  console.log();
  console.log(pc.bold('Commands:'));
  console.log(`${pc.dim('  /new           ')}Create a new session`);
  console.log(`${pc.dim('  /sessions      ')}List all sessions`);
  console.log(`${pc.dim('  /switch <id>   ')}Switch to a session`);
  console.log(`${pc.dim('  /clear         ')}Clear the screen`);
  console.log(`${pc.dim('  /diff          ')}Show session diff`);
  console.log(`${pc.dim('  /abort         ')}Abort current task`);
  console.log(`${pc.dim('  /help          ')}Show this help`);
  console.log(`${pc.dim('  /quit          ')}Exit the TUI`);
  console.log();
}

/**
 * Handle slash commands
 */
async function handleCommand(input: string): Promise<boolean> {
  const [cmd, ...args] = input.slice(1).split(' ');

  if (!cmd) {
    console.log(pc.yellow('Empty command'));
    return true;
  }

  switch (cmd.toLowerCase()) {
    case 'new': {
      const s = p.spinner();
      s.start('Creating new session');
      try {
        currentSession = await client.createSession({
          directory: process.cwd(),
        });
        s.stop(`Session created: ${pc.cyan(currentSession.id)}`);
      } catch (err: any) {
        s.stop(pc.red(`Failed: ${err.message}`));
      }
      return true;
    }

    case 'sessions': {
      const s = p.spinner();
      s.start('Loading sessions');
      try {
        const sessions = await client.listSessions();
        s.stop('Sessions:');

        if (sessions.length === 0) {
          console.log(pc.dim('  No sessions found'));
        } else {
          for (const session of sessions.slice(-10)) {
            const isCurrent = session.id === currentSession?.id;
            const marker = isCurrent ? pc.green('● ') : '  ';
            const title = session.title || 'Untitled';
            const time = formatTime(session.time.created);
            console.log(
              `${marker}${pc.cyan(session.id.slice(0, 8))} ${title} ${pc.dim(time)}`
            );
          }
        }
      } catch (err: any) {
        s.stop(pc.red(`Failed: ${err.message}`));
      }
      console.log();
      return true;
    }

    case 'switch': {
      const sessionId = args[0];
      if (!sessionId) {
        console.log(pc.yellow('Usage: /switch <session-id>'));
        return true;
      }

      const s = p.spinner();
      s.start('Switching session');
      try {
        currentSession = await client.getSession(sessionId);
        s.stop(`Switched to: ${pc.cyan(currentSession.id)}`);

        // Load recent messages
        const messages = await client.getMessages(sessionId, 5);
        if (messages.length > 0) {
          console.log(pc.dim('\nRecent messages:'));
          for (const msg of messages) {
            const textPart = msg.parts.find((p) => p.type === 'text');
            if (textPart?.text) {
              displayMessage(msg.role, truncate(textPart.text, 100));
            }
          }
          console.log();
        }
      } catch (err: any) {
        s.stop(pc.red(`Failed: ${err.message}`));
      }
      return true;
    }

    case 'clear': {
      console.clear();
      showLogo();
      if (currentSession) {
        console.log(pc.dim(`Session: ${currentSession.id}`));
        console.log();
      }
      return true;
    }

    case 'diff': {
      if (!currentSession) {
        console.log(pc.yellow('No active session'));
        return true;
      }

      const s = p.spinner();
      s.start('Loading diff');
      try {
        const diffs = await client.getSessionDiff(currentSession.id);
        s.stop('Diff:');

        if (diffs.length === 0) {
          console.log(pc.dim('  No changes'));
        } else {
          for (const diff of diffs) {
            console.log(pc.cyan(diff.path));
            console.log(diff.content);
          }
        }
      } catch (err: any) {
        s.stop(pc.red(`Failed: ${err.message}`));
      }
      console.log();
      return true;
    }

    case 'abort': {
      if (!currentSession) {
        console.log(pc.yellow('No active session'));
        return true;
      }

      const s = p.spinner();
      s.start('Aborting');
      try {
        await client.abortSession(currentSession.id);
        s.stop('Aborted');
      } catch (err: any) {
        s.stop(pc.red(`Failed: ${err.message}`));
      }
      return true;
    }

    case 'help': {
      showHelp();
      return true;
    }

    case 'quit':
    case 'exit':
    case 'q': {
      isRunning = false;
      return true;
    }

    default: {
      console.log(pc.yellow(`Unknown command: /${cmd}`));
      console.log(pc.dim('Type /help for available commands'));
      return true;
    }
  }
}

/**
 * Main chat loop
 */
async function chatLoop() {
  while (isRunning) {
    // Get user input
    const sessionLabel = currentSession
      ? pc.dim(`[${currentSession.id.slice(0, 8)}] `)
      : '';

    const input = await p.text({
      message: sessionLabel + pc.blue('Message'),
      placeholder: 'Type a message or /help for commands',
    });

    // Handle cancellation
    if (p.isCancel(input)) {
      const shouldQuit = await p.confirm({
        message: 'Are you sure you want to quit?',
        initialValue: false,
      });

      if (p.isCancel(shouldQuit) || shouldQuit) {
        isRunning = false;
      }
      continue;
    }

    const trimmed = (input as string).trim();
    if (!trimmed) continue;

    // Handle slash commands
    if (trimmed.startsWith('/')) {
      await handleCommand(trimmed);
      continue;
    }

    // Ensure we have a session
    if (!currentSession) {
      const s = p.spinner();
      s.start('Creating session');
      try {
        currentSession = await client.createSession({
          directory: process.cwd(),
        });
        s.stop(`Session: ${pc.cyan(currentSession.id)}`);
      } catch (err: any) {
        s.stop(pc.red(`Failed to create session: ${err.message}`));
        continue;
      }
    }

    // Display user message
    displayMessage('user', trimmed);
    console.log();

    // Send message and stream response
    try {
      const stream = client.sendMessage(currentSession.id, trimmed);
      await handleStreamingResponse(stream);
    } catch (err: any) {
      console.log(pc.red(`Error: ${err.message}`));
    }
  }
}

/**
 * Initialize and start the TUI
 */
async function main() {
  // Parse CLI args
  const args = process.argv.slice(2);
  const helpFlag = args.includes('--help') || args.includes('-h');
  const versionFlag = args.includes('--version') || args.includes('-v');

  // Check for exec subcommand (headless mode)
  if (args[0] === 'exec') {
    await runExec(args.slice(1));
    return;
  }

  if (helpFlag) {
    console.log(`
${pc.bold('plue')} - Plue AI Agent TUI

${pc.bold('USAGE:')}
  plue [OPTIONS]
  plue exec [EXEC_OPTIONS] <prompt>

${pc.bold('OPTIONS:')}
  -h, --help       Show this help
  -v, --version    Show version
  --api-url <url>  Set API URL (default: http://localhost:4000)

${pc.bold('EXEC OPTIONS:')}
  -f, --file <path>     Read prompt from file
  -s, --session <id>    Use existing session
  -m, --model <model>   Model to use
  --json                Output as JSON
  --stream              Stream output as it arrives
  --timeout <ms>        Request timeout (default: 60000)

${pc.bold('EXAMPLES:')}
  plue                            Interactive mode
  plue exec "explain this code"   Headless single prompt
  plue exec --stream "hello"      Stream response
  echo "prompt" | plue exec       Read prompt from stdin

${pc.bold('INTERACTIVE COMMANDS:')}
  Type /help in the chat for available commands
`);
    process.exit(0);
  }

  if (versionFlag) {
    console.log(`plue v${VERSION}`);
    process.exit(0);
  }

  // Initialize client
  const apiUrlIdx = args.indexOf('--api-url');
  const apiUrl = apiUrlIdx >= 0 ? args[apiUrlIdx + 1] : API_URL;
  client = new PlueClient(apiUrl);

  // Show logo
  showLogo();

  // Introduction
  p.intro(pc.bgCyan(pc.black(' Plue AI Agent ')));

  // Check server connection
  const s = p.spinner();
  s.start('Connecting to server');

  try {
    const sessions = await client.listSessions();
    s.stop(`Connected (${sessions.length} sessions)`);

    // Offer to resume or create new session
    if (sessions.length > 0) {
      const recentSessions = sessions.slice(-5).reverse();
      const choices = [
        { value: 'new', label: 'Start new session' },
        ...recentSessions.map((sess) => ({
          value: sess.id,
          label: `${sess.title || 'Untitled'} ${pc.dim(`(${sess.id.slice(0, 8)})`)}`,
          hint: formatTime(sess.time.created),
        })),
      ];

      const sessionChoice = await p.select({
        message: 'Select a session',
        options: choices,
      });

      if (p.isCancel(sessionChoice)) {
        p.cancel('Cancelled');
        process.exit(0);
      }

      if (sessionChoice !== 'new') {
        currentSession = await client.getSession(sessionChoice as string);
        console.log(pc.dim(`Resumed session: ${currentSession.id}`));

        // Show recent history
        const messages = await client.getMessages(currentSession.id, 3);
        if (messages.length > 0) {
          console.log(pc.dim('\nRecent:'));
          for (const msg of messages) {
            const textPart = msg.parts.find((p) => p.type === 'text');
            if (textPart?.text) {
              displayMessage(msg.role, truncate(textPart.text, 80));
            }
          }
        }
      }
    }
  } catch (err: any) {
    s.stop(pc.red('Connection failed'));
    console.log(pc.red(`Error: ${err.message}`));
    console.log(pc.dim(`\nMake sure the server is running at ${apiUrl}`));
    console.log(pc.dim('Start it with: bun run dev:api'));
    process.exit(1);
  }

  console.log();
  console.log(pc.dim('Type a message to chat, or /help for commands'));
  console.log();

  // Start chat loop
  await chatLoop();

  // Outro
  p.outro(pc.dim('Goodbye!'));
}

// Handle uncaught errors
process.on('uncaughtException', (err) => {
  console.error(pc.red('Uncaught error:'), err.message);
  process.exit(1);
});

// Run
main().catch((err) => {
  console.error(pc.red('Fatal error:'), err.message);
  process.exit(1);
});
