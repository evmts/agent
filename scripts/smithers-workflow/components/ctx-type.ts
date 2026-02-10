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

/** Count distinct iterations for a given nodeId prefix (e.g. "ticket:review-claude"). */
export function iterationCount(
  ctx: WorkflowCtx,
  table: SQLiteTable,
  args: { nodeId: string },
): number {
  const rows = (ctx.outputs as any)(table) as any[] | undefined;
  if (!rows || rows.length === 0) return 0;
  const seen = new Set<number>();
  for (const row of rows) {
    if (!row || row.nodeId !== args.nodeId) continue;
    const iter = Number.isFinite(Number(row.iteration)) ? Number(row.iteration) : 0;
    seen.add(iter);
  }
  return seen.size;
}
