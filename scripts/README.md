# SwiftSweep Development Scripts

This directory contains scripts for code quality, testing, and documentation.

## Quick Start

```bash
# Install all development tools
./scripts/install_tools.sh

# Set up pre-commit hooks
./scripts/install_hooks.sh
```

## Scripts Overview

### Code Quality

#### `lint.sh`
Run SwiftLint to check code quality.

```bash
# Basic lint check
./scripts/lint.sh

# Strict mode (warnings as errors)
./scripts/lint.sh --strict

# Auto-fix violations
./scripts/lint.sh --autocorrect
```

#### `format.sh`
Run SwiftFormat to check/fix code formatting.

```bash
# Check formatting (no changes)
./scripts/format.sh --lint

# Preview changes
./scripts/format.sh --dryrun

# Format code
./scripts/format.sh

# Format specific path
./scripts/format.sh Sources/SwiftSweepCore
```

### Testing & Coverage

#### `coverage_report.sh`
Generate code coverage reports.

```bash
# Run tests and generate coverage
./scripts/coverage_report.sh

# View HTML report
open coverage_html/index.html
```

Requirements:
- `lcov` (optional, for HTML reports): `brew install lcov`

### Documentation

#### `generate_docs.sh`
Generate DocC API documentation.

```bash
# Generate for local preview
./scripts/generate_docs.sh

# Generate for GitHub Pages
./scripts/generate_docs.sh --static
```

The static documentation will be generated in `docs/api/` and can be deployed to GitHub Pages.

### Installation

#### `install_tools.sh`
Install all development tools (SwiftLint, SwiftFormat, pre-commit).

```bash
./scripts/install_tools.sh
```

#### `install_hooks.sh`
Install pre-commit hooks.

```bash
./scripts/install_hooks.sh
```

Hooks will run automatically on `git commit`:
- SwiftLint (strict mode)
- SwiftFormat (lint mode)
- Trailing whitespace check
- Large file detection
- Private key detection

To skip hooks (not recommended):
```bash
git commit --no-verify
```

## Configuration Files

- `.swiftlint.yml` - SwiftLint rules
- `.swiftformat` - SwiftFormat rules
- `.swift-version` - Swift version (5.9)
- `.pre-commit-config.yaml` - Pre-commit hook configuration

## CI/CD Integration

These scripts are designed to work in CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Lint
  run: ./scripts/lint.sh --strict

- name: Format Check
  run: ./scripts/format.sh --lint

- name: Test with Coverage
  run: ./scripts/coverage_report.sh
```

## Troubleshooting

### SwiftLint/SwiftFormat not found

Install via Homebrew:
```bash
brew install swiftlint swiftformat
```

Or run:
```bash
./scripts/install_tools.sh
```

### Pre-commit hooks not running

Reinstall hooks:
```bash
./scripts/install_hooks.sh
```

### Coverage report fails

Ensure tests pass first:
```bash
swift test
```

Then generate coverage:
```bash
./scripts/coverage_report.sh
```

## Development Workflow

1. **Before starting work:**
   ```bash
   ./scripts/install_tools.sh
   ./scripts/install_hooks.sh
   ```

2. **During development:**
   - Hooks run automatically on commit
   - Or run manually: `./scripts/lint.sh && ./scripts/format.sh --lint`

3. **Before submitting PR:**
   ```bash
   ./scripts/lint.sh --strict
   ./scripts/format.sh --lint
   ./scripts/coverage_report.sh
   swift test
   ```

4. **Updating documentation:**
   ```bash
   ./scripts/generate_docs.sh --static
   git add docs/api/
   git commit -m "docs: Update API documentation"
   ```

## See Also

- [TESTING.md](../docs/TESTING.md) - Testing guidelines
- [CONTRIBUTING.md](../CONTRIBUTING.md) - Contribution guidelines (if exists)
- [README.md](../README.md) - Project overview
