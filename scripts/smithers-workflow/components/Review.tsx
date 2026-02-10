
import { Task, Parallel } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude, codex } from "../agents";
import type { WorkflowCtx } from "./ctx-type";
import ReviewPrompt from "../prompts/5_review.mdx";
import type { Ticket, ImplementRow, ValidateRow } from "./types";

export const reviewTable = sqliteTable("review", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  reviewer: text("reviewer"),
  approved: integer("approved", { mode: "boolean" }),
  issues: text("issues", { mode: "json" }).$type<any[]>(),
  testCoverage: text("test_coverage"),
  codeQuality: text("code_quality"),
  feedback: text("feedback"),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

export const reviewOutputSchema = z.object({
  ticketId: z.string().describe("The ticket being reviewed"),
  reviewer: z.string().describe("Which agent reviewed (claude, codex)"),
  approved: z.boolean().describe("Whether the reviewer approves (LGTM)"),
  issues: z.array(z.object({
    severity: z.enum(["critical", "major", "minor", "nit"]),
    file: z.string(),
    line: z.number().nullable(),
    description: z.string(),
    suggestion: z.string().nullable(),
  })).describe("Issues found during review"),
  testCoverage: z.enum(["excellent", "good", "insufficient", "missing"]).describe("Test coverage assessment"),
  codeQuality: z.enum(["excellent", "good", "needs-work", "poor"]).describe("Code quality assessment"),
  feedback: z.string().describe("Overall review feedback"),
});

interface ReviewProps {
  ctx: WorkflowCtx;
  ticketId: string;
  ticket: Ticket;
  latestImplement: ImplementRow | undefined;
  latestValidate: ValidateRow | undefined;
  validationPassed: boolean;
}


export function Review({
  ctx,
  ticketId,
  ticket,
  latestImplement,
  latestValidate,
  validationPassed,
}: ReviewProps) {
  if (!validationPassed) {
    return null;
  }
  const reviewSchema = zodSchemaToJsonExample(reviewOutputSchema);

  const reviewProps = {
    ticketId,
    ticketTitle: ticket.title,
    ticketDescription: ticket.description,
    acceptanceCriteria: ticket.acceptanceCriteria?.join("\n- ") ?? "",
    filesCreated: latestImplement?.filesCreated ?? [],
    filesModified: latestImplement?.filesModified ?? [],
    zigTests: latestValidate?.zigTestsPassed ? "PASS" : "FAIL",
    playwrightTests:
      latestValidate?.playwrightTestsPassed == null
        ? "N/A"
        : latestValidate.playwrightTestsPassed
          ? "PASS"
          : "FAIL",
    buildStatus: latestValidate?.buildSucceeded ? "PASS" : "FAIL",
    failingSummary: latestValidate?.failingSummary ?? null,
    reviewSchema,
  };

  return (
    <Parallel>
      <Task
        id={`${ticketId}:review-claude`}
        output={reviewTable}
        outputSchema={reviewOutputSchema}
        agent={claude}
      >
        {render(ReviewPrompt, { ...reviewProps, reviewer: "claude" })}
      </Task>

      <Task
        id={`${ticketId}:review-codex`}
        output={reviewTable}
        outputSchema={reviewOutputSchema}
        agent={codex}
      >
        {render(ReviewPrompt, { ...reviewProps, reviewer: "codex" })}
      </Task>
    </Parallel>
  );
}
