/**
 * Tests for message models and type guards.
 */

import { describe, test, expect } from 'bun:test';
import {
  type Message,
  type UserMessage,
  type AssistantMessage,
  type MessageStatus,
  isUserMessage,
  isAssistantMessage,
} from '../message';

describe('MessageStatus type', () => {
  test('has all expected literal values', () => {
    const statuses: MessageStatus[] = [
      'pending',
      'streaming',
      'completed',
      'failed',
      'aborted',
    ];

    // Verify each status is assignable to MessageStatus
    statuses.forEach((status) => {
      const typed: MessageStatus = status;
      expect(typed).toBe(status);
    });
  });
});

describe('UserMessage structure', () => {
  test('has required fields', () => {
    const userMessage: UserMessage = {
      id: 'msg-123',
      sessionID: 'session-456',
      role: 'user',
      time: {
        created: Date.now(),
      },
      status: 'completed',
      agent: 'default',
      model: {
        providerID: 'anthropic',
        modelID: 'claude-3-opus',
      },
    };

    expect(userMessage.id).toBe('msg-123');
    expect(userMessage.sessionID).toBe('session-456');
    expect(userMessage.role).toBe('user');
    expect(userMessage.status).toBe('completed');
    expect(userMessage.agent).toBe('default');
    expect(userMessage.model.providerID).toBe('anthropic');
    expect(userMessage.model.modelID).toBe('claude-3-opus');
  });

  test('supports optional fields', () => {
    const userMessage: UserMessage = {
      id: 'msg-123',
      sessionID: 'session-456',
      role: 'user',
      time: {
        created: Date.now(),
        completed: Date.now() + 1000,
      },
      status: 'completed',
      agent: 'default',
      model: {
        providerID: 'anthropic',
        modelID: 'claude-3-opus',
      },
      thinkingText: 'Processing...',
      errorMessage: 'Something went wrong',
      system: 'You are a helpful assistant',
      tools: {
        read: true,
        write: false,
      },
    };

    expect(userMessage.thinkingText).toBe('Processing...');
    expect(userMessage.errorMessage).toBe('Something went wrong');
    expect(userMessage.system).toBe('You are a helpful assistant');
    expect(userMessage.tools?.read).toBe(true);
    expect(userMessage.tools?.write).toBe(false);
  });

  test('supports all MessageStatus values', () => {
    const statuses: MessageStatus[] = ['pending', 'streaming', 'completed', 'failed', 'aborted'];

    statuses.forEach((status) => {
      const msg: UserMessage = {
        id: 'msg-123',
        sessionID: 'session-456',
        role: 'user',
        time: { created: Date.now() },
        status,
        agent: 'default',
        model: {
          providerID: 'anthropic',
          modelID: 'claude-3-opus',
        },
      };
      expect(msg.status).toBe(status);
    });
  });
});

describe('AssistantMessage structure', () => {
  test('has required fields', () => {
    const assistantMessage: AssistantMessage = {
      id: 'msg-789',
      sessionID: 'session-456',
      role: 'assistant',
      time: {
        created: Date.now(),
      },
      status: 'completed',
      parentID: 'msg-123',
      modelID: 'claude-3-opus',
      providerID: 'anthropic',
      mode: 'chat',
      path: {
        cwd: '/home/user',
        root: '/home',
      },
      cost: 0.05,
      tokens: {
        input: 100,
        output: 200,
        reasoning: 50,
      },
    };

    expect(assistantMessage.id).toBe('msg-789');
    expect(assistantMessage.sessionID).toBe('session-456');
    expect(assistantMessage.role).toBe('assistant');
    expect(assistantMessage.status).toBe('completed');
    expect(assistantMessage.parentID).toBe('msg-123');
    expect(assistantMessage.modelID).toBe('claude-3-opus');
    expect(assistantMessage.providerID).toBe('anthropic');
    expect(assistantMessage.mode).toBe('chat');
    expect(assistantMessage.path.cwd).toBe('/home/user');
    expect(assistantMessage.cost).toBe(0.05);
    expect(assistantMessage.tokens.input).toBe(100);
  });

  test('supports optional fields', () => {
    const assistantMessage: AssistantMessage = {
      id: 'msg-789',
      sessionID: 'session-456',
      role: 'assistant',
      time: {
        created: Date.now(),
        completed: Date.now() + 1000,
      },
      status: 'completed',
      parentID: 'msg-123',
      modelID: 'claude-3-opus',
      providerID: 'anthropic',
      mode: 'chat',
      path: {
        cwd: '/home/user',
        root: '/home',
      },
      cost: 0.05,
      tokens: {
        input: 100,
        output: 200,
        reasoning: 50,
        cache: {
          read: 500,
          write: 100,
        },
      },
      thinkingText: 'Analyzing...',
      errorMessage: 'API error',
      finish: 'stop',
      summary: true,
      error: {
        code: 'RATE_LIMIT',
        message: 'Rate limit exceeded',
      },
    };

    expect(assistantMessage.thinkingText).toBe('Analyzing...');
    expect(assistantMessage.errorMessage).toBe('API error');
    expect(assistantMessage.finish).toBe('stop');
    expect(assistantMessage.summary).toBe(true);
    expect(assistantMessage.error?.code).toBe('RATE_LIMIT');
    expect(assistantMessage.tokens.cache?.read).toBe(500);
  });

  test('supports token cache information', () => {
    const assistantMessage: AssistantMessage = {
      id: 'msg-789',
      sessionID: 'session-456',
      role: 'assistant',
      time: { created: Date.now() },
      status: 'completed',
      parentID: 'msg-123',
      modelID: 'claude-3-opus',
      providerID: 'anthropic',
      mode: 'chat',
      path: { cwd: '/home/user', root: '/home' },
      cost: 0.05,
      tokens: {
        input: 100,
        output: 200,
        reasoning: 50,
        cache: {
          read: 1000,
          write: 500,
        },
      },
    };

    expect(assistantMessage.tokens.cache).toBeDefined();
    expect(assistantMessage.tokens.cache?.read).toBe(1000);
    expect(assistantMessage.tokens.cache?.write).toBe(500);
  });
});

describe('isUserMessage', () => {
  test('returns true for user messages', () => {
    const userMessage: Message = {
      id: 'msg-123',
      sessionID: 'session-456',
      role: 'user',
      time: { created: Date.now() },
      status: 'completed',
      agent: 'default',
      model: {
        providerID: 'anthropic',
        modelID: 'claude-3-opus',
      },
    };

    expect(isUserMessage(userMessage)).toBe(true);
  });

  test('returns false for assistant messages', () => {
    const assistantMessage: Message = {
      id: 'msg-789',
      sessionID: 'session-456',
      role: 'assistant',
      time: { created: Date.now() },
      status: 'completed',
      parentID: 'msg-123',
      modelID: 'claude-3-opus',
      providerID: 'anthropic',
      mode: 'chat',
      path: { cwd: '/home/user', root: '/home' },
      cost: 0.05,
      tokens: {
        input: 100,
        output: 200,
        reasoning: 50,
      },
    };

    expect(isUserMessage(assistantMessage)).toBe(false);
  });

  test('type guard narrows type correctly', () => {
    const message: Message = {
      id: 'msg-123',
      sessionID: 'session-456',
      role: 'user',
      time: { created: Date.now() },
      status: 'completed',
      agent: 'default',
      model: {
        providerID: 'anthropic',
        modelID: 'claude-3-opus',
      },
    };

    if (isUserMessage(message)) {
      // TypeScript should know this is a UserMessage
      expect(message.agent).toBeDefined();
      expect(message.model).toBeDefined();
    }
  });
});

describe('isAssistantMessage', () => {
  test('returns true for assistant messages', () => {
    const assistantMessage: Message = {
      id: 'msg-789',
      sessionID: 'session-456',
      role: 'assistant',
      time: { created: Date.now() },
      status: 'completed',
      parentID: 'msg-123',
      modelID: 'claude-3-opus',
      providerID: 'anthropic',
      mode: 'chat',
      path: { cwd: '/home/user', root: '/home' },
      cost: 0.05,
      tokens: {
        input: 100,
        output: 200,
        reasoning: 50,
      },
    };

    expect(isAssistantMessage(assistantMessage)).toBe(true);
  });

  test('returns false for user messages', () => {
    const userMessage: Message = {
      id: 'msg-123',
      sessionID: 'session-456',
      role: 'user',
      time: { created: Date.now() },
      status: 'completed',
      agent: 'default',
      model: {
        providerID: 'anthropic',
        modelID: 'claude-3-opus',
      },
    };

    expect(isAssistantMessage(userMessage)).toBe(false);
  });

  test('type guard narrows type correctly', () => {
    const message: Message = {
      id: 'msg-789',
      sessionID: 'session-456',
      role: 'assistant',
      time: { created: Date.now() },
      status: 'completed',
      parentID: 'msg-123',
      modelID: 'claude-3-opus',
      providerID: 'anthropic',
      mode: 'chat',
      path: { cwd: '/home/user', root: '/home' },
      cost: 0.05,
      tokens: {
        input: 100,
        output: 200,
        reasoning: 50,
      },
    };

    if (isAssistantMessage(message)) {
      // TypeScript should know this is an AssistantMessage
      expect(message.parentID).toBeDefined();
      expect(message.cost).toBeDefined();
      expect(message.tokens).toBeDefined();
    }
  });
});

describe('Message union type', () => {
  test('can be either UserMessage or AssistantMessage', () => {
    const messages: Message[] = [
      {
        id: 'msg-1',
        sessionID: 'session-1',
        role: 'user',
        time: { created: Date.now() },
        status: 'completed',
        agent: 'default',
        model: { providerID: 'anthropic', modelID: 'claude-3-opus' },
      },
      {
        id: 'msg-2',
        sessionID: 'session-1',
        role: 'assistant',
        time: { created: Date.now() },
        status: 'completed',
        parentID: 'msg-1',
        modelID: 'claude-3-opus',
        providerID: 'anthropic',
        mode: 'chat',
        path: { cwd: '/home/user', root: '/home' },
        cost: 0.05,
        tokens: { input: 100, output: 200, reasoning: 50 },
      },
    ];

    expect(messages.length).toBe(2);
    expect(isUserMessage(messages[0])).toBe(true);
    expect(isAssistantMessage(messages[1])).toBe(true);
  });

  test('type guards can be used to filter messages', () => {
    const messages: Message[] = [
      {
        id: 'msg-1',
        sessionID: 'session-1',
        role: 'user',
        time: { created: Date.now() },
        status: 'completed',
        agent: 'default',
        model: { providerID: 'anthropic', modelID: 'claude-3-opus' },
      },
      {
        id: 'msg-2',
        sessionID: 'session-1',
        role: 'assistant',
        time: { created: Date.now() },
        status: 'completed',
        parentID: 'msg-1',
        modelID: 'claude-3-opus',
        providerID: 'anthropic',
        mode: 'chat',
        path: { cwd: '/home/user', root: '/home' },
        cost: 0.05,
        tokens: { input: 100, output: 200, reasoning: 50 },
      },
      {
        id: 'msg-3',
        sessionID: 'session-1',
        role: 'user',
        time: { created: Date.now() },
        status: 'completed',
        agent: 'default',
        model: { providerID: 'anthropic', modelID: 'claude-3-opus' },
      },
    ];

    const userMessages = messages.filter(isUserMessage);
    const assistantMessages = messages.filter(isAssistantMessage);

    expect(userMessages.length).toBe(2);
    expect(assistantMessages.length).toBe(1);
  });
});
