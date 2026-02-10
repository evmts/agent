
import { Task } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude } from "../agents";
import ResearchPrompt from "../prompts/1_research.mdx";

export const researchTable = sqliteTable("research", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  referenceFiles: text("reference_files"),
  externalDocs: text("external_docs"),
  referenceCode: text("reference_code"),
  existingImplementation: text("existing_implementation"),
  contextFilePath: text("context_file_path").notNull(),
  summary: text("summary").notNull(),
});

export const researchOutputSchema = z.object({
  ticketId: z.string().describe("The ticket being researched"),
  referenceFiles: z.array(z.string()).describe("Files in the repo that are relevant"),
  externalDocs: z.array(z.object({
    url: z.string(),
    summary: z.string(),
  })).nullable().describe("External documentation found via web search"),
  referenceCode: z.array(z.object({
    source: z.string(),
    description: z.string(),
  })).nullable().describe("Reference code patterns found"),
  existingImplementation: z.array(z.string()).nullable().describe("Files that already partially implement this"),
  contextFilePath: z.string().describe("Path to the context file written for this ticket"),
  summary: z.string().describe("Summary of all research findings"),
});

interface ResearchProps {
  ticketId: string;
  ticketTitle: string;
  ticketDescription: string;
  acceptanceCriteria: string;
  testPlan: string;
}

export function Research({
  ticketId,
  ticketTitle,
  ticketDescription,
  acceptanceCriteria,
  testPlan,
}: ResearchProps) {
  return (
    <Task
      id={`${ticketId}:research`}
      output={researchTable}
      outputSchema={researchOutputSchema}
      agent={claude}
    >
      {render(ResearchPrompt, {
        ticketId,
        ticketTitle,
        ticketDescription,
        acceptanceCriteria,
        testPlan,
        researchSchema: zodSchemaToJsonExample(researchOutputSchema),
      })}
    </Task>
  );
}
