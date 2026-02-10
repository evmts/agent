
import { Task } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude } from "../agents";
import { typedOutput, type WorkflowCtx } from "./ctx-type";
import ReportPrompt from "../prompts/7_report.mdx";
import { reviewTable } from "./Review";
import { validateTable } from "./Validate";
import { coerceJsonArray } from "../lib/coerce";
import type { ImplementRow, ValidateRow, ReviewRow } from "./types";

export const reportTable = sqliteTable("report", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketId: text("ticket_id").notNull(),
  ticketTitle: text("ticket_title"),
  status: text("status"),
  summary: text("summary"),
  filesChanged: integer("files_changed"),
  testsAdded: integer("tests_added"),
  reviewRounds: integer("review_rounds"),
  struggles: text("struggles", { mode: "json" }).$type<string[]>(),
  timeSpent: text("time_spent"),
  lessonsLearned: text("lessons_learned", { mode: "json" }).$type<string[]>(),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

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
  loopExhausted: boolean;
}

export function Report({
  ctx,
  ticketId,
  ticketTitle,
  ticketDescription,
  latestImplement,
  loopExhausted,
}: ReportProps) {
  const claudeReview = typedOutput<ReviewRow>(ctx, reviewTable, {
    nodeId: `${ticketId}:review-claude`,
  });
  const codexReview = typedOutput<ReviewRow>(ctx, reviewTable, {
    nodeId: `${ticketId}:review-codex`,
  });

  const latestValidate = typedOutput<ValidateRow>(ctx, validateTable, {
    nodeId: `${ticketId}:validate`,
  });

  const allApproved = !!claudeReview?.approved && !!codexReview?.approved;

  // Collect all review issues for the report
  const issueItem = z.object({
    severity: z.string(),
    file: z.string(),
    line: z.number().nullable(),
    description: z.string(),
    suggestion: z.string().nullable(),
  });
  const allIssues = [
    ...coerceJsonArray(claudeReview?.issues, issueItem),
    ...coerceJsonArray(codexReview?.issues, issueItem),
  ];

  const reviewIssuesSummary =
    allIssues.length > 0 ? JSON.stringify(allIssues, null, 2) : null;

  // Estimate review rounds from iteration count
  const reviewRounds = 1;

  return (
    <Task
      id={`${ticketId}:report`}
      output={reportTable}
      outputSchema={reportOutputSchema}
      agent={claude}
      skipIf={!allApproved && !loopExhausted}
    >
      {render(ReportPrompt, {
        ticketId,
        ticketTitle,
        ticketDescription,
        whatWasDone: latestImplement?.whatWasDone ?? "No implementation data available",
        filesCreated: latestImplement?.filesCreated ?? [],
        filesModified: latestImplement?.filesModified ?? [],
        commitMessages: latestImplement?.commitMessages ?? [],
        testsWritten: latestImplement?.testsWritten ?? [],
        docsUpdated: latestImplement?.docsUpdated ?? [],
        allTestsPassing: latestImplement?.allTestsPassing ?? false,
        failingSummary: latestValidate?.failingSummary ?? null,
        reviewRounds,
        reviewIssues: reviewIssuesSummary,
        reportSchema: zodSchemaToJsonExample(reportOutputSchema),
      })}
    </Task>
  );
}
