
import { Ralph, Sequence } from "smithers";
import { Implement } from "./Implement";
import { implementTable } from "./Implement";
import { Validate } from "./Validate";
import { validateTable } from "./Validate";
import { Review } from "./Review";
import { reviewTable } from "./Review";
import { ReviewFix } from "./ReviewFix";
import type { WorkflowCtx } from "./ctx-type";
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

const MAX_REVIEW_ROUNDS = 3;

export function ValidationLoop({
  ctx,
  ticket,
  ticketId,
  latestResearch,
  latestPlan,
}: ValidationLoopProps) {
  const latestImplement = ctx.outputMaybe(implementTable, {
    nodeId: `${ticketId}:implement`,
  }) as ImplementRow | undefined;

  const latestValidate = ctx.outputMaybe(validateTable, {
    nodeId: `${ticketId}:validate`,
  }) as ValidateRow | undefined;

  const claudeReview = ctx.outputMaybe(reviewTable, {
    nodeId: `${ticketId}:review-claude`,
  }) as ReviewRow | undefined;
  const codexReview = ctx.outputMaybe(reviewTable, {
    nodeId: `${ticketId}:review-codex`,
  }) as ReviewRow | undefined;
  const geminiReview = ctx.outputMaybe(reviewTable, {
    nodeId: `${ticketId}:review-gemini`,
  }) as ReviewRow | undefined;

  const allApproved =
    (claudeReview?.approved ?? 0) === 1 &&
    (codexReview?.approved ?? 0) === 1 &&
    (geminiReview?.approved ?? 0) === 1;

  const validationPassed = (latestValidate?.allPassed ?? 0) === 1;

  return (
    <Ralph
      id={`${ticketId}:impl-review-loop`}
      until={allApproved}
      maxIterations={MAX_REVIEW_ROUNDS * 3}
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
          planSummary={latestPlan?.planFilePath ?? ""}
          approachDecisions={latestPlan?.implementationSteps ?? ""}
          filesAffected={`Files to create: ${latestPlan?.filesToCreate ?? ""}\nFiles to modify: ${latestPlan?.filesToModify ?? ""}`}
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
        />
      </Sequence>
    </Ralph>
  );
}
