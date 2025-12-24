#!/usr/bin/env bun
/**
 * Database MCP Server
 *
 * Enables AI agents to query the PostgreSQL database for debugging.
 * Provides safe, read-only access with common query templates.
 *
 * SECURITY: Only read operations are allowed. No mutations.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ToolSchema,
} from "@modelcontextprotocol/sdk/types.js";
import postgres from "postgres";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://postgres:postgres@localhost:54321/plue";

const sql = postgres(DATABASE_URL, {
  max: 3,
  idle_timeout: 20,
  connect_timeout: 10,
  // Force read-only mode where possible
  types: {
    // Disable type parsing for safety
  },
});

// Tool definitions
const tools: ToolSchema[] = [
  {
    name: "query",
    description:
      "Execute a read-only SQL query. Only SELECT queries are allowed. Use for debugging and data exploration.",
    inputSchema: {
      type: "object",
      properties: {
        sql: {
          type: "string",
          description: "SQL SELECT query to execute",
        },
        limit: {
          type: "number",
          description: "Max rows to return (default: 100, max: 1000)",
        },
      },
      required: ["sql"],
    },
  },
  {
    name: "describe_table",
    description:
      "Get the schema of a table including columns, types, and constraints.",
    inputSchema: {
      type: "object",
      properties: {
        table: {
          type: "string",
          description: "Table name to describe",
        },
      },
      required: ["table"],
    },
  },
  {
    name: "list_tables",
    description:
      "List all tables in the database with row counts and descriptions.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "find_user",
    description:
      "Find a user by username, email, or ID. Shows related data.",
    inputSchema: {
      type: "object",
      properties: {
        username: {
          type: "string",
          description: "Username to search for",
        },
        email: {
          type: "string",
          description: "Email to search for",
        },
        id: {
          type: "number",
          description: "User ID",
        },
      },
    },
  },
  {
    name: "find_repository",
    description:
      "Find a repository by owner/name or ID. Shows related workflows and recent activity.",
    inputSchema: {
      type: "object",
      properties: {
        owner: {
          type: "string",
          description: "Repository owner",
        },
        name: {
          type: "string",
          description: "Repository name",
        },
        id: {
          type: "number",
          description: "Repository ID",
        },
      },
    },
  },
  {
    name: "recent_activity",
    description:
      "Get recent database activity: new users, repos, workflow runs, etc.",
    inputSchema: {
      type: "object",
      properties: {
        hours: {
          type: "number",
          description: "Hours to look back (default: 24)",
        },
      },
    },
  },
  {
    name: "db_stats",
    description:
      "Get database statistics: table sizes, index usage, connection info.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "find_sessions",
    description:
      "Find active user sessions. Useful for debugging auth issues.",
    inputSchema: {
      type: "object",
      properties: {
        user_id: {
          type: "number",
          description: "Filter by user ID",
        },
        active_only: {
          type: "boolean",
          description: "Only show active sessions (default: true)",
        },
      },
    },
  },
  {
    name: "check_connections",
    description:
      "Check database connection pool status and active queries.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "explain_query",
    description:
      "Run EXPLAIN ANALYZE on a query to debug performance issues.",
    inputSchema: {
      type: "object",
      properties: {
        sql: {
          type: "string",
          description: "SQL SELECT query to analyze",
        },
      },
      required: ["sql"],
    },
  },
];

// Validate query is read-only
function isReadOnly(query: string): boolean {
  const normalized = query.trim().toLowerCase();

  // Block dangerous keywords
  const forbidden = [
    "insert", "update", "delete", "drop", "create", "alter",
    "truncate", "grant", "revoke", "execute", "call", "copy",
    "do", "lock", "vacuum", "analyze", "cluster", "reindex"
  ];

  for (const word of forbidden) {
    // Check for word boundaries
    const regex = new RegExp(`\\b${word}\\b`, "i");
    if (regex.test(normalized)) {
      return false;
    }
  }

  // Must start with SELECT, WITH, EXPLAIN, or SHOW
  if (!normalized.match(/^(select|with|explain|show)\b/)) {
    return false;
  }

  return true;
}

// Format query results as table
function formatResults(rows: any[], limit: number): string {
  if (rows.length === 0) {
    return "No results.";
  }

  const columns = Object.keys(rows[0]);

  // Calculate column widths
  const widths: Record<string, number> = {};
  for (const col of columns) {
    widths[col] = col.length;
    for (const row of rows) {
      const val = String(row[col] ?? "NULL");
      widths[col] = Math.min(50, Math.max(widths[col], val.length));
    }
  }

  // Build header
  const header = columns.map(c => c.padEnd(widths[c])).join(" | ");
  const separator = columns.map(c => "-".repeat(widths[c])).join("-+-");

  // Build rows
  const rowLines = rows.slice(0, limit).map(row => {
    return columns.map(c => {
      const val = String(row[c] ?? "NULL");
      return val.slice(0, 50).padEnd(widths[c]);
    }).join(" | ");
  });

  let result = `${header}\n${separator}\n${rowLines.join("\n")}`;

  if (rows.length > limit) {
    result += `\n\n... ${rows.length - limit} more rows`;
  }

  return result;
}

// Tool handlers
async function handleTool(name: string, args: Record<string, unknown>): Promise<string> {
  switch (name) {
    case "query": {
      const query = args.sql as string;
      const limit = Math.min((args.limit as number) || 100, 1000);

      if (!isReadOnly(query)) {
        return "Error: Only read-only queries (SELECT) are allowed.";
      }

      try {
        // Add LIMIT if not present
        let safeQuery = query;
        if (!query.toLowerCase().includes("limit")) {
          safeQuery = `${query} LIMIT ${limit}`;
        }

        const rows = await sql.unsafe(safeQuery);
        return formatResults(rows, limit);
      } catch (error) {
        return `Query error: ${error}`;
      }
    }

    case "describe_table": {
      const table = args.table as string;

      try {
        const columns = await sql`
          SELECT
            column_name,
            data_type,
            is_nullable,
            column_default,
            character_maximum_length
          FROM information_schema.columns
          WHERE table_name = ${table}
          ORDER BY ordinal_position
        `;

        if (columns.length === 0) {
          return `Table '${table}' not found.`;
        }

        // Get indexes
        const indexes = await sql`
          SELECT
            indexname,
            indexdef
          FROM pg_indexes
          WHERE tablename = ${table}
        `;

        // Get foreign keys
        const fks = await sql`
          SELECT
            tc.constraint_name,
            kcu.column_name,
            ccu.table_name AS foreign_table,
            ccu.column_name AS foreign_column
          FROM information_schema.table_constraints AS tc
          JOIN information_schema.key_column_usage AS kcu
            ON tc.constraint_name = kcu.constraint_name
          JOIN information_schema.constraint_column_usage AS ccu
            ON ccu.constraint_name = tc.constraint_name
          WHERE tc.table_name = ${table}
            AND tc.constraint_type = 'FOREIGN KEY'
        `;

        let result = `Table: ${table}\n${"=".repeat(50)}\n\nColumns:\n`;

        for (const col of columns) {
          const nullable = col.is_nullable === "YES" ? "NULL" : "NOT NULL";
          const len = col.character_maximum_length ? `(${col.character_maximum_length})` : "";
          const def = col.column_default ? ` DEFAULT ${col.column_default}` : "";
          result += `  ${col.column_name}: ${col.data_type}${len} ${nullable}${def}\n`;
        }

        if (indexes.length > 0) {
          result += "\nIndexes:\n";
          for (const idx of indexes) {
            result += `  ${idx.indexname}\n`;
          }
        }

        if (fks.length > 0) {
          result += "\nForeign Keys:\n";
          for (const fk of fks) {
            result += `  ${fk.column_name} -> ${fk.foreign_table}(${fk.foreign_column})\n`;
          }
        }

        return result;
      } catch (error) {
        return `Error: ${error}`;
      }
    }

    case "list_tables": {
      try {
        const tables = await sql`
          SELECT
            t.table_name,
            pg_size_pretty(pg_total_relation_size(quote_ident(t.table_name))) as size,
            (SELECT count(*) FROM information_schema.columns WHERE table_name = t.table_name) as columns,
            obj_description(quote_ident(t.table_name)::regclass, 'pg_class') as description
          FROM information_schema.tables t
          WHERE t.table_schema = 'public'
            AND t.table_type = 'BASE TABLE'
          ORDER BY t.table_name
        `;

        let result = `Database Tables\n${"=".repeat(50)}\n\n`;

        for (const t of tables) {
          result += `${t.table_name}\n`;
          result += `  Size: ${t.size} | Columns: ${t.columns}\n`;
          if (t.description) {
            result += `  ${t.description}\n`;
          }
        }

        return result;
      } catch (error) {
        return `Error: ${error}`;
      }
    }

    case "find_user": {
      const username = args.username as string;
      const email = args.email as string;
      const id = args.id as number;

      try {
        let query;
        if (id) {
          query = sql`SELECT * FROM users WHERE id = ${id}`;
        } else if (username) {
          query = sql`SELECT * FROM users WHERE username ILIKE ${username}`;
        } else if (email) {
          query = sql`SELECT * FROM users WHERE email ILIKE ${email}`;
        } else {
          return "Provide username, email, or id";
        }

        const [user] = await query;

        if (!user) {
          return "User not found.";
        }

        // Get user's repos
        const repos = await sql`
          SELECT id, name, is_private
          FROM repositories
          WHERE owner_id = ${user.id}
          LIMIT 10
        `;

        // Get recent auth sessions
        const sessions = await sql`
          SELECT session_key as id, created_at, expires_at
          FROM auth_sessions
          WHERE user_id = ${user.id}
          ORDER BY created_at DESC
          LIMIT 5
        `;

        let result = `User: ${user.username}\n${"=".repeat(50)}\n`;
        result += `ID:       ${user.id}\n`;
        result += `Email:    ${user.email}\n`;
        result += `Created:  ${user.created_at}\n`;
        result += `Verified: ${user.email_verified || false}\n`;

        if (repos.length > 0) {
          result += `\nRepositories (${repos.length}):\n`;
          for (const r of repos) {
            result += `  - ${r.name} ${r.is_private ? "(private)" : ""}\n`;
          }
        }

        if (sessions.length > 0) {
          result += `\nRecent Sessions:\n`;
          for (const s of sessions) {
            result += `  - ${s.id.slice(0, 8)}... (created: ${s.created_at})\n`;
          }
        }

        return result;
      } catch (error) {
        return `Error: ${error}`;
      }
    }

    case "find_repository": {
      const owner = args.owner as string;
      const name = args.name as string;
      const id = args.id as number;

      try {
        let query;
        if (id) {
          query = sql`
            SELECT r.*, u.username as owner_name
            FROM repositories r
            JOIN users u ON r.owner_id = u.id
            WHERE r.id = ${id}
          `;
        } else if (owner && name) {
          query = sql`
            SELECT r.*, u.username as owner_name
            FROM repositories r
            JOIN users u ON r.owner_id = u.id
            WHERE u.username ILIKE ${owner} AND r.name ILIKE ${name}
          `;
        } else {
          return "Provide owner/name or id";
        }

        const [repo] = await query;

        if (!repo) {
          return "Repository not found.";
        }

        // Get workflows
        const workflows = await sql`
          SELECT id, name, file_path
          FROM workflow_definitions
          WHERE repository_id = ${repo.id}
        `;

        // Get recent runs
        const runs = await sql`
          SELECT r.id, r.status, r.created_at, w.name as workflow_name
          FROM workflow_runs r
          JOIN workflow_definitions w ON r.workflow_definition_id = w.id
          WHERE w.repository_id = ${repo.id}
          ORDER BY r.created_at DESC
          LIMIT 10
        `;

        let result = `Repository: ${repo.owner_name}/${repo.name}\n${"=".repeat(50)}\n`;
        result += `ID:          ${repo.id}\n`;
        result += `Private:     ${repo.is_private}\n`;
        result += `Default:     ${repo.default_branch}\n`;
        result += `Created:     ${repo.created_at}\n`;

        if (workflows.length > 0) {
          result += `\nWorkflows (${workflows.length}):\n`;
          for (const w of workflows) {
            result += `  - ${w.name} (${w.file_path})\n`;
          }
        }

        if (runs.length > 0) {
          result += `\nRecent Runs:\n`;
          for (const r of runs) {
            result += `  - #${r.id} ${r.workflow_name}: ${r.status} (${r.created_at})\n`;
          }
        }

        return result;
      } catch (error) {
        return `Error: ${error}`;
      }
    }

    case "recent_activity": {
      const hours = (args.hours as number) || 24;

      try {
        const users = await sql`
          SELECT COUNT(*) as count
          FROM users
          WHERE created_at > NOW() - make_interval(hours => ${hours})
        `;

        const repos = await sql`
          SELECT COUNT(*) as count
          FROM repositories
          WHERE created_at > NOW() - make_interval(hours => ${hours})
        `;

        const runs = await sql`
          SELECT
            COUNT(*) as total,
            COUNT(*) FILTER (WHERE status = 'completed') as completed,
            COUNT(*) FILTER (WHERE status = 'failed') as failed
          FROM workflow_runs
          WHERE created_at > NOW() - make_interval(hours => ${hours})
        `;

        const sessions = await sql`
          SELECT COUNT(*) as count
          FROM auth_sessions
          WHERE created_at > NOW() - make_interval(hours => ${hours})
        `;

        return `Recent Activity (last ${hours}h)
${"=".repeat(50)}

New users:        ${users[0].count}
New repositories: ${repos[0].count}
New sessions:     ${sessions[0].count}

Workflow runs:
  Total:     ${runs[0].total}
  Completed: ${runs[0].completed}
  Failed:    ${runs[0].failed}
`;
      } catch (error) {
        return `Error: ${error}`;
      }
    }

    case "db_stats": {
      try {
        const size = await sql`
          SELECT pg_size_pretty(pg_database_size(current_database())) as size
        `;

        const tables = await sql`
          SELECT
            relname as table,
            pg_size_pretty(pg_total_relation_size(relid)) as size,
            n_live_tup as rows
          FROM pg_stat_user_tables
          ORDER BY pg_total_relation_size(relid) DESC
          LIMIT 10
        `;

        const connections = await sql`
          SELECT
            count(*) as total,
            count(*) FILTER (WHERE state = 'active') as active,
            count(*) FILTER (WHERE state = 'idle') as idle
          FROM pg_stat_activity
          WHERE datname = current_database()
        `;

        let result = `Database Statistics
${"=".repeat(50)}

Database size: ${size[0].size}

Connections:
  Total:  ${connections[0].total}
  Active: ${connections[0].active}
  Idle:   ${connections[0].idle}

Largest Tables:
`;
        for (const t of tables) {
          result += `  ${t.table}: ${t.size} (${t.rows} rows)\n`;
        }

        return result;
      } catch (error) {
        return `Error: ${error}`;
      }
    }

    case "find_sessions": {
      const userId = args.user_id as number;
      const activeOnly = args.active_only !== false;

      try {
        let query = sql`
          SELECT
            s.session_key as id,
            s.user_id,
            s.username,
            s.created_at,
            s.expires_at,
            s.expires_at > NOW() as is_active
          FROM auth_sessions s
          WHERE 1=1
        `;

        if (userId) {
          query = sql`${query} AND s.user_id = ${userId}`;
        }
        if (activeOnly) {
          query = sql`${query} AND s.expires_at > NOW()`;
        }

        query = sql`${query} ORDER BY s.created_at DESC LIMIT 50`;

        const sessions = await query;

        if (sessions.length === 0) {
          return "No sessions found.";
        }

        let result = `Sessions${activeOnly ? " (active only)" : ""}\n${"=".repeat(50)}\n\n`;

        for (const s of sessions) {
          const status = s.is_active ? "ACTIVE" : "EXPIRED";
          result += `[${status}] ${s.id.slice(0, 16)}...\n`;
          result += `  User: ${s.username} (ID: ${s.user_id})\n`;
          result += `  Created: ${s.created_at}\n`;
          result += `  Expires: ${s.expires_at}\n\n`;
        }

        return result;
      } catch (error) {
        return `Error: ${error}`;
      }
    }

    case "check_connections": {
      try {
        const connections = await sql`
          SELECT
            pid,
            usename,
            application_name,
            client_addr,
            state,
            query_start,
            EXTRACT(EPOCH FROM (NOW() - query_start)) as query_seconds,
            LEFT(query, 100) as query
          FROM pg_stat_activity
          WHERE datname = current_database()
          ORDER BY query_start DESC NULLS LAST
          LIMIT 20
        `;

        let result = `Database Connections\n${"=".repeat(50)}\n\n`;

        for (const c of connections) {
          result += `PID ${c.pid}: ${c.state || "unknown"}\n`;
          result += `  User: ${c.usename} | App: ${c.application_name || "N/A"}\n`;
          if (c.query && c.state === "active") {
            result += `  Query (${Math.round(c.query_seconds || 0)}s): ${c.query}...\n`;
          }
          result += "\n";
        }

        return result;
      } catch (error) {
        return `Error: ${error}`;
      }
    }

    case "explain_query": {
      const query = args.sql as string;

      if (!isReadOnly(query)) {
        return "Error: Only read-only queries (SELECT) are allowed.";
      }

      try {
        const plan = await sql.unsafe(`EXPLAIN ANALYZE ${query}`);
        return plan.map((row: any) => row["QUERY PLAN"]).join("\n");
      } catch (error) {
        return `Error: ${error}`;
      }
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// Main server setup
const server = new Server(
  {
    name: "database-mcp",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Register handlers
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools,
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    const result = await handleTool(name, args || {});
    return {
      content: [{ type: "text", text: result }],
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      content: [{ type: "text", text: `Error: ${message}` }],
      isError: true,
    };
  }
});

// Cleanup on exit
process.on("SIGINT", async () => {
  await sql.end();
  process.exit(0);
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Database MCP server started");
}

main().catch(console.error);
