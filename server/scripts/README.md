# SSH Server Scripts

Shell scripts and configuration for the Git-over-SSH server. Provides Git protocol access with public key authentication.

## Key Files

| File | Purpose |
|------|---------|
| `authorized_keys_command.sh` | Dynamic SSH key lookup from database |
| `git-shell.sh` | Restricted shell for Git operations |
| `sshd_config.plue` | OpenSSH server configuration |
| `git-shell-commands/` | Allowed Git commands directory |

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                   SSH Git Server                           │
│                                                            │
│  Git Client (ssh git@plue.app)                             │
│         │                                                  │
│         ▼                                                  │
│  ┌──────────────────────────────────────────────────────┐ │
│  │              OpenSSH (sshd)                          │ │
│  │                                                      │ │
│  │  • Port 22                                           │ │
│  │  • PublicKey authentication only                    │ │
│  │  • AuthorizedKeysCommand                            │ │
│  └────────────────────┬─────────────────────────────────┘ │
│                       │                                   │
│                       ▼                                   │
│  ┌──────────────────────────────────────────────────────┐ │
│  │     authorized_keys_command.sh                       │ │
│  │                                                      │ │
│  │  • Query database for user's SSH keys               │ │
│  │  • Return authorized_keys format                    │ │
│  │  • Enforce restrictions (no-port-forwarding)        │ │
│  └────────────────────┬─────────────────────────────────┘ │
│                       │                                   │
│                       ▼                                   │
│  ┌──────────────────────────────────────────────────────┐ │
│  │           git-shell.sh                               │ │
│  │                                                      │ │
│  │  • Restricted shell environment                     │ │
│  │  • Only allows Git commands                         │ │
│  │  • Validates repository access                      │ │
│  └────────────────────┬─────────────────────────────────┘ │
│                       │                                   │
│                       ▼                                   │
│              Git Operations                               │
│        (push, pull, fetch, clone)                         │
└────────────────────────────────────────────────────────────┘
```

## SSH Key Authentication Flow

```
1. Git client initiates SSH connection
   $ git clone git@plue.app:owner/repo.git

2. OpenSSH calls authorized_keys_command.sh
   - Passes username and key fingerprint
   - Script queries PostgreSQL for user's public keys
   - Returns keys in authorized_keys format

3. If key matches, OpenSSH spawns git-shell.sh
   - Sets restricted environment
   - Only git-receive-pack and git-upload-pack allowed
   - Repository access validated

4. Git protocol operations execute
   - Push: git-receive-pack
   - Pull/Clone: git-upload-pack
   - Fetch: git-upload-pack

5. Connection terminates after operation
```

## Configuration

The `sshd_config.plue` file configures:

- Public key authentication only (no passwords)
- Dynamic key lookup via AuthorizedKeysCommand
- Restricted shell (git-shell.sh)
- No port forwarding, X11 forwarding, or agent forwarding
- Chroot or restricted directory access

## Security Features

| Feature | Description |
|---------|-------------|
| Key-only auth | No password authentication |
| Database lookup | SSH keys stored in PostgreSQL, not filesystem |
| Restricted shell | Only Git commands allowed |
| No forwarding | TCP/X11/Agent forwarding disabled |
| Command validation | git-shell.sh validates all commands |
