<!--
Sync Impact Report:
Version: 0.0.0 → 1.0.0
Change Type: MAJOR (Initial constitution establishment)
Modified Principles: N/A (new document)
Added Sections:
  - Core Principles (5 principles)
  - Quality Standards
  - Development Workflow
  - Governance
Templates Requiring Updates:
  ✅ plan-template.md - reviewed, Constitution Check section aligns
  ✅ spec-template.md - reviewed, requirements alignment confirmed
  ✅ tasks-template.md - reviewed, task categorization matches principles
  ⚠ agent-file-template.md - pending first population with actual project data
Follow-up TODOs:
  - None (all placeholders resolved)
-->

# Sanmill Constitution

## Core Principles

### I. Code Quality First
All code contributions MUST meet the following non-negotiable standards:
- **Static Analysis Compliance**: Code MUST pass all linter checks without warnings. For C++, follow modern C++ best practices (C++17 or later). For Dart/Flutter, adhere to effective_dart guidelines.
- **Code Review Requirement**: Every change MUST be reviewed by at least one team member before merging. Self-merges are prohibited.
- **Documentation Mandate**: Public APIs, complex algorithms, and non-obvious design decisions MUST be documented inline. Architecture decisions MUST be recorded in relevant design documents.
- **Zero Technical Debt Policy**: New code MUST NOT introduce known technical debt. If technical debt is unavoidable, it MUST be documented with a clear remediation plan and tracked explicitly.

**Rationale**: The project serves users across multiple platforms (Android, iOS, Windows, macOS) with both casual and competitive players. Poor code quality directly impacts user experience, platform stability, and maintainability across this diverse ecosystem.

### II. Test-Driven Development (NON-NEGOTIABLE)
The following TDD discipline is strictly enforced:
- **Test-First Workflow**: For all new features and bug fixes, tests MUST be written before implementation code.
- **Red-Green-Refactor Cycle**: Tests MUST fail initially (red), then pass after minimal implementation (green), followed by refactoring for quality.
- **Test Coverage Gates**: All new code MUST achieve minimum 80% line coverage. Critical paths (game logic, AI engine, platform integration) MUST achieve 95% coverage.
- **Test Types Required**:
  - **Unit Tests**: For all business logic, algorithms, utilities
  - **Integration Tests**: For AI engine interactions, UI-to-engine communication, cross-platform features
  - **Widget Tests**: For all Flutter UI components
  - **Platform-Specific Tests**: For platform integration features (iOS, Android, Windows, macOS)

**Rationale**: Sanmill's AI engine is complex (MCTS, Perfect AI, search algorithms), and the multi-platform UI requires robust testing to prevent regressions. TDD ensures correctness from the outset and provides a safety net for continuous improvement.

### III. User Experience Consistency
User-facing features MUST maintain consistency across all platforms:
- **Cross-Platform Parity**: Core game features MUST behave identically on Android, iOS, Windows, and macOS. Platform-specific variations require explicit justification.
- **Accessibility Standards**: All UI components MUST support screen readers, keyboard navigation, and high-contrast modes. Touch targets MUST meet minimum size requirements (44x44 dp for mobile).
- **Localization Completeness**: All user-facing strings MUST be externalized and translatable. New features MUST include localization keys before release.
- **Visual Consistency**: UI components MUST follow the established design system. Deviations require design review and approval.
- **Error Handling**: All error states MUST provide clear, actionable messages to users. Never expose technical stack traces or jargon to end users.

**Rationale**: Sanmill is distributed through multiple app stores (Google Play, App Store, Microsoft Store, F-Droid) with users speaking different languages. Inconsistent UX fragments the user base and damages the app's reputation.

### IV. Performance Requirements
All features MUST meet or exceed the following performance standards:
- **UI Responsiveness**: Main thread MUST remain responsive. UI interactions MUST provide feedback within 100ms. Long operations (>200ms) MUST use async patterns with progress indicators.
- **AI Engine Performance**: Move generation MUST complete within configured time limits. Search algorithms MUST respect CPU/memory budgets defined in UCI options.
- **Memory Efficiency**: Mobile builds MUST operate within 150MB baseline memory usage. Desktop builds MUST NOT exceed 300MB for normal gameplay. Memory leaks are considered critical bugs.
- **Battery Efficiency**: On mobile, game sessions MUST NOT drain more than 5% battery per 30 minutes of active play under standard difficulty settings.
- **Startup Time**: Cold app launch MUST complete within 3 seconds on mid-range devices (4-year-old hardware baseline).
- **Animation Performance**: All animations MUST maintain 60 FPS on target platforms. Jank (dropped frames) is not acceptable in production.

**Rationale**: Performance directly impacts user retention. Poor performance on mobile devices leads to uninstalls. The AI engine's computational intensity demands careful resource management to maintain acceptable gameplay experience.

### V. Security and Privacy Standards
Given GPL v3 licensing and public distribution, security and privacy are paramount:
- **No PII Collection**: The application MUST NOT collect personally identifiable information without explicit, informed consent. Anonymous crash reports are permitted only with user opt-in.
- **Secure Data Handling**: Game state, user preferences, and statistics MUST be stored securely. No sensitive data in plain text logs.
- **Dependency Vetting**: All third-party dependencies MUST be reviewed for security vulnerabilities before adoption. Regular dependency audits are mandatory.
- **GPL Compliance**: All code MUST comply with GPL v3. Unofficial builds MUST be clearly labeled and use different application IDs.
- **Crash Reporting**: When enabled, crash reports MUST be anonymized. Users MUST be able to review report contents before submission.

**Rationale**: As free software distributed globally, Sanmill has a responsibility to protect user privacy and maintain license compliance. Security breaches or privacy violations would undermine user trust and violate free software principles.

## Quality Standards

### Code Style and Formatting
- **C++ Code**: Follow Google C++ Style Guide with project-specific adaptations documented in src/CODING_STYLE.md (if exists, otherwise establish baseline).
- **Dart/Flutter Code**: Adhere to official Dart style guide. Use `dart format` and `flutter analyze` as gates.
- **Automated Formatting**: All code MUST be formatted via automated tools before commit. CI MUST reject improperly formatted code.

### Build and CI Requirements
- **Build Success**: All commits to main branches MUST pass full CI build (all platforms).
- **No Warnings**: Compiler warnings and analyzer warnings MUST be treated as errors in CI.
- **Incremental Validation**: PRs MUST pass incremental checks (lint, test, build) before review.

### Documentation Standards
- **Code Documentation**: Complex algorithms (MCTS, Perfect AI, bitboard operations) MUST include explanatory comments and references to research papers or algorithms used.
- **API Documentation**: Public APIs in both C++ engine and Dart UI MUST have complete doc comments.
- **Change Documentation**: Non-trivial changes MUST update relevant documentation (README, CHANGELOG, in-code comments).

## Development Workflow

### Feature Development Process
1. **Specification**: Features MUST begin with a written specification (use `/specify` command).
2. **Planning**: Implementation plan MUST be created and reviewed (use `/plan` command).
3. **Task Breakdown**: Tasks MUST be generated with clear dependencies (use `/tasks` command).
4. **Implementation**: Follow TDD cycle with continuous integration.
5. **Review**: Code review with at least one approval required.
6. **Validation**: Manual testing on at least two platforms before merge.

### Branching Strategy
- **Main Branch**: `master` - stable, release-ready code only.
- **Feature Branches**: `[issue-number]-feature-name` format required.
- **Release Branches**: For coordinating multi-platform releases.
- **No Direct Commits**: All changes via pull requests, no exceptions.

### Testing Gates
- **Pre-Commit**: Local unit tests MUST pass.
- **Pre-PR**: Full test suite + linters MUST pass.
- **Pre-Merge**: Integration tests + platform builds MUST pass.
- **Pre-Release**: Manual QA on all target platforms MUST be completed.

### Code Review Standards
- **Scope**: Reviews MUST verify correctness, test coverage, performance impact, and UX consistency.
- **Responsiveness**: Reviewers MUST respond within 48 hours. Authors MUST address feedback within 72 hours.
- **Approval Criteria**: Code may only be merged when all feedback is addressed and at least one approval is granted.

## Governance

### Amendment Process
This constitution governs all development activities. Amendments require:
1. **Proposal**: Written proposal with rationale for change.
2. **Discussion**: Open discussion period (minimum 7 days for MAJOR changes, 3 days for MINOR).
3. **Approval**: Consensus among core maintainers.
4. **Documentation**: Version increment following semantic versioning.
5. **Migration Plan**: If amendment introduces new requirements, provide migration guidance.

### Compliance and Enforcement
- **All PRs/Reviews MUST Verify Compliance**: Reviewers must check adherence to constitutional principles.
- **Deviation Justification**: Deviations from principles MUST be explicitly justified in PR description and approved by lead maintainer.
- **Continuous Improvement**: Principles MUST be refined based on project evolution and community feedback.

### Version Control
- **Semantic Versioning**: Constitution versions follow MAJOR.MINOR.PATCH.
  - **MAJOR**: Backward-incompatible principle changes or removals.
  - **MINOR**: New principles or sections added, material expansions.
  - **PATCH**: Clarifications, wording improvements, non-semantic fixes.
- **Change Tracking**: All amendments MUST update the Sync Impact Report at the top of this document.

### Constitutional Review
- **Periodic Review**: Constitution MUST be reviewed quarterly to ensure alignment with project needs.
- **Metrics-Driven**: Review should consider: test coverage trends, code quality metrics, user feedback, incident post-mortems.
- **Community Input**: Community members may propose amendments via GitHub issues/discussions.

**Version**: 1.0.0 | **Ratified**: 2025-10-06 | **Last Amended**: 2025-10-06
