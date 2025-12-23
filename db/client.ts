/**
 * Database Client
 *
 * PostgreSQL connection pool singleton using the postgres library.
 */

import postgres from "postgres";

// =============================================================================
// Configuration
// =============================================================================

const DATABASE_URL = process.env.DATABASE_URL ||
  "postgresql://postgres:password@localhost:5432/plue";

// Default query timeout in seconds (30 seconds)
const QUERY_TIMEOUT = parseInt(process.env.DB_QUERY_TIMEOUT || '30', 10);

// =============================================================================
// Client
// =============================================================================

export const sql = postgres(DATABASE_URL, {
  // Connection pool settings
  max: 10,
  idle_timeout: 20,
  connect_timeout: 10,

  // Suppress notices
  onnotice: () => {},

  // Transform undefined to null
  transform: {
    undefined: null,
  },

  // Connection options that set statement_timeout
  connection: {
    statement_timeout: QUERY_TIMEOUT * 1000, // Convert to milliseconds
  },
});

export default sql;
