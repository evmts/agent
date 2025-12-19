/**
 * Enhanced readline-based input with history support.
 */

import * as readline from 'node:readline';
import pc from 'picocolors';

export interface InputOptions {
  prompt?: string;
  history?: string[];
}

/**
 * Get user input with readline interface
 * Supports arrow key history navigation
 */
export function getInput(options: InputOptions = {}): Promise<string | null> {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
      prompt: options.prompt || pc.blue('> '),
      historySize: 100,
      terminal: true,
    });

    // Add history if provided
    if (options.history) {
      (rl as any).history = [...options.history];
    }

    rl.prompt();

    rl.on('line', (line) => {
      rl.close();
      resolve(line);
    });

    rl.on('close', () => {
      resolve(null);
    });

    rl.on('SIGINT', () => {
      rl.close();
      resolve(null);
    });
  });
}

/**
 * Create a persistent input handler with history
 */
export class InputHandler {
  private history: string[] = [];
  private maxHistory = 100;

  async prompt(promptText?: string): Promise<string | null> {
    const input = await getInput({
      prompt: promptText,
      history: this.history,
    });

    if (input?.trim()) {
      this.history.unshift(input);
      if (this.history.length > this.maxHistory) {
        this.history.pop();
      }
    }

    return input;
  }

  getHistory(): string[] {
    return [...this.history];
  }

  clearHistory(): void {
    this.history = [];
  }
}
