NOTE: Legacy document. This PRD predates the current Zig + workflows architecture. For current sources of truth, see `docs/workflows-prd.md` and `docs/workflows-engineering.md`.

Below is a full end-to-end specification for a **single-project, self-hosted Git forge** (a minimal “Gitea-like” backend) built in **TypeScript**, with **local-first metadata** via **ElectricSQL**, and **standard Git clients** for clone/fetch/push over SSH.

This spec is written so you can implement it incrementally while keeping the architecture coherent.

---

# 1) Product overview

## 1.1 What we’re building

A self-hosted system for a team of up to ~100 users working on **one Git project**. The system provides:

- **Git hosting** (clone/fetch/push) via SSH using standard Git tooling (`git-upload-pack`, `git-receive-pack`). ([Git][1])
- A **forge backend** (auth, membership, roles, branch protection, event feed, code browsing APIs, comments/discussions, webhooks).
- A **local-first client experience for forge data** (membership, discussions, settings, activity, notifications) using ElectricSQL shapes (read-path sync) with an authorizing proxy + gatekeeper. ([Electric SQL][2])
- A **minimal functional UI** spec (enough to use the system without building a full GitHub clone).

## 1.2 Design principles

1. **Keep Git transport boring and proven**: use SSH to invoke upload/receive-pack rather than implementing Git protocols yourself. ([Git][1])
2. **Treat Electric as read-path sync**: clients sync subsets (“shapes”) out of Postgres; you implement the write path (mutations) explicitly. Electric’s primitives are “shapes” and the HTTP shape API. ([Electric SQL][3])
3. **Local-first means the UI is backed by a local DB** and works offline for forge metadata; Git itself is inherently local-first (working copy + history local) and remains standard.

---

# 2) Scope

## 2.1 In-scope (v1)

**Access + project**

- Users (login), membership for a single project
- Roles: **Reader**, **Writer**, **Admin**

**Git**

- Clone/fetch/push via SSH
- Protected branches + basic server-side enforcement
- Post-receive event generation (“push happened”)

**Forge metadata (local-first)**

- User directory + membership
- Activity feed (push events, settings changes)
- Discussions: comment threads attached to commits or file+line anchors
- Notifications (mention / thread updates)
- Webhooks (admin-only)

**Code browsing**

- List branches/tags
- Commit list + commit detail
- Tree + blob read
- Diffs (commit diff, compare two refs)

## 2.2 Explicitly out-of-scope (v1)

- Pull requests / merge requests
- CI/CD runner
- Issue tracker
- Multi-repo / multi-project hosting
- Advanced policy (CODEOWNERS, required approvals, signed commits)
- LFS (can be added later)

---

# 3) Architecture

## 3.1 Component diagram

**Data plane (Electric)**

- Postgres = source of truth for forge metadata
- Electric sync service sits “in front of Postgres” and exposes an HTTP API for syncing shapes. ([Electric SQL][4])
- Electric’s HTTP API is **public by default**; production deployments should secure it via **API token + network rules + authorizing proxy**. ([Electric SQL][4])

**Control plane (Forge API)**

- TypeScript backend that:

  - authenticates users
  - authorizes data access
  - proxies and validates shape requests (Gatekeeper pattern)
  - accepts writes (mutations) and applies them to Postgres

**Git plane**

- SSH front door that:

  - authenticates using user SSH keys
  - authorizes pushes/fetches based on your Postgres roles/policies
  - execs `git-upload-pack` / `git-receive-pack` against a bare repo directory. ([Git][1])

## 3.2 Electric auth pattern

Use **Gatekeeper + Authorizing Proxy**:

- Gatekeeper endpoint issues **shape-scoped JWT** containing the authorized shape definition.
- Proxy endpoint validates the JWT and verifies the client is requesting **exactly the same shape** authorized by the gatekeeper. ([Electric SQL][2])
  This keeps heavy auth logic off the “hot path” of every streaming request. ([Electric SQL][2])

## 3.3 Electric “secret” token handling

Electric can be secured with an API token passed as a `secret` query parameter; **do not send it to clients**. Add it server-side in the proxy. ([Electric SQL][4])

---

# 4) Data model (Postgres)

> Note: Electric shapes are **single-table** and shape definitions are **immutable**, so you will sync multiple shapes (one per table or per filtered subset). ([Electric SQL][3])

## 4.1 Core tables

### `users`

- `id uuid pk`
- `email text unique`
- `handle text unique`
- `display_name text`
- `password_hash text` (or `oidc_sub text`)
- `created_at timestamptz`
- `status text` (`active|disabled`)

### `project` (single row for v1)

- `id uuid pk`
- `slug text unique`
- `name text`
- `repo_path text` (absolute path to bare repo)
- `default_branch text`
- `created_at timestamptz`

### `memberships`

- `project_id uuid fk`
- `user_id uuid fk`
- `role text` (`reader|writer|admin`)
- `created_at timestamptz`
  Primary key: `(project_id, user_id)`

### `ssh_keys`

- `id uuid pk`
- `user_id uuid fk`
- `public_key text`
- `fingerprint text unique`
- `label text`
- `created_at timestamptz`
- `revoked_at timestamptz null`

### `branch_protection`

- `id uuid pk`
- `project_id uuid fk`
- `pattern text` (e.g., `main`, `release/*`)
- `allow_force_push boolean default false`
- `allow_delete boolean default false`
- `restrict_push_to_role text` (`writer|admin`)
- `created_at timestamptz`

### `events`

Append-only activity stream.

- `id uuid pk`
- `project_id uuid fk`
- `type text` (`push|settings_change|membership_change|webhook_delivery|comment_created|…`)
- `actor_user_id uuid fk null` (null for system)
- `created_at timestamptz`
- `payload jsonb`

### `threads`

Discussion thread anchor.

- `id uuid pk`
- `project_id uuid fk`
- `anchor_type text` (`commit|file_line`)
- `anchor jsonb`

  - commit anchor: `{ "commit": "<sha>" }`
  - file line anchor: `{ "commit": "<sha>", "path": "src/a.ts", "line": 123 }`

- `status text` (`open|resolved`)
- `created_by uuid fk`
- `created_at timestamptz`

### `comments`

- `id uuid pk`
- `thread_id uuid fk`
- `project_id uuid fk`
- `author_id uuid fk`
- `body text`
- `created_at timestamptz`
- `edited_at timestamptz null`
- `deleted_at timestamptz null`

### `mentions`

- `id uuid pk`
- `comment_id uuid fk`
- `mentioned_user_id uuid fk`
- `created_at timestamptz`

### `notifications`

- `id uuid pk`
- `user_id uuid fk`
- `type text` (`mention|thread_update|system`)
- `created_at timestamptz`
- `read_at timestamptz null`
- `payload jsonb`

### `webhooks`

- `id uuid pk`
- `project_id uuid fk`
- `url text`
- `secret text`
- `events text[]` (event types)
- `active boolean`
- `created_at timestamptz`

### `webhook_deliveries`

- `id uuid pk`
- `webhook_id uuid fk`
- `event_id uuid fk`
- `status text` (`pending|success|failed`)
- `attempts int`
- `next_retry_at timestamptz null`
- `last_error text null`
- `created_at timestamptz`

---

# 5) Shapes (Electric read-path sync)

## 5.1 Shape definition constraints

Shapes are defined by **table** plus optional **where** and **columns** selection; they are currently **single-table** and definitions are **immutable**. ([Electric SQL][3])

## 5.2 Required shapes (v1)

Below is a minimal set that keeps clients functional offline for forge metadata.

### Shape: `memberships_by_project`

- table: `memberships`
- where: `project_id = :PROJECT_ID`
- columns: all

### Shape: `users_public`

- table: `users`
- where: `status = 'active'`
- columns: `id, handle, display_name, status`

### Shape: `ssh_keys_by_user`

- table: `ssh_keys`
- where: `user_id = :CURRENT_USER_ID AND revoked_at IS NULL`
- columns: `id, label, fingerprint, created_at, public_key`

### Shape: `branch_protection`

- table: `branch_protection`
- where: `project_id = :PROJECT_ID`
- columns: all

### Shape: `threads`

- table: `threads`
- where: `project_id = :PROJECT_ID`
- columns: all

### Shape: `comments`

- table: `comments`
- where: `project_id = :PROJECT_ID AND deleted_at IS NULL`
- columns: all

### Shape: `notifications_by_user`

- table: `notifications`
- where: `user_id = :CURRENT_USER_ID`
- columns: all

### Shape: `events_recent`

Options:

- **Simplest**: sync all events (may grow).
- **Recommended**: keep `events` retention bounded (e.g., 30–90 days) and sync the whole table.

(If you want strict “recent only” without dynamic `now()` in an immutable where clause, implement retention/archival at the DB layer.)

---

# 6) Gatekeeper + Proxy endpoints

## 6.1 Gatekeeper contract

Electric’s gatekeeper flow is:

1. client POSTs to gatekeeper to obtain a **shape-scoped token**
2. client requests the shape through an **authorizing proxy** that validates token and request params match exactly. ([Electric SQL][2])

### Endpoint

`POST /gatekeeper/shapes`

**Request**

```json
{
  "shape": {
    "table": "comments",
    "where": "project_id = '…' AND deleted_at IS NULL",
    "columns": [
      "id",
      "thread_id",
      "author_id",
      "body",
      "created_at",
      "edited_at"
    ]
  }
}
```

**Gatekeeper behavior**

- Authenticate user session/JWT
- Compute allowed shape(s) based on:

  - membership role
  - admin-only tables (webhooks, deliveries)

- Validate requested shape is a subset of policy (or ignore client where entirely and generate canonical server-side where/columns).
- Mint JWT with claim:

  - `shape: { table, where, columns, replica? }`
  - `sub: user_id`
  - `exp`

**Response**

```json
{
  "proxyUrl": "https://forge.example.com/proxy/v1/shape",
  "headers": { "Authorization": "Bearer <shape-jwt>" }
}
```

## 6.2 Proxy endpoint

`GET /proxy/v1/shape?...` (same query params as Electric)

**Proxy behavior**

- Verify Authorization JWT
- Compare shape claim with request parameters:

  - table, where, columns, replica must match (byte-for-byte normalization rules required)

- Append Electric API token (`secret=...`) server-side; Electric docs describe using an API token and that it should be added by the authorizing proxy. ([Electric SQL][4])
- Forward request to Electric `/v1/shape`
- Stream response back to client

---

# 7) Client sync model (TypeScript)

Electric’s TypeScript client primitives:

- `ShapeStream` streams logical ops for a shape
- `Shape` materializes it and provides `rows` and subscription callbacks ([Electric SQL][5])

## 7.1 Client local storage

Use **SQLite** locally:

- Desktop: on-disk SQLite
- Web: SQLite WASM (or an equivalent embedded SQLite)

Client maintains:

- `remote_*` tables: last-known server state (materialized from shapes)
- `local_*` tables: local-first state including pending writes (optional)
- `outbox` table: queued mutations awaiting server apply
- `sync_state` table: per-shape offsets/checkpoints

---

# 8) Write-path design (local-first)

Electric is a read-path engine; handling offline writes requires explicit patterns. The Electric “Writes” guide describes multiple patterns and calls out that full local-first (“through-the-database sync”) increases complexity, especially around merge logic and rollbacks. ([Electric SQL][6])

You have two viable approaches. This spec chooses **Approach A** for v1 because it is robust and implementable; **Approach B** is a planned upgrade if you want “pure DB-only local programming model”.

## 8.1 Approach A (recommended v1): Outbox + optimistic local tables

### Client-side

- When user creates/edits data (comment/thread/etc.):

  1. write to local DB immediately (`local_*`), mark as `pending=true`
  2. enqueue a row in `outbox` with:

     - `mutation_id (uuid)`
     - `type`
     - `payload`
     - `created_at`
     - `attempts`

- Background worker sends mutations when online.

### Server-side

- `POST /mutations/batch`
- Each mutation:

  - authenticated user
  - validated for authorization + schema
  - applied transactionally to Postgres
  - emits an `events` row

Once Postgres updates, Electric streams changes to all clients; the originating client reconciles by:

- matching `client_generated_id` / `mutation_id`
- clearing `pending` on local rows
- or applying server canonical row if ids differ

### Rejections

If server rejects a mutation (e.g., permission denied, invalid anchor):

- client marks mutation as `rejected`
- UI surfaces “Needs attention” and offers:

  - discard local change
  - retry (if transient)
  - copy text and recreate

This aligns with Electric’s discussion that rollback handling becomes important when offline writes exist. ([Electric SQL][6])

## 8.2 Approach B (v2): Through-the-database sync

Electric describes a pattern where app code talks only to local embedded DB and sync runs in background, providing “pure local-first” at the cost of additional complexity (shadow tables, triggers, merge/rollback challenges). ([Electric SQL][6])

If you want this later:

- implement DB triggers to write to a local changelog table
- have a sync utility push changelog to server and apply merges
- implement conflict-rebase logic and nuanced rollback instead of clearing everything (Electric notes naive rollbacks are possible but not ideal). ([Electric SQL][6])

---

# 9) Forge API specification (TypeScript)

## 9.1 Authentication

### Endpoints

- `POST /auth/login` → session cookie or JWT
- `POST /auth/logout`
- `GET /me`

### Auth model

- Use JWT access tokens (15 min) + refresh token (httpOnly cookie)
- `sub=user_id`

## 9.2 Membership + roles

- `GET /project` → project metadata (slug, default branch)
- `GET /project/members` (admin) → list members + roles
- `PUT /project/members/:userId` (admin) → set role
- `DELETE /project/members/:userId` (admin)

## 9.3 SSH key management

- `GET /me/ssh-keys`
- `POST /me/ssh-keys`
- `DELETE /me/ssh-keys/:id`

Server writes `events` on add/revoke.

## 9.4 Discussions

- `GET /threads?anchor_type=&anchor=` (optional; local-first will rely mostly on shapes)
- `POST /threads`
- `POST /threads/:id/comments`
- `PATCH /comments/:id`
- `DELETE /comments/:id` (soft delete)

## 9.5 Notifications

- `POST /notifications/:id/read`
- Optional: `POST /notifications/read-all`

## 9.6 Webhooks (admin)

- `GET /webhooks`
- `POST /webhooks`
- `PATCH /webhooks/:id`
- `DELETE /webhooks/:id`
- `GET /webhooks/:id/deliveries`

## 9.7 Mutations (write-path)

- `POST /mutations/batch`

**Request**

```json
{
  "deviceId": "uuid",
  "mutations": [
    {
      "id": "uuid",
      "type": "comment.create",
      "baseVersion": 0,
      "payload": {
        "threadId": "uuid",
        "clientCommentId": "uuid",
        "body": "…"
      }
    }
  ]
}
```

**Response**

```json
{
  "results": [
    { "id": "uuid", "status": "applied", "serverIds": { "commentId": "uuid" } }
  ]
}
```

**Idempotency**

- `(user_id, device_id, mutation_id)` unique constraint
- Replays return same result

---

# 10) Git transport specification

## 10.1 Why SSH forced command

Git’s SSH transport is effectively remote execution of `git-upload-pack` and `git-receive-pack` on the server, then the client speaks the pack protocol over the SSH channel. ([Git][1])

This allows you to:

- use standard Git tooling
- centralize authorization checks
- avoid writing a custom Git server

## 10.2 SSH entrypoint: `git-ssh-bridge`

A small executable/script invoked by sshd forced command.

**Input**

- `SSH_ORIGINAL_COMMAND` like:

  - `git-upload-pack 'project.git'`
  - `git-receive-pack 'project.git'`

**Algorithm**

1. Identify user from SSH key fingerprint (look up in Postgres)
2. Parse command:

   - upload-pack = read access required
   - receive-pack = write access required ([Git][7])

3. Enforce branch protections on receive-pack:

   - pre-receive hook receives ref updates; validate:

     - deny force pushes if `allow_force_push=false`
     - deny delete if `allow_delete=false`
     - restrict pushes to role >= configured

4. Exec the git command against the bare repo path:

   - `git-upload-pack /repos/project.git` ([Git][8])
   - `git-receive-pack /repos/project.git` ([Git][7])

## 10.3 Hooks

### `pre-receive`

- reads stdin lines: `<old> <new> <ref>`
- runs protection checks
- rejects with clear message on stderr

### `post-receive`

- generates a `push` event:

  - actor user id
  - ref updates
  - list of new commits (optional; can be computed lazily)

- enqueues webhook deliveries

---

# 11) Repo browsing APIs

These are for your minimal UI. Implementation can shell out to `git` against the bare repo (recommended for correctness). Git’s upload-pack/receive-pack are protocol-side; browsing can use `git cat-file`, `git rev-list`, `git diff`, etc.

### Endpoints

- `GET /git/refs` → branches/tags
- `GET /git/commits?ref=main&limit=50`
- `GET /git/commit/:sha`
- `GET /git/tree?ref=:sha&path=...`
- `GET /git/blob?ref=:sha&path=...`
- `GET /git/diff?base=:sha&head=:sha`

### Caching

- Cache tree listings and commit pages in memory (LRU) or Redis
- Cache invalidated on push events

---

# 12) Minimal functional UI product spec

This is deliberately minimal but “complete enough” to operate the forge.

## 12.1 UI goals

- Users can:

  - authenticate
  - configure SSH keys
  - clone/push using Git
  - browse code + history
  - discuss code via threads/comments
  - see activity
  - admins can manage membership and policies

## 12.2 Primary screens

### A) Login

- Email + password (or SSO)
- Shows connection status:

  - “Online / syncing”
  - “Offline / using local data” (local-first expectation)

### B) Project Home (single project dashboard)

Panels:

- “Recent activity” (from `events` shape)
- “My notifications” (from `notifications` shape)
- “Branches” quick list (from browse API or cached)

Offline behavior:

- Still shows last-synced activity and notifications (local DB)
- If offline and no cached code data: show “code browsing unavailable offline” unless local repo integration exists

### C) Code Browser

- Left: tree
- Main: file view
- Top: branch selector, commit selector
- “Copy clone URL” (ssh)

Interactions:

- Open file at a commit
- Jump to commit history for a file
- Create a discussion thread on a line (right-click / gutter icon)

### D) Commit View

- Commit metadata
- Diff
- Threads attached to this commit and inline threads

### E) Discussions

- Thread list (open/resolved)
- Filter by: author, status, anchor type
- Thread detail: comments, resolve/unresolve

Offline behavior:

- Creating a comment works offline:

  - comment appears immediately
  - marked “Pending sync”
  - once applied, pending badge clears
  - if rejected, show “Rejected” with details and an action to copy/retry

### F) Settings (User)

- SSH keys:

  - add key, list keys, revoke

- API tokens (optional)

### G) Admin Settings (Project)

- Members: add/remove, set role
- Branch protection rules
- Webhooks: create, disable, see deliveries

## 12.3 Minimal UX requirements for local-first

- Global status indicator:

  - Online + last sync time
  - Offline
  - Sync error state

- “Pending changes” panel:

  - outbox queue size
  - per-item retry/discard

---

# 13) Security requirements

## 13.1 Electric exposure

- Electric HTTP API is public by default; secure via:

  - network controls
  - API token
  - authorizing proxy ([Electric SQL][4])

- API token (`secret`) must be injected by proxy, not stored in client. ([Electric SQL][4])

## 13.2 Data authorization

- Gatekeeper enforces per-role access to shapes, and proxy ensures a client can only request the authorized shape. ([Electric SQL][2])
- Admin-only tables: webhooks, deliveries, membership management.

## 13.3 Git authorization

- SSH key → user mapping
- Enforce role on:

  - fetch/clone (reader+)
  - push (writer+)

- Enforce branch protections on pre-receive

---

# 14) Deployment (single-node friendly)

**Baseline**

- Postgres
- Electric sync service
- Forge API (Node/TS)
- SSHD + repo storage
- Worker (can be same process initially)

**Notes**

- If you later put Electric behind a CDN, keep the proxy at the edge; Electric’s docs explicitly frame proxying as core to authorization. ([Electric SQL][4])

---

# 15) Implementation milestones

## Milestone 1: Git hosting + auth

- Postgres schema: users, memberships, ssh_keys, project
- SSH bridge: authorize upload/receive-pack
- Basic admin bootstrap

## Milestone 2: Electric read-path

- Electric running against Postgres
- Gatekeeper + proxy endpoints
- Client materializes shapes locally (users/memberships)

## Milestone 3: Discussions + outbox writes

- threads/comments tables + shapes
- mutations/batch endpoint
- offline create comment + reconcile

## Milestone 4: Branch protection + events + webhooks

- pre/post receive hooks
- events table + shape
- webhooks + worker retries

## Milestone 5: Minimal UI completeness

- screens A–G above
- operational hardening (metrics, backups, retention)

---

# 16) Deliverables checklist

### Backend

- [ ] Postgres migrations
- [ ] Electric deployment + config
- [ ] Gatekeeper + shape proxy
- [ ] Auth system
- [ ] Mutations write API + idempotency
- [ ] Git SSH bridge + hooks
- [ ] Browse APIs
- [ ] Worker (webhooks, maintenance)

### Minimal UI

- [ ] Local DB layer + shape materialization
- [ ] Outbox + retry UX
- [ ] Repo browsing screens + discussions

---

If you want, I can follow up with a **concrete, implementable API + schema bundle** (OpenAPI spec + SQL migrations + example shape policies) tailored to your preferred framework (Fastify vs NestJS vs Hono) and your desired client platform (Electron vs web + SQLite WASM).

[1]: https://git-scm.com/docs/pack-protocol?utm_source=chatgpt.com "Git - pack-protocol Documentation"
[2]: https://electric-sql.com/docs/guides/auth "Auth - Guide | Electric"
[3]: https://electric-sql.com/docs/guides/shapes "Shapes - Guide | Electric"
[4]: https://electric-sql.com/docs/guides/security "Security - Guide | Electric"
[5]: https://electric-sql.com/docs/api/clients/typescript "Typescript Client | Electric"
[6]: https://electric-sql.com/docs/guides/writes "Writes - Guide | Electric"
[7]: https://git-scm.com/docs/git-receive-pack?utm_source=chatgpt.com "Git - git-receive-pack Documentation"
[8]: https://git-scm.com/docs/git-upload-pack?utm_source=chatgpt.com "Git - git-upload-pack Documentation"
