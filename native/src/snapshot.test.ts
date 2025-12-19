import { test, expect, beforeAll, afterAll, describe } from 'bun:test';
import { Snapshot, SnapshotSessionManager } from './snapshot';
import { isJjWorkspace } from '../index.js';

const TEST_DIR = `/tmp/jj-snapshot-test-${Date.now()}`;

// Check if jj CLI is available
async function isJjCliAvailable(): Promise<boolean> {
  try {
    const result = await Bun.$`jj --version`.quiet();
    return result.exitCode === 0;
  } catch {
    return false;
  }
}

describe('Snapshot System', () => {
  let jjAvailable = false;

  beforeAll(async () => {
    jjAvailable = await isJjCliAvailable();
    if (!jjAvailable) {
      console.log('⚠️  jj CLI not available - some tests will be skipped');
    }
    // Create test directory
    await Bun.$`mkdir -p ${TEST_DIR}`;
  });

  afterAll(async () => {
    // Cleanup
    await Bun.$`rm -rf ${TEST_DIR}`;
  });

  describe('Initialization', () => {
    test('should initialize a new workspace', () => {
      if (!jjAvailable) return;

      const testPath = `${TEST_DIR}/init-test`;
      Bun.spawnSync(['mkdir', '-p', testPath]);

      const snapshot = Snapshot.init(testPath);

      expect(snapshot.isInitialized).toBe(true);
      expect(snapshot.root).toBe(testPath);
      expect(isJjWorkspace(testPath)).toBe(true);
    });

    test('should open existing workspace', () => {
      if (!jjAvailable) return;

      const testPath = `${TEST_DIR}/init-test`;

      const snapshot = Snapshot.open(testPath);

      expect(snapshot.isInitialized).toBe(true);
      expect(snapshot.root).toBe(testPath);
    });

    test('should throw when opening non-workspace', () => {
      const testPath = `${TEST_DIR}/not-a-workspace`;
      Bun.spawnSync(['mkdir', '-p', testPath]);

      expect(() => Snapshot.open(testPath)).toThrow('Not a jj workspace');
    });
  });

  describe('Snapshot Operations', () => {
    let snapshot: Snapshot;
    let testPath: string;

    beforeAll(async () => {
      if (!jjAvailable) return;

      testPath = `${TEST_DIR}/ops-test`;
      await Bun.$`mkdir -p ${testPath}`;
      snapshot = Snapshot.init(testPath);
    });

    test('should track a snapshot', async () => {
      if (!jjAvailable) return;

      // Create a file
      await Bun.write(`${testPath}/test.txt`, 'hello world');

      const changeId = await snapshot.track('First snapshot');

      expect(changeId).toBeTruthy();
      expect(changeId.length).toBeGreaterThan(0);
    });

    test('should get current state', async () => {
      if (!jjAvailable) return;

      const current = await snapshot.current();

      expect(current).toBeTruthy();
      expect(current.length).toBeGreaterThan(0);
    });

    test('should detect changed files with patch', async () => {
      if (!jjAvailable) return;

      // Track current state
      const before = await snapshot.track('Before changes');

      // Make changes
      await Bun.write(`${testPath}/new-file.txt`, 'new content');
      await Bun.write(`${testPath}/test.txt`, 'modified content');

      // Get changed files
      const changedFiles = await snapshot.patch(before);

      expect(changedFiles).toContain('new-file.txt');
      expect(changedFiles).toContain('test.txt');
    });

    test('should get detailed diff', async () => {
      if (!jjAvailable) return;

      // Track current state
      const before = await snapshot.track('Before diff test');

      // Make changes
      await Bun.write(`${testPath}/diff-test.txt`, 'line 1\nline 2\nline 3\n');

      const diffs = await snapshot.diff(before);

      expect(diffs.length).toBeGreaterThan(0);

      const diffTestFile = diffs.find(d => d.path === 'diff-test.txt');
      expect(diffTestFile).toBeTruthy();
      expect(diffTestFile?.changeType).toBe('added');
    });

    test('should restore from snapshot', async () => {
      if (!jjAvailable) return;

      // Track initial state
      const initial = await snapshot.track('Initial state');

      // Make changes
      await Bun.write(`${testPath}/to-delete.txt`, 'will be restored');

      // Track changed state
      await snapshot.track('Changed state');

      // Restore to initial
      await snapshot.restore(initial);

      // File should be gone (wasn't in initial snapshot)
      const exists = await Bun.file(`${testPath}/to-delete.txt`).exists();
      expect(exists).toBe(false);
    });

    test('should get file at specific snapshot', async () => {
      if (!jjAvailable) return;

      // Create file with initial content
      await Bun.write(`${testPath}/versioned.txt`, 'version 1');
      const v1 = await snapshot.track('Version 1');

      // Modify file
      await Bun.write(`${testPath}/versioned.txt`, 'version 2');
      await snapshot.track('Version 2');

      // Get file at v1
      const contentAtV1 = await snapshot.getFileAt(v1, 'versioned.txt');

      expect(contentAtV1).toBe('version 1');
    });

    test('should list files at snapshot', async () => {
      if (!jjAvailable) return;

      await Bun.write(`${testPath}/file-a.txt`, 'a');
      await Bun.write(`${testPath}/file-b.txt`, 'b');
      const snapshotId = await snapshot.track('Multiple files');

      const files = await snapshot.listFilesAt(snapshotId);

      expect(files).toContain('file-a.txt');
      expect(files).toContain('file-b.txt');
    });
  });

  describe('Operation Log', () => {
    test('should list operations', async () => {
      if (!jjAvailable) return;

      const testPath = `${TEST_DIR}/oplog-test`;
      await Bun.$`mkdir -p ${testPath}`;
      const snapshot = Snapshot.init(testPath);

      // Create some operations
      await Bun.write(`${testPath}/op1.txt`, 'op1');
      await snapshot.track('Operation 1');
      await Bun.write(`${testPath}/op2.txt`, 'op2');
      await snapshot.track('Operation 2');

      const ops = await snapshot.getOperationLog(10);

      expect(ops.length).toBeGreaterThan(0);
      expect(ops[0].description).toBeTruthy();
    });
  });

  describe('Session Manager', () => {
    test('should manage sessions', async () => {
      if (!jjAvailable) return;

      const manager = new SnapshotSessionManager();
      const testPath = `${TEST_DIR}/session-test`;
      await Bun.$`mkdir -p ${testPath}`;

      // Init session
      const initialSnapshot = await manager.initSession('test-session', testPath);

      expect(initialSnapshot).toBeTruthy();
      expect(manager.getActiveSessions()).toContain('test-session');

      // Track changes
      await Bun.write(`${testPath}/session-file.txt`, 'session content');
      const tracked = await manager.trackSnapshot('test-session', 'Session change');

      expect(tracked).toBeTruthy();

      // Check history
      const history = manager.getHistory('test-session');
      expect(history.length).toBe(2);

      // Cleanup
      manager.cleanupSession('test-session');
      expect(manager.getActiveSessions()).not.toContain('test-session');
    });
  });
});
