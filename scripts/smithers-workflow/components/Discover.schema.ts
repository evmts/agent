import { z } from "zod";

export const Ticket = z.object({
  id: z.string().describe("Unique slug identifier derived from the title (e.g. 'sqlite-wal-init', 'chat-sidebar-mode-bar'). Must be lowercase kebab-case. NEVER use numeric IDs like T-001."),
  title: z.string().describe("Short imperative title (e.g. 'Add SQLite WAL mode initialization')"),
  description: z.string().describe("Detailed description of what needs to be implemented"),
  scope: z.enum(["zig", "swift", "web", "e2e", "docs", "build"]).describe("Primary scope of the ticket (use 'e2e' when spanning Zig+Swift+Web)"),
  layers: z.array(z.string()).describe("Which layers this ticket touches (e.g. ['zig'] for infra, ['zig','swift','web'] for e2e)"),
  acceptanceCriteria: z.array(z.string()).describe("List of acceptance criteria"),
  testPlan: z.string().describe("How to validate: unit tests, e2e tests, manual verification"),
  estimatedComplexity: z.enum(["trivial", "small", "medium", "large"]).describe("Estimated complexity"),
  dependencies: z.array(z.string()).nullable().describe("IDs of tickets this depends on"),
});
export type Ticket = z.infer<typeof Ticket>;

export const DiscoverOutput = z.object({
  tickets: z.array(Ticket).max(5).describe("The next 0-5 tickets to implement"),
  reasoning: z.string().describe("Why these tickets were chosen and in this order"),
  completionEstimate: z.string().describe("Overall progress estimate for the project"),
});
export type DiscoverOutput = z.infer<typeof DiscoverOutput>;
