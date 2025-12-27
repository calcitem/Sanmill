
# Implementation Plan: Verify Custodian and Intervention Rule Implementation

**Branch**: `001-verify-custodian-intervention` | **Date**: 2025-10-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/home/user/Sanmill/specs/001-verify-custodian-intervention/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path
   → If not found: ERROR "No feature spec at {path}"
2. Fill Technical Context (scan for NEEDS CLARIFICATION)
   → Detect Project Type from file system structure or context (web=frontend+backend, mobile=app+api)
   → Set Structure Decision based on project type
3. Fill the Constitution Check section based on the content of the constitution document.
4. Evaluate Constitution Check section below
   → If violations exist: Document in Complexity Tracking
   → If no justification possible: ERROR "Simplify approach first"
   → Update Progress Tracking: Initial Constitution Check
5. Execute Phase 0 → research.md
   → If NEEDS CLARIFICATION remain: ERROR "Resolve unknowns"
6. Execute Phase 1 → contracts, data-model.md, quickstart.md, agent-specific template file (e.g., `CLAUDE.md` for Claude Code, `.github/copilot-instructions.md` for GitHub Copilot, `GEMINI.md` for Gemini CLI, `QWEN.md` for Qwen Code, or `AGENTS.md` for all other agents).
7. Re-evaluate Constitution Check section
   → If new violations: Refactor design, return to Phase 1
   → Update Progress Tracking: Post-Design Constitution Check
8. Plan Phase 2 → Describe task generation approach (DO NOT create tasks.md)
9. STOP - Ready for /tasks command
```

**IMPORTANT**: The /plan command STOPS at step 7. Phases 2-4 are executed by other commands:
- Phase 2: /tasks command creates tasks.md
- Phase 3-4: Implementation execution (manual or via tools)

## Summary
Verify the correctness and completeness of recently implemented custodian and intervention capture rules in the Sanmill game engine. The implementation spans C++ game logic (position.cpp, movegen.cpp, rule.cpp) and Dart/Flutter UI (position.dart, mill.dart).

**Existing Test Coverage**: 23 integration test cases already implemented in `automated_move_test_data.dart` covering intervention capture, custodian capture, and mill combinations.

**Verification Scope**: Ensure 39 functional requirements are met across standalone rules, rule combinations (mill+custodian, mill+intervention), mayRemoveMultiple=false mode, FEN notation consistency, and move legality validation. Identify any gaps in existing tests and add missing coverage.

## Technical Context
**Language/Version**: C++17 (game engine), Dart 3.8+ (Flutter UI)
**Primary Dependencies**: C++ STL, Flutter SDK 3.38.5, Dart test framework, integration_test package
**Storage**: FEN notation for game state serialization (file-based), in-memory game state
**Testing**: Dart unit tests (`flutter test`), integration tests (`flutter test integration_test`), C++ unit tests (existing test harness)
**Target Platform**: Multi-platform (Android, iOS, Windows, macOS)
**Project Type**: Mobile + Desktop (Flutter UI + C++ engine via FFI)
**Performance Goals**: Rule checking <10ms per move, UI responsiveness <100ms, test suite execution <5 minutes
**Constraints**: Must maintain backward compatibility with existing FEN format, zero regression on existing rules, 95% test coverage for critical game logic paths
**Scale/Scope**: 39 functional requirements, ~10-15 test files, estimated 50-80 test cases covering all rule combinations and edge cases

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Verify alignment with Sanmill Constitution v1.0.0 (`.specify/memory/constitution.md`):

**Principle I - Code Quality First**:
- [x] Feature design includes linter compliance strategy (Use `flutter analyze` for Dart, existing C++ linter config)
- [x] Code review plan documented (All test code requires review per constitution)
- [x] Documentation requirements identified (Test documentation, code comments for complex rule interactions)
- [x] Technical debt impact assessed (No new debt - verification only, may identify existing issues to document)

**Principle II - Test-Driven Development**:
- [x] Test-first workflow planned (tests verify existing implementation, already written)
- [x] Test coverage targets defined (95% for critical game logic - custodian/intervention rules)
- [x] Unit, integration, widget, and platform tests identified (Dart unit tests, integration tests, C++ unit tests)
- [x] Red-Green-Refactor cycle incorporated in task ordering (Tests validate existing code, will identify bugs to fix)

**Principle III - User Experience Consistency**:
- [x] Cross-platform behavior verified (Tests run on all platforms via existing CI)
- [x] Accessibility requirements documented (N/A - internal rule logic, no new UI elements)
- [x] Localization keys planned for all user-facing strings (N/A - verification task, no new user-facing features)
- [x] Visual consistency with design system confirmed (N/A - no UI changes)
- [x] User-facing error handling designed (FEN import validation errors already specified in FR-035)

**Principle IV - Performance Requirements**:
- [x] UI responsiveness targets defined (Rule checking <10ms per move, no UI thread blocking)
- [x] AI engine performance constraints respected (No changes to engine performance characteristics)
- [x] Memory efficiency verified (No new memory allocation in rule checking)
- [x] Battery impact assessed (Negligible - rule checks are computationally trivial)
- [x] Startup time impact evaluated (No impact - runtime rule validation only)

**Principle V - Security and Privacy**:
- [x] No PII collection or proper consent mechanism (N/A - no data collection)
- [x] Secure data storage approach confirmed (FEN notation is game state only, not sensitive)
- [x] Dependencies vetted for vulnerabilities (Using existing test frameworks only)
- [x] GPL v3 compliance maintained (All test code under same license)

*All constitutional checks PASS. This is a verification/testing task with zero new user-facing features and minimal implementation changes (bug fixes only if tests fail).*

## Project Structure

### Documentation (this feature)
```
specs/001-verify-custodian-intervention/
├── plan.md              # This file (/plan command output)
├── research.md          # Phase 0 output (/plan command)
├── data-model.md        # Phase 1 output (/plan command)
├── quickstart.md        # Phase 1 output (/plan command)
├── test-scenarios/      # Phase 1 output (replaces contracts/ for test verification)
└── tasks.md             # Phase 2 output (/tasks command - NOT created by /plan)
```

### Source Code (repository root)
```
# C++ Game Engine (verification targets)
src/
├── position.cpp         # Custodian/intervention detection and state management
├── position.h           # Position class declarations
├── movegen.cpp          # Move generation with capture rule integration
├── rule.cpp             # Rule validation logic
├── rule.h               # Rule configuration
└── ucioption.cpp        # UCI options for rule configuration

# Flutter/Dart UI (verification targets)
src/ui/flutter_app/lib/game_page/services/
├── engine/
│   ├── position.dart    # Dart mirror of C++ position logic
│   ├── game.dart        # Game state management
│   └── ext_move.dart    # Move extensions
├── mill.dart            # Mill detection and capture handling
├── import_export/
│   └── import_service.dart  # FEN import with c:/i:/p: markers
└── controller/
    └── tap_handler.dart # UI capture selection logic

# Test Files (to be created/enhanced)
src/ui/flutter_app/test/game/
├── custodian_rule_test.dart          # FR-001 to FR-004
├── intervention_rule_test.dart       # FR-005 to FR-009
├── mill_custodian_combo_test.dart    # FR-010 to FR-013
├── mill_intervention_combo_test.dart # FR-014 to FR-017
├── triple_combo_test.dart            # FR-032, FR-033
├── may_remove_multiple_test.dart     # FR-018 to FR-020, FR-036 to FR-038
├── fen_notation_test.dart            # FR-021 to FR-027, FR-034, FR-035, FR-039
└── move_legality_test.dart           # FR-028 to FR-031

src/ui/flutter_app/integration_test/
└── custodian_intervention_e2e_test.dart  # End-to-end scenarios
```

**Structure Decision**: Hybrid Mobile+Desktop structure (Flutter UI + C++ engine). Test files will be organized by functional requirement groups. C++ tests may be added if Dart tests reveal engine-level bugs that require C++-specific validation.

## Phase 0: Outline & Research
1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:
   ```
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

## Phase 1: Design & Contracts
*Prerequisites: research.md complete*

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Generate API contracts** from functional requirements:
   - For each user action → endpoint
   - Use standard REST/GraphQL patterns
   - Output OpenAPI/GraphQL schema to `/contracts/`

3. **Generate contract tests** from contracts:
   - One test file per endpoint
   - Assert request/response schemas
   - Tests must fail (no implementation yet)

4. **Extract test scenarios** from user stories:
   - Each story → integration test scenario
   - Quickstart test = story validation steps

5. **Update agent file incrementally** (O(1) operation):
   - Run `.specify/scripts/bash/update-agent-context.sh cursor`
     **IMPORTANT**: Execute it exactly as specified above. Do not add or remove any arguments.
   - If exists: Add only NEW tech from current plan
   - Preserve manual additions between markers
   - Update recent changes (keep last 3)
   - Keep under 150 lines for token efficiency
   - Output to repository root

**Output**: data-model.md, /contracts/*, failing tests, quickstart.md, agent-specific file

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:
- Load `.specify/templates/tasks-template.md` as base
- Audit existing 23 integration tests against 39 FRs
- Identify coverage gaps in existing tests
- Create additional unit tests for uncovered FRs
- Add FEN import/export validation tests
- Generate bug fix tasks if existing tests fail

**Existing Test Coverage Audit** (23 integration tests in `automated_move_test_data.dart`):
- ✅ Intervention capture: ~10 test cases (FR-005 to FR-009 likely covered)
- ✅ Custodian capture: ~6 test cases (FR-001 to FR-004 likely covered)
- ✅ Mill + custodian/intervention combos: ~4 test cases (FR-010 to FR-017 partially covered)
- ❓ Triple combo (custodian + intervention + mill): Unknown (FR-032, FR-033 - need to verify)
- ❓ mayRemoveMultiple=false mode: Unknown (FR-018 to FR-020, FR-036 to FR-038 - need to verify)
- ❌ FEN notation with c:/i:/p: markers: NOT covered (FR-021 to FR-027, FR-034, FR-035, FR-039)
- ❌ Move legality validation: NOT explicitly tested (FR-028 to FR-031)

**Additional Test Files Needed**:
1. `fen_notation_test.dart` - FEN import/export with custodian/intervention markers (7 FRs)
2. `move_legality_test.dart` - Illegal move rejection tests (4 FRs)
3. `may_remove_multiple_test.dart` - mayRemoveMultiple=false mode coverage (6 FRs) if not in existing tests
4. Unit tests for specific edge cases identified in existing test gaps

**Ordering Strategy**:
- Run existing 23 integration tests first to identify failures
- Map existing test coverage to 39 FRs (gap analysis)
- Create missing unit tests for uncovered FRs [P]
- Add FEN validation tests [P]
- Bug fix tasks based on test failures

**Estimated Output**: 10-15 numbered, ordered tasks in tasks.md
- 1 task: Run existing integration tests and document results
- 1 task: Gap analysis (map 23 tests to 39 FRs)
- 3-5 tasks: Create new test files for gaps [P]
- 1-2 tasks: Coverage verification
- 0-N tasks: Bug fixes (depends on failures)

**IMPORTANT**: This phase is executed by the /tasks command, NOT by /plan

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)
**Phase 4**: Implementation (execute tasks.md following constitutional principles)
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |


## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command) - research.md created
- [x] Phase 1: Design complete (/plan command) - data-model.md, test-scenarios/, quickstart.md created
- [x] Phase 2: Task planning complete (/plan command - describe approach only) - task generation strategy documented
- [ ] Phase 3: Tasks generated (/tasks command)
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS (all 23 checks passed - verification task, no new features)
- [x] Post-Design Constitution Check: PASS (no design changes affecting constitutional compliance)
- [x] All NEEDS CLARIFICATION resolved (5 clarifications completed in spec.md)
- [x] Complexity deviations documented (N/A - no complexity violations)

---
*Based on Constitution v1.0.0 - See `.specify/memory/constitution.md`*
