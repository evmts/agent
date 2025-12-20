/**
 * AI Agent implementation using Vercel AI SDK.
 *
 * Provides streaming and non-streaming interfaces for running Claude-powered agents.
 */

import { anthropic } from '@ai-sdk/anthropic';
// Use explicit path to avoid conflict with local ai/ folder
import { streamText, generateText, type CoreMessage } from '../node_modules/ai/dist/index.mjs';
import { getAgentConfig } from './registry';
import { agentTools, type AgentToolName } from './tools';

// Re-export types from core to maintain compatibility
export type { MessageWithParts } from '../core/state';

/**
 * Options for running an agent.
 */
export interface AgentOptions {
  /** Model ID (e.g. 'claude-sonnet-4-20250514') */
  modelId: string;
  /** Agent name from registry (e.g. 'build', 'explore', 'plan') */
  agentName: string;
  /** Working directory for file operations */
  workingDir: string;
  /** Optional abort signal for cancellation */
  abortSignal?: AbortSignal;
}

/**
 * Events emitted during agent streaming.
 */
export type StreamEvent =
  | { type: 'text'; data?: string }
  | { type: 'tool_call'; toolName?: string; toolId?: string; args?: unknown }
  | { type: 'tool_result'; toolId?: string; toolOutput?: string }
  | { type: 'error'; error?: string }
  | { type: 'done' };

/**
 * Get enabled tools for an agent based on its configuration.
 */
function getEnabledTools(agentName: string): Record<string, typeof agentTools[AgentToolName]> {
  const config = getAgentConfig(agentName);
  const enabledTools: Record<string, typeof agentTools[AgentToolName]> = {};

  for (const [name, tool] of Object.entries(agentTools)) {
    const enabled = config.toolsEnabled[name as AgentToolName];
    // Default to true if not explicitly disabled
    if (enabled !== false) {
      enabledTools[name] = tool;
    }
  }

  return enabledTools;
}

/**
 * Stream agent responses with tool execution.
 *
 * @example
 * ```typescript
 * for await (const event of streamAgent(messages, options)) {
 *   if (event.type === 'text') {
 *     process.stdout.write(event.data ?? '');
 *   }
 * }
 * ```
 */
export async function* streamAgent(
  messages: CoreMessage[],
  options: AgentOptions
): AsyncGenerator<StreamEvent, void, unknown> {
  const config = getAgentConfig(options.agentName);
  const enabledTools = getEnabledTools(options.agentName);
  const model = anthropic(options.modelId);

  try {
    const result = streamText({
      model,
      messages,
      system: config.systemPrompt,
      tools: enabledTools,
      abortSignal: options.abortSignal,
      maxSteps: 10, // Allow multi-step tool execution
      temperature: config.temperature,
      topP: config.topP,
    });

    for await (const part of (await result).fullStream) {
      switch (part.type) {
        case 'text-delta':
          yield { type: 'text', data: part.textDelta };
          break;

        case 'tool-call':
          yield {
            type: 'tool_call',
            toolName: part.toolName,
            toolId: part.toolCallId,
            args: part.args,
          };
          break;

        case 'tool-result':
          yield {
            type: 'tool_result',
            toolId: part.toolCallId,
            toolOutput: typeof part.result === 'string' ? part.result : JSON.stringify(part.result),
          };
          break;

        case 'error':
          yield { type: 'error', error: String(part.error) };
          break;

        case 'finish':
          yield { type: 'done' };
          break;
      }
    }
  } catch (error) {
    yield { type: 'error', error: error instanceof Error ? error.message : String(error) };
  }
}

/**
 * Run agent and return the complete response (non-streaming).
 */
export async function runAgent(
  messages: CoreMessage[],
  options: AgentOptions
): Promise<string> {
  const config = getAgentConfig(options.agentName);
  const enabledTools = getEnabledTools(options.agentName);
  const model = anthropic(options.modelId);

  const result = await generateText({
    model,
    messages,
    system: config.systemPrompt,
    tools: enabledTools,
    abortSignal: options.abortSignal,
    maxSteps: 10,
    temperature: config.temperature,
    topP: config.topP,
  });

  return result.text;
}

/**
 * Run agent synchronously (blocking wrapper for testing).
 *
 * Note: This is not truly synchronous - it blocks the event loop.
 * Use only for testing or CLI tools where blocking is acceptable.
 */
export function runAgentSync(
  messages: CoreMessage[],
  options: AgentOptions
): string {
  // Use Bun's synchronous promise resolution
  let result = '';
  let error: Error | null = null;
  let settled = false;
  const maxWaitMs = 300000; // 5 minute timeout
  const startTime = Date.now();

  runAgent(messages, options)
    .then((r) => { result = r; settled = true; })
    .catch((e) => { error = e; settled = true; });

  // Block until promise resolves (Bun-specific)
  // @ts-expect-error - Bun internal API
  if (typeof Bun !== 'undefined' && Bun.sleepSync) {
    while (!settled && (Date.now() - startTime) < maxWaitMs) {
      // @ts-expect-error - Bun internal API
      Bun.sleepSync(10);
    }

    if (!settled) {
      throw new Error('runAgentSync timed out after 5 minutes');
    }
  }

  if (error) throw error;
  return result;
}

/**
 * Stream agent with persistence to database.
 *
 * Wraps streamAgent and persists events using the database helpers.
 */
export async function* persistedStreamAgent(
  messages: CoreMessage[],
  options: AgentOptions,
  sessionId: string
): AsyncGenerator<StreamEvent, void, unknown> {
  // Import dynamically to avoid circular dependencies
  const { appendStreamingPart, updateMessageStatus, generateMessageId } = await import('../db/agent-state');

  // Generate a message ID at the start for consistent persistence
  const messageId = generateMessageId();
  let sortOrder = 0;

  try {
    for await (const event of streamAgent(messages, options)) {
      // Persist event to database
      if (event.type === 'text' && event.data) {
        await appendStreamingPart(sessionId, messageId, {
          type: 'text',
          text: event.data,
          sort_order: sortOrder++,
          time_start: Date.now(),
        });
      } else if (event.type === 'tool_call') {
        await appendStreamingPart(sessionId, messageId, {
          type: 'tool',
          tool_name: event.toolName,
          tool_state: {
            status: 'calling',
            toolId: event.toolId,
            args: event.args,
          },
          sort_order: sortOrder++,
          time_start: Date.now(),
        });
      } else if (event.type === 'tool_result') {
        await appendStreamingPart(sessionId, messageId, {
          type: 'tool',
          tool_name: 'result',
          tool_state: {
            status: 'complete',
            toolId: event.toolId,
            result: event.toolOutput,
          },
          sort_order: sortOrder++,
          time_start: Date.now(),
          time_end: Date.now(),
        });
      }

      yield event;

      if (event.type === 'done') {
        await updateMessageStatus(sessionId, messageId, 'complete');
      }
    }
  } catch (error) {
    await updateMessageStatus(sessionId, messageId, 'error');
    throw error;
  }
}
