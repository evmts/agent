import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";

export const validateTable = sqliteTable("validate", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  allPassed: integer("all_passed", { mode: "boolean" }),
  failingSummary: text("failing_summary"),
  fullOutput: text("full_output"),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

export const validateOutputSchema = z.object({
  ticketId: z.string().describe("The ticket being validated"),
  allPassed: z.boolean().describe("Whether `zig build all` exited with status 0"),
  failingSummary: z.string().nullable().describe("Summary of what failed and why (null if all passed)"),
  fullOutput: z.string().describe("Full output from `zig build all`"),
});
