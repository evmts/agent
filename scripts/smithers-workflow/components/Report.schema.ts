import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";

export const reportTable = sqliteTable("report", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  ticketTitle: text("ticket_title"),
  status: text("status"),
  summary: text("summary"),
  filesChanged: integer("files_changed"),
  testsAdded: integer("tests_added"),
  reviewRounds: integer("review_rounds"),
  struggles: text("struggles", { mode: "json" }).$type<string[]>(),
  timeSpent: text("time_spent"),
  lessonsLearned: text("lessons_learned", { mode: "json" }).$type<string[]>(),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

export const reportOutputSchema = z.object({
  ticketId: z.string().default("unknown").describe("The ticket this report covers"),
  ticketTitle: z.string().describe("Title of the ticket"),
  status: z.enum(["completed", "partial", "failed"]).describe("Final status"),
  summary: z.string().describe("Concise summary of what was implemented"),
  filesChanged: z.number().describe("Number of files changed (pre-computed, echo back as-is)"),
  testsAdded: z.number().describe("Number of tests added (pre-computed, echo back as-is)"),
  reviewRounds: z.number().describe("How many review rounds it took (pre-computed, echo back as-is)"),
  struggles: z.array(z.string()).nullable().describe("Any struggles or issues encountered"),
  timeSpent: z.string().nullable().describe("Approximate time spent"),
  lessonsLearned: z.array(z.string()).nullable().describe("Lessons for future tickets"),
});
