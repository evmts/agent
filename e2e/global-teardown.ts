/**
 * Playwright Global Teardown
 *
 * Runs after all tests to clean up test data.
 * Set KEEP_TEST_DATA=1 to preserve test data for debugging.
 */

import { teardown } from "./seed";

async function globalTeardown() {
  console.log("\n=== Playwright Global Teardown ===\n");

  // Skip teardown if KEEP_TEST_DATA is set (useful for debugging)
  if (process.env.KEEP_TEST_DATA === "1") {
    console.log("KEEP_TEST_DATA=1, skipping teardown");
    return;
  }

  try {
    await teardown();
    console.log("\n=== Global Teardown Complete ===\n");
  } catch (error) {
    console.error("Global teardown failed:", error);
    // Don't throw - we don't want to fail the test run on teardown errors
  }
}

export default globalTeardown;
