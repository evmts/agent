
import { Task, Parallel } from "smithers";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude, codex } from "../agents";
import type { WorkflowCtx } from "./ctx-type";
import ReviewPrompt from "../prompts/5_review.mdx";
import type { Ticket, ImplementRow, ValidateRow } from "./types";
export { reviewTable, reviewOutputSchema } from "./Review.schema";
import { reviewTable, reviewOutputSchema } from "./Review.schema";

interface ReviewProps {
  ctx: WorkflowCtx;
  ticketId: string;
  ticket: Ticket;
  latestImplement: ImplementRow | undefined;
  latestValidate: ValidateRow | undefined;
  validationPassed: boolean;
}


export function Review({
  ctx,
  ticketId,
  ticket,
  latestImplement,
  latestValidate,
  validationPassed,
}: ReviewProps) {
  if (!validationPassed) {
    return null;
  }
  const reviewSchema = zodSchemaToJsonExample(reviewOutputSchema);

  const reviewProps = {
    ticketId,
    ticketTitle: ticket.title,
    ticketDescription: ticket.description,
    acceptanceCriteria: ticket.acceptanceCriteria?.join("\n- ") ?? "",
    filesCreated: latestImplement?.filesCreated ?? [],
    filesModified: latestImplement?.filesModified ?? [],
    validationPassed: latestValidate?.allPassed ? "PASS" : "FAIL",
    failingSummary: latestValidate?.failingSummary ?? null,
    reviewSchema,
  };

  return (
    <Parallel>
      <Task
        id={`${ticketId}:review-claude`}
        output={reviewTable}
        outputSchema={reviewOutputSchema}
        agent={claude}
      >
        {render(ReviewPrompt, { ...reviewProps, reviewer: "claude" })}
      </Task>

      <Task
        id={`${ticketId}:review-codex`}
        output={reviewTable}
        outputSchema={reviewOutputSchema}
        agent={codex}
      >
        {render(ReviewPrompt, { ...reviewProps, reviewer: "codex" })}
      </Task>
    </Parallel>
  );
}
