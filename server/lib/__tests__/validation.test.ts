/**
 * Tests for validation schemas.
 */

import { describe, test, expect } from 'bun:test';
import { z } from 'zod';
import {
  usernameSchema,
  emailSchema,
  updateProfileSchema,
} from '../validation';

describe('usernameSchema', () => {
  describe('valid usernames', () => {
    test('accepts 3 character username', () => {
      const result = usernameSchema.safeParse('abc');
      expect(result.success).toBe(true);
    });

    test('accepts 39 character username', () => {
      const username = 'a'.repeat(39);
      const result = usernameSchema.safeParse(username);
      expect(result.success).toBe(true);
    });

    test('accepts alphanumeric characters', () => {
      const validUsernames = [
        'abc123',
        'user123',
        'test456',
        'username1',
        '123abc',
        '123456',
      ];

      validUsernames.forEach((username) => {
        const result = usernameSchema.safeParse(username);
        expect(result.success).toBe(true);
      });
    });

    test('accepts hyphens in middle', () => {
      const validUsernames = [
        'john-doe',
        'test-user',
        'my-username',
        'user-123',
        'a-b-c',
      ];

      validUsernames.forEach((username) => {
        const result = usernameSchema.safeParse(username);
        expect(result.success).toBe(true);
      });
    });

    test('accepts underscores in middle', () => {
      const validUsernames = [
        'john_doe',
        'test_user',
        'my_username',
        'user_123',
        'a_b_c',
      ];

      validUsernames.forEach((username) => {
        const result = usernameSchema.safeParse(username);
        expect(result.success).toBe(true);
      });
    });

    test('accepts mixed separators', () => {
      const validUsernames = [
        'john-doe_123',
        'test_user-name',
        'my-user_name',
      ];

      validUsernames.forEach((username) => {
        const result = usernameSchema.safeParse(username);
        expect(result.success).toBe(true);
      });
    });

    test('accepts uppercase letters', () => {
      const validUsernames = [
        'JohnDoe',
        'TESTUSER',
        'MyUsername',
        'ABC123',
      ];

      validUsernames.forEach((username) => {
        const result = usernameSchema.safeParse(username);
        expect(result.success).toBe(true);
      });
    });

    test('accepts mixed case', () => {
      const result = usernameSchema.safeParse('JohnDoe123');
      expect(result.success).toBe(true);
    });
  });

  describe('invalid usernames - length', () => {
    test('rejects usernames shorter than 3 characters', () => {
      const invalidUsernames = ['ab', 'a', ''];

      invalidUsernames.forEach((username) => {
        const result = usernameSchema.safeParse(username);
        expect(result.success).toBe(false);
        if (!result.success) {
          expect(result.error.issues[0].message).toContain('at least 3 characters');
        }
      });
    });

    test('rejects usernames longer than 39 characters', () => {
      const username = 'a'.repeat(40);
      const result = usernameSchema.safeParse(username);

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.issues[0].message).toContain('at most 39 characters');
      }
    });

    test('rejects very long usernames', () => {
      const username = 'a'.repeat(100);
      const result = usernameSchema.safeParse(username);

      expect(result.success).toBe(false);
    });
  });

  describe('invalid usernames - format', () => {
    test('rejects usernames starting with hyphen', () => {
      const invalidUsernames = ['-username', '-test', '-abc'];

      invalidUsernames.forEach((username) => {
        const result = usernameSchema.safeParse(username);
        expect(result.success).toBe(false);
        if (!result.success) {
          expect(result.error.issues[0].message).toContain('start and end with alphanumeric');
        }
      });
    });

    test('rejects usernames ending with hyphen', () => {
      const invalidUsernames = ['username-', 'test-', 'abc-'];

      invalidUsernames.forEach((username) => {
        const result = usernameSchema.safeParse(username);
        expect(result.success).toBe(false);
        if (!result.success) {
          expect(result.error.issues[0].message).toContain('start and end with alphanumeric');
        }
      });
    });

    test('rejects usernames starting with underscore', () => {
      const result = usernameSchema.safeParse('_username');
      expect(result.success).toBe(false);
    });

    test('rejects usernames ending with underscore', () => {
      const result = usernameSchema.safeParse('username_');
      expect(result.success).toBe(false);
    });

    test('rejects usernames with special characters', () => {
      const invalidUsernames = [
        'user@name',
        'user#name',
        'user$name',
        'user%name',
        'user.name',
        'user name',
        'user+name',
        'user=name',
      ];

      invalidUsernames.forEach((username) => {
        const result = usernameSchema.safeParse(username);
        expect(result.success).toBe(false);
      });
    });

    test('rejects usernames with spaces', () => {
      const invalidUsernames = [
        'user name',
        'john doe',
        'test user',
      ];

      invalidUsernames.forEach((username) => {
        const result = usernameSchema.safeParse(username);
        expect(result.success).toBe(false);
      });
    });

    test('rejects usernames with only special characters', () => {
      const invalidUsernames = ['---', '___', '@@@', '...'];

      invalidUsernames.forEach((username) => {
        const result = usernameSchema.safeParse(username);
        expect(result.success).toBe(false);
      });
    });
  });

  describe('edge cases', () => {
    test('rejects single character usernames even if alphanumeric', () => {
      const result = usernameSchema.safeParse('a');
      expect(result.success).toBe(false);
    });

    test('accepts single character with hyphens in middle (3 chars total)', () => {
      const result = usernameSchema.safeParse('a-b');
      expect(result.success).toBe(true);
    });

    test('rejects usernames with only hyphens and underscores', () => {
      const invalidUsernames = ['a--', 'a__', 'a-_'];

      // These should be valid as they start and end with alphanumeric
      // But single char + separator might fail length checks
      const result1 = usernameSchema.safeParse('a--');
      expect(result1.success).toBe(false); // ends with hyphen
    });

    test('handles consecutive separators', () => {
      const result = usernameSchema.safeParse('a--b');
      expect(result.success).toBe(true);
    });

    test('rejects non-string values', () => {
      const result = usernameSchema.safeParse(123);
      expect(result.success).toBe(false);
    });

    test('rejects null', () => {
      const result = usernameSchema.safeParse(null);
      expect(result.success).toBe(false);
    });

    test('rejects undefined', () => {
      const result = usernameSchema.safeParse(undefined);
      expect(result.success).toBe(false);
    });
  });
});

describe('emailSchema', () => {
  describe('valid emails', () => {
    test('accepts standard email format', () => {
      const validEmails = [
        'user@example.com',
        'test@test.com',
        'email@domain.com',
        'firstname.lastname@example.com',
      ];

      validEmails.forEach((email) => {
        const result = emailSchema.safeParse(email);
        expect(result.success).toBe(true);
      });
    });

    test('accepts emails with subdomains', () => {
      const validEmails = [
        'user@mail.example.com',
        'test@dev.test.com',
        'email@sub.domain.com',
      ];

      validEmails.forEach((email) => {
        const result = emailSchema.safeParse(email);
        expect(result.success).toBe(true);
      });
    });

    test('accepts emails with plus sign', () => {
      const result = emailSchema.safeParse('user+tag@example.com');
      expect(result.success).toBe(true);
    });

    test('accepts emails with numbers', () => {
      const validEmails = [
        'user123@example.com',
        'test456@test.com',
        '123@example.com',
      ];

      validEmails.forEach((email) => {
        const result = emailSchema.safeParse(email);
        expect(result.success).toBe(true);
      });
    });

    test('accepts emails with hyphens', () => {
      const result = emailSchema.safeParse('first-last@example.com');
      expect(result.success).toBe(true);
    });

    test('accepts emails with underscores', () => {
      const result = emailSchema.safeParse('first_last@example.com');
      expect(result.success).toBe(true);
    });

    test('accepts emails with various TLDs', () => {
      const validEmails = [
        'user@example.com',
        'user@example.org',
        'user@example.net',
        'user@example.co.uk',
        'user@example.io',
      ];

      validEmails.forEach((email) => {
        const result = emailSchema.safeParse(email);
        expect(result.success).toBe(true);
      });
    });
  });

  describe('invalid emails', () => {
    test('rejects emails without @', () => {
      const invalidEmails = [
        'userexample.com',
        'test.com',
        'email',
      ];

      invalidEmails.forEach((email) => {
        const result = emailSchema.safeParse(email);
        expect(result.success).toBe(false);
        if (!result.success) {
          expect(result.error.issues[0].message).toContain('Invalid email');
        }
      });
    });

    test('rejects emails without domain', () => {
      const result = emailSchema.safeParse('user@');
      expect(result.success).toBe(false);
    });

    test('rejects emails without username', () => {
      const result = emailSchema.safeParse('@example.com');
      expect(result.success).toBe(false);
    });

    test('rejects emails with spaces', () => {
      const invalidEmails = [
        'user @example.com',
        'user@ example.com',
        'user @example .com',
      ];

      invalidEmails.forEach((email) => {
        const result = emailSchema.safeParse(email);
        expect(result.success).toBe(false);
      });
    });

    test('rejects emails longer than 255 characters', () => {
      const longEmail = 'a'.repeat(250) + '@example.com';
      const result = emailSchema.safeParse(longEmail);

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.issues[0].message).toContain('at most 255 characters');
      }
    });

    test('rejects empty string', () => {
      const result = emailSchema.safeParse('');
      expect(result.success).toBe(false);
    });
  });

  describe('edge cases', () => {
    test('rejects multiple @ symbols', () => {
      const result = emailSchema.safeParse('user@@example.com');
      expect(result.success).toBe(false);
    });

    test('rejects non-string values', () => {
      const result = emailSchema.safeParse(123);
      expect(result.success).toBe(false);
    });

    test('rejects null', () => {
      const result = emailSchema.safeParse(null);
      expect(result.success).toBe(false);
    });

    test('rejects undefined', () => {
      const result = emailSchema.safeParse(undefined);
      expect(result.success).toBe(false);
    });
  });
});

describe('updateProfileSchema', () => {
  describe('valid profile updates', () => {
    test('accepts empty object', () => {
      const result = updateProfileSchema.safeParse({});
      expect(result.success).toBe(true);
    });

    test('accepts displayName only', () => {
      const result = updateProfileSchema.safeParse({
        displayName: 'John Doe',
      });
      expect(result.success).toBe(true);
    });

    test('accepts bio only', () => {
      const result = updateProfileSchema.safeParse({
        bio: 'This is my bio',
      });
      expect(result.success).toBe(true);
    });

    test('accepts avatarUrl only', () => {
      const result = updateProfileSchema.safeParse({
        avatarUrl: 'https://example.com/avatar.png',
      });
      expect(result.success).toBe(true);
    });

    test('accepts email only', () => {
      const result = updateProfileSchema.safeParse({
        email: 'user@example.com',
      });
      expect(result.success).toBe(true);
    });

    test('accepts all fields', () => {
      const result = updateProfileSchema.safeParse({
        displayName: 'John Doe',
        bio: 'Software developer',
        avatarUrl: 'https://example.com/avatar.png',
        email: 'john@example.com',
      });
      expect(result.success).toBe(true);
    });

    test('accepts long displayName up to 255 characters', () => {
      const result = updateProfileSchema.safeParse({
        displayName: 'a'.repeat(255),
      });
      expect(result.success).toBe(true);
    });

    test('accepts long bio up to 2000 characters', () => {
      const result = updateProfileSchema.safeParse({
        bio: 'a'.repeat(2000),
      });
      expect(result.success).toBe(true);
    });

    test('accepts long avatarUrl up to 2048 characters', () => {
      const longUrl = 'https://example.com/' + 'a'.repeat(2020) + '.png';
      const result = updateProfileSchema.safeParse({
        avatarUrl: longUrl,
      });
      expect(result.success).toBe(true);
    });
  });

  describe('invalid profile updates', () => {
    test('rejects displayName longer than 255 characters', () => {
      const result = updateProfileSchema.safeParse({
        displayName: 'a'.repeat(256),
      });
      expect(result.success).toBe(false);
    });

    test('rejects bio longer than 2000 characters', () => {
      const result = updateProfileSchema.safeParse({
        bio: 'a'.repeat(2001),
      });
      expect(result.success).toBe(false);
    });

    test('rejects invalid avatarUrl format', () => {
      const invalidUrls = [
        'not-a-url',
        '/relative/path.png',
        'relative/path.png',
        'just-text',
        '',
      ];

      invalidUrls.forEach((url) => {
        const result = updateProfileSchema.safeParse({
          avatarUrl: url,
        });
        expect(result.success).toBe(false);
      });
    });

    test('rejects avatarUrl longer than 2048 characters', () => {
      const longUrl = 'https://example.com/' + 'a'.repeat(3000) + '.png';
      const result = updateProfileSchema.safeParse({
        avatarUrl: longUrl,
      });
      expect(result.success).toBe(false);
    });

    test('rejects invalid email format', () => {
      const result = updateProfileSchema.safeParse({
        email: 'not-an-email',
      });
      expect(result.success).toBe(false);
    });

    test('rejects invalid field types', () => {
      const result = updateProfileSchema.safeParse({
        displayName: 123,
      });
      expect(result.success).toBe(false);
    });
  });

  describe('optional fields', () => {
    test('allows missing displayName', () => {
      const result = updateProfileSchema.safeParse({
        bio: 'My bio',
      });
      expect(result.success).toBe(true);
    });

    test('allows missing bio', () => {
      const result = updateProfileSchema.safeParse({
        displayName: 'John Doe',
      });
      expect(result.success).toBe(true);
    });

    test('allows missing avatarUrl', () => {
      const result = updateProfileSchema.safeParse({
        displayName: 'John Doe',
        bio: 'My bio',
      });
      expect(result.success).toBe(true);
    });

    test('allows missing email', () => {
      const result = updateProfileSchema.safeParse({
        displayName: 'John Doe',
        bio: 'My bio',
        avatarUrl: 'https://example.com/avatar.png',
      });
      expect(result.success).toBe(true);
    });

    test('allows all fields to be missing', () => {
      const result = updateProfileSchema.safeParse({});
      expect(result.success).toBe(true);
    });
  });

  describe('extra fields', () => {
    test('ignores extra fields by default', () => {
      const result = updateProfileSchema.safeParse({
        displayName: 'John Doe',
        extraField: 'should be ignored',
      });
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).not.toHaveProperty('extraField');
      }
    });
  });

  describe('edge cases', () => {
    test('accepts empty strings for optional fields', () => {
      const result = updateProfileSchema.safeParse({
        displayName: '',
        bio: '',
      });
      expect(result.success).toBe(true);
    });

    test('rejects null values', () => {
      const result = updateProfileSchema.safeParse({
        displayName: null,
      });
      expect(result.success).toBe(false);
    });

    test('validates multiple fields at once', () => {
      const result = updateProfileSchema.safeParse({
        displayName: 'a'.repeat(300),
        bio: 'a'.repeat(3000),
        avatarUrl: 'not-a-url',
        email: 'not-an-email',
      });

      expect(result.success).toBe(false);
      if (!result.success) {
        // Should have multiple validation errors
        expect(result.error.issues.length).toBeGreaterThan(1);
      }
    });

    test('accepts valid subset of fields', () => {
      const result = updateProfileSchema.safeParse({
        displayName: 'John Doe',
        email: 'john@example.com',
      });
      expect(result.success).toBe(true);
    });
  });

  describe('URL validation', () => {
    test('accepts https URLs', () => {
      const result = updateProfileSchema.safeParse({
        avatarUrl: 'https://example.com/avatar.png',
      });
      expect(result.success).toBe(true);
    });

    test('accepts http URLs', () => {
      const result = updateProfileSchema.safeParse({
        avatarUrl: 'http://example.com/avatar.png',
      });
      expect(result.success).toBe(true);
    });

    test('accepts URLs with subdomains', () => {
      const result = updateProfileSchema.safeParse({
        avatarUrl: 'https://cdn.example.com/avatars/user.png',
      });
      expect(result.success).toBe(true);
    });

    test('accepts URLs with query parameters', () => {
      const result = updateProfileSchema.safeParse({
        avatarUrl: 'https://example.com/avatar.png?size=large',
      });
      expect(result.success).toBe(true);
    });

    test('accepts URLs with fragments', () => {
      const result = updateProfileSchema.safeParse({
        avatarUrl: 'https://example.com/avatar.png#section',
      });
      expect(result.success).toBe(true);
    });
  });
});
