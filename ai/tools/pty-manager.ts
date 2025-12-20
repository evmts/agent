/**
 * PTY session management for interactive command execution.
 *
 * Provides PTYManager for creating and managing pseudo-terminal sessions,
 * enabling interactive command execution with stdin/stdout support.
 */

import { spawn, type Subprocess } from 'bun';
import { isShellCommandAllowed } from '../registry';

// Constants
const DEFAULT_MAX_SESSIONS = 10;
const DEFAULT_SESSION_TIMEOUT_MS = 300000; // 5 minutes
const DEFAULT_READ_TIMEOUT_MS = 100;
const DEFAULT_MAX_READ_BYTES = 65536;
const DEFAULT_MAX_BUFFER_SIZE = 1024 * 1024; // 1MB max buffer per session

// Whitelist of safe environment variables that can be passed to spawned processes
// Blocks dangerous variables that could be used for code injection
const SAFE_ENV_VARS = new Set([
  'HOME',
  'USER',
  'LOGNAME',
  'SHELL',
  'TERM',
  'TMPDIR',
  'LANG',
  'LC_ALL',
  'LC_CTYPE',
  'TZ',
  'PWD',
  'EDITOR',
  'VISUAL',
  'PAGER',
  'NODE_ENV',
  'NO_COLOR',
  'FORCE_COLOR',
  'CI',
  'DEBUG',
]);

// Dangerous environment variables that must never be passed to child processes
const BLOCKED_ENV_VARS = new Set([
  'LD_PRELOAD',
  'LD_LIBRARY_PATH',
  'DYLD_INSERT_LIBRARIES',
  'DYLD_LIBRARY_PATH',
  'NODE_OPTIONS',
  'PYTHON_PATH',
  'PERL5LIB',
  'RUBYLIB',
]);

export interface PTYSession {
  id: string;
  process: Subprocess;
  outputBuffer: string;
  createdAt: number;
  lastActivity: number;
  command: string;
  workdir: string;
}

export interface ProcessStatus {
  running: boolean;
  exitCode: number | null;
}

export interface SessionInfo {
  id: string;
  pid: number | undefined;
  command: string;
  workdir: string;
  createdAt: number;
  lastActivity: number;
  outputBufferSize: number;
  running: boolean;
}

/**
 * Sanitize environment variables by filtering out dangerous ones.
 */
function sanitizeEnvironment(
  userEnv?: Record<string, string>,
  agentName: string = 'build'
): Record<string, string> {
  const sanitized: Record<string, string> = {};

  // Start with safe system environment variables
  for (const [key, value] of Object.entries(process.env)) {
    if (SAFE_ENV_VARS.has(key) && !BLOCKED_ENV_VARS.has(key)) {
      sanitized[key] = value;
    }
  }

  // Add user-provided env vars if they're safe
  if (userEnv) {
    for (const [key, value] of Object.entries(userEnv)) {
      // Block dangerous variables
      if (BLOCKED_ENV_VARS.has(key)) {
        continue;
      }

      // Block PATH manipulation attempts (only allow PATH if it's a safe addition)
      if (key === 'PATH') {
        // Only allow PATH if it's extending the existing PATH, not replacing it
        const existingPath = process.env.PATH || '';
        if (!value.includes(existingPath)) {
          continue;
        }
      }

      sanitized[key] = value;
    }
  }

  return sanitized;
}

/**
 * Manages multiple PTY sessions for interactive command execution.
 */
export class PTYManager {
  private sessions = new Map<string, PTYSession>();
  private maxSessions: number;
  private sessionTimeoutMs: number;
  private agentName: string;

  constructor(options?: {
    maxSessions?: number;
    sessionTimeoutMs?: number;
    agentName?: string;
  }) {
    this.maxSessions = options?.maxSessions ?? DEFAULT_MAX_SESSIONS;
    this.sessionTimeoutMs = options?.sessionTimeoutMs ?? DEFAULT_SESSION_TIMEOUT_MS;
    this.agentName = options?.agentName ?? 'build';
  }

  /**
   * Generate a unique session ID.
   */
  private generateId(): string {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    let id = '';
    for (let i = 0; i < 8; i++) {
      id += chars[Math.floor(Math.random() * chars.length)];
    }
    return id;
  }

  /**
   * Create a new PTY session.
   */
  async createSession(options: {
    cmd: string;
    workdir?: string;
    shell?: string;
    env?: Record<string, string>;
    login?: boolean;
  }): Promise<PTYSession> {
    // Cleanup stale sessions first
    await this.cleanupStaleSessions();

    if (this.sessions.size >= this.maxSessions) {
      throw new Error(`Maximum PTY sessions (${this.maxSessions}) reached`);
    }

    // Validate command is allowed for this agent
    if (!isShellCommandAllowed(this.agentName, options.cmd)) {
      throw new Error(
        `Command not allowed for agent '${this.agentName}': ${options.cmd.substring(0, 100)}`
      );
    }

    // Sanitize environment variables to prevent injection attacks
    const sanitizedEnv = sanitizeEnvironment(options.env, this.agentName);

    const sessionId = this.generateId();
    const workdir = options.workdir ?? process.cwd();
    const shell = options.shell ?? process.env.SHELL ?? '/bin/bash';

    // Build shell command
    const shellArgs = options.login
      ? [shell, '-l', '-c', options.cmd]
      : [shell, '-c', options.cmd];

    // Spawn the process with sanitized environment
    const proc = spawn({
      cmd: shellArgs,
      cwd: workdir,
      env: sanitizedEnv,
      stdin: 'pipe',
      stdout: 'pipe',
      stderr: 'pipe',
    });

    const now = Date.now();
    const session: PTYSession = {
      id: sessionId,
      process: proc,
      outputBuffer: '',
      createdAt: now,
      lastActivity: now,
      command: options.cmd,
      workdir,
    };

    this.sessions.set(sessionId, session);
    return session;
  }

  /**
   * Write input to a PTY session.
   */
  async writeInput(sessionId: string, data: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    const stdin = session.process.stdin;
    if (!stdin || typeof stdin === 'number') {
      throw new Error(`Session ${sessionId} stdin not available`);
    }

    // Write to stdin - FileSink has write() method directly
    const encoded = new TextEncoder().encode(data);
    (stdin as { write: (data: Uint8Array) => number }).write(encoded);
    session.lastActivity = Date.now();
  }

  /**
   * Read available output from a PTY session.
   */
  async readOutput(
    sessionId: string,
    timeoutMs: number = DEFAULT_READ_TIMEOUT_MS,
    maxBytes: number = DEFAULT_MAX_READ_BYTES
  ): Promise<string> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    const stdout = session.process.stdout;
    const stderr = session.process.stderr;

    if (!stdout || typeof stdout === 'number') {
      return '';
    }

    const output: string[] = [];
    let totalBytes = 0;
    const deadline = Date.now() + timeoutMs;

    // Read from stdout
    const reader = (stdout as ReadableStream<Uint8Array>).getReader();

    try {
      while (Date.now() < deadline && totalBytes < maxBytes) {
        // Use a race between read and timeout
        const timeLeft = Math.max(deadline - Date.now(), 0);

        const result = await Promise.race([
          reader.read(),
          new Promise<{ done: true; value: undefined }>((resolve) =>
            setTimeout(() => resolve({ done: true, value: undefined }), timeLeft)
          ),
        ]);

        if (result.done || !result.value) {
          break;
        }

        const decoded = new TextDecoder().decode(result.value);
        output.push(decoded);
        totalBytes += result.value.length;
      }
    } catch {
      // Process may have exited
    } finally {
      reader.releaseLock();
    }

    // Also try to read from stderr
    if (stderr && typeof stderr !== 'number') {
      const stderrReader = (stderr as ReadableStream<Uint8Array>).getReader();
      try {
        const result = await Promise.race([
          stderrReader.read(),
          new Promise<{ done: true; value: undefined }>((resolve) =>
            setTimeout(() => resolve({ done: true, value: undefined }), 10)
          ),
        ]);

        if (!result.done && result.value) {
          const decoded = new TextDecoder().decode(result.value);
          output.push(decoded);
        }
      } catch {
        // Ignore stderr errors
      } finally {
        stderrReader.releaseLock();
      }
    }

    const result = output.join('');
    session.outputBuffer += result;

    // Trim buffer if it exceeds max size (keep last portion)
    if (session.outputBuffer.length > DEFAULT_MAX_BUFFER_SIZE) {
      const trimStart = session.outputBuffer.length - DEFAULT_MAX_BUFFER_SIZE;
      session.outputBuffer = session.outputBuffer.slice(trimStart);
    }

    session.lastActivity = Date.now();
    return result;
  }

  /**
   * Get the status of a PTY session's process.
   */
  getProcessStatus(sessionId: string): ProcessStatus {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    const exitCode = session.process.exitCode;

    if (exitCode === null) {
      return { running: true, exitCode: null };
    }

    return { running: false, exitCode };
  }

  /**
   * Close and cleanup a PTY session.
   */
  async closeSession(sessionId: string, force: boolean = false): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    this.sessions.delete(sessionId);

    try {
      // Kill the process
      if (force) {
        session.process.kill(9); // SIGKILL
      } else {
        session.process.kill(15); // SIGTERM

        // Wait for graceful termination
        await Promise.race([
          session.process.exited,
          new Promise((resolve) => setTimeout(resolve, 1000)),
        ]);

        // Force kill if still running
        if (session.process.exitCode === null) {
          session.process.kill(9);
        }
      }
    } catch {
      // Process may have already exited
    }
  }

  /**
   * Remove sessions that have timed out.
   */
  private async cleanupStaleSessions(): Promise<void> {
    const now = Date.now();
    const stale: string[] = [];

    for (const [id, session] of this.sessions) {
      if (now - session.lastActivity > this.sessionTimeoutMs) {
        stale.push(id);
      }
    }

    for (const id of stale) {
      try {
        await this.closeSession(id);
      } catch {
        // Already removed
      }
    }
  }

  /**
   * Close all active sessions.
   */
  async cleanupAll(): Promise<void> {
    const sessionIds = Array.from(this.sessions.keys());
    for (const id of sessionIds) {
      try {
        await this.closeSession(id);
      } catch {
        // Already removed
      }
    }
  }

  /**
   * List all active sessions.
   */
  listSessions(): SessionInfo[] {
    return Array.from(this.sessions.values()).map((session) => ({
      id: session.id,
      pid: session.process.pid,
      command: session.command,
      workdir: session.workdir,
      createdAt: session.createdAt,
      lastActivity: session.lastActivity,
      outputBufferSize: session.outputBuffer.length,
      running: session.process.exitCode === null,
    }));
  }

  /**
   * Get session count.
   */
  getSessionCount(): number {
    return this.sessions.size;
  }
}

// Global PTY manager instance
let globalPtyManager: PTYManager | null = null;

export function getPtyManager(): PTYManager {
  if (!globalPtyManager) {
    globalPtyManager = new PTYManager();
  }
  return globalPtyManager;
}

export function setPtyManager(manager: PTYManager): void {
  globalPtyManager = manager;
}
