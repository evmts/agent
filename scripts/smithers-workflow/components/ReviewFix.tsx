
import { Task } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { codex } from "../agents";
import { typedOutput, type WorkflowCtx } from "./ctx-type";
import ReviewFixPrompt from "../prompts/6_review_fix.mdx";
import { reviewTable } from "./Review";
import { coerceJsonArray } from "../lib/coerce";
import type { ReviewRow } from "./types";

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
    comment: z.string(),
  })).nullable().describe("Comments added to prevent false positive reviews in future"),
  commitMessages: z.array(z.string()).describe("Commit messages for fixes"),
  allIssuesResolved: z.boolean().describe("Whether all review issues were resolved"),
  summary: z.string().describe("Summary of fixes"),
});

interface ReviewFixProps {
  ctx: WorkflowCtx;
  ticketId: string;
  ticketTitle: string;
  allApproved: boolean;
  validationPassed: boolean;
}

export function ReviewFix({
  ctx,
  ticketId,
  ticketTitle,
  allApproved,
  validationPassed,
}: ReviewFixProps) {
  const claudeReview = typedOutput<ReviewRow>(ctx, reviewTable, {
    nodeId: `${ticketId}:review-claude`,
  });
  const codexReview = typedOutput<ReviewRow>(ctx, reviewTable, {
    nodeId: `${ticketId}:review-codex`,
  });

  const issueItem = z.object({
    severity: z.string(),
    file: z.string(),
    line: z.number().nullable(),
    description: z.string(),
    suggestion: z.string().nullable(),
  });
  const allReviewIssues = [
    ...coerceJsonArray(claudeReview?.issues, issueItem),
    ...coerceJsonArray(codexReview?.issues, issueItem),
  ];

  const allReviewFeedback = [
    claudeReview?.feedback,
    codexReview?.feedback,
  ]
    .filter(Boolean)
    .join("\n\n");

  return (
    <Task
      id={`${ticketId}:review-fix`}
      output={reviewFixTable}
      outputSchema={reviewFixOutputSchema}
      agent={codex}
      skipIf={!validationPassed || allApproved || allReviewIssues.length === 0}
    >
      {render(ReviewFixPrompt, {
        ticketId,
        ticketTitle,
        issues: allReviewIssues,
        feedback: allReviewFeedback,
        reviewFixSchema: zodSchemaToJsonExample(reviewFixOutputSchema),
      })}
    </Task>
  );
}
