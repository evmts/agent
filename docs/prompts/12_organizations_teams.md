# Organizations & Teams Feature Implementation

## Overview

Implement a complete Organizations and Teams system for Plue, allowing users to create organizations, manage teams with granular permissions, and collaborate on repositories at scale. This mirrors GitHub/Gitea's organization model where organizations are special user types that can own repositories and manage access through teams.

**Scope:**
- Organizations as special user types
- Organization creation, profile, and settings pages
- Member management (owners, members, visibility)
- Team creation and management
- Team permissions (read, write, admin) with repository assignment
- Team-based repository access control
- Organization-owned repositories
- Member invitation system

**Out of scope (future features):**
- Organization webhooks
- Organization-level CI/CD runners
- Organization audit logs
- Team synchronization with external systems
- Organization-wide projects/boards

## Tech Stack

- **Runtime**: Bun (not Node.js)
- **Backend**: Hono server with middleware
- **Frontend**: Astro v5 (SSR)
- **Database**: PostgreSQL with `postgres` client
- **Validation**: Zod v4

---

## 1. Database Schema Changes

### 1.1 Update `users` Table

Organizations are stored in the same `users` table with a `type` field to distinguish them:

```sql
-- Add type field to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS type VARCHAR(20) NOT NULL DEFAULT 'user'
  CHECK (type IN ('user', 'organization'));

-- Organization-specific fields
ALTER TABLE users ADD COLUMN IF NOT EXISTS visibility VARCHAR(20) DEFAULT 'public'
  CHECK (visibility IN ('public', 'limited', 'private'));
ALTER TABLE users ADD COLUMN IF NOT EXISTS location VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS website VARCHAR(2048);
ALTER TABLE users ADD COLUMN IF NOT EXISTS max_repo_creation INTEGER DEFAULT -1; -- -1 = unlimited
ALTER TABLE users ADD COLUMN IF NOT EXISTS num_teams INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS num_members INTEGER DEFAULT 0;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_users_type ON users(type);
```

**Migration note**: Existing users default to `type = 'user'`.

### 1.2 Organization Users Table

Maps which users are members of which organizations:

```sql
-- Organization members
CREATE TABLE IF NOT EXISTS org_users (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  org_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  is_public BOOLEAN NOT NULL DEFAULT false, -- Is membership visible publicly?
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, org_id)
);

CREATE INDEX IF NOT EXISTS idx_org_users_user_id ON org_users(user_id);
CREATE INDEX IF NOT EXISTS idx_org_users_org_id ON org_users(org_id);
CREATE INDEX IF NOT EXISTS idx_org_users_is_public ON org_users(is_public);

-- Constraint: org_id must reference organization type
-- Note: PostgreSQL doesn't support cross-table CHECK constraints easily,
-- so enforce in application layer or use triggers
```

### 1.3 Teams Table

Teams are groups within organizations with specific permissions:

```sql
-- Teams within organizations
CREATE TABLE IF NOT EXISTS teams (
  id SERIAL PRIMARY KEY,
  org_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  lower_name VARCHAR(255) NOT NULL, -- for case-insensitive lookups
  description TEXT,

  -- Permissions
  access_mode VARCHAR(20) NOT NULL DEFAULT 'read'
    CHECK (access_mode IN ('none', 'read', 'write', 'admin', 'owner')),

  -- Settings
  includes_all_repositories BOOLEAN NOT NULL DEFAULT false,
  can_create_org_repo BOOLEAN NOT NULL DEFAULT false,

  -- Stats
  num_repos INTEGER DEFAULT 0,
  num_members INTEGER DEFAULT 0,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(org_id, lower_name)
);

CREATE INDEX IF NOT EXISTS idx_teams_org_id ON teams(org_id);
CREATE INDEX IF NOT EXISTS idx_teams_lower_name ON teams(org_id, lower_name);

-- Reserved team name constant: "Owners" (created automatically)
```

**Access modes explained:**
- `none`: No access (placeholder)
- `read`: Read-only access to repositories
- `write`: Read + write access (push, create branches)
- `admin`: Write + admin access (settings, webhooks, delete)
- `owner`: Full organization control (only for "Owners" team)

### 1.4 Team Users Table

Maps which users belong to which teams:

```sql
-- Team members
CREATE TABLE IF NOT EXISTS team_users (
  id SERIAL PRIMARY KEY,
  org_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  team_id INTEGER NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(team_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_team_users_team_id ON team_users(team_id);
CREATE INDEX IF NOT EXISTS idx_team_users_user_id ON team_users(user_id);
CREATE INDEX IF NOT EXISTS idx_team_users_org_id ON team_users(org_id);
```

### 1.5 Team Repositories Table

Maps which teams have access to which repositories:

```sql
-- Team-repository access
CREATE TABLE IF NOT EXISTS team_repos (
  id SERIAL PRIMARY KEY,
  org_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  team_id INTEGER NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  repo_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(team_id, repo_id)
);

CREATE INDEX IF NOT EXISTS idx_team_repos_team_id ON team_repos(team_id);
CREATE INDEX IF NOT EXISTS idx_team_repos_repo_id ON team_repos(repo_id);
CREATE INDEX IF NOT EXISTS idx_team_repos_org_id ON team_repos(org_id);
```

### 1.6 Schema Migration

Add these tables to `/Users/williamcory/plue/db/schema.sql` after the existing `users` table.

Update `/Users/williamcory/plue/db/migrate.ts` to run the schema additions.

---

## 2. TypeScript Types

Create `/Users/williamcory/plue/ui/lib/types.ts` additions:

```typescript
export type UserType = 'user' | 'organization';

export type VisibilityType = 'public' | 'limited' | 'private';

export type AccessMode = 'none' | 'read' | 'write' | 'admin' | 'owner';

export interface Organization {
  id: number;
  username: string;
  display_name: string | null;
  bio: string | null;
  type: 'organization';
  visibility: VisibilityType;
  location: string | null;
  website: string | null;
  max_repo_creation: number;
  num_teams: number;
  num_members: number;
  created_at: Date;
  updated_at: Date;
}

export interface OrgUser {
  id: number;
  user_id: number;
  org_id: number;
  is_public: boolean;
  created_at: Date;
}

export interface Team {
  id: number;
  org_id: number;
  name: string;
  lower_name: string;
  description: string | null;
  access_mode: AccessMode;
  includes_all_repositories: boolean;
  can_create_org_repo: boolean;
  num_repos: number;
  num_members: number;
  created_at: Date;
  updated_at: Date;
}

export interface TeamUser {
  id: number;
  org_id: number;
  team_id: number;
  user_id: number;
  created_at: Date;
}

export interface TeamRepo {
  id: number;
  org_id: number;
  team_id: number;
  repo_id: number;
  created_at: Date;
}

// Joined types for display
export interface TeamWithMembers extends Team {
  members: User[];
}

export interface TeamWithRepos extends Team {
  repositories: Repository[];
}

export interface OrgMember extends User {
  is_public: boolean;
  is_owner: boolean;
}
```

---

## 3. Backend Implementation

### 3.1 Organization Service

Create `/Users/williamcory/plue/server/services/organization.ts`:

```typescript
import { sql } from "../../ui/lib/db";
import type { Organization, OrgUser, Team, TeamUser, User } from "../../ui/lib/types";

export const OWNER_TEAM_NAME = "Owners";

interface CreateOrgParams {
  username: string;
  display_name?: string;
  bio?: string;
  visibility?: 'public' | 'limited' | 'private';
}

/**
 * Create a new organization
 * Adapted from: gitea/models/organization/org.go::CreateOrganization
 */
export async function createOrganization(
  params: CreateOrgParams,
  owner: User
): Promise<Organization> {
  const { username, display_name, bio, visibility = 'public' } = params;

  // Validate username is available
  const existing = await sql`
    SELECT id FROM users WHERE username = ${username}
  `;
  if (existing.length > 0) {
    throw new Error(`Username "${username}" is already taken`);
  }

  // Transaction: Create org + owner membership + owner team
  const result = await sql.begin(async (sql) => {
    // 1. Create organization user
    const [org] = await sql`
      INSERT INTO users (
        username,
        display_name,
        bio,
        type,
        visibility,
        num_teams,
        num_members
      )
      VALUES (
        ${username},
        ${display_name || username},
        ${bio || null},
        'organization',
        ${visibility},
        1,
        1
      )
      RETURNING *
    ` as Organization[];

    // 2. Add owner to organization
    await sql`
      INSERT INTO org_users (user_id, org_id, is_public)
      VALUES (${owner.id}, ${org.id}, ${visibility === 'public'})
    `;

    // 3. Create "Owners" team
    const [ownerTeam] = await sql`
      INSERT INTO teams (
        org_id,
        name,
        lower_name,
        description,
        access_mode,
        includes_all_repositories,
        can_create_org_repo,
        num_members
      )
      VALUES (
        ${org.id},
        ${OWNER_TEAM_NAME},
        ${OWNER_TEAM_NAME.toLowerCase()},
        'Organization owners with full access',
        'owner',
        true,
        true,
        1
      )
      RETURNING *
    ` as Team[];

    // 4. Add owner to owner team
    await sql`
      INSERT INTO team_users (org_id, team_id, user_id)
      VALUES (${org.id}, ${ownerTeam.id}, ${owner.id})
    `;

    return org;
  });

  return result;
}

/**
 * Get organization by username
 * Adapted from: gitea/models/organization/org.go::GetOrgByName
 */
export async function getOrganizationByUsername(
  username: string
): Promise<Organization | null> {
  const [org] = await sql`
    SELECT * FROM users
    WHERE username = ${username}
    AND type = 'organization'
  ` as Organization[];

  return org || null;
}

/**
 * Check if user is organization member
 * Adapted from: gitea/models/organization/org_user.go::IsOrganizationMember
 */
export async function isOrganizationMember(
  orgId: number,
  userId: number
): Promise<boolean> {
  const result = await sql`
    SELECT 1 FROM org_users
    WHERE org_id = ${orgId}
    AND user_id = ${userId}
    LIMIT 1
  `;
  return result.length > 0;
}

/**
 * Check if user is organization owner
 * Adapted from: gitea/models/organization/org_user.go::IsOrganizationOwner
 */
export async function isOrganizationOwner(
  orgId: number,
  userId: number
): Promise<boolean> {
  const result = await sql`
    SELECT 1 FROM team_users tu
    JOIN teams t ON tu.team_id = t.id
    WHERE tu.org_id = ${orgId}
    AND tu.user_id = ${userId}
    AND t.name = ${OWNER_TEAM_NAME}
    LIMIT 1
  `;
  return result.length > 0;
}

/**
 * Get organization members
 * Adapted from: gitea/models/organization/org.go::FindOrgMembers
 */
export async function getOrganizationMembers(
  orgId: number,
  publicOnly: boolean = false
): Promise<OrgMember[]> {
  const query = publicOnly
    ? sql`
        SELECT u.*, ou.is_public
        FROM users u
        JOIN org_users ou ON u.id = ou.user_id
        WHERE ou.org_id = ${orgId}
        AND ou.is_public = true
        ORDER BY u.username
      `
    : sql`
        SELECT u.*, ou.is_public
        FROM users u
        JOIN org_users ou ON u.id = ou.user_id
        WHERE ou.org_id = ${orgId}
        ORDER BY u.username
      `;

  const members = await query as any[];

  // Add is_owner flag
  const memberIds = members.map(m => m.id);
  const owners = await sql`
    SELECT tu.user_id
    FROM team_users tu
    JOIN teams t ON tu.team_id = t.id
    WHERE tu.org_id = ${orgId}
    AND t.name = ${OWNER_TEAM_NAME}
    AND tu.user_id IN ${sql(memberIds)}
  ` as { user_id: number }[];

  const ownerIds = new Set(owners.map(o => o.user_id));

  return members.map(m => ({
    ...m,
    is_owner: ownerIds.has(m.id)
  }));
}

/**
 * Add user to organization
 * Adapted from: gitea/models/organization/org.go::AddOrgUser
 */
export async function addOrganizationMember(
  orgId: number,
  userId: number,
  isPublic: boolean = false
): Promise<void> {
  await sql.begin(async (sql) => {
    // Check if already a member
    const existing = await sql`
      SELECT id FROM org_users
      WHERE org_id = ${orgId} AND user_id = ${userId}
    `;
    if (existing.length > 0) {
      throw new Error("User is already a member");
    }

    // Add membership
    await sql`
      INSERT INTO org_users (org_id, user_id, is_public)
      VALUES (${orgId}, ${userId}, ${isPublic})
    `;

    // Increment member count
    await sql`
      UPDATE users
      SET num_members = num_members + 1
      WHERE id = ${orgId}
    `;
  });
}

/**
 * Remove user from organization
 */
export async function removeOrganizationMember(
  orgId: number,
  userId: number
): Promise<void> {
  // Check if user is last owner
  const isOwner = await isOrganizationOwner(orgId, userId);
  if (isOwner) {
    const ownerCount = await sql`
      SELECT COUNT(*) as count
      FROM team_users tu
      JOIN teams t ON tu.team_id = t.id
      WHERE tu.org_id = ${orgId}
      AND t.name = ${OWNER_TEAM_NAME}
    ` as { count: number }[];

    if (ownerCount[0].count <= 1) {
      throw new Error("Cannot remove the last owner");
    }
  }

  await sql.begin(async (sql) => {
    // Remove from all teams
    await sql`
      DELETE FROM team_users
      WHERE org_id = ${orgId} AND user_id = ${userId}
    `;

    // Remove org membership
    await sql`
      DELETE FROM org_users
      WHERE org_id = ${orgId} AND user_id = ${userId}
    `;

    // Decrement member count
    await sql`
      UPDATE users
      SET num_members = num_members - 1
      WHERE id = ${orgId}
    `;
  });
}
```

### 3.2 Team Service

Create `/Users/williamcory/plue/server/services/team.ts`:

```typescript
import { sql } from "../../ui/lib/db";
import type { Team, TeamUser, TeamRepo, User, Repository } from "../../ui/lib/types";
import { OWNER_TEAM_NAME } from "./organization";

interface CreateTeamParams {
  org_id: number;
  name: string;
  description?: string;
  access_mode?: 'read' | 'write' | 'admin';
  includes_all_repositories?: boolean;
  can_create_org_repo?: boolean;
}

/**
 * Create a new team
 * Adapted from: gitea/models/organization/team.go
 */
export async function createTeam(params: CreateTeamParams): Promise<Team> {
  const {
    org_id,
    name,
    description = '',
    access_mode = 'read',
    includes_all_repositories = false,
    can_create_org_repo = false
  } = params;

  // Validate name
  if (name.toLowerCase() === OWNER_TEAM_NAME.toLowerCase()) {
    throw new Error(`Team name "${OWNER_TEAM_NAME}" is reserved`);
  }
  if (name.toLowerCase() === 'new') {
    throw new Error('Team name "new" is reserved');
  }

  // Check if team already exists
  const existing = await sql`
    SELECT id FROM teams
    WHERE org_id = ${org_id}
    AND lower_name = ${name.toLowerCase()}
  `;
  if (existing.length > 0) {
    throw new Error(`Team "${name}" already exists`);
  }

  const result = await sql.begin(async (sql) => {
    // Create team
    const [team] = await sql`
      INSERT INTO teams (
        org_id,
        name,
        lower_name,
        description,
        access_mode,
        includes_all_repositories,
        can_create_org_repo,
        num_repos,
        num_members
      )
      VALUES (
        ${org_id},
        ${name},
        ${name.toLowerCase()},
        ${description},
        ${access_mode},
        ${includes_all_repositories},
        ${can_create_org_repo},
        0,
        0
      )
      RETURNING *
    ` as Team[];

    // Increment org team count
    await sql`
      UPDATE users
      SET num_teams = num_teams + 1
      WHERE id = ${org_id}
    `;

    return team;
  });

  return result;
}

/**
 * Get team by name within organization
 * Adapted from: gitea/models/organization/team.go::GetTeam
 */
export async function getTeamByName(
  orgId: number,
  teamName: string
): Promise<Team | null> {
  const [team] = await sql`
    SELECT * FROM teams
    WHERE org_id = ${orgId}
    AND lower_name = ${teamName.toLowerCase()}
  ` as Team[];

  return team || null;
}

/**
 * Get all teams in organization
 * Adapted from: gitea/models/organization/org.go::FindOrgTeams
 */
export async function getOrganizationTeams(orgId: number): Promise<Team[]> {
  const teams = await sql`
    SELECT * FROM teams
    WHERE org_id = ${orgId}
    ORDER BY
      CASE WHEN name = ${OWNER_TEAM_NAME} THEN 0 ELSE 1 END,
      name ASC
  ` as Team[];

  return teams;
}

/**
 * Add user to team
 */
export async function addTeamMember(
  teamId: number,
  userId: number
): Promise<void> {
  await sql.begin(async (sql) => {
    // Get team info
    const [team] = await sql`
      SELECT org_id FROM teams WHERE id = ${teamId}
    ` as { org_id: number }[];
    if (!team) {
      throw new Error("Team not found");
    }

    // Check if user is org member
    const isMember = await sql`
      SELECT 1 FROM org_users
      WHERE org_id = ${team.org_id}
      AND user_id = ${userId}
    `;
    if (isMember.length === 0) {
      throw new Error("User must be organization member first");
    }

    // Check if already in team
    const existing = await sql`
      SELECT id FROM team_users
      WHERE team_id = ${teamId} AND user_id = ${userId}
    `;
    if (existing.length > 0) {
      throw new Error("User is already a team member");
    }

    // Add to team
    await sql`
      INSERT INTO team_users (org_id, team_id, user_id)
      VALUES (${team.org_id}, ${teamId}, ${userId})
    `;

    // Increment team member count
    await sql`
      UPDATE teams
      SET num_members = num_members + 1
      WHERE id = ${teamId}
    `;
  });
}

/**
 * Remove user from team
 */
export async function removeTeamMember(
  teamId: number,
  userId: number
): Promise<void> {
  await sql.begin(async (sql) => {
    // Check if this is the owner team
    const [team] = await sql`
      SELECT name, org_id FROM teams WHERE id = ${teamId}
    ` as { name: string; org_id: number }[];

    if (team.name === OWNER_TEAM_NAME) {
      // Check if last owner
      const ownerCount = await sql`
        SELECT COUNT(*) as count
        FROM team_users
        WHERE team_id = ${teamId}
      ` as { count: number }[];

      if (ownerCount[0].count <= 1) {
        throw new Error("Cannot remove the last owner");
      }
    }

    // Remove from team
    await sql`
      DELETE FROM team_users
      WHERE team_id = ${teamId} AND user_id = ${userId}
    `;

    // Decrement team member count
    await sql`
      UPDATE teams
      SET num_members = num_members - 1
      WHERE id = ${teamId}
    `;
  });
}

/**
 * Get team members
 */
export async function getTeamMembers(teamId: number): Promise<User[]> {
  const members = await sql`
    SELECT u.*
    FROM users u
    JOIN team_users tu ON u.id = tu.user_id
    WHERE tu.team_id = ${teamId}
    ORDER BY u.username
  ` as User[];

  return members;
}

/**
 * Add repository to team
 * Adapted from: gitea/models/organization/team_repo.go::AddTeamRepo
 */
export async function addTeamRepository(
  teamId: number,
  repoId: number
): Promise<void> {
  await sql.begin(async (sql) => {
    // Get team info
    const [team] = await sql`
      SELECT org_id FROM teams WHERE id = ${teamId}
    ` as { org_id: number }[];
    if (!team) {
      throw new Error("Team not found");
    }

    // Verify repo belongs to organization
    const [repo] = await sql`
      SELECT id FROM repositories
      WHERE id = ${repoId} AND user_id = ${team.org_id}
    `;
    if (!repo) {
      throw new Error("Repository not found or not owned by organization");
    }

    // Check if already added
    const existing = await sql`
      SELECT id FROM team_repos
      WHERE team_id = ${teamId} AND repo_id = ${repoId}
    `;
    if (existing.length > 0) {
      return; // Already added
    }

    // Add repository
    await sql`
      INSERT INTO team_repos (org_id, team_id, repo_id)
      VALUES (${team.org_id}, ${teamId}, ${repoId})
    `;

    // Increment team repo count
    await sql`
      UPDATE teams
      SET num_repos = num_repos + 1
      WHERE id = ${teamId}
    `;
  });
}

/**
 * Remove repository from team
 */
export async function removeTeamRepository(
  teamId: number,
  repoId: number
): Promise<void> {
  await sql.begin(async (sql) => {
    await sql`
      DELETE FROM team_repos
      WHERE team_id = ${teamId} AND repo_id = ${repoId}
    `;

    await sql`
      UPDATE teams
      SET num_repos = num_repos - 1
      WHERE id = ${teamId}
    `;
  });
}

/**
 * Get team repositories
 */
export async function getTeamRepositories(teamId: number): Promise<Repository[]> {
  const repos = await sql`
    SELECT r.*
    FROM repositories r
    JOIN team_repos tr ON r.id = tr.repo_id
    WHERE tr.team_id = ${teamId}
    ORDER BY r.name
  ` as Repository[];

  return repos;
}

/**
 * Get user's teams in organization
 */
export async function getUserTeamsInOrg(
  userId: number,
  orgId: number
): Promise<Team[]> {
  const teams = await sql`
    SELECT t.*
    FROM teams t
    JOIN team_users tu ON t.id = tu.team_id
    WHERE tu.user_id = ${userId}
    AND tu.org_id = ${orgId}
    ORDER BY
      CASE WHEN t.name = ${OWNER_TEAM_NAME} THEN 0 ELSE 1 END,
      t.name ASC
  ` as Team[];

  return teams;
}

/**
 * Check if user has access to repository through teams
 */
export async function getUserRepoAccessMode(
  userId: number,
  repoId: number
): Promise<'none' | 'read' | 'write' | 'admin' | 'owner'> {
  // Get highest access mode from all teams user belongs to
  const result = await sql`
    SELECT MAX(
      CASE t.access_mode
        WHEN 'owner' THEN 5
        WHEN 'admin' THEN 4
        WHEN 'write' THEN 3
        WHEN 'read' THEN 2
        ELSE 1
      END
    ) as max_access
    FROM teams t
    JOIN team_users tu ON t.id = tu.team_id
    LEFT JOIN team_repos tr ON t.id = tr.team_id
    WHERE tu.user_id = ${userId}
    AND (tr.repo_id = ${repoId} OR t.includes_all_repositories = true)
  ` as { max_access: number }[];

  const accessLevel = result[0]?.max_access || 0;

  if (accessLevel >= 5) return 'owner';
  if (accessLevel >= 4) return 'admin';
  if (accessLevel >= 3) return 'write';
  if (accessLevel >= 2) return 'read';
  return 'none';
}
```

### 3.3 API Routes

Create `/Users/williamcory/plue/server/routes/organizations.ts`:

```typescript
import { Hono } from "hono";
import { z } from "zod";
import {
  createOrganization,
  getOrganizationByUsername,
  getOrganizationMembers,
  addOrganizationMember,
  removeOrganizationMember,
  isOrganizationOwner,
  isOrganizationMember
} from "../services/organization";
import {
  createTeam,
  getOrganizationTeams,
  getTeamByName,
  addTeamMember,
  removeTeamMember,
  getTeamMembers,
  addTeamRepository,
  removeTeamRepository,
  getTeamRepositories
} from "../services/team";

const app = new Hono();

// Create organization schema
const createOrgSchema = z.object({
  username: z.string().min(1).max(255).regex(/^[a-zA-Z0-9-_]+$/),
  display_name: z.string().max(255).optional(),
  bio: z.string().optional(),
  visibility: z.enum(['public', 'limited', 'private']).optional()
});

// POST /api/organizations - Create organization
app.post("/", async (c) => {
  const body = await c.req.json();
  const data = createOrgSchema.parse(body);

  // TODO: Get current user from session
  const currentUser = { id: 1, username: "testuser" }; // Placeholder

  try {
    const org = await createOrganization(data, currentUser as any);
    return c.json(org, 201);
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// GET /api/organizations/:org - Get organization
app.get("/:org", async (c) => {
  const orgName = c.req.param("org");
  const org = await getOrganizationByUsername(orgName);

  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  return c.json(org);
});

// GET /api/organizations/:org/members - Get members
app.get("/:org/members", async (c) => {
  const orgName = c.req.param("org");
  const org = await getOrganizationByUsername(orgName);

  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  // TODO: Check if requester is member to see private members
  const publicOnly = true;
  const members = await getOrganizationMembers(org.id, publicOnly);

  return c.json(members);
});

// POST /api/organizations/:org/members - Add member
app.post("/:org/members", async (c) => {
  const orgName = c.req.param("org");
  const { user_id, is_public } = await c.req.json();

  const org = await getOrganizationByUsername(orgName);
  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  // TODO: Check if requester is owner
  try {
    await addOrganizationMember(org.id, user_id, is_public);
    return c.json({ success: true }, 201);
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// DELETE /api/organizations/:org/members/:userId - Remove member
app.delete("/:org/members/:userId", async (c) => {
  const orgName = c.req.param("org");
  const userId = parseInt(c.req.param("userId"));

  const org = await getOrganizationByUsername(orgName);
  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  try {
    await removeOrganizationMember(org.id, userId);
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// GET /api/organizations/:org/teams - Get teams
app.get("/:org/teams", async (c) => {
  const orgName = c.req.param("org");
  const org = await getOrganizationByUsername(orgName);

  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  const teams = await getOrganizationTeams(org.id);
  return c.json(teams);
});

// POST /api/organizations/:org/teams - Create team
const createTeamSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().optional(),
  access_mode: z.enum(['read', 'write', 'admin']).optional(),
  includes_all_repositories: z.boolean().optional(),
  can_create_org_repo: z.boolean().optional()
});

app.post("/:org/teams", async (c) => {
  const orgName = c.req.param("org");
  const body = await c.req.json();
  const data = createTeamSchema.parse(body);

  const org = await getOrganizationByUsername(orgName);
  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  try {
    const team = await createTeam({ org_id: org.id, ...data });
    return c.json(team, 201);
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// GET /api/organizations/:org/teams/:team - Get team
app.get("/:org/teams/:team", async (c) => {
  const orgName = c.req.param("org");
  const teamName = c.req.param("team");

  const org = await getOrganizationByUsername(orgName);
  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  const team = await getTeamByName(org.id, teamName);
  if (!team) {
    return c.json({ error: "Team not found" }, 404);
  }

  return c.json(team);
});

// GET /api/organizations/:org/teams/:team/members - Get team members
app.get("/:org/teams/:team/members", async (c) => {
  const orgName = c.req.param("org");
  const teamName = c.req.param("team");

  const org = await getOrganizationByUsername(orgName);
  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  const team = await getTeamByName(org.id, teamName);
  if (!team) {
    return c.json({ error: "Team not found" }, 404);
  }

  const members = await getTeamMembers(team.id);
  return c.json(members);
});

// POST /api/organizations/:org/teams/:team/members - Add member to team
app.post("/:org/teams/:team/members", async (c) => {
  const orgName = c.req.param("org");
  const teamName = c.req.param("team");
  const { user_id } = await c.req.json();

  const org = await getOrganizationByUsername(orgName);
  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  const team = await getTeamByName(org.id, teamName);
  if (!team) {
    return c.json({ error: "Team not found" }, 404);
  }

  try {
    await addTeamMember(team.id, user_id);
    return c.json({ success: true }, 201);
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// DELETE /api/organizations/:org/teams/:team/members/:userId - Remove member from team
app.delete("/:org/teams/:team/members/:userId", async (c) => {
  const orgName = c.req.param("org");
  const teamName = c.req.param("team");
  const userId = parseInt(c.req.param("userId"));

  const org = await getOrganizationByUsername(orgName);
  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  const team = await getTeamByName(org.id, teamName);
  if (!team) {
    return c.json({ error: "Team not found" }, 404);
  }

  try {
    await removeTeamMember(team.id, userId);
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// GET /api/organizations/:org/teams/:team/repos - Get team repositories
app.get("/:org/teams/:team/repos", async (c) => {
  const orgName = c.req.param("org");
  const teamName = c.req.param("team");

  const org = await getOrganizationByUsername(orgName);
  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  const team = await getTeamByName(org.id, teamName);
  if (!team) {
    return c.json({ error: "Team not found" }, 404);
  }

  const repos = await getTeamRepositories(team.id);
  return c.json(repos);
});

// POST /api/organizations/:org/teams/:team/repos - Add repository to team
app.post("/:org/teams/:team/repos", async (c) => {
  const orgName = c.req.param("org");
  const teamName = c.req.param("team");
  const { repo_id } = await c.req.json();

  const org = await getOrganizationByUsername(orgName);
  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  const team = await getTeamByName(org.id, teamName);
  if (!team) {
    return c.json({ error: "Team not found" }, 404);
  }

  try {
    await addTeamRepository(team.id, repo_id);
    return c.json({ success: true }, 201);
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// DELETE /api/organizations/:org/teams/:team/repos/:repoId - Remove repository from team
app.delete("/:org/teams/:team/repos/:repoId", async (c) => {
  const orgName = c.req.param("org");
  const teamName = c.req.param("team");
  const repoId = parseInt(c.req.param("repoId"));

  const org = await getOrganizationByUsername(orgName);
  if (!org) {
    return c.json({ error: "Organization not found" }, 404);
  }

  const team = await getTeamByName(org.id, teamName);
  if (!team) {
    return c.json({ error: "Team not found" }, 404);
  }

  try {
    await removeTeamRepository(team.id, repoId);
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

export default app;
```

Update `/Users/williamcory/plue/server/index.ts` to mount the routes:

```typescript
import organizations from "./routes/organizations";

app.route("/api/organizations", organizations);
```

---

## 4. Frontend Implementation

### 4.1 Organization Profile Page

Create `/Users/williamcory/plue/ui/pages/[user]/index.astro` (update existing):

```astro
---
import Layout from "../../layouts/Layout.astro";
import Header from "../../components/Header.astro";
import RepoCard from "../../components/RepoCard.astro";
import { sql } from "../../lib/db";
import type { User, Repository, Organization } from "../../lib/types";

const { user: username } = Astro.params;

// Fetch user or organization
const [userOrOrg] = await sql`
  SELECT * FROM users WHERE username = ${username}
` as (User | Organization)[];

if (!userOrOrg) {
  return Astro.redirect("/404");
}

const isOrg = userOrOrg.type === 'organization';

// Fetch repositories
const repos = await sql`
  SELECT r.*, u.username
  FROM repositories r
  JOIN users u ON r.user_id = u.id
  WHERE r.user_id = ${userOrOrg.id} AND r.is_public = true
  ORDER BY r.updated_at DESC
` as Repository[];

// If organization, fetch teams count
let teamsCount = 0;
if (isOrg) {
  const org = userOrOrg as Organization;
  teamsCount = org.num_teams;
}
---

<Layout title={`${userOrOrg.username} · plue`}>
  <Header />
  <div class="container">
    <div class="profile-header mb-3">
      <div class="profile-info">
        <h1 class="page-title">{userOrOrg.display_name || userOrOrg.username}</h1>
        {isOrg && <span class="org-badge">Organization</span>}
        {userOrOrg.bio && <p class="bio">{userOrOrg.bio}</p>}

        {isOrg && (
          <div class="org-stats">
            <span>{(userOrOrg as Organization).num_members} members</span>
            <span>{teamsCount} teams</span>
            <span>{repos.length} repositories</span>
          </div>
        )}
      </div>

      {isOrg && (
        <div class="org-nav">
          <a href={`/${username}`} class="active">Repositories</a>
          <a href={`/${username}/teams`}>Teams</a>
          <a href={`/${username}/members`}>Members</a>
        </div>
      )}
    </div>

    <h2 class="mb-2">Repositories</h2>

    {repos.length === 0 ? (
      <div class="empty-state">
        <p>No repositories yet</p>
      </div>
    ) : (
      <ul class="repo-list">
        {repos.map((repo) => (
          <RepoCard repo={repo} showUser={false} />
        ))}
      </ul>
    )}
  </div>
</Layout>

<style>
  .profile-header {
    padding-bottom: 24px;
    border-bottom: 1px solid var(--border);
  }

  .bio {
    margin-top: 8px;
  }

  .org-badge {
    display: inline-block;
    padding: 2px 8px;
    background: var(--border);
    border: 1px solid var(--text);
    font-size: 12px;
    margin-left: 8px;
  }

  .org-stats {
    display: flex;
    gap: 16px;
    margin-top: 12px;
    font-size: 14px;
  }

  .org-nav {
    display: flex;
    gap: 16px;
    margin-top: 16px;
    border-bottom: 1px solid var(--border);
  }

  .org-nav a {
    padding: 8px 0;
    text-decoration: none;
    color: var(--text);
    border-bottom: 2px solid transparent;
  }

  .org-nav a.active {
    border-bottom-color: var(--text);
    font-weight: bold;
  }
</style>
```

### 4.2 Organization Teams Page

Create `/Users/williamcory/plue/ui/pages/[user]/teams.astro`:

```astro
---
import Layout from "../../layouts/Layout.astro";
import Header from "../../components/Header.astro";
import { sql } from "../../lib/db";
import type { Organization, Team } from "../../lib/types";

const { user: username } = Astro.params;

const [org] = await sql`
  SELECT * FROM users WHERE username = ${username} AND type = 'organization'
` as Organization[];

if (!org) {
  return Astro.redirect("/404");
}

const teams = await sql`
  SELECT * FROM teams
  WHERE org_id = ${org.id}
  ORDER BY
    CASE WHEN name = 'Owners' THEN 0 ELSE 1 END,
    name ASC
` as Team[];
---

<Layout title={`Teams · ${org.username} · plue`}>
  <Header />
  <div class="container">
    <div class="org-header mb-3">
      <h1 class="page-title">{org.display_name || org.username}</h1>
      <div class="org-nav">
        <a href={`/${username}`}>Repositories</a>
        <a href={`/${username}/teams`} class="active">Teams</a>
        <a href={`/${username}/members`}>Members</a>
      </div>
    </div>

    <div class="teams-header mb-2">
      <h2>Teams</h2>
      <a href={`/${username}/teams/new`} class="btn-primary">New team</a>
    </div>

    {teams.length === 0 ? (
      <div class="empty-state">
        <p>No teams yet</p>
      </div>
    ) : (
      <ul class="team-list">
        {teams.map((team) => (
          <li class="team-item">
            <div class="team-info">
              <h3>
                <a href={`/${username}/teams/${team.name.toLowerCase()}`}>
                  {team.name}
                </a>
                {team.name === 'Owners' && <span class="owner-badge">Owner</span>}
              </h3>
              {team.description && <p class="team-description">{team.description}</p>}
              <div class="team-meta">
                <span>{team.num_members} members</span>
                <span>{team.num_repos} repositories</span>
                <span class="access-mode">{team.access_mode}</span>
              </div>
            </div>
          </li>
        ))}
      </ul>
    )}
  </div>
</Layout>

<style>
  .org-header {
    padding-bottom: 24px;
    border-bottom: 1px solid var(--border);
  }

  .org-nav {
    display: flex;
    gap: 16px;
    margin-top: 16px;
    border-bottom: 1px solid var(--border);
  }

  .org-nav a {
    padding: 8px 0;
    text-decoration: none;
    color: var(--text);
    border-bottom: 2px solid transparent;
  }

  .org-nav a.active {
    border-bottom-color: var(--text);
    font-weight: bold;
  }

  .teams-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .team-list {
    list-style: none;
    padding: 0;
  }

  .team-item {
    padding: 16px;
    border: 1px solid var(--border);
    margin-bottom: 8px;
  }

  .team-item h3 {
    margin: 0 0 8px 0;
    font-size: 18px;
  }

  .team-item h3 a {
    text-decoration: none;
    color: var(--text);
  }

  .team-item h3 a:hover {
    text-decoration: underline;
  }

  .owner-badge {
    display: inline-block;
    padding: 2px 6px;
    background: var(--border);
    border: 1px solid var(--text);
    font-size: 11px;
    margin-left: 8px;
  }

  .team-description {
    margin: 0 0 8px 0;
    color: var(--text-muted);
  }

  .team-meta {
    display: flex;
    gap: 16px;
    font-size: 13px;
    color: var(--text-muted);
  }

  .access-mode {
    text-transform: uppercase;
    font-weight: bold;
  }

  .btn-primary {
    padding: 8px 16px;
    background: var(--text);
    color: var(--bg);
    border: 1px solid var(--text);
    text-decoration: none;
    display: inline-block;
  }

  .btn-primary:hover {
    background: var(--bg);
    color: var(--text);
  }
</style>
```

### 4.3 Organization Members Page

Create `/Users/williamcory/plue/ui/pages/[user]/members.astro`:

```astro
---
import Layout from "../../layouts/Layout.astro";
import Header from "../../components/Header.astro";
import { sql } from "../../lib/db";
import type { Organization, User } from "../../lib/types";

const { user: username } = Astro.params;

const [org] = await sql`
  SELECT * FROM users WHERE username = ${username} AND type = 'organization'
` as Organization[];

if (!org) {
  return Astro.redirect("/404");
}

// Get members with owner status
const members = await sql`
  SELECT
    u.*,
    ou.is_public,
    EXISTS(
      SELECT 1 FROM team_users tu
      JOIN teams t ON tu.team_id = t.id
      WHERE tu.user_id = u.id
      AND t.org_id = ${org.id}
      AND t.name = 'Owners'
    ) as is_owner
  FROM users u
  JOIN org_users ou ON u.id = ou.user_id
  WHERE ou.org_id = ${org.id}
  ORDER BY is_owner DESC, u.username ASC
` as (User & { is_public: boolean; is_owner: boolean })[];
---

<Layout title={`Members · ${org.username} · plue`}>
  <Header />
  <div class="container">
    <div class="org-header mb-3">
      <h1 class="page-title">{org.display_name || org.username}</h1>
      <div class="org-nav">
        <a href={`/${username}`}>Repositories</a>
        <a href={`/${username}/teams`}>Teams</a>
        <a href={`/${username}/members`} class="active">Members</a>
      </div>
    </div>

    <div class="members-header mb-2">
      <h2>{members.length} members</h2>
      <a href={`/${username}/invitations/new`} class="btn-primary">Invite member</a>
    </div>

    <ul class="member-list">
      {members.map((member) => (
        <li class="member-item">
          <div class="member-info">
            <h3>
              <a href={`/${member.username}`}>{member.display_name || member.username}</a>
              {member.is_owner && <span class="owner-badge">Owner</span>}
              {!member.is_public && <span class="private-badge">Private</span>}
            </h3>
            {member.bio && <p class="member-bio">{member.bio}</p>}
          </div>
        </li>
      ))}
    </ul>
  </div>
</Layout>

<style>
  .org-header {
    padding-bottom: 24px;
    border-bottom: 1px solid var(--border);
  }

  .org-nav {
    display: flex;
    gap: 16px;
    margin-top: 16px;
    border-bottom: 1px solid var(--border);
  }

  .org-nav a {
    padding: 8px 0;
    text-decoration: none;
    color: var(--text);
    border-bottom: 2px solid transparent;
  }

  .org-nav a.active {
    border-bottom-color: var(--text);
    font-weight: bold;
  }

  .members-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .member-list {
    list-style: none;
    padding: 0;
  }

  .member-item {
    padding: 16px;
    border: 1px solid var(--border);
    margin-bottom: 8px;
  }

  .member-item h3 {
    margin: 0 0 4px 0;
    font-size: 16px;
  }

  .member-item h3 a {
    text-decoration: none;
    color: var(--text);
  }

  .member-item h3 a:hover {
    text-decoration: underline;
  }

  .owner-badge,
  .private-badge {
    display: inline-block;
    padding: 2px 6px;
    background: var(--border);
    border: 1px solid var(--text);
    font-size: 11px;
    margin-left: 8px;
  }

  .member-bio {
    margin: 0;
    font-size: 14px;
    color: var(--text-muted);
  }

  .btn-primary {
    padding: 8px 16px;
    background: var(--text);
    color: var(--bg);
    border: 1px solid var(--text);
    text-decoration: none;
    display: inline-block;
  }

  .btn-primary:hover {
    background: var(--bg);
    color: var(--text);
  }
</style>
```

### 4.4 Team Detail Page

Create `/Users/williamcory/plue/ui/pages/[user]/teams/[team].astro`:

```astro
---
import Layout from "../../../layouts/Layout.astro";
import Header from "../../../components/Header.astro";
import { sql } from "../../../lib/db";
import type { Organization, Team, User, Repository } from "../../../lib/types";

const { user: username, team: teamName } = Astro.params;

const [org] = await sql`
  SELECT * FROM users WHERE username = ${username} AND type = 'organization'
` as Organization[];

if (!org) {
  return Astro.redirect("/404");
}

const [team] = await sql`
  SELECT * FROM teams
  WHERE org_id = ${org.id}
  AND lower_name = ${teamName.toLowerCase()}
` as Team[];

if (!team) {
  return Astro.redirect("/404");
}

const members = await sql`
  SELECT u.*
  FROM users u
  JOIN team_users tu ON u.id = tu.user_id
  WHERE tu.team_id = ${team.id}
  ORDER BY u.username
` as User[];

const repos = await sql`
  SELECT r.*
  FROM repositories r
  JOIN team_repos tr ON r.id = tr.repo_id
  WHERE tr.team_id = ${team.id}
  ORDER BY r.name
` as Repository[];
---

<Layout title={`${team.name} · ${org.username} · plue`}>
  <Header />
  <div class="container">
    <div class="team-header mb-3">
      <div class="breadcrumb">
        <a href={`/${username}`}>{org.username}</a>
        <span>/</span>
        <a href={`/${username}/teams`}>teams</a>
        <span>/</span>
        <span>{team.name}</span>
      </div>

      <h1 class="page-title">{team.name}</h1>
      {team.description && <p class="team-description">{team.description}</p>}

      <div class="team-stats">
        <span class="access-mode">Access: {team.access_mode}</span>
        {team.includes_all_repositories && <span>All repositories</span>}
        {team.can_create_org_repo && <span>Can create repos</span>}
      </div>
    </div>

    <div class="team-content">
      <section class="mb-4">
        <h2 class="mb-2">Members ({members.length})</h2>
        {members.length === 0 ? (
          <div class="empty-state">
            <p>No members yet</p>
          </div>
        ) : (
          <ul class="member-list">
            {members.map((member) => (
              <li>
                <a href={`/${member.username}`}>
                  {member.display_name || member.username}
                </a>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section>
        <h2 class="mb-2">Repositories ({repos.length})</h2>
        {team.includes_all_repositories ? (
          <p class="info-message">This team has access to all repositories</p>
        ) : repos.length === 0 ? (
          <div class="empty-state">
            <p>No repositories assigned</p>
          </div>
        ) : (
          <ul class="repo-list">
            {repos.map((repo) => (
              <li>
                <a href={`/${username}/${repo.name}`}>{repo.name}</a>
                {repo.description && <span class="repo-desc">{repo.description}</span>}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  </div>
</Layout>

<style>
  .breadcrumb {
    font-size: 14px;
    margin-bottom: 8px;
  }

  .breadcrumb a {
    text-decoration: none;
    color: var(--text);
  }

  .breadcrumb a:hover {
    text-decoration: underline;
  }

  .team-header {
    padding-bottom: 24px;
    border-bottom: 1px solid var(--border);
  }

  .team-description {
    margin-top: 8px;
    color: var(--text-muted);
  }

  .team-stats {
    display: flex;
    gap: 16px;
    margin-top: 12px;
    font-size: 14px;
  }

  .access-mode {
    text-transform: uppercase;
    font-weight: bold;
  }

  .member-list,
  .repo-list {
    list-style: none;
    padding: 0;
  }

  .member-list li,
  .repo-list li {
    padding: 8px;
    border: 1px solid var(--border);
    margin-bottom: 4px;
  }

  .member-list a,
  .repo-list a {
    text-decoration: none;
    color: var(--text);
    font-weight: bold;
  }

  .member-list a:hover,
  .repo-list a:hover {
    text-decoration: underline;
  }

  .repo-desc {
    display: block;
    font-size: 13px;
    color: var(--text-muted);
    margin-top: 4px;
  }

  .info-message {
    padding: 12px;
    background: var(--border);
    border: 1px solid var(--text);
  }
</style>
```

---

## 5. Key Gitea Reference Code

### 5.1 Organization Creation Flow

From `gitea/models/organization/org.go::CreateOrganization` (lines 284-376):

```go
func CreateOrganization(ctx context.Context, org *Organization, owner *user_model.User) (err error) {
	if !owner.CanCreateOrganization() {
		return ErrUserNotAllowedCreateOrg{}
	}

	org.LowerName = strings.ToLower(org.Name)
	org.Type = user_model.UserTypeOrganization
	org.NumTeams = 1
	org.NumMembers = 1

	return db.WithTx(ctx, func(ctx context.Context) error {
		// Insert organization as user
		if err = db.Insert(ctx, org); err != nil {
			return err
		}

		// Add owner to org_user
		if err = db.Insert(ctx, &OrgUser{
			UID:      owner.ID,
			OrgID:    org.ID,
			IsPublic: setting.Service.DefaultOrgMemberVisible,
		}); err != nil {
			return err
		}

		// Create "Owners" team
		t := &Team{
			OrgID:                   org.ID,
			Name:                    OwnerTeamName,
			AccessMode:              perm.AccessModeOwner,
			IncludesAllRepositories: true,
			CanCreateOrgRepo:        true,
		}
		if err = db.Insert(ctx, t); err != nil {
			return err
		}

		// Add owner to team
		if err = db.Insert(ctx, &TeamUser{
			UID:    owner.ID,
			OrgID:  org.ID,
			TeamID: t.ID,
		}); err != nil {
			return err
		}
		return nil
	})
}
```

**Key insight**: Organizations are users with `type = 'organization'`. Every org automatically gets an "Owners" team with full access.

### 5.2 Access Mode Hierarchy

From `gitea/models/perm/access_mode.go`:

```go
const (
	AccessModeNone  AccessMode = iota // 0
	AccessModeRead                    // 1
	AccessModeWrite                   // 2
	AccessModeAdmin                   // 3
	AccessModeOwner                   // 4
)
```

Higher values grant more permissions. Teams with `includes_all_repositories = true` automatically get access to all org repos.

### 5.3 Team Permission Check

From `gitea/models/organization/team_repo.go::GetTeamsWithAccessToAnyRepoUnit`:

The logic checks:
1. Direct team-repo assignment via `team_repos`
2. OR team has `includes_all_repositories = true`
3. Returns highest access mode from all matching teams

---

## 6. Implementation Checklist

### Phase 1: Database & Types
- [ ] Add organization fields to `users` table
- [ ] Create `org_users` table
- [ ] Create `teams` table
- [ ] Create `team_users` table
- [ ] Create `team_repos` table
- [ ] Run migration script
- [ ] Add TypeScript types to `ui/lib/types.ts`

### Phase 2: Backend Services
- [ ] Implement `organization.ts` service
  - [ ] `createOrganization()`
  - [ ] `getOrganizationByUsername()`
  - [ ] `isOrganizationMember()`
  - [ ] `isOrganizationOwner()`
  - [ ] `getOrganizationMembers()`
  - [ ] `addOrganizationMember()`
  - [ ] `removeOrganizationMember()`
- [ ] Implement `team.ts` service
  - [ ] `createTeam()`
  - [ ] `getTeamByName()`
  - [ ] `getOrganizationTeams()`
  - [ ] `addTeamMember()`
  - [ ] `removeTeamMember()`
  - [ ] `getTeamMembers()`
  - [ ] `addTeamRepository()`
  - [ ] `removeTeamRepository()`
  - [ ] `getTeamRepositories()`
  - [ ] `getUserRepoAccessMode()`

### Phase 3: API Routes
- [ ] Create `server/routes/organizations.ts`
- [ ] Implement organization CRUD endpoints
- [ ] Implement team CRUD endpoints
- [ ] Implement member management endpoints
- [ ] Implement repository assignment endpoints
- [ ] Mount routes in `server/index.ts`

### Phase 4: Frontend Pages
- [ ] Update `[user]/index.astro` to support organizations
- [ ] Create `[user]/teams.astro` (teams list)
- [ ] Create `[user]/members.astro` (members list)
- [ ] Create `[user]/teams/[team].astro` (team detail)
- [ ] Create `[user]/teams/new.astro` (create team form)
- [ ] Create `[user]/settings.astro` (org settings)

### Phase 5: Repository Integration
- [ ] Update repository creation to support organization owner
- [ ] Add organization selector to new repo form
- [ ] Update repository access checks to consider teams
- [ ] Show team access on repository settings page

### Phase 6: Testing
- [ ] Test organization creation flow
- [ ] Test team creation and member assignment
- [ ] Test repository access via teams
- [ ] Test owner team restrictions (can't remove last owner)
- [ ] Test visibility settings (public/private members)
- [ ] Test `includes_all_repositories` flag

### Phase 7: UI/UX Polish
- [ ] Add organization/team icons
- [ ] Add member invitation system
- [ ] Add breadcrumb navigation
- [ ] Add access mode badges
- [ ] Add empty states
- [ ] Add loading states

---

## 7. Testing Scenarios

### Organization Creation
```bash
# Create organization
curl -X POST http://localhost:3000/api/organizations \
  -H "Content-Type: application/json" \
  -d '{
    "username": "acme-corp",
    "display_name": "ACME Corporation",
    "bio": "We make everything",
    "visibility": "public"
  }'

# Should create:
# - Organization in users table
# - org_users entry for creator
# - "Owners" team
# - team_users entry for creator in Owners team
```

### Team Management
```bash
# Create team
curl -X POST http://localhost:3000/api/organizations/acme-corp/teams \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Engineering",
    "description": "Core engineering team",
    "access_mode": "write",
    "can_create_org_repo": true
  }'

# Add member to team
curl -X POST http://localhost:3000/api/organizations/acme-corp/teams/engineering/members \
  -H "Content-Type: application/json" \
  -d '{"user_id": 2}'

# Add repository to team
curl -X POST http://localhost:3000/api/organizations/acme-corp/teams/engineering/repos \
  -H "Content-Type: application/json" \
  -d '{"repo_id": 5}'
```

### Access Control
```sql
-- Check if user has access to org repo
SELECT
  COALESCE(MAX(
    CASE t.access_mode
      WHEN 'owner' THEN 5
      WHEN 'admin' THEN 4
      WHEN 'write' THEN 3
      WHEN 'read' THEN 2
      ELSE 1
    END
  ), 0) as access_level
FROM teams t
JOIN team_users tu ON t.id = tu.team_id
LEFT JOIN team_repos tr ON t.id = tr.team_id
WHERE tu.user_id = ?
AND (tr.repo_id = ? OR t.includes_all_repositories = true);
```

---

## 8. Future Enhancements

**Not in scope for initial implementation:**

1. **Team Synchronization**: Sync teams with LDAP/OAuth groups
2. **Repository Templates**: Org-wide repo templates
3. **Organization Webhooks**: Webhooks for all org events
4. **Audit Logs**: Track all org/team changes
5. **Team Discussions**: Team-specific discussion boards
6. **Organization Projects**: Org-level project boards
7. **Team Permissions per Unit**: Fine-grained permissions (issues, PRs, wiki, etc.)
8. **Organization Secrets**: Shared CI/CD secrets
9. **Organization Runners**: Shared CI/CD runners
10. **Team Mentions**: @team mentions in issues/PRs

---

## 9. Notes & Gotchas

1. **Organizations are Users**: The `users` table stores both regular users and organizations, distinguished by the `type` field. This simplifies URL routing (`/username` works for both).

2. **Owners Team is Special**: Every organization has an "Owners" team created automatically. This team:
   - Cannot be deleted
   - Always has `access_mode = 'owner'`
   - Always has `includes_all_repositories = true`
   - Must have at least one member

3. **Team Access Mode Hierarchy**: Access modes are hierarchical:
   ```
   owner > admin > write > read > none
   ```
   A user's effective permission is the highest from all their teams.

4. **Includes All Repositories**: Teams with this flag automatically access all current and future org repos, bypassing the `team_repos` table.

5. **Visibility Levels**:
   - `public`: Visible to everyone
   - `limited`: Visible to logged-in users
   - `private`: Visible only to members

6. **Member Visibility**: Individual org memberships can be public or private via `org_users.is_public`.

7. **Repository Ownership**: When an organization owns a repository, the `repositories.user_id` field points to the organization's ID (which is in the `users` table).

8. **PostgreSQL Arrays**: The `conflicted_files` field in pull requests uses PostgreSQL's array type (`TEXT[]`).

---

## 10. Success Criteria

The feature is complete when:

- [ ] Users can create organizations
- [ ] Organizations have profile pages showing repos/teams/members
- [ ] Owners can create teams with read/write/admin permissions
- [ ] Owners can assign repositories to teams
- [ ] Team members can access assigned repositories based on permissions
- [ ] Owners can add/remove organization members
- [ ] Members can be added to multiple teams
- [ ] Last owner cannot be removed
- [ ] "Includes all repositories" flag works correctly
- [ ] Member visibility (public/private) works
- [ ] Organization visibility works
- [ ] All database constraints are enforced
- [ ] API endpoints work correctly
- [ ] Frontend pages render properly
- [ ] Access control checks work throughout the app

---

## References

- **Gitea Organization Model**: `/Users/williamcory/plue/gitea/models/organization/org.go`
- **Gitea Team Model**: `/Users/williamcory/plue/gitea/models/organization/team.go`
- **Gitea Team-Repo Relations**: `/Users/williamcory/plue/gitea/models/organization/team_repo.go`
- **Plue Database Schema**: `/Users/williamcory/plue/db/schema.sql`
- **Plue User Pages**: `/Users/williamcory/plue/ui/pages/[user]/index.astro`
