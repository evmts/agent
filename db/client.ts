/**
 * Database client for E2E tests and migrations.
 * Re-exports the postgres client from ui/lib/db.ts
 */

import postgres from "postgres";

const DATABASE_URL = process.env.DATABASE_URL ||
  "postgresql://postgres:password@localhost:54321/electric";

export const sql = postgres(DATABASE_URL, {
  max: 10,
  idle_timeout: 20,
  connect_timeout: 10,
  onnotice: () => {},
  transform: {
    undefined: null,
  },
  connection: {
    statement_timeout: 30000,
  },
});

export default sql;
