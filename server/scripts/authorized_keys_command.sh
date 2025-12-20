#!/usr/bin/env bash
# Plue SSH Authorized Keys Command
# Queries the database for authorized SSH public keys
#
# Usage: authorized_keys_command.sh <username>
#
# Configure in sshd_config:
#   AuthorizedKeysCommand /path/to/authorized_keys_command.sh
#   AuthorizedKeysCommandUser git

set -euo pipefail

USERNAME="$1"

# Only allow 'git' user (like GitHub)
if [ "$USERNAME" != "git" ]; then
    exit 1
fi

# Database connection (set via environment or config)
DATABASE_URL="${DATABASE_URL:-postgres://localhost/plue}"

# Query database for all active users' public keys
psql "$DATABASE_URL" -t -A -c "
    SELECT public_key
    FROM ssh_keys k
    JOIN users u ON k.user_id = u.id
    WHERE u.is_active = true
    ORDER BY k.id
" 2>/dev/null || exit 1
