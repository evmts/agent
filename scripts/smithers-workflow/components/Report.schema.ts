import { z } from "zod";

export const ReportOutput = z.object({
  ticketTitle: z.string().describe("Title of the ticket"),
  status: z.enum(["completed", "partial", "failed"]).describe("Final status"),
  summary: z.string().describe("Concise summary of what was implemented"),
  filesChanged: z.number().describe("Number of files changed (pre-computed, echo back as-is)"),
  testsAdded: z.number().describe("Number of tests added (pre-computed, echo back as-is)"),
  reviewRounds: z.number().describe("How many review rounds it took (pre-computed, echo back as-is)"),
  struggles: z.array(z.string()).nullable().describe("Any struggles or issues encountered"),
  timeSpent: z.string().nullable().describe("Approximate time spent"),
  lessonsLearned: z.array(z.string()).nullable().describe("Lessons for future tickets"),
});
export type ReportOutput = z.infer<typeof ReportOutput>;
