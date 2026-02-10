import { drizzle } from "drizzle-orm/bun-sqlite";
import { getTableConfig, sqliteTable, text } from "drizzle-orm/sqlite-core";
import type { SQLiteTable } from "drizzle-orm/sqlite-core";

// Import tables from the components that define them
import { discoverTable } from "./components/Discover";
import { researchTable } from "./components/Research";
import { planTable } from "./components/Plan";
import { implementTable } from "./components/Implement";
import { validateTable } from "./components/Validate";
import { reviewTable } from "./components/Review";
import { reviewFixTable } from "./components/ReviewFix";
import { reportTable } from "./components/Report";
import { outputTable } from "./components/PassTracker";

// Input table required by smithers engine
const inputTable = sqliteTable("input", {
  runId: text("run_id").primaryKey(),
});

// Schema: all tables registered for drizzle
const schema = {
  input: inputTable,
  discover: discoverTable,
  research: researchTable,
  plan: planTable,
  implement: implementTable,
  validate: validateTable,
  review: reviewTable,
  review_fix: reviewFixTable,
  report: reportTable,
  output: outputTable,
};

// Primary keys per table (composite keys not expressible in sqliteTable columns)
const primaryKeys: Record<string, string[]> = {
  input: ["run_id"],
  discover: ["run_id", "node_id", "iteration"],
  research: ["run_id", "node_id", "iteration"],
  plan: ["run_id", "node_id", "iteration"],
  implement: ["run_id", "node_id", "iteration"],
  validate: ["run_id", "node_id", "iteration"],
  review: ["run_id", "node_id", "iteration"],
  review_fix: ["run_id", "node_id", "iteration"],
  report: ["run_id", "node_id", "iteration"],
  output: ["run_id", "node_id"],
};

// Auto-generate CREATE TABLE SQL from Drizzle schema
function createTableSQL(table: SQLiteTable): string {
  const config = getTableConfig(table);
  const colDefs = config.columns.map((col) => {
    let def = `${col.name} ${col.getSQLType()}`;
    if (col.notNull) def += " NOT NULL";
    if (col.hasDefault && col.default !== undefined) def += ` DEFAULT ${col.default}`;
    return def;
  });
  const pk = primaryKeys[config.name];
  if (pk) colDefs.push(`PRIMARY KEY (${pk.join(", ")})`);
  return `CREATE TABLE IF NOT EXISTS ${config.name} (\n    ${colDefs.join(",\n    ")}\n  )`;
}

// Database setup
export const db = drizzle("./smithers-v2.db", { schema });

const allCreateSQL = Object.values(schema).map(createTableSQL).join(";\n  ");
(db as any).$client.exec(allCreateSQL);
