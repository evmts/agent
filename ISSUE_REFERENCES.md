# Issue Cross-References Implementation

This document describes the issue cross-reference (#123 linking) feature implemented in Plue.

## Overview

Users can now reference issues using GitHub-style syntax:
- `#123` - References issue #123 in the same repository
- `owner/repo#123` - References issue #123 in a different repository

These references are automatically parsed and converted to clickable links in issue descriptions and comments.

## Components Created

### 1. Reference Parser (`ui/lib/references.ts`)
Core parser that extracts issue references from text.

**Functions:**
- `parseReferences(text, currentOwner, currentRepo)` - Parse all issue references from text
- `buildIssueUrl(ref)` - Build URL for an issue reference
- `formatReference(ref)` - Format reference for display

**Features:**
- Supports both short (#123) and full (owner/repo#123) formats
- Context-aware: short references resolve to current repository
- Smart pattern matching to avoid false positives

### 2. Markdown Enhancement (`ui/lib/markdown.ts`)
Updated to detect and link issue references in rendered markdown.

**Changes:**
- Added `owner` and `repo` parameters to `renderMarkdown()`
- Processes issue references after HTML escaping but before other markdown
- Generates links with `.issue-link` class for styling

**Styling:**
- Blue links for issue references
- Line-through styling for closed issues (class: `.issue-link.closed`)

### 3. Markdown Component (`ui/components/Markdown.astro`)
Updated to accept and pass through repository context.

**Props:**
- `content` - Markdown content to render
- `owner` - Repository owner (for resolving #123)
- `repo` - Repository name (for resolving #123)

### 4. IssueReference Component (`ui/components/IssueReference.astro`)
Displays a rich issue reference with state indicator and title.

**Props:**
- `issue` - Issue object with metadata
- `user` - Repository owner
- `repo` - Repository name
- `showState` - Whether to show open/closed state (default: true)

**Display:**
- State badge (open = green, closed = red)
- Issue number (#123)
- Issue title (truncated to 300px)
- Hover effect with border highlight

### 5. Database Schema (`db/migrate-issue-references.sql`)
Tables for tracking cross-references (for future database-backed issues).

**Tables:**
- `issue_references` - Tracks issue-to-issue references
- `comment_references` - Tracks comment-to-issue references

**Features:**
- Prevents duplicate references (UNIQUE constraints)
- Cascading deletes when source/target is deleted
- Indexed for fast lookups

### 6. Reference Tracking (`ui/lib/issue-references.ts`)
Functions for tracking references in the database (future use).

**Functions:**
- `trackIssueReferences()` - Parse and store references from issue body
- `trackCommentReferences()` - Parse and store references from comments
- `getReferencingIssues()` - Get all issues that reference this issue
- `getReferencedIssues()` - Get all issues referenced by this issue

### 7. Reference Parser for Git Issues (`ui/lib/issue-reference-parser.ts`)
Helper for resolving references in git-based issue system.

**Functions:**
- `parseAndResolveReferences()` - Parse and resolve references with metadata
- `findReferencingIssues()` - Find issues referencing a target (stub)

## Usage

### In Issue/Comment Text
Simply type issue references naturally:

```markdown
This fixes #123 and relates to #456.

See also user/repo#789 for more context.
```

These will automatically become clickable links.

### In Components
Pass repository context to Markdown component:

```astro
<Markdown
  content={issue.body}
  owner={username}
  repo={reponame}
/>
```

### Programmatic Parsing
```typescript
import { parseReferences } from "./lib/references";

const refs = parseReferences(
  "Fixes #123 and see user/repo#456",
  "currentUser",
  "currentRepo"
);
// Returns: [
//   { owner: "currentUser", repo: "currentRepo", number: 123, raw: "#123" },
//   { owner: "user", repo: "repo", number: 456, raw: "user/repo#456" }
// ]
```

## Testing

Tests are provided in `ui/lib/references.test.ts`:
- Short format parsing (#123)
- Full format parsing (owner/repo#123)
- Mixed formats
- URL building
- Reference formatting

Run tests:
```bash
bun test ui/lib/references.test.ts
```

## Current Limitations

1. **No Reverse Lookup** - The "Referenced by" section is not yet implemented because:
   - Git-based issues require scanning all issues (expensive)
   - Database tracking requires issues to be synced to PostgreSQL

2. **No Hover Tooltips** - Issue title/state on hover is not yet implemented

3. **No Auto-linking in Timeline** - References in comments don't automatically appear in issue timeline

## Future Enhancements

1. **Timeline Events** - Show when an issue is referenced in timeline
2. **Bidirectional Links** - "Referenced by" section showing reverse references
3. **Hover Tooltips** - Show issue metadata on hover
4. **Cross-Repository Tracking** - Track references across different repositories
5. **Reference Notifications** - Notify users when their issue is referenced
6. **Smart Suggestions** - Auto-complete issue numbers while typing

## Architecture Notes

Plue uses a hybrid architecture:
- Issues are stored in git (`.plue/issues/` directory)
- PostgreSQL is used for indexes, references, and metadata

The reference tracking system is designed to work with both:
- Markdown parsing works immediately with git-based issues
- Database tracking tables are ready for when issues are synced to PostgreSQL

## Files Modified

- `ui/lib/markdown.ts` - Added reference parsing
- `ui/components/Markdown.astro` - Added owner/repo props
- `ui/components/CommentCard.astro` - Pass owner/repo to Markdown
- `ui/pages/[user]/[repo]/issues/[number].astro` - Pass owner/repo to Markdown
- `bunfig.toml` - Fixed test configuration

## Files Created

- `ui/lib/references.ts` - Core reference parser
- `ui/lib/references.test.ts` - Parser tests
- `ui/lib/issue-references.ts` - Database reference tracking
- `ui/lib/issue-reference-parser.ts` - Git-based reference resolution
- `ui/components/IssueReference.astro` - Reference display component
- `db/migrate-issue-references.sql` - Database schema
- `db/migrate-issue-refs.ts` - Migration script
