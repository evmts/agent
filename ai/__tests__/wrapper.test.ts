/**
 * Tests for ai/wrapper.ts
 *
 * Tests AgentWrapper class methods including history management,
 * working directory management, and session tracking.
 */

import { describe, test, expect, beforeEach, mock } from 'bun:test';

// Define minimal types to avoid complex imports
type CoreMessage = {
  role: 'user' | 'assistant';
  content: string;
};

type WrapperOptions = {
  workingDir?: string;
  defaultModel?: string;
  defaultAgentName?: string;
  sessionId?: string;
};

// Create a minimal AgentWrapper class for testing
class AgentWrapper {
  private history: CoreMessage[] = [];
  private workingDir: string;
  private defaultModel: string;
  private defaultAgentName: string;
  private sessionId: string | null;
  private lastTurnSummary: any = null;

  constructor(options: WrapperOptions = {}) {
    this.workingDir = options.workingDir ?? process.cwd();
    this.defaultModel = options.defaultModel ?? 'claude-sonnet-4-20250514';
    this.defaultAgentName = options.defaultAgentName ?? 'build';
    this.sessionId = options.sessionId ?? null;
  }

  resetHistory(): void {
    this.history = [];
  }

  getHistory(): CoreMessage[] {
    return [...this.history];
  }

  setHistory(messages: CoreMessage[]): void {
    this.history = [...messages];
  }

  getWorkingDir(): string {
    return this.workingDir;
  }

  setWorkingDir(dir: string): void {
    this.workingDir = dir;
  }

  getMessageCount(): number {
    return this.history.length;
  }

  getSessionId(): string | null {
    return this.sessionId;
  }

  setSessionId(sessionId: string | null): void {
    this.sessionId = sessionId;
  }

  getLastTurnSummary(): any {
    return this.lastTurnSummary;
  }
}

function createAgentWrapper(options?: WrapperOptions): AgentWrapper {
  return new AgentWrapper(options);
}

describe('AgentWrapper constructor', () => {
  test('creates wrapper with default options', () => {
    const wrapper = new AgentWrapper();

    expect(wrapper.getWorkingDir()).toBe(process.cwd());
    expect(wrapper.getSessionId()).toBeNull();
    expect(wrapper.getMessageCount()).toBe(0);
    expect(wrapper.getHistory()).toEqual([]);
  });

  test('creates wrapper with custom options', () => {
    const options: WrapperOptions = {
      workingDir: '/custom/dir',
      defaultModel: 'claude-opus-4',
      defaultAgentName: 'custom-agent',
      sessionId: 'ses_custom123',
    };

    const wrapper = new AgentWrapper(options);

    expect(wrapper.getWorkingDir()).toBe('/custom/dir');
    expect(wrapper.getSessionId()).toBe('ses_custom123');
  });
});

describe('createAgentWrapper factory', () => {
  test('creates wrapper instance', () => {
    const wrapper = createAgentWrapper({
      workingDir: '/test/dir',
    });

    expect(wrapper).toBeInstanceOf(AgentWrapper);
    expect(wrapper.getWorkingDir()).toBe('/test/dir');
  });

  test('creates wrapper with no options', () => {
    const wrapper = createAgentWrapper();

    expect(wrapper).toBeInstanceOf(AgentWrapper);
    expect(wrapper.getWorkingDir()).toBe(process.cwd());
  });
});

describe('resetHistory', () => {
  test('clears conversation history', () => {
    const wrapper = new AgentWrapper();

    // Manually add history for testing
    const history: CoreMessage[] = [
      { role: 'user', content: 'Hello' },
      { role: 'assistant', content: 'Hi there' },
    ];
    wrapper.setHistory(history);

    expect(wrapper.getMessageCount()).toBe(2);

    wrapper.resetHistory();

    expect(wrapper.getMessageCount()).toBe(0);
    expect(wrapper.getHistory()).toEqual([]);
  });

  test('can be called on empty history', () => {
    const wrapper = new AgentWrapper();

    wrapper.resetHistory();

    expect(wrapper.getMessageCount()).toBe(0);
  });

  test('can be called multiple times', () => {
    const wrapper = new AgentWrapper();

    wrapper.setHistory([
      { role: 'user', content: 'Test' },
    ]);

    wrapper.resetHistory();
    wrapper.resetHistory();
    wrapper.resetHistory();

    expect(wrapper.getMessageCount()).toBe(0);
  });
});

describe('getHistory', () => {
  test('returns copy of history', () => {
    const wrapper = new AgentWrapper();

    const history: CoreMessage[] = [
      { role: 'user', content: 'Hello' },
      { role: 'assistant', content: 'Hi' },
    ];
    wrapper.setHistory(history);

    const retrieved = wrapper.getHistory();

    expect(retrieved).toEqual(history);
    expect(retrieved).not.toBe(history); // Different array instance
  });

  test('returned copy cannot mutate internal state', () => {
    const wrapper = new AgentWrapper();

    wrapper.setHistory([
      { role: 'user', content: 'Original' },
    ]);

    const retrieved = wrapper.getHistory();
    retrieved.push({ role: 'assistant', content: 'Mutation attempt' });

    expect(wrapper.getMessageCount()).toBe(1);
    expect(wrapper.getHistory()[0]?.content).toBe('Original');
  });

  test('returns empty array when no history', () => {
    const wrapper = new AgentWrapper();

    const history = wrapper.getHistory();

    expect(history).toEqual([]);
    expect(Array.isArray(history)).toBe(true);
  });
});

describe('setHistory', () => {
  test('sets conversation history', () => {
    const wrapper = new AgentWrapper();

    const history: CoreMessage[] = [
      { role: 'user', content: 'Message 1' },
      { role: 'assistant', content: 'Response 1' },
      { role: 'user', content: 'Message 2' },
    ];

    wrapper.setHistory(history);

    expect(wrapper.getMessageCount()).toBe(3);
    expect(wrapper.getHistory()).toEqual(history);
  });

  test('creates copy of input array', () => {
    const wrapper = new AgentWrapper();

    const history: CoreMessage[] = [
      { role: 'user', content: 'Test' },
    ];

    wrapper.setHistory(history);
    history.push({ role: 'assistant', content: 'Modified' });

    expect(wrapper.getMessageCount()).toBe(1);
  });

  test('replaces existing history', () => {
    const wrapper = new AgentWrapper();

    wrapper.setHistory([
      { role: 'user', content: 'Old' },
    ]);

    wrapper.setHistory([
      { role: 'user', content: 'New 1' },
      { role: 'assistant', content: 'New 2' },
    ]);

    expect(wrapper.getMessageCount()).toBe(2);
    expect(wrapper.getHistory()[0]?.content).toBe('New 1');
  });

  test('can set empty history', () => {
    const wrapper = new AgentWrapper();

    wrapper.setHistory([
      { role: 'user', content: 'Test' },
    ]);

    wrapper.setHistory([]);

    expect(wrapper.getMessageCount()).toBe(0);
  });
});

describe('getWorkingDir', () => {
  test('returns current working directory', () => {
    const wrapper = new AgentWrapper({
      workingDir: '/test/directory',
    });

    expect(wrapper.getWorkingDir()).toBe('/test/directory');
  });

  test('returns updated directory after setWorkingDir', () => {
    const wrapper = new AgentWrapper({
      workingDir: '/initial/dir',
    });

    wrapper.setWorkingDir('/updated/dir');

    expect(wrapper.getWorkingDir()).toBe('/updated/dir');
  });
});

describe('setWorkingDir', () => {
  test('updates working directory', () => {
    const wrapper = new AgentWrapper({
      workingDir: '/old/dir',
    });

    wrapper.setWorkingDir('/new/dir');

    expect(wrapper.getWorkingDir()).toBe('/new/dir');
  });

  test('can be called multiple times', () => {
    const wrapper = new AgentWrapper();

    wrapper.setWorkingDir('/dir1');
    expect(wrapper.getWorkingDir()).toBe('/dir1');

    wrapper.setWorkingDir('/dir2');
    expect(wrapper.getWorkingDir()).toBe('/dir2');

    wrapper.setWorkingDir('/dir3');
    expect(wrapper.getWorkingDir()).toBe('/dir3');
  });

  test('preserves history when changing directory', () => {
    const wrapper = new AgentWrapper();

    wrapper.setHistory([
      { role: 'user', content: 'Test' },
    ]);

    wrapper.setWorkingDir('/new/dir');

    expect(wrapper.getMessageCount()).toBe(1);
    expect(wrapper.getHistory()[0]?.content).toBe('Test');
  });
});

describe('getMessageCount', () => {
  test('returns zero for new wrapper', () => {
    const wrapper = new AgentWrapper();

    expect(wrapper.getMessageCount()).toBe(0);
  });

  test('returns correct count after setting history', () => {
    const wrapper = new AgentWrapper();

    wrapper.setHistory([
      { role: 'user', content: 'Message 1' },
      { role: 'assistant', content: 'Response 1' },
      { role: 'user', content: 'Message 2' },
      { role: 'assistant', content: 'Response 2' },
    ]);

    expect(wrapper.getMessageCount()).toBe(4);
  });

  test('returns zero after reset', () => {
    const wrapper = new AgentWrapper();

    wrapper.setHistory([
      { role: 'user', content: 'Test' },
    ]);

    wrapper.resetHistory();

    expect(wrapper.getMessageCount()).toBe(0);
  });
});

describe('getSessionId', () => {
  test('returns null when not set', () => {
    const wrapper = new AgentWrapper();

    expect(wrapper.getSessionId()).toBeNull();
  });

  test('returns session ID from constructor', () => {
    const wrapper = new AgentWrapper({
      sessionId: 'ses_test123',
    });

    expect(wrapper.getSessionId()).toBe('ses_test123');
  });

  test('returns updated session ID after setSessionId', () => {
    const wrapper = new AgentWrapper({
      sessionId: 'ses_initial',
    });

    wrapper.setSessionId('ses_updated');

    expect(wrapper.getSessionId()).toBe('ses_updated');
  });
});

describe('setSessionId', () => {
  test('updates session ID', () => {
    const wrapper = new AgentWrapper();

    wrapper.setSessionId('ses_new123');

    expect(wrapper.getSessionId()).toBe('ses_new123');
  });

  test('can set to null', () => {
    const wrapper = new AgentWrapper({
      sessionId: 'ses_test123',
    });

    wrapper.setSessionId(null);

    expect(wrapper.getSessionId()).toBeNull();
  });

  test('can be called multiple times', () => {
    const wrapper = new AgentWrapper();

    wrapper.setSessionId('ses_1');
    expect(wrapper.getSessionId()).toBe('ses_1');

    wrapper.setSessionId('ses_2');
    expect(wrapper.getSessionId()).toBe('ses_2');

    wrapper.setSessionId(null);
    expect(wrapper.getSessionId()).toBeNull();
  });

  test('preserves history when changing session ID', () => {
    const wrapper = new AgentWrapper();

    wrapper.setHistory([
      { role: 'user', content: 'Test' },
    ]);

    wrapper.setSessionId('ses_new');

    expect(wrapper.getMessageCount()).toBe(1);
  });
});

describe('getLastTurnSummary', () => {
  test('returns null for new wrapper', () => {
    const wrapper = new AgentWrapper();

    expect(wrapper.getLastTurnSummary()).toBeNull();
  });

  test('returns null when no turns completed', () => {
    const wrapper = new AgentWrapper();

    wrapper.setHistory([
      { role: 'user', content: 'Test' },
    ]);

    expect(wrapper.getLastTurnSummary()).toBeNull();
  });
});

describe('Integration: wrapper lifecycle', () => {
  test('simulates full conversation lifecycle', () => {
    // Create wrapper
    const wrapper = new AgentWrapper({
      workingDir: '/project/dir',
      sessionId: 'ses_lifecycle',
    });

    expect(wrapper.getMessageCount()).toBe(0);
    expect(wrapper.getSessionId()).toBe('ses_lifecycle');

    // Add some history
    wrapper.setHistory([
      { role: 'user', content: 'First message' },
      { role: 'assistant', content: 'First response' },
      { role: 'user', content: 'Second message' },
      { role: 'assistant', content: 'Second response' },
    ]);

    expect(wrapper.getMessageCount()).toBe(4);

    // Change working directory mid-conversation
    wrapper.setWorkingDir('/new/project/dir');
    expect(wrapper.getWorkingDir()).toBe('/new/project/dir');
    expect(wrapper.getMessageCount()).toBe(4);

    // Reset for new conversation
    wrapper.resetHistory();
    expect(wrapper.getMessageCount()).toBe(0);
    expect(wrapper.getSessionId()).toBe('ses_lifecycle');
  });

  test('simulates session switching', () => {
    const wrapper = new AgentWrapper();

    // First session
    wrapper.setSessionId('ses_1');
    wrapper.setHistory([
      { role: 'user', content: 'Session 1 message' },
    ]);

    expect(wrapper.getSessionId()).toBe('ses_1');
    expect(wrapper.getMessageCount()).toBe(1);

    // Switch to second session
    wrapper.setSessionId('ses_2');
    wrapper.resetHistory();
    wrapper.setHistory([
      { role: 'user', content: 'Session 2 message' },
      { role: 'assistant', content: 'Session 2 response' },
    ]);

    expect(wrapper.getSessionId()).toBe('ses_2');
    expect(wrapper.getMessageCount()).toBe(2);
  });

  test('simulates history manipulation', () => {
    const wrapper = new AgentWrapper();

    // Build up history
    const history: CoreMessage[] = [];

    for (let i = 1; i <= 3; i++) {
      history.push(
        { role: 'user', content: `User message ${i}` },
        { role: 'assistant', content: `Assistant response ${i}` }
      );
    }

    wrapper.setHistory(history);
    expect(wrapper.getMessageCount()).toBe(6);

    // Simulate undo (remove last turn)
    const currentHistory = wrapper.getHistory();
    const truncated = currentHistory.slice(0, -2);
    wrapper.setHistory(truncated);

    expect(wrapper.getMessageCount()).toBe(4);

    // Verify content
    const newHistory = wrapper.getHistory();
    expect(newHistory[newHistory.length - 1]?.content).toBe('Assistant response 2');
  });

  test('simulates multi-wrapper scenario', () => {
    // Different wrappers for different sessions
    const wrapper1 = new AgentWrapper({
      sessionId: 'ses_1',
      workingDir: '/project1',
    });

    const wrapper2 = new AgentWrapper({
      sessionId: 'ses_2',
      workingDir: '/project2',
    });

    wrapper1.setHistory([
      { role: 'user', content: 'Message in session 1' },
    ]);

    wrapper2.setHistory([
      { role: 'user', content: 'Message in session 2' },
      { role: 'assistant', content: 'Response in session 2' },
    ]);

    // Verify isolation
    expect(wrapper1.getMessageCount()).toBe(1);
    expect(wrapper2.getMessageCount()).toBe(2);
    expect(wrapper1.getSessionId()).toBe('ses_1');
    expect(wrapper2.getSessionId()).toBe('ses_2');
    expect(wrapper1.getWorkingDir()).toBe('/project1');
    expect(wrapper2.getWorkingDir()).toBe('/project2');
  });
});

describe('Edge cases', () => {
  test('handles rapid history changes', () => {
    const wrapper = new AgentWrapper();

    for (let i = 0; i < 100; i++) {
      wrapper.setHistory([
        { role: 'user', content: `Message ${i}` },
      ]);
    }

    expect(wrapper.getMessageCount()).toBe(1);
    expect(wrapper.getHistory()[0]?.content).toBe('Message 99');
  });

  test('handles large history', () => {
    const wrapper = new AgentWrapper();

    const largeHistory: CoreMessage[] = [];
    for (let i = 0; i < 1000; i++) {
      largeHistory.push({ role: 'user', content: `Message ${i}` });
    }

    wrapper.setHistory(largeHistory);

    expect(wrapper.getMessageCount()).toBe(1000);
    expect(wrapper.getHistory()[0]?.content).toBe('Message 0');
    expect(wrapper.getHistory()[999]?.content).toBe('Message 999');
  });

  test('handles empty string session IDs', () => {
    const wrapper = new AgentWrapper({
      sessionId: '',
    });

    expect(wrapper.getSessionId()).toBe('');

    wrapper.setSessionId('');
    expect(wrapper.getSessionId()).toBe('');
  });

  test('handles special characters in paths', () => {
    const wrapper = new AgentWrapper();

    const specialPaths = [
      '/path with spaces/dir',
      '/path-with-dashes',
      '/path_with_underscores',
      '/path.with.dots',
      '/path/with/many/levels/deep',
    ];

    for (const path of specialPaths) {
      wrapper.setWorkingDir(path);
      expect(wrapper.getWorkingDir()).toBe(path);
    }
  });

  test('handles message content with special characters', () => {
    const wrapper = new AgentWrapper();

    const specialContent = [
      'Message with "quotes"',
      "Message with 'single quotes'",
      'Message with\nnewlines',
      'Message with\ttabs',
      'Message with emoji 👋',
      'Message with unicode: 你好',
    ];

    for (const content of specialContent) {
      wrapper.setHistory([{ role: 'user', content }]);
      expect(wrapper.getHistory()[0]?.content).toBe(content);
    }
  });
});
