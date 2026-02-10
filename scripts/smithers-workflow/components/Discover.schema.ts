import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";

export const discoverTable = sqliteTable("discover", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  tickets: text("tickets", { mode: "json" }).$type<any[]>().notNull(),
  reasoning: text("reasoning"),
  completionEstimate: text("completion_estimate"),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

export const ticketSchema = z.object({
  id: z.string().describe("Unique slug identifier derived from the title (e.g. 'sqlite-wal-init', 'chat-sidebar-mode-bar'). Must be lowercase kebab-case. NEVER use numeric IDs like T-001."),
  title: z.string().describe("Short imperative title (e.g. 'Add SQLite WAL mode initialization')"),
  description: z.string().describe("Detailed description of what needs to be implemented"),
  scope: z.enum(["zig", "swift", "web", "e2e", "docs", "build"]).describe("Primary scope of the ticket (use 'e2e' when spanning Zig+Swift+Web)"),
  layers: z.array(z.string()).describe("Which layers this ticket touches (e.g. ['zig'] for infra, ['zig','swift','web'] for e2e)"),
  acceptanceCriteria: z.array(z.string()).describe("List of acceptance criteria"),
  testPlan: z.string().describe("How to validate: unit tests, e2e tests, manual verification"),
  estimatedComplexity: z.enum(["trivial", "small", "medium", "large"]).describe("Estimated complexity"),
  dependencies: z.array(z.string()).nullable().describe("IDs of tickets this depends on"),
});

export const discoverOutputSchema = z.object({
  tickets: z.array(ticketSchema).max(5).describe("The next 0-5 tickets to implement"),
  reasoning: z.string().describe("Why these tickets were chosen and in this order"),
  completionEstimate: z.string().describe("Overall progress estimate for the project"),
});
