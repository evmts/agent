import { watch, type FSWatcher } from 'node:fs';
import { sql } from '../../ui/lib/db';
import { jjSyncService } from './jj-sync';

class RepoWatcherService {
  private watchers = new Map<string, FSWatcher>();
  private debounceTimers = new Map<string, Timer>();
  private DEBOUNCE_MS = 300;

  private getWatcherKey(user: string, repo: string): string {
    return `${user}/${repo}`;
  }

  private getRepoPath(user: string, repo: string): string {
    return `${process.cwd()}/repos/${user}/${repo}`;
  }

  private shouldIgnorePath(filename: string): boolean {
    return filename.includes('.jj/') || filename.includes('.git/');
  }

  private handleChange(user: string, repo: string, filename: string | null): void {
    if (filename && this.shouldIgnorePath(filename)) {
      return;
    }

    const key = this.getWatcherKey(user, repo);

    // Clear existing timer
    const existingTimer = this.debounceTimers.get(key);
    if (existingTimer) {
      clearTimeout(existingTimer);
    }

    // Set new debounced timer
    const timer = setTimeout(async () => {
      try {
        await jjSyncService.syncToDatabase(user, repo);
        this.debounceTimers.delete(key);
      } catch (error) {
        console.error(`Failed to sync ${key}:`, error);
      }
    }, this.DEBOUNCE_MS);

    this.debounceTimers.set(key, timer);
  }

  watchRepo(user: string, repo: string): void {
    const key = this.getWatcherKey(user, repo);

    // Don't create duplicate watchers
    if (this.watchers.has(key)) {
      return;
    }

    const repoPath = this.getRepoPath(user, repo);

    try {
      const watcher = watch(
        repoPath,
        { recursive: true },
        (eventType, filename) => {
          this.handleChange(user, repo, filename);
        }
      );

      this.watchers.set(key, watcher);
      console.log(`Started watching: ${key}`);
    } catch (error) {
      console.error(`Failed to watch ${key}:`, error);
    }
  }

  unwatchRepo(user: string, repo: string): void {
    const key = this.getWatcherKey(user, repo);
    const watcher = this.watchers.get(key);

    if (watcher) {
      watcher.close();
      this.watchers.delete(key);

      // Clear any pending debounce timer
      const timer = this.debounceTimers.get(key);
      if (timer) {
        clearTimeout(timer);
        this.debounceTimers.delete(key);
      }

      console.log(`Stopped watching: ${key}`);
    }
  }

  async watchAllRepos(): Promise<void> {
    try {
      // Query all repositories from database
      const repos = await sql`
        SELECT u.username as user, r.name as repo
        FROM repositories r
        JOIN users u ON r.user_id = u.id
      `;

      console.log(`Starting watchers for ${repos.length} repositories`);

      for (const { user, repo } of repos) {
        this.watchRepo(user, repo);
      }
    } catch (error) {
      console.error('Failed to watch all repos:', error);
    }
  }
}

export const repoWatcherService = new RepoWatcherService();
