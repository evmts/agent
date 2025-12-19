# Plue MVP Feature List

Based on Gitea feature analysis. Implementation prompts in `docs/prompts/`.

## MVP Features (15 total)

| # | Feature | Prompt | Description |
|---|---------|--------|-------------|
| 01 | Authentication | [01_authentication.md](prompts/01_authentication.md) | Login, register, sessions, API tokens |
| 02 | Pull Requests | [02_pull_requests.md](prompts/02_pull_requests.md) | Create, merge, diff viewing |
| 03 | Branch Management | [03_branch_management.md](prompts/03_branch_management.md) | Create, delete, protect branches |
| 04 | Repository Settings | [04_repository_settings.md](prompts/04_repository_settings.md) | Visibility, delete, collaborators |
| 05 | Code Review | [05_code_review.md](prompts/05_code_review.md) | PR reviews, inline comments, approve/reject |
| 06 | Labels & Milestones | [06_labels_milestones.md](prompts/06_labels_milestones.md) | Issue categorization and tracking |
| 07 | Issue Enhancements | [07_issue_enhancements.md](prompts/07_issue_enhancements.md) | Templates, reactions, assignees, dependencies |
| 08 | File Operations | [08_file_operations.md](prompts/08_file_operations.md) | Create, edit, delete files in browser |
| 09 | Search | [09_search.md](prompts/09_search.md) | Find repos, issues, code, users |
| 10 | Forking | [10_forking.md](prompts/10_forking.md) | Fork repositories |
| 11 | Code Navigation | [11_code_navigation.md](prompts/11_code_navigation.md) | Blame, git graph, file history |
| 12 | Webhooks | [12_webhooks.md](prompts/12_webhooks.md) | Trigger external services on events |
| 13 | CI/CD Actions | [13_cicd_actions.md](prompts/13_cicd_actions.md) | GitHub Actions-style workflows |
| 14 | Security Features | [14_security_features.md](prompts/14_security_features.md) | 2FA, GPG keys, deploy keys |
| 15 | Administration | [15_administration.md](prompts/15_administration.md) | Basic admin dashboard, user management |

## Recommended Implementation Order

**Phase 1 - Core (must have to be usable):**
1. Authentication
2. Pull Requests
3. Branch Management

**Phase 2 - Essential collaboration:**
4. Repository Settings
5. Code Review
6. Labels & Milestones

**Phase 3 - Quality of life:**
7. Issue Enhancements
8. File Operations
9. Search
10. Forking

**Phase 4 - Power features:**
11. Code Navigation
12. Webhooks
13. CI/CD Actions
14. Security Features
15. Administration

## Removed from Gitea (not in MVP)

- Wiki (separate repo, not useful)
- Tags & Releases (can add later)
- Activity & Notifications (can add later)
- Organizations & Teams (can add later)
- Package Registry (npm/Docker - can add later)
- Starring, topics, language stats, license detection

## Plue Unique Features (already have)

- Integrated AI Agent (Claude-powered)
- Real-time PTY terminal sessions
- Session fork/revert/undo
- Multi-agent architecture
