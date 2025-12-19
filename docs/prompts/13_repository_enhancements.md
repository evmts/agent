# Repository Enhancements Implementation Prompt

## Overview

Add advanced repository features to Plue including starring, forking, topics/tags, language statistics, license detection, and repository templates. This prompt provides comprehensive implementation guidance based on Gitea's proven patterns translated to Plue's TypeScript/Bun stack.

## Research Foundation

This implementation is based on analysis of:
- `/Users/williamcory/plue/gitea/models/repo/` - Data models for stars, forks, topics, languages, licenses
- `/Users/williamcory/plue/gitea/services/repository/` - Business logic for forking and templates
- `/Users/williamcory/plue/gitea/routers/web/repo/` - API handlers
- `/Users/williamcory/plue/db/schema.sql` - Plue's current database schema
- `/Users/williamcory/plue/ui/pages/[user]/[repo]/` - Plue's repository UI

## Database Schema Changes

Add these tables to `/Users/williamcory/plue/db/schema.sql`:

```sql
-- Repository Stars
CREATE TABLE IF NOT EXISTS repository_stars (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, repository_id)
);

CREATE INDEX idx_repository_stars_repo ON repository_stars(repository_id);
CREATE INDEX idx_repository_stars_user ON repository_stars(user_id);

-- Topics (global topic registry)
CREATE TABLE IF NOT EXISTS topics (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) UNIQUE NOT NULL,
  repo_count INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_topics_name ON topics(name);

-- Repository Topics (join table)
CREATE TABLE IF NOT EXISTS repository_topics (
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
  PRIMARY KEY (repository_id, topic_id)
);

CREATE INDEX idx_repository_topics_repo ON repository_topics(repository_id);
CREATE INDEX idx_repository_topics_topic ON repository_topics(topic_id);

-- Language Statistics
CREATE TABLE IF NOT EXISTS language_stats (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  commit_id VARCHAR(40),
  language VARCHAR(50) NOT NULL,
  size BIGINT NOT NULL DEFAULT 0,
  is_primary BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, language)
);

CREATE INDEX idx_language_stats_repo ON language_stats(repository_id);

-- Repository Licenses
CREATE TABLE IF NOT EXISTS repository_licenses (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  commit_id VARCHAR(40),
  license VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, license)
);

CREATE INDEX idx_repository_licenses_repo ON repository_licenses(repository_id);

-- Add columns to existing repositories table
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS num_stars INTEGER DEFAULT 0;
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS num_forks INTEGER DEFAULT 0;
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS is_fork BOOLEAN DEFAULT false;
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS fork_id INTEGER REFERENCES repositories(id) ON DELETE SET NULL;
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS is_template BOOLEAN DEFAULT false;
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS template_id INTEGER REFERENCES repositories(id) ON DELETE SET NULL;
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS topics TEXT[] DEFAULT '{}';
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS primary_language VARCHAR(50);

CREATE INDEX idx_repositories_fork_id ON repositories(fork_id);
CREATE INDEX idx_repositories_template_id ON repositories(template_id);
```

## Core TypeScript Types

Create `/Users/williamcory/plue/core/models/repository.ts`:

```typescript
import { z } from 'zod';

// Repository Star
export const RepositoryStarSchema = z.object({
  id: z.number(),
  userId: z.number(),
  repositoryId: z.number(),
  createdAt: z.date(),
});

export type RepositoryStar = z.infer<typeof RepositoryStarSchema>;

// Topic
export const TopicSchema = z.object({
  id: z.number(),
  name: z.string().min(1).max(50).regex(/^[a-z0-9][-.a-z0-9]*$/),
  repoCount: z.number().default(0),
  createdAt: z.date(),
  updatedAt: z.date(),
});

export type Topic = z.infer<typeof TopicSchema>;

// Language Stat
export const LanguageStatSchema = z.object({
  id: z.number(),
  repositoryId: z.number(),
  commitId: z.string().nullable(),
  language: z.string(),
  size: z.bigint(),
  isPrimary: z.boolean(),
  percentage: z.number().optional(), // calculated field
  color: z.string().optional(), // calculated field
  createdAt: z.date(),
  updatedAt: z.date(),
});

export type LanguageStat = z.infer<typeof LanguageStatSchema>;

// Repository License
export const RepositoryLicenseSchema = z.object({
  id: z.number(),
  repositoryId: z.number(),
  commitId: z.string().nullable(),
  license: z.string(),
  createdAt: z.date(),
  updatedAt: z.date(),
});

export type RepositoryLicense = z.infer<typeof RepositoryLicenseSchema>;

// Fork Options
export const ForkRepositoryOptionsSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
  singleBranch: z.string().optional(),
});

export type ForkRepositoryOptions = z.infer<typeof ForkRepositoryOptionsSchema>;

// Template Options
export const GenerateFromTemplateOptionsSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
  isPrivate: z.boolean().default(false),
  includeTopics: z.boolean().default(true),
});

export type GenerateFromTemplateOptions = z.infer<typeof GenerateFromTemplateOptionsSchema>;
```

## Service Layer

### Star Service

Create `/Users/williamcory/plue/server/services/star.ts`:

```typescript
import { sql } from '../../lib/db';
import type { RepositoryStar } from '../../core/models/repository';

/**
 * Star or unstar a repository
 * Based on: gitea/models/repo/star.go StarRepo()
 */
export async function starRepository(
  userId: number,
  repositoryId: number,
  star: boolean
): Promise<void> {
  const [{ isStarring }] = await sql`
    SELECT EXISTS(
      SELECT 1 FROM repository_stars
      WHERE user_id = ${userId} AND repository_id = ${repositoryId}
    ) as "isStarring"
  `;

  if (star && !isStarring) {
    // Add star
    await sql.begin(async (tx) => {
      await tx`
        INSERT INTO repository_stars (user_id, repository_id)
        VALUES (${userId}, ${repositoryId})
      `;
      await tx`
        UPDATE repositories SET num_stars = num_stars + 1
        WHERE id = ${repositoryId}
      `;
    });
  } else if (!star && isStarring) {
    // Remove star
    await sql.begin(async (tx) => {
      await tx`
        DELETE FROM repository_stars
        WHERE user_id = ${userId} AND repository_id = ${repositoryId}
      `;
      await tx`
        UPDATE repositories SET num_stars = num_stars - 1
        WHERE id = ${repositoryId}
      `;
    });
  }
}

/**
 * Check if user has starred a repository
 * Based on: gitea/models/repo/star.go IsStaring()
 */
export async function isStarring(
  userId: number,
  repositoryId: number
): Promise<boolean> {
  const [{ exists }] = await sql`
    SELECT EXISTS(
      SELECT 1 FROM repository_stars
      WHERE user_id = ${userId} AND repository_id = ${repositoryId}
    ) as exists
  `;
  return exists;
}

/**
 * Get users who starred a repository
 * Based on: gitea/models/repo/star.go GetStargazers()
 */
export async function getStargazers(
  repositoryId: number,
  limit = 30,
  offset = 0
) {
  return sql`
    SELECT u.* FROM users u
    INNER JOIN repository_stars rs ON rs.user_id = u.id
    WHERE rs.repository_id = ${repositoryId}
    ORDER BY rs.created_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;
}
```

### Fork Service

Create `/Users/williamcory/plue/server/services/fork.ts`:

```typescript
import { sql } from '../../lib/db';
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';
import type { ForkRepositoryOptions } from '../../core/models/repository';

const execAsync = promisify(exec);

/**
 * Fork a repository
 * Based on: gitea/services/repository/fork.go ForkRepository()
 */
export async function forkRepository(
  baseRepoId: number,
  ownerId: number,
  options: ForkRepositoryOptions
) {
  // Check if user already forked this repo
  const [existing] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${ownerId} AND fork_id = ${baseRepoId}
  `;

  if (existing) {
    throw new Error('Repository already forked by user');
  }

  const [baseRepo] = await sql`
    SELECT * FROM repositories WHERE id = ${baseRepoId}
  `;

  if (!baseRepo) {
    throw new Error('Base repository not found');
  }

  const [owner] = await sql`
    SELECT * FROM users WHERE id = ${ownerId}
  `;

  return await sql.begin(async (tx) => {
    // 1. Create repository record
    const [forkedRepo] = await tx`
      INSERT INTO repositories (
        user_id, name, description, is_public,
        default_branch, is_fork, fork_id
      )
      VALUES (
        ${ownerId},
        ${options.name},
        ${options.description || baseRepo.description},
        ${baseRepo.is_public},
        ${options.singleBranch || baseRepo.default_branch},
        true,
        ${baseRepoId}
      )
      RETURNING *
    `;

    // 2. Increment fork count
    await tx`
      UPDATE repositories SET num_forks = num_forks + 1
      WHERE id = ${baseRepoId}
    `;

    // 3. Clone git repository
    const baseRepoPath = path.join(
      process.cwd(),
      'repos',
      baseRepo.user_id.toString(),
      baseRepo.name
    );
    const forkedRepoPath = path.join(
      process.cwd(),
      'repos',
      ownerId.toString(),
      options.name
    );

    // Create bare clone
    const cloneOpts = options.singleBranch
      ? `--single-branch --branch ${options.singleBranch}`
      : '';

    await execAsync(
      `git clone --bare ${cloneOpts} ${baseRepoPath} ${forkedRepoPath}`
    );

    // 4. Copy language stats
    await copyLanguageStats(tx, baseRepoId, forkedRepo.id);

    // 5. Copy license info
    await copyLicense(tx, baseRepoId, forkedRepo.id);

    return forkedRepo;
  });
}

/**
 * Copy language statistics from original to forked repo
 * Based on: gitea/models/repo/language_stats.go CopyLanguageStat()
 */
async function copyLanguageStats(tx: any, sourceRepoId: number, destRepoId: number) {
  const stats = await tx`
    SELECT language, size, is_primary, commit_id
    FROM language_stats
    WHERE repository_id = ${sourceRepoId}
    ORDER BY size DESC
  `;

  if (stats.length > 0) {
    for (const stat of stats) {
      await tx`
        INSERT INTO language_stats (
          repository_id, language, size, is_primary, commit_id
        )
        VALUES (
          ${destRepoId}, ${stat.language}, ${stat.size},
          ${stat.is_primary}, ${stat.commit_id}
        )
      `;
    }
  }
}

/**
 * Copy license info from original to forked repo
 * Based on: gitea/models/repo/license.go CopyLicense()
 */
async function copyLicense(tx: any, sourceRepoId: number, destRepoId: number) {
  const licenses = await tx`
    SELECT license, commit_id
    FROM repository_licenses
    WHERE repository_id = ${sourceRepoId}
  `;

  if (licenses.length > 0) {
    for (const lic of licenses) {
      await tx`
        INSERT INTO repository_licenses (
          repository_id, license, commit_id
        )
        VALUES (${destRepoId}, ${lic.license}, ${lic.commit_id})
      `;
    }
  }
}

/**
 * Get all forks of a repository
 * Based on: gitea/models/repo/fork.go GetRepositoriesByForkID()
 */
export async function getForks(
  repositoryId: number,
  limit = 30,
  offset = 0
) {
  return sql`
    SELECT r.*, u.username, u.display_name
    FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE r.fork_id = ${repositoryId}
    ORDER BY r.created_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;
}

/**
 * Check if user has forked a repository
 * Based on: gitea/models/repo/fork.go HasForkedRepo()
 */
export async function hasForkedRepo(
  userId: number,
  repositoryId: number
): Promise<boolean> {
  const [{ exists }] = await sql`
    SELECT EXISTS(
      SELECT 1 FROM repositories
      WHERE user_id = ${userId} AND fork_id = ${repositoryId}
    ) as exists
  `;
  return exists;
}
```

### Topic Service

Create `/Users/williamcory/plue/server/services/topics.ts`:

```typescript
import { sql } from '../../lib/db';
import type { Topic } from '../../core/models/repository';

const TOPIC_PATTERN = /^[a-z0-9][-.a-z0-9]*$/;
const MAX_TOPIC_LENGTH = 50;

/**
 * Validate topic name
 * Based on: gitea/models/repo/topic.go ValidateTopic()
 */
export function validateTopic(topic: string): boolean {
  return topic.length <= MAX_TOPIC_LENGTH && TOPIC_PATTERN.test(topic);
}

/**
 * Sanitize and validate array of topics
 * Based on: gitea/models/repo/topic.go SanitizeAndValidateTopics()
 */
export function sanitizeAndValidateTopics(topics: string[]): {
  valid: string[];
  invalid: string[];
} {
  const valid: string[] = [];
  const invalid: string[] = [];
  const seen = new Set<string>();

  for (let topic of topics) {
    topic = topic.trim().toLowerCase();

    if (!topic || seen.has(topic)) continue;

    if (validateTopic(topic)) {
      valid.push(topic);
      seen.add(topic);
    } else {
      invalid.push(topic);
    }
  }

  return { valid, invalid };
}

/**
 * Add a topic to a repository
 * Based on: gitea/models/repo/topic.go AddTopic()
 */
export async function addTopic(
  repositoryId: number,
  topicName: string
): Promise<Topic> {
  topicName = topicName.trim().toLowerCase();

  if (!validateTopic(topicName)) {
    throw new Error(`Invalid topic name: ${topicName}`);
  }

  return await sql.begin(async (tx) => {
    // Check if repo already has this topic
    const [existing] = await tx`
      SELECT t.* FROM topics t
      INNER JOIN repository_topics rt ON rt.topic_id = t.id
      WHERE rt.repository_id = ${repositoryId} AND t.name = ${topicName}
    `;

    if (existing) return existing;

    // Get or create topic
    let [topic] = await tx`
      SELECT * FROM topics WHERE name = ${topicName}
    `;

    if (!topic) {
      [topic] = await tx`
        INSERT INTO topics (name, repo_count)
        VALUES (${topicName}, 1)
        RETURNING *
      `;
    } else {
      await tx`
        UPDATE topics SET repo_count = repo_count + 1
        WHERE id = ${topic.id}
      `;
      topic.repo_count += 1;
    }

    // Link topic to repository
    await tx`
      INSERT INTO repository_topics (repository_id, topic_id)
      VALUES (${repositoryId}, ${topic.id})
    `;

    // Update topics array in repository
    await syncTopicsInRepository(tx, repositoryId);

    return topic;
  });
}

/**
 * Remove a topic from a repository
 * Based on: gitea/models/repo/topic.go DeleteTopic()
 */
export async function removeTopic(
  repositoryId: number,
  topicName: string
): Promise<void> {
  topicName = topicName.trim().toLowerCase();

  await sql.begin(async (tx) => {
    const [topic] = await tx`
      SELECT t.* FROM topics t
      INNER JOIN repository_topics rt ON rt.topic_id = t.id
      WHERE rt.repository_id = ${repositoryId} AND t.name = ${topicName}
    `;

    if (!topic) return;

    await tx`
      DELETE FROM repository_topics
      WHERE repository_id = ${repositoryId} AND topic_id = ${topic.id}
    `;

    await tx`
      UPDATE topics SET repo_count = repo_count - 1
      WHERE id = ${topic.id}
    `;

    await syncTopicsInRepository(tx, repositoryId);
  });
}

/**
 * Save topics for a repository (replaces all existing)
 * Based on: gitea/models/repo/topic.go SaveTopics()
 */
export async function saveTopics(
  repositoryId: number,
  topicNames: string[]
): Promise<void> {
  const { valid, invalid } = sanitizeAndValidateTopics(topicNames);

  if (invalid.length > 0) {
    throw new Error(`Invalid topics: ${invalid.join(', ')}`);
  }

  await sql.begin(async (tx) => {
    // Get current topics
    const currentTopics = await tx`
      SELECT t.* FROM topics t
      INNER JOIN repository_topics rt ON rt.topic_id = t.id
      WHERE rt.repository_id = ${repositoryId}
    `;

    // Find topics to add
    const toAdd = valid.filter(
      (name) => !currentTopics.some((t) => t.name === name)
    );

    // Find topics to remove
    const toRemove = currentTopics.filter(
      (t) => !valid.some((name) => name === t.name)
    );

    // Add new topics
    for (const topicName of toAdd) {
      let [topic] = await tx`
        SELECT * FROM topics WHERE name = ${topicName}
      `;

      if (!topic) {
        [topic] = await tx`
          INSERT INTO topics (name, repo_count)
          VALUES (${topicName}, 1)
          RETURNING *
        `;
      } else {
        await tx`
          UPDATE topics SET repo_count = repo_count + 1
          WHERE id = ${topic.id}
        `;
      }

      await tx`
        INSERT INTO repository_topics (repository_id, topic_id)
        VALUES (${repositoryId}, ${topic.id})
      `;
    }

    // Remove old topics
    for (const topic of toRemove) {
      await tx`
        DELETE FROM repository_topics
        WHERE repository_id = ${repositoryId} AND topic_id = ${topic.id}
      `;

      await tx`
        UPDATE topics SET repo_count = repo_count - 1
        WHERE id = ${topic.id}
      `;
    }

    await syncTopicsInRepository(tx, repositoryId);
  });
}

/**
 * Sync topics array in repository record
 * Based on: gitea/models/repo/topic.go syncTopicsInRepository()
 */
async function syncTopicsInRepository(tx: any, repositoryId: number) {
  const topics = await tx`
    SELECT t.name FROM topics t
    INNER JOIN repository_topics rt ON rt.topic_id = t.id
    WHERE rt.repository_id = ${repositoryId}
    ORDER BY t.name ASC
  `;

  const topicNames = topics.map((t: any) => t.name);

  await tx`
    UPDATE repositories SET topics = ${topicNames}
    WHERE id = ${repositoryId}
  `;
}

/**
 * Get topics for a repository
 */
export async function getRepositoryTopics(repositoryId: number): Promise<Topic[]> {
  return sql`
    SELECT t.* FROM topics t
    INNER JOIN repository_topics rt ON rt.topic_id = t.id
    WHERE rt.repository_id = ${repositoryId}
    ORDER BY t.name ASC
  `;
}
```

### Language Stats Service

Create `/Users/williamcory/plue/server/services/languages.ts`:

```typescript
import { sql } from '../../lib/db';
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';
import type { LanguageStat } from '../../core/models/repository';

const execAsync = promisify(exec);

// Language colors from github-linguist
const LANGUAGE_COLORS: Record<string, string> = {
  javascript: '#f1e05a',
  typescript: '#3178c6',
  python: '#3572A5',
  java: '#b07219',
  go: '#00ADD8',
  rust: '#dea584',
  ruby: '#701516',
  php: '#4F5D95',
  c: '#555555',
  'c++': '#f34b7d',
  'c#': '#178600',
  html: '#e34c26',
  css: '#563d7c',
  shell: '#89e051',
  other: '#cccccc',
};

/**
 * Get language statistics for a repository with percentages
 * Based on: gitea/models/repo/language_stats.go GetLanguageStats()
 */
export async function getLanguageStats(repositoryId: number): Promise<LanguageStat[]> {
  const stats = await sql`
    SELECT * FROM language_stats
    WHERE repository_id = ${repositoryId}
    ORDER BY size DESC
  `;

  const total = stats.reduce((sum, s) => sum + Number(s.size), 0);

  return stats.map((stat) => {
    const percentage = total > 0 ? (Number(stat.size) / total) * 100 : 0;
    return {
      ...stat,
      percentage: Math.round(percentage * 10) / 10,
      color: LANGUAGE_COLORS[stat.language.toLowerCase()] || LANGUAGE_COLORS.other,
    };
  });
}

/**
 * Get top N languages for a repository (for language bar display)
 * Based on: gitea/models/repo/language_stats.go GetTopLanguageStats()
 */
export async function getTopLanguageStats(
  repositoryId: number,
  limit = 5
): Promise<LanguageStat[]> {
  const stats = await getLanguageStats(repositoryId);

  if (stats.length <= limit) {
    return stats;
  }

  const top = stats.slice(0, limit);
  const rest = stats.slice(limit);
  const otherSize = rest.reduce((sum, s) => sum + Number(s.size), 0);
  const otherPercentage = rest.reduce((sum, s) => sum + (s.percentage || 0), 0);

  if (otherSize > 0) {
    top.push({
      id: -1,
      repositoryId,
      commitId: null,
      language: 'other',
      size: BigInt(otherSize),
      isPrimary: false,
      percentage: Math.round(otherPercentage * 10) / 10,
      color: LANGUAGE_COLORS.other,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  }

  return top;
}

/**
 * Update language statistics by analyzing git repository
 * Based on: gitea/models/repo/language_stats.go UpdateLanguageStats()
 *
 * This uses github-linguist via CLI. Install with: gem install github-linguist
 */
export async function updateLanguageStats(
  repositoryId: number,
  commitId: string
): Promise<void> {
  const [repo] = await sql`
    SELECT r.*, u.username FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE r.id = ${repositoryId}
  `;

  if (!repo) throw new Error('Repository not found');

  const repoPath = path.join(
    process.cwd(),
    'repos',
    repo.user_id.toString(),
    repo.name
  );

  try {
    // Run github-linguist to analyze languages
    const { stdout } = await execAsync(
      `github-linguist --json`,
      { cwd: repoPath }
    );

    const langStats = JSON.parse(stdout);
    const entries = Object.entries(langStats).map(([lang, size]) => ({
      language: lang,
      size: Number(size),
    }));

    // Find primary language (largest)
    const topLang = entries.sort((a, b) => b.size - a.size)[0]?.language;

    await sql.begin(async (tx) => {
      // Update or insert each language
      for (const { language, size } of entries) {
        await tx`
          INSERT INTO language_stats (
            repository_id, commit_id, language, size, is_primary
          )
          VALUES (
            ${repositoryId}, ${commitId}, ${language},
            ${size}, ${language === topLang}
          )
          ON CONFLICT (repository_id, language)
          DO UPDATE SET
            commit_id = ${commitId},
            size = ${size},
            is_primary = ${language === topLang},
            updated_at = NOW()
        `;
      }

      // Delete languages not in current analysis
      const currentLangs = entries.map((e) => e.language);
      if (currentLangs.length > 0) {
        await tx`
          DELETE FROM language_stats
          WHERE repository_id = ${repositoryId}
            AND commit_id != ${commitId}
        `;
      }

      // Update primary language in repository
      if (topLang) {
        await tx`
          UPDATE repositories SET primary_language = ${topLang}
          WHERE id = ${repositoryId}
        `;
      }
    });
  } catch (error) {
    console.error('Failed to update language stats:', error);
    // Don't throw - language stats are optional
  }
}
```

## API Routes

Create `/Users/williamcory/plue/server/routes/repositories.ts`:

```typescript
import { Hono } from 'hono';
import { sql } from '../../lib/db';
import * as starService from '../services/star';
import * as forkService from '../services/fork';
import * as topicService from '../services/topics';
import * as languageService from '../services/languages';

const app = new Hono();

// Star/Unstar repository
app.post('/:owner/:repo/star', async (c) => {
  const { owner, repo } = c.req.param();
  const { userId } = await c.req.json(); // In real app, get from auth

  const [repository] = await sql`
    SELECT r.* FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE u.username = ${owner} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  await starService.starRepository(userId, repository.id, true);

  return c.json({
    starred: true,
    numStars: repository.num_stars + 1
  });
});

app.delete('/:owner/:repo/star', async (c) => {
  const { owner, repo } = c.req.param();
  const { userId } = await c.req.json();

  const [repository] = await sql`
    SELECT r.* FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE u.username = ${owner} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  await starService.starRepository(userId, repository.id, false);

  return c.json({
    starred: false,
    numStars: Math.max(0, repository.num_stars - 1)
  });
});

// Get stargazers
app.get('/:owner/:repo/stargazers', async (c) => {
  const { owner, repo } = c.req.param();
  const limit = parseInt(c.req.query('limit') || '30');
  const offset = parseInt(c.req.query('offset') || '0');

  const [repository] = await sql`
    SELECT r.* FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE u.username = ${owner} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const stargazers = await starService.getStargazers(
    repository.id,
    limit,
    offset
  );

  return c.json({ stargazers });
});

// Fork repository
app.post('/:owner/:repo/fork', async (c) => {
  const { owner, repo } = c.req.param();
  const body = await c.req.json();
  const { userId, name, description, singleBranch } = body;

  const [repository] = await sql`
    SELECT r.* FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE u.username = ${owner} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  try {
    const forkedRepo = await forkService.forkRepository(
      repository.id,
      userId,
      { name, description, singleBranch }
    );

    return c.json({ repository: forkedRepo }, 201);
  } catch (error) {
    return c.json({ error: (error as Error).message }, 400);
  }
});

// Get forks
app.get('/:owner/:repo/forks', async (c) => {
  const { owner, repo } = c.req.param();
  const limit = parseInt(c.req.query('limit') || '30');
  const offset = parseInt(c.req.query('offset') || '0');

  const [repository] = await sql`
    SELECT r.* FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE u.username = ${owner} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const forks = await forkService.getForks(repository.id, limit, offset);

  return c.json({ forks });
});

// Save topics
app.put('/:owner/:repo/topics', async (c) => {
  const { owner, repo } = c.req.param();
  const { topics } = await c.req.json();

  const [repository] = await sql`
    SELECT r.* FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE u.username = ${owner} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  try {
    await topicService.saveTopics(repository.id, topics);
    const updated = await topicService.getRepositoryTopics(repository.id);
    return c.json({ topics: updated });
  } catch (error) {
    return c.json({ error: (error as Error).message }, 400);
  }
});

// Get topics
app.get('/:owner/:repo/topics', async (c) => {
  const { owner, repo } = c.req.param();

  const [repository] = await sql`
    SELECT r.* FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE u.username = ${owner} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const topics = await topicService.getRepositoryTopics(repository.id);
  return c.json({ topics });
});

// Get language statistics
app.get('/:owner/:repo/languages', async (c) => {
  const { owner, repo } = c.req.param();
  const top = c.req.query('top');

  const [repository] = await sql`
    SELECT r.* FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE u.username = ${owner} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const languages = top
    ? await languageService.getTopLanguageStats(repository.id, parseInt(top))
    : await languageService.getLanguageStats(repository.id);

  return c.json({ languages });
});

export default app;
```

Register routes in `/Users/williamcory/plue/server/index.ts`:

```typescript
import repositories from './routes/repositories';

app.route('/api/repos', repositories);
```

## UI Components

### Star Button Component

Create `/Users/williamcory/plue/ui/components/StarButton.astro`:

```astro
---
interface Props {
  owner: string;
  repo: string;
  isStarred: boolean;
  starCount: number;
}

const { owner, repo, isStarred, starCount } = Astro.props;
---

<button
  class="star-button"
  data-owner={owner}
  data-repo={repo}
  data-starred={isStarred}
>
  <span class="star-icon">{isStarred ? '★' : '☆'}</span>
  <span class="star-text">{isStarred ? 'Unstar' : 'Star'}</span>
  <span class="star-count">{starCount}</span>
</button>

<script>
  document.querySelectorAll('.star-button').forEach((button) => {
    button.addEventListener('click', async () => {
      const owner = button.getAttribute('data-owner')!;
      const repo = button.getAttribute('data-repo')!;
      const isStarred = button.getAttribute('data-starred') === 'true';

      const method = isStarred ? 'DELETE' : 'POST';
      const response = await fetch(`/api/repos/${owner}/${repo}/star`, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ userId: 1 }), // Get from auth
      });

      if (response.ok) {
        const data = await response.json();
        button.setAttribute('data-starred', String(data.starred));
        button.querySelector('.star-icon')!.textContent = data.starred ? '★' : '☆';
        button.querySelector('.star-text')!.textContent = data.starred
          ? 'Unstar'
          : 'Star';
        button.querySelector('.star-count')!.textContent = data.numStars;
      }
    });
  });
</script>

<style>
  .star-button {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 1rem;
    border: 2px solid #000;
    background: #fff;
    cursor: pointer;
    font-size: 14px;
  }

  .star-button:hover {
    background: #f0f0f0;
  }

  .star-icon {
    font-size: 18px;
  }

  .star-count {
    font-weight: bold;
  }
</style>
```

### Language Bar Component

Create `/Users/williamcory/plue/ui/components/LanguageBar.astro`:

```astro
---
interface Language {
  language: string;
  percentage: number;
  color: string;
}

interface Props {
  languages: Language[];
}

const { languages } = Astro.props;
---

{
  languages.length > 0 && (
    <div class="language-bar">
      <div class="bar">
        {languages.map((lang) => (
          <div
            class="segment"
            style={`width: ${lang.percentage}%; background-color: ${lang.color}`}
            title={`${lang.language}: ${lang.percentage}%`}
          />
        ))}
      </div>
      <div class="legend">
        {languages.map((lang) => (
          <div class="legend-item">
            <span
              class="color-dot"
              style={`background-color: ${lang.color}`}
            />
            <span class="language-name">{lang.language}</span>
            <span class="percentage">{lang.percentage}%</span>
          </div>
        ))}
      </div>
    </div>
  )
}

<style>
  .language-bar {
    margin: 1rem 0;
  }

  .bar {
    display: flex;
    height: 8px;
    border: 1px solid #000;
    overflow: hidden;
  }

  .segment {
    height: 100%;
  }

  .legend {
    display: flex;
    flex-wrap: wrap;
    gap: 1rem;
    margin-top: 0.5rem;
    font-size: 12px;
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 0.25rem;
  }

  .color-dot {
    width: 10px;
    height: 10px;
    border: 1px solid #000;
    display: inline-block;
  }

  .percentage {
    font-weight: bold;
  }
</style>
```

### Topics Component

Create `/Users/williamcory/plue/ui/components/Topics.astro`:

```astro
---
interface Topic {
  id: number;
  name: string;
  repo_count: number;
}

interface Props {
  topics: Topic[];
  editable?: boolean;
}

const { topics, editable = false } = Astro.props;
---

<div class="topics" data-editable={editable}>
  {
    topics.map((topic) => (
      <a href={`/topics/${topic.name}`} class="topic-tag">
        {topic.name}
      </a>
    ))
  }
  {editable && <button class="btn-edit-topics">Edit topics</button>}
</div>

<style>
  .topics {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin: 1rem 0;
  }

  .topic-tag {
    display: inline-block;
    padding: 0.25rem 0.75rem;
    border: 1px solid #000;
    background: #f5f5f5;
    text-decoration: none;
    color: #000;
    font-size: 12px;
  }

  .topic-tag:hover {
    background: #e0e0e0;
  }

  .btn-edit-topics {
    padding: 0.25rem 0.75rem;
    border: 1px solid #000;
    background: #fff;
    cursor: pointer;
    font-size: 12px;
  }
</style>
```

### Fork Button Component

Create `/Users/williamcory/plue/ui/components/ForkButton.astro`:

```astro
---
interface Props {
  owner: string;
  repo: string;
  forkCount: number;
  hasForked?: boolean;
}

const { owner, repo, forkCount, hasForked = false } = Astro.props;
---

<button
  class="fork-button"
  data-owner={owner}
  data-repo={repo}
  data-has-forked={hasForked}
>
  <span class="fork-icon">⑂</span>
  <span class="fork-text">Fork</span>
  <span class="fork-count">{forkCount}</span>
</button>

{
  hasForked && (
    <div class="fork-notice">
      You already forked this repository
    </div>
  )
}

<script>
  document.querySelectorAll('.fork-button').forEach((button) => {
    button.addEventListener('click', async () => {
      const owner = button.getAttribute('data-owner')!;
      const repo = button.getAttribute('data-repo')!;
      const hasForked = button.getAttribute('data-has-forked') === 'true';

      if (hasForked) {
        // Navigate to user's fork
        window.location.href = `/${owner}/${repo}`;
        return;
      }

      // Show fork modal/dialog
      const name = prompt('Fork name:', repo);
      if (!name) return;

      const response = await fetch(`/api/repos/${owner}/${repo}/fork`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          userId: 1, // Get from auth
          name,
          description: '',
        }),
      });

      if (response.ok) {
        const data = await response.json();
        window.location.href = `/${owner}/${name}`;
      } else {
        alert('Failed to fork repository');
      }
    });
  });
</script>

<style>
  .fork-button {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 1rem;
    border: 2px solid #000;
    background: #fff;
    cursor: pointer;
    font-size: 14px;
  }

  .fork-button:hover {
    background: #f0f0f0;
  }

  .fork-icon {
    font-size: 18px;
  }

  .fork-count {
    font-weight: bold;
  }

  .fork-notice {
    margin-top: 0.5rem;
    padding: 0.5rem;
    border: 1px solid #000;
    background: #fffacd;
    font-size: 12px;
  }
</style>
```

## Update Repository Page

Update `/Users/williamcory/plue/ui/pages/[user]/[repo]/index.astro`:

```astro
---
import Layout from "../../../layouts/Layout.astro";
import Header from "../../../components/Header.astro";
import FileTree from "../../../components/FileTree.astro";
import Markdown from "../../../components/Markdown.astro";
import StarButton from "../../../components/StarButton.astro";
import ForkButton from "../../../components/ForkButton.astro";
import Topics from "../../../components/Topics.astro";
import LanguageBar from "../../../components/LanguageBar.astro";
import { sql } from "../../../lib/db";
import { getTree, getFileContent, getCloneUrl } from "../../../lib/git";
import type { User, Repository } from "../../../lib/types";

const { user: username, repo: reponame } = Astro.params;
const currentUserId = 1; // Get from auth

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

// Get star status
const [{ isStarred }] = await sql`
  SELECT EXISTS(
    SELECT 1 FROM repository_stars
    WHERE user_id = ${currentUserId} AND repository_id = ${repo.id}
  ) as "isStarred"
`;

// Get fork status
const [{ hasForked }] = await sql`
  SELECT EXISTS(
    SELECT 1 FROM repositories
    WHERE user_id = ${currentUserId} AND fork_id = ${repo.id}
  ) as "hasForked"
`;

// Get topics
const topics = await sql`
  SELECT t.* FROM topics t
  INNER JOIN repository_topics rt ON rt.topic_id = t.id
  WHERE rt.repository_id = ${repo.id}
  ORDER BY t.name ASC
`;

// Get language stats
const languages = await sql`
  SELECT language, size FROM language_stats
  WHERE repository_id = ${repo.id}
  ORDER BY size DESC
  LIMIT 5
`;

const total = languages.reduce((sum, l) => sum + Number(l.size), 0);
const languagesWithPercentage = languages.map((l) => ({
  language: l.language,
  percentage: total > 0 ? Math.round((Number(l.size) / total) * 1000) / 10 : 0,
  color: getLanguageColor(l.language),
}));

// Get license
const [license] = await sql`
  SELECT license FROM repository_licenses
  WHERE repository_id = ${repo.id}
  LIMIT 1
`;

// Get fork source if this is a fork
let forkSource = null;
if (repo.is_fork && repo.fork_id) {
  [forkSource] = await sql`
    SELECT r.*, u.username FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE r.id = ${repo.fork_id}
  `;
}

const defaultBranch = repo.default_branch || "main";
const tree = await getTree(username!, reponame!, defaultBranch);

// Try to get README
let readme = "";
const readmeFile = tree.find(
  (f) => f.name.toLowerCase().startsWith("readme") && f.type === "blob"
);
if (readmeFile) {
  readme = (await getFileContent(username!, reponame!, defaultBranch, readmeFile.name)) || "";
}

const cloneUrl = getCloneUrl(username!, reponame!);

const [{ count: issueCount }] = await sql`
  SELECT COUNT(*) as count FROM issues WHERE repository_id = ${repo.id} AND state = 'open'
`;

function getLanguageColor(lang: string): string {
  const colors: Record<string, string> = {
    javascript: '#f1e05a',
    typescript: '#3178c6',
    python: '#3572A5',
    // ... add more
  };
  return colors[lang.toLowerCase()] || '#cccccc';
}
---

<Layout title={`${username}/${reponame} · plue`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <span class="current">{reponame}</span>
  </div>

  {forkSource && (
    <div class="fork-notice">
      Forked from <a href={`/${forkSource.username}/${forkSource.name}`}>
        {forkSource.username}/{forkSource.name}
      </a>
    </div>
  )}

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`} class="active">Code</a>
    <a href={`/${username}/${reponame}/issues`}>
      Issues
      {Number(issueCount) > 0 && <span class="badge">{issueCount}</span>}
    </a>
    <a href={`/${username}/${reponame}/commits/${defaultBranch}`}>Commits</a>
  </nav>

  <div class="container">
    <div class="repo-header">
      <div class="repo-info">
        {repo.description && <p class="description">{repo.description}</p>}

        {topics.length > 0 && <Topics topics={topics} />}

        <div class="repo-meta">
          {repo.primary_language && (
            <span class="meta-item">
              <span class="dot" style={`background: ${getLanguageColor(repo.primary_language)}`}></span>
              {repo.primary_language}
            </span>
          )}
          {license && (
            <span class="meta-item">
              License: {license.license}
            </span>
          )}
        </div>
      </div>

      <div class="repo-actions">
        <StarButton
          owner={username!}
          repo={reponame!}
          isStarred={isStarred}
          starCount={repo.num_stars || 0}
        />
        <ForkButton
          owner={username!}
          repo={reponame!}
          forkCount={repo.num_forks || 0}
          hasForked={hasForked}
        />
      </div>
    </div>

    {languagesWithPercentage.length > 0 && (
      <LanguageBar languages={languagesWithPercentage} />
    )}

    <div class="clone-url mb-3">
      <code>{cloneUrl}</code>
      <button class="btn btn-sm" onclick="navigator.clipboard.writeText(this.previousElementSibling.textContent)">
        Copy
      </button>
    </div>

    <FileTree tree={tree} user={username!} repo={reponame!} branch={defaultBranch} />

    {readme && (
      <div class="mt-3">
        <Markdown content={readme} />
      </div>
    )}
  </div>
</Layout>

<style>
  .repo-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    margin-bottom: 1rem;
    padding-bottom: 1rem;
    border-bottom: 2px solid #000;
  }

  .repo-info {
    flex: 1;
  }

  .repo-actions {
    display: flex;
    gap: 0.5rem;
  }

  .description {
    font-size: 14px;
    margin-bottom: 0.5rem;
  }

  .repo-meta {
    display: flex;
    gap: 1rem;
    font-size: 12px;
    margin-top: 0.5rem;
  }

  .meta-item {
    display: flex;
    align-items: center;
    gap: 0.25rem;
  }

  .dot {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    border: 1px solid #000;
  }

  .fork-notice {
    padding: 0.5rem 1rem;
    border: 2px solid #000;
    background: #fffacd;
    margin-bottom: 1rem;
    font-size: 14px;
  }

  .fork-notice a {
    font-weight: bold;
  }
</style>
```

## Background Jobs

Create `/Users/williamcory/plue/server/jobs/language-stats.ts`:

```typescript
/**
 * Background job to update language statistics for all repositories
 */

import { sql } from '../../lib/db';
import { updateLanguageStats } from '../services/languages';
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';

const execAsync = promisify(exec);

export async function updateAllLanguageStats() {
  const repos = await sql`
    SELECT r.id, r.name, r.user_id, r.default_branch, u.username
    FROM repositories r
    INNER JOIN users u ON u.id = r.user_id
    WHERE r.is_fork = false OR r.is_fork IS NULL
  `;

  console.log(`Updating language stats for ${repos.length} repositories...`);

  for (const repo of repos) {
    try {
      const repoPath = path.join(
        process.cwd(),
        'repos',
        repo.user_id.toString(),
        repo.name
      );

      // Get latest commit ID
      const { stdout } = await execAsync(
        `git rev-parse ${repo.default_branch}`,
        { cwd: repoPath }
      );

      const commitId = stdout.trim();

      await updateLanguageStats(repo.id, commitId);
      console.log(`✓ Updated ${repo.username}/${repo.name}`);
    } catch (error) {
      console.error(`✗ Failed ${repo.username}/${repo.name}:`, error);
    }
  }

  console.log('Language stats update complete');
}

// Run if executed directly
if (import.meta.main) {
  await updateAllLanguageStats();
  process.exit(0);
}
```

## Implementation Checklist

### Phase 1: Database & Models (Day 1)
- [ ] Add database tables (stars, topics, languages, licenses)
- [ ] Add columns to repositories table
- [ ] Run migration: `bun run db/migrate.ts`
- [ ] Create TypeScript types in `core/models/repository.ts`
- [ ] Test database schema with sample data

### Phase 2: Star Service (Day 1-2)
- [ ] Implement `server/services/star.ts`
- [ ] Add star/unstar API endpoints
- [ ] Create `StarButton.astro` component
- [ ] Test starring functionality
- [ ] Add star count display to repo page

### Phase 3: Topics (Day 2)
- [ ] Implement `server/services/topics.ts`
- [ ] Add topic validation logic
- [ ] Create `Topics.astro` component
- [ ] Add topic management API endpoints
- [ ] Test adding/removing topics
- [ ] Create topics listing page (optional)

### Phase 4: Language Statistics (Day 3)
- [ ] Install github-linguist: `gem install github-linguist`
- [ ] Implement `server/services/languages.ts`
- [ ] Create `LanguageBar.astro` component
- [ ] Add language stats API endpoint
- [ ] Create background job `jobs/language-stats.ts`
- [ ] Test language detection and display

### Phase 5: License Detection (Day 3)
- [ ] Add license detection to language stats job
- [ ] Display license in repo metadata
- [ ] Test with various license files (MIT, Apache, GPL)

### Phase 6: Fork Functionality (Day 4-5)
- [ ] Implement `server/services/fork.ts`
- [ ] Add git clone logic for forking
- [ ] Create `ForkButton.astro` component
- [ ] Add fork API endpoints
- [ ] Test forking workflow
- [ ] Display fork source on forked repos
- [ ] Create forks listing page

### Phase 7: Repository Templates (Day 6)
- [ ] Add `is_template` flag to repos
- [ ] Implement template generation logic
- [ ] Add "Use this template" button
- [ ] Test creating repo from template
- [ ] Support variable substitution in template files

### Phase 8: UI Polish (Day 7)
- [ ] Update repository index page with all new features
- [ ] Add responsive styles
- [ ] Test all interactions
- [ ] Add loading states to buttons
- [ ] Improve error handling and user feedback

### Phase 9: Testing & Documentation (Day 8)
- [ ] Write tests for star service
- [ ] Write tests for fork service
- [ ] Write tests for topic service
- [ ] Document API endpoints
- [ ] Create migration guide for existing repos
- [ ] Performance test with large repos

## Testing Notes

### Manual Testing Checklist
1. Star/unstar repositories as different users
2. Fork a repository and verify git clone worked
3. Add/remove topics from repository
4. Verify language bar shows correct percentages
5. Test forking with single-branch option
6. Create repository from template
7. Verify fork counts increment/decrement correctly
8. Check that language stats background job runs successfully

### Edge Cases to Test
- Starring already-starred repo (should be idempotent)
- Forking already-forked repo (should error)
- Invalid topic names (special chars, too long)
- Empty repositories (no languages)
- Repositories without LICENSE file
- Very large repositories (performance)

## Performance Considerations

1. **Language Stats**: Run as background job, not on-demand
2. **Star Counts**: Denormalized in repositories table for fast reads
3. **Fork Counts**: Denormalized in repositories table for fast reads
4. **Topics**: Use join table with indexes for efficient queries
5. **Git Operations**: Use bare clones for forks to save disk space

## Security Notes

1. Validate all topic names against regex pattern
2. Check user permissions before allowing fork
3. Sanitize repository names in fork operations
4. Rate limit star/unstar operations
5. Validate commit IDs before updating stats

## Reference Code Translation

Key Gitea patterns translated to TypeScript:

| Gitea Pattern | Plue Pattern |
|---------------|--------------|
| `db.WithTx()` | `sql.begin()` |
| `xorm.Get()` | `sql SELECT ... LIMIT 1` |
| `xorm.Insert()` | `sql INSERT ... RETURNING *` |
| `xorm.Update()` | `sql UPDATE ... SET` |
| `models/repo/` | `core/models/` + `server/services/` |
| `routers/web/repo/` | `server/routes/` |

## Additional Features (Future)

- [ ] Watch/unwatch repositories (notifications)
- [ ] Repository transfer (change owner)
- [ ] Archive/unarchive repositories
- [ ] Repository visibility settings
- [ ] Advanced template variables
- [ ] Topic autocomplete
- [ ] Language detection via tree-sitter
- [ ] Repository badges/shields
- [ ] Network graph (forks visualization)

## Resources

- Gitea star model: `/Users/williamcory/plue/gitea/models/repo/star.go`
- Gitea fork service: `/Users/williamcory/plue/gitea/services/repository/fork.go`
- Gitea topics: `/Users/williamcory/plue/gitea/models/repo/topic.go`
- Gitea languages: `/Users/williamcory/plue/gitea/models/repo/language_stats.go`
- github-linguist: https://github.com/github-linguist/linguist
