
import { Task } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude } from "../agents";
import type { WorkflowCtx } from "./ctx-type";
import ReportPrompt from "../prompts/7_report.mdx";
import { reviewTable } from "./Review";
import type { ImplementRow, ReviewRow } from "./types";

export const reportTable = sqliteTable("report", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  ticketTitle: text("ticket_title").notNull(),
  status: text("status").notNull(),
  summary: text("summary").notNull(),
  filesChanged: integer("files_changed").notNull(),
  testsAdded: integer("tests_added").notNull(),
  reviewRounds: integer("review_rounds").notNull(),
  struggles: text("struggles", { mode: "json" }).$type<string[]>(),
  timeSpent: text("time_spent"),
  lessonsLearned: text("lessons_learned", { mode: "json" }).$type<string[]>(),
});

export const reportOutputSchema = z.object({
  ticketId: z.string().describe("The ticket this report covers"),
  ticketTitle: z.string().describe("Title of the ticket"),
  status: z.enum(["completed", "partial", "failed"]).describe("Final status"),
  summary: z.string().describe("Concise summary of what was implemented"),
  filesChanged: z.number().describe("Number of files changed"),
  testsAdded: z.number().describe("Number of tests added"),
  reviewRounds: z.number().describe("How many review rounds it took"),
  struggles: z.array(z.string()).nullable().describe("Any struggles or issues encountered"),
  timeSpent: z.string().nullable().describe("Approximate time spent"),
  lessonsLearned: z.array(z.string()).nullable().describe("Lessons for future tickets"),
});

interface ReportProps {
  ctx: WorkflowCtx;
  ticketId: string;
  ticketTitle: string;
  ticketDescription: string;
  latestImplement: ImplementRow | undefined;
}

function parseJson<T>(raw: string | null | undefined): T | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export function Report({
  ctx,
  ticketId,
  ticketTitle,
  ticketDescription,
  latestImplement,
}: ReportProps) {
  const claudeReview = ctx.outputMaybe(reviewTable, {
    nodeId: `${ticketId}:review-claude`,
  }) as ReviewRow | undefined;
  const codexReview = ctx.outputMaybe(reviewTable, {
    nodeId: `${ticketId}:review-codex`,
  }) as ReviewRow | undefined;
  const geminiReview = ctx.outputMaybe(reviewTable, {
    nodeId: `${ticketId}:review-gemini`,
  }) as ReviewRow | undefined;

  const allApproved =
    (claudeReview?.approved ?? 0) === 1 &&
    (codexReview?.approved ?? 0) === 1 &&
    (geminiReview?.approved ?? 0) === 1;

  return (
    <Task
      id={`${ticketId}:report`}
      output={reportTable}
      outputSchema={reportOutputSchema}
      agent={claude}
      skipIf={!allApproved}
    >
      {render(ReportPrompt, {
        ticketId,
        ticketTitle,
        ticketDescription,
        filesCreated: parseJson(latestImplement?.filesCreated) ?? [],
        filesModified: parseJson(latestImplement?.filesModified) ?? [],
        testsWritten: parseJson(latestImplement?.testsWritten) ?? [],
        docsUpdated: parseJson(latestImplement?.docsUpdated) ?? [],
        reportSchema: zodSchemaToJsonExample(reportOutputSchema),
      })}
    </Task>
  );
}
