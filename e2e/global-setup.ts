/**
 * Playwright Global Setup
 *
 * Runs before all tests to apply migrations and seed the database with test data.
 */

import { seed } from "./seed";
import { sql } from "../db/client";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

/**
 * Apply database migrations needed for tests.
 * The JJ migration creates tables like landing_queue, bookmarks, changes, etc.
 */
async function applyMigrations() {
  console.log("Applying database migrations...");

  // Apply JJ native migration
  const migrationPath = join(process.cwd(), "db/migrate-jj-native.sql");
  const migrationSql = await readFile(migrationPath, "utf-8");
  await sql.unsafe(migrationSql);

  // Apply missing tables from schema.sql that may not exist
  // These are newer tables added to schema.sql after initial DB setup
  await sql.unsafe(`
    -- Stars table tracks which users have starred which repositories
    CREATE TABLE IF NOT EXISTS stars (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
      created_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(user_id, repository_id)
    );

    CREATE INDEX IF NOT EXISTS idx_stars_user ON stars(user_id);
    CREATE INDEX IF NOT EXISTS idx_stars_repo ON stars(repository_id);
    CREATE INDEX IF NOT EXISTS idx_stars_created ON stars(created_at DESC);

    -- Watches table tracks which users are watching which repositories
    CREATE TABLE IF NOT EXISTS watches (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
      level VARCHAR(20) NOT NULL DEFAULT 'all' CHECK (level IN ('all', 'releases', 'ignore')),
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(user_id, repository_id)
    );

    CREATE INDEX IF NOT EXISTS idx_watches_user ON watches(user_id);
    CREATE INDEX IF NOT EXISTS idx_watches_repo ON watches(repository_id);
    CREATE INDEX IF NOT EXISTS idx_watches_level ON watches(level);

    -- Reactions for issues and comments
    CREATE TABLE IF NOT EXISTS reactions (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      target_type VARCHAR(20) NOT NULL CHECK (target_type IN ('issue', 'comment')),
      target_id INTEGER NOT NULL,
      emoji VARCHAR(10) NOT NULL,
      created_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(user_id, target_type, target_id, emoji)
    );

    CREATE INDEX IF NOT EXISTS idx_reactions_issue ON reactions(target_type, target_id) WHERE target_type = 'issue';
    CREATE INDEX IF NOT EXISTS idx_reactions_comment ON reactions(target_type, target_id) WHERE target_type = 'comment';
  `);

  console.log("Migrations applied successfully");
}

async function globalSetup() {
  console.log("\n=== Playwright Global Setup ===\n");

  try {
    // Apply migrations first to ensure all tables exist
    await applyMigrations();

    // Then seed the database with test data
    await seed();
    console.log("\n=== Global Setup Complete ===\n");
  } catch (error) {
    console.error("Global setup failed:", error);
    throw error;
  }
}

export default globalSetup;
