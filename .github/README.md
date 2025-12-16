# GitHub Actions & CI/CD

This directory contains GitHub Actions workflows for building and releasing the agent.

## Workflows

### `release.yml`

Triggered on version tags (`v*`). Builds platform-specific binaries and publishes to GitHub Releases and npm.

**Trigger:**
```bash
git tag v1.0.0
git push --tags
```

**Build Matrix:**

| Target | Runner | Output |
|--------|--------|--------|
| darwin-arm64 | `macos-14` | agent-darwin-arm64.tar.gz |
| darwin-amd64 | `macos-13` | agent-darwin-amd64.tar.gz |
| linux-amd64 | `ubuntu-latest` | agent-linux-amd64.tar.gz |
| linux-arm64 | `ubuntu-24.04-arm64` | agent-linux-arm64.tar.gz |

**Jobs:**
1. `build` - Builds PyInstaller + Go binary for each platform
2. `release` - Creates GitHub Release with all artifacts
3. `publish-npm` - Publishes `@tevm/agent` to npm registry

## Required Secrets

Configure these in **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Description | How to Obtain |
|--------|-------------|---------------|
| `NPM_TOKEN` | npm automation token for publishing `@tevm/agent` | [npmjs.com](https://www.npmjs.com) → Access Tokens → Generate New Token → Automation |

## Required Permissions

The workflow uses `GITHUB_TOKEN` (automatically provided) with `contents: write` permission to create releases.

## First-Time Setup

### 1. Create npm Organization

If the `@tevm` org doesn't exist on npm:

```bash
npm login
npm org create tevm
```

### 2. Generate npm Token

1. Go to [npmjs.com](https://www.npmjs.com) and log in
2. Click your profile → Access Tokens
3. Generate New Token → Automation (for CI/CD)
4. Copy the token

### 3. Add Secret to GitHub

1. Go to your repo → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `NPM_TOKEN`
4. Value: paste the npm token
5. Click "Add secret"

### 4. Create Your First Release

```bash
# Ensure all changes are committed
git add .
git commit -m "Prepare v0.1.0 release"

# Create and push tag
git tag v0.1.0
git push origin main
git push --tags
```

## Environment Variables (Runtime)

These are set by the workflow during build, not secrets you need to configure:

| Variable | Description | Set By |
|----------|-------------|--------|
| `GOOS` | Target OS (darwin/linux) | Build matrix |
| `GOARCH` | Target architecture (amd64/arm64) | Build matrix |
| `CGO_ENABLED` | Disable CGO for static binaries | Workflow |

## Troubleshooting

### Build fails on PyInstaller step

- Ensure all Python dependencies are in `pyproject.toml`
- Check hidden imports in the workflow match `build.zig`

### npm publish fails

- Verify `NPM_TOKEN` secret is set correctly
- Ensure `@tevm` org exists and your npm account has publish access
- Check token hasn't expired

### Release not created

- Ensure tag follows `v*` pattern (e.g., `v1.0.0`, `v0.1.0-beta`)
- Check `GITHUB_TOKEN` has `contents: write` permission

## Local Testing

To test the build locally before pushing:

```bash
# Build everything (same as CI)
zig build

# Or build components separately
zig build pyinstaller  # Python server only
zig build build-go     # Go TUI only
```
