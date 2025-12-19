/**
 * Animated status indicator with elapsed time display.
 */

import pc from 'picocolors';

const SPINNER_FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
const UPDATE_INTERVAL_MS = 100;

/**
 * Strip ANSI codes from a string to get visible length
 */
function stripAnsi(str: string): string {
  // eslint-disable-next-line no-control-regex
  return str.replace(/\x1b\[[0-9;]*m/g, '');
}

/**
 * Animated status indicator that shows a spinner with elapsed time.
 */
export class StatusIndicator {
  private intervalId: ReturnType<typeof setInterval> | null = null;
  private frameIndex = 0;
  private startTime = 0;
  private lastLineLength = 0;
  private message = '';

  /**
   * Start the indicator with a message
   */
  start(message = 'Working'): void {
    this.message = message;
    this.startTime = Date.now();
    this.frameIndex = 0;
    this.render();

    this.intervalId = setInterval(() => {
      this.frameIndex = (this.frameIndex + 1) % SPINNER_FRAMES.length;
      this.render();
    }, UPDATE_INTERVAL_MS);
  }

  /**
   * Update the message without resetting the timer
   */
  update(message: string): void {
    this.message = message;
    this.render();
  }

  /**
   * Render the current state
   */
  private render(): void {
    const elapsed = ((Date.now() - this.startTime) / 1000).toFixed(1);
    const frame = SPINNER_FRAMES[this.frameIndex];
    const line = `${pc.cyan(frame)} ${this.message}... ${pc.dim(`${elapsed}s`)}`;

    // Clear previous line and write new one
    this.clearLine();
    process.stdout.write(line);
    this.lastLineLength = stripAnsi(line).length;
  }

  /**
   * Clear the current line
   */
  private clearLine(): void {
    // Move cursor to start of line and clear
    process.stdout.write('\r');
    process.stdout.write(' '.repeat(this.lastLineLength));
    process.stdout.write('\r');
  }

  /**
   * Stop the indicator and clear the line
   */
  stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
    this.clearLine();
  }

  /**
   * Stop with a final message
   */
  stopWithMessage(message: string): void {
    this.stop();
    console.log(message);
  }

  /**
   * Get elapsed time in milliseconds
   */
  getElapsed(): number {
    return Date.now() - this.startTime;
  }

  /**
   * Get elapsed time formatted as string
   */
  getElapsedFormatted(): string {
    const ms = this.getElapsed();
    if (ms < 1000) {
      return `${ms}ms`;
    }
    return `${(ms / 1000).toFixed(1)}s`;
  }

  /**
   * Check if the indicator is running
   */
  isRunning(): boolean {
    return this.intervalId !== null;
  }
}

/**
 * Format token usage for display
 */
export function formatTokenUsage(tokens: {
  input?: number;
  output?: number;
  total?: number;
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
}): string {
  const input = tokens.input ?? tokens.promptTokens ?? 0;
  const output = tokens.output ?? tokens.completionTokens ?? 0;
  const total = tokens.total ?? tokens.totalTokens ?? input + output;

  const formatNum = (n: number) => n.toLocaleString();

  return pc.dim(
    `  ↳ ${formatNum(total)} tokens (in: ${formatNum(input)}, out: ${formatNum(output)})`
  );
}

/**
 * Format keyboard hints for display
 */
export function formatKeyboardHints(
  context: 'idle' | 'streaming' | 'input'
): string {
  const hints =
    context === 'streaming'
      ? [
          { key: 'Ctrl+C', action: 'Cancel' },
          { key: '/abort', action: 'Stop' },
        ]
      : [
          { key: 'Ctrl+C', action: 'Cancel' },
          { key: '/help', action: 'Commands' },
        ];

  return pc.dim(hints.map((h) => `${h.key}: ${h.action}`).join(' | '));
}
