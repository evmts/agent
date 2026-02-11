import { createSmithers } from "smithers";
import { DiscoverOutput } from "./components/Discover.schema";
import { ResearchOutput } from "./components/Research.schema";
import { PlanOutput } from "./components/Plan.schema";
import { ImplementOutput } from "./components/Implement.schema";
import { ValidateOutput } from "./components/Validate.schema";
import { ReviewOutput } from "./components/Review.schema";
import { ReviewFixOutput } from "./components/ReviewFix.schema";
import { ReportOutput } from "./components/Report.schema";

export const { Workflow, Task, useCtx, smithers, tables } = createSmithers({
  discover: DiscoverOutput,
  research: ResearchOutput,
  plan: PlanOutput,
  implement: ImplementOutput,
  validate: ValidateOutput,
  review: ReviewOutput,
  reviewFix: ReviewFixOutput,
  report: ReportOutput,
}, { dbPath: "./smithers-v2.db" });
