/**
 * Tests for core/sessions.ts
 *
 * Tests session CRUD operations, forking, reverting, and undo functionality.
 * Uses mocking to isolate from database and snapshot dependencies.
 */

import { describe, test, expect, beforeEach, mock } from 'bun:test';
import type { Session, CreateSessionOptions, UpdateSessionOptions } from '../models';
import { NullEventBus } from '../events';
import { NotFoundError, InvalidOperationError } from '../exceptions';

// Mock the state module
const mockSessions = new Map<string, Session>();
const mockMessages = new Map<string, any[]>();
const mockSnapshotHistory = new Map<string, string[]>();
const mockActiveTasks = new Map<string, AbortController>();

const mockState = {
  getSession: mock(async (id: string) => mockSessions.get(id) ?? null),
  getAllSessions: mock(async () => Array.from(mockSessions.values())),
  saveSession: mock(async (session: Session) => {
    mockSessions.set(session.id, session);
  }),
  getSessionMessages: mock(async (id: string) => mockMessages.get(id) ?? []),
  setSessionMessages: mock(async (id: string, messages: any[]) => {
    mockMessages.set(id, messages);
  }),
  getSnapshotHistory: mock(async (id: string) => mockSnapshotHistory.get(id) ?? []),
  setSnapshotHistory: mock(async (id: string, history: string[]) => {
    mockSnapshotHistory.set(id, history);
  }),
  activeTasks: mockActiveTasks,
  clearSessionState: mock(async (id: string) => {
    mockSessions.delete(id);
    mockMessages.delete(id);
    mockSnapshotHistory.delete(id);
  }),
};

// Mock the snapshots module
const mockSnapshots = {
  initSnapshot: mock(async () => 'snapshot_init'),
  computeDiff: mock(async () => []),
  getChangedFiles: mock(async () => []),
  restoreSnapshot: mock(async () => {}),
  getSnapshotHistory: mock(async (id: string) => mockSnapshotHistory.get(id) ?? []),
};

// Import with mocks
import * as sessions from '../sessions';

describe('createSession', () => {
  const eventBus = new NullEventBus();

  beforeEach(() => {
    mockSessions.clear();
    mockMessages.clear();
    mockSnapshotHistory.clear();
    mockActiveTasks.clear();
  });

  test('creates session with default values', async () => {
    const options: CreateSessionOptions = {
      directory: '/test/dir',
    };

    const session = await sessions.createSession(options, eventBus);

    expect(session.id).toMatch(/^ses_[a-z0-9]{12}$/);
    expect(session.directory).toBe('/test/dir');
    expect(session.title).toBe('New Session');
    expect(session.projectID).toBe('default');
    expect(session.version).toBe('1.0.0');
    expect(session.bypassMode).toBe(false);
    expect(session.model).toBe('claude-sonnet-4-20250514');
    expect(session.reasoningEffort).toBe('medium');
    expect(session.plugins).toEqual([]);
    expect(session.tokenCount).toBe(0);
    expect(session.time.created).toBeGreaterThan(0);
    expect(session.time.updated).toBeGreaterThan(0);
  });

  test('creates session with custom options', async () => {
    const options: CreateSessionOptions = {
      directory: '/custom/dir',
      title: 'Custom Session',
      parentID: 'ses_parent123',
      bypassMode: true,
      model: 'claude-opus-4',
      reasoningEffort: 'high',
      plugins: ['plugin1', 'plugin2'],
    };

    const session = await sessions.createSession(options, eventBus);

    expect(session.title).toBe('Custom Session');
    expect(session.parentID).toBe('ses_parent123');
    expect(session.bypassMode).toBe(true);
    expect(session.model).toBe('claude-opus-4');
    expect(session.reasoningEffort).toBe('high');
    expect(session.plugins).toEqual(['plugin1', 'plugin2']);
  });

  test('saves session to state', async () => {
    const options: CreateSessionOptions = {
      directory: '/test/dir',
    };

    const session = await sessions.createSession(options, eventBus);

    expect(mockSessions.has(session.id)).toBe(true);
    expect(mockSessions.get(session.id)).toEqual(session);
  });
});

describe('getSession', () => {
  beforeEach(() => {
    mockSessions.clear();
  });

  test('retrieves existing session', async () => {
    const session: Session = {
      id: 'ses_test123',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 100,
      bypassMode: false,
      plugins: [],
    };

    mockSessions.set(session.id, session);

    const result = await sessions.getSession('ses_test123');
    expect(result).toEqual(session);
  });

  test('throws NotFoundError for non-existent session', async () => {
    await expect(sessions.getSession('ses_nonexistent')).rejects.toThrow(NotFoundError);
  });
});

describe('listSessions', () => {
  beforeEach(() => {
    mockSessions.clear();
  });

  test('returns all sessions', async () => {
    const session1: Session = {
      id: 'ses_1',
      projectID: 'default',
      directory: '/test1',
      title: 'Session 1',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    const session2: Session = {
      id: 'ses_2',
      projectID: 'default',
      directory: '/test2',
      title: 'Session 2',
      version: '1.0.0',
      time: { created: 3000, updated: 4000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    mockSessions.set(session1.id, session1);
    mockSessions.set(session2.id, session2);

    const result = await sessions.listSessions();
    expect(result).toHaveLength(2);
    expect(result).toContainEqual(session1);
    expect(result).toContainEqual(session2);
  });

  test('returns empty array when no sessions', async () => {
    const result = await sessions.listSessions();
    expect(result).toEqual([]);
  });
});

describe('updateSession', () => {
  const eventBus = new NullEventBus();

  beforeEach(() => {
    mockSessions.clear();
  });

  test('updates session title', async () => {
    const session: Session = {
      id: 'ses_test123',
      projectID: 'default',
      directory: '/test',
      title: 'Old Title',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    mockSessions.set(session.id, session);

    const options: UpdateSessionOptions = {
      title: 'New Title',
    };

    const updated = await sessions.updateSession('ses_test123', options, eventBus);

    expect(updated.title).toBe('New Title');
    expect(updated.time.updated).toBeGreaterThan(2000);
  });

  test('archives session', async () => {
    const session: Session = {
      id: 'ses_test123',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    mockSessions.set(session.id, session);

    const options: UpdateSessionOptions = {
      archived: true,
    };

    const updated = await sessions.updateSession('ses_test123', options, eventBus);

    expect(updated.time.archived).toBeGreaterThan(0);
  });

  test('unarchives session', async () => {
    const session: Session = {
      id: 'ses_test123',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000, archived: 3000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    mockSessions.set(session.id, session);

    const options: UpdateSessionOptions = {
      archived: false,
    };

    const updated = await sessions.updateSession('ses_test123', options, eventBus);

    expect(updated.time.archived).toBeUndefined();
  });

  test('updates model and reasoningEffort', async () => {
    const session: Session = {
      id: 'ses_test123',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    mockSessions.set(session.id, session);

    const options: UpdateSessionOptions = {
      model: 'claude-opus-4',
      reasoningEffort: 'high',
    };

    const updated = await sessions.updateSession('ses_test123', options, eventBus);

    expect(updated.model).toBe('claude-opus-4');
    expect(updated.reasoningEffort).toBe('high');
  });

  test('throws NotFoundError for non-existent session', async () => {
    const options: UpdateSessionOptions = {
      title: 'New Title',
    };

    await expect(
      sessions.updateSession('ses_nonexistent', options, eventBus)
    ).rejects.toThrow(NotFoundError);
  });
});

describe('deleteSession', () => {
  const eventBus = new NullEventBus();

  beforeEach(() => {
    mockSessions.clear();
    mockActiveTasks.clear();
  });

  test('deletes session and clears state', async () => {
    const session: Session = {
      id: 'ses_test123',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    mockSessions.set(session.id, session);
    mockMessages.set(session.id, [{ info: { id: 'msg_1' } }]);
    mockSnapshotHistory.set(session.id, ['hash1', 'hash2']);

    const result = await sessions.deleteSession('ses_test123', eventBus);

    expect(result).toBe(true);
    expect(mockSessions.has('ses_test123')).toBe(false);
    expect(mockMessages.has('ses_test123')).toBe(false);
    expect(mockSnapshotHistory.has('ses_test123')).toBe(false);
  });

  test('cancels active task before deletion', async () => {
    const session: Session = {
      id: 'ses_test123',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    const controller = new AbortController();
    const abortSpy = mock(() => {});
    controller.abort = abortSpy;

    mockSessions.set(session.id, session);
    mockActiveTasks.set(session.id, controller);

    await sessions.deleteSession('ses_test123', eventBus);

    expect(abortSpy).toHaveBeenCalled();
    expect(mockActiveTasks.has('ses_test123')).toBe(false);
  });

  test('throws NotFoundError for non-existent session', async () => {
    await expect(
      sessions.deleteSession('ses_nonexistent', eventBus)
    ).rejects.toThrow(NotFoundError);
  });
});

describe('abortSession', () => {
  beforeEach(() => {
    mockSessions.clear();
    mockActiveTasks.clear();
  });

  test('aborts active task', async () => {
    const session: Session = {
      id: 'ses_test123',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    const controller = new AbortController();
    const abortSpy = mock(() => {});
    controller.abort = abortSpy;

    mockSessions.set(session.id, session);
    mockActiveTasks.set(session.id, controller);

    const result = await sessions.abortSession('ses_test123');

    expect(result).toBe(true);
    expect(abortSpy).toHaveBeenCalled();
    expect(mockActiveTasks.has('ses_test123')).toBe(false);
  });

  test('returns false when no active task', async () => {
    const session: Session = {
      id: 'ses_test123',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    mockSessions.set(session.id, session);

    const result = await sessions.abortSession('ses_test123');

    expect(result).toBe(false);
  });

  test('throws NotFoundError for non-existent session', async () => {
    await expect(sessions.abortSession('ses_nonexistent')).rejects.toThrow(
      NotFoundError
    );
  });
});

describe('forkSession', () => {
  const eventBus = new NullEventBus();

  beforeEach(() => {
    mockSessions.clear();
    mockMessages.clear();
  });

  test('creates fork with parent reference', async () => {
    const parent: Session = {
      id: 'ses_parent',
      projectID: 'default',
      directory: '/test',
      title: 'Parent Session',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 100,
      bypassMode: false,
      plugins: ['plugin1'],
    };

    mockSessions.set(parent.id, parent);
    mockMessages.set(parent.id, [
      { info: { id: 'msg_1', role: 'user' } },
      { info: { id: 'msg_2', role: 'assistant' } },
    ]);

    const forked = await sessions.forkSession('ses_parent', eventBus);

    expect(forked.id).not.toBe('ses_parent');
    expect(forked.parentID).toBe('ses_parent');
    expect(forked.directory).toBe('/test');
    expect(forked.title).toBe('Parent Session (fork)');
    expect(forked.plugins).toEqual(['plugin1']);
    expect(forked.bypassMode).toBe(false);
  });

  test('forks with custom title', async () => {
    const parent: Session = {
      id: 'ses_parent',
      projectID: 'default',
      directory: '/test',
      title: 'Parent Session',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    mockSessions.set(parent.id, parent);
    mockMessages.set(parent.id, []);

    const forked = await sessions.forkSession(
      'ses_parent',
      eventBus,
      undefined,
      'Custom Fork'
    );

    expect(forked.title).toBe('Custom Fork');
  });

  test('copies messages up to fork point', async () => {
    const parent: Session = {
      id: 'ses_parent',
      projectID: 'default',
      directory: '/test',
      title: 'Parent Session',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    const messages = [
      { info: { id: 'msg_1', role: 'user' } },
      { info: { id: 'msg_2', role: 'assistant' } },
      { info: { id: 'msg_3', role: 'user' } },
      { info: { id: 'msg_4', role: 'assistant' } },
    ];

    mockSessions.set(parent.id, parent);
    mockMessages.set(parent.id, messages);

    const forked = await sessions.forkSession('ses_parent', eventBus, 'msg_2');

    expect(forked.forkPoint).toBe('msg_2');

    const forkedMessages = mockMessages.get(forked.id) ?? [];
    expect(forkedMessages).toHaveLength(2);
    expect(forkedMessages[0]?.info.id).toBe('msg_1');
    expect(forkedMessages[1]?.info.id).toBe('msg_2');
  });

  test('copies all messages when no fork point specified', async () => {
    const parent: Session = {
      id: 'ses_parent',
      projectID: 'default',
      directory: '/test',
      title: 'Parent Session',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    const messages = [
      { info: { id: 'msg_1', role: 'user' } },
      { info: { id: 'msg_2', role: 'assistant' } },
    ];

    mockSessions.set(parent.id, parent);
    mockMessages.set(parent.id, messages);

    const forked = await sessions.forkSession('ses_parent', eventBus);

    const forkedMessages = mockMessages.get(forked.id) ?? [];
    expect(forkedMessages).toHaveLength(2);
  });
});

describe('revertSession', () => {
  const eventBus = new NullEventBus();

  beforeEach(() => {
    mockSessions.clear();
    mockMessages.clear();
    mockSnapshotHistory.clear();
  });

  test('reverts to specified message snapshot', async () => {
    const session: Session = {
      id: 'ses_test',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    const messages = [
      { info: { id: 'msg_1', role: 'user' } },
      { info: { id: 'msg_2', role: 'assistant' } },
      { info: { id: 'msg_3', role: 'user' } },
    ];

    const history = ['hash_0', 'hash_1', 'hash_2', 'hash_3'];

    mockSessions.set(session.id, session);
    mockMessages.set(session.id, messages);
    mockSnapshotHistory.set(session.id, history);

    const reverted = await sessions.revertSession(
      'ses_test',
      'msg_2',
      eventBus
    );

    expect(reverted.revert).toBeDefined();
    expect(reverted.revert?.messageID).toBe('msg_2');
    expect(reverted.revert?.snapshot).toBe('hash_1');
  });

  test('includes part ID in revert info', async () => {
    const session: Session = {
      id: 'ses_test',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    const messages = [{ info: { id: 'msg_1', role: 'user' } }];
    const history = ['hash_0', 'hash_1'];

    mockSessions.set(session.id, session);
    mockMessages.set(session.id, messages);
    mockSnapshotHistory.set(session.id, history);

    const reverted = await sessions.revertSession(
      'ses_test',
      'msg_1',
      eventBus,
      'part_123'
    );

    expect(reverted.revert?.partID).toBe('part_123');
  });
});

describe('unrevertSession', () => {
  const eventBus = new NullEventBus();

  beforeEach(() => {
    mockSessions.clear();
  });

  test('clears revert info', async () => {
    const session: Session = {
      id: 'ses_test',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
      revert: {
        messageID: 'msg_1',
        snapshot: 'hash_1',
      },
    };

    mockSessions.set(session.id, session);

    const unreverted = await sessions.unrevertSession('ses_test', eventBus);

    expect(unreverted.revert).toBeUndefined();
  });
});

describe('undoTurns', () => {
  const eventBus = new NullEventBus();

  beforeEach(() => {
    mockSessions.clear();
    mockMessages.clear();
    mockSnapshotHistory.clear();
  });

  test('undoes single turn', async () => {
    const session: Session = {
      id: 'ses_test',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    // Two turns: user->assistant, user->assistant
    const messages = [
      { info: { id: 'msg_1', role: 'user' } },
      { info: { id: 'msg_2', role: 'assistant' } },
      { info: { id: 'msg_3', role: 'user' } },
      { info: { id: 'msg_4', role: 'assistant' } },
    ];

    const history = ['hash_0', 'hash_1', 'hash_2', 'hash_3', 'hash_4'];

    mockSessions.set(session.id, session);
    mockMessages.set(session.id, messages);
    mockSnapshotHistory.set(session.id, history);

    const [turnsUndone, messagesRemoved, filesReverted, snapshotHash] =
      await sessions.undoTurns('ses_test', eventBus, 1);

    expect(turnsUndone).toBe(1);
    expect(messagesRemoved).toBe(2); // msg_3 and msg_4
    expect(snapshotHash).toBe('hash_2');

    const remainingMessages = mockMessages.get('ses_test') ?? [];
    expect(remainingMessages).toHaveLength(2);
    expect(remainingMessages[0]?.info.id).toBe('msg_1');
    expect(remainingMessages[1]?.info.id).toBe('msg_2');
  });

  test('undoes multiple turns', async () => {
    const session: Session = {
      id: 'ses_test',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    // Three turns
    const messages = [
      { info: { id: 'msg_1', role: 'user' } },
      { info: { id: 'msg_2', role: 'assistant' } },
      { info: { id: 'msg_3', role: 'user' } },
      { info: { id: 'msg_4', role: 'assistant' } },
      { info: { id: 'msg_5', role: 'user' } },
      { info: { id: 'msg_6', role: 'assistant' } },
    ];

    const history = ['hash_0', 'hash_1', 'hash_2', 'hash_3', 'hash_4', 'hash_5', 'hash_6'];

    mockSessions.set(session.id, session);
    mockMessages.set(session.id, messages);
    mockSnapshotHistory.set(session.id, history);

    const [turnsUndone, messagesRemoved] = await sessions.undoTurns(
      'ses_test',
      eventBus,
      2
    );

    expect(turnsUndone).toBe(2);
    expect(messagesRemoved).toBe(4); // msg_3, msg_4, msg_5, msg_6

    const remainingMessages = mockMessages.get('ses_test') ?? [];
    expect(remainingMessages).toHaveLength(2);
  });

  test('returns zeros when no messages', async () => {
    const session: Session = {
      id: 'ses_test',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    mockSessions.set(session.id, session);
    mockMessages.set(session.id, []);
    mockSnapshotHistory.set(session.id, []);

    const [turnsUndone, messagesRemoved, filesReverted, snapshotHash] =
      await sessions.undoTurns('ses_test', eventBus, 1);

    expect(turnsUndone).toBe(0);
    expect(messagesRemoved).toBe(0);
    expect(filesReverted).toEqual([]);
    expect(snapshotHash).toBeNull();
  });

  test('returns zeros when only one turn exists', async () => {
    const session: Session = {
      id: 'ses_test',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    const messages = [
      { info: { id: 'msg_1', role: 'user' } },
      { info: { id: 'msg_2', role: 'assistant' } },
    ];

    mockSessions.set(session.id, session);
    mockMessages.set(session.id, messages);
    mockSnapshotHistory.set(session.id, ['hash_0', 'hash_1']);

    const [turnsUndone] = await sessions.undoTurns('ses_test', eventBus, 1);

    expect(turnsUndone).toBe(0);
  });

  test('caps undo count at available turns', async () => {
    const session: Session = {
      id: 'ses_test',
      projectID: 'default',
      directory: '/test',
      title: 'Test',
      version: '1.0.0',
      time: { created: 1000, updated: 2000 },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    // Two turns
    const messages = [
      { info: { id: 'msg_1', role: 'user' } },
      { info: { id: 'msg_2', role: 'assistant' } },
      { info: { id: 'msg_3', role: 'user' } },
      { info: { id: 'msg_4', role: 'assistant' } },
    ];

    mockSessions.set(session.id, session);
    mockMessages.set(session.id, messages);
    mockSnapshotHistory.set(session.id, ['hash_0', 'hash_1', 'hash_2']);

    // Request to undo 5 turns but only 1 can be undone
    const [turnsUndone] = await sessions.undoTurns('ses_test', eventBus, 5);

    expect(turnsUndone).toBe(1);
  });
});
