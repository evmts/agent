import type { SmithersCtx } from "smithers";

// Type alias for workflow context (avoids JSX parsing issues with generics)
export type WorkflowCtx = SmithersCtx<any>;
