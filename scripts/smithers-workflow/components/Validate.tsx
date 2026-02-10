
import { Task } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { codex } from "../agents";
import ValidatePrompt from "../prompts/4_validate.mdx";
import type { ImplementRow } from "./types";

export const validateTable = sqliteTable("validate", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  zigTestsPassed: integer("zig_tests_passed").notNull(),
  playwrightTestsPassed: integer("playwright_tests_passed"),
  buildSucceeded: integer("build_succeeded").notNull(),
  lintPassed: integer("lint_passed").notNull(),
  allPassed: integer("all_passed").notNull(),
  failingSummary: text("failing_summary"),
  fullOutput: text("full_output").notNull(),
});

export const validateOutputSchema = z.object({
  ticketId: z.string().describe("The ticket being validated"),
  zigTestsPassed: z.boolean().describe("Whether Zig unit tests pass"),
  playwrightTestsPassed: z.boolean().nullable().describe("Whether Playwright e2e tests pass (null if N/A)"),
  buildSucceeded: z.boolean().describe("Whether zig build succeeds"),
  lintPassed: z.boolean().describe("Whether linting passes"),
  allPassed: z.boolean().describe("Whether everything passes"),
  failingSummary: z.string().nullable().describe("Summary of failures if any"),
  fullOutput: z.string().describe("Full test/build output"),
});

interface ValidateProps {
  ticketId: string;
  ticketTitle: string;
  implementOutput: ImplementRow | undefined;
}

export function Validate({
  ticketId,
  ticketTitle,
  implementOutput,
}: ValidateProps) {
  return (
    <Task
      id={`${ticketId}:validate`}
      output={validateTable}
      outputSchema={validateOutputSchema}
      agent={codex}
    >
      {render(ValidatePrompt, {
        ticketId,
        ticketTitle,
        implementOutput,
        validateSchema: zodSchemaToJsonExample(validateOutputSchema),
      })}
    </Task>
  );
}
