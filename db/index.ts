/**
 * TypeScript Database Access Layer
 *
 * Central module re-exporting all TypeScript DAOs and shared types.
 */

// =============================================================================
// Database Client
// =============================================================================

export { sql, sql as default } from './client';

// =============================================================================
// Domain DAOs
// =============================================================================

export * as auth from './auth';
export * as siwe from './siwe';
export * as sessions from './sessions';
export * as mentions from './mentions';
export * as issueReferences from './issue-references';
export * as landing from './landing';

// =============================================================================
// Re-exports for convenience
// =============================================================================

// Auth
export {
  getUserBySession,
  getUserByUsernameOrEmail,
  getUserById,
  getUserByUsername,
  getUserByEmail,
  getUserByActivationToken,
  createUser,
  createSession,
  deleteSession,
  deleteAllUserSessions,
  activateUser,
  createPasswordResetToken,
  getUserByResetToken,
  updateUserPassword,
  deletePasswordResetToken,
  updateUserProfile,
  type AuthUser,
  type CreateSessionResult,
} from './auth';

// SIWE
export {
  createNonce,
  validateNonce,
  markNonceUsed,
  getUserByWallet,
  getOrCreateUserByWallet,
  createAuthSession,
  updateLastLogin,
} from './siwe';

// Sessions
export {
  listSessions,
  createAgentSession,
} from './sessions';

// Mentions
export {
  saveMentionsForIssue,
  saveMentionsForComment,
  getMentionedUsersForIssue,
  getMentionsForUser,
} from './mentions';

// Issue References
export {
  trackIssueReferences,
  trackCommentReferences,
  getReferencingIssues,
  getReferencedIssues,
  deleteCommentReferences,
  deleteIssueReferences,
} from './issue-references';

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
  type LandingRequest,
  type LineComment,
  type LandingReview,
} from './landing';

// =============================================================================
// Utilities
// =============================================================================

// References
export {
  parseReferences,
  buildIssueUrl,
  formatReference,
  type IssueReference,
} from './references';

// Mentions
export {
  extractMentions,
  getUniqueMentionedUsernames,
  replaceMentionsWithLinks,
  hasMentions,
  type Mention,
} from './mentions-utils';
