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
import { StatusIndicator, formatTokenUsage, formatKeyboardHints } from './status-indicator';
import { formatToolCall, formatToolResult, ToolCallTracker } from './render/tools';

// Configuration
const API_URL = process.env.PLUE_API_URL || 'http://localhost:4000';
const VERSION = '0.0.1';

// State
let client: PlueClient;
let currentSession: Session | null = null;
let isRunning = true;
let pendingMention: string | null = null;

// Braille spinner frames
const _spinnerFrames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

// Available models and reasoning efforts
const AVAILABLE_MODELS = [
  'claude-sonnet-4-20250514',
  'claude-opus-4-20250514',
  'claude-3-5-sonnet-20241022',
  'claude-3-5-haiku-20241022',
];

const REASONING_EFFORTS = ['minimal', 'low', 'medium', 'high'] as const;
type ReasoningEffort = (typeof REASONING_EFFORTS)[number];

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
 * Handle streaming response with inline display
 */
async function handleStreamingResponse(
  stream: AsyncGenerator<StreamEvent>
): Promise<string> {
  let textContent = '';
  const indicator = new StatusIndicator();
  const toolTracker = new ToolCallTracker();
  let isStreaming = false;

  for await (const event of stream) {
    switch (event.type) {
      case 'part.updated': {
        const delta = event.properties.delta;
        if (delta) {
          // Stop indicator and start text output
          if (!isStreaming) {
            indicator.stop();
            process.stdout.write(pc.green('⏺ '));
            isStreaming = true;
          }
          process.stdout.write(delta);
          textContent += delta;
        }
        break;
      }

      case 'tool.call': {
        const { toolName, input } = event.properties;

        // New line before tool
        if (isStreaming && textContent) {
          console.log();
          isStreaming = false;
        }

        // Start tracking duration
        toolTracker.start(toolName);
        indicator.start(`Running ${toolName}`);

        // Display tool call
        console.log(formatToolCall(toolName, input));
        break;
      }

      case 'tool.result': {
        const { toolName, output } = event.properties;

        // Get duration and stop tracking
        const duration = toolTracker.getDuration(toolName);
        toolTracker.clear(toolName);

        // Stop indicator and show result
        indicator.stop();
        console.log(formatToolResult(toolName, output, duration));

        // Start waiting indicator for next action
        indicator.start('Working');
        break;
      }

      case 'message.completed': {
        indicator.stop();
        // Finish with newline
        if (isStreaming && textContent) {
          console.log();
        }

        // Display token usage if available
        const tokens = event.properties.tokens || event.properties.usage;
        if (tokens) {
          console.log(formatTokenUsage(tokens));
        }
        break;
      }

      case 'usage': {
        // Handle dedicated usage event
        const tokens = event.properties.tokens || event.properties;
        if (tokens) {
          console.log(formatTokenUsage(tokens));
        }
        break;
      }

      case 'error': {
        indicator.stop();
        console.log();
        console.log(pc.red(`Error: ${event.properties.error}`));
        break;
      }
    }
  }

  indicator.stop();
  console.log();
  return textContent;
}

/**
 * Show help for slash commands
 */
function showHelp() {
  console.log();
  console.log(pc.bold('Commands:'));
  console.log(`${pc.dim('  /new             ')}Create a new session`);
  console.log(`${pc.dim('  /sessions        ')}List all sessions`);
  console.log(`${pc.dim('  /switch <id>     ')}Switch to a session`);
  console.log(`${pc.dim('  /model [name]    ')}List or set the model`);
  console.log(`${pc.dim('  /effort [level]  ')}Set reasoning effort`);
  console.log(`${pc.dim('  /status          ')}Show session status`);
  console.log(`${pc.dim('  /undo [n]        ')}Undo last N turns`);
  console.log(`${pc.dim('  /mention <file>  ')}Include file in next message`);
  console.log(`${pc.dim('  /review          ')}Show changes with stats`);
  console.log(`${pc.dim('  /diff            ')}Show session diff`);
  console.log(`${pc.dim('  /abort           ')}Abort current task`);
  console.log(`${pc.dim('  /clear           ')}Clear the screen`);
  console.log(`${pc.dim('  /help            ')}Show this help`);
  console.log(`${pc.dim('  /quit            ')}Exit the TUI`);
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

    case 'model': {
      const modelArg = args[0];

      if (!modelArg) {
        // List available models
        console.log();
        console.log(pc.bold('Available models:'));
        for (const model of AVAILABLE_MODELS) {
          const isCurrent = currentSession?.model === model;
          const marker = isCurrent ? pc.green('● ') : '  ';
          console.log(`${marker}${pc.cyan(model)}`);
        }
        if (currentSession?.model && !AVAILABLE_MODELS.includes(currentSession.model)) {
          console.log(`${pc.green('● ')}${pc.cyan(currentSession.model)} ${pc.dim('(custom)')}`);
        }
        console.log();
        console.log(pc.dim('Usage: /model <name> to set'));
        console.log();
        return true;
      }

      if (!currentSession) {
        console.log(pc.yellow('No active session'));
        return true;
      }

      const s = p.spinner();
      s.start(`Setting model to ${modelArg}`);
      try {
        currentSession = await client.updateSession(currentSession.id, { model: modelArg });
        s.stop(`Model set to: ${pc.cyan(currentSession.model || modelArg)}`);
      } catch (err: any) {
        s.stop(pc.red(`Failed: ${err.message}`));
      }
      return true;
    }

    case 'effort': {
      const effortArg = args[0]?.toLowerCase() as ReasoningEffort | undefined;

      if (!effortArg) {
        // Show current effort
        console.log();
        console.log(pc.bold('Reasoning effort levels:'));
        const descriptions: Record<ReasoningEffort, string> = {
          minimal: 'Fastest, least thorough',
          low: 'Quick responses',
          medium: 'Balanced (default)',
          high: 'Most thorough, slowest',
        };
        for (const level of REASONING_EFFORTS) {
          const isCurrent = currentSession?.reasoningEffort === level;
          const marker = isCurrent ? pc.green('● ') : '  ';
          console.log(`${marker}${pc.cyan(level)} ${pc.dim(`- ${descriptions[level]}`)}`);
        }
        console.log();
        console.log(pc.dim('Usage: /effort <level> to set'));
        console.log();
        return true;
      }

      if (!REASONING_EFFORTS.includes(effortArg)) {
        console.log(pc.yellow(`Invalid effort level. Choose: ${REASONING_EFFORTS.join(', ')}`));
        return true;
      }

      if (!currentSession) {
        console.log(pc.yellow('No active session'));
        return true;
      }

      const s = p.spinner();
      s.start(`Setting reasoning effort to ${effortArg}`);
      try {
        currentSession = await client.updateSession(currentSession.id, {
          reasoningEffort: effortArg,
        });
        s.stop(`Reasoning effort set to: ${pc.cyan(effortArg)}`);
      } catch (err: any) {
        s.stop(pc.red(`Failed: ${err.message}`));
      }
      return true;
    }

    case 'status': {
      if (!currentSession) {
        console.log(pc.yellow('No active session'));
        return true;
      }

      const s = p.spinner();
      s.start('Loading session status');
      try {
        // Refresh session data
        currentSession = await client.getSession(currentSession.id);
        s.stop('Session Status:');

        console.log();
        console.log(`  ${pc.dim('ID:')}           ${pc.cyan(currentSession.id)}`);
        console.log(`  ${pc.dim('Title:')}        ${currentSession.title || 'Untitled'}`);
        console.log(`  ${pc.dim('Model:')}        ${pc.cyan(currentSession.model || 'default')}`);
        console.log(`  ${pc.dim('Effort:')}       ${pc.cyan(currentSession.reasoningEffort || 'medium')}`);
        console.log(`  ${pc.dim('Directory:')}    ${currentSession.directory}`);
        console.log(`  ${pc.dim('Tokens:')}       ${currentSession.tokenCount?.toLocaleString() ?? 'N/A'}`);
        console.log(`  ${pc.dim('Created:')}      ${formatTime(currentSession.time.created)}`);
        if (currentSession.time.updated) {
          console.log(`  ${pc.dim('Updated:')}      ${formatTime(currentSession.time.updated)}`);
        }
        console.log();
      } catch (err: any) {
        s.stop(pc.red(`Failed: ${err.message}`));
      }
      return true;
    }

    case 'undo': {
      if (!currentSession) {
        console.log(pc.yellow('No active session'));
        return true;
      }

      const count = parseInt(args[0] || '1', 10);
      if (isNaN(count) || count < 1) {
        console.log(pc.yellow('Usage: /undo [n] where n is a positive number'));
        return true;
      }

      const s = p.spinner();
      s.start(`Undoing ${count} turn${count > 1 ? 's' : ''}`);
      try {
        const result = await client.undoTurns(currentSession.id, count);

        if (result.turnsUndone === 0) {
          s.stop(pc.yellow('Nothing to undo'));
        } else {
          s.stop(`Undone: ${pc.cyan(result.turnsUndone.toString())} turn${result.turnsUndone > 1 ? 's' : ''}`);
          console.log(pc.dim(`  Messages removed: ${result.messagesRemoved}`));
          if (result.filesReverted.length > 0) {
            console.log(pc.dim(`  Files reverted: ${result.filesReverted.length}`));
            for (const file of result.filesReverted.slice(0, 5)) {
              console.log(pc.dim(`    - ${file}`));
            }
            if (result.filesReverted.length > 5) {
              console.log(pc.dim(`    ... and ${result.filesReverted.length - 5} more`));
            }
          }
          if (result.snapshotRestored) {
            console.log(pc.dim(`  Snapshot: ${result.snapshotRestored.slice(0, 8)}`));
          }
        }
      } catch (err: any) {
        s.stop(pc.red(`Failed: ${err.message}`));
      }
      console.log();
      return true;
    }

    case 'mention': {
      const filePath = args.join(' ');

      if (!filePath) {
        console.log(pc.yellow('Usage: /mention <file-path>'));
        console.log(pc.dim('  Reads file content and includes it in your next message'));
        return true;
      }

      const s = p.spinner();
      s.start(`Reading ${filePath}`);
      try {
        // Resolve path relative to cwd or session directory
        const basePath = currentSession?.directory || process.cwd();
        const resolvedPath = filePath.startsWith('/') ? filePath : `${basePath}/${filePath}`;

        const file = Bun.file(resolvedPath);
        const exists = await file.exists();

        if (!exists) {
          s.stop(pc.red(`File not found: ${resolvedPath}`));
          return true;
        }

        const content = await file.text();
        const lineCount = content.split('\n').length;
        const byteSize = file.size;

        // Store for injection into next message
        pendingMention = `<file path="${filePath}">\n${content}\n</file>`;

        s.stop(`File loaded: ${pc.cyan(filePath)}`);
        console.log(pc.dim(`  ${lineCount} lines, ${(byteSize / 1024).toFixed(1)} KB`));
        console.log(pc.dim('  Content will be included in your next message'));
      } catch (err: any) {
        s.stop(pc.red(`Failed: ${err.message}`));
      }
      console.log();
      return true;
    }

    case 'review': {
      // Enhanced /diff with summary and coloring
      if (!currentSession) {
        console.log(pc.yellow('No active session'));
        return true;
      }

      const s = p.spinner();
      s.start('Loading changes');
      try {
        const diffs = await client.getSessionDiff(currentSession.id);
        s.stop(pc.bold('Session Changes:'));

        if (diffs.length === 0) {
          console.log(pc.dim('  No changes in this session'));
        } else {
          console.log();
          let totalAdditions = 0;
          let totalDeletions = 0;

          for (const diff of diffs) {
            // Count additions/deletions
            const lines = diff.content?.split('\n') || [];
            const additions = lines.filter((l: string) => l.startsWith('+')).length;
            const deletions = lines.filter((l: string) => l.startsWith('-')).length;
            totalAdditions += additions;
            totalDeletions += deletions;

            // Display file header with stats
            console.log(pc.cyan(pc.bold(`  ${diff.path}`)));
            console.log(`    ${pc.green(`+${additions}`)} ${pc.red(`-${deletions}`)}`);

            // Show abbreviated content with syntax highlighting
            const previewLines = lines.slice(0, 10);
            for (const line of previewLines) {
              if (line.startsWith('+')) {
                console.log(pc.green(`    ${line}`));
              } else if (line.startsWith('-')) {
                console.log(pc.red(`    ${line}`));
              } else if (line.startsWith('@@')) {
                console.log(pc.cyan(`    ${line}`));
              } else {
                console.log(pc.dim(`    ${line}`));
              }
            }
            if (lines.length > 10) {
              console.log(pc.dim(`    ... ${lines.length - 10} more lines`));
            }
            console.log();
          }

          // Summary
          console.log(pc.bold('  Summary:'));
          console.log(`    ${diffs.length} file${diffs.length > 1 ? 's' : ''} changed`);
          console.log(`    ${pc.green(`+${totalAdditions}`)} additions, ${pc.red(`-${totalDeletions}`)} deletions`);
        }
      } catch (err: any) {
        s.stop(pc.red(`Failed: ${err.message}`));
      }
      console.log();
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
      // Include pending mention if present
      let messageContent = trimmed;
      if (pendingMention) {
        messageContent = `${pendingMention}\n\n${trimmed}`;
        pendingMention = null; // Clear after use
      }

      const stream = client.sendMessage(currentSession.id, messageContent);
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
  console.log(formatKeyboardHints('idle'));
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
