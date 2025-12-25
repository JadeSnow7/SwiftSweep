# Requirements Document

## Introduction

This feature involves removing Mac App Store (MAS) related content from the main branch and keeping a dedicated appstore branch as a backup. The main branch will focus exclusively on Developer ID distribution, while MAS-specific functionality is preserved in the appstore branch and updated only through periodic, one-way syncs from main.

## Glossary

- **MAS**: Mac App Store - Apple's official app distribution platform with sandbox restrictions
- **Developer ID**: Apple's code signing certificate for direct distribution outside the App Store
- **SwiftSweep**: The macOS system cleaning and optimization tool
- **Main Branch**: The primary development branch focusing on Developer ID distribution
- **Appstore Branch**: A dedicated backup branch containing MAS-specific configurations and restrictions, updated periodically with selected changes from main
- **Sandbox**: Apple's security model that restricts app capabilities in the App Store
- **Build Target**: A specific configuration for building the application with different capabilities

## Requirements

### Requirement 1

**User Story:** As a developer, I want the main branch to focus only on Developer ID distribution while keeping MAS content in a backup branch, so that active development stays clean and MAS can be restored if needed.

#### Acceptance Criteria

1. WHEN the main branch is accessed THEN the system SHALL contain only Developer ID related configurations and code
2. WHEN MAS-specific files are identified THEN the system SHALL remove them from main and preserve them in the appstore branch
3. WHEN build scripts are updated THEN the system SHALL remove MAS compilation flags from main branch
4. WHEN documentation is updated THEN the system SHALL reflect the Developer ID focus in main and the backup role of the appstore branch
5. WHEN syncing changes THEN the system SHALL apply a one-way sync from main to appstore for shared updates

### Requirement 2

**User Story:** As a developer, I want to identify all MAS-related files and configurations, so that I can ensure complete migration without missing any components.

#### Acceptance Criteria

1. WHEN scanning the codebase THEN the system SHALL identify all files containing MAS-specific code or configurations
2. WHEN examining build configurations THEN the system SHALL locate all MAS compilation flags and settings
3. WHEN reviewing project structure THEN the system SHALL find MAS-specific directories and resources
4. WHEN analyzing documentation THEN the system SHALL identify MAS-related content and references
5. WHEN checking dependencies THEN the system SHALL identify any MAS-specific package configurations

### Requirement 3

**User Story:** As a developer, I want to keep a MAS backup branch, so that MAS-specific functionality is preserved and can be revived later if needed.

#### Acceptance Criteria

1. WHEN establishing the appstore branch THEN the system SHALL ensure it contains all MAS-specific configurations and code from before main cleanup
2. WHEN preserving MAS content THEN the system SHALL keep MAS compilation flags and sandbox restrictions intact in the appstore branch
3. WHEN syncing updates THEN the system SHALL apply selective, one-way updates from main to appstore for shared changes
4. WHEN configuring appstore branch THEN the system SHALL ensure MAS-specific UI limitations are preserved
5. WHEN documenting appstore branch THEN the system SHALL clearly indicate its backup-only purpose and sync expectations

### Requirement 4

**User Story:** As a developer, I want to clean up the main branch, so that it contains only Developer ID related functionality and configurations.

#### Acceptance Criteria

1. WHEN removing MAS content from main THEN the system SHALL delete all MAS-specific files and directories
2. WHEN updating build configurations THEN the system SHALL remove all MAS compilation flags from Package.swift
3. WHEN modifying source code THEN the system SHALL remove MAS conditional compilation blocks
4. WHEN updating documentation THEN the system SHALL remove MAS references and focus on Developer ID
5. WHEN cleaning project structure THEN the system SHALL remove MAS-specific Xcode project configurations
6. WHEN verifying main THEN the system SHALL run a deterministic check that no MAS markers remain (for example: `#if MAS`, `MAS_`, `appstore`, `App Store`, `sandbox` entitlements)
7. WHEN CI runs on main THEN the system SHALL fail if the MAS-free verification check reports matches

### Requirement 5

**User Story:** As a developer, I want to update documentation and build scripts, so that they accurately reflect the main-only Developer ID strategy and the backup nature of the appstore branch.

#### Acceptance Criteria

1. WHEN updating README THEN the system SHALL remove MAS references and focus on Developer ID distribution
2. WHEN modifying build scripts THEN the system SHALL remove MAS-specific build targets and configurations from main
3. WHEN updating project documentation THEN the system SHALL clarify the main-only strategy and the backup role of the appstore branch
4. WHEN revising development guides THEN the system SHALL document the one-way sync process from main to appstore
5. WHEN updating CI/CD configurations THEN the system SHALL reflect the primary main workflow and optional appstore backup updates
