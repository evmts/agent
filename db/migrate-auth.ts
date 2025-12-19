/**
 * Migration script to add authentication to existing users
 * This should be run once to migrate the database to the new schema
 */

import sql from './client';
import { hashPassword, generateSalt } from '../server/lib/password';

async function migrateUsersAuth() {
  console.log('Starting authentication migration...');

  try {
    // Get all users that don't have proper auth fields
    const users = await sql<Array<{
      id: number;
      username: string;
      email: string;
      display_name: string | null;
      bio: string | null;
    }>>`
      SELECT id, username, email, display_name, bio 
      FROM users 
      WHERE password_hash = 'temp_hash' OR password_hash IS NULL
    `;

    console.log(`Found ${users.length} users to migrate`);

    for (const user of users) {
      console.log(`Migrating user: ${user.username}`);

      // Generate temporary password and salt
      const tempPassword = 'TempPassword123!'; // Users will need to reset their password
      const salt = generateSalt();
      const passwordHash = await hashPassword(tempPassword, salt);

      // Update user with proper auth fields
      await sql`
        UPDATE users 
        SET 
          password_hash = ${passwordHash},
          password_algo = 'argon2id',
          salt = ${salt},
          is_active = false,
          must_change_password = true,
          updated_at = NOW()
        WHERE id = ${user.id}
      `;

      // Create email record
      await sql`
        INSERT INTO email_addresses (user_id, email, lower_email, is_primary, is_activated)
        VALUES (${user.id}, ${user.email}, ${user.email.toLowerCase()}, true, false)
        ON CONFLICT (email) DO NOTHING
      `;

      console.log(`✓ Migrated ${user.username} (temporary password: ${tempPassword})`);
    }

    console.log('Migration completed successfully!');
    console.log('');
    console.log('IMPORTANT:');
    console.log('- All existing users now have the temporary password: TempPassword123!');
    console.log('- Users must activate their accounts via email verification');
    console.log('- Users should change their password after activating');
    console.log('- To make a user active without email verification, run:');
    console.log('  UPDATE users SET is_active = true WHERE username = \'username\';');
    
  } catch (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  }
}

export { migrateUsersAuth };