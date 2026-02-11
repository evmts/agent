import { z } from "zod";

export const ResearchOutput = z.object({
  referenceFiles: z.array(z.string()).describe("Files in the repo that are relevant"),
  externalDocs: z.array(z.object({
    url: z.string(),
    summary: z.string(),
  })).nullable().describe("External documentation found via web search"),
  referenceCode: z.array(z.object({
    source: z.string(),
    description: z.string(),
  })).nullable().describe("Reference code patterns found"),
  existingImplementation: z.array(z.string()).nullable().describe("Files that already partially implement this"),
  contextFilePath: z.string().describe("Path to the context file written for this ticket"),
  summary: z.string().describe("Summary of all research findings"),
});
export type ResearchOutput = z.infer<typeof ResearchOutput>;
