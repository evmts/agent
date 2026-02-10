import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";

export const implementTable = sqliteTable("implement", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  filesCreated: text("files_created", { mode: "json" }).$type<string[]>(),
  filesModified: text("files_modified", { mode: "json" }).$type<string[]>(),
  commitMessages: text("commit_messages", { mode: "json" }).$type<string[]>(),
  whatWasDone: text("what_was_done"),
  testsWritten: text("tests_written", { mode: "json" }).$type<string[]>(),
  docsUpdated: text("docs_updated", { mode: "json" }).$type<string[]>(),
  allTestsPassing: integer("all_tests_passing", { mode: "boolean" }),
  testOutput: text("test_output"),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

export const implementOutputSchema = z.object({
  ticketId: z.string().default("unknown").describe("The ticket being implemented"),
  filesCreated: z.array(z.string()).nullable().describe("Files created"),
  filesModified: z.array(z.string()).nullable().describe("Files modified"),
  commitMessages: z.array(z.string()).describe("Git commit messages made"),
  whatWasDone: z.string().describe("Detailed description of what was implemented"),
  testsWritten: z.array(z.string()).describe("Test files written"),
  docsUpdated: z.array(z.string()).describe("Documentation files updated"),
  allTestsPassing: z.boolean().describe("Whether all tests pass after implementation"),
  testOutput: z.string().describe("Output from running tests"),
});
