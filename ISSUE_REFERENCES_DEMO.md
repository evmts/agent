# Issue Cross-References Demo

## Example Usage

### Basic References

When you type in an issue description or comment:

```markdown
This PR fixes #123 and addresses #456.
```

The references `#123` and `#456` will automatically become clickable links to those issues in the same repository.

### Cross-Repository References

Reference issues in other repositories:

```markdown
See the upstream issue at torvalds/linux#12345
Related to facebook/react#18965
```

These will link to issues in the specified repositories.

### Complex Example

```markdown
# Bug Fix: Memory Leak in Session Handler

## Description
This PR fixes a critical memory leak in the session handler that was
discovered in #789.

## Related Issues
- Fixes #789 (memory leak)
- Closes #790 (performance degradation)
- See also core/session#456 for context

## Testing
Tested with the reproduction case from #789 and confirmed the leak
is resolved.
```

All issue references in this text will be automatically linked:
- `#789` → `/currentUser/currentRepo/issues/789`
- `#790` → `/currentUser/currentRepo/issues/790`
- `core/session#456` → `/core/session/issues/456`

## How It Works

1. **Parsing**: The reference parser scans text for patterns:
   - `#\d+` (short format)
   - `owner/repo#\d+` (full format)

2. **Context Resolution**: Short references (#123) are resolved using the current repository context.

3. **Link Generation**: References are converted to HTML links during markdown rendering.

4. **Styling**: Links are styled to indicate they're issue references, and closed issues can be styled differently.

## Integration Points

### In Astro Components

```astro
---
import Markdown from "./components/Markdown.astro";

const username = "alice";
const reponame = "project";
const issueBody = "This fixes #123 and relates to bob/other#456";
---

<Markdown
  content={issueBody}
  owner={username}
  repo={reponame}
/>
```

Output:
```html
<div class="markdown-body">
  <p>This fixes <a href="/alice/project/issues/123" class="issue-link">#123</a>
  and relates to <a href="/bob/other/issues/456" class="issue-link">bob/other#456</a></p>
</div>
```

### Programmatic Use

```typescript
import { parseReferences } from "./lib/references";

const text = "Fixes #123 and see user/repo#456";
const refs = parseReferences(text, "currentUser", "currentRepo");

refs.forEach(ref => {
  console.log(`Found reference: ${ref.owner}/${ref.repo}#${ref.number}`);
});
```

## CSS Styling

The generated links have the `.issue-link` class:

```css
.issue-link {
  color: #58a6ff;
  text-decoration: none;
  font-weight: 500;
  transition: text-decoration 0.15s ease;
}

.issue-link:hover {
  text-decoration: underline;
}

.issue-link.closed {
  color: #8b949e;
  text-decoration: line-through;
}
```

## Testing Examples

The test suite covers these scenarios:

```typescript
// Short format with context
parseReferences("Fixes #123", "user", "repo")
// → [{ owner: "user", repo: "repo", number: 123 }]

// Full format
parseReferences("See user/repo#456")
// → [{ owner: "user", repo: "repo", number: 456 }]

// Mixed formats
parseReferences("Fixes #123 and see other/repo#456", "current", "repo")
// → [
//   { owner: "current", repo: "repo", number: 123 },
//   { owner: "other", repo: "repo", number: 456 }
// ]

// Multiple references
parseReferences("Issues: #1, #2, #3", "user", "repo")
// → Three references to #1, #2, #3

// Start of line
parseReferences("#123 is the issue", "user", "repo")
// → [{ owner: "user", repo: "repo", number: 123 }]
```

## Common Patterns

### Closing Issues

```markdown
Fixes #123
Closes #456
Resolves #789
```

### Relating Issues

```markdown
Related to #123
See also #456
Depends on #789
```

### Cross-References

```markdown
Duplicate of user/repo#123
Supersedes org/project#456
```

## Browser Experience

When viewing an issue:

1. Issue body is rendered with clickable issue links
2. All comments also have clickable issue links
3. Clicking a link navigates to the referenced issue
4. Links maintain brutalist styling (no unnecessary decorations)

## Performance

- Parsing is done during markdown rendering (server-side)
- No client-side JavaScript required for basic functionality
- Database tracking is optional and asynchronous
- Reference resolution is lazy (only when needed)
