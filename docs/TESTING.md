# SwiftSweep Testing Guide

This document defines the local standard test flow and optional checks.

## 1. Standard local flow

```bash
./ci_scripts/local_test.sh
```

By default, this runs `swift test`.

Optional flags:
- `--with-xcodegen`: generate the Xcode project if xcodegen is installed.
- `--with-cli-smoke`: run read-only CLI smoke checks.
- `--with-es-fallback-check`: run an additional compile/test pass with `SWIFTSWEEP_NO_ENDPOINT_SECURITY`.

## 2. Unit tests

```bash
swift test
```

Note: tests use SwiftPM and may read system metrics and scan paths, so they can take longer.

### 2.1 EndpointSecurity fallback check (optional)

```bash
swift test -Xswiftc -DSWIFTSWEEP_NO_ENDPOINT_SECURITY
```

Use this only when you need to verify the explicit no-EndpointSecurity fallback branch in restricted environments.

## 3. CLI smoke (optional)

```bash
swift run swiftsweep status
swift run swiftsweep peripherals --json
swift run swiftsweep peripherals --json --sensitive
swift run swiftsweep diagnostics
swift run swiftsweep clean --dry-run
```

Notes:
- `clean --dry-run` does not delete files.
- `peripherals --json` should keep fixed keys and use `null` for unavailable optional fields.

## 4. CleanupEngine E2E fixtures (optional)

```bash
./scripts/setup_e2e_fixtures.sh
swift run swiftsweep clean --dry-run
./scripts/cleanup_e2e_fixtures.sh
```

Notes:
- The scripts invoke `sudo`, do not run them as root.
- Use `STANDARD_USER=<username>` to create the standard user attack fixture.
- Always run cleanup to remove `/Library/Logs/SwiftSweepE2E` after testing.
