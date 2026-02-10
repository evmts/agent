
import { Task } from "smithers";
import { z } from "zod";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { codex } from "../agents";
import { typedOutput, type WorkflowCtx } from "./ctx-type";
import ReviewFixPrompt from "../prompts/6_review_fix.mdx";
import { reviewTable } from "./Review.schema";
import { coerceJsonArray } from "../lib/coerce";
import type { ReviewRow } from "./types";
export { reviewFixTable, reviewFixOutputSchema } from "./ReviewFix.schema";
import { reviewFixTable, reviewFixOutputSchema } from "./ReviewFix.schema";

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

  // Collect previous false positives to pass to prompt for suppression context
  const prevFalsePositives = typedOutput<{ falsePositiveComments?: any[] }>(
    ctx, reviewFixTable, { nodeId: `${ticketId}:review-fix` },
  )?.falsePositiveComments ?? [];

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
        previousFalsePositives: prevFalsePositives,
        reviewFixSchema: zodSchemaToJsonExample(reviewFixOutputSchema),
      })}
    </Task>
  );
}
