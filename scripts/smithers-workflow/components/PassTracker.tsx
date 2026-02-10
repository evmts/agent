
import { Task } from "smithers";
import { typedOutput, type WorkflowCtx } from "./ctx-type";
export { outputTable, passTrackerOutputSchema } from "./PassTracker.schema";
import { outputTable, passTrackerOutputSchema } from "./PassTracker.schema";

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
