import { resolve } from "node:path";
import { Database } from "bun:sqlite";
import { drizzle } from "drizzle-orm/bun-sqlite";
import { migrate } from "drizzle-orm/bun-sqlite/migrator";
import { sqliteTable, text } from "drizzle-orm/sqlite-core";

import { discoverTable } from "./components/Discover.schema";
import { researchTable } from "./components/Research.schema";
import { planTable } from "./components/Plan.schema";
import { implementTable } from "./components/Implement.schema";
import { validateTable } from "./components/Validate.schema";
import { reviewTable } from "./components/Review.schema";
import { reviewFixTable } from "./components/ReviewFix.schema";
import { reportTable } from "./components/Report.schema";
import { outputTable } from "./components/PassTracker.schema";

const inputTable = sqliteTable("input", {
  runId: text("run_id").primaryKey(),
});

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

const DIR = resolve(new URL(".", import.meta.url).pathname);
const DB_PATH = resolve(DIR, "smithers-v2.db");
const MIGRATIONS_PATH = resolve(DIR, "drizzle");

const sqlite = new Database(DB_PATH);
sqlite.exec("PRAGMA journal_mode = WAL");
sqlite.exec("PRAGMA foreign_keys = ON");

export const db = drizzle(sqlite, { schema });

migrate(db, { migrationsFolder: MIGRATIONS_PATH });
