import { Task } from "../smithers-audit";
import { claude } from "../agents";
import { tables } from "../smithers-audit";
import AuditPrompt from "./Audit.mdx";
export { AuditOutput } from "./Audit.schema";

export function Audit() {
  return (
    <Task id="audit" output={tables.audit} agent={claude}>
      <AuditPrompt />
    </Task>
  );
}
