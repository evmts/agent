import { z } from "zod";

export const PlanOutput = z.object({
  implementationSteps: z.array(z.object({
    step: z.number(),
    description: z.string(),
    files: z.array(z.string()),
    layer: z.enum(["zig", "swift", "web", "docs", "build", "test"]),
  })).describe("Ordered implementation steps"),
  filesToCreate: z.array(z.string()).describe("New files that need to be created"),
  filesToModify: z.array(z.string()).describe("Existing files that need modification"),
  testsToWrite: z.array(z.object({
    type: z.enum(["unit", "e2e", "integration"]),
    description: z.string(),
    file: z.string(),
  })).describe("Tests to write"),
  docsToUpdate: z.array(z.string()).describe("Documentation files to create or update"),
  risks: z.array(z.string()).nullable().describe("Potential risks or blockers"),
  planFilePath: z.string().describe("Path to the plan file written"),
});
export type PlanOutput = z.infer<typeof PlanOutput>;
