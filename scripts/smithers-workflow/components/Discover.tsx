
import { Task, Parallel } from "smithers";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude, codex } from "../agents";
import DiscoverPrompt from "../prompts/0_discover.mdx";
export { discoverTable, ticketSchema, discoverOutputSchema } from "./Discover.schema";
import { discoverTable, discoverOutputSchema } from "./Discover.schema";

interface DiscoverProps {
  previousRun?: { summary: string; ticketsCompleted: string[] } | null;
}

export function Discover({ previousRun }: DiscoverProps) {
  const prompt = render(DiscoverPrompt, {
    previousRun,
    discoverSchema: zodSchemaToJsonExample(discoverOutputSchema),
  });

  return (
    <Parallel>
      <Task
        id="discover-claude"
        output={discoverTable}
        outputSchema={discoverOutputSchema}
        agent={claude}
      >
        {prompt}
      </Task>
      <Task
        id="discover-codex"
        output={discoverTable}
        outputSchema={discoverOutputSchema}
        agent={codex}
      >
        {prompt}
      </Task>
    </Parallel>
  );
}
