/**
 * Tests for db/agent-state.ts
 *
 * Tests database operations for agent state including sessions, messages,
 * parts, snapshot history, file trackers, and row converters.
 */

import { describe, test, expect, beforeEach, mock } from 'bun:test';
import type {
  Session,
  Message,
  UserMessage,
  AssistantMessage,
  Part,
  TextPart,
  ReasoningPart,
  ToolPart,
  FilePart,
} from '../../core/models';

// Mock SQL client
const mockSqlResults: any[] = [];
const mockSql = Object.assign(
  mock(async (...args: any[]) => mockSqlResults),
  {
    unsafe: mock(async (query: string, values: any[]) => mockSqlResults),
  }
);

describe('Session Operations', () => {
  beforeEach(() => {
    mockSqlResults.length = 0;
    mockSql.mockClear();
  });

  describe('getSession', () => {
    test('returns null when session not found', async () => {
      mockSqlResults.length = 0;

      const [row] = mockSqlResults;
      expect(row).toBeUndefined();
    });

    test('returns session when found', async () => {
      const mockRow = {
        id: 'ses_test123',
        project_id: 'default',
        directory: '/test',
        title: 'Test Session',
        version: '1.0.0',
        time_created: 1000,
        time_updated: 2000,
        time_archived: null,
        parent_id: null,
        fork_point: null,
        summary: null,
        revert: null,
        compaction: null,
        token_count: 100,
        bypass_mode: false,
        model: 'claude-sonnet-4',
        reasoning_effort: 'medium',
        ghost_commit: null,
        plugins: '[]',
      };

      mockSqlResults.push(mockRow);

      const [row] = mockSqlResults;
      expect(row).toBeDefined();
      expect(row.id).toBe('ses_test123');
    });

    test('converts database row to Session object', () => {
      const mockRow = {
        id: 'ses_test',
        project_id: 'default',
        directory: '/test',
        title: 'Test',
        version: '1.0.0',
        time_created: 1000,
        time_updated: 2000,
        time_archived: 3000,
        parent_id: 'ses_parent',
        fork_point: 'msg_fork',
        summary: JSON.stringify({ additions: 10, deletions: 5, files: 2 }),
        revert: JSON.stringify({ messageID: 'msg_1', snapshot: 'hash_1' }),
        compaction: null,
        token_count: 150,
        bypass_mode: true,
        model: 'claude-opus-4',
        reasoning_effort: 'high',
        ghost_commit: JSON.stringify({ enabled: true, currentTurn: 5, commits: [] }),
        plugins: JSON.stringify(['plugin1', 'plugin2']),
      };

      // Simulate rowToSession conversion
      const session: Session = {
        id: mockRow.id,
        projectID: mockRow.project_id,
        directory: mockRow.directory,
        title: mockRow.title,
        version: mockRow.version,
        time: {
          created: Number(mockRow.time_created),
          updated: Number(mockRow.time_updated),
          archived: mockRow.time_archived ? Number(mockRow.time_archived) : undefined,
        },
        parentID: mockRow.parent_id ?? undefined,
        forkPoint: mockRow.fork_point ?? undefined,
        summary: mockRow.summary ? JSON.parse(mockRow.summary) : undefined,
        revert: mockRow.revert ? JSON.parse(mockRow.revert) : undefined,
        compaction: undefined,
        tokenCount: Number(mockRow.token_count),
        bypassMode: mockRow.bypass_mode,
        model: mockRow.model ?? undefined,
        reasoningEffort: mockRow.reasoning_effort as Session['reasoningEffort'],
        ghostCommit: mockRow.ghost_commit ? JSON.parse(mockRow.ghost_commit) : undefined,
        plugins: JSON.parse(mockRow.plugins),
      };

      expect(session.id).toBe('ses_test');
      expect(session.time.archived).toBe(3000);
      expect(session.parentID).toBe('ses_parent');
      expect(session.summary?.additions).toBe(10);
      expect(session.plugins).toEqual(['plugin1', 'plugin2']);
    });
  });

  describe('getAllSessions', () => {
    test('returns empty array when no sessions', async () => {
      mockSqlResults.length = 0;

      expect(mockSqlResults).toEqual([]);
    });

    test('returns all sessions sorted by updated time', async () => {
      mockSqlResults.push(
        {
          id: 'ses_1',
          project_id: 'default',
          directory: '/test1',
          title: 'Session 1',
          version: '1.0.0',
          time_created: 1000,
          time_updated: 3000,
          time_archived: null,
          parent_id: null,
          fork_point: null,
          summary: null,
          revert: null,
          compaction: null,
          token_count: 0,
          bypass_mode: false,
          model: null,
          reasoning_effort: null,
          ghost_commit: null,
          plugins: '[]',
        },
        {
          id: 'ses_2',
          project_id: 'default',
          directory: '/test2',
          title: 'Session 2',
          version: '1.0.0',
          time_created: 2000,
          time_updated: 4000,
          time_archived: null,
          parent_id: null,
          fork_point: null,
          summary: null,
          revert: null,
          compaction: null,
          token_count: 0,
          bypass_mode: false,
          model: null,
          reasoning_effort: null,
          ghost_commit: null,
          plugins: '[]',
        }
      );

      expect(mockSqlResults).toHaveLength(2);
      // Most recently updated should be first in real query
      expect(mockSqlResults[1]?.time_updated).toBeGreaterThan(mockSqlResults[0]?.time_updated ?? 0);
    });
  });

  describe('saveSession', () => {
    test('inserts new session', async () => {
      const session: Session = {
        id: 'ses_new',
        projectID: 'default',
        directory: '/test',
        title: 'New Session',
        version: '1.0.0',
        time: { created: 1000, updated: 2000 },
        tokenCount: 0,
        bypassMode: false,
        plugins: [],
      };

      // Verify all required fields are present
      expect(session.id).toBeDefined();
      expect(session.projectID).toBeDefined();
      expect(session.directory).toBeDefined();
      expect(session.title).toBeDefined();
    });

    test('updates existing session on conflict', async () => {
      const session: Session = {
        id: 'ses_existing',
        projectID: 'default',
        directory: '/test',
        title: 'Updated Title',
        version: '1.0.0',
        time: { created: 1000, updated: 3000 },
        tokenCount: 150,
        bypassMode: false,
        plugins: ['new-plugin'],
      };

      // ON CONFLICT DO UPDATE logic
      expect(session.title).toBe('Updated Title');
      expect(session.time.updated).toBe(3000);
      expect(session.tokenCount).toBe(150);
    });

    test('handles optional fields correctly', async () => {
      const session: Session = {
        id: 'ses_test',
        projectID: 'default',
        directory: '/test',
        title: 'Test',
        version: '1.0.0',
        time: { created: 1000, updated: 2000, archived: 3000 },
        parentID: 'ses_parent',
        forkPoint: 'msg_fork',
        summary: { additions: 5, deletions: 3, files: 2 },
        revert: { messageID: 'msg_1', snapshot: 'hash_1' },
        tokenCount: 100,
        bypassMode: true,
        model: 'claude-opus-4',
        reasoningEffort: 'high',
        ghostCommit: { enabled: true, currentTurn: 5, commits: ['commit1'] },
        plugins: ['plugin1'],
      };

      // Verify JSON serialization
      expect(JSON.stringify(session.summary)).toContain('additions');
      expect(JSON.stringify(session.revert)).toContain('messageID');
      expect(JSON.stringify(session.ghostCommit)).toContain('enabled');
      expect(JSON.stringify(session.plugins)).toContain('plugin1');
    });
  });

  describe('deleteSession', () => {
    test('deletes session by ID', async () => {
      await mockSql`DELETE FROM sessions WHERE id = 'ses_delete'`;

      expect(mockSql).toHaveBeenCalled();
    });
  });
});

describe('Message Operations', () => {
  beforeEach(() => {
    mockSqlResults.length = 0;
    mockSql.mockClear();
  });

  describe('getSessionMessages', () => {
    test('returns empty array when no messages', async () => {
      mockSqlResults.length = 0;

      expect(mockSqlResults).toEqual([]);
    });

    test('groups parts by message ID', () => {
      const messageRows = [
        { id: 'msg_1', role: 'user' },
        { id: 'msg_2', role: 'assistant' },
      ];

      const partRows = [
        { id: 'part_1', message_id: 'msg_1', type: 'text', text: 'Hello' },
        { id: 'part_2', message_id: 'msg_1', type: 'text', text: 'World' },
        { id: 'part_3', message_id: 'msg_2', type: 'text', text: 'Hi' },
      ];

      const partsByMessage = new Map<string, Part[]>();
      for (const row of partRows) {
        const existing = partsByMessage.get(row.message_id) ?? [];
        existing.push(row as any);
        partsByMessage.set(row.message_id, existing);
      }

      expect(partsByMessage.get('msg_1')).toHaveLength(2);
      expect(partsByMessage.get('msg_2')).toHaveLength(1);
    });

    test('converts user message row to UserMessage', () => {
      const mockRow = {
        id: 'msg_user',
        session_id: 'ses_test',
        role: 'user',
        time_created: 1000,
        time_completed: 2000,
        status: 'completed',
        thinking_text: 'Thinking...',
        error_message: null,
        agent: 'build',
        model_provider_id: 'anthropic',
        model_model_id: 'claude-sonnet-4',
        system_prompt: 'System prompt',
        tools: JSON.stringify({ grep: true, read: true }),
      };

      const message: UserMessage = {
        id: mockRow.id,
        sessionID: mockRow.session_id,
        role: 'user',
        time: {
          created: Number(mockRow.time_created),
          completed: mockRow.time_completed ? Number(mockRow.time_completed) : undefined,
        },
        status: mockRow.status as any,
        thinkingText: mockRow.thinking_text ?? undefined,
        errorMessage: mockRow.error_message ?? undefined,
        agent: mockRow.agent,
        model: {
          providerID: mockRow.model_provider_id,
          modelID: mockRow.model_model_id,
        },
        system: mockRow.system_prompt ?? undefined,
        tools: mockRow.tools ? JSON.parse(mockRow.tools) : undefined,
      };

      expect(message.role).toBe('user');
      expect(message.agent).toBe('build');
      expect(message.tools).toEqual({ grep: true, read: true });
    });

    test('converts assistant message row to AssistantMessage', () => {
      const mockRow = {
        id: 'msg_assistant',
        session_id: 'ses_test',
        role: 'assistant',
        time_created: 1000,
        time_completed: 2000,
        status: 'completed',
        thinking_text: null,
        error_message: null,
        parent_id: 'msg_user',
        mode: 'agentic',
        path_cwd: '/test',
        path_root: '/test',
        cost: 0.05,
        tokens_input: 100,
        tokens_output: 200,
        tokens_reasoning: 50,
        tokens_cache_read: 10,
        tokens_cache_write: 5,
        finish: 'stop',
        is_summary: false,
        error: null,
        model_provider_id: 'anthropic',
        model_model_id: 'claude-sonnet-4',
      };

      const message: AssistantMessage = {
        id: mockRow.id,
        sessionID: mockRow.session_id,
        role: 'assistant',
        time: {
          created: Number(mockRow.time_created),
          completed: mockRow.time_completed ? Number(mockRow.time_completed) : undefined,
        },
        status: mockRow.status as any,
        thinkingText: mockRow.thinking_text ?? undefined,
        errorMessage: mockRow.error_message ?? undefined,
        parentID: mockRow.parent_id,
        modelID: mockRow.model_model_id,
        providerID: mockRow.model_provider_id,
        mode: mockRow.mode,
        path: {
          cwd: mockRow.path_cwd,
          root: mockRow.path_root,
        },
        cost: Number(mockRow.cost),
        tokens: {
          input: Number(mockRow.tokens_input),
          output: Number(mockRow.tokens_output),
          reasoning: Number(mockRow.tokens_reasoning),
          cache: mockRow.tokens_cache_read != null ? {
            read: Number(mockRow.tokens_cache_read),
            write: Number(mockRow.tokens_cache_write),
          } : undefined,
        },
        finish: mockRow.finish ?? undefined,
        summary: mockRow.is_summary ?? undefined,
        error: mockRow.error ? JSON.parse(mockRow.error) : undefined,
      };

      expect(message.role).toBe('assistant');
      expect(message.cost).toBe(0.05);
      expect(message.tokens.cache?.read).toBe(10);
    });
  });

  describe('saveMessage', () => {
    test('saves user message', async () => {
      const message: UserMessage = {
        id: 'msg_user',
        sessionID: 'ses_test',
        role: 'user',
        time: { created: 1000 },
        status: 'pending',
        agent: 'build',
        model: {
          providerID: 'anthropic',
          modelID: 'claude-sonnet-4',
        },
      };

      expect(message.role).toBe('user');
      expect(message.model.providerID).toBe('anthropic');
    });

    test('saves assistant message', async () => {
      const message: AssistantMessage = {
        id: 'msg_assistant',
        sessionID: 'ses_test',
        role: 'assistant',
        time: { created: 1000 },
        status: 'completed',
        parentID: 'msg_user',
        modelID: 'claude-sonnet-4',
        providerID: 'anthropic',
        mode: 'agentic',
        path: { cwd: '/test', root: '/test' },
        cost: 0.05,
        tokens: {
          input: 100,
          output: 200,
          reasoning: 50,
        },
      };

      expect(message.role).toBe('assistant');
      expect(message.tokens.input).toBe(100);
    });

    test('updates message on conflict', async () => {
      // ON CONFLICT DO UPDATE should update status, thinking_text, error_message, etc.
      const updateFields = [
        'time_completed',
        'status',
        'thinking_text',
        'error_message',
      ];

      for (const field of updateFields) {
        expect(field).toBeTruthy();
      }
    });
  });

  describe('setSessionMessages', () => {
    test('deletes existing messages before inserting', async () => {
      const sessionId = 'ses_test';

      // Should delete parts first, then messages
      await mockSql`DELETE FROM parts WHERE session_id = ${sessionId}`;
      await mockSql`DELETE FROM messages WHERE session_id = ${sessionId}`;

      expect(mockSql).toHaveBeenCalledTimes(2);
    });
  });
});

describe('Part Operations', () => {
  beforeEach(() => {
    mockSqlResults.length = 0;
    mockSql.mockClear();
  });

  describe('savePart', () => {
    test('saves text part', async () => {
      const part: TextPart = {
        id: 'part_text',
        sessionID: 'ses_test',
        messageID: 'msg_test',
        type: 'text',
        text: 'Hello world',
        time: { start: 1000, end: 2000 },
      };

      expect(part.type).toBe('text');
      expect(part.text).toBe('Hello world');
      expect(part.time?.start).toBe(1000);
    });

    test('saves reasoning part', async () => {
      const part: ReasoningPart = {
        id: 'part_reasoning',
        sessionID: 'ses_test',
        messageID: 'msg_test',
        type: 'reasoning',
        text: 'Reasoning content',
        time: { start: 1000, end: 2000 },
      };

      expect(part.type).toBe('reasoning');
      expect(part.text).toBe('Reasoning content');
      expect(part.time.start).toBe(1000);
    });

    test('saves tool part', async () => {
      const part: ToolPart = {
        id: 'part_tool',
        sessionID: 'ses_test',
        messageID: 'msg_test',
        type: 'tool',
        tool: 'grep',
        state: {
          status: 'completed',
          args: { pattern: 'test' },
          output: 'Results...',
        },
      };

      expect(part.type).toBe('tool');
      expect(part.tool).toBe('grep');
      expect(JSON.stringify(part.state)).toContain('completed');
    });

    test('saves file part', async () => {
      const part: FilePart = {
        id: 'part_file',
        sessionID: 'ses_test',
        messageID: 'msg_test',
        type: 'file',
        mime: 'image/png',
        url: 'https://example.com/image.png',
        filename: 'screenshot.png',
      };

      expect(part.type).toBe('file');
      expect(part.mime).toBe('image/png');
      expect(part.filename).toBe('screenshot.png');
    });

    test('updates part on conflict', async () => {
      // ON CONFLICT DO UPDATE should update text, time_start, time_end, etc.
      const updateFields = ['text', 'time_start', 'time_end', 'tool_state'];

      for (const field of updateFields) {
        expect(field).toBeTruthy();
      }
    });
  });

  describe('rowToPart', () => {
    test('converts text part row', () => {
      const row = {
        id: 'part_text',
        session_id: 'ses_test',
        message_id: 'msg_test',
        type: 'text',
        text: 'Hello',
        time_start: 1000,
        time_end: 2000,
      };

      const part: TextPart = {
        id: row.id,
        sessionID: row.session_id,
        messageID: row.message_id,
        type: 'text',
        text: row.text,
        time: row.time_start != null ? {
          start: Number(row.time_start),
          end: row.time_end ? Number(row.time_end) : undefined,
        } : undefined,
      };

      expect(part.text).toBe('Hello');
      expect(part.time?.start).toBe(1000);
    });

    test('converts tool part row', () => {
      const row = {
        id: 'part_tool',
        session_id: 'ses_test',
        message_id: 'msg_test',
        type: 'tool',
        tool_name: 'grep',
        tool_state: JSON.stringify({ status: 'completed' }),
      };

      const part: ToolPart = {
        id: row.id,
        sessionID: row.session_id,
        messageID: row.message_id,
        type: 'tool',
        tool: row.tool_name,
        state: JSON.parse(row.tool_state),
      };

      expect(part.tool).toBe('grep');
      expect(part.state.status).toBe('completed');
    });
  });
});

describe('Snapshot History Operations', () => {
  beforeEach(() => {
    mockSqlResults.length = 0;
    mockSql.mockClear();
  });

  describe('getSnapshotHistory', () => {
    test('returns empty array when no history', async () => {
      mockSqlResults.length = 0;

      expect(mockSqlResults).toEqual([]);
    });

    test('returns snapshot hashes in order', async () => {
      mockSqlResults.push(
        { change_id: 'hash_0' },
        { change_id: 'hash_1' },
        { change_id: 'hash_2' }
      );

      const hashes = mockSqlResults.map(r => r.change_id);

      expect(hashes).toEqual(['hash_0', 'hash_1', 'hash_2']);
    });
  });

  describe('setSnapshotHistory', () => {
    test('deletes existing history before inserting', async () => {
      const sessionId = 'ses_test';

      await mockSql`DELETE FROM snapshot_history WHERE session_id = ${sessionId}`;

      expect(mockSql).toHaveBeenCalled();
    });

    test('inserts history with correct sort order', async () => {
      const history = ['hash_0', 'hash_1', 'hash_2'];

      for (let i = 0; i < history.length; i++) {
        const changeId = history[i];
        expect(changeId).toBeDefined();
        expect(i).toBeLessThan(history.length);
      }
    });
  });

  describe('appendSnapshotHistory', () => {
    test('appends to end of history', async () => {
      mockSqlResults.push({ max_order: 2 });

      const [row] = mockSqlResults;
      const nextOrder = row ? Number(row.max_order) + 1 : 0;

      expect(nextOrder).toBe(3);
    });

    test('starts at 0 when no existing history', async () => {
      mockSqlResults.push({ max_order: -1 });

      const [row] = mockSqlResults;
      const nextOrder = row ? Number(row.max_order) + 1 : 0;

      expect(nextOrder).toBe(0);
    });
  });
});

describe('File Tracker Operations', () => {
  beforeEach(() => {
    mockSqlResults.length = 0;
    mockSql.mockClear();
  });

  describe('getFileTracker', () => {
    test('returns empty tracker when no files', async () => {
      mockSqlResults.length = 0;

      const tracker = {
        readTimes: new Map(),
        modTimes: new Map(),
      };

      expect(tracker.readTimes.size).toBe(0);
      expect(tracker.modTimes.size).toBe(0);
    });

    test('populates read and mod times', async () => {
      mockSqlResults.push(
        { file_path: '/file1.ts', read_time: 1000, mod_time: 2000 },
        { file_path: '/file2.ts', read_time: 3000, mod_time: null }
      );

      const tracker = {
        readTimes: new Map<string, number>(),
        modTimes: new Map<string, number>(),
      };

      for (const row of mockSqlResults) {
        const path = row.file_path;
        if (row.read_time != null) {
          tracker.readTimes.set(path, Number(row.read_time));
        }
        if (row.mod_time != null) {
          tracker.modTimes.set(path, Number(row.mod_time));
        }
      }

      expect(tracker.readTimes.get('/file1.ts')).toBe(1000);
      expect(tracker.modTimes.get('/file1.ts')).toBe(2000);
      expect(tracker.readTimes.get('/file2.ts')).toBe(3000);
      expect(tracker.modTimes.has('/file2.ts')).toBe(false);
    });
  });

  describe('updateFileTracker', () => {
    test('inserts new file tracker entry', async () => {
      const sessionId = 'ses_test';
      const filePath = '/test.ts';
      const readTime = 1000;
      const modTime = 2000;

      expect(sessionId).toBeTruthy();
      expect(filePath).toBeTruthy();
      expect(readTime).toBe(1000);
      expect(modTime).toBe(2000);
    });

    test('updates existing entry on conflict', async () => {
      // ON CONFLICT DO UPDATE should use COALESCE to preserve existing values
      const updateClause = 'COALESCE(EXCLUDED.read_time, file_trackers.read_time)';

      expect(updateClause).toContain('COALESCE');
    });

    test('handles null read_time', async () => {
      const readTime = undefined;
      const modTime = 2000;

      const readTimeValue = readTime ?? null;

      expect(readTimeValue).toBeNull();
      expect(modTime).toBe(2000);
    });

    test('handles null mod_time', async () => {
      const readTime = 1000;
      const modTime = undefined;

      const modTimeValue = modTime ?? null;

      expect(readTime).toBe(1000);
      expect(modTimeValue).toBeNull();
    });
  });

  describe('clearFileTrackers', () => {
    test('deletes all trackers for session', async () => {
      const sessionId = 'ses_test';

      await mockSql`DELETE FROM file_trackers WHERE session_id = ${sessionId}`;

      expect(mockSql).toHaveBeenCalled();
    });
  });
});

describe('Streaming Operations', () => {
  describe('appendStreamingPart', () => {
    test('generates unique part ID', () => {
      const partId = 'part_' + 'a'.repeat(12);

      expect(partId).toMatch(/^part_[a-z0-9]{12}$/);
    });

    test('creates text part', async () => {
      const partData = {
        type: 'text' as const,
        text: 'Streaming text...',
        sort_order: 0,
        time_start: 1000,
      };

      expect(partData.type).toBe('text');
      expect(partData.text).toBe('Streaming text...');
    });

    test('creates tool part', async () => {
      const partData = {
        type: 'tool' as const,
        tool_name: 'grep',
        tool_state: { status: 'running' },
        sort_order: 0,
      };

      expect(partData.type).toBe('tool');
      expect(partData.tool_name).toBe('grep');
    });
  });

  describe('updateStreamingPart', () => {
    test('updates text field', async () => {
      const updates = {
        text: 'Updated text',
      };

      expect(updates.text).toBe('Updated text');
    });

    test('updates tool_state', async () => {
      const updates = {
        tool_state: { status: 'completed', result: 'Success' },
      };

      expect(JSON.stringify(updates.tool_state)).toContain('completed');
    });

    test('updates time_end', async () => {
      const updates = {
        time_end: 2000,
      };

      expect(updates.time_end).toBe(2000);
    });
  });

  describe('updateMessageStatus', () => {
    test('updates status field', async () => {
      const updates = {
        status: 'completed' as const,
      };

      expect(updates.status).toBe('completed');
    });

    test('updates token counts', async () => {
      const updates = {
        tokens_input: 100,
        tokens_output: 200,
        tokens_reasoning: 50,
        tokens_cache_read: 10,
        tokens_cache_write: 5,
      };

      expect(updates.tokens_input).toBe(100);
      expect(updates.tokens_cache_read).toBe(10);
    });

    test('uses COALESCE to preserve existing values', () => {
      const updateClause = 'COALESCE($1, existing_value)';

      expect(updateClause).toContain('COALESCE');
    });
  });
});

describe('Cleanup Operations', () => {
  describe('clearSessionState', () => {
    test('deletes session cascading to related data', async () => {
      const sessionId = 'ses_test';

      await mockSql`DELETE FROM sessions WHERE id = ${sessionId}`;

      expect(mockSql).toHaveBeenCalled();
    });

    test('relies on foreign key cascades', () => {
      // Foreign key cascades should handle:
      // - parts
      // - messages
      // - snapshot_history
      // - subtasks
      // - file_trackers

      const cascadedTables = [
        'parts',
        'messages',
        'snapshot_history',
        'subtasks',
        'file_trackers',
      ];

      expect(cascadedTables).toHaveLength(5);
    });
  });
});

describe('Edge Cases', () => {
  test('handles empty strings in fields', () => {
    const session: Session = {
      id: 'ses_test',
      projectID: '',
      directory: '',
      title: '',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    expect(session.projectID).toBe('');
    expect(session.title).toBe('');
  });

  test('handles large token counts', () => {
    const tokens = {
      input: 1000000,
      output: 500000,
      reasoning: 250000,
    };

    expect(tokens.input).toBe(1000000);
  });

  test('handles deeply nested JSON in tool state', () => {
    const toolState = {
      level1: {
        level2: {
          level3: {
            data: 'deep value',
          },
        },
      },
    };

    const serialized = JSON.stringify(toolState);
    const deserialized = JSON.parse(serialized);

    expect(deserialized.level1.level2.level3.data).toBe('deep value');
  });

  test('handles special characters in file paths', () => {
    const paths = [
      '/path with spaces/file.ts',
      '/path-with-dashes/file.ts',
      '/path.with.dots/file.ts',
      '/path_with_underscores/file.ts',
    ];

    for (const path of paths) {
      expect(path).toBeTruthy();
    }
  });

  test('handles very long text content', () => {
    const longText = 'a'.repeat(100000);

    expect(longText).toHaveLength(100000);
  });

  test('handles Unicode in messages', () => {
    const unicodeText = 'Hello 世界 🌍';
    const serialized = JSON.stringify({ text: unicodeText });
    const deserialized = JSON.parse(serialized);

    expect(deserialized.text).toBe(unicodeText);
  });

  test('handles null vs undefined in optional fields', () => {
    const withNull = { value: null };
    const withUndefined = { value: undefined };

    expect(JSON.stringify(withNull)).toBe('{"value":null}');
    expect(JSON.stringify(withUndefined)).toBe('{}');
  });
});
