/**
 * Parse references from issue/comment text (for git-based issues)
 */

import { parseReferences } from "@plue/db";
import { getIssue as getGitIssue } from "./git-issues";

export interface ResolvedReference {
  owner: string;
  repo: string;
  number: number;
  title?: string;
  state?: 'open' | 'closed';
  exists: boolean;
}

/**
 * Parse and resolve references from text
 */
export async function parseAndResolveReferences(
  text: string,
  currentOwner: string,
  currentRepo: string
): Promise<ResolvedReference[]> {
  const references = parseReferences(text, currentOwner, currentRepo);
  const resolved: ResolvedReference[] = [];

  for (const ref of references) {
    if (!ref.owner || !ref.repo) continue;

    // Try to fetch the issue to check if it exists and get metadata
    try {
      const issue = await getGitIssue(ref.owner, ref.repo, ref.number);

      if (issue) {
        resolved.push({
          owner: ref.owner,
          repo: ref.repo,
          number: ref.number,
          title: issue.title,
          state: issue.state,
          exists: true,
        });
      } else {
        resolved.push({
          owner: ref.owner,
          repo: ref.repo,
          number: ref.number,
          exists: false,
        });
      }
    } catch {
      // Issue doesn't exist or can't be accessed
      resolved.push({
        owner: ref.owner,
        repo: ref.repo,
        number: ref.number,
        exists: false,
      });
    }
  }

  // Remove duplicates
  const seen = new Set<string>();
  return resolved.filter(ref => {
    const key = `${ref.owner}/${ref.repo}#${ref.number}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/**
 * Find all issues that reference this issue (reverse lookup)
 * This requires scanning all issues - expensive but works for git-based system
 */
export async function findReferencingIssues(
  _targetOwner: string,
  _targetRepo: string,
  _targetNumber: number
): Promise<Array<{ owner: string; repo: string; number: number; title: string; state: 'open' | 'closed' }>> {
  // For now, return empty array
  // In the future, this could be implemented by:
  // 1. Scanning all issues in the repository
  // 2. Parsing references from each issue
  // 3. Finding matches
  // This is expensive and should be done asynchronously or cached
  return [];
}
