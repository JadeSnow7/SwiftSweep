# UI Consistency & Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a shared design token layer and convert all 15 primary views to use macOS-native `.navigationTitle()` + `.toolbar {}` pattern, eliminating the layout bug caused by `.listStyle(.sidebar)` safe-area propagation and unifying spacing, color, and card styles across the app.

**Architecture:** A two-file design system (`DesignTokens.swift`, `ViewStyles.swift`) lives in a new `DesignSystem/` folder under `SwiftSweepUI`. Every view drops its manual header block and adopts `.navigationTitle()` so the `NavigationSplitView` detail column owns the window chrome correctly. Action buttons move to native `.toolbar {}` items; content-area layouts keep only scrollable/interactive content.

**Tech Stack:** SwiftUI (macOS 12+), no new dependencies.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Sources/SwiftSweepUI/DesignSystem/DesignTokens.swift` | Spacing, Color, Radius constants |
| Create | `Sources/SwiftSweepUI/DesignSystem/ViewStyles.swift` | `cardStyle()` ViewModifier |
| Modify | `Sources/SwiftSweepUI/StatusView.swift` | navigationTitle + toolbar |
| Modify | `Sources/SwiftSweepUI/CleanView.swift` | navigationTitle |
| Modify | `Sources/SwiftSweepUI/UninstallView.swift` | navigationTitle + toolbar |
| Modify | `Sources/SwiftSweepUI/InsightsView.swift` | navigationTitle + toolbar (replace headerView) |
| Modify | `Sources/SwiftSweepUI/OptimizeView.swift` | navigationTitle + cardStyle() |
| Modify | `Sources/SwiftSweepUI/SettingsView.swift` | navigationTitle |
| Modify | `Sources/SwiftSweepUI/Workspace/FileManagerView.swift` | navigationTitle + toolbar, remove FileManagerToolbar |
| Delete | `Sources/SwiftSweepUI/Workspace/FileManagerToolbar.swift` | Replaced by inline toolbar |

---

## Task 1: Create DesignTokens.swift

**Files:**
- Create: `Sources/SwiftSweepUI/DesignSystem/DesignTokens.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

// MARK: - Spacing

enum Spacing {
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 12
  static let lg: CGFloat = 16
  static let xl: CGFloat = 20
  static let xxl: CGFloat = 24
}

// MARK: - Corner Radius

enum Radius {
  static let sm: CGFloat = 8
  static let md: CGFloat = 10
  static let lg: CGFloat = 12
}

// MARK: - Color tokens

extension Color {
  /// Standard card / panel background (respects dark mode)
  static let cardBackground = Color(nsColor: .controlBackgroundColor)
  /// 12 % primary-color tint — selected / active state borders
  static let borderPrimary = Color.primary.opacity(0.12)
  /// 8 % gray tint — default card border
  static let borderSubtle = Color.gray.opacity(0.15)
  /// 5 % primary tint — hover / subtle fill
  static let subtleFill = Color.primary.opacity(0.05)
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/SwiftSweepUI/DesignSystem/DesignTokens.swift
git commit -m "feat(design): add DesignTokens (Spacing, Radius, Color)"
```

---

## Task 2: Create ViewStyles.swift

**Files:**
- Create: `Sources/SwiftSweepUI/DesignSystem/ViewStyles.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

// MARK: - Card style

struct CardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(Spacing.lg)
      .background(Color.cardBackground)
      .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
      .overlay(
        RoundedRectangle(cornerRadius: Radius.lg)
          .stroke(Color.borderSubtle, lineWidth: 1)
      )
  }
}

extension View {
  /// Applies the standard SwiftSweep card appearance.
  func cardStyle() -> some View {
    modifier(CardModifier())
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/SwiftSweepUI/DesignSystem/ViewStyles.swift
git commit -m "feat(design): add cardStyle() ViewModifier"
```

---

## Task 3: Fix FileManagerView — native toolbar

This is the root fix for the empty-space layout bug. The `FileManagerToolbar` component is removed; its path field stays in the content VStack, and all action buttons move to native `.toolbar {}`.

**Files:**
- Modify: `Sources/SwiftSweepUI/Workspace/FileManagerView.swift`
- Delete: `Sources/SwiftSweepUI/Workspace/FileManagerToolbar.swift`

- [ ] **Step 1: Replace `body` in FileManagerView.swift**

Open `Sources/SwiftSweepUI/Workspace/FileManagerView.swift`.

Replace the entire `body` computed property and add `pathInput` state:

```swift
@State private var pathInput: String = ""

public var body: some View {
  VStack(spacing: 0) {
    // Path bar — stays in content so layout is unambiguous
    HStack {
      TextField("Path", text: $pathInput)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          let url = URL(fileURLWithPath: pathInput)
          mode = .browser
          store.dispatch(.workspaceFileManager(.openLocation(url, pane: state.activePane)))
        }
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.sm)
    .onAppear { pathInput = activeTab?.locationURL?.path ?? "" }
    .onChange(of: activeTab?.locationURL?.path) { newPath in
      pathInput = newPath ?? ""
    }

    Divider()

    Picker("", selection: $mode) {
      ForEach(Mode.allCases, id: \.self) { m in
        Text(m.rawValue).tag(m)
      }
    }
    .pickerStyle(.segmented)
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.sm)

    if case .error(let message) = state.phase {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text(message)
          .font(.caption)
          .lineLimit(1)
        Spacer()
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.sm)
      Divider()
    }

    if mode == .spaceAnalysis {
      AnalyzeView()
    } else {
      HSplitView {
        FileManagerSidebar(
          favorites: state.favorites,
          recentLocations: state.recentLocations,
          mountedVolumes: state.mountedVolumes,
          onOpen: { url in
            store.dispatch(.workspaceFileManager(.openLocation(url, pane: state.activePane)))
          }
        )
        .frame(minWidth: 180, maxWidth: 260)

        paneColumn(.left)
          .frame(minWidth: 320)

        if state.isDualPane {
          paneColumn(.right)
            .frame(minWidth: 320)
        }

        if let previewURL = state.previewURL {
          WorkspaceQuickLookPreview(url: previewURL)
            .frame(minWidth: 220, maxWidth: 360)
        }
      }
    }
  }
  .navigationTitle("File Manager")
  .toolbar {
    ToolbarItemGroup(placement: .primaryAction) {
      Button {
        if mode == .browser, let location = activeTab?.locationURL {
          store.dispatch(.workspaceFileManager(.openLocation(location, pane: state.activePane)))
        }
        store.dispatch(.workspaceFileManager(.refreshVolumes))
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }

      Button {
        mode = .browser
        store.dispatch(.workspaceFileManager(.toggleDualPane))
      } label: {
        Label(state.isDualPane ? "Single Pane" : "Dual Pane", systemImage: "rectangle.split.2x1")
      }

      Button {
        mode = .browser
        store.dispatch(.workspaceFileManager(.createTab(pane: state.activePane, location: nil)))
      } label: {
        Label("New Tab", systemImage: "plus.rectangle.on.rectangle")
      }

      Divider()

      Button { performTransfer(type: .copy) } label: {
        Label("Copy", systemImage: "doc.on.doc")
      }

      Button { performTransfer(type: .move) } label: {
        Label("Move", systemImage: "arrow.right.doc.on.clipboard")
      }

      Button { performRename() } label: {
        Label("Rename", systemImage: "pencil")
      }

      Button(role: .destructive) { performTrash() } label: {
        Label("Trash", systemImage: "trash")
      }
    }

    ToolbarItem(placement: .automatic) {
      Button {
        store.dispatch(.workspaceFileManager(.showQueueSheet(true)))
      } label: {
        Label("Queue", systemImage: "list.bullet.rectangle")
      }
    }
  }
  .onAppear {
    store.dispatch(.workspaceFileManager(.boot))
  }
  .sheet(
    isPresented: Binding(
      get: { state.showQueueSheet },
      set: { store.dispatch(.workspaceFileManager(.showQueueSheet($0))) }
    )
  ) {
    FileOperationQueueSheet(
      items: state.queueItems,
      onPause: { id in store.dispatch(.workspaceFileManager(.pauseOperation(id))) },
      onResume: { id in store.dispatch(.workspaceFileManager(.resumeOperation(id))) },
      onCancel: { id in store.dispatch(.workspaceFileManager(.cancelOperation(id))) }
    )
  }
}
```

- [ ] **Step 2: Delete FileManagerToolbar.swift**

```bash
rm Sources/SwiftSweepUI/Workspace/FileManagerToolbar.swift
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/huaodong/Documents/SwiftSweep
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftSweepUI/Workspace/FileManagerView.swift
git rm Sources/SwiftSweepUI/Workspace/FileManagerToolbar.swift
git commit -m "fix(filemanager): use native toolbar — eliminates safe-area layout gap"
```

---

## Task 4: StatusView — navigationTitle + toolbar

**Files:**
- Modify: `Sources/SwiftSweepUI/StatusView.swift`

- [ ] **Step 1: Remove the manual header block**

In `StatusView.body`, delete lines 38–67 (the `HStack { VStack ... Button ... Button }` header block including `.padding(.bottom)`). The `ScrollView { VStack(alignment: .leading, spacing: 20) {` stays; its first child becomes the `LazyVGrid` metrics cards.

- [ ] **Step 2: Add navigationTitle + toolbar after the closing brace of `ScrollView`**

```swift
.navigationTitle("System Status")
.toolbar {
  ToolbarItemGroup(placement: .primaryAction) {
    Button(action: { showDiagnosticsSheet = true }) {
      Label(L10n.Status.appleDiagnostics.localized, systemImage: "stethoscope")
    }

    Button(action: { store.dispatch(.status(.startMonitoring)) }) {
      Label(L10n.Common.refresh.localized, systemImage: "arrow.clockwise")
    }
    .disabled(store.state.status.phase == .monitoring)
    .help(L10n.Common.refresh.localized)
  }
}
```

- [ ] **Step 3: Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftSweepUI/StatusView.swift
git commit -m "feat(status): use navigationTitle and native toolbar"
```

---

## Task 5: CleanView — navigationTitle

**Files:**
- Modify: `Sources/SwiftSweepUI/CleanView.swift`

- [ ] **Step 1: Remove manual header lines**

Delete the two lines in `body`:
```swift
Text("System Cleanup")
  .font(.largeTitle)
  .fontWeight(.bold)

Text("Remove junk files, caches, and temporary data to free up disk space.")
  .foregroundColor(.secondary)
```

- [ ] **Step 2: Add navigationTitle on the ScrollView**

```swift
.navigationTitle("System Cleanup")
```

- [ ] **Step 3: Replace hardcoded corner radius and background in scanning/error cards**

Find all occurrences of:
```swift
.background(Color(nsColor: .controlBackgroundColor))
.cornerRadius(10)
```

Replace each with:
```swift
.cardStyle()
```

Note: Remove the `.padding()` that precedes `.background(...)` since `cardStyle()` adds `Spacing.lg` padding internally. Keep any `.padding(.top)` that adds spacing *between* cards.

- [ ] **Step 4: Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftSweepUI/CleanView.swift
git commit -m "feat(clean): use navigationTitle, apply cardStyle()"
```

---

## Task 6: UninstallView — navigationTitle + toolbar

**Files:**
- Modify: `Sources/SwiftSweepUI/UninstallView.swift`

- [ ] **Step 1: Remove the manual header HStack**

Delete lines 36–61 in `body` (the entire `// Header` block: `HStack { VStack ... Button(Image(arrow.clockwise)) ... }`).

- [ ] **Step 2: Add navigationTitle + toolbar**

Add after the outermost `VStack`'s last modifier (before `.searchable` if present, otherwise before `.onAppear`):

```swift
.navigationTitle("App Uninstaller")
.toolbar {
  ToolbarItemGroup(placement: .primaryAction) {
    if state.phase == .scanning {
      ProgressView()
        .scaleEffect(0.8)
    }

    Button(action: { store.dispatch(.uninstall(.startScan)) }) {
      Label("Refresh", systemImage: "arrow.clockwise")
    }
    .disabled(state.phase == .scanning)
  }
}
```

- [ ] **Step 3: Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftSweepUI/UninstallView.swift
git commit -m "feat(uninstall): use navigationTitle and native toolbar"
```

---

## Task 7: InsightsView — navigationTitle + toolbar (replace headerView)

**Files:**
- Modify: `Sources/SwiftSweepUI/InsightsView.swift`

- [ ] **Step 1: Remove `headerView` usage from body**

In `body`, delete the two lines:
```swift
headerView

Divider()
```

- [ ] **Step 2: Delete the `headerView` computed property**

Remove the entire `private var headerView: some View { ... }` block (lines 91–163 approximately).

- [ ] **Step 3: Add navigationTitle + toolbar**

Add on the outermost `VStack`:

```swift
.navigationTitle("Smart Insights")
.toolbar {
  ToolbarItemGroup(placement: .primaryAction) {
    // Category filter
    Picker("Category", selection: Binding(
      get: { store.state.insights.selectedCategory },
      set: { store.dispatch(.insights(.selectCategory($0))) }
    )) {
      Text("All").tag(nil as RuleCategory?)
      ForEach(RuleCategory.allCases, id: \.self) { category in
        Label(category.rawValue, systemImage: category.icon)
          .tag(category as RuleCategory?)
      }
    }
    .pickerStyle(.menu)
    .frame(width: 140)

    if hasCleanableRecommendations {
      Button(action: { showBatchCleanup = true }) {
        Label("Clean All", systemImage: "trash")
      }
      .buttonStyle(.borderedProminent)
      .tint(.orange)
      .disabled(store.state.insights.phase == .loading)
    }

    Button(action: { Task { await loadRecommendations(forceRefresh: false) } }) {
      Label("Refresh", systemImage: "arrow.clockwise")
    }
    .disabled(store.state.insights.phase == .loading)

    Button(action: { Task { await loadRecommendations(forceRefresh: true) } }) {
      Label("Force Refresh", systemImage: "arrow.clockwise.circle")
    }
    .disabled(store.state.insights.phase == .loading)
    .help("Bypass cache and rescan everything")
  }
}
```

- [ ] **Step 4: Move cache-age indicator to subtitle**

The cache-age indicator was in `headerView`. Add it as a subtitle in the content area — place it just above `recommendationsList` as a small HStack:

```swift
if store.state.insights.isCacheHit, let age = store.state.insights.cacheAge {
  HStack {
    Image(systemName: "clock")
      .font(.caption)
      .foregroundStyle(.orange)
    Text("Cached \(Int(age / 60))m ago")
      .font(.caption)
      .foregroundStyle(.orange)
    Spacer()
    if let total = totalPotentialSavings {
      Text("\(formatBytes(total)) potential savings")
        .font(.caption.bold())
        .foregroundStyle(.green)
    }
  }
  .padding(.horizontal, Spacing.lg)
  .padding(.top, Spacing.sm)
}
```

- [ ] **Step 5: Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftSweepUI/InsightsView.swift
git commit -m "feat(insights): replace headerView with navigationTitle + toolbar"
```

---

## Task 8: OptimizeView — navigationTitle + cardStyle()

**Files:**
- Modify: `Sources/SwiftSweepUI/OptimizeView.swift`

- [ ] **Step 1: Remove the manual header block**

In `OptimizeView.body`, delete the `// Header` HStack block (the one containing `Text("System Optimizer")` and the "Run All" button) and its `.padding()`.

- [ ] **Step 2: Add navigationTitle + toolbar**

```swift
.navigationTitle("System Optimizer")
.toolbar {
  ToolbarItem(placement: .primaryAction) {
    Button(action: { viewModel.runAll() }) {
      Label("Run All", systemImage: "bolt.fill")
    }
    .buttonStyle(.borderedProminent)
  }
}
```

- [ ] **Step 3: Apply cardStyle() to OptimizationCard**

In `OptimizationCard.body`, replace:
```swift
.padding()
.background(Color(nsColor: .controlBackgroundColor))
.cornerRadius(12)
```
with:
```swift
.cardStyle()
```

Note: Remove the inner `.padding()` call since `cardStyle()` supplies `Spacing.lg` padding.

- [ ] **Step 4: Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftSweepUI/OptimizeView.swift
git commit -m "feat(optimize): use navigationTitle, toolbar, cardStyle()"
```

---

## Task 9: SettingsView — navigationTitle

**Files:**
- Modify: `Sources/SwiftSweepUI/SettingsView.swift`

- [ ] **Step 1: Remove the manual header block**

Delete the `// Header` block:
```swift
VStack(alignment: .leading) {
  Text("Settings")
    .font(.largeTitle)
    .fontWeight(.bold)
  Text("Configure SwiftSweep preferences")
    .foregroundColor(.secondary)
}
.padding()
```

- [ ] **Step 2: Add navigationTitle**

Add on the `ScrollView`:
```swift
.navigationTitle("Settings")
```

- [ ] **Step 3: Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftSweepUI/SettingsView.swift
git commit -m "feat(settings): use navigationTitle"
```

---

## Task 10: Apply Spacing tokens to all modified views

Replace the most common hardcoded padding values across all files touched in Tasks 3–9. Do one view at a time.

**Files:** All views modified in Tasks 3–9.

For each file, apply these substitutions (use Search & Replace):

| Old | New |
|-----|-----|
| `.padding(4)` | `.padding(Spacing.xs)` |
| `.padding(8)` | `.padding(Spacing.sm)` |
| `.padding(12)` | `.padding(Spacing.md)` |
| `.padding(16)` | `.padding(Spacing.lg)` |
| `.padding(20)` | `.padding(Spacing.xl)` |
| `.padding(24)` | `.padding(Spacing.xxl)` |
| `.padding(.horizontal, 8)` | `.padding(.horizontal, Spacing.sm)` |
| `.padding(.horizontal, 10)` | `.padding(.horizontal, Spacing.md)` |
| `.padding(.horizontal, 16)` | `.padding(.horizontal, Spacing.lg)` |
| `.padding(.vertical, 4)` | `.padding(.vertical, Spacing.xs)` |
| `.padding(.vertical, 6)` | `.padding(.vertical, Spacing.sm)` |
| `.padding(.vertical, 8)` | `.padding(.vertical, Spacing.sm)` |
| `spacing: 20` (in VStack/LazyVGrid) | `spacing: Spacing.xl` |
| `spacing: 24` (in VStack) | `spacing: Spacing.xxl` |
| `spacing: 16` (in VStack/HStack) | `spacing: Spacing.lg` |

Also replace color tokens:
| Old | New |
|-----|-----|
| `Color(nsColor: .controlBackgroundColor)` | `Color.cardBackground` |
| `Color.gray.opacity(0.2)` | `Color.borderSubtle` |
| `Color.primary.opacity(0.05)` | `Color.subtleFill` |

- [ ] **Step 1: Apply substitutions to FileManagerView.swift**
- [ ] **Step 2: Apply substitutions to FileManagerPaneView.swift**
- [ ] **Step 3: Apply substitutions to FileManagerSidebar.swift**
- [ ] **Step 4: Apply substitutions to StatusView.swift**
- [ ] **Step 5: Apply substitutions to CleanView.swift**
- [ ] **Step 6: Apply substitutions to UninstallView.swift**
- [ ] **Step 7: Apply substitutions to InsightsView.swift**
- [ ] **Step 8: Apply substitutions to OptimizeView.swift**
- [ ] **Step 9: Apply substitutions to SettingsView.swift**

- [ ] **Step 10: Build to verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 11: Commit**

```bash
git add Sources/SwiftSweepUI/
git commit -m "refactor(ui): replace hardcoded spacing/color values with design tokens"
```

---

## Task 11: Final build + tag

- [ ] **Step 1: Full clean build**

```bash
cd /Users/huaodong/Documents/SwiftSweep
swift build 2>&1 | tail -5
```

Expected last line: `Build complete!`

- [ ] **Step 2: Verify File Manager layout**

Launch the app, navigate to File Manager. The toolbar (Refresh, Single/Dual Pane, New Tab, Copy, Move, Rename, Trash, Queue) should appear in the native macOS window toolbar. The path TextField should appear at the very top of the content area with no gap above it.

- [ ] **Step 3: Commit and summarise**

```bash
git add -A
git commit -m "chore: UI consistency pass complete — design tokens, native nav, cardStyle"
```

---

## Self-Review Checklist

- [x] DesignTokens.swift covers Spacing, Radius, Color — all values used in tasks reference these
- [x] ViewStyles.swift provides `cardStyle()` — used in CleanView, OptimizeView
- [x] FileManagerView root cause fixed: no `.listStyle(.sidebar)` propagating safe-area + native toolbar
- [x] All 6 primary views get `.navigationTitle()` — consistent window chrome
- [x] Toolbar pattern consistent: `ToolbarItemGroup(placement: .primaryAction)` for actions
- [x] No TBDs or placeholders
- [x] Type consistency: `Spacing.lg`, `Radius.lg`, `Color.cardBackground` used identically in both token file and view tasks
- [x] `cardStyle()` replaces `.padding() + .background(...) + .cornerRadius(12)` — padding removed from callers to avoid double-padding
