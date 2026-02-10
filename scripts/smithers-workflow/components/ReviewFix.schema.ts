import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";

export const reviewFixTable = sqliteTable("review_fix", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  fixesMade: text("fixes_made", { mode: "json" }).$type<any[]>(),
  falsePositiveComments: text("false_positive_comments", { mode: "json" }).$type<any[]>(),
  commitMessages: text("commit_messages", { mode: "json" }).$type<string[]>(),
  allIssuesResolved: integer("all_issues_resolved", { mode: "boolean" }),
  summary: text("summary"),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

export const reviewFixOutputSchema = z.object({
  ticketId: z.string().describe("The ticket being fixed"),
  fixesMade: z.array(z.object({
    issue: z.string(),
    fix: z.string(),
    file: z.string(),
  })).describe("Fixes applied"),
  falsePositiveComments: z.array(z.object({
    file: z.string(),
    line: z.number(),
    issue: z.string().describe("The review issue that was a false positive"),
    rationale: z.string().describe("Why this is a false positive"),
  })).nullable().describe("False positives to suppress in future reviews (stored in DB, NOT as code comments)"),
  commitMessages: z.array(z.string()).describe("Commit messages for fixes"),
  allIssuesResolved: z.boolean().describe("Whether all review issues were resolved"),
  summary: z.string().describe("Summary of fixes"),
});
