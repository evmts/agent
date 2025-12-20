/**
 * Tests for session model types and interfaces.
 */

import { describe, test, expect } from 'bun:test';
import type {
  Session,
  SessionTime,
  SessionSummary,
  RevertInfo,
  CompactionInfo,
  GhostCommitInfo,
  CreateSessionOptions,
  UpdateSessionOptions,
} from '../session';

describe('SessionTime interface', () => {
  test('has correct structure', () => {
    const time: SessionTime = {
      created: Date.now(),
      updated: Date.now(),
      archived: Date.now(),
    };

    expect(typeof time.created).toBe('number');
    expect(typeof time.updated).toBe('number');
    expect(typeof time.archived).toBe('number');
  });

  test('archived is optional', () => {
    const time: SessionTime = {
      created: Date.now(),
      updated: Date.now(),
    };

    expect(time.archived).toBeUndefined();
  });
});

describe('SessionSummary interface', () => {
  test('has correct structure', () => {
    const summary: SessionSummary = {
      additions: 100,
      deletions: 50,
      files: 5,
    };

    expect(summary.additions).toBe(100);
    expect(summary.deletions).toBe(50);
    expect(summary.files).toBe(5);
  });

  test('handles zero values', () => {
    const summary: SessionSummary = {
      additions: 0,
      deletions: 0,
      files: 0,
    };

    expect(summary.additions).toBe(0);
    expect(summary.deletions).toBe(0);
    expect(summary.files).toBe(0);
  });
});

describe('RevertInfo interface', () => {
  test('has correct structure with all fields', () => {
    const revert: RevertInfo = {
      messageID: 'msg-123',
      partID: 'part-456',
      snapshot: 'snapshot-789',
    };

    expect(revert.messageID).toBe('msg-123');
    expect(revert.partID).toBe('part-456');
    expect(revert.snapshot).toBe('snapshot-789');
  });

  test('partID is optional', () => {
    const revert: RevertInfo = {
      messageID: 'msg-123',
      snapshot: 'snapshot-789',
    };

    expect(revert.messageID).toBe('msg-123');
    expect(revert.partID).toBeUndefined();
  });

  test('snapshot is optional', () => {
    const revert: RevertInfo = {
      messageID: 'msg-123',
      partID: 'part-456',
    };

    expect(revert.messageID).toBe('msg-123');
    expect(revert.snapshot).toBeUndefined();
  });
});

describe('CompactionInfo interface', () => {
  test('has correct structure', () => {
    const compaction: CompactionInfo = {
      originalCount: 100,
      compactedAt: Date.now(),
    };

    expect(compaction.originalCount).toBe(100);
    expect(typeof compaction.compactedAt).toBe('number');
  });

  test('handles large counts', () => {
    const compaction: CompactionInfo = {
      originalCount: 999999,
      compactedAt: Date.now(),
    };

    expect(compaction.originalCount).toBe(999999);
  });
});

describe('GhostCommitInfo interface', () => {
  test('has correct structure', () => {
    const ghostCommit: GhostCommitInfo = {
      enabled: true,
      currentTurn: 5,
      commits: ['commit-1', 'commit-2', 'commit-3'],
    };

    expect(ghostCommit.enabled).toBe(true);
    expect(ghostCommit.currentTurn).toBe(5);
    expect(ghostCommit.commits).toHaveLength(3);
  });

  test('works when disabled', () => {
    const ghostCommit: GhostCommitInfo = {
      enabled: false,
      currentTurn: 0,
      commits: [],
    };

    expect(ghostCommit.enabled).toBe(false);
    expect(ghostCommit.currentTurn).toBe(0);
    expect(ghostCommit.commits).toEqual([]);
  });

  test('handles many commits', () => {
    const commits = Array.from({ length: 100 }, (_, i) => `commit-${i}`);
    const ghostCommit: GhostCommitInfo = {
      enabled: true,
      currentTurn: 100,
      commits,
    };

    expect(ghostCommit.commits).toHaveLength(100);
    expect(ghostCommit.commits[0]).toBe('commit-0');
    expect(ghostCommit.commits[99]).toBe('commit-99');
  });
});

describe('Session interface', () => {
  test('has correct structure with required fields', () => {
    const session: Session = {
      id: 'session-123',
      projectID: 'project-456',
      directory: '/path/to/project',
      title: 'Test Session',
      version: '1.0.0',
      time: {
        created: Date.now(),
        updated: Date.now(),
      },
      tokenCount: 1000,
      bypassMode: false,
      plugins: [],
    };

    expect(session.id).toBe('session-123');
    expect(session.projectID).toBe('project-456');
    expect(session.directory).toBe('/path/to/project');
    expect(session.title).toBe('Test Session');
    expect(session.version).toBe('1.0.0');
    expect(session.tokenCount).toBe(1000);
    expect(session.bypassMode).toBe(false);
    expect(session.plugins).toEqual([]);
  });

  test('has optional fields', () => {
    const session: Session = {
      id: 'session-123',
      projectID: 'project-456',
      directory: '/path/to/project',
      title: 'Test Session',
      version: '1.0.0',
      time: {
        created: Date.now(),
        updated: Date.now(),
        archived: Date.now(),
      },
      parentID: 'parent-789',
      forkPoint: 'fork-abc',
      summary: {
        additions: 100,
        deletions: 50,
        files: 5,
      },
      revert: {
        messageID: 'msg-123',
      },
      compaction: {
        originalCount: 100,
        compactedAt: Date.now(),
      },
      tokenCount: 1000,
      bypassMode: false,
      model: 'claude-sonnet-4',
      reasoningEffort: 'medium',
      ghostCommit: {
        enabled: true,
        currentTurn: 5,
        commits: ['commit-1'],
      },
      plugins: ['plugin-1', 'plugin-2'],
    };

    expect(session.parentID).toBe('parent-789');
    expect(session.forkPoint).toBe('fork-abc');
    expect(session.summary).toBeDefined();
    expect(session.revert).toBeDefined();
    expect(session.compaction).toBeDefined();
    expect(session.model).toBe('claude-sonnet-4');
    expect(session.reasoningEffort).toBe('medium');
    expect(session.ghostCommit).toBeDefined();
    expect(session.plugins).toHaveLength(2);
  });

  test('reasoning effort values', () => {
    const efforts: Array<'minimal' | 'low' | 'medium' | 'high'> = [
      'minimal',
      'low',
      'medium',
      'high',
    ];

    efforts.forEach(effort => {
      const session: Session = {
        id: 'session-123',
        projectID: 'project-456',
        directory: '/path/to/project',
        title: 'Test Session',
        version: '1.0.0',
        time: {
          created: Date.now(),
          updated: Date.now(),
        },
        tokenCount: 1000,
        bypassMode: false,
        reasoningEffort: effort,
        plugins: [],
      };

      expect(session.reasoningEffort).toBe(effort);
    });
  });

  test('bypass mode states', () => {
    const enabled: Session = {
      id: 'session-123',
      projectID: 'project-456',
      directory: '/path/to/project',
      title: 'Test Session',
      version: '1.0.0',
      time: {
        created: Date.now(),
        updated: Date.now(),
      },
      tokenCount: 1000,
      bypassMode: true,
      plugins: [],
    };

    const disabled: Session = {
      id: 'session-123',
      projectID: 'project-456',
      directory: '/path/to/project',
      title: 'Test Session',
      version: '1.0.0',
      time: {
        created: Date.now(),
        updated: Date.now(),
      },
      tokenCount: 1000,
      bypassMode: false,
      plugins: [],
    };

    expect(enabled.bypassMode).toBe(true);
    expect(disabled.bypassMode).toBe(false);
  });

  test('plugins array', () => {
    const session: Session = {
      id: 'session-123',
      projectID: 'project-456',
      directory: '/path/to/project',
      title: 'Test Session',
      version: '1.0.0',
      time: {
        created: Date.now(),
        updated: Date.now(),
      },
      tokenCount: 1000,
      bypassMode: false,
      plugins: ['git', 'docker', 'kubernetes'],
    };

    expect(session.plugins).toHaveLength(3);
    expect(session.plugins).toContain('git');
    expect(session.plugins).toContain('docker');
    expect(session.plugins).toContain('kubernetes');
  });
});

describe('CreateSessionOptions interface', () => {
  test('has required fields', () => {
    const options: CreateSessionOptions = {
      directory: '/path/to/project',
    };

    expect(options.directory).toBe('/path/to/project');
  });

  test('has optional fields', () => {
    const options: CreateSessionOptions = {
      directory: '/path/to/project',
      title: 'New Session',
      parentID: 'parent-123',
      bypassMode: true,
      model: 'claude-opus-4',
      reasoningEffort: 'high',
      plugins: ['plugin-1'],
    };

    expect(options.title).toBe('New Session');
    expect(options.parentID).toBe('parent-123');
    expect(options.bypassMode).toBe(true);
    expect(options.model).toBe('claude-opus-4');
    expect(options.reasoningEffort).toBe('high');
    expect(options.plugins).toEqual(['plugin-1']);
  });

  test('minimal valid options', () => {
    const options: CreateSessionOptions = {
      directory: '/tmp',
    };

    expect(options.directory).toBe('/tmp');
    expect(options.title).toBeUndefined();
    expect(options.parentID).toBeUndefined();
    expect(options.bypassMode).toBeUndefined();
  });
});

describe('UpdateSessionOptions interface', () => {
  test('all fields are optional', () => {
    const options: UpdateSessionOptions = {};

    expect(options.title).toBeUndefined();
    expect(options.archived).toBeUndefined();
    expect(options.model).toBeUndefined();
    expect(options.reasoningEffort).toBeUndefined();
  });

  test('can update title', () => {
    const options: UpdateSessionOptions = {
      title: 'Updated Title',
    };

    expect(options.title).toBe('Updated Title');
  });

  test('can archive session', () => {
    const options: UpdateSessionOptions = {
      archived: true,
    };

    expect(options.archived).toBe(true);
  });

  test('can update model', () => {
    const options: UpdateSessionOptions = {
      model: 'claude-sonnet-4',
    };

    expect(options.model).toBe('claude-sonnet-4');
  });

  test('can update reasoning effort', () => {
    const options: UpdateSessionOptions = {
      reasoningEffort: 'low',
    };

    expect(options.reasoningEffort).toBe('low');
  });

  test('can update multiple fields', () => {
    const options: UpdateSessionOptions = {
      title: 'New Title',
      archived: false,
      model: 'claude-opus-4',
      reasoningEffort: 'medium',
    };

    expect(options.title).toBe('New Title');
    expect(options.archived).toBe(false);
    expect(options.model).toBe('claude-opus-4');
    expect(options.reasoningEffort).toBe('medium');
  });
});

describe('Session lifecycle', () => {
  test('create, update, and archive flow', () => {
    // Create
    const createOptions: CreateSessionOptions = {
      directory: '/path/to/project',
      title: 'Initial Title',
      bypassMode: false,
    };

    const session: Session = {
      id: 'session-123',
      projectID: 'project-456',
      directory: createOptions.directory,
      title: createOptions.title!,
      version: '1.0.0',
      time: {
        created: Date.now(),
        updated: Date.now(),
      },
      tokenCount: 0,
      bypassMode: createOptions.bypassMode!,
      plugins: [],
    };

    expect(session.title).toBe('Initial Title');
    expect(session.bypassMode).toBe(false);
    expect(session.time.archived).toBeUndefined();

    // Update
    const updateOptions: UpdateSessionOptions = {
      title: 'Updated Title',
      model: 'claude-sonnet-4',
    };

    const updatedSession: Session = {
      ...session,
      title: updateOptions.title!,
      model: updateOptions.model,
      time: {
        ...session.time,
        updated: Date.now(),
      },
    };

    expect(updatedSession.title).toBe('Updated Title');
    expect(updatedSession.model).toBe('claude-sonnet-4');

    // Archive
    const archiveOptions: UpdateSessionOptions = {
      archived: true,
    };

    const archivedSession: Session = {
      ...updatedSession,
      time: {
        ...updatedSession.time,
        archived: Date.now(),
      },
    };

    expect(archivedSession.time.archived).toBeDefined();
    expect(typeof archivedSession.time.archived).toBe('number');
  });

  test('forked session', () => {
    const parentSession: Session = {
      id: 'parent-123',
      projectID: 'project-456',
      directory: '/path/to/project',
      title: 'Parent Session',
      version: '1.0.0',
      time: {
        created: Date.now(),
        updated: Date.now(),
      },
      tokenCount: 1000,
      bypassMode: false,
      plugins: [],
    };

    const forkedSession: Session = {
      id: 'forked-456',
      projectID: parentSession.projectID,
      directory: parentSession.directory,
      title: 'Forked Session',
      version: parentSession.version,
      time: {
        created: Date.now(),
        updated: Date.now(),
      },
      parentID: parentSession.id,
      forkPoint: 'msg-789',
      tokenCount: 0,
      bypassMode: parentSession.bypassMode,
      plugins: [...parentSession.plugins],
    };

    expect(forkedSession.parentID).toBe(parentSession.id);
    expect(forkedSession.forkPoint).toBe('msg-789');
    expect(forkedSession.projectID).toBe(parentSession.projectID);
  });

  test('session with ghost commits enabled', () => {
    const session: Session = {
      id: 'session-123',
      projectID: 'project-456',
      directory: '/path/to/project',
      title: 'Ghost Commit Session',
      version: '1.0.0',
      time: {
        created: Date.now(),
        updated: Date.now(),
      },
      tokenCount: 500,
      bypassMode: false,
      ghostCommit: {
        enabled: true,
        currentTurn: 0,
        commits: [],
      },
      plugins: [],
    };

    expect(session.ghostCommit?.enabled).toBe(true);
    expect(session.ghostCommit?.currentTurn).toBe(0);
    expect(session.ghostCommit?.commits).toEqual([]);

    // Simulate turn progression
    const afterTurn1: Session = {
      ...session,
      ghostCommit: {
        enabled: true,
        currentTurn: 1,
        commits: ['commit-1'],
      },
    };

    expect(afterTurn1.ghostCommit?.currentTurn).toBe(1);
    expect(afterTurn1.ghostCommit?.commits).toHaveLength(1);
  });
});

describe('Edge cases', () => {
  test('empty strings', () => {
    const session: Session = {
      id: '',
      projectID: '',
      directory: '',
      title: '',
      version: '',
      time: {
        created: 0,
        updated: 0,
      },
      tokenCount: 0,
      bypassMode: false,
      plugins: [],
    };

    expect(session.id).toBe('');
    expect(session.title).toBe('');
  });

  test('large token counts', () => {
    const session: Session = {
      id: 'session-123',
      projectID: 'project-456',
      directory: '/path/to/project',
      title: 'Large Session',
      version: '1.0.0',
      time: {
        created: Date.now(),
        updated: Date.now(),
      },
      tokenCount: 1000000,
      bypassMode: false,
      plugins: [],
    };

    expect(session.tokenCount).toBe(1000000);
  });

  test('special characters in paths', () => {
    const session: Session = {
      id: 'session-123',
      projectID: 'project-456',
      directory: '/path/with spaces/and-特殊字符/emoji😀',
      title: 'Session with 特殊字符 and emoji 😀',
      version: '1.0.0',
      time: {
        created: Date.now(),
        updated: Date.now(),
      },
      tokenCount: 100,
      bypassMode: false,
      plugins: [],
    };

    expect(session.directory).toContain('特殊字符');
    expect(session.title).toContain('😀');
  });
});
