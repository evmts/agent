# SSH Server Implementation for Plue

This document describes the SSH server implementation for Plue's Git operations over SSH.

## Overview

The SSH implementation provides Git repository access via SSH protocol, similar to GitHub/GitLab. Users authenticate using SSH public keys stored in the database, and the `git` user is used for all operations.

## Architecture

The implementation consists of two approaches:

### 1. Native Zig Implementation (Experimental)

Located in `src/ssh/`, this is a native Zig implementation with the following components:

- **`src/ssh/types.zig`**: SSH protocol types and constants (RFC 4253, RFC 4252, RFC 4254)
- **`src/ssh/auth.zig`**: Public key authentication against the database
- **`src/ssh/session.zig`**: Session handler for `git-upload-pack` and `git-receive-pack`
- **`src/ssh/server.zig`**: Main SSH server with TCP socket handling

**Status**: Basic TCP connection handling implemented. Full SSH protocol implementation requires:
- Key exchange (KEX) with Diffie-Hellman
- Session key derivation
- Packet encryption/MAC
- Channel management
- Exec request handling

**For production**, consider integrating:
- [libssh2](https://github.com/mattnite/zig-libssh2) - C library with Zig bindings
- [MiSSHod](https://github.com/ringtailsoftware/misshod) - Pure Zig SSH library (experimental)
- [ZSSH](https://git.sr.ht/~mulling/zssh) - SUSE's Zig SSH implementation (in development)

### 2. OpenSSH Integration (Production-Ready)

Located in `scripts/`, this approach leverages OpenSSH's `sshd` for protocol handling while implementing authentication and command execution in Plue.

**Components**:
- **`scripts/authorized_keys_command.sh`**: Queries database for authorized keys
- **`scripts/git-shell.sh`**: Handles git commands with repository validation
- **`scripts/sshd_config.plue`**: Sample SSH server configuration

## Configuration

### Environment Variables

```bash
# Enable SSH server (Zig implementation)
SSH_ENABLED=true

# SSH server host and port
SSH_HOST=0.0.0.0
SSH_PORT=2222

# Repository directory
PLUE_REPOS_DIR=/var/lib/plue/repos

# Database connection
DATABASE_URL=postgres://user:pass@localhost:5432/plue
```

### Database Schema

SSH keys are stored in the `ssh_keys` table:

```sql
CREATE TABLE ssh_keys (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  fingerprint VARCHAR(255) NOT NULL UNIQUE,
  public_key TEXT NOT NULL,
  key_type VARCHAR(32) NOT NULL DEFAULT 'user',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_ssh_keys_fingerprint ON ssh_keys(fingerprint);
CREATE INDEX idx_ssh_keys_user_id ON ssh_keys(user_id);
```

## Usage

### Option 1: Native Zig Server (Experimental)

```bash
# Build the server
zig build

# Run with SSH enabled
SSH_ENABLED=true zig build run
```

This starts the experimental SSH server on port 2222. Note: Full protocol implementation is not yet complete.

### Option 2: OpenSSH Integration (Recommended)

#### Setup

1. **Create `git` user**:
   ```bash
   sudo useradd -r -m -d /var/lib/plue -s /bin/bash git
   ```

2. **Set up directories**:
   ```bash
   sudo mkdir -p /var/lib/plue/repos
   sudo mkdir -p /var/log/plue
   sudo chown -R git:git /var/lib/plue /var/log/plue
   ```

3. **Install scripts**:
   ```bash
   sudo mkdir -p /opt/plue/scripts
   sudo cp scripts/*.sh /opt/plue/scripts/
   sudo chmod +x /opt/plue/scripts/*.sh
   ```

4. **Generate host keys**:
   ```bash
   sudo ssh-keygen -t rsa -b 4096 -f /var/lib/plue/ssh_host_rsa_key -N ""
   sudo ssh-keygen -t ed25519 -f /var/lib/plue/ssh_host_ed25519_key -N ""
   ```

5. **Configure SSH**:
   ```bash
   # Option A: Separate SSH instance (recommended for development)
   sudo /usr/sbin/sshd -f scripts/sshd_config.plue -D

   # Option B: System SSH (production)
   sudo cp scripts/sshd_config.plue /etc/ssh/sshd_config.d/plue.conf
   sudo systemctl restart sshd
   ```

#### Testing

```bash
# Add your SSH key to Plue via the API
curl -X POST http://localhost:4000/api/ssh-keys \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "My Key",
    "publicKey": "ssh-rsa AAAAB3NzaC1yc2E... user@host"
  }'

# Clone a repository
git clone git@localhost:alice/myrepo.git

# Push changes
cd myrepo
git add .
git commit -m "Update"
git push origin main
```

## Git Commands

The SSH server supports two Git commands:

### `git-upload-pack` (Clone/Fetch)

```bash
git clone git@server:user/repo.git
git fetch origin
```

**Access Control**: Public repositories allow anyone, private repositories require read access.

### `git-receive-pack` (Push)

```bash
git push origin main
```

**Access Control**: Requires write or admin access to the repository.

**Post-Push Hook**: After a successful push, the server triggers JJ sync to update the database.

## Authentication Flow

1. Client connects via SSH
2. Client presents public key
3. Server calls `authorized_keys_command.sh` which queries database
4. Server validates key fingerprint matches database
5. If valid, connection authenticated as `git` user
6. Client can execute git commands

## Security Considerations

1. **Host Key Verification**: Always verify the host key fingerprint on first connection
2. **Key Management**: Rotate SSH keys regularly via the API
3. **Access Control**: Repository access is enforced at the database level
4. **Audit Logging**: All git operations are logged to `/var/log/plue/git-shell.log`
5. **Network Security**: Use firewall rules to restrict SSH access
6. **User Isolation**: The `git` user should have minimal privileges

## Troubleshooting

### Debug SSH Authentication

```bash
# Test SSH connection
ssh -vvv git@localhost -p 2222

# Check authorized keys command
sudo -u git /opt/plue/scripts/authorized_keys_command.sh git

# View SSH logs
sudo journalctl -u sshd -f

# View git-shell logs
sudo tail -f /var/log/plue/git-shell.log
```

### Common Issues

**"Permission denied (publickey)"**
- Verify key is added to database
- Check key fingerprint matches
- Ensure user is active in database
- Verify `authorized_keys_command.sh` has database access

**"Repository not found"**
- Check repository path: `/var/lib/plue/repos/user/repo`
- Verify `.git` directory exists
- Check file permissions

**"Access denied"**
- Verify user has read/write access to repository
- Check collaborators table for permissions
- Ensure repository is not private (for read access)

## Future Improvements

1. **Complete Native Implementation**: Finish the Zig SSH protocol implementation
2. **Deploy Keys**: Support read-only deploy keys for CI/CD
3. **SSH Certificates**: Use SSH certificates instead of public keys
4. **Git LFS**: Support Git Large File Storage over SSH
5. **Performance**: Connection pooling and caching for high-traffic scenarios
6. **Monitoring**: Prometheus metrics for SSH connections and git operations

## References

- [RFC 4253 - SSH Transport Layer Protocol](https://www.rfc-editor.org/rfc/rfc4253)
- [RFC 4252 - SSH Authentication Protocol](https://www.rfc-editor.org/rfc/rfc4252)
- [RFC 4254 - SSH Connection Protocol](https://www.rfc-editor.org/rfc/rfc4254)
- [OpenSSH Documentation](https://www.openssh.com/manual.html)
- [Git Transfer Protocols](https://git-scm.com/book/en/v2/Git-Internals-Transfer-Protocols)
- [libssh2 Zig Bindings](https://github.com/mattnite/zig-libssh2)
- [MiSSHod - Minimal SSH in Zig](https://github.com/ringtailsoftware/misshod)
- [ZSSH - SUSE's Zig SSH](https://git.sr.ht/~mulling/zssh)
