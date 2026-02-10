
import { Task } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude } from "../agents";
import PlanPrompt from "../prompts/2_plan.mdx";

export const planTable = sqliteTable("plan", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  implementationSteps: text("implementation_steps", { mode: "json" }).$type<any[]>(),
  filesToCreate: text("files_to_create", { mode: "json" }).$type<string[]>(),
  filesToModify: text("files_to_modify", { mode: "json" }).$type<string[]>(),
  testsToWrite: text("tests_to_write", { mode: "json" }).$type<any[]>(),
  docsToUpdate: text("docs_to_update", { mode: "json" }).$type<string[]>(),
  risks: text("risks", { mode: "json" }).$type<string[]>(),
  planFilePath: text("plan_file_path"),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

export const planOutputSchema = z.object({
  ticketId: z.string().describe("The ticket being planned"),
  implementationSteps: z.array(z.object({
    step: z.number(),
    description: z.string(),
    files: z.array(z.string()),
    layer: z.enum(["zig", "swift", "web", "docs", "build", "test"]),
  })).describe("Ordered implementation steps"),
  filesToCreate: z.array(z.string()).describe("New files that need to be created"),
  filesToModify: z.array(z.string()).describe("Existing files that need modification"),
  testsToWrite: z.array(z.object({
    type: z.enum(["unit", "e2e", "integration"]),
    description: z.string(),
    file: z.string(),
  })).describe("Tests to write"),
  docsToUpdate: z.array(z.string()).describe("Documentation files to create or update"),
  risks: z.array(z.string()).nullable().describe("Potential risks or blockers"),
  planFilePath: z.string().describe("Path to the plan file written"),
});

interface PlanProps {
  ticketId: string;
  ticketTitle: string;
  ticketDescription: string;
  acceptanceCriteria: string;
  contextFilePath: string;
  researchSummary: string;
}

export function Plan({
  ticketId,
  ticketTitle,
  ticketDescription,
  acceptanceCriteria,
  contextFilePath,
  researchSummary,
}: PlanProps) {
  return (
    <Task
      id={`${ticketId}:plan`}
      output={planTable}
      outputSchema={planOutputSchema}
      agent={claude}
    >
      {render(PlanPrompt, {
        ticketId,
        ticketTitle,
        ticketDescription,
        acceptanceCriteria,
        contextFilePath,
        researchSummary,
        planSchema: zodSchemaToJsonExample(planOutputSchema),
      })}
    </Task>
  );
}
