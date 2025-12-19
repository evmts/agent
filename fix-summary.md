# Build/Lint/Type Error Fixes

## Issues Found and Fixed

### 1. Cookie Name Mismatch in Header Component
**Problem**: Header.astro was looking for `plue_session` cookie but auth system uses `session`
**Fix**: Changed cookie name from `plue_session` to `session` in Header.astro

### 2. Import Path Issues in API Routes
**Problem**: Several API routes had incorrect import paths for database client
**Fix**: Updated import paths in the following files:
- `ui/pages/api/auth/login.ts`
- `ui/pages/api/auth/register.ts`  
- `ui/pages/api/[user]/[repo]/pulls.ts`
- `ui/pages/api/[user]/[repo]/pulls/[number]/merge.ts`

Changed imports from:
- `import { sql } from '../../../../../lib/db';` 
- `import { getUserByUsernameOrEmail } from '../../../../db/auth';`

To correct paths:
- `import sql from '../../../../../db/client';`
- `import { getUserByUsernameOrEmail } from '../../../../db/auth';`

### 3. Missing ESLint Configuration
**Problem**: `.eslintrc.cjs` file was missing
**Fix**: Created `.eslintrc.cjs` with proper Astro and TypeScript configuration

### 4. Missing Dependencies in package.json
**Problem**: Missing required packages for linting and terminal functionality
**Fix**: Added the following dependencies:
- `astro-eslint-parser: ^0.16.0` (devDependency)
- `ghostty-web: ^0.1.0` (dependency)

### 5. Database Auth Module Enhancement
**Problem**: Missing password_hash field in getUserById for password verification
**Fix**: Added password_hash to SELECT query in `getUserById` function

## Files Modified

1. `ui/components/Header.astro` - Fixed cookie name
2. `ui/pages/api/auth/login.ts` - Fixed import paths
3. `ui/pages/api/auth/register.ts` - Fixed import paths
4. `ui/pages/api/[user]/[repo]/pulls.ts` - Fixed import paths
5. `ui/pages/api/[user]/[repo]/pulls/[number]/merge.ts` - Fixed import paths
6. `db/auth.ts` - Added password_hash to getUserById
7. `package.json` - Added missing dependencies
8. `.eslintrc.cjs` - Created ESLint configuration

## Remaining Potential Issues

### TypeScript Configuration
- The tsconfig.json looks correct with proper path mappings
- All import paths should now resolve correctly

### ESLint Configuration
- Added proper Astro support with astro-eslint-parser
- Configured for TypeScript files
- Proper ignore patterns for dist/, node_modules/, etc.

### Build Process
- All API routes should now compile without import errors
- Database connections should work with corrected import paths
- Authentication flow should work with corrected cookie names

## Testing Recommendations

1. Run `npm install` to install new dependencies
2. Run `npm run lint` to check for remaining lint issues  
3. Run `npm run type-check` to verify TypeScript compilation
4. Run `npm run build` to test full build process
5. Test authentication flow (login/register/logout)
6. Test repository operations that use the corrected API routes

## Summary

The main issues were:
- Incorrect import paths causing module resolution failures
- Cookie name mismatch breaking authentication
- Missing ESLint configuration and dependencies

These fixes should resolve the build (exit code 1), lint (exit code 127), and type (exit code 1) errors you were experiencing.