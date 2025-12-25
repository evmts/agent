/**
 * TypeScript Database Access Layer
 *
 * Central module re-exporting all TypeScript DAOs and shared types.
 *
 * IMPORTANT: The `sql` template tag is intentionally NOT exported here.
 * All database queries should go through DAOs, not raw SQL in UI code.
 * DAOs import sql from './client' internally.
 */

// =============================================================================
// Domain DAOs
// =============================================================================

export * as siwe from './daos/siwe';
export * as sessions from './daos/sessions';
export * as mentions from './daos/mentions';
export * as issueReferences from './daos/issue-references';
export * as issueEvents from './daos/issue-events';
export * as landing from './daos/landing';
export * as repositories from './daos/repositories';
export * as users from './daos/users';
export * as stars from './daos/stars';
export * as watchers from './daos/watchers';
export * as milestones from './daos/milestones';
export * as issues from './daos/issues';
export * as workflows from './daos/workflows';
export * as sshKeys from './daos/ssh-keys';
export * as tokens from './daos/tokens';
export * as reactions from './daos/reactions';

// =============================================================================
// Re-exports for convenience
// =============================================================================

// SIWE
export {
  createNonce,
  validateNonce,
  markNonceUsed,
  getUserByWallet,
  getOrCreateUserByWallet,
  createAuthSession,
  updateLastLogin,
} from './daos/siwe';

// Sessions
export {
  listSessions,
  createAgentSession,
} from './daos/sessions';

// Mentions
export {
  saveMentionsForIssue,
  saveMentionsForComment,
  getMentionedUsersForIssue,
  getMentionsForUser,
} from './daos/mentions';

// Issue References
export {
  trackIssueReferences,
  trackCommentReferences,
  getReferencingIssues,
  getReferencedIssues,
  deleteCommentReferences,
  deleteIssueReferences,
} from './daos/issue-references';

// Issue Events
export {
  getEventsForIssue,
  recordEvent as recordIssueEvent,
  type IssueEvent,
  type IssueEventType,
} from './daos/issue-events';

// Landing
export {
  list as listLandingRequests,
  getById as getLandingById,
  findByChangeId as findLandingByChangeId,
  count as countLandingRequests,
  create as createLandingRequest,
  updateStatus as updateLandingStatus,
  updateConflicts as updateLandingConflicts,
  markLanded,
  getLineComments,
  createLineComment,
  updateLineComment,
  deleteLineComment,
  getReviews as getLandingReviews,
  createReview as createLandingReview,
  listWithAuthors,
  getCommitStatuses,
  getCommitStatusStates,
  type LandingRequest,
  type LandingRequestWithAuthor,
  type LineComment,
  type LandingReview,
  type CommitStatus,
} from './daos/landing';

