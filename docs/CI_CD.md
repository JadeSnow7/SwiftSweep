# CI/CD Pipeline Documentation

## Overview

SwiftSweep uses GitHub Actions for continuous integration and deployment. The CI/CD pipeline ensures code quality, security, and reliability through automated checks.

## Workflows

### 1. PR Tests (`pr-tests.yml`)

**Triggers:**
- Pull requests to `main` branch
- Pushes to `main` branch

**Jobs:**

#### Lint Job
- Installs SwiftLint via Homebrew
- Runs `./scripts/lint.sh --strict`
- Fails on any warnings or errors

#### Format Job
- Installs SwiftFormat via Homebrew
- Runs `./scripts/format.sh --lint`
- Fails if code is not properly formatted

#### Build Job
- Sets up Xcode 15.0
- Builds in both Debug and Release configurations
- Ensures code compiles successfully

#### Test Job
- Runs all unit tests with coverage enabled
- Generates coverage report using lcov
- Uploads coverage to Codecov (if token configured)
- Comments coverage report on PR

#### Security Job
- Runs pre-commit security checks
- Detects private keys
- Checks for large files

**Required Secrets:**
- `CODECOV_TOKEN` (optional) - For coverage reporting

### 2. CodeQL Security Analysis (`codeql.yml`)

**Triggers:**
- Pull requests to `main` branch
- Pushes to `main` branch
- Weekly schedule (Mondays at 00:00 UTC)

**Jobs:**

#### Analyze Job
- Initializes CodeQL for Swift
- Builds project in Release mode
- Performs security and quality analysis
- Reports findings to GitHub Security tab

**Features:**
- Detects security vulnerabilities
- Identifies code quality issues
- Provides automated security alerts

### 3. Build and Notarize (`build-notarize.yml`)

**Triggers:**
- Git tags matching `v*` pattern
- Manual workflow dispatch

**Jobs:**

#### Build and Notarize Job
- Imports code signing certificate
- Builds universal binary (arm64 + x86_64)
- Signs application with Developer ID
- Notarizes with Apple
- Staples notarization ticket
- Creates DMG
- Uploads artifacts
- Creates GitHub release

**Required Secrets:**
- `MACOS_CERTIFICATE` - Base64-encoded Developer ID certificate
- `MACOS_CERTIFICATE_PWD` - Certificate password
- `SIGNING_IDENTITY` - Developer ID identity name
- `APPLE_ID` - Apple ID for notarization
- `APPLE_TEAM_ID` - Apple Developer Team ID
- `APPLE_APP_PASSWORD` - App-specific password

### 4. Dependabot (`dependabot.yml`)

**Schedule:**
- Weekly updates (Mondays at 09:00)

**Monitored:**
- Swift Package Manager dependencies
- GitHub Actions versions

**Configuration:**
- Maximum 5 open PRs per ecosystem
- Automatic labels: `dependencies`, `swift`, `github-actions`
- Commit message prefix: `chore`

## Branch Protection Rules

### Recommended Settings for `main` Branch

1. **Require pull request reviews:**
   - Required approving reviews: 1
   - Dismiss stale reviews when new commits are pushed

2. **Require status checks to pass:**
   - SwiftLint
   - SwiftFormat
   - Build
   - Test with Coverage

3. **Require branches to be up to date:**
   - Enabled

4. **Restrictions:**
   - No force pushes
   - No deletions

### Setup Instructions

1. Go to repository Settings → Branches
2. Add branch protection rule for `main`
3. Enable the settings above
4. Save changes

## Local Development

### Pre-commit Hooks

Install pre-commit hooks to run checks locally:

```bash
./scripts/install_hooks.sh
```

This ensures code quality before pushing to remote.

### Manual CI Checks

Run the same checks locally before creating a PR:

```bash
# Lint check
./scripts/lint.sh --strict

# Format check
./scripts/format.sh --lint

# Build
swift build -c debug
swift build -c release

# Tests with coverage
./scripts/coverage_report.sh
```

## Coverage Reporting

### Codecov Integration (Optional)

1. Sign up at [codecov.io](https://codecov.io)
2. Add repository
3. Get upload token
4. Add `CODECOV_TOKEN` to repository secrets
5. Coverage reports will be automatically uploaded

### Viewing Coverage

- **Local:** `open coverage_html/index.html`
- **CI:** Check PR comments for coverage report
- **Codecov:** View detailed coverage at codecov.io

## Security Scanning

### CodeQL

- Runs automatically on PRs and weekly
- View results in Security → Code scanning alerts
- Provides automated security vulnerability detection

### Dependabot

- Automatically creates PRs for dependency updates
- Security updates are prioritized
- Review and merge dependency PRs regularly

## Troubleshooting

### Lint Failures

```bash
# Auto-fix violations
./scripts/lint.sh --autocorrect

# Check specific file
swiftlint lint --path Sources/SwiftSweepCore/SomeFile.swift
```

### Format Failures

```bash
# Preview changes
./scripts/format.sh --dryrun

# Apply formatting
./scripts/format.sh
```

### Test Failures

```bash
# Run tests locally
swift test

# Run specific test
swift test --filter TestName

# Verbose output
swift test --verbose
```

### Build Failures

```bash
# Clean build
rm -rf .build
swift build

# Check for package issues
swift package resolve
swift package update
```

## Performance Optimization

### Caching

GitHub Actions automatically caches:
- Swift Package Manager dependencies
- Build artifacts

### Parallel Execution

Jobs run in parallel when possible:
- Lint, Format, Build, Test run concurrently
- Reduces total CI time

### Conditional Execution

- CodeQL runs weekly (not on every PR)
- Build and Notarize only on releases
- Coverage upload only if token configured

## Monitoring

### GitHub Actions Dashboard

View workflow runs at:
`https://github.com/JadeSnow7/SwiftSweep/actions`

### Status Badges

Add to README.md:

```markdown
![PR Tests](https://github.com/JadeSnow7/SwiftSweep/workflows/PR%20Tests/badge.svg)
![CodeQL](https://github.com/JadeSnow7/SwiftSweep/workflows/CodeQL%20Security%20Analysis/badge.svg)
```

## Best Practices

1. **Always run local checks before pushing**
2. **Keep dependencies up to date** (review Dependabot PRs)
3. **Monitor CodeQL alerts** (fix security issues promptly)
4. **Maintain test coverage** (aim for 80%+)
5. **Review CI failures** (don't merge failing PRs)
6. **Use conventional commits** (helps with changelog generation)

## Future Enhancements

- [ ] Performance benchmarking in CI
- [ ] Automated changelog generation
- [ ] Nightly builds
- [ ] Integration tests on real macOS VMs
- [ ] Automated release notes generation
- [ ] Slack/Discord notifications for CI failures

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [CodeQL for Swift](https://codeql.github.com/docs/codeql-language-guides/codeql-for-swift/)
- [Dependabot Documentation](https://docs.github.com/en/code-security/dependabot)
- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)
- [SwiftFormat Rules](https://github.com/nicklockwood/SwiftFormat/blob/main/Rules.md)

---

**Last Updated:** 2026-02-06
