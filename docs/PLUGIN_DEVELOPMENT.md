# SwiftSweep Plugin Development Guide

This guide explains how to create data pack plugins for SwiftSweep.

## Overview

SwiftSweep plugins are **data packs** that contain rules, templates, and metadata—not executable code. This design ensures security and compatibility with macOS Hardened Runtime.

## Plugin Structure

```
my-plugin.zip
├── manifest.json       # Plugin metadata
├── rules/              # Cleanup rules
│   ├── cache.json
│   └── logs.json
└── assets/             # Optional icons/images
    └── icon.png
```

## Manifest Format

```json
{
  "id": "com.example.myplugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "description": "Cleans up MyApp cache and logs",
  "author": "Your Name",
  "minAppVersion": "0.3.0",
  "rules": ["rules/cache.json", "rules/logs.json"]
}
```

## Rule Format

Each rule file defines cleanup targets:

```json
{
  "id": "myapp-cache",
  "name": "MyApp Cache",
  "description": "Temporary cache files",
  "category": "Cache",
  "paths": [
    "~/Library/Caches/com.example.myapp",
    "~/Library/Application Support/MyApp/cache"
  ],
  "patterns": ["*.tmp", "*.cache"],
  "excludePatterns": ["*.important"],
  "safeToDelete": true
}
```

### Rule Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique rule identifier |
| `name` | string | Display name |
| `description` | string | What this rule cleans |
| `category` | string | Cache, Logs, Temp, etc. |
| `paths` | string[] | Directories to scan |
| `patterns` | string[] | File patterns to match |
| `excludePatterns` | string[] | Patterns to skip |
| `safeToDelete` | boolean | Auto-deletable without confirmation |

## Publishing

1. Create your plugin zip file
2. Calculate SHA256 checksum: `shasum -a 256 my-plugin.zip`
3. Host on GitHub Releases or similar
4. Submit PR to add your plugin to `plugins.json`

### plugins.json Entry

```json
{
  "id": "com.example.myplugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "description": "Cleans up MyApp cache and logs",
  "author": "Your Name",
  "min_app_version": "0.3.0",
  "download_url": "https://github.com/.../releases/download/v1.0.0/my-plugin.zip",
  "checksum": "sha256:abc123...",
  "category": "Utilities",
  "icon_url": null
}
```

## Best Practices

1. **Test thoroughly** - Verify all paths exist and patterns are correct
2. **Be conservative** - Mark `safeToDelete: false` for anything uncertain
3. **Document clearly** - Explain what each rule removes
4. **Version semantically** - Follow semver for updates

## Example: Xcode Cleaner Plugin

```json
{
  "id": "xcode-derived-data",
  "name": "Xcode Derived Data",
  "description": "Build artifacts and indexes",
  "category": "Developer",
  "paths": [
    "~/Library/Developer/Xcode/DerivedData"
  ],
  "patterns": ["*"],
  "excludePatterns": [],
  "safeToDelete": true
}
```

## Questions?

Open an issue on [GitHub](https://github.com/JadeSnow7/SwiftSweep/issues).
