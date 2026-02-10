import { Ralph, Sequence } from "smithers";
import { z } from "zod";
import { Implement } from "./Implement";
import { implementTable } from "./Implement.schema";
import { Validate } from "./Validate";
import { validateTable } from "./Validate.schema";
import { Review } from "./Review";
import { reviewTable } from "./Review.schema";
import { ReviewFix } from "./ReviewFix";
import { typedOutput, type WorkflowCtx } from "./ctx-type";
import { coerceJsonArray } from "../lib/coerce";
import { MAX_REVIEW_ROUNDS } from "../config";
import type {
  Ticket,
  ResearchRow,
  PlanRow,
  ImplementRow,
  ValidateRow,
  ReviewRow,
} from "./types";

interface ValidationLoopProps {
  ctx: WorkflowCtx;
  ticket: Ticket;
  ticketId: string;
  latestResearch: ResearchRow | undefined;
  latestPlan: PlanRow | undefined;
}

export function ValidationLoop({
  ctx,
  ticket,
  ticketId,
  latestResearch,
  latestPlan,
}: ValidationLoopProps) {
  const latestImplement = typedOutput<ImplementRow>(ctx, implementTable, {
    nodeId: `${ticketId}:implement`,
  });

  const latestValidate = typedOutput<ValidateRow>(ctx, validateTable, {
    nodeId: `${ticketId}:validate`,
  });

  const claudeReview = typedOutput<ReviewRow>(ctx, reviewTable, {
    nodeId: `${ticketId}:review-claude`,
  });
  const codexReview = typedOutput<ReviewRow>(ctx, reviewTable, {
    nodeId: `${ticketId}:review-codex`,
  });

  const allApproved =
    !!claudeReview?.approved &&
    !!codexReview?.approved;

  const validationPassed = !!latestValidate?.allPassed;

  const issueItem = z.object({
    severity: z.string(),
    file: z.string(),
    line: z.number().nullable(),
    description: z.string(),
    suggestion: z.string().nullable(),
  });
  const reviewIssues = [
    ...coerceJsonArray(claudeReview?.issues, issueItem),
    ...coerceJsonArray(codexReview?.issues, issueItem),
  ];

  const reviewFeedback = [
    claudeReview?.feedback,
    codexReview?.feedback,
  ]
    .filter(Boolean)
    .join("\n\n");

  const reviewFixesSummary =
    reviewIssues.length > 0
      ? `Issues from review:\n${JSON.stringify(reviewIssues, null, 2)}\n\nFeedback:\n${reviewFeedback}`
      : null;

  return (
    <Ralph
      id={`${ticketId}:impl-review-loop`}
      until={allApproved}
      maxIterations={MAX_REVIEW_ROUNDS}
      onMaxReached="return-last"
    >
      <Sequence>
        <Implement
          ticketId={ticketId}
          ticketTitle={ticket.title}
          ticketDescription={ticket.description}
          acceptanceCriteria={ticket.acceptanceCriteria?.join("\n- ") ?? ""}
          contextFilePath={
            latestResearch?.contextFilePath ?? `docs/context/${ticketId}.md`
          }
          planFilePath={latestPlan?.planFilePath ?? `docs/plans/${ticketId}.md`}
          previousImplementation={
            latestImplement
              ? {
                  whatWasDone: latestImplement.whatWasDone ?? null,
                  testOutput: latestImplement.testOutput ?? null,
                }
              : null
          }
          reviewFixes={reviewFixesSummary}
          validationFeedback={
            latestValidate
              ? {
                  allPassed: latestValidate.allPassed ?? null,
                  failingSummary: latestValidate.failingSummary ?? null,
                }
              : null
          }
        />

        <Validate
          ticketId={ticketId}
          ticketTitle={ticket.title}
          implementOutput={latestImplement}
        />

        <Review
          ctx={ctx}
          ticketId={ticketId}
          ticket={ticket}
          latestImplement={latestImplement}
          latestValidate={latestValidate}
          validationPassed={validationPassed}
        />

        <ReviewFix
          ctx={ctx}
          ticketId={ticketId}
          ticketTitle={ticket.title}
          allApproved={allApproved}
          validationPassed={validationPassed}
        />
      </Sequence>
    </Ralph>
  );
}
