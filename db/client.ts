/**
 * Database client singleton.
 */

import postgres from "postgres";

const DATABASE_URL = process.env.DATABASE_URL ||
  "postgresql://postgres:password@localhost:54321/electric";

export const sql = postgres(DATABASE_URL, {
  // Connection pool settings
  max: 10,
  idle_timeout: 20,
  connect_timeout: 10,
});

export default sql;
