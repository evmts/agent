
import { Task } from "smithers";
import { z } from "zod";
import { sqliteTable, text, integer, primaryKey } from "drizzle-orm/sqlite-core";
import { typedOutput, type WorkflowCtx } from "./ctx-type";

export const outputTable = sqliteTable("output", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  iteration: integer("iteration").notNull().default(0),
  ticketsCompleted: text("tickets_completed", { mode: "json" }).$type<string[]>(),
  totalIterations: integer("total_iterations"),
  summary: text("summary"),
}, (t) => [primaryKey({ columns: [t.runId, t.nodeId, t.iteration] })]);

export const passTrackerOutputSchema = z.object({
  totalIterations: z.number().describe("Total pass count"),
  ticketsCompleted: z.array(z.string()).describe("IDs of tickets completed this pass"),
  summary: z.string().describe("Summary of what was accomplished this pass"),
});

interface PassTrackerProps {
  ctx: WorkflowCtx;
  completedTicketIds: string[];
}

export function PassTracker({ ctx, completedTicketIds }: PassTrackerProps) {
  const prev = typedOutput<{ totalIterations?: number }>(ctx, outputTable, {
    nodeId: "pass-tracker",
  });

  const passCount = (prev?.totalIterations ?? 0) + 1;

  const payload = {
    totalIterations: passCount,
    ticketsCompleted: completedTicketIds,
    summary: `Pass ${passCount} complete. Tickets completed: ${completedTicketIds.join(", ") || "none"}.`,
  };

  return (
    <Task
      id="pass-tracker"
      output={outputTable}
      outputSchema={passTrackerOutputSchema}
    >
      {JSON.stringify(payload)}
    </Task>
  );
}
