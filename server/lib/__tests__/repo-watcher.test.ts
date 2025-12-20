/**
 * Tests for Repository Watcher Service.
 */

import { describe, test, expect, beforeEach, mock, spyOn } from 'bun:test';
import { repoWatcherService } from '../repo-watcher';
import * as fs from 'node:fs';

// Mock the database client
const mockSql = mock(async () => []);

// Mock jjSyncService
const mockJjSyncService = {
  syncToDatabase: mock(async () => {}),
};

// Mock fs.watch
const mockWatcher = {
  close: mock(() => {}),
};
const mockWatch = mock(() => mockWatcher);

// Mock the modules
mock.module('../../ui/lib/db', () => ({
  sql: mockSql,
}));

mock.module('../jj-sync', () => ({
  jjSyncService: mockJjSyncService,
}));

mock.module('node:fs', () => ({
  watch: mockWatch,
}));

describe('RepoWatcherService.watchRepo', () => {
  beforeEach(() => {
    mockWatch.mockClear();
    mockJjSyncService.syncToDatabase.mockClear();
    // Clear all watchers
    const service = repoWatcherService as any;
    service.watchers.clear();
    service.debounceTimers.clear();
  });

  test('creates a watcher for a repository', () => {
    mockWatch.mockReturnValue(mockWatcher);

    repoWatcherService.watchRepo('testuser', 'testrepo');

    expect(mockWatch).toHaveBeenCalledTimes(1);
    const watchCall = mockWatch.mock.calls[0];
    expect(watchCall[0]).toContain('repos/testuser/testrepo');
    expect(watchCall[1]).toEqual({ recursive: true });
  });

  test('does not create duplicate watchers', () => {
    mockWatch.mockReturnValue(mockWatcher);

    repoWatcherService.watchRepo('alice', 'project');
    repoWatcherService.watchRepo('alice', 'project');
    repoWatcherService.watchRepo('alice', 'project');

    expect(mockWatch).toHaveBeenCalledTimes(1);
  });

  test('watches different repositories independently', () => {
    mockWatch.mockReturnValue(mockWatcher);

    repoWatcherService.watchRepo('user1', 'repo1');
    repoWatcherService.watchRepo('user2', 'repo2');
    repoWatcherService.watchRepo('user1', 'repo3');

    expect(mockWatch).toHaveBeenCalledTimes(3);
  });

  test('handles watch errors gracefully', () => {
    mockWatch.mockImplementation(() => {
      throw new Error('Watch failed');
    });

    // Should not throw
    expect(() => {
      repoWatcherService.watchRepo('user', 'repo');
    }).not.toThrow();
  });

  test('uses correct repository path', () => {
    mockWatch.mockReturnValue(mockWatcher);
    const originalCwd = process.cwd();

    repoWatcherService.watchRepo('bob', 'myrepo');

    const watchCall = mockWatch.mock.calls[0];
    expect(watchCall[0]).toBe(`${originalCwd}/repos/bob/myrepo`);
  });
});

describe('RepoWatcherService.unwatchRepo', () => {
  beforeEach(() => {
    mockWatch.mockClear();
    mockWatcher.close.mockClear();
    mockJjSyncService.syncToDatabase.mockClear();
    const service = repoWatcherService as any;
    service.watchers.clear();
    service.debounceTimers.clear();
  });

  test('closes and removes watcher', () => {
    mockWatch.mockReturnValue(mockWatcher);

    repoWatcherService.watchRepo('user', 'repo');
    repoWatcherService.unwatchRepo('user', 'repo');

    expect(mockWatcher.close).toHaveBeenCalledTimes(1);
  });

  test('handles unwatching non-existent watcher', () => {
    // Should not throw
    expect(() => {
      repoWatcherService.unwatchRepo('nonexistent', 'repo');
    }).not.toThrow();
  });

  test('clears pending debounce timer', async () => {
    mockWatch.mockReturnValue({
      ...mockWatcher,
      close: mock(() => {}),
    });

    repoWatcherService.watchRepo('user', 'repo');

    // Trigger a change to create a debounce timer
    const service = repoWatcherService as any;
    service.handleChange('user', 'repo', 'file.txt');

    // Unwatch should clear the timer
    repoWatcherService.unwatchRepo('user', 'repo');

    // Wait to ensure sync doesn't happen
    await new Promise((resolve) => setTimeout(resolve, 400));

    expect(mockJjSyncService.syncToDatabase).not.toHaveBeenCalled();
  });

  test('allows re-watching after unwatching', () => {
    mockWatch.mockReturnValue(mockWatcher);

    repoWatcherService.watchRepo('user', 'repo');
    repoWatcherService.unwatchRepo('user', 'repo');
    repoWatcherService.watchRepo('user', 'repo');

    expect(mockWatch).toHaveBeenCalledTimes(2);
  });
});

describe('RepoWatcherService.handleChange', () => {
  beforeEach(() => {
    mockWatch.mockClear();
    mockJjSyncService.syncToDatabase.mockClear();
    const service = repoWatcherService as any;
    service.watchers.clear();
    service.debounceTimers.clear();
  });

  test('ignores .jj/ directory changes', async () => {
    mockWatch.mockImplementation((path, options, callback) => {
      callback('change', '.jj/store/abc123');
      return mockWatcher;
    });

    repoWatcherService.watchRepo('user', 'repo');

    await new Promise((resolve) => setTimeout(resolve, 400));

    expect(mockJjSyncService.syncToDatabase).not.toHaveBeenCalled();
  });

  test('ignores .git/ directory changes', async () => {
    mockWatch.mockImplementation((path, options, callback) => {
      callback('change', '.git/objects/12/345');
      return mockWatcher;
    });

    repoWatcherService.watchRepo('user', 'repo');

    await new Promise((resolve) => setTimeout(resolve, 400));

    expect(mockJjSyncService.syncToDatabase).not.toHaveBeenCalled();
  });

  test('triggers sync for file changes', async () => {
    mockWatch.mockImplementation((path, options, callback) => {
      callback('change', 'src/main.ts');
      return mockWatcher;
    });
    mockJjSyncService.syncToDatabase.mockResolvedValue(undefined);

    repoWatcherService.watchRepo('user', 'repo');

    await new Promise((resolve) => setTimeout(resolve, 400));

    expect(mockJjSyncService.syncToDatabase).toHaveBeenCalledWith('user', 'repo');
  });

  test('debounces multiple rapid changes', async () => {
    let changeCallback: any;
    mockWatch.mockImplementation((path, options, callback) => {
      changeCallback = callback;
      return mockWatcher;
    });
    mockJjSyncService.syncToDatabase.mockResolvedValue(undefined);

    repoWatcherService.watchRepo('user', 'repo');

    // Trigger multiple changes rapidly
    changeCallback('change', 'file1.ts');
    await new Promise((resolve) => setTimeout(resolve, 50));
    changeCallback('change', 'file2.ts');
    await new Promise((resolve) => setTimeout(resolve, 50));
    changeCallback('change', 'file3.ts');

    // Wait for debounce to complete
    await new Promise((resolve) => setTimeout(resolve, 400));

    // Should only sync once due to debouncing
    expect(mockJjSyncService.syncToDatabase).toHaveBeenCalledTimes(1);
  });

  test('handles sync errors gracefully', async () => {
    mockWatch.mockImplementation((path, options, callback) => {
      callback('change', 'error.ts');
      return mockWatcher;
    });
    mockJjSyncService.syncToDatabase.mockRejectedValue(new Error('Sync failed'));

    // Should not throw
    repoWatcherService.watchRepo('user', 'repo');

    await new Promise((resolve) => setTimeout(resolve, 400));

    expect(mockJjSyncService.syncToDatabase).toHaveBeenCalled();
  });

  test('handles null filename', async () => {
    mockWatch.mockImplementation((path, options, callback) => {
      callback('change', null);
      return mockWatcher;
    });
    mockJjSyncService.syncToDatabase.mockResolvedValue(undefined);

    repoWatcherService.watchRepo('user', 'repo');

    await new Promise((resolve) => setTimeout(resolve, 400));

    // Should still trigger sync even with null filename
    expect(mockJjSyncService.syncToDatabase).toHaveBeenCalledWith('user', 'repo');
  });

  test('resets debounce timer on new changes', async () => {
    let changeCallback: any;
    mockWatch.mockImplementation((path, options, callback) => {
      changeCallback = callback;
      return mockWatcher;
    });
    mockJjSyncService.syncToDatabase.mockResolvedValue(undefined);

    repoWatcherService.watchRepo('user', 'repo');

    // First change
    changeCallback('change', 'file1.ts');
    await new Promise((resolve) => setTimeout(resolve, 250));

    // Second change before first debounce completes
    changeCallback('change', 'file2.ts');
    await new Promise((resolve) => setTimeout(resolve, 250));

    // Should not have synced yet (timer reset)
    expect(mockJjSyncService.syncToDatabase).not.toHaveBeenCalled();

    // Wait for final debounce
    await new Promise((resolve) => setTimeout(resolve, 100));

    expect(mockJjSyncService.syncToDatabase).toHaveBeenCalledTimes(1);
  });
});

describe('RepoWatcherService.watchAllRepos', () => {
  beforeEach(() => {
    mockSql.mockClear();
    mockWatch.mockClear();
    mockJjSyncService.syncToDatabase.mockClear();
    const service = repoWatcherService as any;
    service.watchers.clear();
    service.debounceTimers.clear();
  });

  test('watches all repositories from database', async () => {
    const mockRepos = [
      { user: 'alice', repo: 'project1' },
      { user: 'bob', repo: 'project2' },
      { user: 'alice', repo: 'project3' },
    ];

    mockSql.mockResolvedValue(mockRepos);
    mockWatch.mockReturnValue(mockWatcher);

    await repoWatcherService.watchAllRepos();

    expect(mockSql).toHaveBeenCalledTimes(1);
    expect(mockWatch).toHaveBeenCalledTimes(3);
  });

  test('handles empty repository list', async () => {
    mockSql.mockResolvedValue([]);

    await repoWatcherService.watchAllRepos();

    expect(mockWatch).not.toHaveBeenCalled();
  });

  test('handles database query error', async () => {
    mockSql.mockRejectedValue(new Error('Database error'));

    // Should not throw
    await expect(repoWatcherService.watchAllRepos()).resolves.toBeUndefined();

    expect(mockWatch).not.toHaveBeenCalled();
  });

  test('continues watching even if some fail', async () => {
    const mockRepos = [
      { user: 'alice', repo: 'repo1' },
      { user: 'bob', repo: 'repo2' },
      { user: 'charlie', repo: 'repo3' },
    ];

    mockSql.mockResolvedValue(mockRepos);
    mockWatch.mockImplementation((path) => {
      if (path.includes('bob')) {
        throw new Error('Failed to watch');
      }
      return mockWatcher;
    });

    await repoWatcherService.watchAllRepos();

    // Should have attempted to watch all repos
    expect(mockWatch).toHaveBeenCalledTimes(3);
  });

  test('skips already watched repositories', async () => {
    const mockRepos = [
      { user: 'alice', repo: 'project' },
      { user: 'bob', repo: 'project' },
    ];

    mockSql.mockResolvedValue(mockRepos);
    mockWatch.mockReturnValue(mockWatcher);

    // Watch one repo first
    repoWatcherService.watchRepo('alice', 'project');

    await repoWatcherService.watchAllRepos();

    // Should have called watch 3 times total: 1 manual + 2 from watchAllRepos
    // But alice/project should be skipped in watchAllRepos
    expect(mockWatch).toHaveBeenCalledTimes(2);
  });
});

describe('RepoWatcherService.getWatcherKey', () => {
  test('formats key correctly', () => {
    const service = repoWatcherService as any;
    expect(service.getWatcherKey('user', 'repo')).toBe('user/repo');
    expect(service.getWatcherKey('alice', 'myproject')).toBe('alice/myproject');
  });
});

describe('RepoWatcherService.getRepoPath', () => {
  test('constructs correct path', () => {
    const service = repoWatcherService as any;
    const cwd = process.cwd();
    expect(service.getRepoPath('user', 'repo')).toBe(`${cwd}/repos/user/repo`);
    expect(service.getRepoPath('test', 'project')).toBe(`${cwd}/repos/test/project`);
  });
});

describe('RepoWatcherService.shouldIgnorePath', () => {
  test('ignores .jj/ paths', () => {
    const service = repoWatcherService as any;
    expect(service.shouldIgnorePath('.jj/store/file')).toBe(true);
    expect(service.shouldIgnorePath('path/.jj/data')).toBe(true);
  });

  test('ignores .git/ paths', () => {
    const service = repoWatcherService as any;
    expect(service.shouldIgnorePath('.git/objects/12/34')).toBe(true);
    expect(service.shouldIgnorePath('dir/.git/config')).toBe(true);
  });

  test('does not ignore normal paths', () => {
    const service = repoWatcherService as any;
    expect(service.shouldIgnorePath('src/main.ts')).toBe(false);
    expect(service.shouldIgnorePath('README.md')).toBe(false);
    expect(service.shouldIgnorePath('tests/test.ts')).toBe(false);
  });

  test('does not ignore paths with .jj or .git in filename', () => {
    const service = repoWatcherService as any;
    expect(service.shouldIgnorePath('my.jj.file')).toBe(false);
    expect(service.shouldIgnorePath('.gitignore')).toBe(false);
  });
});

describe('RepoWatcherService debounce behavior', () => {
  beforeEach(() => {
    mockWatch.mockClear();
    mockJjSyncService.syncToDatabase.mockClear();
    const service = repoWatcherService as any;
    service.watchers.clear();
    service.debounceTimers.clear();
  });

  test('uses 300ms debounce by default', async () => {
    let changeCallback: any;
    mockWatch.mockImplementation((path, options, callback) => {
      changeCallback = callback;
      return mockWatcher;
    });
    mockJjSyncService.syncToDatabase.mockResolvedValue(undefined);

    repoWatcherService.watchRepo('user', 'repo');

    const startTime = Date.now();
    changeCallback('change', 'file.ts');

    // Wait for debounce
    await new Promise((resolve) => setTimeout(resolve, 350));

    const endTime = Date.now();
    const elapsed = endTime - startTime;

    expect(mockJjSyncService.syncToDatabase).toHaveBeenCalled();
    expect(elapsed).toBeGreaterThanOrEqual(300);
  });

  test('cleans up debounce timer after sync', async () => {
    let changeCallback: any;
    mockWatch.mockImplementation((path, options, callback) => {
      changeCallback = callback;
      return mockWatcher;
    });
    mockJjSyncService.syncToDatabase.mockResolvedValue(undefined);

    repoWatcherService.watchRepo('user', 'repo');

    changeCallback('change', 'file.ts');

    await new Promise((resolve) => setTimeout(resolve, 400));

    const service = repoWatcherService as any;
    expect(service.debounceTimers.has('user/repo')).toBe(false);
  });
});
