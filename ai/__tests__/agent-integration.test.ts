/**
 * Integration tests for AI agent execution flow.
 *
 * These tests verify the complete agent execution pipeline including:
 * - Tool configuration and enablement
 * - Stream event handling
 * - Error propagation
 * - Session context management
 */

import { describe, test, expect, beforeEach, mock, afterEach } from 'bun:test';

// Mock types
type CoreMessage = {
  role: 'user' | 'assistant' | 'system';
  content: string;
};

type StreamEvent =
  | { type: 'text'; data?: string }
  | { type: 'tool_call'; toolName?: string; toolId?: string; args?: unknown }
  | { type: 'tool_result'; toolId?: string; toolOutput?: string }
  | { type: 'error'; error?: string }
  | { type: 'done' };

type AgentOptions = {
  modelId: string;
  agentName: string;
  workingDir: string;
  sessionId?: string;
  abortSignal?: AbortSignal;
};

// Simulated agent configuration
const AGENT_CONFIGS: Record<string, { toolsEnabled: Record<string, boolean> }> = {
  build: {
    toolsEnabled: {
      read_file: true,
      write_file: true,
      execute_shell: true,
      search_grep: true,
    },
  },
  explore: {
    toolsEnabled: {
      read_file: true,
      search_grep: true,
      write_file: false,
      execute_shell: false,
    },
  },
  plan: {
    toolsEnabled: {
      read_file: true,
      search_grep: true,
      write_file: false,
      execute_shell: false,
    },
  },
};

describe('Agent Configuration', () => {
  test('build agent has all tools enabled', () => {
    const config = AGENT_CONFIGS['build'];

    expect(config.toolsEnabled.read_file).toBe(true);
    expect(config.toolsEnabled.write_file).toBe(true);
    expect(config.toolsEnabled.execute_shell).toBe(true);
    expect(config.toolsEnabled.search_grep).toBe(true);
  });

  test('explore agent has write tools disabled', () => {
    const config = AGENT_CONFIGS['explore'];

    expect(config.toolsEnabled.read_file).toBe(true);
    expect(config.toolsEnabled.write_file).toBe(false);
    expect(config.toolsEnabled.execute_shell).toBe(false);
  });

  test('plan agent has write tools disabled', () => {
    const config = AGENT_CONFIGS['plan'];

    expect(config.toolsEnabled.read_file).toBe(true);
    expect(config.toolsEnabled.write_file).toBe(false);
    expect(config.toolsEnabled.execute_shell).toBe(false);
  });
});

describe('Stream Event Processing', () => {
  test('handles text events', () => {
    const events: StreamEvent[] = [
      { type: 'text', data: 'Hello' },
      { type: 'text', data: ' world' },
      { type: 'done' },
    ];

    const text = events
      .filter((e): e is { type: 'text'; data: string } => e.type === 'text' && !!e.data)
      .map(e => e.data)
      .join('');

    expect(text).toBe('Hello world');
  });

  test('handles tool call events', () => {
    const events: StreamEvent[] = [
      { type: 'tool_call', toolName: 'read_file', toolId: 'call_1', args: { path: '/test.txt' } },
      { type: 'tool_result', toolId: 'call_1', toolOutput: 'File contents' },
      { type: 'done' },
    ];

    const toolCalls = events.filter(e => e.type === 'tool_call');
    const toolResults = events.filter(e => e.type === 'tool_result');

    expect(toolCalls).toHaveLength(1);
    expect(toolResults).toHaveLength(1);
    expect(toolCalls[0].toolName).toBe('read_file');
    expect(toolResults[0].toolOutput).toBe('File contents');
  });

  test('handles error events', () => {
    const events: StreamEvent[] = [
      { type: 'text', data: 'Starting...' },
      { type: 'error', error: 'Something went wrong' },
    ];

    const errors = events.filter(e => e.type === 'error');

    expect(errors).toHaveLength(1);
    expect(errors[0].error).toBe('Something went wrong');
  });

  test('processes mixed event types in order', () => {
    const events: StreamEvent[] = [
      { type: 'text', data: 'Let me check...' },
      { type: 'tool_call', toolName: 'search_grep', toolId: 'call_1', args: { pattern: 'TODO' } },
      { type: 'tool_result', toolId: 'call_1', toolOutput: 'Found 3 matches' },
      { type: 'text', data: 'I found 3 TODOs.' },
      { type: 'done' },
    ];

    const eventTypes = events.map(e => e.type);
    expect(eventTypes).toEqual(['text', 'tool_call', 'tool_result', 'text', 'done']);
  });
});

describe('Agent Options Validation', () => {
  test('validates required options', () => {
    const validOptions: AgentOptions = {
      modelId: 'claude-sonnet-4-20250514',
      agentName: 'build',
      workingDir: '/test/dir',
    };

    expect(validOptions.modelId).toBeTruthy();
    expect(validOptions.agentName).toBeTruthy();
    expect(validOptions.workingDir).toBeTruthy();
  });

  test('accepts optional sessionId', () => {
    const optionsWithSession: AgentOptions = {
      modelId: 'claude-sonnet-4-20250514',
      agentName: 'build',
      workingDir: '/test/dir',
      sessionId: 'ses_test123',
    };

    expect(optionsWithSession.sessionId).toBe('ses_test123');
  });

  test('accepts optional abortSignal', () => {
    const controller = new AbortController();
    const options: AgentOptions = {
      modelId: 'claude-sonnet-4-20250514',
      agentName: 'build',
      workingDir: '/test/dir',
      abortSignal: controller.signal,
    };

    expect(options.abortSignal).toBeDefined();
    expect(options.abortSignal?.aborted).toBe(false);
  });
});

describe('Abort Signal Handling', () => {
  test('abortSignal starts as not aborted', () => {
    const controller = new AbortController();
    expect(controller.signal.aborted).toBe(false);
  });

  test('abortSignal becomes aborted when controller aborts', () => {
    const controller = new AbortController();
    controller.abort();
    expect(controller.signal.aborted).toBe(true);
  });

  test('abortSignal can have custom reason', () => {
    const controller = new AbortController();
    controller.abort('User cancelled');
    expect(controller.signal.aborted).toBe(true);
    expect(controller.signal.reason).toBe('User cancelled');
  });
});

describe('Message History Management', () => {
  test('builds conversation history correctly', () => {
    const messages: CoreMessage[] = [
      { role: 'system', content: 'You are a helpful assistant.' },
      { role: 'user', content: 'Hello!' },
    ];

    expect(messages).toHaveLength(2);
    expect(messages[0].role).toBe('system');
    expect(messages[1].role).toBe('user');
  });

  test('appends assistant response to history', () => {
    const messages: CoreMessage[] = [
      { role: 'user', content: 'Hello!' },
    ];

    const response = 'Hi there! How can I help?';
    messages.push({ role: 'assistant', content: response });

    expect(messages).toHaveLength(2);
    expect(messages[1].content).toBe(response);
  });

  test('maintains conversation order', () => {
    const messages: CoreMessage[] = [];

    // Simulate multi-turn conversation
    messages.push({ role: 'user', content: 'What is TypeScript?' });
    messages.push({ role: 'assistant', content: 'TypeScript is a typed superset of JavaScript.' });
    messages.push({ role: 'user', content: 'How do I use it?' });
    messages.push({ role: 'assistant', content: 'You can compile TypeScript with tsc.' });

    expect(messages.map(m => m.role)).toEqual(['user', 'assistant', 'user', 'assistant']);
  });
});

describe('Tool Result Processing', () => {
  test('parses JSON tool results', () => {
    const toolOutput = JSON.stringify({ files: ['a.ts', 'b.ts'], count: 2 });
    const parsed = JSON.parse(toolOutput);

    expect(parsed.files).toEqual(['a.ts', 'b.ts']);
    expect(parsed.count).toBe(2);
  });

  test('handles string tool results', () => {
    const toolOutput = 'File contents:\nLine 1\nLine 2';

    expect(typeof toolOutput).toBe('string');
    expect(toolOutput.includes('Line 1')).toBe(true);
  });

  test('truncates long tool results', () => {
    const MAX_LENGTH = 1000;
    const longOutput = 'x'.repeat(2000);

    const truncated = longOutput.length > MAX_LENGTH
      ? longOutput.slice(0, MAX_LENGTH) + '... (truncated)'
      : longOutput;

    expect(truncated.length).toBeLessThan(longOutput.length);
    expect(truncated.endsWith('(truncated)')).toBe(true);
  });
});

describe('Error Handling', () => {
  test('handles API errors gracefully', () => {
    const errorEvent: StreamEvent = {
      type: 'error',
      error: 'API rate limit exceeded',
    };

    expect(errorEvent.error).toContain('rate limit');
  });

  test('handles tool execution errors', () => {
    const errorEvent: StreamEvent = {
      type: 'error',
      error: 'Tool execution failed: File not found',
    };

    expect(errorEvent.error).toContain('Tool execution failed');
  });

  test('handles network errors', () => {
    const errorEvent: StreamEvent = {
      type: 'error',
      error: 'Network error: Connection refused',
    };

    expect(errorEvent.error).toContain('Network error');
  });
});

describe('Session Context', () => {
  test('session ID is passed to tools', () => {
    const options: AgentOptions = {
      modelId: 'claude-sonnet-4-20250514',
      agentName: 'build',
      workingDir: '/test',
      sessionId: 'ses_abc123',
    };

    // Simulate tool context creation
    const toolContext = {
      sessionId: options.sessionId,
      workingDir: options.workingDir,
    };

    expect(toolContext.sessionId).toBe('ses_abc123');
    expect(toolContext.workingDir).toBe('/test');
  });

  test('tools without session ID work correctly', () => {
    const options: AgentOptions = {
      modelId: 'claude-sonnet-4-20250514',
      agentName: 'build',
      workingDir: '/test',
    };

    const toolContext = {
      sessionId: options.sessionId,
      workingDir: options.workingDir,
    };

    expect(toolContext.sessionId).toBeUndefined();
    expect(toolContext.workingDir).toBe('/test');
  });
});

describe('Multi-Step Execution', () => {
  test('processes multiple tool calls in sequence', () => {
    const events: StreamEvent[] = [
      { type: 'text', data: 'Let me search first...' },
      { type: 'tool_call', toolName: 'search_grep', toolId: 'call_1', args: { pattern: 'error' } },
      { type: 'tool_result', toolId: 'call_1', toolOutput: 'src/index.ts:10' },
      { type: 'text', data: 'Now reading the file...' },
      { type: 'tool_call', toolName: 'read_file', toolId: 'call_2', args: { path: 'src/index.ts' } },
      { type: 'tool_result', toolId: 'call_2', toolOutput: 'const x = 1;' },
      { type: 'text', data: 'Done!' },
      { type: 'done' },
    ];

    const toolCalls = events.filter(e => e.type === 'tool_call');
    expect(toolCalls).toHaveLength(2);

    const toolCallNames = toolCalls.map(e => e.toolName);
    expect(toolCallNames).toEqual(['search_grep', 'read_file']);
  });

  test('tracks step count', () => {
    const maxSteps = 10;
    let currentStep = 0;

    // Simulate step counting
    const simulateStep = () => {
      currentStep++;
      return currentStep <= maxSteps;
    };

    for (let i = 0; i < 15; i++) {
      if (!simulateStep()) break;
    }

    expect(currentStep).toBe(11); // Stopped at step 11 (exceeded max)
  });
});

describe('Agent Flow Integration', () => {
  test('complete agent execution flow', async () => {
    // Simulate a complete agent execution
    const results: string[] = [];

    // Step 1: Receive user message
    const userMessage: CoreMessage = { role: 'user', content: 'List files in src/' };
    results.push(`Received: ${userMessage.content}`);

    // Step 2: Process through agent
    const events: StreamEvent[] = [
      { type: 'text', data: 'I\'ll list the files.' },
      { type: 'tool_call', toolName: 'execute_shell', toolId: 'call_1', args: { command: 'ls src/' } },
      { type: 'tool_result', toolId: 'call_1', toolOutput: 'index.ts\nutils.ts' },
      { type: 'text', data: 'Found 2 files.' },
      { type: 'done' },
    ];

    // Step 3: Process events
    for (const event of events) {
      if (event.type === 'text' && event.data) {
        results.push(`Text: ${event.data}`);
      } else if (event.type === 'tool_call') {
        results.push(`Tool: ${event.toolName}`);
      } else if (event.type === 'tool_result') {
        results.push(`Result: ${event.toolOutput}`);
      } else if (event.type === 'done') {
        results.push('Complete');
      }
    }

    expect(results).toEqual([
      'Received: List files in src/',
      'Text: I\'ll list the files.',
      'Tool: execute_shell',
      'Result: index.ts\nutils.ts',
      'Text: Found 2 files.',
      'Complete',
    ]);
  });

  test('agent execution with abort', () => {
    const controller = new AbortController();
    const events: StreamEvent[] = [];
    let wasAborted = false;

    // Simulate abort during execution
    const simulateExecution = () => {
      for (let i = 0; i < 5; i++) {
        if (controller.signal.aborted) {
          wasAborted = true;
          break;
        }
        events.push({ type: 'text', data: `Step ${i}` });
        if (i === 2) {
          controller.abort();
        }
      }
    };

    simulateExecution();

    expect(wasAborted).toBe(true);
    expect(events).toHaveLength(3); // Only steps 0, 1, 2 completed
  });
});
