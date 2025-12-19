import postgres from "postgres";

const DATABASE_URL = process.env.DATABASE_URL ||
  "postgresql://postgres:password@localhost:54321/electric";

const sql = postgres(DATABASE_URL);

async function migrate() {
  console.log("Running migrations...");

  const schema = await Bun.file("./db/schema.sql").text();

  // Split by semicolons and run each statement
  const statements = schema
    .split(";")
    .map(s => s.trim())
    .filter(s => s.length > 0);

  for (const statement of statements) {
    try {
      await sql.unsafe(statement);
      console.log("✓", statement.slice(0, 50) + "...");
    } catch (error) {
      console.error("✗", statement.slice(0, 50) + "...");
      console.error("  Error:", (error as Error).message);
    }
  }

  console.log("Migrations complete!");
  await sql.end();
  process.exit(0);
}

migrate();
