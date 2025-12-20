/**
 * Database client singleton.
 */

import postgres from "postgres";

const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  throw new Error(
    "DATABASE_URL environment variable is required. " +
    "Please set it to your PostgreSQL connection string."
  );
}

// Default query timeout in seconds (30 seconds)
const QUERY_TIMEOUT = parseInt(process.env.DB_QUERY_TIMEOUT || '30', 10);

export const sql = postgres(DATABASE_URL, {
  // Connection pool settings
  max: 10,
  idle_timeout: 20,
  connect_timeout: 10,

  // Query timeout to prevent hanging queries
  // This sets statement_timeout on each connection
  onnotice: () => {}, // Suppress notices
  transform: {
    undefined: null, // Transform undefined to null
  },

  // Connection options that set statement_timeout
  connection: {
    statement_timeout: QUERY_TIMEOUT * 1000, // Convert to milliseconds
  },
});

export default sql;
