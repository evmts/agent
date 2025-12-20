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

export interface IssueFilters {
  state?: "open" | "closed" | "all";
  author?: string;
  assignee?: string;
  labels?: string[];
  milestone?: string;
  search?: string;
  sort?: "created" | "updated" | "comments";
}

/**
 * List all issues, optionally filtered
 */
export async function listIssues(
  user: string,
  repo: string,
  filters: IssueFilters | "open" | "closed" | "all" = "all"
): Promise<GitIssue[]> {
  const issuesPath = getIssuesPath(user, repo);

  if (!existsSync(issuesPath)) {
    return [];
  }

  // Handle legacy string parameter for backwards compatibility
  const filterOptions: IssueFilters = typeof filters === "string"
    ? { state: filters }
    : filters;

  const {
    state = "all",
    author,
    assignee,
    labels = [],
    milestone,
    search,
    sort = "created"
  } = filterOptions;

  const entries = await readdir(issuesPath, { withFileTypes: true });
  const issues: GitIssue[] = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;

    const issueNumber = parseInt(entry.name, 10);
    if (isNaN(issueNumber)) continue;

    const issue = await getIssue(user, repo, issueNumber);
    if (!issue) continue;

    // Filter by state
    if (state !== "all" && issue.state !== state) {
      continue;
    }

    // Filter by author
    if (author && issue.author.username !== author) {
      continue;
    }

    // Filter by assignee
    if (assignee && !issue.assignees.includes(assignee)) {
      continue;
    }

    // Filter by labels (issue must have ALL specified labels)
    if (labels.length > 0) {
      const hasAllLabels = labels.every(label => issue.labels.includes(label));
      if (!hasAllLabels) {
        continue;
      }
    }

    // Filter by milestone
    if (milestone !== undefined) {
      if (milestone === "none" && issue.milestone !== null) {
        continue;
      } else if (milestone !== "none" && issue.milestone !== milestone) {
        continue;
      }
    }

    // Filter by search text (search in title and body)
    if (search) {
      const searchLower = search.toLowerCase();
      const titleMatch = issue.title.toLowerCase().includes(searchLower);
      const bodyMatch = issue.body.toLowerCase().includes(searchLower);
      if (!titleMatch && !bodyMatch) {
        continue;
      }
    }

    issues.push(issue);
  }

  // Sort issues
  switch (sort) {
    case "updated":
      issues.sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());
      break;
    case "comments":
      // For comments sort, we need to count comments for each issue
      // For now, we'll just use updated_at as a proxy
      // TODO: Implement actual comment counting
      issues.sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());
      break;
    case "created":
    default:
      // Sort by issue number descending (newest first)
      issues.sort((a, b) => b.number - a.number);
      break;
  }

  return issues;
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

/**
 * Update a comment
 */
export async function updateComment(
  user: string,
  repo: string,
  issueNumber: number,
  commentId: number,
  data: { body: string }
): Promise<GitComment> {
  const issuesPath = getIssuesPath(user, repo);
  const issue = await getIssue(user, repo, issueNumber);

  if (!issue) {
    throw new IssueNotFoundError(user, repo, issueNumber);
  }

  const commentIdStr = commentId.toString().padStart(3, "0");
  const commentPath = `${issuesPath}/${issueNumber}/comments/${commentIdStr}.md`;

  if (!existsSync(commentPath)) {
    throw new Error(`Comment #${commentId} not found`);
  }

  // Read existing comment
  const content = await readFile(commentPath, "utf-8");
  const { data: existingData } = parseFrontmatter<CommentFrontmatter>(content);

  // Update comment data
  const now = new Date().toISOString();
  const updatedData: CommentFrontmatter = {
    ...existingData,
    updated_at: now,
    edited: true,
  };

  // Write updated comment
  const updatedContent = stringifyFrontmatter(
    updatedData as unknown as Record<string, unknown>,
    data.body
  );
  await writeFile(commentPath, updatedContent);

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
    [`${issueNumber}/comments/${commentIdStr}.md`, `${issueNumber}/issue.md`],
    createCommitMessage("edit comment", issueNumber, `Update comment #${commentId}`)
  );

  return {
    ...updatedData,
    body: data.body,
  };
}

/**
 * Delete a comment
 */
export async function deleteComment(
  user: string,
  repo: string,
  issueNumber: number,
  commentId: number
): Promise<void> {
  const issuesPath = getIssuesPath(user, repo);
  const issue = await getIssue(user, repo, issueNumber);

  if (!issue) {
    throw new IssueNotFoundError(user, repo, issueNumber);
  }

  const commentIdStr = commentId.toString().padStart(3, "0");
  const commentPath = `${issuesPath}/${issueNumber}/comments/${commentIdStr}.md`;

  if (!existsSync(commentPath)) {
    throw new Error(`Comment #${commentId} not found`);
  }

  // Remove comment file
  await rm(commentPath);

  // Update issue's updated_at
  const now = new Date().toISOString();
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
    [`${issueNumber}/comments/${commentIdStr}.md`, `${issueNumber}/issue.md`],
    createCommitMessage("delete comment", issueNumber, `Delete comment #${commentId}`)
  );
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
): Promise<Array<{ name: string; color: string; description?: string }>> {
  await ensureIssuesRepo(user, repo);
  const config = await getConfig(user, repo);
  return config.labels;
}

/**
 * Get unique authors from all issues
 */
export async function getUniqueAuthors(
  user: string,
  repo: string
): Promise<Array<{ username: string }>> {
  const issues = await listIssues(user, repo, "all");
  const authorsMap = new Map<string, { username: string }>();

  for (const issue of issues) {
    authorsMap.set(issue.author.username, { username: issue.author.username });
  }

  return Array.from(authorsMap.values()).sort((a, b) =>
    a.username.localeCompare(b.username)
  );
}

/**
 * Get unique assignees from all issues
 */
export async function getUniqueAssignees(
  user: string,
  repo: string
): Promise<Array<{ username: string }>> {
  const issues = await listIssues(user, repo, "all");
  const assigneesSet = new Set<string>();

  for (const issue of issues) {
    for (const assignee of issue.assignees) {
      assigneesSet.add(assignee);
    }
  }

  return Array.from(assigneesSet)
    .map(username => ({ username }))
    .sort((a, b) => a.username.localeCompare(b.username));
}

/**
 * Create a new label
 */
export async function createLabel(
  user: string,
  repo: string,
  label: { name: string; color: string; description?: string }
): Promise<void> {
  await ensureIssuesRepo(user, repo);
  const issuesPath = getIssuesPath(user, repo);
  const config = await getConfig(user, repo);

  // Check if label already exists
  if (config.labels.some((l) => l.name === label.name)) {
    throw new Error(`Label "${label.name}" already exists`);
  }

  // Add label to config
  config.labels.push(label);
  await saveConfig(user, repo, config);

  // Commit
  await atomicCommit(
    issuesPath,
    ["config.yaml"],
    `Add label: ${label.name}`
  );
}

/**
 * Update a label
 */
export async function updateLabel(
  user: string,
  repo: string,
  oldName: string,
  newLabel: { name: string; color: string; description?: string }
): Promise<void> {
  await ensureIssuesRepo(user, repo);
  const issuesPath = getIssuesPath(user, repo);
  const config = await getConfig(user, repo);

  const labelIndex = config.labels.findIndex((l) => l.name === oldName);
  if (labelIndex === -1) {
    throw new Error(`Label "${oldName}" not found`);
  }

  // Update label
  config.labels[labelIndex] = newLabel;
  await saveConfig(user, repo, config);

  // If name changed, update all issues that use this label
  if (oldName !== newLabel.name) {
    const issues = await listIssues(user, repo, "all");
    for (const issue of issues) {
      if (issue.labels.includes(oldName)) {
        const updatedLabels = issue.labels.map((l) =>
          l === oldName ? newLabel.name : l
        );
        await updateIssue(user, repo, issue.number, { labels: updatedLabels });
      }
    }
  }

  // Commit
  await atomicCommit(
    issuesPath,
    ["config.yaml"],
    `Update label: ${oldName} -> ${newLabel.name}`
  );
}

/**
 * Delete a label
 */
export async function deleteLabel(
  user: string,
  repo: string,
  name: string
): Promise<void> {
  await ensureIssuesRepo(user, repo);
  const issuesPath = getIssuesPath(user, repo);
  const config = await getConfig(user, repo);

  const labelIndex = config.labels.findIndex((l) => l.name === name);
  if (labelIndex === -1) {
    throw new Error(`Label "${name}" not found`);
  }

  // Remove label from config
  config.labels.splice(labelIndex, 1);
  await saveConfig(user, repo, config);

  // Remove label from all issues
  const issues = await listIssues(user, repo, "all");
  for (const issue of issues) {
    if (issue.labels.includes(name)) {
      const updatedLabels = issue.labels.filter((l) => l !== name);
      await updateIssue(user, repo, issue.number, { labels: updatedLabels });
    }
  }

  // Commit
  await atomicCommit(
    issuesPath,
    ["config.yaml"],
    `Delete label: ${name}`
  );
}

/**
 * Add labels to an issue
 */
export async function addLabelsToIssue(
  user: string,
  repo: string,
  issueNumber: number,
  labels: string[]
): Promise<GitIssue> {
  const issue = await getIssue(user, repo, issueNumber);
  if (!issue) {
    throw new IssueNotFoundError(user, repo, issueNumber);
  }

  // Get valid labels from config
  const config = await getConfig(user, repo);
  const validLabels = config.labels.map((l) => l.name);

  // Filter to only valid labels that aren't already on the issue
  const newLabels = labels.filter(
    (l) => validLabels.includes(l) && !issue.labels.includes(l)
  );

  if (newLabels.length === 0) {
    return issue;
  }

  // Add new labels
  const updatedLabels = [...issue.labels, ...newLabels];
  return await updateIssue(user, repo, issueNumber, { labels: updatedLabels });
}

/**
 * Remove a label from an issue
 */
export async function removeLabelFromIssue(
  user: string,
  repo: string,
  issueNumber: number,
  label: string
): Promise<GitIssue> {
  const issue = await getIssue(user, repo, issueNumber);
  if (!issue) {
    throw new IssueNotFoundError(user, repo, issueNumber);
  }

  if (!issue.labels.includes(label)) {
    return issue;
  }

  const updatedLabels = issue.labels.filter((l) => l !== label);
  return await updateIssue(user, repo, issueNumber, { labels: updatedLabels });
}
