/**
 * Migration: Add message status tracking columns
 *
 * Adds status, thinking_text, and error_message columns to the messages table.
 */

import sql from "./client";

async function migrate() {
  console.log("Running message status migration...");

  try {
    // Add status column with default value and constraint
    await sql`
      ALTER TABLE messages
      ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'pending'
      CHECK (status IN ('pending', 'streaming', 'completed', 'failed', 'aborted'))
    `;
    console.log("✓ Added status column");

    // Add thinking_text column
    await sql`
      ALTER TABLE messages
      ADD COLUMN IF NOT EXISTS thinking_text TEXT
    `;
    console.log("✓ Added thinking_text column");

    // Add error_message column
    await sql`
      ALTER TABLE messages
      ADD COLUMN IF NOT EXISTS error_message TEXT
    `;
    console.log("✓ Added error_message column");

    console.log("\nMigration complete!");
  } catch (error) {
    console.error("Migration failed:", error);
    throw error;
  } finally {
    await sql.end();
    process.exit(0);
  }
}

migrate();
