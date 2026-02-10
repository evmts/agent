
import { Task } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { codex } from "../agents";
import type { WorkflowCtx } from "./ctx-type";
import ReviewFixPrompt from "../prompts/6_review_fix.mdx";
import { reviewTable } from "./Review";
import type { ReviewRow } from "./types";

export const reviewFixTable = sqliteTable("review_fix", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  fixesMade: text("fixes_made").notNull(),
  falsePositiveComments: text("false_positive_comments"),
  commitMessages: text("commit_messages").notNull(),
  allIssuesResolved: integer("all_issues_resolved").notNull(),
  summary: text("summary").notNull(),
});

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
}

function parseJson<T>(raw: string | null | undefined): T | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export function ReviewFix({
  ctx,
  ticketId,
  ticketTitle,
  allApproved,
}: ReviewFixProps) {
  const claudeReview = ctx.outputMaybe(reviewTable, {
    nodeId: `${ticketId}:review-claude`,
  }) as ReviewRow | undefined;
  const codexReview = ctx.outputMaybe(reviewTable, {
    nodeId: `${ticketId}:review-codex`,
  }) as ReviewRow | undefined;
  const geminiReview = ctx.outputMaybe(reviewTable, {
    nodeId: `${ticketId}:review-gemini`,
  }) as ReviewRow | undefined;

  const allReviewIssues = [
    ...(parseJson<any[]>(claudeReview?.issues) ?? []),
    ...(parseJson<any[]>(codexReview?.issues) ?? []),
    ...(parseJson<any[]>(geminiReview?.issues) ?? []),
  ];

  const allReviewFeedback = [
    claudeReview?.feedback,
    codexReview?.feedback,
    geminiReview?.feedback,
  ]
    .filter(Boolean)
    .join("\n\n");

  return (
    <Task
      id={`${ticketId}:review-fix`}
      output={reviewFixTable}
      outputSchema={reviewFixOutputSchema}
      agent={codex}
      skipIf={allApproved || allReviewIssues.length === 0}
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
