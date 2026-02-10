
import { Sequence } from "smithers";
import { Research } from "./Research";
import { researchTable } from "./Research";
import { Plan } from "./Plan";
import { planTable } from "./Plan";
import { ValidationLoop } from "./ValidationLoop";
import { Report } from "./Report";
import { reportTable } from "./Report";
import { implementTable } from "./Implement";
import type { WorkflowCtx } from "./ctx-type";
import type {
  Ticket,
  ResearchRow,
  PlanRow,
  ImplementRow,
  ReportRow,
} from "./types";

interface TicketPipelineProps {
  ctx: WorkflowCtx;
  ticket: Ticket;
}

export function TicketPipeline({ ctx, ticket }: TicketPipelineProps) {
  const tid = ticket.id;

  const latestResearch = ctx.outputMaybe(researchTable, {
    nodeId: `${tid}:research`,
  }) as ResearchRow | undefined;

  const latestPlan = ctx.outputMaybe(planTable, {
    nodeId: `${tid}:plan`,
  }) as PlanRow | undefined;

  const latestImplement = ctx.outputMaybe(implementTable, {
    nodeId: `${tid}:implement`,
  }) as ImplementRow | undefined;

  const latestReport = ctx.outputMaybe(reportTable, {
    nodeId: `${tid}:report`,
  }) as ReportRow | undefined;

  const ticketComplete = latestReport != null;

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
      />
    </Sequence>
  );
}
