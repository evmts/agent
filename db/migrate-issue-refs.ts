import { readFileSync } from 'fs';
import sql from "./client";

async function migrate() {
  console.log("Running issue references migration...");

  const schema = readFileSync("./db/migrate-issue-references.sql", "utf-8");

  // Split by semicolons and run each statement
  const statements = schema
    .split(";")
    .map(s => s.trim())
    .filter(s => s.length > 0 && !s.startsWith("--"));

  for (const statement of statements) {
    try {
      await sql.unsafe(statement);
      console.log("✓", `${statement.slice(0, 60).replace(/\n/g, ' ')}...`);
    } catch (error) {
      console.error("✗", `${statement.slice(0, 60).replace(/\n/g, ' ')}...`);
      console.error("  Error:", (error as Error).message);
    }
  }

  console.log("Issue references migration complete!");
  await sql.end();
  process.exit(0);
}

migrate();
