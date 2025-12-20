/**
 * Tests for JJ Sync Service.
 */

import { describe, test, expect, beforeEach, mock, spyOn } from 'bun:test';
import { jjSyncService } from '../jj-sync';

// Mock the database client
const mockSql = mock(async () => []);
mockSql.array = mock((arr: any[], type: string) => arr);

// Mock the jj library functions
const mockListChanges = mock(async () => []);
const mockListBookmarks = mock(async () => []);
const mockGetOperationLog = mock(async () => []);
const mockGetConflicts = mock(async () => []);

// Mock the modules
mock.module('../../ui/lib/db', () => ({
  sql: mockSql,
}));

mock.module('../../ui/lib/jj', () => ({
  listChanges: mockListChanges,
  listBookmarks: mockListBookmarks,
  getOperationLog: mockGetOperationLog,
  getConflicts: mockGetConflicts,
}));

describe('JjSyncService.syncToDatabase', () => {
  beforeEach(() => {
    mockSql.mockClear();
    mockListChanges.mockClear();
    mockListBookmarks.mockClear();
    mockGetOperationLog.mockClear();
    mockGetConflicts.mockClear();
  });

  test('throws error when repository not found', async () => {
    mockSql.mockResolvedValueOnce([]);

    await expect(
      jjSyncService.syncToDatabase('testuser', 'testrepo')
    ).rejects.toThrow('Repository testuser/testrepo not found');
  });

  test('queries repository by user and name', async () => {
    mockSql.mockResolvedValueOnce([{ id: 1 }]);
    mockListChanges.mockResolvedValue([]);
    mockListBookmarks.mockResolvedValue([]);
    mockGetOperationLog.mockResolvedValue([]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncToDatabase('alice', 'myrepo');

    expect(mockSql).toHaveBeenCalled();
    const firstCall = mockSql.mock.calls[0];
    expect(firstCall).toBeDefined();
  });

  test('syncs all data types in parallel', async () => {
    mockSql.mockResolvedValueOnce([{ id: 1 }]);
    mockListChanges.mockResolvedValue([]);
    mockListBookmarks.mockResolvedValue([]);
    mockGetOperationLog.mockResolvedValue([]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncToDatabase('user', 'repo');

    expect(mockListChanges).toHaveBeenCalledWith('user', 'repo', 1000);
    expect(mockListBookmarks).toHaveBeenCalledWith('user', 'repo');
    expect(mockGetOperationLog).toHaveBeenCalledWith('user', 'repo', 100);
  });
});

describe('JjSyncService.syncChanges', () => {
  beforeEach(() => {
    mockSql.mockClear();
    mockListChanges.mockClear();
  });

  test('syncs empty changes list', async () => {
    mockListChanges.mockResolvedValue([]);

    await jjSyncService.syncChanges('user', 'repo', 1);

    expect(mockListChanges).toHaveBeenCalledWith('user', 'repo', 1000);
    expect(mockSql).not.toHaveBeenCalled();
  });

  test('inserts change with all fields', async () => {
    const mockChange = {
      changeId: 'change-123',
      commitId: 'commit-abc',
      parentChangeIds: ['parent-1', 'parent-2'],
      description: 'Test change',
      author: {
        name: 'Alice',
        email: 'alice@example.com',
      },
      timestamp: new Date('2025-01-01T00:00:00Z'),
      isEmpty: false,
      hasConflicts: false,
    };

    mockListChanges.mockResolvedValue([mockChange]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncChanges('user', 'repo', 1);

    expect(mockSql).toHaveBeenCalledTimes(1);
  });

  test('handles changes with empty parent list', async () => {
    const mockChange = {
      changeId: 'change-456',
      commitId: 'commit-def',
      parentChangeIds: [],
      description: 'Root change',
      author: {
        name: 'Bob',
        email: 'bob@example.com',
      },
      timestamp: new Date(),
      isEmpty: true,
      hasConflicts: false,
    };

    mockListChanges.mockResolvedValue([mockChange]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncChanges('user', 'repo', 2);

    expect(mockSql).toHaveBeenCalled();
  });

  test('syncs multiple changes', async () => {
    const mockChanges = [
      {
        changeId: 'change-1',
        commitId: 'commit-1',
        parentChangeIds: [],
        description: 'First',
        author: { name: 'Alice', email: 'alice@example.com' },
        timestamp: new Date(),
        isEmpty: false,
        hasConflicts: false,
      },
      {
        changeId: 'change-2',
        commitId: 'commit-2',
        parentChangeIds: ['change-1'],
        description: 'Second',
        author: { name: 'Bob', email: 'bob@example.com' },
        timestamp: new Date(),
        isEmpty: false,
        hasConflicts: true,
      },
    ];

    mockListChanges.mockResolvedValue(mockChanges);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncChanges('user', 'repo', 3);

    expect(mockSql).toHaveBeenCalledTimes(2);
  });

  test('handles changes with conflicts', async () => {
    const mockChange = {
      changeId: 'conflict-change',
      commitId: 'conflict-commit',
      parentChangeIds: ['parent-1', 'parent-2'],
      description: 'Conflicting change',
      author: { name: 'Charlie', email: 'charlie@example.com' },
      timestamp: new Date(),
      isEmpty: false,
      hasConflicts: true,
    };

    mockListChanges.mockResolvedValue([mockChange]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncChanges('user', 'repo', 4);

    expect(mockSql).toHaveBeenCalled();
  });
});

describe('JjSyncService.syncBookmarks', () => {
  beforeEach(() => {
    mockSql.mockClear();
    mockListBookmarks.mockClear();
  });

  test('syncs empty bookmarks list', async () => {
    mockListBookmarks.mockResolvedValue([]);
    mockSql.mockResolvedValueOnce([]);

    await jjSyncService.syncBookmarks('user', 'repo', 1);

    expect(mockListBookmarks).toHaveBeenCalledWith('user', 'repo');
  });

  test('inserts new bookmark', async () => {
    const mockBookmark = {
      name: 'main',
      targetChangeId: 'change-123',
      isDefault: true,
    };

    mockListBookmarks.mockResolvedValue([mockBookmark]);
    mockSql.mockResolvedValueOnce([]);
    mockSql.mockResolvedValueOnce([]);

    await jjSyncService.syncBookmarks('user', 'repo', 1);

    expect(mockSql).toHaveBeenCalledTimes(2);
  });

  test('updates existing bookmark', async () => {
    const mockBookmark = {
      name: 'feature',
      targetChangeId: 'new-change-456',
      isDefault: false,
    };

    mockListBookmarks.mockResolvedValue([mockBookmark]);
    mockSql.mockResolvedValueOnce([{ name: 'feature' }]);
    mockSql.mockResolvedValueOnce([]);

    await jjSyncService.syncBookmarks('user', 'repo', 2);

    expect(mockSql).toHaveBeenCalled();
  });

  test('deletes removed bookmarks', async () => {
    const currentBookmarks = [
      { name: 'main', targetChangeId: 'change-1', isDefault: true },
    ];

    mockListBookmarks.mockResolvedValue(currentBookmarks);
    mockSql.mockResolvedValueOnce([
      { name: 'main' },
      { name: 'old-branch' },
      { name: 'deleted-feature' },
    ]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncBookmarks('user', 'repo', 3);

    // Should call SQL for: get existing, upsert main, delete old-branch, delete deleted-feature
    expect(mockSql.mock.calls.length).toBeGreaterThanOrEqual(3);
  });

  test('syncs multiple bookmarks', async () => {
    const mockBookmarks = [
      { name: 'main', targetChangeId: 'change-1', isDefault: true },
      { name: 'dev', targetChangeId: 'change-2', isDefault: false },
      { name: 'staging', targetChangeId: 'change-3', isDefault: false },
    ];

    mockListBookmarks.mockResolvedValue(mockBookmarks);
    mockSql.mockResolvedValueOnce([]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncBookmarks('user', 'repo', 4);

    // One call to get existing bookmarks + 3 upserts
    expect(mockSql.mock.calls.length).toBeGreaterThanOrEqual(4);
  });

  test('handles bookmark without default flag', async () => {
    const mockBookmark = {
      name: 'test',
      targetChangeId: 'change-789',
      isDefault: false,
    };

    mockListBookmarks.mockResolvedValue([mockBookmark]);
    mockSql.mockResolvedValueOnce([]);
    mockSql.mockResolvedValueOnce([]);

    await jjSyncService.syncBookmarks('user', 'repo', 5);

    expect(mockSql).toHaveBeenCalled();
  });
});

describe('JjSyncService.syncOperations', () => {
  beforeEach(() => {
    mockSql.mockClear();
    mockGetOperationLog.mockClear();
  });

  test('syncs empty operations list', async () => {
    mockGetOperationLog.mockResolvedValue([]);

    await jjSyncService.syncOperations('user', 'repo', 1);

    expect(mockGetOperationLog).toHaveBeenCalledWith('user', 'repo', 100);
    expect(mockSql).not.toHaveBeenCalled();
  });

  test('inserts operation with all fields', async () => {
    const mockOp = {
      operationId: 'op-123',
      type: 'snapshot',
      description: 'Test snapshot',
      timestamp: new Date('2025-01-01T00:00:00Z'),
      isUndone: false,
    };

    mockGetOperationLog.mockResolvedValue([mockOp]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncOperations('user', 'repo', 1);

    expect(mockSql).toHaveBeenCalledTimes(1);
  });

  test('syncs multiple operations', async () => {
    const mockOps = [
      {
        operationId: 'op-1',
        type: 'commit',
        description: 'First commit',
        timestamp: new Date(),
        isUndone: false,
      },
      {
        operationId: 'op-2',
        type: 'rebase',
        description: 'Rebase operation',
        timestamp: new Date(),
        isUndone: false,
      },
      {
        operationId: 'op-3',
        type: 'undo',
        description: 'Undo previous',
        timestamp: new Date(),
        isUndone: true,
      },
    ];

    mockGetOperationLog.mockResolvedValue(mockOps);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncOperations('user', 'repo', 2);

    expect(mockSql).toHaveBeenCalledTimes(3);
  });

  test('handles undone operations', async () => {
    const mockOp = {
      operationId: 'op-undone',
      type: 'edit',
      description: 'Undone edit',
      timestamp: new Date(),
      isUndone: true,
    };

    mockGetOperationLog.mockResolvedValue([mockOp]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncOperations('user', 'repo', 3);

    expect(mockSql).toHaveBeenCalled();
  });

  test('requests limited number of operations', async () => {
    mockGetOperationLog.mockResolvedValue([]);

    await jjSyncService.syncOperations('user', 'repo', 4);

    expect(mockGetOperationLog).toHaveBeenCalledWith('user', 'repo', 100);
  });
});

describe('JjSyncService.syncConflicts', () => {
  beforeEach(() => {
    mockSql.mockClear();
    mockGetConflicts.mockClear();
  });

  test('marks resolved conflicts when no changes have conflicts', async () => {
    mockSql.mockResolvedValueOnce([]);
    mockSql.mockResolvedValueOnce([]);

    await jjSyncService.syncConflicts('user', 'repo', 1);

    expect(mockSql).toHaveBeenCalledTimes(2);
  });

  test('syncs conflicts for changes that have them', async () => {
    const mockConflict = {
      filePath: 'src/main.ts',
      conflictType: 'merge',
      resolved: false,
    };

    mockSql.mockResolvedValueOnce([{ change_id: 'change-123' }]);
    mockSql.mockResolvedValueOnce([]);
    mockGetConflicts.mockResolvedValue([mockConflict]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncConflicts('user', 'repo', 1);

    expect(mockGetConflicts).toHaveBeenCalledWith('user', 'repo', 'change-123');
    expect(mockSql.mock.calls.length).toBeGreaterThanOrEqual(3);
  });

  test('syncs multiple conflicts for single change', async () => {
    const mockConflicts = [
      { filePath: 'file1.ts', conflictType: 'merge', resolved: false },
      { filePath: 'file2.ts', conflictType: 'merge', resolved: false },
      { filePath: 'file3.ts', conflictType: 'edit', resolved: false },
    ];

    mockSql.mockResolvedValueOnce([{ change_id: 'change-456' }]);
    mockSql.mockResolvedValueOnce([]);
    mockGetConflicts.mockResolvedValue(mockConflicts);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncConflicts('user', 'repo', 2);

    expect(mockSql.mock.calls.length).toBeGreaterThanOrEqual(5);
  });

  test('syncs conflicts for multiple changes', async () => {
    mockSql.mockResolvedValueOnce([
      { change_id: 'change-1' },
      { change_id: 'change-2' },
    ]);
    mockSql.mockResolvedValueOnce([]);
    mockGetConflicts.mockResolvedValueOnce([
      { filePath: 'file1.ts', conflictType: 'merge', resolved: false },
    ]);
    mockGetConflicts.mockResolvedValueOnce([
      { filePath: 'file2.ts', conflictType: 'edit', resolved: false },
    ]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncConflicts('user', 'repo', 3);

    expect(mockGetConflicts).toHaveBeenCalledTimes(2);
    expect(mockGetConflicts).toHaveBeenCalledWith('user', 'repo', 'change-1');
    expect(mockGetConflicts).toHaveBeenCalledWith('user', 'repo', 'change-2');
  });

  test('handles resolved conflicts', async () => {
    const mockConflict = {
      filePath: 'resolved.ts',
      conflictType: 'merge',
      resolved: true,
    };

    mockSql.mockResolvedValueOnce([{ change_id: 'change-789' }]);
    mockSql.mockResolvedValueOnce([]);
    mockGetConflicts.mockResolvedValue([mockConflict]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncConflicts('user', 'repo', 4);

    expect(mockSql).toHaveBeenCalled();
  });

  test('handles empty conflict list', async () => {
    mockSql.mockResolvedValueOnce([{ change_id: 'change-empty' }]);
    mockSql.mockResolvedValueOnce([]);
    mockGetConflicts.mockResolvedValue([]);

    await jjSyncService.syncConflicts('user', 'repo', 5);

    expect(mockGetConflicts).toHaveBeenCalledWith('user', 'repo', 'change-empty');
  });
});

describe('JjSyncService integration', () => {
  beforeEach(() => {
    mockSql.mockClear();
    mockListChanges.mockClear();
    mockListBookmarks.mockClear();
    mockGetOperationLog.mockClear();
    mockGetConflicts.mockClear();
  });

  test('full sync completes successfully', async () => {
    mockSql.mockResolvedValueOnce([{ id: 1 }]);
    mockListChanges.mockResolvedValue([
      {
        changeId: 'change-1',
        commitId: 'commit-1',
        parentChangeIds: [],
        description: 'Initial',
        author: { name: 'Test', email: 'test@example.com' },
        timestamp: new Date(),
        isEmpty: false,
        hasConflicts: false,
      },
    ]);
    mockListBookmarks.mockResolvedValue([
      { name: 'main', targetChangeId: 'change-1', isDefault: true },
    ]);
    mockGetOperationLog.mockResolvedValue([
      {
        operationId: 'op-1',
        type: 'snapshot',
        description: 'Snapshot',
        timestamp: new Date(),
        isUndone: false,
      },
    ]);
    mockSql.mockResolvedValue([]);

    await jjSyncService.syncToDatabase('user', 'repo');

    expect(mockListChanges).toHaveBeenCalled();
    expect(mockListBookmarks).toHaveBeenCalled();
    expect(mockGetOperationLog).toHaveBeenCalled();
  });
});
