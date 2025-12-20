import { readFileSync } from 'fs';
import sql from "./client";

async function migrate() {
  console.log("Running issue references migration...");

  const schema = readFileSync("./db/migrate-issue-references.sql", "utf-8");

  // Remove comments and split by semicolons at end of statements
  const lines = schema.split('\n');
  const cleanedLines = lines.filter(line => !line.trim().startsWith('--'));
  const cleaned = cleanedLines.join('\n');

  const statements = cleaned
    .split(/;\s*\n/)
    .map(s => s.trim())
    .filter(s => s.length > 0)
    .map(s => s.endsWith(';') ? s : s + ';');

  for (const statement of statements) {
    try {
      await sql.unsafe(statement);
      const preview = statement.slice(0, 60).replace(/\n/g, ' ').replace(/\s+/g, ' ');
      console.log("✓", `${preview}...`);
    } catch (error) {
      const preview = statement.slice(0, 60).replace(/\n/g, ' ').replace(/\s+/g, ' ');
      console.error("✗", `${preview}...`);
      console.error("  Error:", (error as Error).message);
    }
  }

  console.log("Issue references migration complete!");
  await sql.end();
  process.exit(0);
}

migrate();
