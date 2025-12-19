# Plue vs Gitea Feature Gap Analysis

## Current State

**Plue** is a "brutalist GitHub clone" with AI agent integration focused on:
- Basic repository browsing (file tree, commits, file viewer)
- Basic issue tracking (list, create, comment, close/reopen)
- AI agent system with 9 tools for autonomous development
- Real-time PTY terminal sessions

**Gitea** is a full-featured self-hosted Git forge with enterprise capabilities.

---

## Missing Features (Organized by Priority)

### 🔴 Critical (Core Git Forge Functionality)

#### 1. Authentication & Authorization
- [ ] User registration/login system
- [ ] Session management with cookies/JWT
- [ ] OAuth2/SSO integration (GitHub, Google, etc.)
- [ ] API token management with scopes
- [ ] SSH key management for git operations
- [ ] Password reset/recovery
- [ ] Email verification

#### 2. Pull Requests
- [ ] PR creation from branch comparisons
- [ ] PR listing and filtering
- [ ] Diff viewer for PRs
- [ ] Merge operations (merge, squash, rebase, fast-forward)
- [ ] PR status (open, merged, closed, draft)
- [ ] Merge conflict detection
- [ ] Target branch selection

#### 3. Branch Management (via UI)
- [ ] Create branch from web UI
- [ ] Delete branch from web UI
- [ ] Branch listing page
- [ ] Branch protection rules
- [ ] Default branch configuration

#### 4. Repository Settings
- [ ] Repository settings page
- [ ] Visibility toggle (public/private)
- [ ] Repository deletion
- [ ] Repository transfer
- [ ] Collaborator management

---

### 🟠 Important (Expected Features)

#### 5. Code Review
- [ ] PR review workflow (approve, request changes, comment)
- [ ] Inline code comments on diffs
- [ ] Review threads and resolution
- [ ] Required reviewers

#### 6. Labels & Milestones
- [ ] Label CRUD (create, edit, delete)
- [ ] Label assignment to issues
- [ ] Milestone CRUD
- [ ] Milestone assignment
- [ ] Milestone progress tracking

#### 7. Issue Enhancements
- [ ] Issue templates
- [ ] Issue reactions (emoji)
- [ ] Issue assignees (multiple)
- [ ] Issue dependencies (blocks/blocked by)
- [ ] Issue locking
- [ ] Issue pinning

#### 8. Tags & Releases
- [ ] Tag listing page
- [ ] Release creation with notes
- [ ] Release asset uploads
- [ ] Release downloads
- [ ] Changelog generation

#### 9. File Operations (via UI)
- [ ] Create new file
- [ ] Edit file inline
- [ ] Delete file
- [ ] Upload files
- [ ] Raw file download
- [ ] Archive download (zip/tar.gz)

#### 10. Search
- [ ] Global search bar
- [ ] Repository search
- [ ] Issue search with filters
- [ ] Code search
- [ ] User search

---

### 🟡 Nice to Have (Enhanced Experience)

#### 11. Activity & Notifications
- [ ] Activity feed (home dashboard)
- [ ] User activity/contribution graph
- [ ] Repository activity feed
- [ ] Notification system (in-app)
- [ ] Email notifications
- [ ] Watch/unwatch repositories

#### 12. Organizations & Teams
- [ ] Organization creation
- [ ] Organization profile page
- [ ] Team management
- [ ] Team-based permissions
- [ ] Organization settings

#### 13. Repository Enhancements
- [ ] Repository forking
- [ ] Repository starring
- [ ] Repository topics/tags
- [ ] Language statistics bar
- [ ] License detection
- [ ] README rendering improvements
- [ ] .gitignore templates
- [ ] Repository templates

#### 14. Code Navigation
- [ ] Blame view
- [ ] Git graph visualization
- [ ] Commit comparison
- [ ] File history
- [ ] Jump to definition (with LSP)

#### 15. Webhooks
- [ ] Webhook CRUD
- [ ] Event type selection
- [ ] Webhook delivery history
- [ ] Webhook testing

---

### 🟢 Advanced (Enterprise/Power User)

#### 16. CI/CD (Actions)
- [ ] Workflow YAML support
- [ ] Workflow execution
- [ ] Job/step visualization
- [ ] Runner management
- [ ] Secrets management
- [ ] Artifacts
- [ ] Status checks for PRs

#### 17. Wiki
- [ ] Wiki page CRUD
- [ ] Wiki navigation/sidebar
- [ ] Wiki search
- [ ] Wiki history

#### 18. Security Features
- [ ] Two-factor authentication (TOTP)
- [ ] GPG key management
- [ ] Signed commits verification
- [ ] Deploy keys
- [ ] Audit logs

#### 19. Package Registry
- [ ] NPM registry
- [ ] Container registry (Docker)
- [ ] Other package formats

#### 20. Administration
- [ ] Admin dashboard
- [ ] User management
- [ ] System settings
- [ ] Database maintenance
- [ ] Backup/restore

---

## Quick Reference: What Plue Has vs Missing

| Feature | Plue | Gitea |
|---------|------|-------|
| Repository browsing | ✅ | ✅ |
| File tree | ✅ | ✅ |
| Commit history | ✅ | ✅ |
| File viewer | ✅ | ✅ |
| Issues (basic) | ✅ | ✅ |
| Issue comments | ✅ | ✅ |
| AI Agent | ✅ | ❌ |
| PTY Terminal | ✅ | ❌ |
| Authentication | ❌ | ✅ |
| Pull Requests | ❌ | ✅ |
| Code Review | ❌ | ✅ |
| Branch Management | ❌ | ✅ |
| Labels/Milestones | ❌ | ✅ |
| Releases | ❌ | ✅ |
| Search | ❌ | ✅ |
| Organizations | ❌ | ✅ |
| CI/CD | ❌ | ✅ |
| Webhooks | ❌ | ✅ |
| Wiki | ❌ | ✅ |
| Package Registry | ❌ | ✅ |

---

## Recommended Implementation Order

1. **Authentication** - Foundation for everything else
2. **Pull Requests** - Core collaboration feature
3. **Branch Management** - Essential for PR workflow
4. **Labels & Milestones** - Issue organization
5. **Releases** - Software distribution
6. **Search** - Discoverability
7. **Organizations** - Team collaboration
8. **Webhooks** - Integration capabilities
9. **CI/CD** - Automation
10. **Package Registry** - Artifact management

---

## Unique Plue Advantages

Plue has features Gitea doesn't:

1. **Integrated AI Agent** - Claude-powered autonomous development
2. **Real-time PTY Sessions** - Interactive terminal in browser
3. **Session Management** - Fork, revert, undo conversation states
4. **Multi-agent Architecture** - Specialized agents (build, explore, plan)
5. **Read-before-write Safety** - File modification tracking
