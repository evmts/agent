import postgres from "postgres";

const DATABASE_URL = process.env.DATABASE_URL ||
  "postgresql://postgres:password@localhost:54321/electric";

export const sql = postgres(DATABASE_URL);
