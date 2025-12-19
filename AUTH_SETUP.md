# Authentication Setup Guide

This guide covers setting up the authentication system for Plue.

## Features Implemented

### Core Authentication
- ✅ User registration with email verification
- ✅ Secure password hashing with Argon2id
- ✅ Session-based authentication with HTTP-only cookies
- ✅ Password reset via email
- ✅ Account activation via email
- ✅ Rate limiting on auth endpoints
- ✅ Comprehensive input validation
- ✅ CSRF protection via SameSite cookies

### User Management
- ✅ User profile management
- ✅ Password change functionality
- ✅ Account status management (active/inactive)
- ✅ Multiple email addresses support
- ✅ Admin user support

### Security Features
- ✅ Password complexity requirements
- ✅ Session expiration and refresh
- ✅ Automatic session cleanup
- ✅ Rate limiting to prevent abuse
- ✅ Secure token generation for email verification
- ✅ Protection against user enumeration

## Environment Variables

Add these to your `.env` file:

```bash
# Database (if different from default)
DATABASE_URL=postgresql://postgres:password@localhost:54321/electric

# Session Security
SESSION_SECRET=your-random-secret-here

# Site Configuration
SITE_URL=http://localhost:4321  # for email links

# Email Service (choose one)

# Option 1: Resend (recommended for production)
EMAIL_FROM=noreply@yourdomain.com
RESEND_API_KEY=re_your_api_key_here

# Option 2: SMTP
EMAIL_FROM=noreply@yourdomain.com
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=username
SMTP_PASS=password

# Security
NODE_ENV=production  # enables secure cookies
SECURE_COOKIES=true  # force secure cookies
```

## Installation & Setup

### 1. Install Dependencies

```bash
bun install
```

### 2. Database Setup

The database schema includes all authentication tables. If you have existing data:

```bash
# Run the authentication migration
bun run db/migrate-auth.ts
```

This will:
- Update existing users with authentication fields
- Set temporary password `TempPassword123!` for all users
- Mark all accounts as inactive (requiring email verification)
- Create email address records

### 3. Email Service Setup

#### Option A: Resend (Recommended)

1. Sign up at [resend.com](https://resend.com)
2. Add your domain and verify DNS records
3. Create an API key
4. Add to `.env`:

```bash
EMAIL_FROM=noreply@yourdomain.com
RESEND_API_KEY=re_your_api_key_here
```

#### Option B: SMTP

Configure your SMTP provider:

```bash
EMAIL_FROM=noreply@yourdomain.com
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
```

#### Option C: Development Mode

For development, emails will be logged to the console instead of sent.

### 4. Start the Application

```bash
bun run dev
```

The authentication system is now active!

## User Flow

### New User Registration

1. User visits `/register`
2. Fills out username, email, password, optional display name
3. System validates input and creates inactive account
4. Activation email sent to user
5. User clicks activation link in email
6. Account activated, user can now log in

### Existing User Migration

1. Admin runs migration script (see step 2 above)
2. All users get temporary password `TempPassword123!`
3. Users must activate account via email (or admin can activate manually)
4. Users should change password after first login

### Password Reset

1. User visits `/password/reset`
2. Enters email address
3. Reset email sent (if email exists)
4. User clicks reset link in email
5. Sets new password
6. All sessions invalidated for security

## API Endpoints

### Authentication
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login user
- `POST /api/auth/logout` - Logout user
- `GET /api/auth/me` - Get current user
- `POST /api/auth/activate` - Activate account
- `POST /api/auth/password/reset-request` - Request password reset
- `POST /api/auth/password/reset-confirm` - Confirm password reset

### User Management
- `GET /api/users/:username` - Get public user profile
- `PATCH /api/users/me` - Update own profile
- `POST /api/users/me/password` - Change password

## Frontend Pages

- `/login` - Sign in page
- `/register` - Sign up page
- `/password/reset` - Request password reset
- `/password/reset/[token]` - Reset password with token
- `/activate/[token]` - Account activation
- `/[username]/profile` - User profile settings

## Security Considerations

### Password Security
- Argon2id hashing with secure parameters
- 32-byte random salt per password
- Password complexity requirements enforced
- Passwords never stored in plain text

### Session Security
- HTTP-only cookies prevent XSS access
- Secure flag enabled in production
- SameSite=Lax for CSRF protection
- 30-day expiration with activity refresh
- Automatic cleanup of expired sessions

### Rate Limiting
- 5 login attempts per 15 minutes
- 3 password reset emails per hour
- 100 API requests per 15 minutes

### Email Verification
- SHA-256 hashed tokens
- Time-limited expiration
- Single-use tokens
- No user enumeration via reset emails

## Administration

### Manually Activate User

```sql
UPDATE users SET is_active = true WHERE username = 'username';
```

### Make User Admin

```sql
UPDATE users SET is_admin = true WHERE username = 'username';
```

### Disable User Account

```sql
UPDATE users SET prohibit_login = true WHERE username = 'username';
```

### View Session Information

```sql
-- Active sessions
SELECT 
  u.username, 
  a.created_at, 
  a.expires_at
FROM auth_sessions a 
JOIN users u ON a.user_id = u.id 
WHERE a.expires_at > NOW()
ORDER BY a.created_at DESC;
```

## Troubleshooting

### Email Not Sending

1. Check environment variables are set correctly
2. Verify email service credentials
3. Check server logs for error messages
4. In development, emails are logged to console

### Can't Login After Migration

1. Verify account is active: `SELECT is_active FROM users WHERE username = 'user';`
2. Use temporary password: `TempPassword123!`
3. Check email verification status
4. Manually activate if needed (see Administration section)

### Session Issues

1. Check cookie settings in browser dev tools
2. Verify `SITE_URL` matches your domain
3. Check for secure cookie issues in development
4. Clear browser cookies and try again

### Database Connection

1. Verify `DATABASE_URL` is correct
2. Check PostgreSQL is running
3. Verify database exists and schema is applied
4. Check network connectivity

## Development Notes

- The auth middleware is applied globally to all API routes
- Frontend pages use the `client-auth.ts` utilities for API calls
- Session cleanup runs automatically every hour
- Rate limiting uses in-memory storage (consider Redis for production clusters)
- All auth-related operations have comprehensive error handling

## Production Deployment

1. Set `NODE_ENV=production`
2. Use strong `SESSION_SECRET` (32+ random characters)
3. Configure proper email service (Resend recommended)
4. Set `SECURE_COOKIES=true`
5. Use HTTPS for all communication
6. Consider Redis for rate limiting storage
7. Set up database backups
8. Monitor authentication logs

## Migration from Existing System

The authentication system is designed to be backward-compatible:

1. Existing users get temporary passwords
2. All accounts start as inactive
3. Users must verify email to activate
4. Existing routes remain protected
5. Session data is preserved where possible

For a seamless migration:
1. Run migration during maintenance window
2. Notify users of temporary password
3. Provide clear activation instructions
4. Consider bulk-activating known good users
5. Monitor for support requests

## Support

For issues with the authentication system:
1. Check this guide and troubleshooting section
2. Review server logs for errors
3. Verify environment configuration
4. Test with a fresh user account
5. Check database constraints and indexes