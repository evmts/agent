/**
 * Agent wrapper - provides conversation history and session management.
 *
 * Wraps the low-level agent functions with conversation state tracking
 * and message history management.
 */

import type { CoreMessage } from 'ai';
import { streamAgent, type AgentOptions, type StreamEvent } from './agent';

export interface StreamOptions {
  sessionId?: string;
  modelId?: string;
  agentName?: string;
  reasoningEffort?: 'minimal' | 'low' | 'medium' | 'high';
}

export interface WrapperOptions {
  workingDir?: string;
  defaultModel?: string;
  defaultAgentName?: string;
}

/**
 * AgentWrapper maintains conversation history and provides a streaming interface.
 *
 * Usage:
 * ```typescript
 * const wrapper = new AgentWrapper({ workingDir: '/path/to/project' });
 *
 * for await (const event of wrapper.streamAsync('Help me write a function')) {
 *   if (event.type === 'text') {
 *     process.stdout.write(event.data ?? '');
 *   }
 * }
 * ```
 */
export class AgentWrapper {
  private history: CoreMessage[] = [];
  private workingDir: string;
  private defaultModel: string;
  private defaultAgentName: string;

  constructor(options: WrapperOptions = {}) {
    this.workingDir = options.workingDir ?? process.cwd();
    this.defaultModel = options.defaultModel ?? 'claude-sonnet-4-20250514';
    this.defaultAgentName = options.defaultAgentName ?? 'build';
  }

  /**
   * Stream a response for a user message.
   *
   * The conversation history is automatically maintained and included
   * in subsequent calls.
   */
  async *streamAsync(
    userText: string,
    options: StreamOptions = {}
  ): AsyncGenerator<StreamEvent, void, unknown> {
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
}

/**
 * Create an AgentWrapper instance.
 */
export function createAgentWrapper(options?: WrapperOptions): AgentWrapper {
  return new AgentWrapper(options);
}

// Re-export types
export type { StreamEvent } from './agent';
