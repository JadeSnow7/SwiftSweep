# SwiftSweep Development Workflow Quick Reference

## Initial Setup (One-time)

```bash
# Clone repository
git clone https://github.com/JadeSnow7/SwiftSweep.git
cd SwiftSweep

# Install development tools
./scripts/install_tools.sh

# Install pre-commit hooks
./scripts/install_hooks.sh

# Verify setup
./scripts/lint.sh
./scripts/format.sh --lint
swift test
```

## Daily Development

### Before Starting Work

```bash
# Pull latest changes
git pull origin main

# Check code quality
./scripts/lint.sh
./scripts/format.sh --lint
```

### During Development

```bash
# Run tests frequently
swift test

# Check specific test
swift test --filter TestName

# Auto-fix lint issues
./scripts/lint.sh --autocorrect

# Format code
./scripts/format.sh
```

### Before Committing

Pre-commit hooks will automatically run:
- SwiftLint (strict mode)
- SwiftFormat (lint mode)
- General checks (whitespace, large files, etc.)

If hooks fail, fix issues and commit again.

To skip hooks (NOT recommended):
```bash
git commit --no-verify
```

### Before Creating PR

```bash
# Run full quality checks
./scripts/lint.sh --strict
./scripts/format.sh --lint

# Run all tests
swift test

# Generate coverage report
./scripts/coverage_report.sh
open coverage_html/index.html

# Build project
swift build
```

## Common Tasks

### Code Quality

```bash
# Check code quality
./scripts/lint.sh

# Strict mode (warnings as errors)
./scripts/lint.sh --strict

# Auto-fix violations
./scripts/lint.sh --autocorrect

# Check formatting
./scripts/format.sh --lint

# Preview format changes
./scripts/format.sh --dryrun

# Apply formatting
./scripts/format.sh
```

### Testing

```bash
# Run all tests
swift test

# Run specific test file
swift test --filter CleanupEngineTests

# Run specific test
swift test --filter testScanForCleanableItems

# Generate coverage
./scripts/coverage_report.sh

# View coverage report
open coverage_html/index.html
```

### Documentation

```bash
# Generate docs for local preview
./scripts/generate_docs.sh

# Generate docs for GitHub Pages
./scripts/generate_docs.sh --static

# View generated docs
open docs/api/index.html
```

### Building

```bash
# Build all targets
swift build

# Build specific target
swift build --target SwiftSweepCore

# Build release
swift build -c release

# Run CLI
swift run swiftsweep --help

# Run GUI
swift run SwiftSweepApp
```

## Troubleshooting

### Tools Not Found

```bash
# Reinstall tools
./scripts/install_tools.sh

# Check installation
which swiftlint
which swiftformat
which pre-commit
```

### Hooks Not Running

```bash
# Reinstall hooks
./scripts/install_hooks.sh

# Verify hooks
ls -la .git/hooks/pre-commit
```

### Tests Failing

```bash
# Clean build
rm -rf .build
swift build

# Run tests with verbose output
swift test --verbose
```

### Coverage Report Fails

```bash
# Ensure tests pass first
swift test

# Install lcov (optional)
brew install lcov

# Generate coverage
./scripts/coverage_report.sh
```

## Git Workflow

### Feature Branch

```bash
# Create feature branch
git checkout -b feature/my-feature

# Make changes and commit
git add .
git commit -m "feat: Add new feature"

# Push to remote
git push origin feature/my-feature

# Create PR on GitHub
```

### Commit Message Format

Follow conventional commits:

```
feat: Add new feature
fix: Fix bug in cleanup engine
docs: Update API documentation
test: Add tests for uninstall engine
refactor: Refactor state management
chore: Update dependencies
style: Format code
perf: Improve scan performance
```

## Code Style

### SwiftLint Rules

- 2-space indentation
- 120 character line length
- No force unwrapping (use `guard` or `if let`)
- Explicit error messages for `fatalError`
- Cyclomatic complexity < 15 (warning), < 25 (error)

### SwiftFormat Rules

- 2-space indentation
- K&R brace style
- Remove redundant `self` (except in closures)
- Consistent spacing and alignment

## Documentation Style

### Public APIs

```swift
/// Brief description of the function.
///
/// Detailed description with multiple paragraphs if needed.
///
/// - Parameters:
///   - param1: Description of param1
///   - param2: Description of param2
/// - Returns: Description of return value
/// - Throws: Description of errors thrown
///
/// ## Example
///
/// ```swift
/// let result = try await function(param1: value1, param2: value2)
/// ```
public func function(param1: Type1, param2: Type2) async throws -> ReturnType {
  // Implementation
}
```

## Performance Tips

### Parallel Testing

```bash
# Run tests in parallel
swift test --parallel
```

### Incremental Builds

```bash
# Build only changed files
swift build
```

### Cache Cleaning

```bash
# Clean build cache
rm -rf .build

# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData
```

## Resources

- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)
- [SwiftFormat Rules](https://github.com/nicklockwood/SwiftFormat/blob/main/Rules.md)
- [DocC Documentation](https://www.swift.org/documentation/docc/)
- [Swift Package Manager](https://www.swift.org/package-manager/)

## Quick Links

- [README.md](../README.md) - Project overview
- [TESTING.md](TESTING.md) - Testing guidelines
- [PHASE1_IMPLEMENTATION.md](PHASE1_IMPLEMENTATION.md) - Phase 1 details
- [scripts/README.md](../scripts/README.md) - Script documentation

---

**Last Updated:** 2026-02-06
