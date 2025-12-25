# Components

Astro components for Plue UI. All components are server-rendered with optional client-side interactivity.

## Component Categories

### Repository UI
| Component | Purpose |
|-----------|---------|
| `RepoCard.astro` | Repository list item |
| `FileTree.astro` | Directory browser |
| `FileViewer.astro` | File content display |
| `BlameView.astro` | Git blame with commit info |
| `DiffView.astro` | Unified diff viewer |
| `FileDiffCard.astro` | Pull request file diff |
| `CommitList.astro` | Commit history |
| `CommitStatus.astro` | Commit status badge |

### Issues & Pull Requests
| Component | Purpose |
|-----------|---------|
| `IssueCard.astro` | Issue/PR list item |
| `IssueSidebar.astro` | Issue metadata sidebar |
| `IssueFilters.astro` | Filter UI for issues |
| `IssueReference.astro` | Cross-reference display |
| `IssueDependencies.astro` | Dependency graph |
| `MilestoneCard.astro` | Milestone display |
| `StatusChecks.astro` | CI/CD status |

### Comments & Markdown
| Component | Purpose |
|-----------|---------|
| `CommentCard.astro` | Comment display |
| `LineComment.astro` | Inline code comment |
| `MarkdownEditor.astro` | Rich markdown editor |
| `Markdown.astro` | Markdown renderer |
| `MentionAutocomplete.astro` | @mention completion |
| `EmojiPicker.astro` | Emoji selection |
| `Reactions.astro` | Comment reactions |

### Workflows
| Component | Purpose |
|-----------|---------|
| `WorkflowRunCard.astro` | Workflow run summary |
| `WorkflowStatusBadge.astro` | Status indicator |
| `WorkflowLogs.astro` | Execution logs |

### UI Framework
| Component | Purpose |
|-----------|---------|
| `Header.astro` | Site header/navigation |
| `Footer.astro` | Site footer |
| `TabNav.astro` | Tab navigation |
| `Pagination.astro` | Page controls |
| `Avatar.astro` | User avatar |
| `Toast.astro` | Notification toast |
| `ToastContainer.astro` | Toast manager |
| `RelativeTime.astro` | Time formatting |
| `ReloadPrompt.astro` | PWA update prompt |
| `TopicBadge.astro` | Topic tag |
| `ActivityItem.astro` | Activity feed item |

## Component Patterns

### Server-Side Rendering
All components are Astro components (`.astro`) rendered on the server. Client-side JavaScript is minimal and progressive.

### Props Interface
```astro
---
interface Props {
  // Define component props
}
const { prop1, prop2 } = Astro.props;
---
```

### Client Interactivity
Use `<script>` tags for client-side behavior:
```astro
<script>
  // Runs once on page load
</script>
```

### Styling
Scoped styles per component:
```astro
<style>
  /* Scoped to this component */
</style>
```

## Dependencies

Components rely on:
- `lib/` - Shared utilities and types
- `layouts/Layout.astro` - Page wrapper
- Zig API server at `localhost:4000`
