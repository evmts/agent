import { smithers, Workflow, Sequence, Ralph, Branch } from "smithers";
import { db } from "./db";
import { discoverTable } from "./components/Discover";
import {
  Discover,
  TicketPipeline,
  PassTracker,
  type DiscoverRow,
  type Ticket,
} from "./components";

function parseJson<T>(raw: string | null | undefined): T | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export default smithers(db, (ctx) => {
  const latestDiscover = ctx.outputMaybe(discoverTable, {
    nodeId: "discover",
  }) as DiscoverRow | undefined;

  const tickets: Ticket[] = parseJson(latestDiscover?.tickets) ?? [];

  const needsDiscovery = tickets.length === 0;

  return (
    <Workflow name="smithers-v2-workflow">
      <Ralph until={false} onMaxReached="return-last">
        <Sequence>
          <Branch if={needsDiscovery} then={<Discover />} />

          {tickets.map((ticket) => (
            <TicketPipeline key={ticket.id} ctx={ctx} ticket={ticket} />
          ))}

          <PassTracker ctx={ctx} />
        </Sequence>
      </Ralph>
    </Workflow>
  );
});
