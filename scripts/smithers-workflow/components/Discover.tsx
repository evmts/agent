
import { Task } from "smithers";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { codex } from "../agents";
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
    <Task
      id="discover-codex"
      output={discoverTable}
      outputSchema={discoverOutputSchema}
      agent={codex}
    >
      {prompt}
    </Task>
  );
}
