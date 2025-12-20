/**
 * Playwright Global Setup
 *
 * Runs before all tests to seed the database with test data.
 */

import { seed } from "./seed";

async function globalSetup() {
  console.log("\n=== Playwright Global Setup ===\n");

  try {
    await seed();
    console.log("\n=== Global Setup Complete ===\n");
  } catch (error) {
    console.error("Global setup failed:", error);
    throw error;
  }
}

export default globalSetup;
