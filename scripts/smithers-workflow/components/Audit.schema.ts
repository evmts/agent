import { z } from "zod";

const Feature = z.object({
  name: z.string().describe("Feature name from specs"),
  status: z.enum(["implemented", "partial", "not-started"]).describe("Current state"),
  details: z.string().describe("What exists or what's missing"),
  files: z.array(z.string()).describe("Relevant files found (or expected)"),
});

export const AuditOutput = z.object({
  implemented: z.array(Feature).describe("Features that are fully implemented"),
  partial: z.array(Feature).describe("Features that are partially implemented"),
  notStarted: z.array(Feature).describe("Features that have not been started"),
  summary: z.string().describe("High-level summary of project progress"),
});
export type AuditOutput = z.infer<typeof AuditOutput>;
