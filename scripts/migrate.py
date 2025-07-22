#!/usr/bin/env python3
"""
Database migration script for Plue application
"""

import os
import sys
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT

def get_connection_params():
    """Get database connection parameters from environment variables"""
    return {
        'host': os.getenv('POSTGRES_HOST', 'localhost'),
        'port': int(os.getenv('POSTGRES_PORT', '5432')),
        'user': os.getenv('POSTGRES_USER', 'plue'),
        'password': os.getenv('POSTGRES_PASSWORD', 'plue_password'),
        'database': os.getenv('POSTGRES_DB', 'plue')
    }

def create_schema_table(cursor):
    """Create the schema_version table if it doesn't exist"""
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY,
            applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            description TEXT
        )
    """)

def get_current_version(cursor):
    """Get the current schema version"""
    try:
        cursor.execute("SELECT MAX(version) FROM schema_version")
        result = cursor.fetchone()
        return result[0] if result[0] is not None else 0
    except psycopg2.ProgrammingError:
        return 0

def apply_migration(cursor, version, description, sql):
    """Apply a single migration"""
    print(f"Applying migration {version}: {description}")
    
    # Execute the migration SQL
    cursor.execute(sql)
    
    # Record the migration
    cursor.execute(
        "INSERT INTO schema_version (version, description) VALUES (%s, %s)",
        (version, description)
    )

def migrate_up():
    """Apply all pending migrations"""
    try:
        params = get_connection_params()
        conn = psycopg2.connect(**params)
        conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
        cursor = conn.cursor()
        
        print(f"Connected to database: {params['database']} at {params['host']}:{params['port']}")
        
        # Create schema version table
        create_schema_table(cursor)
        
        # Get current version
        current_version = get_current_version(cursor)
        print(f"Current schema version: {current_version}")
        
        # Define migrations
        migrations = [
            (1, "Create users table", """
                CREATE TABLE users (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(255) NOT NULL UNIQUE,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """),
            # Add more migrations here as needed
        ]
        
        # Apply pending migrations
        applied_count = 0
        for version, description, sql in migrations:
            if version > current_version:
                apply_migration(cursor, version, description, sql)
                applied_count += 1
        
        if applied_count == 0:
            print("No migrations to apply - database is up to date")
        else:
            print(f"Applied {applied_count} migration(s) successfully")
        
        cursor.close()
        conn.close()
        
    except psycopg2.Error as e:
        print(f"Database error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

def migrate_down(target_version):
    """Rollback to a specific version (simplified implementation)"""
    try:
        params = get_connection_params()
        conn = psycopg2.connect(**params)
        conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
        cursor = conn.cursor()
        
        current_version = get_current_version(cursor)
        print(f"Current version: {current_version}, target version: {target_version}")
        
        if target_version >= current_version:
            print("Target version must be less than current version")
            return
        
        # Simple rollback - just delete migration records
        # In a real app, you'd want proper down migrations
        cursor.execute(
            "DELETE FROM schema_version WHERE version > %s",
            (target_version,)
        )
        
        # Drop tables if rolling back to version 0
        if target_version == 0:
            cursor.execute("DROP TABLE IF EXISTS users")
            cursor.execute("DROP TABLE IF EXISTS schema_version")
        
        print(f"Rolled back to version {target_version}")
        
        cursor.close()
        conn.close()
        
    except psycopg2.Error as e:
        print(f"Database error: {e}")
        sys.exit(1)

def show_status():
    """Show current migration status"""
    try:
        params = get_connection_params()
        conn = psycopg2.connect(**params)
        cursor = conn.cursor()
        
        try:
            cursor.execute("SELECT version, applied_at, description FROM schema_version ORDER BY version")
            migrations = cursor.fetchall()
            
            if not migrations:
                print("No migrations applied")
            else:
                print("Applied migrations:")
                for version, applied_at, description in migrations:
                    print(f"  {version}: {description} (applied: {applied_at})")
        
        except psycopg2.ProgrammingError:
            print("Schema version table does not exist - no migrations applied")
        
        cursor.close()
        conn.close()
        
    except psycopg2.Error as e:
        print(f"Database error: {e}")
        sys.exit(1)

def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        print("Usage: migrate.py [up|down|status] [version]")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "up":
        migrate_up()
    elif command == "down":
        if len(sys.argv) < 3:
            print("Down migration requires target version")
            sys.exit(1)
        target_version = int(sys.argv[2])
        migrate_down(target_version)
    elif command == "status":
        show_status()
    else:
        print("Unknown command. Use: up, down, or status")
        sys.exit(1)

if __name__ == "__main__":
    main()