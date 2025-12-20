import { DurableObject } from 'cloudflare:workers';
import { ShapeStream, isChangeMessage, isControlMessage } from '@electric-sql/client';
import type { Env, User, Repository, Issue, Comment, PullRequest, Review, InvalidationMessage } from '../types';

type ChangeMessage = {
  headers: { operation: 'insert' | 'update' | 'delete' };
  key: Record<string, unknown>;
  value: Record<string, unknown>;
  offset: string;
};

/**
 * Durable Object providing edge-cached data synchronization with push-based invalidation.
 *
 * This DO maintains a SQLite-backed cache of:
 * - PostgreSQL data synced via Electric SQL shapes (users, repos, issues, PRs)
 * - Git repository data (trees, file contents) validated by merkle roots
 *
 * Cache Invalidation Strategy:
 * - Push mode (ENABLE_PUSH_INVALIDATION=true): K8s sends invalidation messages via
 *   /invalidate endpoint when data changes. Cached data is trusted until invalidated.
 * - TTL mode (default): 5-second cache TTL with polling Electric SQL for updates.
 *
 * Git Cache Validation:
 * - Each repo/ref has a merkle root hash stored in the DO
 * - Cached trees and files include the merkle root they were fetched under
 * - On cache hit, merkle root is compared; mismatch triggers refetch from origin
 * - K8s pushes new merkle roots when commits are pushed to the repository
 *
 * @see InvalidationMessage for the invalidation message format
 */
export class DataSyncDO extends DurableObject<Env> {
  private sql: SqlStorage;
  private syncPromises: Map<string, Promise<void>> = new Map();

  /**
   * Feature flag controlling cache invalidation mode.
   * When true, uses push-based invalidation from K8s.
   * When false, uses 5-second TTL polling.
   */
  private enablePushInvalidation: boolean;

  /**
   * Maximum total size of file content cache in bytes (50MB).
   * Uses LRU eviction when this limit is exceeded.
   */
  private readonly MAX_FILE_CACHE_SIZE = 50 * 1024 * 1024; // 50MB

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.enablePushInvalidation = this.env.ENABLE_PUSH_INVALIDATION === 'true';
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

      -- Git tree cache with merkle validation
      CREATE TABLE IF NOT EXISTS git_trees (
        cache_key TEXT PRIMARY KEY,
        merkle_root TEXT NOT NULL,
        tree_data TEXT NOT NULL,
        cached_at TEXT NOT NULL
      );

      -- LRU file content cache
      CREATE TABLE IF NOT EXISTS git_files (
        cache_key TEXT PRIMARY KEY,
        merkle_root TEXT NOT NULL,
        content TEXT NOT NULL,
        size INTEGER NOT NULL,
        accessed_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_git_files_accessed ON git_files(accessed_at);

      -- Current merkle roots per repo/ref
      CREATE TABLE IF NOT EXISTS merkle_roots (
        repo_ref TEXT PRIMARY KEY,
        root_hash TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    `);
  }

  /**
   * Ensures an Electric SQL shape is synced to the local cache.
   *
   * In push invalidation mode (ENABLE_PUSH_INVALIDATION=true):
   * - If cached data exists, returns immediately (trusts cache until invalidated)
   * - Only syncs if no cache exists or shape metadata was deleted by invalidation
   *
   * In TTL mode (default):
   * - Uses 5-second TTL on cached data
   * - Syncs if cache is older than 5 seconds or doesn't exist
   *
   * Multiple concurrent calls for the same shape will wait on a single sync promise.
   *
   * @param shapeName - Electric SQL table name (e.g., 'users', 'repositories')
   * @param where - Optional WHERE clause to filter the shape (e.g., 'is_public = true')
   * @returns Promise that resolves when shape is synced
   *
   * @example
   * // Sync all public repositories
   * await ensureSync('repositories', 'is_public = true');
   *
   * @example
   * // Sync all users (no filter)
   * await ensureSync('users');
   */
  async ensureSync(shapeName: string, where?: string): Promise<void> {
    const key = where ? `${shapeName}:${where}` : shapeName;

    // If already syncing, wait for it
    if (this.syncPromises.has(key)) {
      return this.syncPromises.get(key);
    }

    // Check if we have cached data
    const meta = this.sql
      .exec(
        `SELECT shape_offset, shape_handle, last_synced_at
         FROM shape_sync_metadata WHERE shape_name = ?`,
        key
      )
      .toArray()[0] as { shape_offset: string; shape_handle: string; last_synced_at: string } | undefined;

    if (meta?.shape_offset) {
      // If push invalidation is enabled, trust cached data
      if (this.enablePushInvalidation) {
        return;
      }

      // Fallback: 5-second TTL for backward compatibility
      if (meta.last_synced_at) {
        const lastSync = new Date(meta.last_synced_at);
        const now = new Date();
        if (now.getTime() - lastSync.getTime() < 5000) {
          return;
        }
      }
    }

    // No cached data or stale - start sync
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

  // Git cache methods with merkle root validation

  /**
   * Handles git cache invalidation by updating the merkle root.
   *
   * When K8s detects a repository change (push, commit), it sends an invalidation
   * message with the new merkle root hash. This method updates the stored merkle
   * root, which automatically invalidates all cached tree and file data associated
   * with the old root.
   *
   * Cached entries are not deleted immediately; they fail merkle validation on next
   * access and are refreshed lazily from origin.
   *
   * @param msg - Invalidation message containing repoKey and merkleRoot
   * @returns Promise that resolves when merkle root is updated
   *
   * @example
   * // Called via /invalidate endpoint after git push
   * await handleGitInvalidation({
   *   type: 'git',
   *   repoKey: 'torvalds/linux',
   *   merkleRoot: 'a1b2c3d4e5f6...',
   *   timestamp: Date.now()
   * });
   */
  async handleGitInvalidation(msg: InvalidationMessage): Promise<void> {
    if (!msg.repoKey || !msg.merkleRoot) {
      console.warn('Git invalidation missing repoKey or merkleRoot');
      return;
    }

    // Default to 'main' ref for now, can be extended to support specific refs
    const repoRef = `${msg.repoKey}:main`;

    // Update merkle root - this automatically invalidates old cached data
    // since cache lookups compare against current merkle root
    this.sql.exec(
      `INSERT OR REPLACE INTO merkle_roots (repo_ref, root_hash, updated_at)
       VALUES (?, ?, ?)`,
      repoRef, msg.merkleRoot, new Date().toISOString()
    );

    console.log(`Updated merkle root for ${repoRef}: ${msg.merkleRoot.substring(0, 8)}...`);
  }

  /**
   * Retrieves cached git tree data with merkle root validation.
   *
   * Returns cached directory listing if:
   * 1. A merkle root exists for this repo/ref
   * 2. Cached data exists for this path
   * 3. The cached data's merkle root matches the current merkle root
   *
   * Returns null if any validation fails, triggering a refetch from origin.
   *
   * @param owner - Repository owner username
   * @param repo - Repository name
   * @param ref - Git ref (branch, tag, or commit SHA)
   * @param path - Directory path within the repository
   * @returns Cached tree data array or null if cache miss/stale
   *
   * @example
   * const tree = await getTreeData('torvalds', 'linux', 'main', 'drivers/usb');
   * if (!tree) {
   *   // Cache miss - fetch from origin
   * }
   */
  async getTreeData(owner: string, repo: string, ref: string, path: string): Promise<unknown[] | null> {
    const repoRef = `${owner}/${repo}:${ref}`;
    const cacheKey = `${repoRef}:${path}`;

    // Get current merkle root
    const rootRow = this.sql.exec(
      'SELECT root_hash FROM merkle_roots WHERE repo_ref = ?',
      repoRef
    ).toArray()[0] as { root_hash: string } | undefined;

    if (!rootRow) {
      // No merkle root known - can't validate cache, return null
      return null;
    }

    // Check cache
    const cached = this.sql.exec(
      'SELECT tree_data, merkle_root FROM git_trees WHERE cache_key = ?',
      cacheKey
    ).toArray()[0] as { tree_data: string; merkle_root: string } | undefined;

    if (cached && cached.merkle_root === rootRow.root_hash) {
      // Cache hit - merkle root matches
      return JSON.parse(cached.tree_data);
    }

    // Cache miss or stale
    return null;
  }

  /**
   * Caches git tree data with the current merkle root.
   *
   * Stores directory listing data tagged with the current merkle root hash.
   * Will not cache if no merkle root exists for the repo/ref (safety check).
   *
   * Cached data will be validated against the merkle root on future reads via
   * getTreeData(). If the merkle root changes, cached data becomes stale.
   *
   * @param owner - Repository owner username
   * @param repo - Repository name
   * @param ref - Git ref (branch, tag, or commit SHA)
   * @param path - Directory path within the repository
   * @param data - Tree data array to cache (typically from origin)
   * @returns Promise that resolves when data is cached
   *
   * @example
   * // After fetching from origin
   * const treeData = await fetchTreeFromOrigin(owner, repo, ref, path);
   * await cacheTreeData(owner, repo, ref, path, treeData);
   */
  async cacheTreeData(owner: string, repo: string, ref: string, path: string, data: unknown[]): Promise<void> {
    const repoRef = `${owner}/${repo}:${ref}`;
    const cacheKey = `${repoRef}:${path}`;

    // Get current merkle root
    const rootRow = this.sql.exec(
      'SELECT root_hash FROM merkle_roots WHERE repo_ref = ?',
      repoRef
    ).toArray()[0] as { root_hash: string } | undefined;

    if (!rootRow) {
      // No merkle root - don't cache without validation reference
      return;
    }

    this.sql.exec(
      `INSERT OR REPLACE INTO git_trees (cache_key, merkle_root, tree_data, cached_at)
       VALUES (?, ?, ?, ?)`,
      cacheKey, rootRow.root_hash, JSON.stringify(data), new Date().toISOString()
    );
  }

  /**
   * Retrieves cached file content with merkle root validation and LRU tracking.
   *
   * Returns cached file content if:
   * 1. A merkle root exists for this repo/ref
   * 2. Cached content exists for this file path
   * 3. The cached content's merkle root matches the current merkle root
   *
   * On cache hit, updates the accessed_at timestamp for LRU eviction.
   * Returns null if any validation fails, triggering a refetch from origin.
   *
   * @param owner - Repository owner username
   * @param repo - Repository name
   * @param ref - Git ref (branch, tag, or commit SHA)
   * @param path - File path within the repository
   * @returns Cached file content or null if cache miss/stale
   *
   * @example
   * const content = await getFileContent('torvalds', 'linux', 'main', 'README.md');
   * if (!content) {
   *   // Cache miss - fetch from origin
   * }
   */
  async getFileContent(owner: string, repo: string, ref: string, path: string): Promise<string | null> {
    const repoRef = `${owner}/${repo}:${ref}`;
    const cacheKey = `${repoRef}:${path}`;

    // Get current merkle root
    const rootRow = this.sql.exec(
      'SELECT root_hash FROM merkle_roots WHERE repo_ref = ?',
      repoRef
    ).toArray()[0] as { root_hash: string } | undefined;

    if (!rootRow) {
      return null;
    }

    // Check cache
    const cached = this.sql.exec(
      'SELECT content, merkle_root FROM git_files WHERE cache_key = ?',
      cacheKey
    ).toArray()[0] as { content: string; merkle_root: string } | undefined;

    if (cached && cached.merkle_root === rootRow.root_hash) {
      // Update accessed_at for LRU
      this.sql.exec(
        'UPDATE git_files SET accessed_at = ? WHERE cache_key = ?',
        new Date().toISOString(), cacheKey
      );
      return cached.content;
    }

    return null;
  }

  /**
   * Caches file content with the current merkle root, enforcing LRU size limits.
   *
   * Stores file content tagged with the current merkle root hash. Before caching,
   * checks if the total cache size would exceed MAX_FILE_CACHE_SIZE (50MB) and
   * evicts least-recently-accessed files if needed.
   *
   * Will not cache if no merkle root exists for the repo/ref (safety check).
   *
   * @param owner - Repository owner username
   * @param repo - Repository name
   * @param ref - Git ref (branch, tag, or commit SHA)
   * @param path - File path within the repository
   * @param content - File content string to cache (typically from origin)
   * @returns Promise that resolves when content is cached
   *
   * @example
   * // After fetching from origin
   * const fileContent = await fetchFileFromOrigin(owner, repo, ref, path);
   * await cacheFileContent(owner, repo, ref, path, fileContent);
   */
  async cacheFileContent(owner: string, repo: string, ref: string, path: string, content: string): Promise<void> {
    const repoRef = `${owner}/${repo}:${ref}`;
    const cacheKey = `${repoRef}:${path}`;
    const size = new TextEncoder().encode(content).length;

    // Get current merkle root
    const rootRow = this.sql.exec(
      'SELECT root_hash FROM merkle_roots WHERE repo_ref = ?',
      repoRef
    ).toArray()[0] as { root_hash: string } | undefined;

    if (!rootRow) {
      return;
    }

    // Evict old entries if needed
    await this.evictFileCacheIfNeeded(size);

    this.sql.exec(
      `INSERT OR REPLACE INTO git_files (cache_key, merkle_root, content, size, accessed_at)
       VALUES (?, ?, ?, ?, ?)`,
      cacheKey, rootRow.root_hash, content, size, new Date().toISOString()
    );
  }

  /**
   * Evicts least-recently-accessed files from cache to free up space.
   *
   * Uses LRU (Least Recently Used) eviction strategy based on accessed_at timestamps.
   * Deletes files in batches of 100 until there is enough space for neededSize.
   *
   * Safety Features:
   * - Checks current size before each iteration
   * - Breaks if no files were deleted (prevents infinite loop)
   * - Batch deletion reduces transaction overhead
   *
   * @param neededSize - Bytes needed for the new cache entry
   * @returns Promise that resolves when enough space is freed
   *
   * @example
   * // Before caching a 10MB file
   * await evictFileCacheIfNeeded(10 * 1024 * 1024);
   */
  private async evictFileCacheIfNeeded(neededSize: number): Promise<void> {
    const total = this.sql.exec('SELECT COALESCE(SUM(size), 0) as total FROM git_files').toArray()[0] as { total: number };

    if (total.total + neededSize <= this.MAX_FILE_CACHE_SIZE) {
      return;
    }

    // Delete oldest accessed files until we have space
    // Delete in batches of 100 to avoid long transactions
    while (true) {
      const currentTotal = this.sql.exec('SELECT COALESCE(SUM(size), 0) as total FROM git_files').toArray()[0] as { total: number };

      if (currentTotal.total + neededSize <= this.MAX_FILE_CACHE_SIZE) {
        break;
      }

      this.sql.exec(`
        DELETE FROM git_files WHERE cache_key IN (
          SELECT cache_key FROM git_files ORDER BY accessed_at ASC LIMIT 100
        )
      `);

      // Safety: if nothing was deleted but we still need space, break to prevent infinite loop
      const changes = this.sql.exec('SELECT changes() as c').toArray()[0] as { c: number } | undefined;
      if (!changes || changes.c === 0) {
        break;
      }
    }
  }

  /**
   * HTTP request handler for the Durable Object.
   *
   * Endpoints:
   * - GET /health - Health check endpoint (returns "OK")
   * - POST /invalidate - Receives cache invalidation messages from K8s
   *
   * /invalidate Endpoint:
   * - Requires Authorization: Bearer <PUSH_SECRET> header
   * - Accepts InvalidationMessage JSON payload
   * - SQL invalidations: Deletes shape sync metadata to force resync
   * - Git invalidations: Updates merkle root to invalidate cached trees/files
   *
   * @param request - Incoming HTTP request
   * @returns HTTP response
   *
   * @example
   * // K8s sends git invalidation
   * POST /invalidate
   * Authorization: Bearer <PUSH_SECRET>
   * {
   *   "type": "git",
   *   "repoKey": "torvalds/linux",
   *   "merkleRoot": "abc123...",
   *   "timestamp": 1234567890
   * }
   *
   * @example
   * // K8s sends SQL invalidation
   * POST /invalidate
   * Authorization: Bearer <PUSH_SECRET>
   * {
   *   "type": "sql",
   *   "table": "issues",
   *   "timestamp": 1234567890
   * }
   */
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/health') {
      return new Response('OK');
    }

    if (url.pathname === '/invalidate' && request.method === 'POST') {
      // Verify shared secret
      const auth = request.headers.get('Authorization');
      if (auth !== `Bearer ${this.env.PUSH_SECRET}`) {
        return new Response('Unauthorized', { status: 401 });
      }

      try {
        const msg: InvalidationMessage = await request.json();

        if (msg.type === 'sql') {
          // Clear shape metadata to force resync
          this.sql.exec(
            'DELETE FROM shape_sync_metadata WHERE shape_name LIKE ?',
            `${msg.table}%`
          );
        } else if (msg.type === 'git') {
          await this.handleGitInvalidation(msg);
        }

        return new Response(JSON.stringify({ ok: true }), {
          headers: { 'Content-Type': 'application/json' }
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: 'Invalid request' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    return new Response('Not found', { status: 404 });
  }
}
