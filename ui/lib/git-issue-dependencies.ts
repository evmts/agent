/**
 * Issue Dependency Management
 *
 * Handles "blocks" and "blocked by" relationships between issues
 */

import { getIssue, updateIssue, IssueNotFoundError } from "./git-issues";
import type { GitIssue } from "./git-issue-types";

// =============================================================================
// Dependency Operations
// =============================================================================

/**
 * Add a dependency relationship between issues
 * @param blockingIssue - The issue number that blocks
 * @param blockedIssue - The issue number that is blocked
 */
export async function addDependency(
  user: string,
  repo: string,
  blockingIssue: number,
  blockedIssue: number
): Promise<{ blocking: GitIssue; blocked: GitIssue }> {
  const blocking = await getIssue(user, repo, blockingIssue);
  const blocked = await getIssue(user, repo, blockedIssue);

  if (!blocking) {
    throw new IssueNotFoundError(user, repo, blockingIssue);
  }
  if (!blocked) {
    throw new IssueNotFoundError(user, repo, blockedIssue);
  }

  // Prevent self-dependency
  if (blockingIssue === blockedIssue) {
    throw new Error("An issue cannot depend on itself");
  }

  // Check if dependency already exists
  const blocks = blocking.blocks || [];
  const blockedBy = blocked.blocked_by || [];

  if (blocks.includes(blockedIssue)) {
    // Dependency already exists
    return { blocking, blocked };
  }

  // Add the dependency
  const updatedBlocks = [...blocks, blockedIssue];
  const updatedBlockedBy = [...blockedBy, blockingIssue];

  // Update both issues atomically
  const updatedBlocking = await updateIssue(user, repo, blockingIssue, {
    blocks: updatedBlocks,
  });

  const updatedBlocked = await updateIssue(user, repo, blockedIssue, {
    blocked_by: updatedBlockedBy,
  });

  return { blocking: updatedBlocking, blocked: updatedBlocked };
}

/**
 * Remove a dependency relationship between issues
 * @param blockingIssue - The issue number that blocks
 * @param blockedIssue - The issue number that is blocked
 */
export async function removeDependency(
  user: string,
  repo: string,
  blockingIssue: number,
  blockedIssue: number
): Promise<{ blocking: GitIssue; blocked: GitIssue }> {
  const blocking = await getIssue(user, repo, blockingIssue);
  const blocked = await getIssue(user, repo, blockedIssue);

  if (!blocking) {
    throw new IssueNotFoundError(user, repo, blockingIssue);
  }
  if (!blocked) {
    throw new IssueNotFoundError(user, repo, blockedIssue);
  }

  // Remove from both issues
  const blocks = blocking.blocks || [];
  const blockedBy = blocked.blocked_by || [];

  const updatedBlocks = blocks.filter((n) => n !== blockedIssue);
  const updatedBlockedBy = blockedBy.filter((n) => n !== blockingIssue);

  // Update both issues
  const updatedBlocking = await updateIssue(user, repo, blockingIssue, {
    blocks: updatedBlocks,
  });

  const updatedBlocked = await updateIssue(user, repo, blockedIssue, {
    blocked_by: updatedBlockedBy,
  });

  return { blocking: updatedBlocking, blocked: updatedBlocked };
}

/**
 * Get all blocking issues (issues that this issue blocks)
 */
export async function getBlockingIssues(
  user: string,
  repo: string,
  issueNumber: number
): Promise<GitIssue[]> {
  const issue = await getIssue(user, repo, issueNumber);
  if (!issue) {
    throw new IssueNotFoundError(user, repo, issueNumber);
  }

  const blocks = issue.blocks || [];
  const blockingIssues: GitIssue[] = [];

  for (const blockedNumber of blocks) {
    const blockedIssue = await getIssue(user, repo, blockedNumber);
    if (blockedIssue) {
      blockingIssues.push(blockedIssue);
    }
  }

  return blockingIssues;
}

/**
 * Get all blocked-by issues (issues that block this issue)
 */
export async function getBlockedByIssues(
  user: string,
  repo: string,
  issueNumber: number
): Promise<GitIssue[]> {
  const issue = await getIssue(user, repo, issueNumber);
  if (!issue) {
    throw new IssueNotFoundError(user, repo, issueNumber);
  }

  const blockedBy = issue.blocked_by || [];
  const blockingIssues: GitIssue[] = [];

  for (const blockingNumber of blockedBy) {
    const blockingIssue = await getIssue(user, repo, blockingNumber);
    if (blockingIssue) {
      blockingIssues.push(blockingIssue);
    }
  }

  return blockingIssues;
}

/**
 * Check if an issue can be closed (not blocked by open issues)
 */
export async function canCloseIssue(
  user: string,
  repo: string,
  issueNumber: number
): Promise<{ canClose: boolean; openBlockers: GitIssue[] }> {
  const issue = await getIssue(user, repo, issueNumber);
  if (!issue) {
    throw new IssueNotFoundError(user, repo, issueNumber);
  }

  const blockedBy = issue.blocked_by || [];
  const openBlockers: GitIssue[] = [];

  for (const blockingNumber of blockedBy) {
    const blockingIssue = await getIssue(user, repo, blockingNumber);
    if (blockingIssue && blockingIssue.state === "open") {
      openBlockers.push(blockingIssue);
    }
  }

  return {
    canClose: openBlockers.length === 0,
    openBlockers,
  };
}
