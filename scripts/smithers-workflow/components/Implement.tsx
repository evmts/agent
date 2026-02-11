
import { Task } from "smithers";
import { z } from "zod";
import { codex } from "../agents";
import ImplementPrompt from "./Implement.mdx";
export { ImplementOutput } from "./Implement.schema";
import { useCtx, tables } from "../smithers";
import type { Ticket } from "./Discover.schema";
import type { ResearchOutput } from "./Research.schema";
import type { PlanOutput } from "./Plan.schema";
import type { ImplementOutput } from "./Implement.schema";
import type { ValidateOutput } from "./Validate.schema";
import type { ReviewOutput } from "./Review.schema";

interface ImplementProps {
  ticket: Ticket;
}

export function Implement({ ticket }: ImplementProps) {
  const ctx = useCtx();
  const ticketId = ticket.id;
  const acceptanceCriteria = ticket.acceptanceCriteria?.join("\n- ") ?? "";

  const latestResearch = ctx.latest(tables.research, `${ticketId}:research`) as ResearchOutput | undefined;
  const latestPlan = ctx.latest(tables.plan, `${ticketId}:plan`) as PlanOutput | undefined;
  const latestImplement = ctx.latest(tables.implement, `${ticketId}:implement`) as ImplementOutput | undefined;
  const latestValidate = ctx.latest(tables.validate, `${ticketId}:validate`) as ValidateOutput | undefined;

  const claudeReview = ctx.latest(tables.review, `${ticketId}:review-claude`) as ReviewOutput | undefined;
  const codexReview = ctx.latest(tables.review, `${ticketId}:review-codex`) as ReviewOutput | undefined;

  const issueItem = z.object({
    severity: z.string(),
    file: z.string(),
    line: z.number().nullable(),
    description: z.string(),
    suggestion: z.string().nullable(),
  });
  const reviewIssues = [
    ...ctx.latestArray(claudeReview?.issues, issueItem),
    ...ctx.latestArray(codexReview?.issues, issueItem),
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
    <Task
      id={`${ticketId}:implement`}
      output={tables.implement}
      agent={codex}
    >
      <ImplementPrompt
        ticketId={ticketId}
        ticketTitle={ticket.title}
        ticketDescription={ticket.description}
        acceptanceCriteria={acceptanceCriteria}
        contextFilePath={latestResearch?.contextFilePath ?? `docs/context/${ticketId}.md`}
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
    </Task>
  );
}
