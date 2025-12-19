/**
 * Agent implementation using Vercel AI SDK.
 *
 * Provides the main agent functionality with tool calling support
 * using Claude via the Anthropic provider.
 */

import { anthropic } from '@ai-sdk/anthropic';
import { streamText, type StreamTextResult, type CoreMessage } from 'ai';
import { agentTools, type AgentToolName } from './tools';
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
}

export interface StreamEvent {
  type: 'text' | 'tool_call' | 'tool_result' | 'reasoning' | 'finish';
  data?: string;
  toolName?: string;
  toolInput?: Record<string, unknown>;
  toolOutput?: string;
  toolId?: string;
  finishReason?: string;
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
    prompt += '\n\n' + customPrompt;
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
  const tools = filterToolsForAgent(agentName);

  // Create the stream
  const result = streamText({
    model: anthropic(modelId),
    system: systemPrompt,
    messages,
    tools,
    maxSteps: options.maxSteps ?? DEFAULT_MAX_STEPS,
    maxTokens: options.maxTokens ?? DEFAULT_MAX_TOKENS,
    temperature: options.temperature ?? config.temperature,
  });

  // Transform the stream to our StreamEvent format
  for await (const part of result.fullStream) {
    switch (part.type) {
      case 'text-delta':
        yield {
          type: 'text',
          data: part.textDelta,
        };
        break;

      case 'reasoning':
        yield {
          type: 'reasoning',
          data: part.textDelta,
        };
        break;

      case 'tool-call':
        yield {
          type: 'tool_call',
          toolName: part.toolName,
          toolInput: part.args as Record<string, unknown>,
          toolId: part.toolCallId,
        };
        break;

      case 'tool-result':
        yield {
          type: 'tool_result',
          toolName: part.toolName,
          toolOutput: typeof part.result === 'string' ? part.result : JSON.stringify(part.result),
          toolId: part.toolCallId,
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
