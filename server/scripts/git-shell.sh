#!/usr/bin/env bash
# Plue Git Shell
# Handles git-upload-pack and git-receive-pack commands via SSH
#
# This script is used as ForceCommand in sshd_config

set -euo pipefail

# Repository base directory
REPOS_DIR="${PLUE_REPOS_DIR:-/var/lib/plue/repos}"

# Original SSH command
COMMAND="$SSH_ORIGINAL_COMMAND"

# Log directory
LOG_DIR="${PLUE_LOG_DIR:-/var/log/plue}"
mkdir -p "$LOG_DIR"

# Log the command
echo "$(date -Iseconds) - $USER - $COMMAND" >> "$LOG_DIR/git-shell.log"

# Parse command
case "$COMMAND" in
    git-upload-pack\ *)
        # Extract repo path from "git-upload-pack '/user/repo.git'"
        REPO_PATH=$(echo "$COMMAND" | sed -n "s/^git-upload-pack '\/*\([^']*\)'$/\1/p")
        if [ -z "$REPO_PATH" ]; then
            echo "Error: Invalid git-upload-pack command" >&2
            exit 1
        fi

        # Remove .git suffix
        REPO_PATH="${REPO_PATH%.git}"

        # Full path to repository
        FULL_PATH="$REPOS_DIR/$REPO_PATH"

        if [ ! -d "$FULL_PATH" ]; then
            echo "Error: Repository not found: $REPO_PATH" >&2
            exit 1
        fi

        # Execute git-upload-pack
        exec /usr/bin/git-upload-pack "$FULL_PATH"
        ;;

    git-receive-pack\ *)
        # Extract repo path from "git-receive-pack '/user/repo.git'"
        REPO_PATH=$(echo "$COMMAND" | sed -n "s/^git-receive-pack '\/*\([^']*\)'$/\1/p")
        if [ -z "$REPO_PATH" ]; then
            echo "Error: Invalid git-receive-pack command" >&2
            exit 1
        fi

        # Remove .git suffix
        REPO_PATH="${REPO_PATH%.git}"

        # Full path to repository
        FULL_PATH="$REPOS_DIR/$REPO_PATH"

        if [ ! -d "$FULL_PATH" ]; then
            echo "Error: Repository not found: $REPO_PATH" >&2
            exit 1
        fi

        # Execute git-receive-pack
        /usr/bin/git-receive-pack "$FULL_PATH"
        EXIT_CODE=$?

        # Trigger jj sync if push succeeded
        if [ $EXIT_CODE -eq 0 ]; then
            # Parse user and repo from path
            USER_NAME=$(echo "$REPO_PATH" | cut -d'/' -f1)
            REPO_NAME=$(echo "$REPO_PATH" | cut -d'/' -f2)

            # Trigger sync (async via background process)
            (
                echo "$(date -Iseconds) - Triggering jj sync for $USER_NAME/$REPO_NAME" >> "$LOG_DIR/jj-sync.log"

                # Call Plue API to trigger sync
                API_URL="${PLUE_API_URL:-http://localhost:8080}"
                SYNC_URL="$API_URL/api/watcher/sync/$USER_NAME/$REPO_NAME"

                curl -X POST -s -f -m 5 "$SYNC_URL" >> "$LOG_DIR/jj-sync.log" 2>&1 || {
                    echo "$(date -Iseconds) - Failed to trigger sync for $USER_NAME/$REPO_NAME" >> "$LOG_DIR/jj-sync.log"
                }
            ) &
        fi

        exit $EXIT_CODE
        ;;

    *)
        echo "Error: Command not supported: $COMMAND" >&2
        echo "Plue only supports git-upload-pack and git-receive-pack" >&2
        exit 1
        ;;
esac
