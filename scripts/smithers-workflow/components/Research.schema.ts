import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";

export const researchTable = sqliteTable("research", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  referenceFiles: text("reference_files", { mode: "json" }).$type<string[]>(),
  externalDocs: text("external_docs", { mode: "json" }).$type<any[]>(),
  referenceCode: text("reference_code", { mode: "json" }).$type<any[]>(),
  existingImplementation: text("existing_implementation", { mode: "json" }).$type<string[]>(),
  contextFilePath: text("context_file_path"),
  summary: text("summary"),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

export const researchOutputSchema = z.object({
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
