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
            (2, "Extend users table for full user management", """
                ALTER TABLE users 
                ADD COLUMN email VARCHAR(255),
                ADD COLUMN passwd VARCHAR(255),
                ADD COLUMN type SMALLINT DEFAULT 0,
                ADD COLUMN is_admin BOOLEAN DEFAULT FALSE,
                ADD COLUMN avatar VARCHAR(255),
                ADD COLUMN created_unix BIGINT,
                ADD COLUMN updated_unix BIGINT;
                
                -- Update existing timestamps to unix
                UPDATE users SET 
                    created_unix = EXTRACT(EPOCH FROM created_at)::BIGINT,
                    updated_unix = EXTRACT(EPOCH FROM updated_at)::BIGINT;
                
                -- Make unix timestamps not null
                ALTER TABLE users 
                ALTER COLUMN created_unix SET NOT NULL,
                ALTER COLUMN updated_unix SET NOT NULL;
                
                -- Drop old timestamp columns
                ALTER TABLE users 
                DROP COLUMN created_at,
                DROP COLUMN updated_at;
            """),
            (3, "Create organization user relationship table", """
                CREATE TABLE org_user (
                    id SERIAL PRIMARY KEY,
                    uid BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    org_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    is_owner BOOLEAN NOT NULL DEFAULT FALSE,
                    UNIQUE(uid, org_id)
                );
                
                CREATE INDEX idx_org_user_uid ON org_user(uid);
                CREATE INDEX idx_org_user_orgid ON org_user(org_id);
            """),
            (4, "Create SSH public keys table", """
                CREATE TABLE public_key (
                    id SERIAL PRIMARY KEY,
                    owner_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    name VARCHAR(255) NOT NULL,
                    content TEXT NOT NULL,
                    fingerprint VARCHAR(255) NOT NULL,
                    created_unix BIGINT NOT NULL,
                    updated_unix BIGINT NOT NULL
                );
                
                CREATE INDEX idx_public_key_owner ON public_key(owner_id);
                CREATE INDEX idx_public_key_fingerprint ON public_key(fingerprint);
            """),
            (5, "Create repository and branch tables", """
                CREATE TABLE repository (
                    id SERIAL PRIMARY KEY,
                    owner_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    lower_name VARCHAR(255) NOT NULL,
                    name VARCHAR(255) NOT NULL,
                    description TEXT,
                    default_branch VARCHAR(255) DEFAULT 'main',
                    is_private BOOLEAN NOT NULL DEFAULT FALSE,
                    is_fork BOOLEAN NOT NULL DEFAULT FALSE,
                    fork_id BIGINT REFERENCES repository(id) ON DELETE SET NULL,
                    created_unix BIGINT NOT NULL,
                    updated_unix BIGINT NOT NULL,
                    UNIQUE(owner_id, lower_name)
                );
                
                CREATE INDEX idx_repository_owner ON repository(owner_id);
                CREATE INDEX idx_repository_fork ON repository(fork_id) WHERE fork_id IS NOT NULL;
                
                CREATE TABLE branch (
                    id SERIAL PRIMARY KEY,
                    repo_id BIGINT NOT NULL REFERENCES repository(id) ON DELETE CASCADE,
                    name VARCHAR(255) NOT NULL,
                    commit_id VARCHAR(40),
                    is_protected BOOLEAN NOT NULL DEFAULT FALSE,
                    UNIQUE(repo_id, name)
                );
                
                CREATE INDEX idx_branch_repo ON branch(repo_id);
            """),
            (6, "Create LFS support tables", """
                CREATE TABLE lfs_meta_object (
                    oid VARCHAR(64) PRIMARY KEY,
                    size BIGINT NOT NULL,
                    repository_id BIGINT NOT NULL REFERENCES repository(id) ON DELETE CASCADE
                );
                
                CREATE INDEX idx_lfs_meta_object_repo ON lfs_meta_object(repository_id);
                
                CREATE TABLE lfs_lock (
                    id SERIAL PRIMARY KEY,
                    repo_id BIGINT NOT NULL REFERENCES repository(id) ON DELETE CASCADE,
                    path TEXT NOT NULL,
                    owner_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    created_unix BIGINT NOT NULL
                );
                
                CREATE INDEX idx_lfs_lock_repo ON lfs_lock(repo_id);
                CREATE INDEX idx_lfs_lock_owner ON lfs_lock(owner_id);
            """),
            (7, "Create issue tracking tables", """
                CREATE TABLE issue (
                    id SERIAL PRIMARY KEY,
                    repo_id BIGINT NOT NULL REFERENCES repository(id) ON DELETE CASCADE,
                    index BIGINT NOT NULL,
                    poster_id BIGINT NOT NULL REFERENCES users(id),
                    title VARCHAR(255) NOT NULL,
                    content TEXT,
                    is_closed BOOLEAN NOT NULL DEFAULT FALSE,
                    is_pull BOOLEAN NOT NULL DEFAULT FALSE,
                    assignee_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
                    created_unix BIGINT NOT NULL,
                    UNIQUE(repo_id, index)
                );
                
                CREATE INDEX idx_issue_repo ON issue(repo_id);
                CREATE INDEX idx_issue_poster ON issue(poster_id);
                CREATE INDEX idx_issue_assignee ON issue(assignee_id) WHERE assignee_id IS NOT NULL;
                
                CREATE TABLE label (
                    id SERIAL PRIMARY KEY,
                    repo_id BIGINT NOT NULL REFERENCES repository(id) ON DELETE CASCADE,
                    name VARCHAR(255) NOT NULL,
                    color VARCHAR(7) NOT NULL
                );
                
                CREATE INDEX idx_label_repo ON label(repo_id);
                
                CREATE TABLE issue_label (
                    id SERIAL PRIMARY KEY,
                    issue_id BIGINT NOT NULL REFERENCES issue(id) ON DELETE CASCADE,
                    label_id BIGINT NOT NULL REFERENCES label(id) ON DELETE CASCADE,
                    UNIQUE(issue_id, label_id)
                );
                
                CREATE INDEX idx_issue_label_issue ON issue_label(issue_id);
                CREATE INDEX idx_issue_label_label ON issue_label(label_id);
            """),
            (8, "Create review and comment tables", """
                CREATE TABLE review (
                    id SERIAL PRIMARY KEY,
                    type SMALLINT NOT NULL,
                    reviewer_id BIGINT NOT NULL REFERENCES users(id),
                    issue_id BIGINT NOT NULL REFERENCES issue(id) ON DELETE CASCADE,
                    commit_id VARCHAR(40)
                );
                
                CREATE INDEX idx_review_issue ON review(issue_id);
                CREATE INDEX idx_review_reviewer ON review(reviewer_id);
                
                CREATE TABLE comment (
                    id SERIAL PRIMARY KEY,
                    poster_id BIGINT NOT NULL REFERENCES users(id),
                    issue_id BIGINT NOT NULL REFERENCES issue(id) ON DELETE CASCADE,
                    review_id BIGINT REFERENCES review(id) ON DELETE CASCADE,
                    content TEXT NOT NULL,
                    commit_id VARCHAR(40),
                    line INTEGER,
                    created_unix BIGINT NOT NULL
                );
                
                CREATE INDEX idx_comment_issue ON comment(issue_id);
                CREATE INDEX idx_comment_poster ON comment(poster_id);
                CREATE INDEX idx_comment_review ON comment(review_id) WHERE review_id IS NOT NULL;
            """),
            (9, "Create Actions core tables", """
                CREATE TABLE action_run (
                    id SERIAL PRIMARY KEY,
                    repo_id BIGINT NOT NULL REFERENCES repository(id) ON DELETE CASCADE,
                    workflow_id VARCHAR(255) NOT NULL,
                    commit_sha VARCHAR(40) NOT NULL,
                    trigger_event VARCHAR(255) NOT NULL,
                    status SMALLINT NOT NULL,
                    created_unix BIGINT NOT NULL
                );
                
                CREATE INDEX idx_action_run_repo ON action_run(repo_id);
                CREATE INDEX idx_action_run_status ON action_run(status);
                
                CREATE TABLE action_job (
                    id SERIAL PRIMARY KEY,
                    run_id BIGINT NOT NULL REFERENCES action_run(id) ON DELETE CASCADE,
                    name VARCHAR(255) NOT NULL,
                    runs_on TEXT NOT NULL,
                    status SMALLINT NOT NULL,
                    log TEXT,
                    started BIGINT,
                    stopped BIGINT
                );
                
                CREATE INDEX idx_action_job_run ON action_job(run_id);
                CREATE INDEX idx_action_job_status ON action_job(status);
            """),
            (10, "Create Actions runner and artifact tables", """
                CREATE TABLE action_runner (
                    id SERIAL PRIMARY KEY,
                    uuid VARCHAR(255) NOT NULL UNIQUE,
                    name VARCHAR(255) NOT NULL,
                    owner_id BIGINT NOT NULL DEFAULT 0,
                    repo_id BIGINT NOT NULL DEFAULT 0,
                    token_hash VARCHAR(255) NOT NULL,
                    labels TEXT,
                    status VARCHAR(32) NOT NULL,
                    last_online BIGINT
                );
                
                CREATE INDEX idx_action_runner_owner ON action_runner(owner_id) WHERE owner_id > 0;
                CREATE INDEX idx_action_runner_repo ON action_runner(repo_id) WHERE repo_id > 0;
                CREATE INDEX idx_action_runner_status ON action_runner(status);
                
                CREATE TABLE action_runner_token (
                    id SERIAL PRIMARY KEY,
                    token_hash VARCHAR(255) NOT NULL UNIQUE,
                    owner_id BIGINT NOT NULL DEFAULT 0,
                    repo_id BIGINT NOT NULL DEFAULT 0
                );
                
                CREATE TABLE action_artifact (
                    id SERIAL PRIMARY KEY,
                    job_id BIGINT NOT NULL REFERENCES action_job(id) ON DELETE CASCADE,
                    name VARCHAR(255) NOT NULL,
                    path TEXT NOT NULL,
                    file_size BIGINT NOT NULL
                );
                
                CREATE INDEX idx_action_artifact_job ON action_artifact(job_id);
                
                CREATE TABLE action_secret (
                    id SERIAL PRIMARY KEY,
                    owner_id BIGINT NOT NULL DEFAULT 0,
                    repo_id BIGINT NOT NULL DEFAULT 0,
                    name VARCHAR(255) NOT NULL,
                    data BYTEA NOT NULL
                );
                
                CREATE INDEX idx_action_secret_owner ON action_secret(owner_id) WHERE owner_id > 0;
                CREATE INDEX idx_action_secret_repo ON action_secret(repo_id) WHERE repo_id > 0;
            """),
            (11, "Create authentication token table", """
                CREATE TABLE auth_token (
                    id SERIAL PRIMARY KEY,
                    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    token VARCHAR(255) NOT NULL UNIQUE,
                    created_unix BIGINT NOT NULL,
                    expires_unix BIGINT NOT NULL
                );
                
                CREATE INDEX idx_auth_token_user ON auth_token(user_id);
                CREATE INDEX idx_auth_token_token ON auth_token(token);
                CREATE INDEX idx_auth_token_expires ON auth_token(expires_unix);
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
            # Drop in reverse dependency order
            cursor.execute("DROP TABLE IF EXISTS auth_token CASCADE")
            cursor.execute("DROP TABLE IF EXISTS action_secret CASCADE")
            cursor.execute("DROP TABLE IF EXISTS action_artifact CASCADE")
            cursor.execute("DROP TABLE IF EXISTS action_runner_token CASCADE")
            cursor.execute("DROP TABLE IF EXISTS action_runner CASCADE")
            cursor.execute("DROP TABLE IF EXISTS action_job CASCADE")
            cursor.execute("DROP TABLE IF EXISTS action_run CASCADE")
            cursor.execute("DROP TABLE IF EXISTS comment CASCADE")
            cursor.execute("DROP TABLE IF EXISTS review CASCADE")
            cursor.execute("DROP TABLE IF EXISTS issue_label CASCADE")
            cursor.execute("DROP TABLE IF EXISTS label CASCADE")
            cursor.execute("DROP TABLE IF EXISTS issue CASCADE")
            cursor.execute("DROP TABLE IF EXISTS lfs_lock CASCADE")
            cursor.execute("DROP TABLE IF EXISTS lfs_meta_object CASCADE")
            cursor.execute("DROP TABLE IF EXISTS branch CASCADE")
            cursor.execute("DROP TABLE IF EXISTS repository CASCADE")
            cursor.execute("DROP TABLE IF EXISTS public_key CASCADE")
            cursor.execute("DROP TABLE IF EXISTS org_user CASCADE")
            cursor.execute("DROP TABLE IF EXISTS users CASCADE")
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