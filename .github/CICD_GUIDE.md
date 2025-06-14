# Plue CI/CD Pipeline Guide

## Overview

This document describes the comprehensive CI/CD pipeline for Plue, a Swift-Zig hybrid macOS application. The pipeline is designed specifically for production macOS development with emphasis on security, quality, and automated releases.

## Workflow Architecture

### 🚀 Core Workflows

#### 1. **Quick Build & Test** (`build.yml`)
- **Triggers**: Push/PR to `main` or `develop`
- **Purpose**: Fast feedback for development
- **Runtime**: ~5-10 minutes
- **Features**:
  - Zig formatting validation
  - Quick compilation checks
  - Basic smoke tests
  - Nix environment validation
  - Debug artifact uploads

#### 2. **Comprehensive CI/CD** (`ci.yml`)
- **Triggers**: Push/PR to `main` or `develop`, and releases
- **Purpose**: Full testing and production builds
- **Runtime**: ~20-30 minutes
- **Features**:
  - Multi-matrix testing (Zig unit/integration/module tests)
  - Swift testing with coverage
  - Performance benchmarks
  - Integration testing
  - Production release builds
  - Automated release management

#### 3. **Security & Dependencies** (`security.yml`)
- **Triggers**: Daily schedule, push to `main`
- **Purpose**: Security monitoring and dependency management
- **Runtime**: ~10-15 minutes
- **Features**:
  - Dependency vulnerability scanning
  - CodeQL security analysis
  - Binary security analysis
  - Hardcoded secret detection
  - License compliance checks
  - Automated dependency update tracking

#### 4. **Release Pipeline** (`release.yml`)
- **Triggers**: Git tags (`v*.*.*`)
- **Purpose**: Automated production releases
- **Runtime**: ~30-45 minutes
- **Features**:
  - Multi-architecture builds (x64, ARM64, Universal)
  - Release asset creation
  - Automated release notes
  - Checksum generation
  - GitHub release publishing
  - Post-release notifications

#### 5. **Automated Maintenance** (`maintenance.yml`)
- **Triggers**: Weekly schedule, manual dispatch
- **Purpose**: Repository health and housekeeping
- **Runtime**: ~5-10 minutes
- **Features**:
  - Artifact cleanup with retention policies
  - Repository health monitoring
  - Dependency health reports
  - Build performance tracking
  - Automated issue management
  - Documentation completeness checks

## Development Workflow

### For Developers

#### Daily Development
1. **Push to feature branch** → Quick Build & Test runs
2. **Create PR** → Full CI/CD pipeline runs
3. **Merge to main** → All workflows run + security checks

#### Code Quality Gates
- ✅ Zig formatting (`zig fmt --check`)
- ✅ Compilation success (debug + release)
- ✅ All tests pass (Zig + Swift)
- ✅ Security scans clean
- ✅ No hardcoded secrets

#### Pre-commit Checklist
```bash
# Format code
zig fmt src/ test/ build.zig

# Run tests locally
zig build test

# Build and test
zig build swift
.build/release/plue --help
```

### For Releases

#### Creating a Release
1. **Tag the release**:
   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```

2. **Automatic process**:
   - Release workflow builds all targets
   - Creates GitHub release
   - Uploads signed binaries
   - Generates checksums
   - Creates installation script

#### Release Types
- **Stable**: `v1.2.3` → Full release
- **Beta**: `v1.2.3-beta.1` → Pre-release
- **Alpha**: `v1.2.3-alpha.1` → Pre-release

## Build Targets & Artifacts

### Build Matrix
- **Debug builds**: Fast compilation, debugging symbols
- **Release builds**: Optimized, production-ready
- **Architectures**: x86_64, ARM64, Universal binary

### Artifacts Generated
```
plue-v1.2.3-macos-x64.tar.gz       # Intel Macs
plue-v1.2.3-macos-arm64.tar.gz     # Apple Silicon
plue-v1.2.3-macos-universal.tar.gz # Universal binary
checksums.txt                       # SHA256 checksums
install.sh                          # Installation script
```

### Installation Distribution
Each release package contains:
- `plue` - Main executable
- `plue-cli` - CLI wrapper script
- `install.sh` - Installation script
- `README.md` - Documentation
- `LICENSE` - License file

## Security Features

### Automated Security Checks
- **CodeQL Analysis**: Swift code security scanning
- **Dependency Auditing**: Known vulnerability checking
- **Secret Detection**: Hardcoded credential scanning
- **Binary Analysis**: Security feature verification
- **License Compliance**: Legal requirement checking

### Security Policies
- **Artifact Retention**: 
  - Release artifacts: 90 days
  - Debug builds: 14 days
  - Test artifacts: 7 days
  - Security reports: 30 days

- **Access Control**:
  - Workflows require appropriate permissions
  - Secrets are properly scoped
  - Artifact access is controlled

## Performance Monitoring

### Build Performance
- **Build time tracking**: Monitor for regression
- **Binary size monitoring**: Track application bloat
- **Test execution time**: Ensure test suite efficiency
- **Cache effectiveness**: Nix cache hit rates

### Benchmarks
- **Startup time**: Application launch performance
- **Memory usage**: Runtime memory consumption
- **Binary analysis**: Security features enabled

## Troubleshooting

### Common Issues

#### Build Failures
```bash
# Check Zig formatting
zig fmt --check src/ test/ build.zig

# Verify Nix environment
nix develop --command zig version
nix develop --command swift --version

# Clean build
rm -rf .build zig-out .zig-cache
zig build swift
```

#### Test Failures
```bash
# Run specific test suites
zig build test-integration
zig build test-libplue
zig build test-farcaster

# Run Swift tests
swift test --parallel
```

#### Release Issues
```bash
# Check tag format
git tag -l | grep v1.2.3

# Verify release workflow
gh workflow run release.yml

# Manual release testing
tar -xzf plue-v1.2.3-macos-universal.tar.gz
cd plue-v1.2.3-macos-universal
./plue --help
```

### Debug Information
- **Workflow logs**: Available in GitHub Actions
- **Artifact inspection**: Download from Actions tab
- **Performance reports**: Generated weekly
- **Security reports**: Available in Security tab

## Monitoring & Alerts

### Automated Monitoring
- **Daily security scans**: Dependency vulnerabilities
- **Weekly maintenance**: Repository health
- **Build performance**: Size and time tracking
- **Issue management**: Stale issue cleanup

### Manual Monitoring
- **Release success**: Check GitHub releases
- **Test coverage**: Review coverage reports  
- **Security advisories**: Monitor GitHub Security tab
- **Performance trends**: Weekly performance reports

## Configuration

### Environment Variables
```yaml
MACOS_VERSION: "14"          # macOS runner version
XCODE_VERSION: "15.2"        # Xcode version
DEVELOPER_DIR: /Applications/Xcode_15.2.app/Contents/Developer
```

### Customization Points
- **Test timeout**: Adjust for longer tests
- **Retention policies**: Modify artifact cleanup
- **Security thresholds**: Set vulnerability limits
- **Performance baselines**: Define acceptable ranges

## Best Practices

### For Contributors
1. **Run tests locally** before pushing
2. **Follow conventional commits** for better release notes
3. **Keep PRs focused** for easier review
4. **Update tests** when adding features
5. **Document breaking changes** in PR description

### For Maintainers
1. **Review security reports** weekly
2. **Monitor build performance** trends
3. **Update dependencies** regularly
4. **Rotate secrets** periodically
5. **Archive old releases** when appropriate

## Integration Points

### External Services
- **GitHub Actions**: Primary CI/CD platform
- **Nix Cache**: Build acceleration
- **CodeQL**: Security analysis
- **Codecov**: Test coverage (optional)

### Local Development
```bash
# Set up development environment
nix develop

# Available commands
zig build          # Build Zig libraries
zig build swift    # Build complete application
zig build test     # Run all tests
zig build run      # Build and run application
```

## Metrics & KPIs

### Build Metrics
- **Success rate**: % of successful builds
- **Build time**: Average build duration
- **Test coverage**: Code coverage percentage
- **Binary size**: Application size tracking

### Security Metrics
- **Vulnerability count**: Known security issues
- **Scan frequency**: Security check cadence
- **Resolution time**: Time to fix issues
- **Compliance score**: License/policy adherence

### Release Metrics
- **Release frequency**: How often releases occur
- **Lead time**: Time from commit to release
- **Hotfix rate**: Emergency release frequency
- **Download metrics**: Release adoption tracking

---

## Quick Reference

### Workflow Status
- 🟢 **build.yml**: Quick feedback (5-10 min)
- 🔵 **ci.yml**: Full pipeline (20-30 min)  
- 🟡 **security.yml**: Security checks (10-15 min)
- 🟣 **release.yml**: Release process (30-45 min)
- ⚪ **maintenance.yml**: Weekly cleanup (5-10 min)

### Key Commands
```bash
# Local development
nix develop
zig build swift
.build/release/plue --help

# Release
git tag v1.2.3 && git push origin v1.2.3

# Manual workflow trigger
gh workflow run maintenance.yml
```

### Support
- **Documentation**: This file and workflow comments
- **Issues**: GitHub Issues for bug reports
- **Discussions**: GitHub Discussions for questions
- **Security**: Security tab for vulnerability reports