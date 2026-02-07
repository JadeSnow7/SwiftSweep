# SwiftSweep 外设检测收口：PR 归档草案

## 范围说明

- 本次仅做外设检测与 Apple Diagnostics 引导入口的收口，不扩展新功能面。
- Public API 与 CLI JSON 契约保持冻结：
  - `peripherals [--json] [--sensitive]`
  - `diagnostics [--open-support]`
  - fixed keys + optional `null` + `collected_at` ISO8601

## 已执行验证（2026-02-07）

### Build / Test

- `swift build` ✅
- `swift test` ✅（90 tests, 0 failures）
- `swift test -Xswiftc -DSWIFTSWEEP_NO_ENDPOINT_SECURITY` ✅（90 tests, 0 failures）

### CLI Smoke

- `swift run swiftsweep peripherals --json` ✅
- `swift run swiftsweep peripherals --json --sensitive` ✅
- `swift run swiftsweep diagnostics` ✅

## 非阻塞告警（后续任务）

1. SwiftPM 资源告警  
   - 现象：`Helper/Info.plist` unhandled resource warning  
   - 影响：不阻塞构建与测试  
   - 后续建议：在 `Package.swift` 中补充资源声明或显式 exclude 规则。

2. Swift 6 兼容性预警  
   - 现象：`Sources/SwiftSweepCore/Git/GitRepoCleaner.swift` 中 async context 的 iterator 警告  
   - 影响：当前不阻塞，但未来 Swift 6 模式可能升级为错误  
   - 后续建议：重构该处异步遍历实现，消除 `makeIterator` 异步上下文警告。

## 可直接粘贴的 PR 描述

### Summary
- Finalize peripherals + Apple Diagnostics closeout without expanding scope.
- Keep core API/CLI schema frozen.
- Complete release gates (build/test/CLI smoke) and archive non-blocking warnings.

### What Changed
- Restore EndpointSecurity default availability with explicit fallback gate.
- Fix CLI `isBuiltin` tri-state text semantics (`Built-in` / `External` / `Unknown`).
- Finish peripherals sheet localization cleanup (`N/A` and device-kind labels).
- Add tests for CLI tri-state formatting and UI device-kind localization.
- Sync docs/scripts for optional ES fallback validation command.

### Validation
- `swift build`
- `swift test`
- `swift test -Xswiftc -DSWIFTSWEEP_NO_ENDPOINT_SECURITY`
- `swift run swiftsweep peripherals --json`
- `swift run swiftsweep peripherals --json --sensitive`
- `swift run swiftsweep diagnostics`

All passed on 2026-02-07.

### Follow-ups (out of scope)
- SwiftPM warning for `Helper/Info.plist` resource handling.
- Swift 6 async iterator warning in `GitRepoCleaner.swift`.
