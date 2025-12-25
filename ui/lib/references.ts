/**
 * Issue Reference Parser
 *
 * Parses issue references from text:
 * - #123 (same repository)
 * - owner/repo#123 (cross-repository)
 */

export interface IssueReference {
  owner?: string;
  repo?: string;
  number: number;
  raw: string;
}

/**
 * Parse issue references from text
 *
 * @param text Text to parse
 * @param currentOwner Current repository owner (for resolving #123)
 * @param currentRepo Current repository name (for resolving #123)
 * @returns Array of issue references
 */
export function parseReferences(
  text: string,
  currentOwner?: string,
  currentRepo?: string
): IssueReference[] {
  const references: IssueReference[] = [];

  // Match full references: owner/repo#123
  const fullPattern = /([a-zA-Z0-9_-]+)\/([a-zA-Z0-9_-]+)#(\d+)/g;
  let match: RegExpExecArray | null;

  while ((match = fullPattern.exec(text)) !== null) {
    references.push({
      owner: match[1],
      repo: match[2],
      number: parseInt(match[3], 10),
      raw: match[0],
    });
  }

  // Match short references: #123
  // Only match if preceded by whitespace, start of string, or punctuation
  // to avoid matching in URLs or code
  const shortPattern = /(?:^|[\s([{])#(\d+)(?=$|[\s)\]}.,;!?])/gm;

  while ((match = shortPattern.exec(text)) !== null) {
    const number = parseInt(match[1], 10);
    const raw = `#${number}`;

    // Check if this reference is already captured by a full reference
    const alreadyCaptured = references.some(
      ref => ref.number === number && match && text.indexOf(ref.raw) === match.index
    );

    if (!alreadyCaptured) {
      references.push({
        owner: currentOwner,
        repo: currentRepo,
        number,
        raw,
      });
    }
  }

  return references;
}

/**
 * Build issue URL from reference
 */
export function buildIssueUrl(ref: IssueReference): string {
  if (ref.owner && ref.repo) {
    return `/${ref.owner}/${ref.repo}/issues/${ref.number}`;
  }
  return `#${ref.number}`;
}

/**
 * Format reference for display
 */
export function formatReference(ref: IssueReference): string {
  if (ref.owner && ref.repo) {
    return `${ref.owner}/${ref.repo}#${ref.number}`;
  }
  return `#${ref.number}`;
}
