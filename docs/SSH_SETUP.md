# SSH Git Operations Setup Guide

This guide explains how to set up SSH git operations for Plue using OpenSSH's `authorized_keys_command` mechanism.

## Overview

Plue implements SSH git operations using OpenSSH as the protocol handler. This approach:
- Leverages OpenSSH's mature, battle-tested SSH protocol implementation
- Uses `AuthorizedKeysCommand` to query the database for user SSH keys
- Uses `ForceCommand` to restrict sessions to git operations only
- Provides the same user experience as GitHub/GitLab (`git@server:user/repo.git`)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Git Client (git clone/push/pull)                            │
└────────────────────┬────────────────────────────────────────┘
                     │ SSH Protocol
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ OpenSSH Server (sshd)                                        │
│  - Protocol handling                                         │
│  - Key exchange & encryption                                 │
│  - Calls AuthorizedKeysCommand                              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ authorized_keys_command.sh                                   │
│  - Queries PostgreSQL for user's SSH keys                   │
│  - Returns keys with security restrictions                   │
└────────────────────┬────────────────────────────────────────┘
                     │ Authentication Success
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ git-shell.sh (ForceCommand)                                  │
│  - Validates git command (upload-pack/receive-pack)         │
│  - Checks repository exists                                  │
│  - Executes git command                                      │
│  - Triggers jj sync on successful push                       │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- OpenSSH server (sshd) installed
- PostgreSQL with Plue database
- Git installed
- Bash shell
- `psql` command-line tool

## Setup Instructions

### 1. Create Git User

Create a dedicated `git` user for SSH operations:

```bash
# Create user with home directory
sudo useradd -r -m -d /var/lib/plue -s /bin/bash git

# Set up directory structure
sudo mkdir -p /var/lib/plue/repos
sudo mkdir -p /var/log/plue
sudo chown -R git:git /var/lib/plue /var/log/plue
```

### 2. Install Scripts

Copy the SSH scripts to a system location:

```bash
# Create scripts directory
sudo mkdir -p /opt/plue/scripts

# Copy scripts from repository
sudo cp server/scripts/authorized_keys_command.sh /opt/plue/scripts/
sudo cp server/scripts/git-shell.sh /opt/plue/scripts/

# Make executable
sudo chmod +x /opt/plue/scripts/*.sh

# Set ownership
sudo chown root:root /opt/plue/scripts/*.sh
```

### 3. Generate SSH Host Keys

Generate dedicated host keys for the Plue SSH server:

```bash
# RSA key (for compatibility)
sudo ssh-keygen -t rsa -b 4096 -f /var/lib/plue/ssh_host_rsa_key -N "" -C "plue-ssh-host-rsa"

# Ed25519 key (recommended, modern)
sudo ssh-keygen -t ed25519 -f /var/lib/plue/ssh_host_ed25519_key -N "" -C "plue-ssh-host-ed25519"

# Set proper permissions
sudo chmod 600 /var/lib/plue/ssh_host_*_key
sudo chmod 644 /var/lib/plue/ssh_host_*_key.pub
sudo chown root:root /var/lib/plue/ssh_host_*_key*
```

### 4. Configure Environment Variables

Create an environment file for the scripts:

```bash
sudo tee /opt/plue/scripts/env.sh > /dev/null <<'EOF'
# Plue SSH Configuration
export DATABASE_URL="postgres://plue:password@localhost:5432/plue"
export PLUE_REPOS_DIR="/var/lib/plue/repos"
export PLUE_LOG_DIR="/var/log/plue"
export PLUE_API_URL="http://localhost:8080"
EOF

sudo chmod 600 /opt/plue/scripts/env.sh
sudo chown git:git /opt/plue/scripts/env.sh
```

Update both scripts to source this environment file:

```bash
# Add to the top of both scripts (after shebang and comments)
sudo sed -i '3i # Source environment\n[ -f /opt/plue/scripts/env.sh ] && source /opt/plue/scripts/env.sh' \
  /opt/plue/scripts/authorized_keys_command.sh \
  /opt/plue/scripts/git-shell.sh
```

### 5. Configure OpenSSH

You have two options for configuring OpenSSH:

#### Option A: Standalone SSH Instance (Recommended for Development)

Create a dedicated sshd instance for Plue on port 2222:

```bash
# Copy sample config
sudo cp server/scripts/sshd_config.plue /etc/ssh/sshd_config.plue

# Edit paths if needed
sudo nano /etc/ssh/sshd_config.plue

# Start standalone sshd
sudo /usr/sbin/sshd -f /etc/ssh/sshd_config.plue -D
```

To run as a systemd service:

```bash
sudo tee /etc/systemd/system/plue-sshd.service > /dev/null <<'EOF'
[Unit]
Description=Plue SSH Server
After=network.target postgresql.service

[Service]
Type=simple
ExecStart=/usr/sbin/sshd -D -f /etc/ssh/sshd_config.plue
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable plue-sshd
sudo systemctl start plue-sshd
```

#### Option B: System SSH (Production)

Add Plue configuration to your system SSH:

```bash
# Create drop-in config
sudo tee /etc/ssh/sshd_config.d/plue.conf > /dev/null <<'EOF'
# Plue SSH Git Operations
# Only applies to connections from user 'git' on port 22

Match User git
    AuthorizedKeysCommand /opt/plue/scripts/authorized_keys_command.sh
    AuthorizedKeysCommandUser git
    ForceCommand /opt/plue/scripts/git-shell.sh
    PasswordAuthentication no
    PubkeyAuthentication yes
    PermitRootLogin no
    X11Forwarding no
    AllowTcpForwarding no
    AllowAgentForwarding no
    PermitTunnel no
EOF

# Test configuration
sudo sshd -t

# Reload SSH
sudo systemctl reload sshd
```

### 6. Configure Database Access

Grant the `git` user access to query the database:

```sql
-- Connect to PostgreSQL as superuser
psql -U postgres

-- Grant read access to the git user
GRANT CONNECT ON DATABASE plue TO git;
GRANT USAGE ON SCHEMA public TO git;
GRANT SELECT ON users, ssh_keys TO git;
```

Alternatively, use a `.pgpass` file:

```bash
# Create password file for git user
sudo -u git tee ~/.pgpass > /dev/null <<EOF
localhost:5432:plue:git:your_password_here
EOF

sudo -u git chmod 600 ~/.pgpass
```

### 7. Test the Setup

#### Test 1: Verify authorized_keys_command

```bash
# Switch to git user
sudo -u git bash

# Test the command
/opt/plue/scripts/authorized_keys_command.sh git

# Should output SSH public keys with restrictions:
# no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-rsa AAAAB3...
```

#### Test 2: Test SSH Connection

```bash
# From your development machine, test SSH (will fail but shows authentication)
ssh -v git@your-server -p 2222

# Should see authentication success, then git-shell refusing interactive login
```

#### Test 3: Test Git Operations

```bash
# Add your SSH key to Plue (via API or web UI)
curl -X POST http://localhost:8080/api/ssh-keys \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My Development Key",
    "publicKey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... user@host"
  }'

# Create a test repository in Plue
mkdir -p /var/lib/plue/repos/testuser/testrepo
cd /var/lib/plue/repos/testuser/testrepo
git init --bare
jj git init --colocate

# Clone the repository
git clone git@your-server:testuser/testrepo.git
cd testrepo

# Make changes and push
echo "# Test" > README.md
git add README.md
git commit -m "Initial commit"
git push origin main
```

## sshd_config Reference

Here's the complete `sshd_config.plue` with explanations:

```sshd_config
# Plue SSH Server Configuration
# For git operations over SSH

# Network Configuration
Port 2222                    # Use non-standard port (22 for production)
ListenAddress 0.0.0.0        # Listen on all interfaces
Protocol 2                   # SSH protocol version 2 only

# Host Keys
HostKey /var/lib/plue/ssh_host_rsa_key
HostKey /var/lib/plue/ssh_host_ed25519_key

# Authentication Configuration
PubkeyAuthentication yes     # Enable public key authentication
PasswordAuthentication no    # Disable password authentication
ChallengeResponseAuthentication no
UsePAM no                    # Don't use PAM

# Authorized Keys Command
# This queries the database for authorized SSH keys
AuthorizedKeysCommand /opt/plue/scripts/authorized_keys_command.sh
AuthorizedKeysCommandUser git

# Force Command
# All SSH sessions execute this script (no interactive shell)
ForceCommand /opt/plue/scripts/git-shell.sh

# User Restrictions
AllowUsers git               # Only allow 'git' user

# Logging
SyslogFacility AUTH
LogLevel INFO               # Use VERBOSE or DEBUG for troubleshooting

# Security Hardening
PermitRootLogin no          # Never allow root login
PermitEmptyPasswords no     # No empty passwords
X11Forwarding no            # Disable X11
AllowTcpForwarding no       # Disable TCP forwarding
AllowAgentForwarding no     # Disable agent forwarding
PermitTunnel no             # Disable tunneling

# Session Configuration
PrintMotd no                # Don't print message of the day
PrintLastLog no             # Don't print last login
UseDNS no                   # Speed up connections
```

## Security Considerations

### 1. Principle of Least Privilege

The `git` user should have minimal permissions:

```bash
# Restrict git user shell (after testing)
sudo usermod -s /bin/bash git  # Keep bash for ForceCommand

# Limit git user to necessary directories
sudo chmod 750 /var/lib/plue
sudo chmod 770 /var/lib/plue/repos
```

### 2. SSH Key Restrictions

The `authorized_keys_command.sh` adds these restrictions to every key:
- `no-port-forwarding`: Prevents SSH tunneling
- `no-X11-forwarding`: Prevents X11 forwarding
- `no-agent-forwarding`: Prevents SSH agent forwarding
- `no-pty`: Prevents pseudo-terminal allocation

These ensure SSH sessions can only execute git commands, not interactive shells.

### 3. Database Access Security

The `authorized_keys_command.sh` script needs database access:
- Use read-only database credentials
- Limit access to `users` and `ssh_keys` tables only
- Consider using SSL/TLS for PostgreSQL connections
- Rotate credentials regularly

```sql
-- Create read-only user for authorized_keys_command
CREATE ROLE plue_ssh_reader WITH LOGIN PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE plue TO plue_ssh_reader;
GRANT USAGE ON SCHEMA public TO plue_ssh_reader;
GRANT SELECT ON users, ssh_keys TO plue_ssh_reader;
```

### 4. Repository Access Control

Access control is enforced at two levels:

1. **SSH Authentication**: User must have valid SSH key in database
2. **Repository Permissions**: Checked by `validateAccess` in `session.zig`
   - Read operations: Repository must be public OR user must be owner/collaborator
   - Write operations: User must be owner or have write/admin access

### 5. Audit Logging

All git operations are logged:

```bash
# Git shell operations log
/var/log/plue/git-shell.log

# JJ sync operations log
/var/log/plue/jj-sync.log

# System SSH authentication log
/var/log/auth.log

# Example log analysis
# Show all git operations by user
sudo grep "git-" /var/log/plue/git-shell.log

# Show failed authentication attempts
sudo grep "Failed" /var/log/auth.log | grep plue
```

### 6. Firewall Configuration

Restrict SSH access:

```bash
# Allow SSH only from specific networks
sudo ufw allow from 192.168.1.0/24 to any port 2222 proto tcp

# Or for public access
sudo ufw allow 2222/tcp

# Check firewall status
sudo ufw status
```

### 7. Host Key Verification

Users should verify the SSH host key fingerprint on first connection:

```bash
# Get host key fingerprints
ssh-keygen -lf /var/lib/plue/ssh_host_ed25519_key.pub
ssh-keygen -lf /var/lib/plue/ssh_host_rsa_key.pub

# Display on web UI or documentation
# Users should verify:
git clone git@server:user/repo.git
# The authenticity of host '[server]:2222' can't be established.
# ED25519 key fingerprint is SHA256:...
# Verify this matches the published fingerprint
```

## Troubleshooting

### Debug Mode

Enable verbose logging to diagnose issues:

```bash
# Test sshd configuration
sudo sshd -t -f /etc/ssh/sshd_config.plue

# Run sshd in debug mode (foreground, single connection)
sudo /usr/sbin/sshd -d -f /etc/ssh/sshd_config.plue

# Connect with verbose client output
ssh -vvv git@localhost -p 2222
```

### Common Issues

#### "Permission denied (publickey)"

**Symptoms**: SSH authentication fails

**Causes & Solutions**:

1. SSH key not in database
   ```bash
   # Check keys in database
   psql plue -c "SELECT u.username, k.name, k.fingerprint FROM ssh_keys k JOIN users u ON k.user_id = u.id WHERE u.is_active = true;"
   ```

2. User not active
   ```sql
   UPDATE users SET is_active = true WHERE username = 'youruser';
   ```

3. authorized_keys_command.sh failing
   ```bash
   # Test as git user
   sudo -u git /opt/plue/scripts/authorized_keys_command.sh git

   # Check database connection
   sudo -u git psql "$DATABASE_URL" -c "SELECT 1"
   ```

4. Wrong permissions on scripts
   ```bash
   sudo chmod +x /opt/plue/scripts/*.sh
   sudo chown root:root /opt/plue/scripts/authorized_keys_command.sh
   ```

#### "Repository not found"

**Symptoms**: Git operations fail with repository not found

**Causes & Solutions**:

1. Repository doesn't exist
   ```bash
   ls -la /var/lib/plue/repos/user/repo
   ```

2. Missing .git directory
   ```bash
   # For colocated jj repos, ensure .git exists
   ls -la /var/lib/plue/repos/user/repo/.git
   ```

3. Wrong repository path
   ```bash
   # Should be: git@server:user/repo.git
   # Not: git@server:/user/repo.git (no leading slash)
   ```

4. Permissions issue
   ```bash
   sudo chown -R git:git /var/lib/plue/repos
   sudo chmod -R 755 /var/lib/plue/repos
   ```

#### "Access denied"

**Symptoms**: Authentication succeeds but git operation fails

**Causes & Solutions**:

1. No repository access
   - Check repository is public (for read) or user is collaborator
   - Verify user has write access (for push)

   ```sql
   -- Check repository access
   SELECT r.*, u.username as owner
   FROM repositories r
   JOIN users u ON r.owner_id = u.id
   WHERE u.username = 'owner' AND r.name = 'repo';

   -- Check collaborators
   SELECT u.username, c.permission
   FROM collaborators c
   JOIN users u ON c.user_id = u.id
   WHERE c.repo_id = (
     SELECT id FROM repositories WHERE name = 'repo'
   );
   ```

2. Repository is private
   ```sql
   -- Make repository public
   UPDATE repositories SET is_public = true WHERE name = 'repo';
   ```

#### "JJ sync not triggering"

**Symptoms**: Push succeeds but database not updated

**Causes & Solutions**:

1. Check jj-sync.log
   ```bash
   sudo tail -f /var/log/plue/jj-sync.log
   ```

2. Verify repo_watcher is running
   ```bash
   # Check if Zig server is running
   ps aux | grep server-zig

   # Check server logs
   journalctl -u plue-server -f
   ```

3. Test sync manually
   ```bash
   # Trigger sync via API (if implemented)
   curl -X POST http://localhost:8080/internal/sync \
     -H "Content-Type: application/json" \
     -d '{"owner":"user","repo":"repo"}'
   ```

### Log Files

Key log files for troubleshooting:

```bash
# SSH authentication logs
sudo tail -f /var/log/auth.log

# Git shell operations
sudo tail -f /var/log/plue/git-shell.log

# JJ sync operations
sudo tail -f /var/log/plue/jj-sync.log

# System journal (if using systemd)
sudo journalctl -u plue-sshd -f

# Zig server logs
sudo journalctl -u plue-server -f
```

## Performance Considerations

### Connection Pooling

For high-traffic deployments, consider:

1. **Database connection pooling**: The `authorized_keys_command.sh` opens a new database connection for each authentication. Use PgBouncer:

   ```bash
   sudo apt install pgbouncer
   # Configure in /etc/pgbouncer/pgbouncer.ini
   # Update DATABASE_URL to use PgBouncer port
   ```

2. **Caching authorized keys**: For very high traffic, cache authorized keys:

   ```bash
   # Create authorized_keys cache updater
   sudo tee /opt/plue/scripts/update_authorized_keys.sh > /dev/null <<'EOF'
   #!/bin/bash
   set -euo pipefail

   DATABASE_URL="${DATABASE_URL:-postgres://localhost/plue}"
   CACHE_FILE="/var/lib/plue/.ssh/authorized_keys_cache"

   mkdir -p "$(dirname "$CACHE_FILE")"

   psql "$DATABASE_URL" -t -A -c "
     SELECT 'no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ' || public_key
     FROM ssh_keys k
     JOIN users u ON k.user_id = u.id
     WHERE u.is_active = true
     ORDER BY k.id
   " > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"

   chmod 644 "$CACHE_FILE"
   EOF

   sudo chmod +x /opt/plue/scripts/update_authorized_keys.sh

   # Run every minute via cron
   echo "* * * * * /opt/plue/scripts/update_authorized_keys.sh" | sudo crontab -u git -

   # Update authorized_keys_command.sh to use cache
   # (with fallback to database)
   ```

## Migration from Native Zig SSH

If migrating from the experimental native Zig SSH implementation:

1. Stop the Zig SSH server
2. Follow setup instructions above
3. Update git remote URLs (if port changed)
4. Test with existing SSH keys (they should work as-is)

## Next Steps

After completing setup:

1. Test with all supported key types (RSA, Ed25519, ECDSA)
2. Set up monitoring for SSH connections
3. Configure log rotation for `/var/log/plue/`
4. Document host key fingerprints for users
5. Set up automated backups of `/var/lib/plue/repos/`

## References

- [OpenSSH sshd_config man page](https://man.openbsd.org/sshd_config)
- [OpenSSH AuthorizedKeysCommand](https://man.openbsd.org/sshd_config#AuthorizedKeysCommand)
- [Git Smart HTTP/SSH Protocols](https://git-scm.com/book/en/v2/Git-Internals-Transfer-Protocols)
- [GitHub SSH Key Requirements](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)

## Additional Resources

- Server implementation: `server/src/ssh/`
- Scripts: `server/scripts/`
- API routes: `server/src/routes/ssh_keys.zig`
- Database schema: `db/schema.sql` (ssh_keys table)
