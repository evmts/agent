import { DurableObject } from 'cloudflare:workers';
import { ShapeStream, isChangeMessage, isControlMessage } from '@electric-sql/client';
import type { Env, User, Repository, Issue, Comment, PullRequest, Review } from '../types';

type ChangeMessage = {
  headers: { operation: 'insert' | 'update' | 'delete' };
  key: Record<string, unknown>;
  value: Record<string, unknown>;
  offset: string;
};

export class DataSyncDO extends DurableObject<Env> {
  private sql: SqlStorage;
  private syncPromises: Map<string, Promise<void>> = new Map();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.initTables();
  }

  private initTables(): void {
    this.sql.exec(`
      -- Users table (subset of fields needed for display)
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        display_name TEXT,
        avatar_url TEXT,
        bio TEXT,
        created_at TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

      -- Repositories table
      CREATE TABLE IF NOT EXISTS repositories (
        id INTEGER PRIMARY KEY,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        is_public INTEGER DEFAULT 1,
        default_branch TEXT DEFAULT 'main',
        created_at TEXT,
        updated_at TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_repos_user ON repositories(user_id);
      CREATE INDEX IF NOT EXISTS idx_repos_public ON repositories(is_public, updated_at);

      -- Issues table
      CREATE TABLE IF NOT EXISTS issues (
        id INTEGER PRIMARY KEY,
        repository_id INTEGER NOT NULL,
        author_id INTEGER NOT NULL,
        issue_number INTEGER NOT NULL,
        title TEXT NOT NULL,
        body TEXT,
        state TEXT DEFAULT 'open',
        created_at TEXT,
        updated_at TEXT,
        closed_at TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_issues_repo ON issues(repository_id);
      CREATE INDEX IF NOT EXISTS idx_issues_state ON issues(repository_id, state);

      -- Comments table
      CREATE TABLE IF NOT EXISTS comments (
        id INTEGER PRIMARY KEY,
        issue_id INTEGER NOT NULL,
        author_id INTEGER NOT NULL,
        body TEXT NOT NULL,
        created_at TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_comments_issue ON comments(issue_id);

      -- Pull requests table
      CREATE TABLE IF NOT EXISTS pull_requests (
        id INTEGER PRIMARY KEY,
        issue_id INTEGER NOT NULL,
        head_repo_id INTEGER,
        head_branch TEXT NOT NULL,
        base_repo_id INTEGER NOT NULL,
        base_branch TEXT NOT NULL,
        status TEXT DEFAULT 'checking',
        has_merged INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_prs_base_repo ON pull_requests(base_repo_id);
      CREATE INDEX IF NOT EXISTS idx_prs_issue ON pull_requests(issue_id);

      -- Reviews table
      CREATE TABLE IF NOT EXISTS reviews (
        id INTEGER PRIMARY KEY,
        pull_request_id INTEGER NOT NULL,
        reviewer_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        content TEXT,
        created_at TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_reviews_pr ON reviews(pull_request_id);

      -- Sync metadata for Electric offset tracking
      CREATE TABLE IF NOT EXISTS shape_sync_metadata (
        shape_name TEXT PRIMARY KEY,
        shape_offset TEXT,
        shape_handle TEXT,
        last_synced_at TEXT
      );
    `);
  }

  // Start syncing a shape in the background
  async ensureSync(shapeName: string, where?: string): Promise<void> {
    const key = where ? `${shapeName}:${where}` : shapeName;

    // If already syncing, wait for it
    if (this.syncPromises.has(key)) {
      return this.syncPromises.get(key);
    }

    // Check if we have recent data (within last 5 seconds)
    const meta = this.sql
      .exec(
        `SELECT shape_offset, shape_handle, last_synced_at
         FROM shape_sync_metadata WHERE shape_name = ?`,
        key
      )
      .toArray()[0] as { shape_offset: string; shape_handle: string; last_synced_at: string } | undefined;

    if (meta?.last_synced_at) {
      const lastSync = new Date(meta.last_synced_at);
      const now = new Date();
      if (now.getTime() - lastSync.getTime() < 5000) {
        // Data is fresh enough
        return;
      }
    }

    // Start sync
    const promise = this.syncShape(key, shapeName, where, meta?.shape_offset, meta?.shape_handle);
    this.syncPromises.set(key, promise);

    try {
      await promise;
    } finally {
      this.syncPromises.delete(key);
    }
  }

  private async syncShape(
    key: string,
    table: string,
    where?: string,
    offset?: string,
    handle?: string
  ): Promise<void> {
    const params: Record<string, string> = { table };
    if (where) params.where = where;
    if (offset) params.offset = offset;
    if (handle) params.handle = handle;

    const stream = new ShapeStream({
      url: `${this.env.ELECTRIC_URL}/v1/shape`,
      params,
    });

    let lastOffset = offset;
    let lastHandle = handle;

    // Process stream until we're up to date
    for await (const messages of stream) {
      for (const message of messages) {
        if (isChangeMessage(message)) {
          const change = message as unknown as ChangeMessage;
          this.applyChange(table, change);
          lastOffset = change.offset;
        }
        if (isControlMessage(message) && message.headers?.control === 'up-to-date') {
          // We're caught up, can stop
          break;
        }
        // Capture handle from headers if present
        const headers = (message as { headers?: Record<string, string> }).headers;
        if (headers?.['electric-handle']) {
          lastHandle = headers['electric-handle'];
        }
      }
    }

    // Update sync metadata
    this.sql.exec(
      `INSERT OR REPLACE INTO shape_sync_metadata (shape_name, shape_offset, shape_handle, last_synced_at)
       VALUES (?, ?, ?, ?)`,
      key,
      lastOffset || '',
      lastHandle || '',
      new Date().toISOString()
    );
  }

  private applyChange(table: string, message: ChangeMessage): void {
    const { headers, key, value } = message;
    const id = key.id as number;

    if (headers.operation === 'delete') {
      this.sql.exec(`DELETE FROM ${table} WHERE id = ?`, id);
      return;
    }

    // Map PostgreSQL column names to SQLite (snake_case)
    const columnMap: Record<string, string> = {
      displayName: 'display_name',
      avatarUrl: 'avatar_url',
      userId: 'user_id',
      isPublic: 'is_public',
      defaultBranch: 'default_branch',
      createdAt: 'created_at',
      updatedAt: 'updated_at',
      repositoryId: 'repository_id',
      authorId: 'author_id',
      issueNumber: 'issue_number',
      closedAt: 'closed_at',
      issueId: 'issue_id',
      headRepoId: 'head_repo_id',
      headBranch: 'head_branch',
      baseRepoId: 'base_repo_id',
      baseBranch: 'base_branch',
      hasMerged: 'has_merged',
      pullRequestId: 'pull_request_id',
      reviewerId: 'reviewer_id',
    };

    const columns: string[] = [];
    const values: unknown[] = [];

    for (const [k, v] of Object.entries(value)) {
      const col = columnMap[k] || k;
      columns.push(col);
      // Convert boolean to integer for SQLite
      if (typeof v === 'boolean') {
        values.push(v ? 1 : 0);
      } else {
        values.push(v);
      }
    }

    const placeholders = columns.map(() => '?').join(', ');
    const updateClauses = columns.map((col) => `${col} = excluded.${col}`).join(', ');

    this.sql.exec(
      `INSERT INTO ${table} (${columns.join(', ')}) VALUES (${placeholders})
       ON CONFLICT(id) DO UPDATE SET ${updateClauses}`,
      ...values
    );
  }

  // Query methods for pages

  async getPublicRepositories(limit = 50): Promise<(Repository & { username: string })[]> {
    await this.ensureSync('repositories', 'is_public = true');
    await this.ensureSync('users');

    return this.sql
      .exec(
        `SELECT r.*, u.username
         FROM repositories r
         JOIN users u ON r.user_id = u.id
         WHERE r.is_public = 1
         ORDER BY r.updated_at DESC
         LIMIT ?`,
        limit
      )
      .toArray() as (Repository & { username: string })[];
  }

  async getUser(username: string): Promise<User | null> {
    await this.ensureSync('users');

    const results = this.sql
      .exec(`SELECT * FROM users WHERE username = ?`, username)
      .toArray() as User[];
    return results[0] || null;
  }

  async getUserRepositories(userId: number): Promise<Repository[]> {
    await this.ensureSync('repositories');

    return this.sql
      .exec(
        `SELECT * FROM repositories WHERE user_id = ? ORDER BY updated_at DESC`,
        userId
      )
      .toArray() as Repository[];
  }

  async getRepository(userId: number, name: string): Promise<Repository | null> {
    await this.ensureSync('repositories');

    const results = this.sql
      .exec(`SELECT * FROM repositories WHERE user_id = ? AND name = ?`, userId, name)
      .toArray() as Repository[];
    return results[0] || null;
  }

  async getRepoByOwnerAndName(owner: string, name: string): Promise<(Repository & { username: string }) | null> {
    await this.ensureSync('users');
    await this.ensureSync('repositories');

    const results = this.sql
      .exec(
        `SELECT r.*, u.username
         FROM repositories r
         JOIN users u ON r.user_id = u.id
         WHERE u.username = ? AND r.name = ?`,
        owner,
        name
      )
      .toArray() as (Repository & { username: string })[];
    return results[0] || null;
  }

  async getIssues(
    repositoryId: number,
    state?: 'open' | 'closed' | 'all'
  ): Promise<(Issue & { authorUsername: string })[]> {
    await this.ensureSync('issues', `repository_id = ${repositoryId}`);
    await this.ensureSync('users');

    let query = `
      SELECT i.*, u.username as authorUsername
      FROM issues i
      JOIN users u ON i.author_id = u.id
      WHERE i.repository_id = ?
    `;

    if (state && state !== 'all') {
      query += ` AND i.state = '${state}'`;
    }

    query += ' ORDER BY i.created_at DESC';

    return this.sql.exec(query, repositoryId).toArray() as (Issue & { authorUsername: string })[];
  }

  async getIssue(
    repositoryId: number,
    issueNumber: number
  ): Promise<(Issue & { authorUsername: string }) | null> {
    await this.ensureSync('issues', `repository_id = ${repositoryId}`);
    await this.ensureSync('users');

    const results = this.sql
      .exec(
        `SELECT i.*, u.username as authorUsername
         FROM issues i
         JOIN users u ON i.author_id = u.id
         WHERE i.repository_id = ? AND i.issue_number = ?`,
        repositoryId,
        issueNumber
      )
      .toArray() as (Issue & { authorUsername: string })[];
    return results[0] || null;
  }

  async getIssueComments(issueId: number): Promise<(Comment & { authorUsername: string })[]> {
    await this.ensureSync('comments', `issue_id = ${issueId}`);
    await this.ensureSync('users');

    return this.sql
      .exec(
        `SELECT c.*, u.username as authorUsername
         FROM comments c
         JOIN users u ON c.author_id = u.id
         WHERE c.issue_id = ?
         ORDER BY c.created_at ASC`,
        issueId
      )
      .toArray() as (Comment & { authorUsername: string })[];
  }

  async getIssueCounts(repositoryId: number): Promise<{ open: number; closed: number }> {
    await this.ensureSync('issues', `repository_id = ${repositoryId}`);

    const results = this.sql
      .exec(
        `SELECT state, COUNT(*) as count FROM issues WHERE repository_id = ? GROUP BY state`,
        repositoryId
      )
      .toArray() as { state: string; count: number }[];

    const counts = { open: 0, closed: 0 };
    for (const row of results) {
      if (row.state === 'open') counts.open = row.count;
      if (row.state === 'closed') counts.closed = row.count;
    }
    return counts;
  }

  async getPullRequests(
    repositoryId: number,
    state?: 'open' | 'merged' | 'all'
  ): Promise<(PullRequest & { title: string; authorUsername: string; issueNumber: number })[]> {
    await this.ensureSync('pull_requests', `base_repo_id = ${repositoryId}`);
    await this.ensureSync('issues', `repository_id = ${repositoryId}`);
    await this.ensureSync('users');

    let query = `
      SELECT pr.*, i.title, i.issue_number as issueNumber, u.username as authorUsername
      FROM pull_requests pr
      JOIN issues i ON pr.issue_id = i.id
      JOIN users u ON i.author_id = u.id
      WHERE pr.base_repo_id = ?
    `;

    if (state === 'open') {
      query += ` AND pr.has_merged = 0 AND i.state = 'open'`;
    } else if (state === 'merged') {
      query += ` AND pr.has_merged = 1`;
    }

    query += ' ORDER BY pr.created_at DESC';

    return this.sql.exec(query, repositoryId).toArray() as (PullRequest & {
      title: string;
      authorUsername: string;
      issueNumber: number;
    })[];
  }

  async getPullRequest(
    repositoryId: number,
    prNumber: number
  ): Promise<(PullRequest & { title: string; body: string; authorUsername: string; issueNumber: number }) | null> {
    await this.ensureSync('pull_requests', `base_repo_id = ${repositoryId}`);
    await this.ensureSync('issues', `repository_id = ${repositoryId}`);
    await this.ensureSync('users');

    const results = this.sql
      .exec(
        `SELECT pr.*, i.title, i.body, i.issue_number as issueNumber, u.username as authorUsername
         FROM pull_requests pr
         JOIN issues i ON pr.issue_id = i.id
         JOIN users u ON i.author_id = u.id
         WHERE pr.base_repo_id = ? AND i.issue_number = ?`,
        repositoryId,
        prNumber
      )
      .toArray() as (PullRequest & {
      title: string;
      body: string;
      authorUsername: string;
      issueNumber: number;
    })[];
    return results[0] || null;
  }

  async getPullRequestReviews(prId: number): Promise<(Review & { reviewerUsername: string })[]> {
    await this.ensureSync('reviews', `pull_request_id = ${prId}`);
    await this.ensureSync('users');

    return this.sql
      .exec(
        `SELECT r.*, u.username as reviewerUsername
         FROM reviews r
         JOIN users u ON r.reviewer_id = u.id
         WHERE r.pull_request_id = ?
         ORDER BY r.created_at ASC`,
        prId
      )
      .toArray() as (Review & { reviewerUsername: string })[];
  }

  async getPullRequestCounts(
    repositoryId: number
  ): Promise<{ open: number; merged: number }> {
    await this.ensureSync('pull_requests', `base_repo_id = ${repositoryId}`);
    await this.ensureSync('issues', `repository_id = ${repositoryId}`);

    const open = this.sql
      .exec(
        `SELECT COUNT(*) as count FROM pull_requests pr
         JOIN issues i ON pr.issue_id = i.id
         WHERE pr.base_repo_id = ? AND pr.has_merged = 0 AND i.state = 'open'`,
        repositoryId
      )
      .toArray()[0] as { count: number };

    const merged = this.sql
      .exec(
        `SELECT COUNT(*) as count FROM pull_requests WHERE base_repo_id = ? AND has_merged = 1`,
        repositoryId
      )
      .toArray()[0] as { count: number };

    return { open: open?.count || 0, merged: merged?.count || 0 };
  }

  // Fetch handler for the DO
  async fetch(request: Request): Promise<Response> {
    // This DO is primarily used via RPC methods, not HTTP
    // But we can expose a health endpoint
    const url = new URL(request.url);
    if (url.pathname === '/health') {
      return new Response('OK');
    }
    return new Response('Not found', { status: 404 });
  }
}
