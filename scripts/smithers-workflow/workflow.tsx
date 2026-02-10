import { smithers, Workflow, Sequence, Branch } from "smithers";
import { db } from "./db";
import { discoverTable, ticketSchema } from "./components/Discover";
import { reportTable } from "./components/Report";
import { outputTable } from "./components/PassTracker";
import { coerceJsonArray } from "./lib/coerce";
import {
  Discover,
  TicketPipeline,
  PassTracker,
  type Ticket,
} from "./components";
import { typedOutput } from "./components/ctx-type";

export default smithers(db, (ctx) => {
  const latestDiscover = typedOutput<{
    tickets: unknown;
    reasoning?: string;
    completionEstimate?: string;
  }>(ctx, discoverTable, { nodeId: "discover" });

  const allTickets = coerceJsonArray(latestDiscover?.tickets, ticketSchema);

  const pendingTickets = allTickets.filter(
    (t) => !typedOutput(ctx, reportTable, { nodeId: `${t.id}:report` }),
  );

  const completedTicketIds = allTickets
    .filter((t) => !!typedOutput(ctx, reportTable, { nodeId: `${t.id}:report` }))
    .map((t) => t.id);

  const needsDiscovery = pendingTickets.length === 0;

  const prevPassTracker = typedOutput<{
    totalIterations?: number;
    ticketsCompleted?: string[];
    summary?: string;
  }>(ctx, outputTable, { nodeId: "pass-tracker" });

  const previousRun = prevPassTracker
    ? {
        summary: prevPassTracker.summary ?? "",
        ticketsCompleted: prevPassTracker.ticketsCompleted ?? [],
      }
    : null;

  return (
    <Workflow name="smithers-v2-workflow">
      <Sequence>
        <Branch
          if={needsDiscovery}
          then={<Discover previousRun={previousRun} />}
        />

        {pendingTickets.map((ticket) => (
          <TicketPipeline key={ticket.id} ctx={ctx} ticket={ticket} />
        ))}

        <PassTracker ctx={ctx} completedTicketIds={completedTicketIds} />
      </Sequence>
    </Workflow>
  );
});
