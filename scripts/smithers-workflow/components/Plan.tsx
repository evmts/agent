
import { Task } from "smithers";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude } from "../agents";
import PlanPrompt from "../prompts/2_plan.mdx";
export { planTable, planOutputSchema } from "./Plan.schema";
import { planTable, planOutputSchema } from "./Plan.schema";

interface PlanProps {
  ticketId: string;
  ticketTitle: string;
  ticketDescription: string;
  acceptanceCriteria: string;
  contextFilePath: string;
  researchSummary: string;
}

export function Plan({
  ticketId,
  ticketTitle,
  ticketDescription,
  acceptanceCriteria,
  contextFilePath,
  researchSummary,
}: PlanProps) {
  return (
    <Task
      id={`${ticketId}:plan`}
      output={planTable}
      outputSchema={planOutputSchema}
      agent={claude}
    >
      {render(PlanPrompt, {
        ticketId,
        ticketTitle,
        ticketDescription,
        acceptanceCriteria,
        contextFilePath,
        researchSummary,
        planSchema: zodSchemaToJsonExample(planOutputSchema),
      })}
    </Task>
  );
}
