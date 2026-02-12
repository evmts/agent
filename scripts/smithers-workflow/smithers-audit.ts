import { createSmithers } from "smithers";
import { AuditOutput } from "./components/Audit.schema";

export const { Workflow, Task, useCtx, smithers, tables } = createSmithers({
  audit: AuditOutput,
}, { dbPath: "./smithers-audit.db" });
