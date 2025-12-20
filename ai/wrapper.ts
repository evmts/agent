/**
 * Agent wrapper - provides conversation history and session management.
 *
 * Wraps the low-level agent functions with conversation state tracking,
 * message history management, and snapshot tracking per turn.
 */

import type { CoreMessage } from '../node_modules/ai/dist/index.mjs';
import { streamAgent, type AgentOptions, type StreamEvent } from './agent';
import {
  trackSnapshot,
  computeDiff,
  appendSnapshotHistory,
  type FileDiff,
} from '../core/snapshots';

export interface StreamOptions {
  sessionId?: string;
  modelId?: string;
  agentName?: string;
  reasoningEffort?: 'minimal' | 'low' | 'medium' | 'high';
  abortSignal?: AbortSignal;
}

export interface WrapperOptions {
  workingDir?: string;
  defaultModel?: string;
  defaultAgentName?: string;
  sessionId?: string;
}

export interface TurnSummary {
  diffs: FileDiff[];
  additions: number;
  deletions: number;
  filesChanged: number;
}

/**
 * AgentWrapper maintains conversation history and provides a streaming interface.
 *
 * Automatically tracks file state snapshots before and after each agent turn,
 * enabling undo/revert functionality.
 *
 * Usage:
 * ```typescript
 * const wrapper = new AgentWrapper({
 *   workingDir: '/path/to/project',
 *   sessionId: 'ses_abc123',
 * });
 *
 * for await (const event of wrapper.streamAsync('Help me write a function')) {
 *   if (event.type === 'text') {
 *     process.stdout.write(event.data ?? '');
 *   } else if (event.type === 'turn_summary') {
 *     console.log('Files changed:', event.summary.filesChanged);
 *   }
 * }
 * ```
 */
export class AgentWrapper {
  private history: CoreMessage[] = [];
  private workingDir: string;
  private defaultModel: string;
  private defaultAgentName: string;
  private sessionId: string | null;
  private lastTurnSummary: TurnSummary | null = null;

  constructor(options: WrapperOptions = {}) {
    this.workingDir = options.workingDir ?? process.cwd();
    this.defaultModel = options.defaultModel ?? 'claude-sonnet-4-20250514';
    this.defaultAgentName = options.defaultAgentName ?? 'build';
    this.sessionId = options.sessionId ?? null;
  }

  /**
   * Stream a response for a user message.
   *
   * The conversation history is automatically maintained and included
   * in subsequent calls. Snapshots are captured before and after the
   * agent runs to enable undo/revert functionality.
   */
  async *streamAsync(
    userText: string,
    options: StreamOptions = {}
  ): AsyncGenerator<StreamEvent | { type: 'turn_summary'; summary: TurnSummary }, void, unknown> {
    const sessionId = options.sessionId ?? this.sessionId;

    // Capture snapshot BEFORE agent runs
    let stepStartHash: string | null = null;
    if (sessionId) {
      try {
        stepStartHash = await trackSnapshot(sessionId, 'before-turn');
      } catch (error) {
        console.error('[agent] Failed to capture pre-turn snapshot:', error);
      }
    }

    // Add user message to history
    this.history.push({
      role: 'user',
      content: userText,
    });

    // Build agent options
    const agentOptions: AgentOptions = {
      modelId: options.modelId ?? this.defaultModel,
      agentName: options.agentName ?? this.defaultAgentName,
      workingDir: this.workingDir,
      sessionId: sessionId ?? undefined,
      abortSignal: options.abortSignal,
    };

    // Collect assistant response for history
    let assistantText = '';
    const toolResults: Array<{ toolCallId: string; result: string }> = [];

    try {
      // Stream the response
      for await (const event of streamAgent([...this.history], agentOptions)) {
        // Collect text for history
        if (event.type === 'text' && event.data) {
          assistantText += event.data;
        }

        // Collect tool results for history
        if (event.type === 'tool_result' && event.toolId && event.toolOutput) {
          toolResults.push({
            toolCallId: event.toolId,
            result: event.toolOutput,
          });
        }

        // Yield the event
        yield event;
      }

      // Add assistant message to history
      if (assistantText) {
        this.history.push({
          role: 'assistant',
          content: assistantText,
        });
      }

      // Capture snapshot AFTER agent completes
      if (sessionId && stepStartHash) {
        try {
          const stepFinishHash = await trackSnapshot(sessionId, 'after-turn');
          await appendSnapshotHistory(sessionId, stepFinishHash);

          // Compute diffs to show what changed
          const diffs = await computeDiff(sessionId, stepStartHash, stepFinishHash);

          const summary: TurnSummary = {
            diffs,
            additions: diffs.reduce((sum, d) => sum + d.addedLines, 0),
            deletions: diffs.reduce((sum, d) => sum + d.deletedLines, 0),
            filesChanged: diffs.length,
          };

          this.lastTurnSummary = summary;

          // Emit turn summary event
          yield { type: 'turn_summary' as const, summary };
        } catch (error) {
          console.error('[agent] Failed to capture post-turn snapshot:', error);
        }
      }
    } catch (error) {
      // On error, remove the user message we just added
      this.history.pop();
      throw error;
    }
  }

  /**
   * Run a single message and return the complete response.
   */
  async run(userText: string, options: StreamOptions = {}): Promise<string> {
    let response = '';

    for await (const event of this.streamAsync(userText, options)) {
      if (event.type === 'text' && event.data) {
        response += event.data;
      }
    }

    return response;
  }

  /**
   * Clear conversation history.
   */
  resetHistory(): void {
    this.history = [];
  }

  /**
   * Get a copy of the conversation history.
   */
  getHistory(): CoreMessage[] {
    return [...this.history];
  }

  /**
   * Set the conversation history.
   */
  setHistory(messages: CoreMessage[]): void {
    this.history = [...messages];
  }

  /**
   * Get the current working directory.
   */
  getWorkingDir(): string {
    return this.workingDir;
  }

  /**
   * Set the working directory.
   */
  setWorkingDir(dir: string): void {
    this.workingDir = dir;
  }

  /**
   * Get the message count.
   */
  getMessageCount(): number {
    return this.history.length;
  }

  /**
   * Get the session ID.
   */
  getSessionId(): string | null {
    return this.sessionId;
  }

  /**
   * Set the session ID.
   */
  setSessionId(sessionId: string | null): void {
    this.sessionId = sessionId;
  }

  /**
   * Get the last turn summary (file changes from the most recent agent turn).
   */
  getLastTurnSummary(): TurnSummary | null {
    return this.lastTurnSummary;
  }
}

/**
 * Create an AgentWrapper instance.
 */
export function createAgentWrapper(options?: WrapperOptions): AgentWrapper {
  return new AgentWrapper(options);
}

// Re-export types
export type { StreamEvent } from './agent';
export type { FileDiff } from '../core/snapshots';
