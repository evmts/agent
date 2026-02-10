import type { SmithersCtx } from "smithers";
import type { SQLiteTable } from "drizzle-orm/sqlite-core";

export type WorkflowCtx = SmithersCtx<any>;

export function typedOutput<T>(
  ctx: WorkflowCtx,
  table: SQLiteTable,
  args: { nodeId: string },
): T | undefined {
  const rows = (ctx.outputs as any)(table) as any[] | undefined;
  if (!rows || rows.length === 0) return undefined;
  let latest: any | undefined;
  let latestIteration = -Infinity;
  for (const row of rows) {
    if (!row || row.nodeId !== args.nodeId) continue;
    const iterValue = row.iteration;
    const iter = Number.isFinite(Number(iterValue)) ? Number(iterValue) : 0;
    if (!latest || iter >= latestIteration) {
      latest = row;
      latestIteration = iter;
    }
  }
  return latest as T | undefined;
}
