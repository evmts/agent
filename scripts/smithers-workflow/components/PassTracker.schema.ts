import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";

export const outputTable = sqliteTable("output", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketsCompleted: text("tickets_completed", { mode: "json" }).$type<string[]>(),
  totalIterations: integer("total_iterations"),
  summary: text("summary"),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

export const passTrackerOutputSchema = z.object({
  totalIterations: z.number().describe("Total pass count"),
  ticketsCompleted: z.array(z.string()).describe("IDs of tickets completed this pass (delta, not cumulative)"),
  summary: z.string().describe("Summary of what was accomplished this pass"),
});
