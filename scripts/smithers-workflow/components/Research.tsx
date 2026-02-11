import { Task } from "smithers";
import { claude } from "../agents";
import ResearchPrompt from "./Research.mdx";
export { ResearchOutput } from "./Research.schema";
import { tables } from "../smithers";
import type { Ticket } from "./Discover.schema";

interface ResearchProps {
  ticket: Ticket;
}

export function Research({ ticket }: ResearchProps) {
  const ticketId = ticket.id;
  const acceptanceCriteria = ticket.acceptanceCriteria?.join("\n- ") ?? "";

  return (
    <Task id={`${ticketId}:research`} output={tables.research} agent={claude}>
      <ResearchPrompt
        ticketId={ticketId}
        ticketTitle={ticket.title}
        ticketDescription={ticket.description}
        acceptanceCriteria={acceptanceCriteria}
        testPlan={ticket.testPlan}
      />
    </Task>
  );
}
