import { Sequence } from "smithers";
import { Research } from "./Research";
import { researchTable } from "./Research";
import { Plan } from "./Plan";
import { planTable } from "./Plan";
import { ValidationLoop } from "./ValidationLoop";
import { Report } from "./Report";
import { reportTable } from "./Report";
import { implementTable } from "./Implement";
import { reviewTable } from "./Review";
import { typedOutput, type WorkflowCtx } from "./ctx-type";
import type {
  Ticket,
  ResearchRow,
  PlanRow,
  ImplementRow,
  ReportRow,
  ReviewRow,
} from "./types";

interface TicketPipelineProps {
  ctx: WorkflowCtx;
  ticket: Ticket;
}

export function TicketPipeline({ ctx, ticket }: TicketPipelineProps) {
  const tid = ticket.id;

  const latestResearch = typedOutput<ResearchRow>(ctx, researchTable, {
    nodeId: `${tid}:research`,
  });

  const latestPlan = typedOutput<PlanRow>(ctx, planTable, {
    nodeId: `${tid}:plan`,
  });

  const latestImplement = typedOutput<ImplementRow>(ctx, implementTable, {
    nodeId: `${tid}:implement`,
  });

  const latestReport = typedOutput<ReportRow>(ctx, reportTable, {
    nodeId: `${tid}:report`,
  });

  const ticketComplete = latestReport != null;

  const claudeReview = typedOutput<ReviewRow>(ctx, reviewTable, {
    nodeId: `${tid}:review-claude`,
  });
  const codexReview = typedOutput<ReviewRow>(ctx, reviewTable, {
    nodeId: `${tid}:review-codex`,
  });

  const allApproved = !!claudeReview?.approved && !!codexReview?.approved;

  const hasReviews = claudeReview != null || codexReview != null;
  const loopExhausted = hasReviews && !allApproved;

  return (
    <Sequence key={tid} skipIf={ticketComplete}>
      <Research
        ticketId={tid}
        ticketTitle={ticket.title}
        ticketDescription={ticket.description}
        acceptanceCriteria={ticket.acceptanceCriteria?.join("\n- ") ?? ""}
        testPlan={ticket.testPlan}
      />

      <Plan
        ticketId={tid}
        ticketTitle={ticket.title}
        ticketDescription={ticket.description}
        acceptanceCriteria={ticket.acceptanceCriteria?.join("\n- ") ?? ""}
        contextFilePath={
          latestResearch?.contextFilePath ?? `docs/context/${tid}.md`
        }
        researchSummary={latestResearch?.summary ?? ""}
      />

      <ValidationLoop
        ctx={ctx}
        ticket={ticket}
        ticketId={tid}
        latestResearch={latestResearch}
        latestPlan={latestPlan}
      />

      <Report
        ctx={ctx}
        ticketId={tid}
        ticketTitle={ticket.title}
        ticketDescription={ticket.description}
        latestImplement={latestImplement}
        loopExhausted={loopExhausted}
      />
    </Sequence>
  );
}
