import { z } from 'zod';

/**
 * Username validation
 * - 3-39 characters
 * - alphanumeric, hyphens, underscores
 * - cannot start/end with hyphen
 */
export const usernameSchema = z
  .string()
  .min(3, 'Username must be at least 3 characters')
  .max(39, 'Username must be at most 39 characters')
  .regex(/^[a-zA-Z0-9]([a-zA-Z0-9-_]*[a-zA-Z0-9])?$/,
    'Username must start and end with alphanumeric, contain only letters, numbers, hyphens, and underscores');

/**
 * Email validation (optional for SIWE users)
 */
export const emailSchema = z
  .string()
  .email('Invalid email address')
  .max(255, 'Email must be at most 255 characters');

/**
 * Update profile
 */
export const updateProfileSchema = z.object({
  displayName: z.string().max(255).optional(),
  bio: z.string().max(2000).optional(),
  avatarUrl: z.string().url().max(2048).optional(),
  email: emailSchema.optional(),
});

// =============================================================================
// Session Schemas
// =============================================================================

export const createSessionSchema = z.object({
  directory: z.string().optional(),
  title: z.string().max(255).optional(),
  parentID: z.string().optional(),
  bypassMode: z.boolean().optional(),
  model: z.string().max(100).optional(),
  reasoningEffort: z.enum(['low', 'medium', 'high']).optional(),
  plugins: z.array(z.string()).optional(),
});

export const updateSessionSchema = z.object({
  title: z.string().max(255).optional(),
  archived: z.boolean().optional(),
  model: z.string().max(100).optional(),
  reasoningEffort: z.enum(['low', 'medium', 'high']).optional(),
});

export const forkSessionSchema = z.object({
  messageId: z.string().optional(),
  title: z.string().max(255).optional(),
});

export const revertSessionSchema = z.object({
  messageId: z.string().min(1, 'Message ID is required'),
  partId: z.string().optional(),
});

export const undoTurnsSchema = z.object({
  count: z.number().int().min(1).max(100).optional().default(1),
});

// =============================================================================
// SSH Key Schemas
// =============================================================================

const validKeyTypes = ['ssh-rsa', 'ssh-ed25519', 'ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384', 'ecdsa-sha2-nistp521'] as const;

export const createSshKeySchema = z.object({
  name: z.string().min(1, 'Name is required').max(255, 'Name must be at most 255 characters'),
  publicKey: z.string()
    .min(1, 'Public key is required')
    .refine(
      (key) => validKeyTypes.some(type => key.trim().startsWith(type)),
      'Invalid public key format. Must start with ssh-rsa, ssh-ed25519, or ecdsa-sha2-nistp*'
    ),
});

// =============================================================================
// Access Token Schemas
// =============================================================================

const VALID_SCOPES = ['repo', 'user', 'admin'] as const;

export const createAccessTokenSchema = z.object({
  name: z.string().min(1, 'Token name is required').max(255, 'Name must be at most 255 characters'),
  scopes: z.array(z.enum(VALID_SCOPES)).min(1, 'At least one scope is required'),
});

// =============================================================================
// Repository Schemas
// =============================================================================

export const updateTopicsSchema = z.object({
  topics: z.array(
    z.string()
      .max(35, 'Topic must be at most 35 characters')
      .regex(/^[a-z0-9-]+$/, 'Topic must contain only lowercase letters, numbers, and hyphens')
  ).max(20, 'Maximum 20 topics allowed'),
});

// =============================================================================
// Issue Schemas
// =============================================================================

export const authorSchema = z.object({
  id: z.number().int().positive(),
  username: z.string().min(1).max(39),
});

export const createIssueSchema = z.object({
  title: z.string().min(1, 'Title is required').max(500, 'Title must be at most 500 characters'),
  body: z.string().max(65535, 'Body must be at most 65535 characters').optional(),
  author: authorSchema,
  labels: z.array(z.string().max(50)).max(100).optional(),
  assignees: z.array(z.string()).max(10).optional(),
  milestone: z.number().int().positive().optional(),
});

export const updateIssueSchema = z.object({
  title: z.string().min(1).max(500).optional(),
  body: z.string().max(65535).optional(),
  labels: z.array(z.string().max(50)).max(100).optional(),
  assignees: z.array(z.string()).max(10).optional(),
  milestone: z.number().int().positive().nullable().optional(),
});

export const createCommentSchema = z.object({
  body: z.string().min(1, 'Comment body is required').max(65535, 'Comment must be at most 65535 characters'),
  author: authorSchema,
});

export const updateCommentSchema = z.object({
  body: z.string().min(1, 'Comment body is required').max(65535, 'Comment must be at most 65535 characters'),
});

export const createLabelSchema = z.object({
  name: z.string().min(1, 'Label name is required').max(50, 'Label name must be at most 50 characters'),
  color: z.string().regex(/^[0-9A-Fa-f]{6}$/, 'Color must be a valid 6-character hex code'),
  description: z.string().max(500).optional(),
});

export const updateLabelSchema = z.object({
  name: z.string().min(1).max(50).optional(),
  color: z.string().regex(/^[0-9A-Fa-f]{6}$/, 'Color must be a valid 6-character hex code').optional(),
  description: z.string().max(500).optional(),
});

export const addLabelsSchema = z.object({
  labels: z.array(z.string().max(50)).min(1, 'At least one label is required').max(100),
});

export const dependencySchema = z.object({
  dependsOn: z.number().int().positive('Issue number must be positive'),
});

export const addAssigneeSchema = z.object({
  username: z.string().min(1, 'Username is required').max(39),
});

export const addReactionSchema = z.object({
  user_id: z.number().int().positive('User ID is required'),
  emoji: z.string().min(1, 'Emoji is required').max(50),
});

// =============================================================================
// Common Parameter Schemas
// =============================================================================

export const paginationSchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).optional().default(50),
  offset: z.coerce.number().int().min(0).optional().default(0),
});

export const issueStateSchema = z.enum(['open', 'closed', 'all']).optional().default('open');
