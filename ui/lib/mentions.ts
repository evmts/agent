/**
 * Mentions parser for @username syntax in issues and comments.
 */

export interface Mention {
  username: string;
  startIndex: number;
  endIndex: number;
}

/**
 * Extract all @username mentions from text.
 * Matches @username patterns where username contains alphanumeric, underscore, or hyphen.
 */
export function extractMentions(text: string): Mention[] {
  const mentions: Mention[] = [];
  // Match @username - alphanumeric, underscore, hyphen (1-39 chars, GitHub-style)
  const mentionRegex = /@([a-zA-Z0-9_-]{1,39})\b/g;

  let match: RegExpExecArray | null;
  while ((match = mentionRegex.exec(text)) !== null) {
    mentions.push({
      username: match[1],
      startIndex: match.index,
      endIndex: match.index + match[0].length,
    });
  }

  return mentions;
}

/**
 * Get unique usernames from text.
 */
export function getUniqueMentionedUsernames(text: string): string[] {
  const mentions = extractMentions(text);
  const uniqueUsernames = new Set(mentions.map(m => m.username.toLowerCase()));
  return Array.from(uniqueUsernames);
}

/**
 * Replace @username mentions with HTML links.
 */
export function replaceMentionsWithLinks(text: string): string {
  // Replace @username with link, preserving case for display
  return text.replace(
    /@([a-zA-Z0-9_-]{1,39})\b/g,
    '<a href="/$1" class="mention">@$1</a>'
  );
}

/**
 * Check if text contains any mentions.
 */
export function hasMentions(text: string): boolean {
  return /@[a-zA-Z0-9_-]{1,39}\b/.test(text);
}
