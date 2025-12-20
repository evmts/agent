/**
 * Tests for part models and type guards.
 */

import { describe, test, expect } from 'bun:test';
import {
  type Part,
  type TextPart,
  type ReasoningPart,
  type ToolPart,
  type FilePart,
  type ToolState,
  type ToolStatePending,
  type ToolStateRunning,
  type ToolStateCompleted,
  isTextPart,
  isReasoningPart,
  isToolPart,
  isFilePart,
} from '../part';

describe('TextPart structure', () => {
  test('has required fields', () => {
    const textPart: TextPart = {
      id: 'part-1',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'text',
      text: 'Hello, world!',
    };

    expect(textPart.id).toBe('part-1');
    expect(textPart.sessionID).toBe('session-1');
    expect(textPart.messageID).toBe('msg-1');
    expect(textPart.type).toBe('text');
    expect(textPart.text).toBe('Hello, world!');
  });

  test('supports optional time field', () => {
    const now = Date.now();
    const textPart: TextPart = {
      id: 'part-1',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'text',
      text: 'Hello, world!',
      time: {
        start: now,
        end: now + 1000,
      },
    };

    expect(textPart.time?.start).toBe(now);
    expect(textPart.time?.end).toBe(now + 1000);
  });

  test('can have empty text', () => {
    const textPart: TextPart = {
      id: 'part-1',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'text',
      text: '',
    };

    expect(textPart.text).toBe('');
  });

  test('can have multiline text', () => {
    const textPart: TextPart = {
      id: 'part-1',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'text',
      text: 'Line 1\nLine 2\nLine 3',
    };

    expect(textPart.text).toContain('\n');
  });
});

describe('ReasoningPart structure', () => {
  test('has required fields', () => {
    const now = Date.now();
    const reasoningPart: ReasoningPart = {
      id: 'part-2',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'reasoning',
      text: 'Let me think about this...',
      time: {
        start: now,
      },
    };

    expect(reasoningPart.id).toBe('part-2');
    expect(reasoningPart.sessionID).toBe('session-1');
    expect(reasoningPart.messageID).toBe('msg-1');
    expect(reasoningPart.type).toBe('reasoning');
    expect(reasoningPart.text).toBe('Let me think about this...');
    expect(reasoningPart.time.start).toBe(now);
  });

  test('supports time with end', () => {
    const now = Date.now();
    const reasoningPart: ReasoningPart = {
      id: 'part-2',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'reasoning',
      text: 'Reasoning complete',
      time: {
        start: now,
        end: now + 5000,
      },
    };

    expect(reasoningPart.time.start).toBe(now);
    expect(reasoningPart.time.end).toBe(now + 5000);
  });
});

describe('ToolPart structure with ToolState', () => {
  test('supports pending state', () => {
    const toolPart: ToolPart = {
      id: 'part-3',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'tool',
      tool: 'readFile',
      state: {
        status: 'pending',
        input: { path: '/home/user/file.txt' },
        raw: 'read /home/user/file.txt',
      },
    };

    expect(toolPart.tool).toBe('readFile');
    expect(toolPart.state.status).toBe('pending');

    if (toolPart.state.status === 'pending') {
      expect(toolPart.state.input).toEqual({ path: '/home/user/file.txt' });
      expect(toolPart.state.raw).toBe('read /home/user/file.txt');
    }
  });

  test('supports running state', () => {
    const now = Date.now();
    const toolPart: ToolPart = {
      id: 'part-3',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'tool',
      tool: 'bash',
      state: {
        status: 'running',
        input: { command: 'ls -la' },
        title: 'List files',
        metadata: { timeout: 5000 },
        time: {
          start: now,
        },
      },
    };

    expect(toolPart.state.status).toBe('running');

    if (toolPart.state.status === 'running') {
      expect(toolPart.state.input).toEqual({ command: 'ls -la' });
      expect(toolPart.state.title).toBe('List files');
      expect(toolPart.state.metadata?.timeout).toBe(5000);
      expect(toolPart.state.time.start).toBe(now);
    }
  });

  test('supports completed state', () => {
    const now = Date.now();
    const toolPart: ToolPart = {
      id: 'part-3',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'tool',
      tool: 'grep',
      state: {
        status: 'completed',
        input: { pattern: 'TODO', path: '.' },
        output: 'Found 5 matches',
        title: 'Search for TODO',
        metadata: { matches: 5 },
        time: {
          start: now,
          end: now + 1000,
        },
      },
    };

    expect(toolPart.state.status).toBe('completed');

    if (toolPart.state.status === 'completed') {
      expect(toolPart.state.input).toEqual({ pattern: 'TODO', path: '.' });
      expect(toolPart.state.output).toBe('Found 5 matches');
      expect(toolPart.state.title).toBe('Search for TODO');
      expect(toolPart.state.metadata?.matches).toBe(5);
      expect(toolPart.state.time.start).toBe(now);
      expect(toolPart.state.time.end).toBe(now + 1000);
    }
  });

  test('supports empty input object', () => {
    const toolPart: ToolPart = {
      id: 'part-3',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'tool',
      tool: 'status',
      state: {
        status: 'pending',
        input: {},
        raw: 'status',
      },
    };

    expect(toolPart.state.status).toBe('pending');
    if (toolPart.state.status === 'pending') {
      expect(Object.keys(toolPart.state.input).length).toBe(0);
    }
  });
});

describe('FilePart structure', () => {
  test('has required fields', () => {
    const filePart: FilePart = {
      id: 'part-4',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'file',
      mime: 'image/png',
      url: 'https://example.com/image.png',
    };

    expect(filePart.id).toBe('part-4');
    expect(filePart.sessionID).toBe('session-1');
    expect(filePart.messageID).toBe('msg-1');
    expect(filePart.type).toBe('file');
    expect(filePart.mime).toBe('image/png');
    expect(filePart.url).toBe('https://example.com/image.png');
  });

  test('supports optional filename', () => {
    const filePart: FilePart = {
      id: 'part-4',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'file',
      mime: 'application/pdf',
      url: 'https://example.com/doc.pdf',
      filename: 'document.pdf',
    };

    expect(filePart.filename).toBe('document.pdf');
  });

  test('supports various mime types', () => {
    const mimeTypes = [
      'image/png',
      'image/jpeg',
      'application/pdf',
      'text/plain',
      'video/mp4',
      'audio/mpeg',
    ];

    mimeTypes.forEach((mime) => {
      const filePart: FilePart = {
        id: 'part-4',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'file',
        mime,
        url: 'https://example.com/file',
      };

      expect(filePart.mime).toBe(mime);
    });
  });
});

describe('isTextPart', () => {
  test('returns true for text parts', () => {
    const part: Part = {
      id: 'part-1',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'text',
      text: 'Hello',
    };

    expect(isTextPart(part)).toBe(true);
  });

  test('returns false for non-text parts', () => {
    const parts: Part[] = [
      {
        id: 'part-2',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'reasoning',
        text: 'Thinking...',
        time: { start: Date.now() },
      },
      {
        id: 'part-3',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'tool',
        tool: 'bash',
        state: {
          status: 'pending',
          input: {},
          raw: 'test',
        },
      },
      {
        id: 'part-4',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'file',
        mime: 'image/png',
        url: 'https://example.com/image.png',
      },
    ];

    parts.forEach((part) => {
      expect(isTextPart(part)).toBe(false);
    });
  });

  test('type guard narrows type correctly', () => {
    const part: Part = {
      id: 'part-1',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'text',
      text: 'Hello',
    };

    if (isTextPart(part)) {
      // TypeScript should know this is a TextPart
      expect(part.text).toBeDefined();
    }
  });
});

describe('isReasoningPart', () => {
  test('returns true for reasoning parts', () => {
    const part: Part = {
      id: 'part-2',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'reasoning',
      text: 'Analyzing...',
      time: { start: Date.now() },
    };

    expect(isReasoningPart(part)).toBe(true);
  });

  test('returns false for non-reasoning parts', () => {
    const parts: Part[] = [
      {
        id: 'part-1',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'text',
        text: 'Hello',
      },
      {
        id: 'part-3',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'tool',
        tool: 'bash',
        state: {
          status: 'pending',
          input: {},
          raw: 'test',
        },
      },
      {
        id: 'part-4',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'file',
        mime: 'image/png',
        url: 'https://example.com/image.png',
      },
    ];

    parts.forEach((part) => {
      expect(isReasoningPart(part)).toBe(false);
    });
  });

  test('type guard narrows type correctly', () => {
    const part: Part = {
      id: 'part-2',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'reasoning',
      text: 'Analyzing...',
      time: { start: Date.now() },
    };

    if (isReasoningPart(part)) {
      // TypeScript should know this is a ReasoningPart
      expect(part.time).toBeDefined();
    }
  });
});

describe('isToolPart', () => {
  test('returns true for tool parts', () => {
    const part: Part = {
      id: 'part-3',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'tool',
      tool: 'bash',
      state: {
        status: 'pending',
        input: {},
        raw: 'test',
      },
    };

    expect(isToolPart(part)).toBe(true);
  });

  test('returns false for non-tool parts', () => {
    const parts: Part[] = [
      {
        id: 'part-1',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'text',
        text: 'Hello',
      },
      {
        id: 'part-2',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'reasoning',
        text: 'Analyzing...',
        time: { start: Date.now() },
      },
      {
        id: 'part-4',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'file',
        mime: 'image/png',
        url: 'https://example.com/image.png',
      },
    ];

    parts.forEach((part) => {
      expect(isToolPart(part)).toBe(false);
    });
  });

  test('type guard narrows type correctly', () => {
    const part: Part = {
      id: 'part-3',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'tool',
      tool: 'bash',
      state: {
        status: 'pending',
        input: {},
        raw: 'test',
      },
    };

    if (isToolPart(part)) {
      // TypeScript should know this is a ToolPart
      expect(part.tool).toBeDefined();
      expect(part.state).toBeDefined();
    }
  });
});

describe('isFilePart', () => {
  test('returns true for file parts', () => {
    const part: Part = {
      id: 'part-4',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'file',
      mime: 'image/png',
      url: 'https://example.com/image.png',
    };

    expect(isFilePart(part)).toBe(true);
  });

  test('returns false for non-file parts', () => {
    const parts: Part[] = [
      {
        id: 'part-1',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'text',
        text: 'Hello',
      },
      {
        id: 'part-2',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'reasoning',
        text: 'Analyzing...',
        time: { start: Date.now() },
      },
      {
        id: 'part-3',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'tool',
        tool: 'bash',
        state: {
          status: 'pending',
          input: {},
          raw: 'test',
        },
      },
    ];

    parts.forEach((part) => {
      expect(isFilePart(part)).toBe(false);
    });
  });

  test('type guard narrows type correctly', () => {
    const part: Part = {
      id: 'part-4',
      sessionID: 'session-1',
      messageID: 'msg-1',
      type: 'file',
      mime: 'image/png',
      url: 'https://example.com/image.png',
    };

    if (isFilePart(part)) {
      // TypeScript should know this is a FilePart
      expect(part.mime).toBeDefined();
      expect(part.url).toBeDefined();
    }
  });
});

describe('Part union type', () => {
  test('can be any part type', () => {
    const parts: Part[] = [
      {
        id: 'part-1',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'text',
        text: 'Hello',
      },
      {
        id: 'part-2',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'reasoning',
        text: 'Analyzing...',
        time: { start: Date.now() },
      },
      {
        id: 'part-3',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'tool',
        tool: 'bash',
        state: {
          status: 'pending',
          input: {},
          raw: 'test',
        },
      },
      {
        id: 'part-4',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'file',
        mime: 'image/png',
        url: 'https://example.com/image.png',
      },
    ];

    expect(parts.length).toBe(4);
    expect(isTextPart(parts[0])).toBe(true);
    expect(isReasoningPart(parts[1])).toBe(true);
    expect(isToolPart(parts[2])).toBe(true);
    expect(isFilePart(parts[3])).toBe(true);
  });

  test('type guards can be used to filter parts', () => {
    const parts: Part[] = [
      {
        id: 'part-1',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'text',
        text: 'Hello',
      },
      {
        id: 'part-2',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'text',
        text: 'World',
      },
      {
        id: 'part-3',
        sessionID: 'session-1',
        messageID: 'msg-1',
        type: 'tool',
        tool: 'bash',
        state: {
          status: 'pending',
          input: {},
          raw: 'test',
        },
      },
    ];

    const textParts = parts.filter(isTextPart);
    const toolParts = parts.filter(isToolPart);

    expect(textParts.length).toBe(2);
    expect(toolParts.length).toBe(1);
  });
});
