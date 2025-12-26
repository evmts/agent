/**
 * PostgreSQL Client for E2E Tests and Scripts
 *
 * Provides a typed SQL client using the postgres library.
 * Used by e2e tests, seed scripts, and global setup.
 */

import postgres from "postgres";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://postgres:postgres@localhost:54321/plue";

export const sql = postgres(DATABASE_URL, {
  max: 5,
  idle_timeout: 30,
  connect_timeout: 10,
});

export default sql;
