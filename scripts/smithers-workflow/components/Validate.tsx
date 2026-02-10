
import { Task } from "smithers";
import { render } from "../lib/render";
import { zodSchemaToJsonExample } from "../lib/zod-to-example";
import { codex } from "../agents";
import ValidatePrompt from "../prompts/4_validate.mdx";
export { validateTable, validateOutputSchema } from "./Validate.schema";
import { validateTable, validateOutputSchema } from "./Validate.schema";
import type { ImplementRow } from "./types";

interface ValidateProps {
  ticketId: string;
  ticketTitle: string;
  implementOutput: ImplementRow | undefined;
}

export function Validate({
  ticketId,
  ticketTitle,
  implementOutput,
}: ValidateProps) {
  return (
    <Task
      id={`${ticketId}:validate`}
      output={validateTable}
      outputSchema={validateOutputSchema}
      agent={codex}
    >
      {render(ValidatePrompt, {
        ticketId,
        ticketTitle,
        implementOutput,
        validateSchema: zodSchemaToJsonExample(validateOutputSchema),
      })}
    </Task>
  );
}
