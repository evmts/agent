
import { Task } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude } from "../agents";
import DiscoverPrompt from "../prompts/0_discover.mdx";

export const discoverTable = sqliteTable("discover", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  tickets: text("tickets").notNull(),
  reasoning: text("reasoning").notNull(),
  completionEstimate: text("completion_estimate").notNull(),
});

export const ticketSchema = z.object({
  id: z.string().describe("Unique ticket identifier (e.g. 'T-001')"),
  title: z.string().describe("Short imperative title (e.g. 'Add SQLite WAL mode initialization')"),
  description: z.string().describe("Detailed description of what needs to be implemented"),
  scope: z.enum(["zig", "swift", "web", "e2e", "docs", "build"]).describe("Primary scope of the ticket"),
  endToEnd: z.boolean().describe("Whether this ticket touches multiple layers (Zig + Swift + Web)"),
  acceptanceCriteria: z.array(z.string()).describe("List of acceptance criteria"),
  testPlan: z.string().describe("How to validate: unit tests, e2e tests, manual verification"),
  estimatedComplexity: z.enum(["trivial", "small", "medium", "large"]).describe("Estimated complexity"),
  dependencies: z.array(z.string()).nullable().describe("IDs of tickets this depends on"),
});

export const discoverOutputSchema = z.object({
  tickets: z.array(ticketSchema).min(1).max(5).describe("The next 1-5 tickets to implement"),
  reasoning: z.string().describe("Why these tickets were chosen and in this order"),
  completionEstimate: z.string().describe("Overall progress estimate for the project"),
});

export function Discover() {
  return (
    <Task
      id="discover"
      output={discoverTable}
      outputSchema={discoverOutputSchema}
      agent={claude}
    >
      {render(DiscoverPrompt, {
        discoverSchema: zodSchemaToJsonExample(discoverOutputSchema),
      })}
    </Task>
  );
}
