
import { Task } from "../smithers";
import { claude } from "../agents";
import PlanPrompt from "./Plan.mdx";
export { PlanOutput } from "./Plan.schema";
import { useCtx, tables } from "../smithers";
import type { Ticket } from "./Discover.schema";
import type { ResearchOutput } from "./Research.schema";

interface PlanProps {
  ticket: Ticket;
}

export function Plan({ ticket }: PlanProps) {
  const ctx = useCtx();
  const ticketId = ticket.id;
  const acceptanceCriteria = ticket.acceptanceCriteria?.join("\n- ") ?? "";

  const latestResearch = ctx.latest(tables.research, `${ticketId}:research`) as ResearchOutput | undefined;

  return (
    <Task
      id={`${ticketId}:plan`}
      output={tables.plan}
      agent={claude}
    >
      <PlanPrompt
        ticketId={ticketId}
        ticketTitle={ticket.title}
        ticketDescription={ticket.description}
        acceptanceCriteria={acceptanceCriteria}
        contextFilePath={latestResearch?.contextFilePath ?? `docs/context/${ticketId}.md`}
        researchSummary={latestResearch?.summary ?? ""}
      />
    </Task>
  );
}
