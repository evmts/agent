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
