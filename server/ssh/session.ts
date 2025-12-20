/**
 * SSH Session Handler for Git operations.
 *
 * Handles git-upload-pack (clone/fetch) and git-receive-pack (push).
 */

import { spawn } from 'child_process';
import { join } from 'path';
import { existsSync } from 'fs';
import type { Connection, Session } from 'ssh2';

// Repos directory
const REPOS_DIR = join(process.cwd(), 'repos');

// Allowed git commands
const ALLOWED_COMMANDS = ['git-upload-pack', 'git-receive-pack'];

/**
 * Extract command and repo path from SSH command.
 * Command format: git-upload-pack '/user/repo.git'
 */
function extractCommand(rawCommand: string): { command: string; user: string; repo: string } | null {
  const parts = rawCommand.split(' ');
  if (parts.length < 2) return null;

  const command = parts[0];
  // Remove quotes and leading slash from path
  const repoPath = parts[1].replace(/^'|'$/g, '').replace(/^\//, '');

  // Parse user/repo.git format
  const match = repoPath.match(/^([^/]+)\/([^/]+?)(?:\.git)?$/);
  if (!match) return null;

  return {
    command,
    user: match[1],
    repo: match[2],
  };
}

/**
 * Get the full path to a repository.
 */
function getRepoPath(user: string, repo: string): string {
  return join(REPOS_DIR, user, repo);
}

/**
 * Handle an SSH session for git operations.
 */
export function handleSession(
  accept: () => Session,
  reject: () => void,
  client: Connection
): void {
  const session = accept();

  session.once('exec', (acceptExec, rejectExec, info) => {
    console.log(`SSH exec: ${info.command}`);

    const parsed = extractCommand(info.command);
    if (!parsed) {
      console.log(`SSH rejected: invalid command format`);
      rejectExec();
      return;
    }

    const { command, user, repo } = parsed;

    // Validate command
    if (!ALLOWED_COMMANDS.includes(command)) {
      console.log(`SSH rejected: command '${command}' not allowed`);
      rejectExec();
      return;
    }

    const repoPath = getRepoPath(user, repo);

    // Check if repo exists
    if (!existsSync(repoPath)) {
      console.log(`SSH rejected: repo not found at ${repoPath}`);
      rejectExec();
      return;
    }

    // Check if .git directory exists (for colocated jj repos)
    const gitDir = join(repoPath, '.git');
    if (!existsSync(gitDir)) {
      console.log(`SSH rejected: .git not found in ${repoPath}`);
      rejectExec();
      return;
    }

    console.log(`SSH executing: ${command} ${repoPath}`);

    const stream = acceptExec();

    // Spawn the git command
    const child = spawn(command, [repoPath], {
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    // Pipe streams
    stream.pipe(child.stdin);
    child.stdout.pipe(stream);
    child.stderr.pipe(stream.stderr);

    child.on('exit', (code) => {
      console.log(`SSH command exited with code ${code}`);
      stream.exit(code ?? 0);
      stream.end();
    });

    child.on('error', (err) => {
      console.error(`SSH command error:`, err);
      stream.stderr.write(`Error: ${err.message}\n`);
      stream.exit(1);
      stream.end();
    });
  });
}
