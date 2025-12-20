/**
 * Unit tests for message routes.
 */

import { describe, test, expect, mock, beforeEach } from 'bun:test';
import { Hono } from 'hono';
import messagesApp, { handleCreateMessage, handleUpdateMessage } from '../messages';

// Mock dependencies
const mockSaveMessage = mock(async () => {});

mock.module('../../db/agent-state', () => ({
  saveMessage: mockSaveMessage,
}));

describe('Message Routes', () => {
  let app: Hono;

  beforeEach(() => {
    app = new Hono();
    app.route('/messages', messagesApp);
    mockSaveMessage.mockClear();
  });

  describe('GET /messages/health', () => {
    test('returns health status', async () => {
      const req = new Request('http://localhost/messages/health');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.status).toBe('ok');
    });
  });

  describe('handleCreateMessage', () => {
    test('calls saveMessage with message info', async () => {
      const message = {
        info: {
          id: 'msg-123',
          sessionId: 'session-123',
          role: 'user' as const,
          text: 'Test message',
          createdAt: new Date(),
        },
        parts: [],
      };

      await handleCreateMessage(message);

      expect(mockSaveMessage).toHaveBeenCalledTimes(1);
      expect(mockSaveMessage).toHaveBeenCalledWith(message.info);
    });

    test('handles messages with multiple parts', async () => {
      const message = {
        info: {
          id: 'msg-123',
          sessionId: 'session-123',
          role: 'assistant' as const,
          text: 'Response',
          createdAt: new Date(),
        },
        parts: [
          { type: 'text' as const, text: 'Part 1' },
          { type: 'text' as const, text: 'Part 2' },
        ],
      };

      await handleCreateMessage(message);

      expect(mockSaveMessage).toHaveBeenCalledTimes(1);
    });

    test('handles empty message text', async () => {
      const message = {
        info: {
          id: 'msg-123',
          sessionId: 'session-123',
          role: 'user' as const,
          text: '',
          createdAt: new Date(),
        },
        parts: [],
      };

      await handleCreateMessage(message);

      expect(mockSaveMessage).toHaveBeenCalledTimes(1);
    });
  });

  describe('handleUpdateMessage', () => {
    test('logs message update request', async () => {
      const consoleLogSpy = mock(() => {});
      const originalLog = console.log;
      console.log = consoleLogSpy;

      await handleUpdateMessage('msg-123', { text: 'Updated text' });

      expect(consoleLogSpy).toHaveBeenCalled();

      console.log = originalLog;
    });

    test('accepts partial updates', async () => {
      await handleUpdateMessage('msg-123', {
        text: 'New text',
      });

      // Should not throw
      expect(true).toBe(true);
    });

    test('handles empty updates object', async () => {
      await handleUpdateMessage('msg-123', {});

      // Should not throw
      expect(true).toBe(true);
    });
  });

  describe('MessageRouter', () => {
    test('exports MessageRouter class', async () => {
      const { MessageRouter } = await import('../messages');

      expect(MessageRouter).toBeDefined();
      expect(typeof MessageRouter).toBe('function');
    });

    test('can instantiate MessageRouter', async () => {
      const { MessageRouter } = await import('../messages');

      const router = new MessageRouter();

      expect(router).toBeDefined();
      expect(router instanceof MessageRouter).toBe(true);
    });
  });

  describe('Type exports', () => {
    test('exports MessageWithParts type', async () => {
      const module = await import('../messages');

      // Verify the type is exported (TypeScript check)
      expect('MessageWithParts' in module).toBe(true);
    });

    test('exports saveMessage function', async () => {
      const module = await import('../messages');

      expect(module.saveMessage).toBeDefined();
      expect(typeof module.saveMessage).toBe('function');
    });
  });

  describe('Error handling', () => {
    test('handles database errors in saveMessage', async () => {
      mockSaveMessage.mockRejectedValueOnce(new Error('Database error'));

      const message = {
        info: {
          id: 'msg-123',
          sessionId: 'session-123',
          role: 'user' as const,
          text: 'Test',
          createdAt: new Date(),
        },
        parts: [],
      };

      // Should throw or handle gracefully
      await expect(handleCreateMessage(message)).rejects.toThrow('Database error');
    });

    test('handles invalid message data', async () => {
      const invalidMessage: any = {
        info: null,
        parts: [],
      };

      // Should throw when trying to access message.info
      await expect(handleCreateMessage(invalidMessage)).rejects.toThrow();
    });
  });

  describe('Message validation', () => {
    test('validates message has required fields', async () => {
      const message = {
        info: {
          id: 'msg-123',
          sessionId: 'session-123',
          role: 'user' as const,
          text: 'Test message',
          createdAt: new Date(),
        },
        parts: [],
      };

      // All required fields present
      await handleCreateMessage(message);
      expect(mockSaveMessage).toHaveBeenCalled();
    });

    test('handles different message roles', async () => {
      const roles = ['user', 'assistant', 'system'] as const;

      for (const role of roles) {
        mockSaveMessage.mockClear();

        const message = {
          info: {
            id: `msg-${role}`,
            sessionId: 'session-123',
            role,
            text: `${role} message`,
            createdAt: new Date(),
          },
          parts: [],
        };

        await handleCreateMessage(message);
        expect(mockSaveMessage).toHaveBeenCalledTimes(1);
      }
    });
  });

  describe('Integration with parts', () => {
    test('handles tool use parts', async () => {
      const message = {
        info: {
          id: 'msg-123',
          sessionId: 'session-123',
          role: 'assistant' as const,
          text: '',
          createdAt: new Date(),
        },
        parts: [
          {
            type: 'tool_use' as const,
            id: 'tool-123',
            name: 'read_file',
            input: { path: '/test.ts' },
          },
        ],
      };

      await handleCreateMessage(message);
      expect(mockSaveMessage).toHaveBeenCalled();
    });

    test('handles tool result parts', async () => {
      const message = {
        info: {
          id: 'msg-123',
          sessionId: 'session-123',
          role: 'user' as const,
          text: '',
          createdAt: new Date(),
        },
        parts: [
          {
            type: 'tool_result' as const,
            tool_use_id: 'tool-123',
            content: 'File contents here',
          },
        ],
      };

      await handleCreateMessage(message);
      expect(mockSaveMessage).toHaveBeenCalled();
    });
  });
});
