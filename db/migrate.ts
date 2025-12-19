import { readFileSync } from 'fs';
import sql from "./client";

async function migrate() {
  console.log("Running migrations...");

  const schema = readFileSync("./db/schema.sql", "utf-8");

  // Split by semicolons and run each statement
  const statements = schema
    .split(";")
    .map(s => s.trim())
    .filter(s => s.length > 0);

  for (const statement of statements) {
    try {
      await sql.unsafe(statement);
      console.log("✓", `${statement.slice(0, 50)}...`);
    } catch (error) {
      console.error("✗", `${statement.slice(0, 50)}...`);
      console.error("  Error:", (error as Error).message);
    }
  }

  console.log("Migrations complete!");
  await sql.end();
  process.exit(0);
}

migrate();