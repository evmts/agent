import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "sqlite",
  schema: "./components/*",
  out: "./drizzle",
  dbCredentials: {
    url: "./smithers-v2.db",
  },
});
