import { Sequence, Branch } from "smithers";
import { Discover, TicketPipeline } from "./components";
import { Ticket } from "./components/Discover.schema";
import { Workflow, smithers, tables } from "./smithers";

export default smithers((ctx) => {
  const discoverOutput = ctx.latest(tables.discover, "discover-codex");
  const unfinishedTickets = ctx
    .latestArray(discoverOutput?.tickets, Ticket)
    .filter((t: Ticket) => !ctx.latest(tables.report, `${t.id}:report`)) as Ticket[];

  return (
    <Workflow name="smithers-v2-workflow">
      <Sequence>
        <Branch if={unfinishedTickets.length === 0} then={<Discover />} />
        {unfinishedTickets.map((ticket) => (
          <TicketPipeline key={ticket.id} ticket={ticket} />
        ))}
      </Sequence>
    </Workflow>
  );
});
