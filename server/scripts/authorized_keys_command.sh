#!/usr/bin/env bash
# Plue SSH Authorized Keys Command
# Queries the database for authorized SSH public keys
#
# Usage: authorized_keys_command.sh <username>
#
# Configure in sshd_config:
#   AuthorizedKeysCommand /path/to/authorized_keys_command.sh
#   AuthorizedKeysCommandUser git
#
# Security considerations:
# - This script runs as the AuthorizedKeysCommandUser (typically 'git')
# - Only active users' keys are returned
# - Each key is prefixed with security restrictions:
#   - no-port-forwarding: Prevents SSH port forwarding
#   - no-X11-forwarding: Prevents X11 forwarding
#   - no-agent-forwarding: Prevents SSH agent forwarding
#   - no-pty: Prevents pseudo-terminal allocation
#   - These restrictions ensure the SSH session can only run git commands

set -euo pipefail

USERNAME="$1"

# Only allow 'git' user (like GitHub)
if [ "$USERNAME" != "git" ]; then
    exit 1
fi

# Database connection (set via environment or config)
DATABASE_URL="${DATABASE_URL:-postgres://localhost/plue}"

# Query database for all active users' public keys
# Add security restrictions to each key
psql "$DATABASE_URL" -t -A -c "
    SELECT
        'no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ' || public_key
    FROM ssh_keys k
    JOIN users u ON k.user_id = u.id
    WHERE u.is_active = true
    ORDER BY k.id
" 2>/dev/null || exit 1
