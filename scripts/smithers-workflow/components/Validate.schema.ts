import { z } from "zod";

export const ValidateOutput = z.object({
  allPassed: z.boolean().describe("Whether `zig build all` exited with status 0"),
  failingSummary: z.string().nullable().describe("Summary of what failed and why (null if all passed)"),
  fullOutput: z.string().describe("Full output from `zig build all`"),
});
export type ValidateOutput = z.infer<typeof ValidateOutput>;
