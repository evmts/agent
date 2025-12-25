# Pages

File-based routing for Plue UI. Each `.astro` file becomes a route.

## Route Structure

```
/                           index.astro
/login                      login.astro
/explore                    explore.astro
/users                      users.astro
/settings                   settings.astro
/settings/tokens            settings/tokens.astro
/settings/ssh-keys          settings/ssh-keys.astro
/sessions                   sessions/index.astro
/sessions/:id               sessions/[id].astro
/:user                      [user]/index.astro
/:user/profile              [user]/profile.astro
/:user/:repo/tree/*         [user]/[repo]/tree/[...path].astro
/:user/:repo/blob/*         [user]/[repo]/blob/[...path].astro
/:user/:repo/commits/*      [user]/[repo]/commits/[...path].astro
/:user/:repo/blame/*        [user]/[repo]/blame/[...path].astro
/:user/:repo/issues         [user]/[repo]/issues/
/:user/:repo/changes        [user]/[repo]/changes/
/:user/:repo/milestones     [user]/[repo]/milestones/
/:user/:repo/workflows      [user]/[repo]/workflows/
```

## Page Categories

### Top-Level Pages
| Page | Purpose |
|------|---------|
| `index.astro` | Landing page |
| `login.astro` | SIWE authentication |
| `explore.astro` | Repository discovery |
| `users.astro` | User directory |
| `settings.astro` | User settings |
| `new.astro` | Create repository |
| `404.astro` | Not found |

### User Pages
| Page | Purpose |
|------|---------|
| `[user]/index.astro` | User profile |
| `[user]/profile.astro` | Profile edit |

### Repository Pages
| Directory | Purpose |
|-----------|---------|
| `[user]/[repo]/tree/` | File browser |
| `[user]/[repo]/blob/` | File viewer |
| `[user]/[repo]/commits/` | Commit history |
| `[user]/[repo]/blame/` | Git blame |
| `[user]/[repo]/issues/` | Issue tracker |
| `[user]/[repo]/changes/` | Pull requests |
| `[user]/[repo]/milestones/` | Milestones |
| `[user]/[repo]/workflows/` | CI/CD workflows |
| `[user]/[repo]/landing/` | Repository landing |

### Settings Pages
| Page | Purpose |
|------|---------|
| `settings/tokens.astro` | API tokens |
| `settings/ssh-keys.astro` | SSH key management |

### Session Pages
| Page | Purpose |
|------|---------|
| `sessions/index.astro` | Active sessions |
| `sessions/[id].astro` | Session details |

## API Routes

REST API endpoints in `api/`:

### Authentication
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/auth/login` | POST | Login (SIWE) |
| `/api/auth/register` | POST | Register |
| `/api/auth/logout` | POST | Logout |
| `/api/auth/me` | GET | Current user |
| `/api/auth/activate` | POST | Activate account |
| `/api/auth/password/reset-request` | POST | Request reset |
| `/api/auth/password/reset-confirm` | POST | Confirm reset |

### Users
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/users/me` | GET | Current user profile |
| `/api/users/me` | PATCH | Update profile |
| `/api/users/me/password` | POST | Change password |
| `/api/users/:username` | GET | User profile |

### Sessions
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/sessions` | GET | List sessions |

### Telemetry
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/telemetry` | POST | Analytics events |

## Dynamic Routes

### Parameters
```astro
---
// pages/[user]/[repo]/blob/[...path].astro
const { user, repo, path } = Astro.params;
---
```

### Catch-All Routes
Use `[...path]` for wildcard matching:
- `tree/[...path].astro` - Matches `/tree/src/file.ts`
- `blob/[...path].astro` - Matches `/blob/docs/README.md`

## SSR (Server-Side Rendering)

All pages are server-rendered by default. No static generation.

### Data Fetching
```astro
---
import { getUser } from '../../lib/auth-helpers';

const user = await getUser(Astro.request);
const data = await fetch('http://localhost:4000/api/...');
---
```

### Redirects
```astro
---
if (!user) {
  return Astro.redirect('/login');
}
---
```

## Middleware

All requests pass through `middleware.ts`:
- SIWE authentication
- Session validation
- Security headers
- Request logging
