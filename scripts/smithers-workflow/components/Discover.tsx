import { Task } from "smithers";
import { codex } from "../agents";
import DiscoverPrompt from "./Discover.mdx";
import { Ticket } from "./Discover.schema";
import { useCtx, tables } from "../smithers";

export function Discover() {
  const ctx = useCtx();

  const discoverOutput = ctx.latest(tables.discover, "discover-codex");
  const allTickets = ctx.latestArray(discoverOutput?.tickets, Ticket);
  const completedIds = allTickets
    .filter((t) => !!ctx.latest(tables.report, `${t.id}:report`))
    .map((t) => t.id);

  const previousRun =
    completedIds.length > 0
      ? {
          summary: `Tickets completed: ${completedIds.join(", ")}`,
          ticketsCompleted: completedIds,
        }
      : null;

  return (
    <Task id="discover-codex" output={tables.discover} agent={codex}>
      <DiscoverPrompt previousRun={previousRun} />
    </Task>
  );
}
