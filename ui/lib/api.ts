/**
 * API Client for Plue Zig Server
 *
 * Provides typed fetch wrappers for all API endpoints.
 * Used by Astro pages instead of direct database queries.
 */

// API base URL - check runtime env first (for SSR in Docker), then build-time env
const API_URL = (typeof process !== 'undefined' && process.env.PUBLIC_API_URL)
  || import.meta.env.PUBLIC_API_URL
  || 'http://localhost:4000';

// =============================================================================
// Types
// =============================================================================

export interface Repository {
  id: number;
  name: string;
  owner: string;
  description: string | null;
  isPrivate: boolean;
  defaultBranch: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface RepositoryStats {
  issueCount: number;
  starCount: number;
  landingCount: number;
  watcherCount: number;
}

export interface User {
  id: number;
  username: string;
  displayName: string | null;
  avatarUrl: string | null;
  bio?: string | null;
  repositoryCount?: number;
  createdAt?: string;
}

export interface Topic {
  topic: string;
  count: number;
}

export interface Stargazer {
  id: number;
  username: string;
  displayName: string | null;
  createdAt: string;
}

export interface Watcher {
  id: number;
  username: string;
  displayName: string | null;
  watchLevel: string;
  createdAt: string;
}

export interface Milestone {
  id: number;
  title: string;
  description: string | null;
  dueDate: string | null;
  state: string;
  openIssueCount: number;
  closedIssueCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface Issue {
  id: number;
  number: number;
  title: string;
  body: string | null;
  state: string;
  author: {
    id: number;
    username: string;
  };
  assignees: Array<{
    id: number;
    username: string;
  }>;
  labels: string[];
  milestone: string | null;
  dueDate: string | null;
  isPinned: boolean;
  createdAt: string;
  updatedAt: string;
  closedAt: string | null;
  reactions: Array<{
    emoji: string;
    count: number;
  }>;
}

export interface IssueComment {
  id: number;
  body: string;
  author: {
    id: number;
    username: string;
  };
  createdAt: string;
  updatedAt: string | null;
}

export interface IssueEvent {
  type: string;
  actor: {
    id: number;
    username: string;
  };
  createdAt: string;
  data: Record<string, unknown>;
}

export interface Label {
  name: string;
  color: string;
  description: string | null;
}

export interface Bookmark {
  id: number;
  name: string;
  targetChangeId: string;
  isDefault: boolean;
}

// =============================================================================
// Error Handling
// =============================================================================

export class ApiError extends Error {
  status: number;

  constructor(status: number, message?: string) {
    super(message || `API Error: ${status}`);
    this.status = status;
    this.name = 'ApiError';
  }
}

async function handleResponse<T>(res: Response): Promise<T> {
  if (!res.ok) {
    let message: string | undefined;
    try {
      const body = await res.json();
      message = body.error;
    } catch {
      // Ignore JSON parse errors
    }
    throw new ApiError(res.status, message);
  }
  return res.json();
}

// =============================================================================
// Repository Endpoints
// =============================================================================

export interface ListReposOptions {
  limit?: number;
  offset?: number;
  sort?: 'name' | 'updated_at' | 'created_at';
}

export interface ReposResponse {
  repositories: Repository[];
  total: number;
  limit: number;
  offset: number;
}

/**
 * List public repositories
 */
export async function listRepos(options: ListReposOptions = {}): Promise<ReposResponse> {
  const params = new URLSearchParams();
  if (options.limit) params.set('limit', String(options.limit));
  if (options.offset) params.set('offset', String(options.offset));
  if (options.sort) params.set('sort', options.sort);

  const res = await fetch(`${API_URL}/api/repos?${params}`);
  return handleResponse(res);
}

/**
 * Create a new repository
 * Requires authentication and repo:write scope
 */
export async function createRepository(
  data: { name: string; description?: string },
  headers?: HeadersInit
): Promise<{ repository: Repository }> {
  const res = await fetch(`${API_URL}/api/repos`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
    body: JSON.stringify(data),
  });
  return handleResponse(res);
}

/**
 * Search public repositories
 */
export async function searchRepos(query: string, options: ListReposOptions = {}): Promise<{ repositories: Repository[]; count: number }> {
  const params = new URLSearchParams({ q: query });
  if (options.limit) params.set('limit', String(options.limit));
  if (options.offset) params.set('offset', String(options.offset));

  const res = await fetch(`${API_URL}/api/repos/search?${params}`);
  return handleResponse(res);
}

/**
 * Get popular topics
 */
export async function getPopularTopics(limit = 10): Promise<{ topics: Topic[] }> {
  const res = await fetch(`${API_URL}/api/repos/topics/popular?limit=${limit}`);
  return handleResponse(res);
}

/**
 * Get repositories by topic
 */
export async function getReposByTopic(topic: string, options: ListReposOptions = {}): Promise<{ topic: string; repositories: Repository[]; count: number }> {
  const params = new URLSearchParams();
  if (options.limit) params.set('limit', String(options.limit));
  if (options.offset) params.set('offset', String(options.offset));

  const res = await fetch(`${API_URL}/api/repos/topics/${encodeURIComponent(topic)}?${params}`);
  return handleResponse(res);
}

/**
 * Get repository stats
 */
export async function getRepoStats(owner: string, repo: string): Promise<RepositoryStats> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/stats`);
  return handleResponse(res);
}

/**
 * Get repository stargazers
 */
export async function getStargazers(owner: string, repo: string): Promise<{ stargazers: Stargazer[]; total: number }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/stargazers`);
  return handleResponse(res);
}

/**
 * Get repository watchers
 */
export async function getWatchers(owner: string, repo: string): Promise<{ watchers: Watcher[]; total: number }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/watchers`);
  return handleResponse(res);
}

/**
 * Get repository bookmarks
 */
export async function getBookmarks(owner: string, repo: string): Promise<{ bookmarks: Bookmark[]; total: number }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/bookmarks`);
  return handleResponse(res);
}

// =============================================================================
// User Endpoints
// =============================================================================

export interface ListUsersOptions {
  limit?: number;
  offset?: number;
}

export interface UsersResponse {
  users: User[];
  total: number;
  limit: number;
  offset: number;
}

/**
 * List all users
 */
export async function listUsers(options: ListUsersOptions = {}): Promise<UsersResponse> {
  const params = new URLSearchParams();
  if (options.limit) params.set('limit', String(options.limit));
  if (options.offset) params.set('offset', String(options.offset));

  const res = await fetch(`${API_URL}/api/users?${params}`);
  return handleResponse(res);
}

/**
 * Search users
 */
export async function searchUsers(query: string): Promise<{ users: User[] }> {
  const res = await fetch(`${API_URL}/api/users/search?q=${encodeURIComponent(query)}`);
  return handleResponse(res);
}

/**
 * Get user profile
 */
export async function getUser(username: string): Promise<User> {
  const res = await fetch(`${API_URL}/api/users/${encodeURIComponent(username)}`);
  return handleResponse(res);
}

/**
 * Get user's repositories
 */
export async function getUserRepos(username: string, options: { limit?: number } = {}, headers?: HeadersInit): Promise<{ owner: string; repositories: Repository[]; count: number }> {
  const params = new URLSearchParams();
  if (options.limit) params.set('limit', String(options.limit));

  const res = await fetch(`${API_URL}/api/users/${encodeURIComponent(username)}/repos?${params}`, { headers });
  return handleResponse(res);
}

/**
 * Get repositories starred by user
 */
export async function getUserStarredRepos(username: string, options: ListUsersOptions = {}): Promise<{ user: string; repositories: (Repository & { starredAt: string })[]; total: number }> {
  const params = new URLSearchParams();
  if (options.limit) params.set('limit', String(options.limit));
  if (options.offset) params.set('offset', String(options.offset));

  const res = await fetch(`${API_URL}/api/users/${encodeURIComponent(username)}/starred?${params}`);
  return handleResponse(res);
}

// =============================================================================
// Milestone Endpoints
// =============================================================================

/**
 * List milestones for a repository
 */
export async function getMilestones(owner: string, repo: string, state?: 'open' | 'closed'): Promise<{ milestones: Milestone[]; total: number }> {
  const params = new URLSearchParams();
  if (state) params.set('state', state);

  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/milestones?${params}`);
  return handleResponse(res);
}

/**
 * Get a single milestone
 */
export async function getMilestone(owner: string, repo: string, id: number): Promise<{ milestone: Milestone }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/milestones/${id}`);
  return handleResponse(res);
}

/**
 * Create a new milestone
 */
export async function createMilestone(owner: string, repo: string, data: { title: string; description?: string; dueDate?: string }, headers?: HeadersInit): Promise<{ milestone: Milestone }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/milestones`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(data),
  });
  return handleResponse(res);
}

/**
 * Update a milestone
 */
export async function updateMilestone(owner: string, repo: string, id: number, data: { title?: string; description?: string | null; dueDate?: string | null; state?: string }, headers?: HeadersInit): Promise<{ milestone: Milestone }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/milestones/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(data),
  });
  return handleResponse(res);
}

/**
 * Delete a milestone
 */
export async function deleteMilestone(owner: string, repo: string, id: number, headers?: HeadersInit): Promise<void> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/milestones/${id}`, {
    method: 'DELETE',
    headers,
  });
  if (!res.ok) {
    throw new ApiError(res.status);
  }
}

// =============================================================================
// Issue Endpoints
// =============================================================================

/**
 * List issues for a repository
 */
export async function getIssues(owner: string, repo: string, state?: 'open' | 'closed' | 'all'): Promise<{ issues: Issue[]; counts: { open: number; closed: number } }> {
  const params = new URLSearchParams();
  if (state) params.set('state', state);

  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues?${params}`);
  return handleResponse(res);
}

/**
 * Get a single issue
 */
export async function getIssue(owner: string, repo: string, number: number): Promise<{ issue: Issue }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${number}`);
  return handleResponse(res);
}

/**
 * Create a new issue
 */
export async function createIssue(owner: string, repo: string, data: { title: string; body?: string; authorId: number }, headers?: HeadersInit): Promise<{ issue: Issue }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(data),
  });
  return handleResponse(res);
}

/**
 * Update an issue
 */
export async function updateIssue(owner: string, repo: string, number: number, data: { title?: string; body?: string }, headers?: HeadersInit): Promise<{ issue: Issue }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${number}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(data),
  });
  return handleResponse(res);
}

/**
 * Close an issue
 */
export async function closeIssue(owner: string, repo: string, number: number, headers?: HeadersInit): Promise<void> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${number}/close`, {
    method: 'POST',
    headers,
  });
  if (!res.ok) {
    throw new ApiError(res.status);
  }
}

/**
 * Reopen an issue
 */
export async function reopenIssue(owner: string, repo: string, number: number, headers?: HeadersInit): Promise<void> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${number}/reopen`, {
    method: 'POST',
    headers,
  });
  if (!res.ok) {
    throw new ApiError(res.status);
  }
}

/**
 * Pin an issue
 */
export async function pinIssue(owner: string, repo: string, number: number, headers?: HeadersInit): Promise<void> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${number}/pin`, {
    method: 'POST',
    headers,
  });
  if (!res.ok) {
    throw new ApiError(res.status);
  }
}

/**
 * Unpin an issue
 */
export async function unpinIssue(owner: string, repo: string, number: number, headers?: HeadersInit): Promise<void> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${number}/unpin`, {
    method: 'POST',
    headers,
  });
  if (!res.ok) {
    throw new ApiError(res.status);
  }
}

/**
 * Get comments for an issue
 */
export async function getIssueComments(owner: string, repo: string, number: number): Promise<{ comments: IssueComment[] }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${number}/comments`);
  return handleResponse(res);
}

/**
 * Add a comment to an issue
 */
export async function addIssueComment(owner: string, repo: string, number: number, data: { body: string; authorId: number }, headers?: HeadersInit): Promise<{ comment: IssueComment }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${number}/comments`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(data),
  });
  return handleResponse(res);
}

/**
 * Update a comment
 */
export async function updateIssueComment(owner: string, repo: string, number: number, commentId: number, data: { body: string }, headers?: HeadersInit): Promise<{ comment: IssueComment }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${number}/comments/${commentId}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(data),
  });
  return handleResponse(res);
}

/**
 * Delete a comment
 */
export async function deleteIssueComment(owner: string, repo: string, number: number, commentId: number, headers?: HeadersInit): Promise<void> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${number}/comments/${commentId}`, {
    method: 'DELETE',
    headers,
  });
  if (!res.ok) {
    throw new ApiError(res.status);
  }
}

/**
 * Get labels for a repository
 */
export async function getLabels(owner: string, repo: string): Promise<{ labels: Label[] }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/labels`);
  return handleResponse(res);
}

/**
 * Get issue history/events
 */
export async function getIssueHistory(owner: string, repo: string, number: number): Promise<{ events: IssueEvent[] }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${number}/history`);
  return handleResponse(res);
}

// =============================================================================
// Auth Endpoints
// =============================================================================

/**
 * Get current user (for middleware)
 */
export async function getCurrentUser(headers?: HeadersInit): Promise<User | null> {
  try {
    const res = await fetch(`${API_URL}/api/auth/me`, { headers });
    if (res.status === 401) return null;
    const data = await handleResponse<{ user: User | null }>(res);
    return data.user;
  } catch {
    return null;
  }
}

// =============================================================================
// SSH Keys Endpoints
// =============================================================================

export interface SshKey {
  id: number;
  name: string;
  fingerprint: string;
  createdAt: string;
}

/**
 * List user's SSH keys
 */
export async function listSshKeys(headers?: HeadersInit): Promise<{ keys: SshKey[] }> {
  const res = await fetch(`${API_URL}/api/ssh-keys`, { headers });
  return handleResponse(res);
}

// =============================================================================
// Token Endpoints
// =============================================================================

export interface AccessToken {
  id: number;
  name: string;
  scopes: string[];
  lastUsed: string | null;
  createdAt: string;
}

/**
 * List user's access tokens
 */
export async function listTokens(headers?: HeadersInit): Promise<{ tokens: AccessToken[] }> {
  const res = await fetch(`${API_URL}/api/user/tokens`, { headers });
  return handleResponse(res);
}

// =============================================================================
// Landing Request Endpoints
// =============================================================================

export interface LandingRequest {
  id: number;
  changeId: string;
  targetBookmark: string;
  title: string | null;
  description: string | null;
  status: string;
  hasConflicts: boolean;
  conflictedFiles: string[] | null;
  authorId: number;
  authorUsername: string | null;
  createdAt: string;
  updatedAt: string;
  landedAt: string | null;
  landedChangeId: string | null;
}

export interface LandingReview {
  id: number;
  landingId: number;
  reviewerId: number;
  reviewer_username?: string;
  type: string;
  content: string | null;
  changeId: string;
  createdAt: number;
}

export interface LineComment {
  id: number;
  landingId: number;
  authorId: number;
  author?: {
    username: string;
  };
  filePath: string;
  lineNumber: number;
  side: 'old' | 'new';
  body: string;
  resolved: boolean;
  createdAt: number;
  updatedAt: number;
}

/**
 * List landing requests for a repository
 */
export async function listLandingRequests(owner: string, repo: string): Promise<{ requests: LandingRequest[]; total: number }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/landing`);
  return handleResponse(res);
}

/**
 * Get a single landing request with reviews
 */
export async function getLandingRequest(owner: string, repo: string, id: number): Promise<{ request: LandingRequest; reviews: LandingReview[] }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/landing/${id}`);
  return handleResponse(res);
}

/**
 * Get line comments for a landing request
 */
export async function getLineComments(owner: string, repo: string, id: number): Promise<{ comments: LineComment[] }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/landing/${id}/comments`);
  return handleResponse(res);
}

// =============================================================================
// Commit Status Endpoints
// =============================================================================

export interface CommitStatus {
  id: number;
  repositoryId: number;
  commitSha: string;
  context: string;
  state: 'pending' | 'success' | 'failure' | 'error';
  description: string | null;
  targetUrl: string | null;
  workflowRunId: number | null;
  createdAt: number;
  updatedAt: number;
}

/**
 * Get commit statuses for a change
 */
export async function getCommitStatuses(
  owner: string,
  repo: string,
  changeId: string
): Promise<{ statuses: CommitStatus[]; aggregatedState: string }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/changes/${encodeURIComponent(changeId)}/statuses`);
  return handleResponse(res);
}

// =============================================================================
// Change Stack Endpoints
// =============================================================================

export interface StackChange {
  changeId: string;
  description: string;
  isEmpty: boolean;
  hasConflicts: boolean;
}

export interface ChangeStack {
  current: StackChange | null;
  ancestors: StackChange[];
  descendants: StackChange[];
  changeId: string;
}

/**
 * Get change stack (ancestors and descendants) for context visualization
 */
export async function getChangeStack(
  owner: string,
  repo: string,
  changeId: string,
  options: { ancestors?: number; descendants?: number } = {}
): Promise<ChangeStack> {
  const params = new URLSearchParams();
  if (options.ancestors !== undefined) params.set('ancestors', String(options.ancestors));
  if (options.descendants !== undefined) params.set('descendants', String(options.descendants));

  const queryString = params.toString();
  const url = `${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/changes/${encodeURIComponent(changeId)}/stack${queryString ? `?${queryString}` : ''}`;
  const res = await fetch(url);
  return handleResponse(res);
}

// =============================================================================
// Workflow Run Endpoints
// =============================================================================

export interface WorkflowRun {
  id: number;
  run_number: number;
  title: string | null;
  trigger_event: string;
  status: number;
  ref: string | null;
  commit_sha: string | null;
  created_at: string;
  started_at: string | null;
  stopped_at: string | null;
  workflow_definition_id?: number;
}

export interface ListWorkflowRunsOptions {
  status?: number;
  workflowDefinitionId?: number;
  limit?: number;
  offset?: number;
}

/**
 * List workflow runs for a repository
 */
export async function listWorkflowRuns(owner: string, repo: string, options: ListWorkflowRunsOptions = {}): Promise<{ runs: WorkflowRun[]; total: number }> {
  const params = new URLSearchParams();
  if (options.status !== undefined) params.set('status', String(options.status));
  if (options.workflowDefinitionId) params.set('workflow_definition_id', String(options.workflowDefinitionId));
  if (options.limit) params.set('limit', String(options.limit));
  if (options.offset) params.set('offset', String(options.offset));

  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/workflows/runs?${params}`);
  return handleResponse(res);
}

/**
 * Get a single workflow run
 */
export async function getWorkflowRun(owner: string, repo: string, runId: number): Promise<{ run: WorkflowRun }> {
  const res = await fetch(`${API_URL}/api/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/workflows/runs/${runId}`);
  return handleResponse(res);
}
