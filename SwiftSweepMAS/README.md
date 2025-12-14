# SwiftSweepMAS

Mac App Store version of SwiftSweep - Disk Space Analyzer for Finder.

## Project Setup

This project requires Xcode to build. Follow these steps:

### 1. Create Xcode Project

1. Open Xcode
2. Choose "Create a new Xcode project"
3. Select **macOS** → **App**
4. Product Name: `SwiftSweepMAS`
5. Bundle Identifier: `com.swiftsweep.mas`
6. Team: Your Apple Developer Team
7. Interface: SwiftUI
8. Language: Swift

### 2. Add Finder Sync Extension Target

1. File → New → Target
2. Select **macOS** → **Finder Sync Extension**
3. Product Name: `FinderSyncExtension`
4. Bundle Identifier: `com.swiftsweep.mas.findersync`

### 3. Configure App Groups

1. Select the main target → Signing & Capabilities
2. Add "App Groups" capability
3. Create group: `group.com.swiftsweep.mas`
4. Repeat for FinderSyncExtension target

### 4. Add Source Files

Add the following files to appropriate targets:

**SwiftSweepMAS Target:**
- `SwiftSweepMAS/*.swift`
- `Shared/**/*.swift`
- `Entitlements/SwiftSweepMAS.entitlements`

**FinderSyncExtension Target:**
- `FinderSyncExtension/*.swift`
- `Shared/**/*.swift`
- `Entitlements/FinderSyncExtension.entitlements`

### 5. Configure URL Scheme

1. Select main target → Info
2. Add URL Type:
   - Identifier: `com.swiftsweep.mas`
   - URL Schemes: `swiftsweepmas`

### 6. Build & Run

1. Select the SwiftSweepMAS scheme
2. Build and run

## App Store Review Notes

```
1. Finder Extension Purpose
SwiftSweep provides a Finder extension for disk space analysis. 
It displays folder sizes and largest files in user-selected directories.

2. Directory Registration
Extension menus appear only within directories explicitly 
authorized by the user in the host app.

3. URL Scheme
The `swiftsweepmas://` scheme is used only for internal navigation 
between Finder Extension and Host App. It does not execute privileged 
actions or access protected resources.

4. Functionality Scope
- Read-only analysis of user-authorized directories
- No file modification, deletion, or system optimization
- No network requests
- No background processes

5. Permissions Used
- User-selected file access (read-only)
- Notification (to display quick results)
- App Groups (to share settings with Finder Extension)

6. Troubleshooting Note
If the Finder menu doesn't appear, users can toggle the extension 
off/on in System Settings → Extensions → Finder Extensions.
```

## File Structure

```
SwiftSweepMAS/
├── SwiftSweepMAS/           # Host App
│   ├── SwiftSweepMASApp.swift
│   ├── ContentView.swift
│   ├── DirectoryAuthorizationView.swift
│   ├── ExtensionSetupGuideView.swift
│   ├── NotificationPermissionManager.swift
│   ├── AnalysisResultView.swift
│   └── PrivacyInfo.xcprivacy
│
├── FinderSyncExtension/     # Finder Sync Extension
│   ├── FinderSync.swift
│   ├── AnalyzeMenuHandler.swift
│   └── ResultPresenter.swift
│
├── Shared/                  # Shared between targets
│   ├── AnalyzerEngineSubset/
│   │   ├── README.md
│   │   ├── FileNode.swift
│   │   ├── AnalyzerEngine.swift
│   │   └── SizeFormatter.swift
│   ├── BookmarkManager.swift
│   └── DirectorySyncConstants.swift
│
└── Entitlements/
    ├── SwiftSweepMAS.entitlements
    └── FinderSyncExtension.entitlements
```
