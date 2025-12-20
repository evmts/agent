# Issue Cross-References Architecture

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│ User Types Issue/Comment                                    │
│ "This fixes #123 and relates to user/repo#456"             │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Issue Detail Page                                           │
│ [user]/[repo]/issues/[number].astro                        │
│                                                             │
│ Passes text + context to Markdown component:               │
│ <Markdown content={body} owner={user} repo={repo} />       │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Markdown Component                                          │
│ components/Markdown.astro                                   │
│                                                             │
│ Calls renderMarkdown(content, owner, repo)                 │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Markdown Renderer                                           │
│ lib/markdown.ts                                            │
│                                                             │
│ 1. Escape HTML                                             │
│ 2. Parse issue references:                                 │
│    - Regex: ([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+)#(\d+)      │
│    - Regex: #(\d+)                                         │
│ 3. Replace with HTML links:                                │
│    <a href="/owner/repo/issues/123" class="issue-link">    │
│ 4. Process other markdown (headers, lists, etc.)          │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Rendered HTML                                               │
│                                                             │
│ <div class="markdown-body">                                │
│   <p>This fixes                                            │
│     <a href="/user/repo/issues/123" class="issue-link">    │
│       #123                                                  │
│     </a>                                                    │
│     and relates to                                          │
│     <a href="/user/repo/issues/456" class="issue-link">    │
│       user/repo#456                                         │
│     </a>                                                    │
│   </p>                                                      │
│ </div>                                                      │
└─────────────────────────────────────────────────────────────┘
```

## Component Hierarchy

```
Issue Detail Page
├── Header
├── Breadcrumb
├── Navigation
└── Container
    ├── Issue Header
    │   ├── Title
    │   └── State Badge
    ├── Issue Layout
    │   ├── Issue Main
    │   │   ├── Issue Body Comment
    │   │   │   └── Markdown Component ← Renders references
    │   │   ├── Comment Cards
    │   │   │   └── Markdown Component ← Renders references
    │   │   └── Add Comment Form
    │   └── Issue Sidebar
    │       ├── Assignees
    │       ├── Labels
    │       ├── Milestone
    │       └── Notifications
    └── Footer
```

## Reference Parsing Logic

### Step 1: Pattern Matching

```typescript
// Full format: owner/repo#123
/([a-zA-Z0-9_-]+)\/([a-zA-Z0-9_-]+)#(\d+)/g

// Short format: #123
/(?:^|[\s([{])(#(\d+))(?=$|[\s)\]}.,;!?])/gm
```

### Step 2: Context Resolution

```typescript
if (owner && repo) {
  // Full reference
  "user/repo#123" → { owner: "user", repo: "repo", number: 123 }

  // Short reference (uses context)
  "#123" → { owner: currentOwner, repo: currentRepo, number: 123 }
}
```

### Step 3: Link Generation

```typescript
// Full reference
{ owner: "user", repo: "repo", number: 123 }
→ <a href="/user/repo/issues/123" class="issue-link">user/repo#123</a>

// Short reference
{ owner: "current", repo: "current", number: 123 }
→ <a href="/current/current/issues/123" class="issue-link">#123</a>
```

## Database Schema (Future)

```sql
┌──────────────────────────────────────────────────┐
│ issues                                           │
├──────────────────────────────────────────────────┤
│ id (PK)                                          │
│ repository_id (FK → repositories)                │
│ issue_number                                     │
│ title                                            │
│ body                                             │
│ state                                            │
└──────────────────────┬───────────────────────────┘
                       │
                       │ Referenced by
                       ▼
┌──────────────────────────────────────────────────┐
│ issue_references                                 │
├──────────────────────────────────────────────────┤
│ id (PK)                                          │
│ source_issue_id (FK → issues)                    │
│ target_issue_id (FK → issues)                    │
│ created_at                                       │
│ UNIQUE(source_issue_id, target_issue_id)        │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│ comments                                         │
├──────────────────────────────────────────────────┤
│ id (PK)                                          │
│ issue_id (FK → issues)                           │
│ author_id (FK → users)                           │
│ body                                             │
└──────────────────────┬───────────────────────────┘
                       │
                       │ References
                       ▼
┌──────────────────────────────────────────────────┐
│ comment_references                               │
├──────────────────────────────────────────────────┤
│ id (PK)                                          │
│ comment_id (FK → comments)                       │
│ target_issue_id (FK → issues)                    │
│ created_at                                       │
│ UNIQUE(comment_id, target_issue_id)             │
└──────────────────────────────────────────────────┘
```

## Reference Tracking Flow (Database)

```
Issue Created with Body: "Fixes #123"
    │
    ▼
Parse References
    │
    ├─→ Find target issue #123
    │   in database
    │
    ▼
Insert into issue_references
    │
    ├─→ source_issue_id: current issue
    └─→ target_issue_id: issue #123

Later: View Issue #123
    │
    ▼
Query issue_references
    │
    └─→ WHERE target_issue_id = 123
    │
    ▼
Display "Referenced by" section
    │
    └─→ Show current issue as referencing #123
```

## Styling System

```css
/* Reference Links */
.issue-link {
  color: #58a6ff;           /* Blue */
  text-decoration: none;
  font-weight: 500;
}

.issue-link:hover {
  text-decoration: underline;
}

/* Closed Issues */
.issue-link.closed {
  color: #8b949e;           /* Gray */
  text-decoration: line-through;
}

/* Issue Reference Component */
.issue-ref {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  border: 1px solid var(--border);
  border-radius: var(--radius);
}

.ref-state.open {
  background: rgba(46, 160, 67, 0.15);  /* Green */
  color: rgb(46, 160, 67);
}

.ref-state.closed {
  background: rgba(215, 58, 73, 0.15);  /* Red */
  color: rgb(215, 58, 73);
}
```

## Git-Based Storage

Issues are stored in `.plue/issues/` directory:

```
.plue/issues/
├── config.yaml              # Issue counter
├── 1/                       # Issue #1
│   ├── issue.md            # Issue metadata + body
│   └── comments/
│       ├── 1.md            # Comment #1
│       └── 2.md            # Comment #2
├── 2/                       # Issue #2
│   ├── issue.md
│   └── comments/
└── 123/                     # Issue #123
    ├── issue.md
    └── comments/
```

Each `issue.md` contains:
```yaml
---
id: 123
title: "Fix memory leak"
state: open
author:
  id: 1
  username: alice
created_at: 2025-12-19T10:00:00Z
updated_at: 2025-12-19T10:00:00Z
closed_at: null
labels: [bug, critical]
assignees: [bob]
---

Body text with references to #456 and user/repo#789
```

## Performance Considerations

1. **Parsing**: Done during markdown rendering (server-side)
   - No client-side JavaScript needed
   - Cached as part of rendered HTML

2. **Reference Resolution**: Lazy
   - Basic links work immediately
   - Metadata (title, state) fetched only when needed

3. **Database Tracking**: Asynchronous
   - Doesn't block issue creation
   - Can be rebuilt from git history

4. **Query Optimization**: Indexed
   - `idx_issue_references_source`
   - `idx_issue_references_target`
   - Fast lookups for "Referenced by" queries

## Security

1. **XSS Prevention**:
   - All text is HTML-escaped before processing
   - Links are generated, not embedded from user input

2. **Access Control**:
   - Issue visibility follows repository permissions
   - Private repo issues not linkable from public repos

3. **Rate Limiting**:
   - Database queries limited per request
   - Reference parsing capped at reasonable limits

## Testing Strategy

1. **Unit Tests** (`references.test.ts`)
   - Pattern matching
   - Context resolution
   - URL building

2. **Integration Tests** (future)
   - End-to-end link generation
   - Cross-repository references
   - Database tracking

3. **Manual Testing**
   - Create issues with references
   - Verify links are clickable
   - Check styling
