# Search Feature Implementation

## Overview

Implement comprehensive search functionality for Plue, enabling users to search across repositories, issues, code, and users. This feature will use PostgreSQL Full-Text Search (FTS) for efficient searching without requiring external indexers like Elasticsearch or Bleve.

## Research Summary

Based on Gitea's implementation in `/gitea`:

### Code Search Architecture
- **Indexer Interface**: `modules/indexer/code/internal/indexer.go` - Defines search interface
- **Search Options**: `modules/indexer/code/internal/model.go` - SearchOptions with RepoIDs, Keyword, Language
- **Search Results**: Includes filename, language, line numbers, highlighted content
- **Search Modes**: Exact match, fuzzy search, regex support
- **Language Filtering**: Filter by programming language with color-coded results
- **Fallback**: Git grep as fallback when indexer unavailable

### Issue Search Architecture
- **DB-based Search**: `modules/indexer/issues/db/db.go` - Uses database LIKE queries
- **Search Options**: `modules/indexer/issues/internal/model.go` - Comprehensive filtering
  - Keyword search (title, content, comments)
  - Filter by: state (open/closed), labels, milestone, assignee, author
  - Sort by: created, updated, comments, deadline (asc/desc)
- **Issue Indexer Data**: Title, content, comments, labels, state, assignee, poster

### Repository Search
- **Model**: `models/repo/search.go` - OrderByMap for sorting
- **Search Options**: Keyword, owner, topic, language, archived, fork, mirror, template, private
- **Sort Options**: alpha, created, updated, size, stars, forks (asc/desc)
- **Description Search**: Optionally search in descriptions

### User Search
- **Model**: `models/user/search.go` - SearchUserOptions
- **Search Fields**: Username, full name, email (privacy-aware)
- **Filters**: User type, visibility, active status, admin status
- **Privacy**: Respects email privacy settings

### Web Interface
- **Explore Code**: `routers/web/explore/code.go` - Global code search
- **Repo Search**: `routers/web/repo/search.go` - Repository-specific search
- **Search Preparation**: `routers/common/codesearch.go` - PrepareCodeSearch helper
- **Pagination**: Standard pagination with configurable page size

## Tech Stack

- **Runtime**: Bun
- **Backend**: Hono API server
- **Frontend**: Astro SSR
- **Database**: PostgreSQL with Full-Text Search (FTS)
- **Validation**: Zod v4

## Database Schema Updates

### 1. Add Full-Text Search Indexes

```sql
-- Add tsvector columns for full-text search
ALTER TABLE repositories
ADD COLUMN search_vector tsvector
GENERATED ALWAYS AS (
  setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
  setweight(to_tsvector('english', coalesce(description, '')), 'B')
) STORED;

ALTER TABLE issues
ADD COLUMN search_vector tsvector
GENERATED ALWAYS AS (
  setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
  setweight(to_tsvector('english', coalesce(body, '')), 'B')
) STORED;

ALTER TABLE comments
ADD COLUMN search_vector tsvector
GENERATED ALWAYS AS (
  to_tsvector('english', coalesce(body, ''))
) STORED;

ALTER TABLE users
ADD COLUMN search_vector tsvector
GENERATED ALWAYS AS (
  setweight(to_tsvector('english', coalesce(username, '')), 'A') ||
  setweight(to_tsvector('english', coalesce(display_name, '')), 'B') ||
  setweight(to_tsvector('english', coalesce(bio, '')), 'C')
) STORED;

-- Create GIN indexes for fast full-text search
CREATE INDEX idx_repositories_search ON repositories USING GIN(search_vector);
CREATE INDEX idx_issues_search ON issues USING GIN(search_vector);
CREATE INDEX idx_comments_search ON comments USING GIN(search_vector);
CREATE INDEX idx_users_search ON users USING GIN(search_vector);

-- Add trigram indexes for fuzzy search (requires pg_trgm extension)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX idx_repositories_name_trgm ON repositories USING GIN(name gin_trgm_ops);
CREATE INDEX idx_repositories_description_trgm ON repositories USING GIN(description gin_trgm_ops);
CREATE INDEX idx_issues_title_trgm ON issues USING GIN(title gin_trgm_ops);
CREATE INDEX idx_users_username_trgm ON users USING GIN(username gin_trgm_ops);
```

### 2. Add Repository Topics Table

```sql
-- Repository topics for tag-based search
CREATE TABLE IF NOT EXISTS repository_topics (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
  topic VARCHAR(50) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, topic)
);

CREATE INDEX idx_repository_topics_topic ON repository_topics(topic);
CREATE INDEX idx_repository_topics_repo ON repository_topics(repository_id);
```

### 3. Add Issue Labels Table

```sql
-- Issue labels for filtering
CREATE TABLE IF NOT EXISTS labels (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  color VARCHAR(7) NOT NULL DEFAULT '#cccccc',
  description TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, name)
);

CREATE TABLE IF NOT EXISTS issue_labels (
  issue_id INTEGER REFERENCES issues(id) ON DELETE CASCADE,
  label_id INTEGER REFERENCES labels(id) ON DELETE CASCADE,
  PRIMARY KEY(issue_id, label_id)
);

CREATE INDEX idx_labels_repo ON labels(repository_id);
CREATE INDEX idx_issue_labels_issue ON issue_labels(issue_id);
CREATE INDEX idx_issue_labels_label ON issue_labels(label_id);
```

### 4. Add Search History Table (Optional)

```sql
-- Track popular searches for autocomplete
CREATE TABLE IF NOT EXISTS search_history (
  id SERIAL PRIMARY KEY,
  query TEXT NOT NULL,
  search_type VARCHAR(20) NOT NULL CHECK (search_type IN ('code', 'issues', 'repos', 'users')),
  result_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_search_history_query ON search_history(query);
CREATE INDEX idx_search_history_type ON search_history(search_type);
```

## Backend Implementation

### 1. Search Service (`server/lib/search.ts`)

```typescript
import { sql } from '../db';
import type { Paginator } from './types';

export type SearchMode = 'exact' | 'fuzzy' | 'fulltext';

export interface SearchResult<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}

// Repository Search
export interface RepoSearchOptions {
  keyword?: string;
  mode?: SearchMode;
  ownerID?: number;
  topic?: string;
  language?: string;
  isPublic?: boolean;
  archived?: boolean;
  fork?: boolean;
  mirror?: boolean;
  sortBy?: 'alpha' | 'created' | 'updated' | 'stars' | 'forks';
  sortOrder?: 'asc' | 'desc';
  page?: number;
  pageSize?: number;
}

export async function searchRepositories(
  opts: RepoSearchOptions
): Promise<SearchResult<Repository>> {
  const {
    keyword = '',
    mode = 'fulltext',
    ownerID,
    topic,
    language,
    isPublic,
    archived,
    fork,
    mirror,
    sortBy = 'updated',
    sortOrder = 'desc',
    page = 1,
    pageSize = 20,
  } = opts;

  let whereConditions = ['1=1'];
  let params: any[] = [];
  let paramIndex = 1;

  // Keyword search
  if (keyword) {
    if (mode === 'fulltext') {
      whereConditions.push(`r.search_vector @@ plainto_tsquery('english', $${paramIndex})`);
      params.push(keyword);
      paramIndex++;
    } else if (mode === 'fuzzy') {
      whereConditions.push(`(
        r.name % $${paramIndex} OR
        r.description % $${paramIndex}
      )`);
      params.push(keyword);
      paramIndex++;
    } else {
      whereConditions.push(`(
        LOWER(r.name) LIKE LOWER($${paramIndex}) OR
        LOWER(r.description) LIKE LOWER($${paramIndex})
      )`);
      params.push(`%${keyword}%`);
      paramIndex++;
    }
  }

  // Filter by owner
  if (ownerID) {
    whereConditions.push(`r.user_id = $${paramIndex}`);
    params.push(ownerID);
    paramIndex++;
  }

  // Filter by topic
  if (topic) {
    whereConditions.push(`EXISTS (
      SELECT 1 FROM repository_topics rt
      WHERE rt.repository_id = r.id AND rt.topic = $${paramIndex}
    )`);
    params.push(topic);
    paramIndex++;
  }

  // Filter by public/private
  if (isPublic !== undefined) {
    whereConditions.push(`r.is_public = $${paramIndex}`);
    params.push(isPublic);
    paramIndex++;
  }

  // Filter by archived
  if (archived !== undefined) {
    whereConditions.push(`r.is_archived = $${paramIndex}`);
    params.push(archived);
    paramIndex++;
  }

  const whereClause = whereConditions.join(' AND ');

  // Sort mapping
  const sortMap: Record<string, string> = {
    alpha: 'u.username, r.name',
    created: 'r.created_at',
    updated: 'r.updated_at',
    stars: 'r.stars_count',
    forks: 'r.forks_count',
  };

  const orderBy = `${sortMap[sortBy]} ${sortOrder.toUpperCase()}`;
  const offset = (page - 1) * pageSize;

  // Get total count
  const countResult = await sql`
    SELECT COUNT(*) as count
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE ${sql.raw(whereClause)}
  `.values(params);

  const total = parseInt(countResult[0][0]);

  // Get paginated results
  params.push(pageSize, offset);
  const results = await sql`
    SELECT
      r.*,
      u.username,
      (
        SELECT json_agg(topic)
        FROM repository_topics rt
        WHERE rt.repository_id = r.id
      ) as topics
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE ${sql.raw(whereClause)}
    ORDER BY ${sql.raw(orderBy)}
    LIMIT $${paramIndex} OFFSET $${paramIndex + 1}
  `.values(params);

  return {
    items: results as Repository[],
    total,
    page,
    pageSize,
  };
}

// Issue Search
export interface IssueSearchOptions {
  keyword?: string;
  mode?: SearchMode;
  repoIDs?: number[];
  state?: 'open' | 'closed';
  labelIDs?: number[];
  authorID?: number;
  assigneeID?: number;
  mentionID?: number;
  sortBy?: 'created' | 'updated' | 'comments';
  sortOrder?: 'asc' | 'desc';
  page?: number;
  pageSize?: number;
}

export async function searchIssues(
  opts: IssueSearchOptions
): Promise<SearchResult<Issue>> {
  const {
    keyword = '',
    mode = 'fulltext',
    repoIDs,
    state,
    labelIDs,
    authorID,
    assigneeID,
    mentionID,
    sortBy = 'updated',
    sortOrder = 'desc',
    page = 1,
    pageSize = 20,
  } = opts;

  let whereConditions = ['1=1'];
  let params: any[] = [];
  let paramIndex = 1;

  // Keyword search (title, body, comments)
  if (keyword) {
    if (mode === 'fulltext') {
      whereConditions.push(`(
        i.search_vector @@ plainto_tsquery('english', $${paramIndex})
        OR EXISTS (
          SELECT 1 FROM comments c
          WHERE c.issue_id = i.id
          AND c.search_vector @@ plainto_tsquery('english', $${paramIndex})
        )
      )`);
      params.push(keyword);
      paramIndex++;
    } else if (mode === 'fuzzy') {
      whereConditions.push(`(
        i.title % $${paramIndex} OR i.body % $${paramIndex}
      )`);
      params.push(keyword);
      paramIndex++;
    } else {
      whereConditions.push(`(
        LOWER(i.title) LIKE LOWER($${paramIndex}) OR
        LOWER(i.body) LIKE LOWER($${paramIndex})
        OR EXISTS (
          SELECT 1 FROM comments c
          WHERE c.issue_id = i.id
          AND LOWER(c.body) LIKE LOWER($${paramIndex})
        )
      )`);
      params.push(`%${keyword}%`);
      paramIndex++;
    }
  }

  // Filter by repositories
  if (repoIDs && repoIDs.length > 0) {
    whereConditions.push(`i.repository_id = ANY($${paramIndex})`);
    params.push(repoIDs);
    paramIndex++;
  }

  // Filter by state
  if (state) {
    whereConditions.push(`i.state = $${paramIndex}`);
    params.push(state);
    paramIndex++;
  }

  // Filter by labels
  if (labelIDs && labelIDs.length > 0) {
    whereConditions.push(`EXISTS (
      SELECT 1 FROM issue_labels il
      WHERE il.issue_id = i.id AND il.label_id = ANY($${paramIndex})
    )`);
    params.push(labelIDs);
    paramIndex++;
  }

  // Filter by author
  if (authorID) {
    whereConditions.push(`i.author_id = $${paramIndex}`);
    params.push(authorID);
    paramIndex++;
  }

  // Filter by assignee
  if (assigneeID) {
    whereConditions.push(`i.assignee_id = $${paramIndex}`);
    params.push(assigneeID);
    paramIndex++;
  }

  const whereClause = whereConditions.join(' AND ');

  // Sort mapping
  const sortMap: Record<string, string> = {
    created: 'i.created_at',
    updated: 'i.updated_at',
    comments: 'comment_count',
  };

  const orderBy = `${sortMap[sortBy]} ${sortOrder.toUpperCase()}`;
  const offset = (page - 1) * pageSize;

  // Get total count
  const countResult = await sql`
    SELECT COUNT(*) as count
    FROM issues i
    WHERE ${sql.raw(whereClause)}
  `.values(params);

  const total = parseInt(countResult[0][0]);

  // Get paginated results
  params.push(pageSize, offset);
  const results = await sql`
    SELECT
      i.*,
      r.name as repo_name,
      u.username as author_username,
      (SELECT COUNT(*) FROM comments c WHERE c.issue_id = i.id) as comment_count,
      (
        SELECT json_agg(json_build_object('id', l.id, 'name', l.name, 'color', l.color))
        FROM labels l
        JOIN issue_labels il ON l.id = il.label_id
        WHERE il.issue_id = i.id
      ) as labels
    FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON i.author_id = u.id
    WHERE ${sql.raw(whereClause)}
    ORDER BY ${sql.raw(orderBy)}
    LIMIT $${paramIndex} OFFSET $${paramIndex + 1}
  `.values(params);

  return {
    items: results as Issue[],
    total,
    page,
    pageSize,
  };
}

// Code Search (using git grep as fallback)
export interface CodeSearchOptions {
  keyword: string;
  repoIDs?: number[];
  language?: string;
  path?: string;
  mode?: 'exact' | 'regex';
  page?: number;
  pageSize?: number;
}

export interface CodeSearchResult {
  repoID: number;
  repoName: string;
  filename: string;
  language: string;
  matches: Array<{
    lineNumber: number;
    content: string;
    highlighted: string;
  }>;
}

export async function searchCode(
  opts: CodeSearchOptions
): Promise<SearchResult<CodeSearchResult>> {
  // This will use git grep under the hood
  // For now, return placeholder implementation
  // Real implementation needs to:
  // 1. Get repository paths from database
  // 2. Run git grep on each repo
  // 3. Parse and highlight results
  // 4. Aggregate and paginate

  const {
    keyword,
    repoIDs,
    language,
    path,
    mode = 'exact',
    page = 1,
    pageSize = 20,
  } = opts;

  // TODO: Implement git grep based code search
  // See gitea/modules/indexer/code/gitgrep/gitgrep.go for reference

  return {
    items: [],
    total: 0,
    page,
    pageSize,
  };
}

// User Search
export interface UserSearchOptions {
  keyword?: string;
  mode?: SearchMode;
  page?: number;
  pageSize?: number;
}

export async function searchUsers(
  opts: UserSearchOptions
): Promise<SearchResult<User>> {
  const {
    keyword = '',
    mode = 'fulltext',
    page = 1,
    pageSize = 20,
  } = opts;

  let whereConditions = ['1=1'];
  let params: any[] = [];
  let paramIndex = 1;

  if (keyword) {
    if (mode === 'fulltext') {
      whereConditions.push(`search_vector @@ plainto_tsquery('english', $${paramIndex})`);
      params.push(keyword);
      paramIndex++;
    } else if (mode === 'fuzzy') {
      whereConditions.push(`username % $${paramIndex}`);
      params.push(keyword);
      paramIndex++;
    } else {
      whereConditions.push(`(
        LOWER(username) LIKE LOWER($${paramIndex}) OR
        LOWER(display_name) LIKE LOWER($${paramIndex})
      )`);
      params.push(`%${keyword}%`);
      paramIndex++;
    }
  }

  const whereClause = whereConditions.join(' AND ');
  const offset = (page - 1) * pageSize;

  // Get total count
  const countResult = await sql`
    SELECT COUNT(*) as count
    FROM users
    WHERE ${sql.raw(whereClause)}
  `.values(params);

  const total = parseInt(countResult[0][0]);

  // Get paginated results
  params.push(pageSize, offset);
  const results = await sql`
    SELECT id, username, display_name, bio, created_at
    FROM users
    WHERE ${sql.raw(whereClause)}
    ORDER BY username ASC
    LIMIT $${paramIndex} OFFSET $${paramIndex + 1}
  `.values(params);

  return {
    items: results as User[],
    total,
    page,
    pageSize,
  };
}

// Unified search (searches across all types)
export interface UnifiedSearchOptions {
  keyword: string;
  types?: ('repos' | 'issues' | 'code' | 'users')[];
  page?: number;
  pageSize?: number;
}

export interface UnifiedSearchResult {
  repos: SearchResult<Repository>;
  issues: SearchResult<Issue>;
  code: SearchResult<CodeSearchResult>;
  users: SearchResult<User>;
}

export async function searchAll(
  opts: UnifiedSearchOptions
): Promise<UnifiedSearchResult> {
  const { keyword, types = ['repos', 'issues', 'code', 'users'], page = 1, pageSize = 5 } = opts;

  const results: UnifiedSearchResult = {
    repos: { items: [], total: 0, page, pageSize },
    issues: { items: [], total: 0, page, pageSize },
    code: { items: [], total: 0, page, pageSize },
    users: { items: [], total: 0, page, pageSize },
  };

  const promises = [];

  if (types.includes('repos')) {
    promises.push(
      searchRepositories({ keyword, page, pageSize }).then((r) => {
        results.repos = r;
      })
    );
  }

  if (types.includes('issues')) {
    promises.push(
      searchIssues({ keyword, page, pageSize }).then((r) => {
        results.issues = r;
      })
    );
  }

  if (types.includes('code')) {
    promises.push(
      searchCode({ keyword, page, pageSize }).then((r) => {
        results.code = r;
      })
    );
  }

  if (types.includes('users')) {
    promises.push(
      searchUsers({ keyword, page, pageSize }).then((r) => {
        results.users = r;
      })
    );
  }

  await Promise.all(promises);

  return results;
}
```

### 2. Search API Routes (`server/routes/search.ts`)

```typescript
import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import {
  searchRepositories,
  searchIssues,
  searchCode,
  searchUsers,
  searchAll,
} from '../lib/search';

const app = new Hono();

// Repository Search
const repoSearchSchema = z.object({
  q: z.string().optional(),
  mode: z.enum(['exact', 'fuzzy', 'fulltext']).default('fulltext'),
  owner: z.coerce.number().optional(),
  topic: z.string().optional(),
  language: z.string().optional(),
  public: z.coerce.boolean().optional(),
  archived: z.coerce.boolean().optional(),
  sort: z.enum(['alpha', 'created', 'updated', 'stars', 'forks']).default('updated'),
  order: z.enum(['asc', 'desc']).default('desc'),
  page: z.coerce.number().min(1).default(1),
  per_page: z.coerce.number().min(1).max(100).default(20),
});

app.get('/repos', zValidator('query', repoSearchSchema), async (c) => {
  const params = c.req.valid('query');

  const results = await searchRepositories({
    keyword: params.q,
    mode: params.mode,
    ownerID: params.owner,
    topic: params.topic,
    language: params.language,
    isPublic: params.public,
    archived: params.archived,
    sortBy: params.sort,
    sortOrder: params.order,
    page: params.page,
    pageSize: params.per_page,
  });

  return c.json(results);
});

// Issue Search
const issueSearchSchema = z.object({
  q: z.string().optional(),
  mode: z.enum(['exact', 'fuzzy', 'fulltext']).default('fulltext'),
  repo: z.coerce.number().array().optional(),
  state: z.enum(['open', 'closed']).optional(),
  labels: z.coerce.number().array().optional(),
  author: z.coerce.number().optional(),
  assignee: z.coerce.number().optional(),
  sort: z.enum(['created', 'updated', 'comments']).default('updated'),
  order: z.enum(['asc', 'desc']).default('desc'),
  page: z.coerce.number().min(1).default(1),
  per_page: z.coerce.number().min(1).max(100).default(20),
});

app.get('/issues', zValidator('query', issueSearchSchema), async (c) => {
  const params = c.req.valid('query');

  const results = await searchIssues({
    keyword: params.q,
    mode: params.mode,
    repoIDs: params.repo,
    state: params.state,
    labelIDs: params.labels,
    authorID: params.author,
    assigneeID: params.assignee,
    sortBy: params.sort,
    sortOrder: params.order,
    page: params.page,
    pageSize: params.per_page,
  });

  return c.json(results);
});

// Code Search
const codeSearchSchema = z.object({
  q: z.string().min(1),
  repo: z.coerce.number().array().optional(),
  language: z.string().optional(),
  path: z.string().optional(),
  mode: z.enum(['exact', 'regex']).default('exact'),
  page: z.coerce.number().min(1).default(1),
  per_page: z.coerce.number().min(1).max(100).default(20),
});

app.get('/code', zValidator('query', codeSearchSchema), async (c) => {
  const params = c.req.valid('query');

  const results = await searchCode({
    keyword: params.q,
    repoIDs: params.repo,
    language: params.language,
    path: params.path,
    mode: params.mode,
    page: params.page,
    pageSize: params.per_page,
  });

  return c.json(results);
});

// User Search
const userSearchSchema = z.object({
  q: z.string().optional(),
  mode: z.enum(['exact', 'fuzzy', 'fulltext']).default('fulltext'),
  page: z.coerce.number().min(1).default(1),
  per_page: z.coerce.number().min(1).max(100).default(20),
});

app.get('/users', zValidator('query', userSearchSchema), async (c) => {
  const params = c.req.valid('query');

  const results = await searchUsers({
    keyword: params.q,
    mode: params.mode,
    page: params.page,
    pageSize: params.per_page,
  });

  return c.json(results);
});

// Unified Search
const unifiedSearchSchema = z.object({
  q: z.string().min(1),
  type: z.enum(['repos', 'issues', 'code', 'users']).array().optional(),
  page: z.coerce.number().min(1).default(1),
  per_page: z.coerce.number().min(1).max(20).default(5),
});

app.get('/', zValidator('query', unifiedSearchSchema), async (c) => {
  const params = c.req.valid('query');

  const results = await searchAll({
    keyword: params.q,
    types: params.type,
    page: params.page,
    pageSize: params.per_page,
  });

  return c.json(results);
});

export default app;
```

### 3. Register Search Routes (`server/routes/index.ts`)

```typescript
import { Hono } from 'hono';
import sessions from './sessions';
import messages from './messages';
import pty from './pty';
import search from './search'; // Add this

const app = new Hono();

app.get('/health', (c) => {
  return c.json({ status: 'ok', timestamp: Date.now() });
});

app.route('/sessions', sessions);
app.route('/session', messages);
app.route('/pty', pty);
app.route('/search', search); // Add this

export default app;
```

## Frontend Implementation

### 1. Global Search Bar Component (`ui/components/SearchBar.astro`)

```astro
---
interface Props {
  placeholder?: string;
  defaultQuery?: string;
  defaultType?: string;
}

const {
  placeholder = "Search repositories, issues, code...",
  defaultQuery = "",
  defaultType = "all"
} = Astro.props;
---

<div class="search-bar">
  <form action="/search" method="get" class="search-form">
    <div class="search-input-wrapper">
      <svg class="search-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
        <path d="M7.333 12.667A5.333 5.333 0 1 0 7.333 2a5.333 5.333 0 0 0 0 10.667ZM14 14l-2.9-2.9"
              stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
      <input
        type="text"
        name="q"
        value={defaultQuery}
        placeholder={placeholder}
        class="search-input"
        autocomplete="off"
      />
    </div>

    <select name="type" class="search-type">
      <option value="all" selected={defaultType === "all"}>All</option>
      <option value="repos" selected={defaultType === "repos"}>Repositories</option>
      <option value="issues" selected={defaultType === "issues"}>Issues</option>
      <option value="code" selected={defaultType === "code"}>Code</option>
      <option value="users" selected={defaultType === "users"}>Users</option>
    </select>

    <button type="submit" class="btn btn-primary">Search</button>
  </form>
</div>

<style>
  .search-bar {
    width: 100%;
    max-width: 600px;
    margin: 0 auto;
  }

  .search-form {
    display: flex;
    gap: 0.5rem;
    align-items: center;
  }

  .search-input-wrapper {
    position: relative;
    flex: 1;
  }

  .search-icon {
    position: absolute;
    left: 12px;
    top: 50%;
    transform: translateY(-50%);
    color: var(--text-muted);
  }

  .search-input {
    width: 100%;
    padding: 10px 12px 10px 40px;
    border: 2px solid var(--border);
    background: var(--bg);
    font-size: 14px;
  }

  .search-input:focus {
    outline: none;
    border-color: var(--primary);
  }

  .search-type {
    padding: 10px 12px;
    border: 2px solid var(--border);
    background: var(--bg);
    font-size: 14px;
    min-width: 120px;
  }

  .search-type:focus {
    outline: none;
    border-color: var(--primary);
  }
</style>
```

### 2. Search Results Page (`ui/pages/search.astro`)

```astro
---
import Layout from "../layouts/Layout.astro";
import Header from "../components/Header.astro";
import SearchBar from "../components/SearchBar.astro";
import RepoCard from "../components/RepoCard.astro";
import IssueCard from "../components/IssueCard.astro";

const query = Astro.url.searchParams.get("q") || "";
const type = Astro.url.searchParams.get("type") || "all";
const page = parseInt(Astro.url.searchParams.get("page") || "1");

let results: any = null;

if (query) {
  const searchUrl = new URL(`/search/${type === 'all' ? '' : type}`, Astro.request.url);
  searchUrl.searchParams.set("q", query);
  searchUrl.searchParams.set("page", page.toString());

  const response = await fetch(searchUrl);
  results = await response.json();
}
---

<Layout title={`Search: ${query}`}>
  <Header currentPath="/search" />

  <div class="container">
    <div class="search-header">
      <h1 class="page-title">Search</h1>
      <SearchBar defaultQuery={query} defaultType={type} />
    </div>

    {!query ? (
      <div class="empty-state">
        <p>Enter a search query to find repositories, issues, code, or users</p>
      </div>
    ) : !results ? (
      <div class="loading">Searching...</div>
    ) : type === "all" ? (
      <div class="unified-results">
        {results.repos.total > 0 && (
          <section class="result-section">
            <div class="section-header">
              <h2>Repositories ({results.repos.total})</h2>
              <a href={`/search?q=${encodeURIComponent(query)}&type=repos`}>View all</a>
            </div>
            <ul class="repo-list">
              {results.repos.items.map((repo: any) => (
                <RepoCard repo={repo} />
              ))}
            </ul>
          </section>
        )}

        {results.issues.total > 0 && (
          <section class="result-section">
            <div class="section-header">
              <h2>Issues ({results.issues.total})</h2>
              <a href={`/search?q=${encodeURIComponent(query)}&type=issues`}>View all</a>
            </div>
            <ul class="issue-list">
              {results.issues.items.map((issue: any) => (
                <IssueCard issue={issue} />
              ))}
            </ul>
          </section>
        )}

        {results.code.total > 0 && (
          <section class="result-section">
            <div class="section-header">
              <h2>Code ({results.code.total})</h2>
              <a href={`/search?q=${encodeURIComponent(query)}&type=code`}>View all</a>
            </div>
            <ul class="code-results">
              {results.code.items.map((match: any) => (
                <li class="code-result">
                  <a href={`/${match.repoName}/blob/main/${match.filename}`}>
                    <strong>{match.repoName}</strong>: {match.filename}
                  </a>
                  <pre class="code-preview">{match.matches[0]?.content}</pre>
                </li>
              ))}
            </ul>
          </section>
        )}

        {results.users.total > 0 && (
          <section class="result-section">
            <div class="section-header">
              <h2>Users ({results.users.total})</h2>
              <a href={`/search?q=${encodeURIComponent(query)}&type=users`}>View all</a>
            </div>
            <ul class="user-list">
              {results.users.items.map((user: any) => (
                <li class="user-item">
                  <a href={`/${user.username}`}>
                    <strong>{user.username}</strong>
                    {user.display_name && <span class="user-name">{user.display_name}</span>}
                  </a>
                  {user.bio && <p class="user-bio">{user.bio}</p>}
                </li>
              ))}
            </ul>
          </section>
        )}

        {results.repos.total === 0 &&
         results.issues.total === 0 &&
         results.code.total === 0 &&
         results.users.total === 0 && (
          <div class="empty-state">
            <p>No results found for "{query}"</p>
          </div>
        )}
      </div>
    ) : (
      <div class="filtered-results">
        <div class="results-header">
          <h2>
            {results.total} result{results.total !== 1 ? 's' : ''} for "{query}"
          </h2>

          <div class="filters">
            <!-- Add filter dropdowns here -->
          </div>
        </div>

        {type === "repos" && (
          <ul class="repo-list">
            {results.items.map((repo: any) => (
              <RepoCard repo={repo} />
            ))}
          </ul>
        )}

        {type === "issues" && (
          <ul class="issue-list">
            {results.items.map((issue: any) => (
              <IssueCard issue={issue} />
            ))}
          </ul>
        )}

        {type === "code" && (
          <ul class="code-results">
            {results.items.map((match: any) => (
              <li class="code-result">
                <a href={`/${match.repoName}/blob/main/${match.filename}`}>
                  <strong>{match.repoName}</strong>: {match.filename}
                </a>
                {match.matches.map((m: any) => (
                  <pre class="code-preview">
                    <span class="line-number">{m.lineNumber}</span>
                    <code set:html={m.highlighted} />
                  </pre>
                ))}
              </li>
            ))}
          </ul>
        )}

        {type === "users" && (
          <ul class="user-list">
            {results.items.map((user: any) => (
              <li class="user-item">
                <a href={`/${user.username}`}>
                  <strong>{user.username}</strong>
                  {user.display_name && <span class="user-name">{user.display_name}</span>}
                </a>
                {user.bio && <p class="user-bio">{user.bio}</p>}
              </li>
            ))}
          </ul>
        )}

        {results.total === 0 && (
          <div class="empty-state">
            <p>No results found for "{query}"</p>
          </div>
        )}

        {results.total > results.pageSize && (
          <div class="pagination">
            {page > 1 && (
              <a href={`/search?q=${encodeURIComponent(query)}&type=${type}&page=${page - 1}`}>
                Previous
              </a>
            )}
            <span>Page {page}</span>
            {results.total > page * results.pageSize && (
              <a href={`/search?q=${encodeURIComponent(query)}&type=${type}&page=${page + 1}`}>
                Next
              </a>
            )}
          </div>
        )}
      </div>
    )}
  </div>
</Layout>

<style>
  .search-header {
    margin-bottom: 2rem;
  }

  .result-section {
    margin-bottom: 3rem;
  }

  .section-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
    padding-bottom: 0.5rem;
    border-bottom: 2px solid var(--border);
  }

  .section-header h2 {
    margin: 0;
    font-size: 1.25rem;
  }

  .section-header a {
    color: var(--primary);
    text-decoration: none;
  }

  .results-header {
    margin-bottom: 1.5rem;
  }

  .code-result {
    margin-bottom: 1.5rem;
    padding: 1rem;
    border: 2px solid var(--border);
    background: var(--bg);
  }

  .code-preview {
    margin-top: 0.5rem;
    padding: 0.5rem;
    background: var(--bg-muted);
    border-left: 3px solid var(--primary);
    overflow-x: auto;
  }

  .line-number {
    display: inline-block;
    width: 3rem;
    color: var(--text-muted);
    text-align: right;
    margin-right: 1rem;
  }

  .user-item {
    padding: 1rem;
    border-bottom: 1px solid var(--border);
  }

  .user-name {
    color: var(--text-muted);
    margin-left: 0.5rem;
  }

  .user-bio {
    margin-top: 0.5rem;
    color: var(--text-muted);
  }

  .pagination {
    display: flex;
    justify-content: center;
    gap: 1rem;
    margin-top: 2rem;
    padding: 1rem;
  }
</style>
```

### 3. Add Search to Header (`ui/components/Header.astro`)

```astro
---
interface Props {
  currentPath?: string;
}

const { currentPath = "/" } = Astro.props;
---

<header class="site-header">
  <a href="/" class="logo">plue</a>

  <!-- Add mini search bar in header -->
  <div class="header-search">
    <form action="/search" method="get">
      <input
        type="text"
        name="q"
        placeholder="Search..."
        class="header-search-input"
      />
    </form>
  </div>

  <nav>
    <a href="/" class:list={[{ active: currentPath === "/" }]}>explore</a>
    <a href="/search" class:list={[{ active: currentPath === "/search" }]}>search</a>
    <a href="/new" class:list={[{ active: currentPath === "/new" }]}>new</a>
  </nav>
</header>

<style>
  .site-header {
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .header-search {
    flex: 1;
    max-width: 300px;
  }

  .header-search-input {
    width: 100%;
    padding: 6px 12px;
    border: 2px solid var(--border);
    background: var(--bg);
    font-size: 13px;
  }

  .header-search-input:focus {
    outline: none;
    border-color: var(--primary);
  }
</style>
```

### 4. Repository Code Search Page (`ui/pages/[user]/[repo]/search.astro`)

```astro
---
import Layout from "../../../layouts/Layout.astro";
import Header from "../../../components/Header.astro";

const { user, repo } = Astro.params;
const query = Astro.url.searchParams.get("q") || "";
const language = Astro.url.searchParams.get("l") || "";
const mode = Astro.url.searchParams.get("mode") || "exact";
const page = parseInt(Astro.url.searchParams.get("page") || "1");

// Get repository
const repoData = await sql`
  SELECT r.*, u.username
  FROM repositories r
  JOIN users u ON r.user_id = u.id
  WHERE u.username = ${user} AND r.name = ${repo}
`.then(rows => rows[0]);

if (!repoData) {
  return Astro.redirect("/404");
}

let results: any = null;

if (query) {
  const searchUrl = new URL(`/search/code`, Astro.request.url);
  searchUrl.searchParams.set("q", query);
  searchUrl.searchParams.set("repo", repoData.id.toString());
  if (language) searchUrl.searchParams.set("language", language);
  searchUrl.searchParams.set("mode", mode);
  searchUrl.searchParams.set("page", page.toString());

  const response = await fetch(searchUrl);
  results = await response.json();
}
---

<Layout title={`Search in ${user}/${repo}`}>
  <Header />

  <div class="container">
    <div class="repo-header">
      <h1><a href={`/${user}`}>{user}</a> / <a href={`/${user}/${repo}`}>{repo}</a></h1>
    </div>

    <div class="search-form">
      <form method="get">
        <div class="search-row">
          <input
            type="text"
            name="q"
            value={query}
            placeholder="Search code in this repository..."
            class="search-input"
          />

          <select name="mode" class="search-mode">
            <option value="exact" selected={mode === "exact"}>Exact match</option>
            <option value="regex" selected={mode === "regex"}>Regex</option>
          </select>

          <button type="submit" class="btn btn-primary">Search</button>
        </div>

        {results?.languages && (
          <div class="language-filters">
            <span>Language:</span>
            {results.languages.map((lang: any) => (
              <a
                href={`?q=${encodeURIComponent(query)}&l=${lang.name}&mode=${mode}`}
                class:list={["language-tag", { active: language === lang.name }]}
              >
                {lang.name} ({lang.count})
              </a>
            ))}
          </div>
        )}
      </form>
    </div>

    {results && (
      <div class="search-results">
        <h2>{results.total} result{results.total !== 1 ? 's' : ''}</h2>

        {results.items.map((match: any) => (
          <div class="code-match">
            <h3>
              <a href={`/${user}/${repo}/blob/main/${match.filename}`}>
                {match.filename}
              </a>
            </h3>

            {match.matches.map((m: any) => (
              <pre class="code-snippet">
                <a
                  href={`/${user}/${repo}/blob/main/${match.filename}#L${m.lineNumber}`}
                  class="line-link"
                >
                  <span class="line-number">{m.lineNumber}</span>
                  <code set:html={m.highlighted} />
                </a>
              </pre>
            ))}
          </div>
        ))}
      </div>
    )}
  </div>
</Layout>
```

## Implementation Checklist

### Phase 1: Database Setup
- [ ] Add search_vector columns to repositories, issues, comments, users tables
- [ ] Create GIN indexes for full-text search
- [ ] Add pg_trgm extension and trigram indexes
- [ ] Create repository_topics table
- [ ] Create labels and issue_labels tables
- [ ] Create search_history table (optional)
- [ ] Write database migration script
- [ ] Test indexes with sample data

### Phase 2: Backend - Search Service
- [ ] Create `server/lib/search.ts` with search functions
- [ ] Implement `searchRepositories()` with filters and sorting
- [ ] Implement `searchIssues()` with filters and sorting
- [ ] Implement `searchUsers()` with privacy-aware search
- [ ] Implement `searchCode()` using git grep
- [ ] Implement `searchAll()` for unified search
- [ ] Add TypeScript types for search options and results
- [ ] Write unit tests for search functions

### Phase 3: Backend - API Routes
- [ ] Create `server/routes/search.ts`
- [ ] Add GET `/search/repos` endpoint
- [ ] Add GET `/search/issues` endpoint
- [ ] Add GET `/search/code` endpoint
- [ ] Add GET `/search/users` endpoint
- [ ] Add GET `/search` unified search endpoint
- [ ] Add Zod validation schemas for all endpoints
- [ ] Register search routes in `server/routes/index.ts`
- [ ] Test API endpoints with Postman/curl

### Phase 4: Frontend - Components
- [ ] Create `ui/components/SearchBar.astro`
- [ ] Add search icon SVG
- [ ] Style search input and type selector
- [ ] Add autocomplete support (optional)
- [ ] Test search bar component

### Phase 5: Frontend - Search Results Page
- [ ] Create `ui/pages/search.astro`
- [ ] Implement unified search results view
- [ ] Implement filtered results view (repos/issues/code/users)
- [ ] Add result counters and section headers
- [ ] Add pagination controls
- [ ] Style search results with brutalist theme
- [ ] Test all search result types

### Phase 6: Frontend - Repository Code Search
- [ ] Create `ui/pages/[user]/[repo]/search.astro`
- [ ] Add repository-scoped search form
- [ ] Add language filter chips
- [ ] Add search mode selector (exact/regex)
- [ ] Display code matches with line numbers
- [ ] Add syntax highlighting for results
- [ ] Link to file and line number
- [ ] Test code search in repository

### Phase 7: Frontend - Header Integration
- [ ] Update `ui/components/Header.astro`
- [ ] Add mini search bar to header
- [ ] Add search link to navigation
- [ ] Style header search responsively
- [ ] Test header search on all pages

### Phase 8: Advanced Features
- [ ] Add search result highlighting
- [ ] Implement fuzzy search with similarity scoring
- [ ] Add "did you mean" suggestions
- [ ] Add search history and autocomplete
- [ ] Add advanced filters UI (date range, etc.)
- [ ] Add search analytics (track popular queries)
- [ ] Add keyboard shortcuts (CMD/CTRL+K to focus search)
- [ ] Add search result export (JSON/CSV)

### Phase 9: Performance & Optimization
- [ ] Add query result caching (Redis or in-memory)
- [ ] Optimize database queries with EXPLAIN ANALYZE
- [ ] Add search query rate limiting
- [ ] Add search result count limits
- [ ] Test search performance with large datasets
- [ ] Add search telemetry/monitoring

### Phase 10: Documentation & Testing
- [ ] Write API documentation for search endpoints
- [ ] Write user guide for search features
- [ ] Add search examples to README
- [ ] Write integration tests for search flows
- [ ] Test search with edge cases (special chars, unicode, etc.)
- [ ] Test search pagination and sorting
- [ ] Test search filters and combinations

## Testing Strategy

### Unit Tests
```typescript
// server/lib/search.test.ts
import { test, expect } from "bun:test";
import { searchRepositories, searchIssues } from "./search";

test("searchRepositories returns results", async () => {
  const results = await searchRepositories({
    keyword: "test",
    page: 1,
    pageSize: 10,
  });

  expect(results).toHaveProperty("items");
  expect(results).toHaveProperty("total");
  expect(Array.isArray(results.items)).toBe(true);
});

test("searchIssues filters by state", async () => {
  const results = await searchIssues({
    keyword: "bug",
    state: "open",
    page: 1,
    pageSize: 10,
  });

  expect(results.items.every(i => i.state === "open")).toBe(true);
});
```

### Integration Tests
```typescript
// Test search API endpoints
test("GET /search/repos returns 200", async () => {
  const response = await fetch("http://localhost:3000/search/repos?q=test");
  expect(response.status).toBe(200);

  const data = await response.json();
  expect(data).toHaveProperty("items");
  expect(data).toHaveProperty("total");
});
```

### Manual Testing Checklist
- [ ] Search with empty query returns all results
- [ ] Search with special characters doesn't crash
- [ ] Search with very long query works
- [ ] Pagination works correctly
- [ ] Sorting works for all options
- [ ] Filters combine correctly (AND logic)
- [ ] Search works for non-English text
- [ ] Search respects repository visibility
- [ ] Search results highlight query terms
- [ ] Code search finds matches in files

## Reference Code Translations

### Gitea's Code Search Interface (Go) → TypeScript

**Gitea (`modules/indexer/code/search.go`)**:
```go
type SearchOptions = internal.SearchOptions

func PerformSearch(ctx context.Context, opts *SearchOptions) (int, []*Result, []*SearchResultLanguages, error) {
  if opts == nil || len(opts.Keyword) == 0 {
    return 0, nil, nil, nil
  }

  total, results, resultLanguages, err := (*globalIndexer.Load()).Search(ctx, opts)
  if err != nil {
    return 0, nil, nil, err
  }

  displayResults := make([]*Result, len(results))
  for i, result := range results {
    startIndex, endIndex := indices(result.Content, result.StartIndex, result.EndIndex)
    displayResults[i], err = searchResult(result, startIndex, endIndex)
    if err != nil {
      return 0, nil, nil, err
    }
  }
  return int(total), displayResults, resultLanguages, nil
}
```

**Plue (TypeScript)**:
```typescript
export async function searchCode(
  opts: CodeSearchOptions
): Promise<SearchResult<CodeSearchResult>> {
  if (!opts.keyword) {
    return { items: [], total: 0, page: 1, pageSize: 20 };
  }

  // Use git grep for code search
  const results = await gitGrep({
    repoIDs: opts.repoIDs,
    keyword: opts.keyword,
    language: opts.language,
    mode: opts.mode,
  });

  // Format results with line numbers and highlighting
  const displayResults = results.map(result => ({
    repoID: result.repoID,
    filename: result.filename,
    language: result.language,
    matches: highlightMatches(result.content, opts.keyword),
  }));

  return {
    items: displayResults,
    total: results.length,
    page: opts.page || 1,
    pageSize: opts.pageSize || 20,
  };
}
```

### Gitea's Issue Search (Go) → TypeScript

**Gitea (`modules/indexer/issues/db/db.go`)**:
```go
func (i *Indexer) Search(ctx context.Context, options *internal.SearchOptions) (*internal.SearchResult, error) {
  cond := builder.NewCond()

  if options.Keyword != "" {
    repoCond := builder.In("repo_id", options.RepoIDs)
    subQuery := builder.Select("id").From("issue").Where(repoCond)
    cond = builder.Or(
      buildMatchQuery(searchMode, "issue.name", options.Keyword),
      buildMatchQuery(searchMode, "issue.content", options.Keyword),
      builder.In("issue.id", builder.Select("issue_id").
        From("comment").
        Where(builder.And(
          builder.Eq{"type": issue_model.CommentTypeComment},
          builder.In("issue_id", subQuery),
          buildMatchQuery(searchMode, "content", options.Keyword),
        )),
      ),
    )
  }

  return i.FindWithIssueOptions(ctx, opt, cond)
}
```

**Plue (TypeScript)**:
```typescript
export async function searchIssues(opts: IssueSearchOptions): Promise<SearchResult<Issue>> {
  let whereConditions = ['1=1'];
  let params: any[] = [];

  if (opts.keyword) {
    // Search in title, body, and comments
    whereConditions.push(`(
      i.search_vector @@ plainto_tsquery('english', $1)
      OR EXISTS (
        SELECT 1 FROM comments c
        WHERE c.issue_id = i.id
        AND c.search_vector @@ plainto_tsquery('english', $1)
      )
    )`);
    params.push(opts.keyword);
  }

  if (opts.repoIDs?.length) {
    whereConditions.push(`i.repository_id = ANY($${params.length + 1})`);
    params.push(opts.repoIDs);
  }

  const results = await sql`
    SELECT i.*, COUNT(c.id) as comment_count
    FROM issues i
    LEFT JOIN comments c ON c.issue_id = i.id
    WHERE ${sql.raw(whereConditions.join(' AND '))}
    GROUP BY i.id
    ORDER BY i.updated_at DESC
  `.values(params);

  return { items: results, total: results.length, page: 1, pageSize: 20 };
}
```

## Performance Considerations

1. **PostgreSQL FTS is Fast**: For small to medium datasets (<100k documents), PostgreSQL FTS is sufficient
2. **Index Maintenance**: tsvector columns are automatically updated via GENERATED ALWAYS AS
3. **Query Optimization**: Use GIN indexes for FTS, trigram indexes for fuzzy search
4. **Pagination**: Always paginate results to avoid loading too much data
5. **Caching**: Cache popular search queries in Redis or in-memory
6. **Rate Limiting**: Prevent abuse by rate-limiting search API endpoints

## Future Enhancements

1. **External Indexers**: Support for Elasticsearch/Meilisearch for larger deployments
2. **Advanced Code Search**: AST-based code search for semantic queries
3. **ML-Powered Search**: Use embeddings for semantic search
4. **Search Suggestions**: Auto-complete and query suggestions
5. **Saved Searches**: Allow users to save and share search queries
6. **Search Alerts**: Notify users when new results match saved searches
7. **Multi-Language Support**: Better tokenization for non-English languages
8. **Search Analytics**: Track and analyze search patterns

## Notes

- Start with PostgreSQL FTS - it's simpler and sufficient for most use cases
- Code search requires git grep integration - implement as separate service
- Respect repository visibility permissions in all search queries
- Consider privacy when searching user emails and personal data
- Test search performance with realistic data volumes
- Follow Plue's brutalist design aesthetic for search UI
- Ensure search results are accessible (keyboard navigation, screen readers)

## References

- Gitea Code Indexer: `/gitea/modules/indexer/code/`
- Gitea Issue Indexer: `/gitea/modules/indexer/issues/`
- Gitea Search Routes: `/gitea/routers/web/explore/`
- PostgreSQL FTS: https://www.postgresql.org/docs/current/textsearch.html
- PostgreSQL pg_trgm: https://www.postgresql.org/docs/current/pgtrgm.html
