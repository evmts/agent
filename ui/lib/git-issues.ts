/**
 * Git-based Issue Tracking System
 *
 * Issues are stored as Markdown files with YAML frontmatter in a
 * nested git repository at .plue/issues/ within each project.
 */

import { exec } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, readFile, writeFile, readdir, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { parseFrontmatter, stringifyFrontmatter } from "./frontmatter";
import type {
  GitIssue,
  GitComment,
  IssueConfig,
  IssueFrontmatter,
  CommentFrontmatter,
  CreateIssueInput,
  UpdateIssueInput,
  CreateCommentInput,
  IssueHistoryEntry,
} from "./git-issue-types";

const execAsync = promisify(exec);

const REPOS_DIR = `${process.cwd()}/repos`;

// =============================================================================
// Error Types
// =============================================================================

export class IssueNotFoundError extends Error {
  constructor(user: string, repo: string, number: number) {
    super(`Issue #${number} not found in ${user}/${repo}`);
    this.name = "IssueNotFoundError";
  }
}

export class IssuesRepoNotInitializedError extends Error {
  constructor(user: string, repo: string) {
    super(`Issues repository not initialized for ${user}/${repo}`);
    this.name = "IssuesRepoNotInitializedError";
  }
}

export class GitOperationError extends Error {
  constructor(operation: string, message: string) {
    super(`Git ${operation} failed: ${message}`);
    this.name = "GitOperationError";
  }
}

// =============================================================================
// Helpers
// =============================================================================

function getRepoPath(user: string, repo: string): string {
  return `${REPOS_DIR}/${user}/${repo}`;
}

function getIssuesPath(user: string, repo: string): string {
  return `${getRepoPath(user, repo)}/.plue/issues`;
}

async function runGit(
  args: string[],
  cwd: string
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  try {
    const cmd = `git ${args.map((a) => `"${a.replace(/"/g, '\\"')}"`).join(" ")}`;
    const { stdout, stderr } = await execAsync(cmd, {
      cwd,
      maxBuffer: 10 * 1024 * 1024,
    });
    return { stdout, stderr, exitCode: 0 };
  } catch (error: unknown) {
    const err = error as { stdout?: string; stderr?: string; code?: number };
    return {
      stdout: err.stdout || "",
      stderr: err.stderr || "",
      exitCode: err.code || 1,
    };
  }
}

async function atomicCommit(
  issuesPath: string,
  files: string[],
  message: string
): Promise<void> {
  // Add files
  for (const file of files) {
    await runGit(["add", file], issuesPath);
  }

  // Commit
  const result = await runGit(["commit", "-m", message], issuesPath);

  if (result.exitCode !== 0 && !result.stdout.includes("nothing to commit")) {
    throw new GitOperationError("commit", result.stderr);
  }
}

function createCommitMessage(
  action: string,
  issueNumber: number,
  description: string
): string {
  return `${action} #${issueNumber}: ${description}`;
}

// =============================================================================
// Repository Initialization
// =============================================================================

/**
 * Initialize the issues git repository for a project
 */
export async function initIssuesRepo(user: string, repo: string): Promise<void> {
  const issuesPath = getIssuesPath(user, repo);

  if (existsSync(`${issuesPath}/.git`)) {
    return; // Already initialized
  }

  // Create directory structure
  await mkdir(issuesPath, { recursive: true });

  // Initialize git repo
  await runGit(["init"], issuesPath);
  await runGit(["config", "user.name", "Plue Issues"], issuesPath);
  await runGit(["config", "user.email", "issues@plue.local"], issuesPath);

  // Create initial config
  const config: IssueConfig = {
    version: 1,
    next_issue_number: 1,
    labels: [
      { name: "bug", color: "#d73a4a" },
      { name: "enhancement", color: "#a2eeef" },
      { name: "documentation", color: "#0075ca" },
      { name: "good first issue", color: "#7057ff" },
      { name: "help wanted", color: "#008672" },
    ],
    default_assignees: [],
  };

  await writeFile(
    `${issuesPath}/config.yaml`,
    stringifyFrontmatter(config as unknown as Record<string, unknown>, "")
  );

  // Initial commit
  await runGit(["add", "."], issuesPath);
  await runGit(["commit", "-m", "Initialize issue tracker"], issuesPath);
}

/**
 * Ensure the issues repo exists, initializing if needed
 */
export async function ensureIssuesRepo(user: string, repo: string): Promise<void> {
  const issuesPath = getIssuesPath(user, repo);

  if (!existsSync(`${issuesPath}/.git`)) {
    await initIssuesRepo(user, repo);
  }
}

/**
 * Check if issues repo is initialized
 */
export function isIssuesRepoInitialized(user: string, repo: string): boolean {
  const issuesPath = getIssuesPath(user, repo);
  return existsSync(`${issuesPath}/.git`);
}

// =============================================================================
// Config Operations
// =============================================================================

async function getConfig(user: string, repo: string): Promise<IssueConfig> {
  const issuesPath = getIssuesPath(user, repo);
  const configPath = `${issuesPath}/config.yaml`;

  const content = await readFile(configPath, "utf-8");
  const { data } = parseFrontmatter<IssueConfig>(content);

  return data;
}

async function saveConfig(
  user: string,
  repo: string,
  config: IssueConfig
): Promise<void> {
  const issuesPath = getIssuesPath(user, repo);
  const configPath = `${issuesPath}/config.yaml`;

  await writeFile(
    configPath,
    stringifyFrontmatter(config as unknown as Record<string, unknown>, "")
  );
}

// =============================================================================
// Issue Operations
// =============================================================================

/**
 * Create a new issue
 */
export async function createIssue(
  user: string,
  repo: string,
  data: CreateIssueInput
): Promise<GitIssue> {
  await ensureIssuesRepo(user, repo);
  const issuesPath = getIssuesPath(user, repo);

  // Get next issue number
  const config = await getConfig(user, repo);
  const issueNumber = config.next_issue_number;
  const issuePath = `${issuesPath}/${issueNumber}`;

  // Create issue directory
  await mkdir(`${issuePath}/comments`, { recursive: true });

  // Create issue file
  const now = new Date().toISOString();
  const issueData: IssueFrontmatter = {
    id: issueNumber,
    title: data.title,
    state: "open",
    author: data.author,
    created_at: now,
    updated_at: now,
    closed_at: null,
    labels: data.labels || [],
    assignees: data.assignees || [],
    milestone: data.milestone || null,
  };

  const issueContent = stringifyFrontmatter(
    issueData as unknown as Record<string, unknown>,
    data.body
  );
  await writeFile(`${issuePath}/issue.md`, issueContent);

  // Update config
  config.next_issue_number = issueNumber + 1;
  await saveConfig(user, repo, config);

  // Commit
  await atomicCommit(
    issuesPath,
    [`${issueNumber}/issue.md`, "config.yaml"],
    createCommitMessage("create", issueNumber, data.title)
  );

  return {
    number: issueNumber,
    ...issueData,
    body: data.body,
  };
}

/**
 * Get a single issue by number
 */
export async function getIssue(
  user: string,
  repo: string,
  number: number
): Promise<GitIssue | null> {
  const issuesPath = getIssuesPath(user, repo);
  const issuePath = `${issuesPath}/${number}/issue.md`;

  if (!existsSync(issuePath)) {
    return null;
  }

  const content = await readFile(issuePath, "utf-8");
  const { data, content: body } = parseFrontmatter<IssueFrontmatter>(content);

  return {
    number,
    ...data,
    body,
  };
}

/**
 * List all issues, optionally filtered by state
 */
export async function listIssues(
  user: string,
  repo: string,
  state: "open" | "closed" | "all" = "all"
): Promise<GitIssue[]> {
  const issuesPath = getIssuesPath(user, repo);

  if (!existsSync(issuesPath)) {
    return [];
  }

  const entries = await readdir(issuesPath, { withFileTypes: true });
  const issues: GitIssue[] = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;

    const issueNumber = parseInt(entry.name, 10);
    if (isNaN(issueNumber)) continue;

    const issue = await getIssue(user, repo, issueNumber);
    if (!issue) continue;

    if (state === "all" || issue.state === state) {
      issues.push(issue);
    }
  }

  // Sort by issue number descending (newest first)
  return issues.sort((a, b) => b.number - a.number);
}

/**
 * Update an issue
 */
export async function updateIssue(
  user: string,
  repo: string,
  number: number,
  data: UpdateIssueInput
): Promise<GitIssue> {
  const issuesPath = getIssuesPath(user, repo);
  const issue = await getIssue(user, repo, number);

  if (!issue) {
    throw new IssueNotFoundError(user, repo, number);
  }

  // Update fields
  const now = new Date().toISOString();
  const updatedIssue: GitIssue = {
    ...issue,
    title: data.title ?? issue.title,
    body: data.body ?? issue.body,
    state: data.state ?? issue.state,
    labels: data.labels ?? issue.labels,
    assignees: data.assignees ?? issue.assignees,
    milestone: data.milestone !== undefined ? data.milestone : issue.milestone,
    updated_at: now,
  };

  // Handle state change
  if (data.state === "closed" && issue.state === "open") {
    updatedIssue.closed_at = now;
  } else if (data.state === "open" && issue.state === "closed") {
    updatedIssue.closed_at = null;
  }

  // Build frontmatter
  const frontmatter: IssueFrontmatter = {
    id: updatedIssue.id,
    title: updatedIssue.title,
    state: updatedIssue.state,
    author: updatedIssue.author,
    created_at: updatedIssue.created_at,
    updated_at: updatedIssue.updated_at,
    closed_at: updatedIssue.closed_at,
    labels: updatedIssue.labels,
    assignees: updatedIssue.assignees,
    milestone: updatedIssue.milestone,
  };

  const content = stringifyFrontmatter(
    frontmatter as unknown as Record<string, unknown>,
    updatedIssue.body
  );
  await writeFile(`${issuesPath}/${number}/issue.md`, content);

  // Determine commit action
  let action = "update";
  if (data.state === "closed" && issue.state === "open") {
    action = "close";
  } else if (data.state === "open" && issue.state === "closed") {
    action = "reopen";
  }

  await atomicCommit(
    issuesPath,
    [`${number}/issue.md`],
    createCommitMessage(action, number, issue.title)
  );

  return updatedIssue;
}

/**
 * Close an issue
 */
export async function closeIssue(
  user: string,
  repo: string,
  number: number
): Promise<void> {
  await updateIssue(user, repo, number, { state: "closed" });
}

/**
 * Reopen an issue
 */
export async function reopenIssue(
  user: string,
  repo: string,
  number: number
): Promise<void> {
  await updateIssue(user, repo, number, { state: "open" });
}

/**
 * Delete an issue
 */
export async function deleteIssue(
  user: string,
  repo: string,
  number: number
): Promise<void> {
  const issuesPath = getIssuesPath(user, repo);
  const issue = await getIssue(user, repo, number);

  if (!issue) {
    throw new IssueNotFoundError(user, repo, number);
  }

  // Remove the issue directory
  await rm(`${issuesPath}/${number}`, { recursive: true });

  // Commit the deletion
  await runGit(["add", "-A"], issuesPath);
  await runGit(
    ["commit", "-m", createCommitMessage("delete", number, issue.title)],
    issuesPath
  );
}

// =============================================================================
// Comment Operations
// =============================================================================

/**
 * Add a comment to an issue
 */
export async function addComment(
  user: string,
  repo: string,
  issueNumber: number,
  data: CreateCommentInput
): Promise<GitComment> {
  const issuesPath = getIssuesPath(user, repo);
  const issue = await getIssue(user, repo, issueNumber);

  if (!issue) {
    throw new IssueNotFoundError(user, repo, issueNumber);
  }

  const commentsPath = `${issuesPath}/${issueNumber}/comments`;

  // Get next comment ID
  let nextCommentId = 1;
  if (existsSync(commentsPath)) {
    const entries = await readdir(commentsPath);
    const commentIds = entries
      .map((e) => parseInt(e.replace(".md", ""), 10))
      .filter((n) => !isNaN(n));
    if (commentIds.length > 0) {
      nextCommentId = Math.max(...commentIds) + 1;
    }
  } else {
    await mkdir(commentsPath, { recursive: true });
  }

  const commentId = nextCommentId.toString().padStart(3, "0");
  const now = new Date().toISOString();

  const commentData: CommentFrontmatter = {
    id: nextCommentId,
    author: data.author,
    created_at: now,
  };

  const content = stringifyFrontmatter(
    commentData as unknown as Record<string, unknown>,
    data.body
  );
  await writeFile(`${commentsPath}/${commentId}.md`, content);

  // Update issue's updated_at
  const frontmatter: IssueFrontmatter = {
    id: issue.id,
    title: issue.title,
    state: issue.state,
    author: issue.author,
    created_at: issue.created_at,
    updated_at: now,
    closed_at: issue.closed_at,
    labels: issue.labels,
    assignees: issue.assignees,
    milestone: issue.milestone,
  };
  const issueContent = stringifyFrontmatter(
    frontmatter as unknown as Record<string, unknown>,
    issue.body
  );
  await writeFile(`${issuesPath}/${issueNumber}/issue.md`, issueContent);

  await atomicCommit(
    issuesPath,
    [`${issueNumber}/comments/${commentId}.md`, `${issueNumber}/issue.md`],
    createCommitMessage("comment", issueNumber, `Add comment by ${data.author.username}`)
  );

  return {
    ...commentData,
    body: data.body,
  };
}

/**
 * Get all comments for an issue
 */
export async function getComments(
  user: string,
  repo: string,
  issueNumber: number
): Promise<GitComment[]> {
  const issuesPath = getIssuesPath(user, repo);
  const commentsPath = `${issuesPath}/${issueNumber}/comments`;

  if (!existsSync(commentsPath)) {
    return [];
  }

  const entries = await readdir(commentsPath);
  const comments: GitComment[] = [];

  for (const entry of entries) {
    if (!entry.endsWith(".md")) continue;

    const content = await readFile(`${commentsPath}/${entry}`, "utf-8");
    const { data, content: body } = parseFrontmatter<CommentFrontmatter>(content);

    comments.push({
      ...data,
      body,
    });
  }

  // Sort by ID ascending (oldest first)
  return comments.sort((a, b) => a.id - b.id);
}

// =============================================================================
// History Operations
// =============================================================================

/**
 * Get the git history for an issue
 */
export async function getIssueHistory(
  user: string,
  repo: string,
  issueNumber: number
): Promise<IssueHistoryEntry[]> {
  const issuesPath = getIssuesPath(user, repo);

  const result = await runGit(
    [
      "log",
      "--pretty=format:%H|%s|%an|%at",
      "--",
      `${issueNumber}/`,
    ],
    issuesPath
  );

  if (result.exitCode !== 0 || !result.stdout.trim()) {
    return [];
  }

  const lines = result.stdout.trim().split("\n").filter(Boolean);

  return lines.map((line) => {
    const [hash, message, author, timestamp] = line.split("|");

    // Parse action from commit message
    const actionMatch = message?.match(/^(\w+) #\d+:/);
    const action = actionMatch?.[1] || "update";

    return {
      commitHash: hash || "",
      message: message || "",
      author: author || "",
      timestamp: new Date(parseInt(timestamp || "0", 10) * 1000),
      action,
    };
  });
}

// =============================================================================
// Statistics
// =============================================================================

/**
 * Get issue counts by state
 */
export async function getIssueCounts(
  user: string,
  repo: string
): Promise<{ open: number; closed: number; total: number }> {
  const issues = await listIssues(user, repo, "all");

  const open = issues.filter((i) => i.state === "open").length;
  const closed = issues.filter((i) => i.state === "closed").length;

  return { open, closed, total: issues.length };
}

/**
 * Get available labels for a repository
 */
export async function getLabels(
  user: string,
  repo: string
): Promise<Array<{ name: string; color: string }>> {
  await ensureIssuesRepo(user, repo);
  const config = await getConfig(user, repo);
  return config.labels;
}
