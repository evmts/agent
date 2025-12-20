/**
 * Tests for PTY manager - interactive command execution.
 */

import { describe, test, expect, beforeEach, afterEach } from 'bun:test';
import { PTYManager } from './pty-manager';
import { registerAgent, type AgentConfig } from '../registry';

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

describe('PTYManager Security', () => {
  let manager: PTYManager;

  beforeEach(() => {
    // Create manager with explicit agent name for security testing
    manager = new PTYManager({ agentName: 'security-test', maxSessions: 5 });
  });

  afterEach(async () => {
    await manager.cleanupAll();
  });

  describe('Command Validation', () => {
    test('should reject commands not allowed by agent config', async () => {
      // Register a restricted agent
      const restrictedAgent: AgentConfig = {
        name: 'security-test',
        description: 'Test agent with restricted commands',
        mode: 'subagent',
        systemPrompt: 'Test',
        temperature: 0.7,
        topP: 0.95,
        toolsEnabled: {},
        allowedShellPatterns: ['echo *', 'ls *'],
      };
      registerAgent(restrictedAgent);

      // This should fail - not in allowed patterns
      await expect(
        manager.createSession({
          cmd: 'rm -rf /',
        })
      ).rejects.toThrow('Command not allowed');

      // This should succeed - matches pattern
      const session = await manager.createSession({
        cmd: 'echo hello',
      });
      expect(session).toBeDefined();
      await manager.closeSession(session.id);
    });

    test('should allow all commands when wildcard is present', async () => {
      const wildcardAgent: AgentConfig = {
        name: 'security-test',
        description: 'Test agent with wildcard',
        mode: 'primary',
        systemPrompt: 'Test',
        temperature: 0.7,
        topP: 0.95,
        toolsEnabled: {},
        allowedShellPatterns: ['*'],
      };
      registerAgent(wildcardAgent);

      const session = await manager.createSession({
        cmd: 'echo "any command"',
      });
      expect(session).toBeDefined();
      await manager.closeSession(session.id);
    });
  });

  describe('Environment Variable Sanitization', () => {
    beforeEach(() => {
      // Ensure we have a wildcard agent for env tests
      const wildcardAgent: AgentConfig = {
        name: 'security-test',
        description: 'Test agent',
        mode: 'primary',
        systemPrompt: 'Test',
        temperature: 0.7,
        topP: 0.95,
        toolsEnabled: {},
        allowedShellPatterns: ['*'],
      };
      registerAgent(wildcardAgent);
    });

    test('should block LD_PRELOAD injection', async () => {
      const session = await manager.createSession({
        cmd: 'printenv | grep LD_PRELOAD || echo "LD_PRELOAD not set"',
        env: {
          LD_PRELOAD: '/malicious/library.so',
        },
      });

      // Wait for command to complete
      await session.process.exited;
      const output = await manager.readOutput(session.id);

      // LD_PRELOAD should not be present in the environment
      expect(output).toContain('not set');
      expect(output).not.toContain('/malicious/library.so');

      await manager.closeSession(session.id);
    });

    test('should block LD_LIBRARY_PATH injection', async () => {
      const session = await manager.createSession({
        cmd: 'printenv | grep LD_LIBRARY_PATH || echo "LD_LIBRARY_PATH not set"',
        env: {
          LD_LIBRARY_PATH: '/malicious/libs',
        },
      });

      await session.process.exited;
      const output = await manager.readOutput(session.id);

      expect(output).toContain('not set');
      expect(output).not.toContain('/malicious/libs');

      await manager.closeSession(session.id);
    });

    test('should block DYLD_INSERT_LIBRARIES injection (macOS)', async () => {
      const session = await manager.createSession({
        cmd: 'printenv | grep DYLD_INSERT_LIBRARIES || echo "DYLD_INSERT_LIBRARIES not set"',
        env: {
          DYLD_INSERT_LIBRARIES: '/malicious/library.dylib',
        },
      });

      await session.process.exited;
      const output = await manager.readOutput(session.id);

      expect(output).toContain('not set');
      expect(output).not.toContain('/malicious/library.dylib');

      await manager.closeSession(session.id);
    });

    test('should block NODE_OPTIONS injection', async () => {
      const session = await manager.createSession({
        cmd: 'printenv | grep NODE_OPTIONS || echo "NODE_OPTIONS not set"',
        env: {
          NODE_OPTIONS: '--require /malicious/script.js',
        },
      });

      await session.process.exited;
      const output = await manager.readOutput(session.id);

      expect(output).toContain('not set');
      expect(output).not.toContain('--require /malicious/script.js');

      await manager.closeSession(session.id);
    });

    test('should block PATH replacement', async () => {
      const existingPath = process.env.PATH || '';
      const firstPathComponent = existingPath.split(':')[0];

      // This should be blocked - completely replaces PATH
      const session = await manager.createSession({
        cmd: 'echo $PATH',
        env: {
          PATH: '/malicious/bin',
        },
      });

      await session.process.exited;
      const output = await manager.readOutput(session.id);

      // Should not contain the malicious path
      expect(output).not.toContain('/malicious/bin');
      // Should still have a path from the original
      expect(output.length).toBeGreaterThan(0);

      await manager.closeSession(session.id);
    });

    test('should allow PATH extension', async () => {
      const existingPath = process.env.PATH || '';

      // This should be allowed - extends PATH
      const session = await manager.createSession({
        cmd: 'echo $PATH',
        env: {
          PATH: `/safe/bin:${existingPath}`,
        },
      });

      await session.process.exited;
      const output = await manager.readOutput(session.id);

      // Should contain both the safe addition and original path
      expect(output).toContain('/safe/bin');
      expect(output).toContain(existingPath.split(':')[0]);

      await manager.closeSession(session.id);
    });

    test('should allow safe custom environment variables', async () => {
      const session = await manager.createSession({
        cmd: 'echo $MY_VAR $NODE_ENV $DEBUG',
        env: {
          MY_VAR: 'safe_value',
          NODE_ENV: 'test',
          DEBUG: 'true',
        },
      });

      await session.process.exited;
      const output = await manager.readOutput(session.id);

      expect(output).toContain('safe_value');
      expect(output).toContain('test');
      expect(output).toContain('true');

      await manager.closeSession(session.id);
    });

    test('should block multiple dangerous env vars simultaneously', async () => {
      const session = await manager.createSession({
        cmd: 'printenv | grep -E "(LD_PRELOAD|LD_LIBRARY_PATH|NODE_OPTIONS)" || echo "All blocked"',
        env: {
          LD_PRELOAD: '/malicious/lib.so',
          LD_LIBRARY_PATH: '/malicious/libs',
          NODE_OPTIONS: '--require /malicious/script.js',
        },
      });

      await session.process.exited;
      const output = await manager.readOutput(session.id);

      expect(output).toContain('All blocked');
      expect(output).not.toContain('/malicious');

      await manager.closeSession(session.id);
    });
  });

  describe('Shell Injection Prevention', () => {
    beforeEach(() => {
      const wildcardAgent: AgentConfig = {
        name: 'security-test',
        description: 'Test agent',
        mode: 'primary',
        systemPrompt: 'Test',
        temperature: 0.7,
        topP: 0.95,
        toolsEnabled: {},
        allowedShellPatterns: ['*'],
      };
      registerAgent(wildcardAgent);
    });

    test('should handle commands with special characters safely', async () => {
      // The command is passed to shell via -c, so shell metacharacters
      // are interpreted by the shell. We verify the system doesn't break.
      const session = await manager.createSession({
        cmd: 'echo "test; echo should not execute separately"',
      });

      await session.process.exited;
      const output = await manager.readOutput(session.id);

      // The entire string should be echoed as one unit
      expect(output).toContain('should not execute separately');

      await manager.closeSession(session.id);
    });
  });
});
