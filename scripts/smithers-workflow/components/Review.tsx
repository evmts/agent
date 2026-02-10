
import { Task, Parallel } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude, codex, gemini } from "../agents";
import type { WorkflowCtx } from "./ctx-type";
import ReviewPrompt from "../prompts/5_review.mdx";
import type { Ticket, ImplementRow, ValidateRow } from "./types";

export const reviewTable = sqliteTable("review", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  reviewer: text("reviewer").notNull(),
  approved: integer("approved").notNull(),
  issues: text("issues", { mode: "json" }).$type<any[]>().notNull(),
  testCoverage: text("test_coverage").notNull(),
  codeQuality: text("code_quality").notNull(),
  feedback: text("feedback").notNull(),
});

export const reviewOutputSchema = z.object({
  ticketId: z.string().describe("The ticket being reviewed"),
  reviewer: z.string().describe("Which agent reviewed (claude, codex, gemini)"),
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

function parseJson<T>(raw: string | null | undefined): T | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export function Review({
  ctx,
  ticketId,
  ticket,
  latestImplement,
  latestValidate,
  validationPassed,
}: ReviewProps) {
  const reviewSchema = zodSchemaToJsonExample(reviewOutputSchema);

  const reviewProps = {
    ticketId,
    ticketTitle: ticket.title,
    ticketDescription: ticket.description,
    acceptanceCriteria: ticket.acceptanceCriteria?.join("\n- ") ?? "",
    filesCreated: parseJson(latestImplement?.filesCreated) ?? [],
    filesModified: parseJson(latestImplement?.filesModified) ?? [],
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
    <Parallel skipIf={!validationPassed}>
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

      <Task
        id={`${ticketId}:review-gemini`}
        output={reviewTable}
        outputSchema={reviewOutputSchema}
        agent={gemini}
      >
        {render(ReviewPrompt, { ...reviewProps, reviewer: "gemini" })}
      </Task>
    </Parallel>
  );
}
