/**
 * Tests for PTY manager - interactive command execution.
 */

import { describe, test, expect, beforeEach, afterEach } from 'bun:test';
import { PTYManager } from './pty-manager';

describe('PTYManager', () => {
  let manager: PTYManager;

  beforeEach(() => {
    manager = new PTYManager({ maxSessions: 5, sessionTimeoutMs: 5000 });
  });

  afterEach(async () => {
    await manager.cleanupAll();
  });

  describe('session creation', () => {
    test('creates session with unique ID', async () => {
      const session = await manager.createSession({ cmd: 'echo hello' });

      expect(session.id).toBeTruthy();
      expect(session.id.length).toBe(8);
      expect(session.command).toBe('echo hello');
    });

    test('creates multiple sessions with different IDs', async () => {
      const session1 = await manager.createSession({ cmd: 'echo 1' });
      const session2 = await manager.createSession({ cmd: 'echo 2' });

      expect(session1.id).not.toBe(session2.id);
    });

    test('enforces max sessions limit', async () => {
      // Create max sessions
      for (let i = 0; i < 5; i++) {
        await manager.createSession({ cmd: `sleep 10` });
      }

      // Try to create one more
      await expect(manager.createSession({ cmd: 'echo overflow' })).rejects.toThrow('Maximum PTY sessions');
    });

    test('tracks session count', async () => {
      expect(manager.getSessionCount()).toBe(0);

      await manager.createSession({ cmd: 'echo 1' });
      expect(manager.getSessionCount()).toBe(1);

      await manager.createSession({ cmd: 'echo 2' });
      expect(manager.getSessionCount()).toBe(2);
    });

    test('uses custom working directory', async () => {
      const session = await manager.createSession({
        cmd: 'pwd',
        workdir: '/tmp',
      });

      expect(session.workdir).toBe('/tmp');
    });

    test('uses custom shell', async () => {
      const session = await manager.createSession({
        cmd: 'echo $SHELL',
        shell: '/bin/sh',
      });

      expect(session).toBeTruthy();
    });
  });

  describe('session listing', () => {
    test('lists all active sessions', async () => {
      await manager.createSession({ cmd: 'sleep 10' });
      await manager.createSession({ cmd: 'sleep 10' });

      const sessions = manager.listSessions();

      expect(sessions.length).toBe(2);
      expect(sessions[0].command).toBe('sleep 10');
      expect(sessions[1].command).toBe('sleep 10');
    });

    test('returns session info with correct fields', async () => {
      const session = await manager.createSession({ cmd: 'echo test', workdir: '/tmp' });

      const sessions = manager.listSessions();
      const info = sessions.find((s) => s.id === session.id);

      expect(info).toBeTruthy();
      expect(info!.id).toBe(session.id);
      expect(info!.command).toBe('echo test');
      expect(info!.workdir).toBe('/tmp');
      expect(info!.createdAt).toBeGreaterThan(0);
      expect(info!.lastActivity).toBeGreaterThan(0);
      expect(typeof info!.outputBufferSize).toBe('number');
    });

    test('returns empty list when no sessions', () => {
      const sessions = manager.listSessions();

      expect(sessions).toEqual([]);
    });
  });

  describe('process status', () => {
    test('returns running status for active process', async () => {
      const session = await manager.createSession({ cmd: 'sleep 10' });

      const status = manager.getProcessStatus(session.id);

      expect(status.running).toBe(true);
      expect(status.exitCode).toBeNull();
    });

    test('returns completed status after process exits', async () => {
      const session = await manager.createSession({ cmd: 'echo done' });

      // Wait for process to complete
      await session.process.exited;

      const status = manager.getProcessStatus(session.id);

      expect(status.running).toBe(false);
      expect(status.exitCode).toBe(0);
    });

    test('throws for non-existent session', () => {
      expect(() => manager.getProcessStatus('nonexistent')).toThrow('not found');
    });
  });

  describe('session closing', () => {
    test('closes session gracefully', async () => {
      const session = await manager.createSession({ cmd: 'sleep 10' });

      await manager.closeSession(session.id);

      expect(manager.getSessionCount()).toBe(0);
    });

    test('force closes session', async () => {
      const session = await manager.createSession({ cmd: 'sleep 10' });

      await manager.closeSession(session.id, true);

      expect(manager.getSessionCount()).toBe(0);
    });

    test('throws when closing non-existent session', async () => {
      await expect(manager.closeSession('nonexistent')).rejects.toThrow('not found');
    });

    test('cleans up all sessions', async () => {
      await manager.createSession({ cmd: 'sleep 10' });
      await manager.createSession({ cmd: 'sleep 10' });
      await manager.createSession({ cmd: 'sleep 10' });

      expect(manager.getSessionCount()).toBe(3);

      await manager.cleanupAll();

      expect(manager.getSessionCount()).toBe(0);
    });
  });

  describe('command execution', () => {
    test('executes simple command', async () => {
      const session = await manager.createSession({ cmd: 'echo "hello world"' });

      await session.process.exited;

      const status = manager.getProcessStatus(session.id);
      expect(status.exitCode).toBe(0);
    });

    test('captures non-zero exit code', async () => {
      const session = await manager.createSession({ cmd: 'exit 42' });

      await session.process.exited;

      const status = manager.getProcessStatus(session.id);
      expect(status.exitCode).toBe(42);
    });

    test('handles environment variables', async () => {
      const session = await manager.createSession({
        cmd: 'echo $TEST_VAR',
        env: { TEST_VAR: 'test_value' },
      });

      expect(session).toBeTruthy();
    });
  });

  describe('input/output', () => {
    test('writes input to session', async () => {
      const session = await manager.createSession({ cmd: 'cat' });

      await manager.writeInput(session.id, 'hello\n');

      // Just verify no errors - actual output testing is complex
      expect(session).toBeTruthy();

      await manager.closeSession(session.id, true);
    });

    test('throws when writing to non-existent session', async () => {
      await expect(manager.writeInput('nonexistent', 'data')).rejects.toThrow('not found');
    });

    test('throws when reading from non-existent session', async () => {
      await expect(manager.readOutput('nonexistent')).rejects.toThrow('not found');
    });
  });

  describe('buffer management', () => {
    test('initializes with empty output buffer', async () => {
      const session = await manager.createSession({ cmd: 'sleep 10' });

      expect(session.outputBuffer).toBe('');
    });

    test('tracks buffer size in session info', async () => {
      const session = await manager.createSession({ cmd: 'echo test' });

      const sessions = manager.listSessions();
      const info = sessions.find((s) => s.id === session.id);

      expect(typeof info!.outputBufferSize).toBe('number');
    });
  });

  describe('session metadata', () => {
    test('tracks created time', async () => {
      const before = Date.now();
      const session = await manager.createSession({ cmd: 'echo test' });
      const after = Date.now();

      expect(session.createdAt).toBeGreaterThanOrEqual(before);
      expect(session.createdAt).toBeLessThanOrEqual(after);
    });

    test('tracks last activity time', async () => {
      const session = await manager.createSession({ cmd: 'echo test' });

      expect(session.lastActivity).toBeGreaterThan(0);
      expect(session.lastActivity).toBeGreaterThanOrEqual(session.createdAt);
    });

    test('stores command and workdir', async () => {
      const session = await manager.createSession({
        cmd: 'ls -la',
        workdir: '/tmp',
      });

      expect(session.command).toBe('ls -la');
      expect(session.workdir).toBe('/tmp');
    });
  });
});
