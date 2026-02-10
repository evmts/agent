
import { Task } from "smithers";
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";
import type { WorkflowCtx } from "./ctx-type";
import type { OutputRow } from "./types";

export const outputTable = sqliteTable("output", {
  runId: text("run_id").notNull(),
  nodeId: text("node_id").notNull(),
  ticketsCompleted: text("tickets_completed", { mode: "json" }).$type<string[]>(),
  totalIterations: integer("total_iterations").notNull(),
  summary: text("summary").notNull(),
});

interface PassTrackerProps {
  ctx: WorkflowCtx;
}

export function PassTracker({ ctx }: PassTrackerProps) {
  const passTracker = ctx.outputMaybe(outputTable, {
    nodeId: "pass-tracker",
  }) as OutputRow | undefined;

  const passCount = passTracker?.passCount ?? 0;

  return (
    <Task id="pass-tracker" output={outputTable}>
      {`Pass ${passCount + 1} complete. Ready for next discovery cycle.

Output JSON:
\`\`\`json
{"passCount": ${passCount + 1}, "timestamp": "${new Date().toISOString()}"}
\`\`\`
`}
    </Task>
  );
}
