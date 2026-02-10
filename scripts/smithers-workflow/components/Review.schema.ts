import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";

export const reviewTable = sqliteTable("review", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  reviewer: text("reviewer"),
  approved: integer("approved", { mode: "boolean" }),
  issues: text("issues", { mode: "json" }).$type<any[]>(),
  testCoverage: text("test_coverage"),
  codeQuality: text("code_quality"),
  feedback: text("feedback"),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

export const reviewOutputSchema = z.object({
  reviewer: z.string().default("unknown").describe("Which agent reviewed (claude, codex)"),
  approved: z.boolean().describe("Whether the reviewer approves (LGTM)"),
  issues: z.array(z.object({
    severity: z.enum(["critical", "major", "minor", "nit"]),
    file: z.string(),
    line: z.number().nullable(),
    description: z.string(),
    suggestion: z.string().nullable(),
  })).describe("Issues found during review"),
  testCoverage: z.enum(["excellent", "good", "insufficient", "missing"]).describe("Test coverage assessment"),
  codeQuality: z.enum(["excellent", "good", "needs-work", "poor"]).describe("Code quality assessment"),
  feedback: z.string().describe("Overall review feedback"),
});
