import type { APIRoute } from 'astro';
import { createUser } from '../../../lib/auth-db';
import { hash } from '@node-rs/argon2';
import { randomBytes } from 'crypto';
import {
  validateCsrfToken,
  csrfErrorResponse,
  validatePassword,
  validateUsername,
  validateEmail,
  validateTextInput
} from '../../../lib/auth-helpers';

export const POST: APIRoute = async ({ request }) => {
  try {
    // Validate CSRF token
    if (!validateCsrfToken(request)) {
      return csrfErrorResponse();
    }

    const body = await request.json();
    const { username, email, password, displayName } = body;

    // Validate required fields
    if (!username || !email || !password) {
      return new Response(JSON.stringify({ error: 'Username, email, and password are required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate username
    const usernameValidation = validateUsername(username);
    if (!usernameValidation.valid) {
      return new Response(JSON.stringify({ error: usernameValidation.error }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate email
    const emailValidation = validateEmail(email);
    if (!emailValidation.valid) {
      return new Response(JSON.stringify({ error: emailValidation.error }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate password complexity
    const passwordValidation = validatePassword(password);
    if (!passwordValidation.valid) {
      return new Response(JSON.stringify({
        error: 'Password does not meet requirements',
        details: passwordValidation.errors
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate display name if provided
    const displayNameValidation = validateTextInput(displayName, 'Display name', { maxLength: 100 });
    if (!displayNameValidation.valid) {
      return new Response(JSON.stringify({ error: displayNameValidation.error }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Hash password
    const passwordHash = await hash(password);

    // Generate activation token
    const activationToken = randomBytes(32).toString('hex');

    // Create user
    try {
      const user = await createUser({
        username: username.trim(),
        email: email.trim().toLowerCase(),
        passwordHash,
        displayName: displayNameValidation.value || undefined,
        activationToken
      });

      // TODO: Send activation email with the token
      // For now, just return success

      return new Response(JSON.stringify({
        success: true,
        user: {
          id: Number(user.id),
          username: user.username,
          email: user.email,
          displayName: user.display_name
        },
        message: 'Registration successful. Please check your email for activation link.'
      }), {
        status: 201,
        headers: { 'Content-Type': 'application/json' }
      });
    } catch (dbError: any) {
      if (dbError.code === '23505') { // Unique constraint violation
        return new Response(JSON.stringify({ error: 'User with this username or email already exists' }), {
          status: 409,
          headers: { 'Content-Type': 'application/json' }
        });
      }
      throw dbError;
    }
  } catch (error) {
    console.error('Registration error:', error instanceof Error ? error.message : 'Unknown error');
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};