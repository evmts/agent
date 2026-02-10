
import { Task } from "smithers";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { codex } from "../agents";
import ImplementPrompt from "../prompts/3_implement.mdx";
export { implementTable, implementOutputSchema } from "./Implement.schema";
import { implementTable, implementOutputSchema } from "./Implement.schema";

interface ImplementProps {
  ticketId: string;
  ticketTitle: string;
  ticketDescription: string;
  acceptanceCriteria: string;
  contextFilePath: string;
  planFilePath: string;
  previousImplementation: {
    whatWasDone: string | null;
    testOutput: string | null;
  } | null;
  reviewFixes: string | null;
  validationFeedback: {
    allPassed: boolean | null;
    failingSummary: string | null;
  } | null;
}

export function Implement({
  ticketId,
  ticketTitle,
  ticketDescription,
  acceptanceCriteria,
  contextFilePath,
  planFilePath,
  previousImplementation,
  reviewFixes,
  validationFeedback,
}: ImplementProps) {
  return (
    <Task
      id={`${ticketId}:implement`}
      output={implementTable}
      outputSchema={implementOutputSchema}
      agent={codex}
    >
      {render(ImplementPrompt, {
        ticketId,
        ticketTitle,
        ticketDescription,
        acceptanceCriteria,
        contextFilePath,
        planFilePath,
        previousImplementation,
        reviewFixes,
        validationFeedback,
        implementSchema: zodSchemaToJsonExample(implementOutputSchema),
      })}
    </Task>
  );
}
