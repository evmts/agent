
import { Task } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { codex } from "../agents";
import ImplementPrompt from "../prompts/3_implement.mdx";

export const implementTable = sqliteTable("implement", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  filesCreated: text("files_created"),
  filesModified: text("files_modified"),
  commitMessages: text("commit_messages").notNull(),
  whatWasDone: text("what_was_done").notNull(),
  testsWritten: text("tests_written").notNull(),
  docsUpdated: text("docs_updated").notNull(),
  allTestsPassing: integer("all_tests_passing").notNull(),
  testOutput: text("test_output").notNull(),
});

export const implementOutputSchema = z.object({
  ticketId: z.string().describe("The ticket being implemented"),
  filesCreated: z.array(z.string()).nullable().describe("Files created"),
  filesModified: z.array(z.string()).nullable().describe("Files modified"),
  commitMessages: z.array(z.string()).describe("Git commit messages made"),
  whatWasDone: z.string().describe("Detailed description of what was implemented"),
  testsWritten: z.array(z.string()).describe("Test files written"),
  docsUpdated: z.array(z.string()).describe("Documentation files updated"),
  allTestsPassing: z.boolean().describe("Whether all tests pass after implementation"),
  testOutput: z.string().describe("Output from running tests"),
});

interface ImplementProps {
  ticketId: string;
  ticketTitle: string;
  ticketDescription: string;
  acceptanceCriteria: string;
  contextFilePath: string;
  planSummary: string;
  approachDecisions: string;
  filesAffected: string;
}

export function Implement({
  ticketId,
  ticketTitle,
  ticketDescription,
  acceptanceCriteria,
  contextFilePath,
  planSummary,
  approachDecisions,
  filesAffected,
}: ImplementProps) {
  return (
    <Task
      id={`${ticketId}:implement`}
      output={implementTable}
      outputSchema={implementOutputSchema}
      agent={codex}
    >
      {render(ImplementPrompt, {
        ticketId,
        ticketTitle,
        ticketDescription,
        acceptanceCriteria,
        contextFilePath,
        planSummary,
        approachDecisions,
        filesAffected,
        implementSchema: zodSchemaToJsonExample(implementOutputSchema),
      })}
    </Task>
  );
}
