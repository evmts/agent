// Type aliases for DB row outputs (matches Zod schema shapes)

export type DiscoverRow = {
  tickets: string; // JSON array
  reasoning: string;
  completionEstimate: string;
};

export type ResearchRow = {
  ticketId: string;
  referenceFiles: string; // JSON
  externalDocs: string; // JSON
  referenceCode: string; // JSON
  existingImplementation: string; // JSON
  contextFilePath: string;
  summary: string;
};

export type PlanRow = {
  ticketId: string;
  implementationSteps: string; // JSON
  filesToCreate: string; // JSON
  filesToModify: string; // JSON
  testsToWrite: string; // JSON
  docsToUpdate: string; // JSON
  risks: string; // JSON
  planFilePath: string;
};

export type ImplementRow = {
  ticketId: string;
  filesCreated: string; // JSON
  filesModified: string; // JSON
  commitMessages: string; // JSON
  whatWasDone: string;
  testsWritten: string; // JSON
  docsUpdated: string; // JSON
  allTestsPassing: number;
  testOutput: string;
};

export type ValidateRow = {
  ticketId: string;
  zigTestsPassed: number;
  playwrightTestsPassed: number | null;
  buildSucceeded: number;
  lintPassed: number;
  allPassed: number;
  failingSummary: string | null;
  fullOutput: string;
};

export type ReviewRow = {
  ticketId: string;
  reviewer: string;
  approved: number;
  issues: string; // JSON
  testCoverage: string;
  codeQuality: string;
  feedback: string;
};

export type ReviewFixRow = {
  ticketId: string;
  fixesMade: string; // JSON
  falsePositiveComments: string; // JSON
  commitMessages: string; // JSON
  allIssuesResolved: number;
  summary: string;
};

export type ReportRow = {
  ticketId: string;
  ticketTitle: string;
  status: string;
  summary: string;
  filesChanged: number;
  testsAdded: number;
  reviewRounds: number;
  struggles: string; // JSON
  timeSpent: string | null;
  lessonsLearned: string; // JSON
};

export type OutputRow = {
  passCount?: number;
  ticketsCompleted?: string; // JSON
  totalIterations?: number;
  summary?: string;
  timestamp?: string;
};

export type Ticket = {
  id: string;
  title: string;
  description: string;
  scope: string;
  endToEnd: boolean;
  acceptanceCriteria: string[];
  testPlan: string;
  estimatedComplexity: string;
  dependencies: string[] | null;
};
