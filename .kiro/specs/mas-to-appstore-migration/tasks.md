# Implementation Plan

- [x] 1. Set up migration infrastructure and analysis tools
  - Create MAS content scanner utility to identify MAS-specific patterns
  - Implement file system analysis for MAS-related files and directories
  - Set up Git branch management utilities for safe branch operations
  - _Requirements: 2.1, 2.2, 2.3_

- [x] 1.1 Write property test for content identification completeness
  - **Property 2: Content Identification Completeness**
  - **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5**

- [x] 2. Implement MAS content identification system
  - [x] 2.1 Create source code scanner for MAS compilation flags and patterns
    - Scan for `#if SWIFTSWEEP_MAS` and similar conditional compilation blocks
    - Identify MAS-specific import statements and API usage
    - _Requirements: 2.1_

  - [x] 2.2 Implement build configuration parser
    - Parse Package.swift for MAS-specific targets and dependencies
    - Identify Xcode project MAS configurations
    - _Requirements: 2.2_

  - [x] 2.3 Create documentation content analyzer
    - Scan README.md, PROJECT_DESIGN.md for MAS references
    - Identify MAS-related screenshots and documentation assets
    - _Requirements: 2.4_

  - [x] 2.4 Implement project structure scanner
    - Identify SwiftSweepMAS directory and related files
    - Scan for MAS-specific resource files and configurations
    - _Requirements: 2.3_

- [x] 2.5 Write unit tests for MAS content scanners
  - Test source code scanner with known MAS patterns
  - Test build configuration parser with sample Package.swift files
  - Test documentation analyzer with sample markdown files
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [-] 3. Create appstore branch and preserve MAS functionality
  - [x] 3.1 Implement Git branch creation utilities
    - Create appstore branch from current main branch state
    - Ensure all current content is preserved in appstore branch
    - _Requirements: 3.1_

  - [-] 3.2 Verify MAS functionality preservation in appstore branch
    - Ensure all MAS-specific code remains functional
    - Verify MAS compilation flags are maintained
    - Test MAS UI limitations are preserved
    - _Requirements: 3.2, 3.3, 3.4_

- [ ]* 3.3 Write property test for migration preservation
  - **Property 3: Migration Preservation**
  - **Validates: Requirements 1.2, 1.5, 3.2, 3.3, 3.4**

- [ ] 4. Clean up main branch for Developer ID focus
  - [ ] 4.1 Remove MAS-specific files and directories
    - Delete SwiftSweepMAS directory and contents
    - Remove MAS-specific resource files
    - Clean up MAS-related configuration files
    - _Requirements: 4.1_

  - [ ] 4.2 Update Package.swift for Developer ID only
    - Remove MAS-specific build targets and configurations
    - Clean up MAS compilation flags
    - Update dependencies to remove MAS-specific packages
    - _Requirements: 4.2_

  - [ ] 4.3 Clean source code of MAS conditional compilation
    - Remove `#if SWIFTSWEEP_MAS` blocks and related code
    - Update imports to remove MAS-specific dependencies
    - Simplify code paths by removing MAS alternatives
    - _Requirements: 4.3_

  - [ ] 4.4 Update Xcode project configurations
    - Remove MAS-specific build schemes and targets
    - Clean up project settings and entitlements
    - _Requirements: 4.5_

- [ ]* 4.5 Write property test for main branch cleanliness
  - **Property 1: Main Branch Cleanliness**
  - **Validates: Requirements 1.1, 4.1, 4.2, 4.3, 4.4, 4.5**

- [ ]* 4.6 Write property test for build configuration separation
  - **Property 4: Build Configuration Separation**
  - **Validates: Requirements 1.3, 4.2, 5.2**

- [ ] 5. Update documentation and build scripts
  - [ ] 5.1 Update README.md for Developer ID focus
    - Remove MAS references and limitations
    - Focus content on Developer ID distribution
    - Update build instructions for simplified workflow
    - _Requirements: 5.1_

  - [ ] 5.2 Update PROJECT_DESIGN.md
    - Remove MAS architecture sections
    - Clarify branch separation strategy
    - Update roadmap to reflect Developer ID focus
    - _Requirements: 5.3_

  - [ ] 5.3 Update build scripts and CI/CD configurations
    - Remove MAS-specific build targets from scripts
    - Update GitHub Actions workflows for branch separation
    - Simplify packaging scripts for Developer ID only
    - _Requirements: 5.2, 5.5_

  - [ ] 5.4 Create development guides for both branches
    - Document workflow for main branch (Developer ID)
    - Document workflow for appstore branch (MAS)
    - Provide clear switching instructions between branches
    - _Requirements: 5.4_

- [ ]* 5.5 Write property test for documentation consistency
  - **Property 5: Documentation Consistency**
  - **Validates: Requirements 1.4, 3.5, 5.1, 5.3, 5.4, 5.5**

- [ ] 6. Validation and testing
  - [ ] 6.1 Verify main branch builds successfully
    - Test swift build command works without MAS dependencies
    - Verify SwiftSweepApp runs with full Developer ID functionality
    - Ensure CLI tools function correctly
    - _Requirements: 1.1_

  - [ ] 6.2 Verify appstore branch maintains MAS functionality
    - Test MAS build configurations work correctly
    - Verify sandbox restrictions are properly maintained
    - Ensure MAS-specific UI limitations function as expected
    - _Requirements: 3.2, 3.3, 3.4_

  - [ ] 6.3 Test branch switching workflow
    - Verify developers can switch between branches cleanly
    - Test that no conflicts arise from branch differences
    - Validate documentation accuracy for both branches
    - _Requirements: 5.4_

- [ ]* 6.4 Write integration tests for complete migration workflow
  - Test end-to-end migration process
  - Verify both branches function independently after migration
  - Test documentation accuracy and build success
  - _Requirements: 1.1, 3.1, 4.1_

- [ ] 7. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.