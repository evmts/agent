/**
 * Unit tests for session routes.
 */

import { describe, test, expect, mock, beforeEach } from 'bun:test';
import { Hono } from 'hono';
import sessionsApp from '../sessions';

// Mock dependencies
const mockCreateSession = mock(async () => ({ id: 'session-123', directory: '/test', title: 'Test' }));
const mockGetSession = mock(() => ({ id: 'session-123', directory: '/test', title: 'Test' }));
const mockListSessions = mock(async () => []);
const mockUpdateSession = mock(async () => ({ id: 'session-123', title: 'Updated' }));
const mockDeleteSession = mock(async () => {});
const mockAbortSession = mock(() => true);
const mockGetSessionDiff = mock(async () => []);
const mockForkSession = mock(async () => ({ id: 'forked-session' }));
const mockRevertSession = mock(async () => ({ id: 'session-123' }));
const mockUnrevertSession = mock(async () => ({ id: 'session-123' }));
const mockUndoTurns = mock(async () => [1, 2, ['file.ts'], true]);

const mockGetSessionChanges = mock(async () => []);
const mockGetSessionConflicts = mock(async () => []);
const mockGetSessionOperations = mock(async () => []);
const mockGetSessionCurrentChange = mock(async () => 'change-123');
const mockRestoreSessionOperation = mock(async () => {});
const mockUndoLastOperation = mock(async () => {});
const mockComputeDiff = mock(async () => []);
const mockGetSessionFileAtChange = mock(async () => 'file contents');
const mockGetSessionFilesAtChange = mock(async () => []);

const mockGetServerEventBus = mock(() => ({ emit: mock(() => {}), on: mock(() => {}) }));
const mockRequireAuth = mock(async (c: any, next: any) => next());
const mockRequireActiveAccount = mock(async (c: any, next: any) => next());
const mockNotFoundError = class NotFoundError extends Error {};
const mockInvalidOperationError = class InvalidOperationError extends Error {};

mock.module('../../core/sessions', () => ({
  createSession: mockCreateSession,
  getSession: mockGetSession,
  listSessions: mockListSessions,
  updateSession: mockUpdateSession,
  deleteSession: mockDeleteSession,
  abortSession: mockAbortSession,
  getSessionDiff: mockGetSessionDiff,
  forkSession: mockForkSession,
  revertSession: mockRevertSession,
  unrevertSession: mockUnrevertSession,
  undoTurns: mockUndoTurns,
}));

mock.module('../../core/snapshots', () => ({
  getSessionChanges: mockGetSessionChanges,
  getSessionConflicts: mockGetSessionConflicts,
  getSessionOperations: mockGetSessionOperations,
  getSessionCurrentChange: mockGetSessionCurrentChange,
  restoreSessionOperation: mockRestoreSessionOperation,
  undoLastOperation: mockUndoLastOperation,
  computeDiff: mockComputeDiff,
  getSessionFileAtChange: mockGetSessionFileAtChange,
  getSessionFilesAtChange: mockGetSessionFilesAtChange,
}));

mock.module('../../core/exceptions', () => ({
  NotFoundError: mockNotFoundError,
  InvalidOperationError: mockInvalidOperationError,
}));

mock.module('../event-bus', () => ({
  getServerEventBus: mockGetServerEventBus,
}));

mock.module('../middleware/auth', () => ({
  requireAuth: mockRequireAuth,
  requireActiveAccount: mockRequireActiveAccount,
}));

describe('Session Routes', () => {
  let app: Hono;

  beforeEach(() => {
    app = new Hono();
    app.route('/sessions', sessionsApp);

    // Clear all mocks
    mockCreateSession.mockClear();
    mockGetSession.mockClear();
    mockListSessions.mockClear();
    mockUpdateSession.mockClear();
    mockDeleteSession.mockClear();
    mockAbortSession.mockClear();
    mockGetSessionDiff.mockClear();
    mockForkSession.mockClear();
    mockRevertSession.mockClear();
    mockUnrevertSession.mockClear();
    mockUndoTurns.mockClear();
    mockGetSessionChanges.mockClear();
    mockGetSessionConflicts.mockClear();
    mockGetSessionOperations.mockClear();
    mockGetSessionCurrentChange.mockClear();
    mockRestoreSessionOperation.mockClear();
    mockUndoLastOperation.mockClear();
    mockComputeDiff.mockClear();
    mockGetSessionFileAtChange.mockClear();
    mockGetSessionFilesAtChange.mockClear();
  });

  describe('GET /sessions', () => {
    test('lists all sessions', async () => {
      mockListSessions.mockResolvedValueOnce([
        { id: '1', title: 'Session 1' },
        { id: '2', title: 'Session 2' },
      ]);

      const req = new Request('http://localhost/sessions');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.sessions).toHaveLength(2);
    });

    test('returns empty array when no sessions', async () => {
      mockListSessions.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/sessions');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.sessions).toEqual([]);
    });
  });

  describe('POST /sessions', () => {
    test('creates new session with defaults', async () => {
      const req = new Request('http://localhost/sessions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(201);
      expect(data.session).toBeDefined();
      expect(mockCreateSession).toHaveBeenCalled();
    });

    test('creates session with custom parameters', async () => {
      const req = new Request('http://localhost/sessions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          directory: '/custom/path',
          title: 'Custom Session',
          model: 'claude-opus-4',
          bypassMode: true,
        }),
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(201);
      expect(mockCreateSession).toHaveBeenCalledWith(
        expect.objectContaining({
          directory: '/custom/path',
          title: 'Custom Session',
          model: 'claude-opus-4',
          bypassMode: true,
        }),
        expect.anything()
      );
    });

    test('uses process.cwd() as default directory', async () => {
      const req = new Request('http://localhost/sessions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: 'Test' }),
      });
      await app.fetch(req);

      expect(mockCreateSession).toHaveBeenCalledWith(
        expect.objectContaining({
          directory: expect.any(String),
        }),
        expect.anything()
      );
    });
  });

  describe('GET /sessions/:sessionId', () => {
    test('returns session by ID', async () => {
      const req = new Request('http://localhost/sessions/session-123');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.session.id).toBe('session-123');
    });

    test('returns 404 for non-existent session', async () => {
      mockGetSession.mockImplementationOnce(() => {
        throw new mockNotFoundError('Session not found');
      });

      const req = new Request('http://localhost/sessions/nonexistent');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Session not found');
    });
  });

  describe('PATCH /sessions/:sessionId', () => {
    test('updates session properties', async () => {
      const req = new Request('http://localhost/sessions/session-123', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: 'Updated Title',
          archived: true,
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(mockUpdateSession).toHaveBeenCalledWith(
        'session-123',
        expect.objectContaining({
          title: 'Updated Title',
          archived: true,
        }),
        expect.anything()
      );
    });

    test('returns 404 for non-existent session', async () => {
      mockUpdateSession.mockRejectedValueOnce(new mockNotFoundError('Session not found'));

      const req = new Request('http://localhost/sessions/nonexistent', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: 'New Title' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Session not found');
    });
  });

  describe('DELETE /sessions/:sessionId', () => {
    test('deletes session', async () => {
      const req = new Request('http://localhost/sessions/session-123', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.success).toBe(true);
      expect(mockDeleteSession).toHaveBeenCalledWith('session-123', expect.anything());
    });

    test('returns 404 for non-existent session', async () => {
      mockDeleteSession.mockRejectedValueOnce(new mockNotFoundError('Session not found'));

      const req = new Request('http://localhost/sessions/nonexistent', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Session not found');
    });
  });

  describe('POST /sessions/:sessionId/abort', () => {
    test('aborts session task', async () => {
      const req = new Request('http://localhost/sessions/session-123/abort', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.aborted).toBe(true);
    });

    test('returns 404 for non-existent session', async () => {
      mockAbortSession.mockImplementationOnce(() => {
        throw new mockNotFoundError('Session not found');
      });

      const req = new Request('http://localhost/sessions/nonexistent/abort', {
        method: 'POST',
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(404);
    });
  });

  describe('GET /sessions/:sessionId/diff', () => {
    test('returns session diffs', async () => {
      mockGetSessionDiff.mockResolvedValueOnce([
        { file: 'test.ts', changes: '+line1\n-line2' },
      ]);

      const req = new Request('http://localhost/sessions/session-123/diff');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.diffs).toHaveLength(1);
    });

    test('supports messageId query parameter', async () => {
      const req = new Request('http://localhost/sessions/session-123/diff?messageId=msg-123');
      await app.fetch(req);

      expect(mockGetSessionDiff).toHaveBeenCalledWith('session-123', 'msg-123');
    });
  });

  describe('POST /sessions/:sessionId/fork', () => {
    test('forks session', async () => {
      const req = new Request('http://localhost/sessions/session-123/fork', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: 'Forked Session' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(201);
      expect(data.session).toBeDefined();
      expect(mockForkSession).toHaveBeenCalled();
    });

    test('forks from specific message', async () => {
      const req = new Request('http://localhost/sessions/session-123/fork', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          messageId: 'msg-123',
          title: 'Forked',
        }),
      });
      await app.fetch(req);

      expect(mockForkSession).toHaveBeenCalledWith(
        'session-123',
        expect.anything(),
        'msg-123',
        'Forked'
      );
    });
  });

  describe('POST /sessions/:sessionId/revert', () => {
    test('reverts session to message', async () => {
      const req = new Request('http://localhost/sessions/session-123/revert', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messageId: 'msg-123' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(mockRevertSession).toHaveBeenCalledWith(
        'session-123',
        'msg-123',
        expect.anything(),
        undefined
      );
    });

    test('reverts to specific part', async () => {
      const req = new Request('http://localhost/sessions/session-123/revert', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          messageId: 'msg-123',
          partId: 'part-456',
        }),
      });
      await app.fetch(req);

      expect(mockRevertSession).toHaveBeenCalledWith(
        'session-123',
        'msg-123',
        expect.anything(),
        'part-456'
      );
    });

    test('returns 400 for invalid operation', async () => {
      mockRevertSession.mockRejectedValueOnce(new mockInvalidOperationError('Cannot revert'));

      const req = new Request('http://localhost/sessions/session-123/revert', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messageId: 'msg-123' }),
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(400);
    });
  });

  describe('POST /sessions/:sessionId/unrevert', () => {
    test('unreverts session', async () => {
      const req = new Request('http://localhost/sessions/session-123/unrevert', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(mockUnrevertSession).toHaveBeenCalledWith('session-123', expect.anything());
    });
  });

  describe('POST /sessions/:sessionId/undo', () => {
    test('undoes one turn by default', async () => {
      const req = new Request('http://localhost/sessions/session-123/undo', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.turnsUndone).toBe(1);
      expect(mockUndoTurns).toHaveBeenCalledWith('session-123', expect.anything(), 1);
    });

    test('undoes multiple turns', async () => {
      mockUndoTurns.mockResolvedValueOnce([3, 6, ['file1.ts', 'file2.ts'], true]);

      const req = new Request('http://localhost/sessions/session-123/undo', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ count: 3 }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.turnsUndone).toBe(3);
      expect(data.messagesRemoved).toBe(6);
      expect(mockUndoTurns).toHaveBeenCalledWith('session-123', expect.anything(), 3);
    });
  });

  describe('GET /sessions/:sessionId/changes', () => {
    test('returns session changes with limit', async () => {
      mockGetSessionChanges.mockResolvedValueOnce([
        { changeId: 'change1', description: 'Change 1' },
      ]);

      const req = new Request('http://localhost/sessions/session-123/changes?limit=50');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.changes).toHaveLength(1);
      expect(data.currentChangeId).toBe('change-123');
      expect(mockGetSessionChanges).toHaveBeenCalledWith('session-123', 50);
    });

    test('uses default limit of 50', async () => {
      mockGetSessionChanges.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/sessions/session-123/changes');
      await app.fetch(req);

      expect(mockGetSessionChanges).toHaveBeenCalledWith('session-123', 50);
    });

    test('verifies session exists before getting changes', async () => {
      mockGetSession.mockImplementationOnce(() => {
        throw new mockNotFoundError('Session not found');
      });

      const req = new Request('http://localhost/sessions/nonexistent/changes');
      const res = await app.fetch(req);

      expect(res.status).toBe(404);
    });
  });

  describe('GET /sessions/:sessionId/operations', () => {
    test('returns operation log with limit', async () => {
      mockGetSessionOperations.mockResolvedValueOnce([
        { id: 'op1', type: 'create' },
        { id: 'op2', type: 'update' },
      ]);

      const req = new Request('http://localhost/sessions/session-123/operations?limit=20');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.operations).toHaveLength(2);
      expect(data.total).toBe(2);
    });
  });

  describe('POST /sessions/:sessionId/operations/undo', () => {
    test('undoes last operation', async () => {
      const req = new Request('http://localhost/sessions/session-123/operations/undo', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.success).toBe(true);
      expect(mockUndoLastOperation).toHaveBeenCalledWith('session-123');
    });
  });

  describe('POST /sessions/:sessionId/operations/:operationId/restore', () => {
    test('restores to specific operation', async () => {
      const req = new Request('http://localhost/sessions/session-123/operations/op-456/restore', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.restoredTo).toBe('op-456');
      expect(mockRestoreSessionOperation).toHaveBeenCalledWith('session-123', 'op-456');
    });
  });

  describe('GET /sessions/:sessionId/changes/:changeId/file/*', () => {
    test('returns file content at change', async () => {
      const req = new Request('http://localhost/sessions/session-123/changes/change-456/file/src/test.ts');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.content).toBe('file contents');
      expect(data.filePath).toBe('src/test.ts');
      expect(data.changeId).toBe('change-456');
    });

    test('returns 400 when file path missing', async () => {
      const req = new Request('http://localhost/sessions/session-123/changes/change-456/file/');
      const res = await app.fetch(req);

      expect(res.status).toBe(400);
    });

    test('returns 404 when file not found at change', async () => {
      mockGetSessionFileAtChange.mockResolvedValueOnce(null);

      const req = new Request('http://localhost/sessions/session-123/changes/change-456/file/missing.ts');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('File not found at this change');
    });
  });

  describe('GET /sessions/:sessionId/conflicts', () => {
    test('returns conflicts for session', async () => {
      mockGetSessionConflicts.mockResolvedValueOnce([
        { file: 'test.ts', type: 'content' },
      ]);

      const req = new Request('http://localhost/sessions/session-123/conflicts');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.conflicts).toHaveLength(1);
      expect(data.hasConflicts).toBe(true);
    });

    test('supports optional changeId query parameter', async () => {
      mockGetSessionConflicts.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/sessions/session-123/conflicts?changeId=change-789');
      await app.fetch(req);

      expect(mockGetSessionConflicts).toHaveBeenCalledWith('session-123', 'change-789');
    });
  });
});
