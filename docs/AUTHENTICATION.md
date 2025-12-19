# Plue Authentication System

Complete authentication and authorization implementation for Plue, a GitHub clone built with Bun, Astro, Hono, and PostgreSQL.

## 🌟 Features

- **User Registration & Activation**: Email-based account activation
- **Secure Authentication**: Argon2id password hashing with proper salting
- **Session Management**: Cookie-based sessions with automatic cleanup
- **Password Recovery**: Secure password reset via email tokens
- **Profile Management**: Update display name, bio, avatar, and passwords
- **Rate Limiting**: Protection against brute force attacks
- **Authorization**: Repository and issue access control
- **Real-time Validation**: Frontend form validation with user feedback

## 🏗️ Architecture

### Backend Stack
- **Runtime**: Bun (not Node.js)
- **Server**: Hono with middleware
- **Database**: PostgreSQL with parameterized queries
- **Password Hashing**: `@node-rs/argon2` (native Rust bindings)
- **Validation**: Zod v4 schemas
- **Email**: Development console logging (production email ready)

### Frontend Stack
- **Framework**: Astro v5 (SSR)
- **Styling**: CSS variables with dark theme
- **JavaScript**: TypeScript with real-time validation
- **Forms**: Progressive enhancement with client-side validation

## 📊 Database Schema

### Core Tables

#### Users Table
```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(255) UNIQUE NOT NULL,
  lower_username VARCHAR(255) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  lower_email VARCHAR(255) UNIQUE NOT NULL,
  
  -- Display info
  display_name VARCHAR(255),
  bio TEXT,
  avatar_url VARCHAR(2048),
  
  -- Authentication
  password_hash VARCHAR(255) NOT NULL,
  password_algo VARCHAR(50) NOT NULL DEFAULT 'argon2id',
  salt VARCHAR(64) NOT NULL,
  
  -- Account status
  is_active BOOLEAN NOT NULL DEFAULT false,
  is_admin BOOLEAN NOT NULL DEFAULT false,
  prohibit_login BOOLEAN NOT NULL DEFAULT false,
  must_change_password BOOLEAN NOT NULL DEFAULT false,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_login_at TIMESTAMP
);
```

#### Sessions Table
```sql
CREATE TABLE auth_sessions (
  session_key VARCHAR(64) PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  data BYTEA,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

#### Email Verification Tokens
```sql
CREATE TABLE email_verification_tokens (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  token_hash VARCHAR(64) UNIQUE NOT NULL,
  token_type VARCHAR(20) NOT NULL CHECK (token_type IN ('activate', 'reset_password')),
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);
```

## 🚀 Setup & Installation

### 1. Prerequisites
- Bun runtime
- PostgreSQL database
- Environment variables configured

### 2. Database Migration
```bash
# Run the main schema
bun run db/schema.sql

# Run auth migration for existing installations
bun run db:migrate-auth
```

### 3. Environment Variables
```bash
# .env
DATABASE_URL=postgresql://user:password@localhost:5432/plue
SESSION_SECRET=your-random-secret-here

# Email (Development: console only, Production: configure one)
EMAIL_FROM=noreply@plue.local

# Optional: Resend (recommended for production)
RESEND_API_KEY=re_...

# Optional: SMTP
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=user
SMTP_PASS=pass

# Security
NODE_ENV=development
SECURE_COOKIES=false  # true in production
```

## 🔐 Security Features

### Password Security
- **Argon2id hashing** with secure defaults (64MB memory, 3 iterations, 4 threads)
- **32-byte cryptographic salts** per password
- **Complexity requirements**: 8+ chars, mixed case, digits
- **Timing attack prevention** with constant-time verification

### Session Security
- **HttpOnly cookies** prevent XSS access
- **Secure flag** in production (HTTPS only)
- **SameSite=Lax** for CSRF protection
- **30-day expiration** with activity refresh
- **Automatic cleanup** of expired sessions

### Token Security
- **SHA-256 hashed tokens** for email verification/reset
- **Short expiration times**: 24h activation, 1h password reset
- **Single-use tokens** automatically deleted after use
- **Rate limiting** on sensitive endpoints

### API Security
- **Input validation** with Zod schemas
- **SQL injection prevention** with parameterized queries
- **Rate limiting**: 5 auth attempts/15min, 3 resets/hour
- **Error handling** without information leakage

## 🛠️ API Endpoints

### Authentication Routes (`/api/auth`)

| Method | Endpoint | Purpose | Rate Limited |
|--------|----------|---------|-------------|
| POST | `/register` | User registration | 5/hour |
| POST | `/activate` | Account activation | No |
| POST | `/login` | User login | 5/15min |
| POST | `/logout` | User logout | No |
| GET | `/me` | Current user info | No |
| POST | `/password/reset-request` | Request password reset | 3/hour |
| POST | `/password/reset-confirm` | Confirm password reset | 5/15min |

### User Routes (`/api/users`)

| Method | Endpoint | Purpose | Auth Required |
|--------|----------|---------|---------------|
| GET | `/:username` | Public user profile | No |
| PATCH | `/me` | Update own profile | Yes + Active |
| POST | `/me/password` | Change password | Yes |

## 📱 Frontend Pages

### Public Pages
- `/login` - User sign in
- `/register` - User registration  
- `/password/reset` - Password reset request
- `/password/reset/[token]` - Password reset confirmation
- `/activate/[token]` - Account activation

### Protected Pages
- `/settings` → `/{username}/profile` - Profile settings
- `/{username}/profile` - User profile management

## 🔄 User Flow

### Registration Flow
1. User fills registration form with validation
2. Server validates input and creates inactive user
3. Activation token generated and "sent" (logged in dev)
4. User clicks activation link
5. Account activated, user can login

### Login Flow
1. User enters username/email and password
2. Server verifies credentials and account status
3. Session created and cookie set
4. User redirected to dashboard

### Password Reset Flow
1. User requests reset with email address
2. Reset token generated and "sent" (logged in dev)
3. User clicks reset link and enters new password
4. Password updated, all sessions invalidated
5. User must login with new password

## ⚙️ Configuration

### Rate Limiting
```typescript
// Customize rate limits in server/middleware/rate-limit.ts
export const authRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  maxRequests: 5, // 5 attempts per 15 minutes
});
```

### Password Complexity
```typescript
// Customize in server/lib/password.ts
export function validatePasswordComplexity(password: string) {
  // Current: 8+ chars, uppercase, lowercase, digit
  // Modify validation logic here
}
```

### Email Templates
```typescript
// Customize in server/lib/email.ts
export function createActivationEmail(username, token, baseUrl) {
  // Modify email templates
}
```

## 🚦 Development vs Production

### Development
- Emails logged to console
- Less strict security settings
- Detailed error messages
- Session cleanup logs

### Production Checklist
- [ ] Configure real email service (Resend/SMTP)
- [ ] Set `NODE_ENV=production`
- [ ] Set `SECURE_COOKIES=true`
- [ ] Use strong `SESSION_SECRET`
- [ ] Enable HTTPS
- [ ] Configure proper CORS origins
- [ ] Set up monitoring for failed auth attempts

## 🧪 Testing

### Manual Testing
```bash
# Start development servers
bun run dev:all

# Test registration flow
curl -X POST http://localhost:4000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"test","email":"test@example.com","password":"Test123!"}'

# Check console for activation token
# Test activation
curl -X POST http://localhost:4000/api/auth/activate \
  -H "Content-Type: application/json" \
  -d '{"token":"TOKEN_FROM_CONSOLE"}'

# Test login
curl -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"usernameOrEmail":"test","password":"Test123!"}'
```

### Database Testing
```sql
-- Check user creation
SELECT username, email, is_active, created_at FROM users WHERE username = 'test';

-- Check session creation
SELECT user_id, expires_at FROM auth_sessions WHERE user_id = (SELECT id FROM users WHERE username = 'test');

-- Check email addresses
SELECT email, is_activated, is_primary FROM email_addresses WHERE user_id = (SELECT id FROM users WHERE username = 'test');
```

## 🔧 Troubleshooting

### Common Issues

**"User not found" on existing seed users**
- Run `bun run db:migrate-auth` to update seed users with proper passwords

**Sessions not working**
- Check `SESSION_SECRET` environment variable
- Verify database connection
- Check browser cookies (HttpOnly cookies won't show in dev tools Application tab)

**Email tokens not working**
- Check console for development token logs
- Verify token hasn't expired (24h activation, 1h reset)
- Ensure token is copied exactly (no extra characters)

**Rate limiting too strict**
- Modify limits in `server/middleware/rate-limit.ts`
- Clear rate limit store: `curl -X POST http://localhost:4000/api/debug/clear-rate-limits` (if implemented)

**Database migration fails**
- Ensure PostgreSQL is running
- Check database permissions
- Verify connection string in `DATABASE_URL`

### Logs to Check
- Server startup logs for session cleanup job
- Authentication errors in server console  
- Rate limiting headers in network tab
- Database connection errors

## 📚 Code Examples

### Custom Password Validation
```typescript
// Add to server/lib/password.ts
export function validateCustomPassword(password: string) {
  const errors: string[] = [];
  
  if (password.length < 12) {
    errors.push('Password must be at least 12 characters');
  }
  
  if (!/[!@#$%^&*]/.test(password)) {
    errors.push('Password must contain special characters');
  }
  
  return { valid: errors.length === 0, errors };
}
```

### Authorization Helper
```typescript
// Add to server/lib/auth.ts
export async function canEditRepository(userId: number, repoId: number): Promise<boolean> {
  const [repo] = await sql<Array<{ user_id: number }>>`
    SELECT user_id FROM repositories WHERE id = ${repoId}
  `;
  
  return repo && repo.user_id === userId;
}
```

### Custom Email Provider
```typescript
// Add to server/lib/email.ts
async function sendWithCustomProvider(options: EmailOptions) {
  const response = await fetch('https://api.customprovider.com/send', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.CUSTOM_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      to: options.to,
      subject: options.subject,
      html: options.html,
    }),
  });
  
  if (!response.ok) {
    throw new Error(`Custom provider error: ${response.statusText}`);
  }
}
```

## 🔄 Migration from Previous Version

If upgrading from a pre-authentication version:

1. Backup your database
2. Update codebase to latest version
3. Run `bun run db:migrate-auth`
4. Test with seed user credentials (shown in migration output)
5. Update any custom code that depends on user structure

## 🤝 Contributing

When contributing authentication-related changes:

1. Follow existing security patterns
2. Add tests for new validation logic  
3. Update this documentation
4. Test both development and "production" modes
5. Verify rate limiting still works
6. Check for SQL injection vulnerabilities
7. Validate input thoroughly

## 📄 License

Part of the Plue project. See main LICENSE file.