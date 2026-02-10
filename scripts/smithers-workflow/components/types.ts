// Row types derived from Zod output schemas.
// These match the shapes that agents return and that Drizzle stores.
// Keep in sync with the outputSchema in each component file.
// Using z.infer creates circular imports, so we define them manually
// but ensure they match via the Zod schemas as source of truth.

export type Ticket = {
  id: string;
  title: string;
  description: string;
  scope: "zig" | "swift" | "web" | "e2e" | "docs" | "build";
  layers: ("zig" | "swift" | "web")[];
  acceptanceCriteria: string[];
  testPlan: string;
  estimatedComplexity: "trivial" | "small" | "medium" | "large";
  dependencies: string[] | null;
};

export type DiscoverRow = {
  tickets: Ticket[];
  reasoning: string;
  completionEstimate: string;
};

export type ResearchRow = {
  ticketId: string;
  referenceFiles: string[];
  externalDocs: { url: string; summary: string }[] | null;
  referenceCode: { source: string; description: string }[] | null;
  existingImplementation: string[] | null;
  contextFilePath: string;
  summary: string;
};

export type PlanRow = {
  ticketId: string;
  implementationSteps: { step: number; description: string; files: string[]; layer: string }[];
  filesToCreate: string[];
  filesToModify: string[];
  testsToWrite: { type: string; description: string; file: string }[];
  docsToUpdate: string[];
  risks: string[] | null;
  planFilePath: string;
};

export type ImplementRow = {
  ticketId: string;
  filesCreated: string[] | null;
  filesModified: string[] | null;
  commitMessages: string[];
  whatWasDone: string;
  testsWritten: string[];
  docsUpdated: string[];
  allTestsPassing: boolean;
  testOutput: string;
};

export type ValidateRow = {
  ticketId: string;
  allPassed: boolean;
  failingSummary: string | null;
  fullOutput: string;
};

export type ReviewRow = {
  ticketId: string;
  reviewer: string;
  approved: boolean;
  issues: { severity: string; file: string; line: number | null; description: string; suggestion: string | null }[];
  testCoverage: string;
  codeQuality: string;
  feedback: string;
};

export type ReviewFixRow = {
  ticketId: string;
  fixesMade: { issue: string; fix: string; file: string }[];
  falsePositiveComments: { file: string; line: number; issue: string; rationale: string }[] | null;
  commitMessages: string[];
  allIssuesResolved: boolean;
  summary: string;
};

export type ReportRow = {
  ticketId: string;
  ticketTitle: string;
  status: "completed" | "partial" | "failed";
  summary: string;
  filesChanged: number;
  testsAdded: number;
  reviewRounds: number;
  struggles: string[] | null;
  timeSpent: string | null;
  lessonsLearned: string[] | null;
};

export type OutputRow = {
  totalIterations: number;
  ticketsCompleted: string[];
  summary: string;
};
