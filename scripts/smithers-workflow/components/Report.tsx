
import { Task } from "smithers";
import { z } from "zod";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude } from "../agents";
import { typedOutput, iterationCount, type WorkflowCtx } from "./ctx-type";
import ReportPrompt from "../prompts/7_report.mdx";
import { reviewTable } from "./Review.schema";
import { validateTable } from "./Validate.schema";
import { implementTable } from "./Implement.schema";
import { coerceJsonArray } from "../lib/coerce";
import type { ImplementRow, ValidateRow, ReviewRow } from "./types";
export { reportTable, reportOutputSchema } from "./Report.schema";
import { reportTable, reportOutputSchema } from "./Report.schema";

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

  // Compute deterministic metrics from stored artifacts
  const filesCreated = latestImplement?.filesCreated ?? [];
  const filesModified = latestImplement?.filesModified ?? [];
  const filesChanged = filesCreated.length + filesModified.length;
  const testsAdded = latestImplement?.testsWritten?.length ?? 0;
  const reviewRounds = Math.max(
    iterationCount(ctx, reviewTable, { nodeId: `${ticketId}:review-claude` }),
    iterationCount(ctx, implementTable, { nodeId: `${ticketId}:implement` }),
    1,
  );

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
        filesCreated,
        filesModified,
        commitMessages: latestImplement?.commitMessages ?? [],
        testsWritten: latestImplement?.testsWritten ?? [],
        docsUpdated: latestImplement?.docsUpdated ?? [],
        allTestsPassing: latestImplement?.allTestsPassing ?? false,
        failingSummary: latestValidate?.failingSummary ?? null,
        filesChanged,
        testsAdded,
        reviewRounds,
        reviewIssues: reviewIssuesSummary,
        reportSchema: zodSchemaToJsonExample(reportOutputSchema),
      })}
    </Task>
  );
}
