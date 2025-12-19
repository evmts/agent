/**
 * Agent implementation using Vercel AI SDK.
 *
 * Provides the main agent functionality with tool calling support
 * using Claude via the Anthropic provider.
 */

import { anthropic } from '@ai-sdk/anthropic';
import { streamText, type CoreMessage } from 'ai';
import { agentTools, getToolCallTracker } from './tools';
import { getAgentConfig, isToolEnabled, type AgentConfig } from './registry';

// Constants
const DEFAULT_MODEL = 'claude-sonnet-4-20250514';
const DEFAULT_MAX_STEPS = 10;
const DEFAULT_MAX_TOKENS = 64000;

export interface AgentOptions {
  modelId?: string;
  agentName?: string;
  workingDir?: string;
  maxSteps?: number;
  maxTokens?: number;
  temperature?: number;
  systemPrompt?: string;
  abortSignal?: AbortSignal;
  sessionId?: string; // Session ID for duplicate detection
  enableDuplicateDetection?: boolean; // Enable/disable duplicate detection (default: true)
}

export interface StreamEvent {
  type: 'text' | 'tool_call' | 'tool_result' | 'reasoning' | 'finish';
  data?: string;
  toolName?: string;
  toolInput?: Record<string, unknown>;
  toolOutput?: string;
  toolId?: string;
  finishReason?: string;
  cached?: boolean; // Indicates if result came from duplicate detection cache
}

/**
 * Build the system prompt for an agent.
 *
 * Combines the agent's base system prompt with optional custom prompt
 * and CLAUDE.md content from the working directory.
 */
async function buildSystemPrompt(
  config: AgentConfig,
  workingDir?: string,
  customPrompt?: string
): Promise<string> {
  let prompt = config.systemPrompt;

  // Add custom prompt if provided
  if (customPrompt) {
    prompt += `\n\n${customPrompt}`;
  }

  // Try to load CLAUDE.md from working directory
  if (workingDir) {
    try {
      const claudeMdPath = `${workingDir}/CLAUDE.md`;
      const file = Bun.file(claudeMdPath);
      if (await file.exists()) {
        const content = await file.text();
        prompt += `\n\n## Project Instructions (from CLAUDE.md)\n\n${content}`;
      }
    } catch {
      // CLAUDE.md not found or not readable, continue without it
    }
  }

  return prompt;
}

/**
 * Filter tools based on agent configuration.
 */
function filterToolsForAgent(agentName: string): typeof agentTools {
  const filtered: Partial<typeof agentTools> = {};

  for (const [name, tool] of Object.entries(agentTools)) {
    if (isToolEnabled(agentName, name)) {
      (filtered as Record<string, unknown>)[name] = tool;
    }
  }

  return filtered as typeof agentTools;
}

/**
 * Wrap tools with duplicate detection logic.
 *
 * Returns a new tools object where each tool checks for duplicates
 * before executing and records results after execution.
 */
function wrapToolsWithDuplicateDetection(
  tools: typeof agentTools,
  sessionId: string,
  enabled: boolean
): typeof agentTools {
  if (!enabled) {
    return tools;
  }

  const tracker = getToolCallTracker();
  const wrapped: Record<string, unknown> = {};

  for (const [name, tool] of Object.entries(tools)) {
    wrapped[name] = {
      ...tool,
      execute: async (args: Record<string, unknown>, options?: { abortSignal?: AbortSignal }) => {
        // Check for duplicate
        const duplicateCheck = tracker.checkDuplicate(sessionId, name, args);

        if (duplicateCheck.isDuplicate && duplicateCheck.previousResult) {
          // Return cached result with a note
          const cacheNote = `[Cached result from ${new Date(duplicateCheck.previousTimestamp!).toLocaleTimeString()}]`;
          return `${cacheNote}\n\n${duplicateCheck.previousResult}`;
        }

        // Execute the original tool
        const result = await (tool.execute as (args: Record<string, unknown>, options?: { abortSignal?: AbortSignal }) => Promise<unknown>)(args, options);
        const resultStr = typeof result === 'string' ? result : JSON.stringify(result);

        // Record the call for future duplicate detection
        tracker.recordCall(sessionId, name, args, resultStr);

        return result;
      },
    };
  }

  return wrapped as typeof agentTools;
}

/**
 * Create an agent stream using Vercel AI SDK.
 *
 * Returns an async generator that yields StreamEvents for each
 * piece of the response (text chunks, tool calls, tool results).
 */
export async function* streamAgent(
  messages: CoreMessage[],
  options: AgentOptions = {}
): AsyncGenerator<StreamEvent, void, unknown> {
  const agentName = options.agentName ?? 'build';
  const config = getAgentConfig(agentName);
  const modelId = options.modelId ?? DEFAULT_MODEL;

  // Build system prompt
  const systemPrompt = await buildSystemPrompt(
    config,
    options.workingDir,
    options.systemPrompt
  );

  // Filter tools for this agent
  const filteredTools = filterToolsForAgent(agentName);

  // Wrap tools with duplicate detection if enabled (default: true)
  const enableDuplicateDetection = options.enableDuplicateDetection ?? true;
  const sessionId = options.sessionId ?? 'default';
  const tools = wrapToolsWithDuplicateDetection(
    filteredTools,
    sessionId,
    enableDuplicateDetection
  );

  // Create the stream
  const result = streamText({
    model: anthropic(modelId),
    system: systemPrompt,
    messages,
    tools,
    maxSteps: options.maxSteps ?? DEFAULT_MAX_STEPS,
    maxTokens: options.maxTokens ?? DEFAULT_MAX_TOKENS,
    temperature: options.temperature ?? config.temperature,
    abortSignal: options.abortSignal,
  } as Parameters<typeof streamText>[0]);

  // Transform the stream to our StreamEvent format
  try {
    for await (const part of result.fullStream) {
      // Check if aborted before yielding
      if (options.abortSignal?.aborted) {
        yield {
          type: 'finish',
          finishReason: 'aborted',
        };
        break;
      }

      switch (part.type) {
        case 'text-delta':
          yield {
            type: 'text',
            data: (part as { type: 'text-delta'; text: string }).text,
          };
          break;

        case 'reasoning-delta':
          yield {
            type: 'reasoning',
            data: (part as unknown as { type: 'reasoning-delta'; text: string }).text,
          };
          break;

        case 'tool-call':
          yield {
            type: 'tool_call',
            toolName: part.toolName,
            toolInput: (part as { input: unknown }).input as Record<string, unknown>,
            toolId: part.toolCallId,
          };
          break;

        case 'tool-result':
          const output = typeof (part as { output: unknown }).output === 'string'
            ? (part as { output: string }).output
            : JSON.stringify((part as { output: unknown }).output);

          // Check if result was cached (starts with cache note)
          const cached = output.startsWith('[Cached result from');

          yield {
            type: 'tool_result',
            toolName: part.toolName,
            toolOutput: output,
            toolId: part.toolCallId,
            cached,
          };
          break;

        case 'finish':
          yield {
            type: 'finish',
            finishReason: part.finishReason,
          };
          break;
      }
    }
  } catch (error) {
    // If aborted, yield abort finish event
    if (options.abortSignal?.aborted) {
      yield {
        type: 'finish',
        finishReason: 'aborted',
      };
    } else {
      throw error;
    }
  }
}

/**
 * Run agent with a single user message (convenience function).
 */
export async function* runAgent(
  userMessage: string,
  options: AgentOptions = {}
): AsyncGenerator<StreamEvent, void, unknown> {
  const messages: CoreMessage[] = [
    { role: 'user', content: userMessage },
  ];

  yield* streamAgent(messages, options);
}

/**
 * Collect all stream events and return full response.
 */
export async function runAgentSync(
  userMessage: string,
  options: AgentOptions = {}
): Promise<{
  text: string;
  toolCalls: Array<{ name: string; input: Record<string, unknown>; output: string }>;
}> {
  let text = '';
  const toolCalls: Array<{ name: string; input: Record<string, unknown>; output: string }> = [];
  const pendingToolCalls = new Map<string, { name: string; input: Record<string, unknown> }>();

  for await (const event of runAgent(userMessage, options)) {
    switch (event.type) {
      case 'text':
        text += event.data ?? '';
        break;

      case 'tool_call':
        if (event.toolId && event.toolName) {
          pendingToolCalls.set(event.toolId, {
            name: event.toolName,
            input: event.toolInput ?? {},
          });
        }
        break;

      case 'tool_result':
        if (event.toolId) {
          const pending = pendingToolCalls.get(event.toolId);
          if (pending) {
            toolCalls.push({
              name: pending.name,
              input: pending.input,
              output: event.toolOutput ?? '',
            });
            pendingToolCalls.delete(event.toolId);
          }
        }
        break;
    }
  }

  return { text, toolCalls };
}

/**
 * Stream agent with database persistence for real-time collaboration.
 *
 * Wraps streamAgent to persist all events to the database as they happen,
 * enabling:
 * - Multiple users to see agent progress in real-time via ElectricSQL sync
 * - Session recovery after crashes
 * - Full audit trail of agent actions
 */
export async function* persistedStreamAgent(
  sessionId: string,
  messageId: string,
  messages: CoreMessage[],
  options: AgentOptions = {}
): AsyncGenerator<StreamEvent, void, unknown> {
  const { appendStreamingPart, updateMessageStatus } = await import('../db/agent-state');

  // Update message status to 'streaming'
  await updateMessageStatus(messageId, { status: 'streaming' });

  let partOrder = 0;
  let currentTextPartId: string | null = null;
  let currentTextContent = '';
  let currentReasoningPartId: string | null = null;
  let currentReasoningContent = '';
  const pendingToolCalls = new Map<string, { partId: string; name: string; input: Record<string, unknown> }>();

  try {
    // Pass sessionId to streamAgent for duplicate detection
    const streamOptions = { ...options, sessionId };
    for await (const event of streamAgent(messages, streamOptions)) {
      const now = Date.now();

      switch (event.type) {
        case 'text': {
          // Accumulate text in a single part
          if (event.data) {
            currentTextContent += event.data;

            if (!currentTextPartId) {
              // Create new text part
              currentTextPartId = await appendStreamingPart(sessionId, messageId, {
                type: 'text',
                text: currentTextContent,
                sort_order: partOrder++,
                time_start: now,
              });
            } else {
              // Update existing text part
              const { updateStreamingPart } = await import('../db/agent-state');
              await updateStreamingPart(currentTextPartId, {
                text: currentTextContent,
              });
            }
          }
          break;
        }

        case 'reasoning': {
          // Accumulate reasoning in a single part
          if (event.data) {
            currentReasoningContent += event.data;

            if (!currentReasoningPartId) {
              // Create new reasoning part
              currentReasoningPartId = await appendStreamingPart(sessionId, messageId, {
                type: 'reasoning',
                text: currentReasoningContent,
                sort_order: partOrder++,
                time_start: now,
              });
            } else {
              // Update existing reasoning part
              const { updateStreamingPart } = await import('../db/agent-state');
              await updateStreamingPart(currentReasoningPartId, {
                text: currentReasoningContent,
              });
            }
          }
          break;
        }

        case 'tool_call': {
          if (event.toolName && event.toolId) {
            // Create tool part with pending state
            const toolPartId = await appendStreamingPart(sessionId, messageId, {
              type: 'tool',
              tool_name: event.toolName,
              tool_state: {
                status: 'pending',
                input: event.toolInput ?? {},
              },
              sort_order: partOrder++,
              time_start: now,
            });

            pendingToolCalls.set(event.toolId, {
              partId: toolPartId,
              name: event.toolName,
              input: event.toolInput ?? {},
            });

            // Update thinking text
            await updateMessageStatus(messageId, {
              thinking_text: `Running ${event.toolName}...`,
            });
          }
          break;
        }

        case 'tool_result': {
          if (event.toolId) {
            const pending = pendingToolCalls.get(event.toolId);
            if (pending) {
              // Update tool part with completed state
              const { updateStreamingPart } = await import('../db/agent-state');
              await updateStreamingPart(pending.partId, {
                tool_state: {
                  status: 'completed',
                  input: pending.input,
                  output: event.toolOutput ?? '',
                },
                time_end: now,
              });

              pendingToolCalls.delete(event.toolId);
            }
          }
          break;
        }

        case 'finish': {
          // Mark text/reasoning parts as finished
          if (currentTextPartId) {
            const { updateStreamingPart } = await import('../db/agent-state');
            await updateStreamingPart(currentTextPartId, {
              time_end: now,
            });
          }
          if (currentReasoningPartId) {
            const { updateStreamingPart } = await import('../db/agent-state');
            await updateStreamingPart(currentReasoningPartId, {
              time_end: now,
            });
          }

          // Update message to completed
          await updateMessageStatus(messageId, {
            status: 'completed',
            time_completed: now,
            finish: event.finishReason,
            thinking_text: null as unknown as string, // Clear thinking text
          });
          break;
        }
      }

      // Yield the event to the caller (pass-through)
      yield event;
    }
  } catch (error) {
    // Mark message as failed
    await updateMessageStatus(messageId, {
      status: 'failed',
      error_message: error instanceof Error ? error.message : String(error),
      error: {
        message: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
      },
      time_completed: Date.now(),
    });
    throw error;
  }
}
