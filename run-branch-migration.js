import { readFile } from 'fs/promises';
import { sql } from './ui/lib/db.js';

try {
  const migrationSQL = await readFile('./db/migrate-branches.sql', 'utf8');
  
  // Execute the migration
  await sql.unsafe(migrationSQL);
  
  console.log('Branch management migration completed successfully');
  process.exit(0);
} catch (error) {
  console.error('Migration failed:', error);
  process.exit(1);
}