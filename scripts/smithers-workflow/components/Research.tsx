
import { Task } from "smithers";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { claude } from "../agents";
import ResearchPrompt from "../prompts/1_research.mdx";
export { researchTable, researchOutputSchema } from "./Research.schema";
import { researchTable, researchOutputSchema } from "./Research.schema";

interface ResearchProps {
  ticketId: string;
  ticketTitle: string;
  ticketDescription: string;
  acceptanceCriteria: string;
  testPlan: string;
}

export function Research({
  ticketId,
  ticketTitle,
  ticketDescription,
  acceptanceCriteria,
  testPlan,
}: ResearchProps) {
  return (
    <Task
      id={`${ticketId}:research`}
      output={researchTable}
      outputSchema={researchOutputSchema}
      agent={claude}
    >
      {render(ResearchPrompt, {
        ticketId,
        ticketTitle,
        ticketDescription,
        acceptanceCriteria,
        testPlan,
        researchSchema: zodSchemaToJsonExample(researchOutputSchema),
      })}
    </Task>
  );
}
