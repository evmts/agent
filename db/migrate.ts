import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import sql from "./client";

interface Migration {
  id: number;
  name: string;
  applied_at: Date;
}

/**
 * Ensures the migrations tracking table exists.
 */
async function ensureMigrationsTable(): Promise<void> {
  await sql`
    CREATE TABLE IF NOT EXISTS _migrations (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL UNIQUE,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `;
}

/**
 * Gets list of already applied migrations.
 */
async function getAppliedMigrations(): Promise<Set<string>> {
  const rows = await sql<Migration[]>`
    SELECT name FROM _migrations ORDER BY id
  `;
  return new Set(rows.map(r => r.name));
}

/**
 * Records a migration as applied.
 */
async function recordMigration(name: string): Promise<void> {
  await sql`
    INSERT INTO _migrations (name) VALUES (${name})
  `;
}

/**
 * Gets all migration files in order.
 * Migration files should be named with a prefix for ordering:
 * - 000_schema.sql (base schema)
 * - 001_migrate-siwe-auth.sql
 * - 002_migrate-ssh-keys.sql
 * etc.
 */
function getMigrationFiles(): string[] {
  const dbDir = join(process.cwd(), 'db');
  const files = readdirSync(dbDir)
    .filter(f => f.endsWith('.sql'))
    .sort();

  // schema.sql should always come first
  const schemaIndex = files.indexOf('schema.sql');
  if (schemaIndex > -1) {
    files.splice(schemaIndex, 1);
    files.unshift('schema.sql');
  }

  return files;
}

/**
 * Runs a single migration file.
 */
async function runMigration(filename: string): Promise<void> {
  const filepath = join(process.cwd(), 'db', filename);
  const content = readFileSync(filepath, 'utf-8');

  // Split by semicolons and run each statement in a transaction
  const statements = content
    .split(";")
    .map(s => s.trim())
    .filter(s => s.length > 0 && !s.startsWith('--'));

  await sql.begin(async (tx) => {
    for (const statement of statements) {
      try {
        await tx.unsafe(statement);
      } catch (error) {
        const err = error as Error;
        // Ignore "already exists" errors for idempotency
        if (!err.message.includes('already exists') &&
            !err.message.includes('duplicate key')) {
          throw error;
        }
      }
    }
  });
}

async function migrate() {
  console.log("🔄 Running migrations...\n");

  try {
    // Ensure migrations table exists
    await ensureMigrationsTable();

    // Get applied migrations
    const applied = await getAppliedMigrations();
    console.log(`📋 Found ${applied.size} previously applied migrations\n`);

    // Get all migration files
    const files = getMigrationFiles();
    let newMigrations = 0;

    for (const file of files) {
      if (applied.has(file)) {
        console.log(`⏭️  Skipping ${file} (already applied)`);
        continue;
      }

      console.log(`📦 Applying ${file}...`);
      try {
        await runMigration(file);
        await recordMigration(file);
        console.log(`✅ Applied ${file}`);
        newMigrations++;
      } catch (error) {
        console.error(`❌ Failed to apply ${file}:`);
        console.error(`   ${(error as Error).message}`);
        throw error; // Stop on first failure
      }
    }

    console.log(`\n✨ Migrations complete! (${newMigrations} new, ${applied.size} existing)`);
  } catch (error) {
    console.error("\n💥 Migration failed:", (error as Error).message);
    process.exit(1);
  } finally {
    await sql.end();
  }
}

// Export for programmatic use
export { migrate, ensureMigrationsTable, getAppliedMigrations };

// Run if called directly
if (import.meta.main) {
  migrate();
}
